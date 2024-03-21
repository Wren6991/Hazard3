#include "rv_core.h"
#include "encoding/rv_opcodes.h"
#include "encoding/rv_csr.h"

#include <cassert>

// Use unsigned arithmetic everywhere, with explicit sign extension as required.
static inline ux_t sext(ux_t bits, int sign_bit) {
	if (sign_bit >= XLEN - 1)
		return bits;
	else
		return (bits & (1u << sign_bit + 1) - 1) - ((bits & 1u << sign_bit) << 1);
}

// Inclusive msb:lsb style, like Verilog (and like the ISA manual)
#define BITS_UPTO(msb) (~((-1u << (msb)) << 1))
#define BITRANGE(msb, lsb) (BITS_UPTO((msb) - (lsb)) << (lsb))
#define GETBITS(x, msb, lsb) (((x) & BITRANGE(msb, lsb)) >> (lsb))
#define GETBIT(x, bit) (((x) >> (bit)) & 1u)

static inline ux_t imm_i(uint32_t instr) {
	return (instr >> 20) - (instr >> 19 & 0x1000);
}

static inline ux_t imm_s(uint32_t instr) {
	return (instr >> 20 & 0xfe0u)
		+ (instr >> 7 & 0x1fu)
		- (instr >> 19 & 0x1000u);
}

static inline ux_t imm_u(uint32_t instr) {
	return instr & 0xfffff000u;
}

static inline ux_t imm_b(uint32_t instr) {
	return (instr >> 7 & 0x1e)
		+ (instr >> 20 & 0x7e0)
		+ (instr << 4 & 0x800)
		- (instr >> 19 & 0x1000);
}

static inline ux_t imm_j(uint32_t instr) {
	return (instr >> 20 & 0x7fe)
		+ (instr >> 9 & 0x800)
		+ (instr & 0xff000)
		- (instr >> 11 & 0x100000);
}

static inline ux_t imm_ci(uint32_t instr) {
	return GETBITS(instr, 6, 2) - (GETBIT(instr, 12) << 5);
}

static inline ux_t imm_cj(uint32_t instr) {
	return -(GETBIT(instr, 12) << 11)
		+ (GETBIT(instr, 11) << 4)
		+ (GETBITS(instr, 10, 9) << 8)
		+ (GETBIT(instr, 8) << 10)
		+ (GETBIT(instr, 7) << 6)
		+ (GETBIT(instr, 6) << 7)
		+ (GETBITS(instr, 5, 3) << 1)
		+ (GETBIT(instr, 2) << 5);
}

static inline ux_t imm_cb(uint32_t instr) {
	return -(GETBIT(instr, 12) << 8)
		+ (GETBITS(instr, 11, 10) << 3)
		+ (GETBITS(instr, 6, 5) << 6)
		+ (GETBITS(instr, 4, 3) << 1)
		+ (GETBIT(instr, 2) << 5);
}

static inline uint c_rs1_s(uint32_t instr) {
	return GETBITS(instr, 9, 7) + 8;
}

static inline uint c_rs2_s(uint32_t instr) {
	return GETBITS(instr, 4, 2) + 8;
}

static inline uint c_rs1_l(uint32_t instr) {
	return GETBITS(instr, 11, 7);
}

static inline uint c_rs2_l(uint32_t instr) {
	return GETBITS(instr, 6, 2);
}

static inline uint zcmp_n_regs(uint32_t instr) {
	uint rlist = GETBITS(instr, 7, 4);
	return rlist == 0xf ? 13 : rlist - 3;
}

static inline uint zcmp_stack_adj(uint32_t instr) {
	uint nregs = zcmp_n_regs(instr);
	uint adj_base =
		nregs > 12 ? 0x40 :
		nregs >  8 ? 0x30 :
		nregs >  4 ? 0x20 : 0x10;
	return adj_base + 16 * GETBITS(instr, 3, 2);

}

static inline uint32_t zcmp_reg_mask(uint32_t instr) {
	uint32_t mask = 0;
	switch (zcmp_n_regs(instr)) {
		case 13: mask |= 1u << 27; // s11
		         mask |= 1u << 26; // s10
		case 11: mask |= 1u << 25; // s9
		case 10: mask |= 1u << 24; // s8
		case  9: mask |= 1u << 23; // s7
		case  8: mask |= 1u << 22; // s6
		case  7: mask |= 1u << 21; // s5
		case  6: mask |= 1u << 20; // s4
		case  5: mask |= 1u << 19; // s3
		case  4: mask |= 1u << 18; // s2
		case  3: mask |= 1u <<  9; // s1
		case  2: mask |= 1u <<  8; // s0
		case  1: mask |= 1u <<  1; // ra
	}
	return mask;
}

static inline uint zcmp_s_mapping(uint s_raw) {
	return s_raw + 8 + 8 * ((s_raw & 0x6) != 0);
}

void RVCore::step(bool trace) {

	std::optional<ux_t> rd_wdata;
	std::optional<ux_t> pc_wdata;
	std::optional<uint> exception_cause;
	uint regnum_rd = 0;

	std::optional<uint16_t> fetch0 = r16(pc);
	std::optional<uint16_t> fetch1 = r16(pc + 2);
	uint32_t instr = *fetch0 | ((uint32_t)*fetch1 << 16);

	uint opc = instr >> 2 & 0x1f;
	uint funct3 = instr >> 12 & 0x7;
	uint funct7 = instr >> 25 & 0x7f;

	if (!fetch0 || ((*fetch0 & 0x3) == 0x3 && !fetch1)) {
		exception_cause = XCAUSE_INSTR_FAULT;
	} else if ((instr & 0x3) == 0x3) {
		// 32-bit instruction
		uint regnum_rs1 = instr >> 15 & 0x1f;
		uint regnum_rs2 = instr >> 20 & 0x1f;
		regnum_rd       = instr >> 7 & 0x1f;
		ux_t rs1 = regs[regnum_rs1];
		ux_t rs2 = regs[regnum_rs2];
		switch (opc) {

		case OPC_OP: {
			if (funct7 == 0b00'00000) {
				if (funct3 == 0b000)
					rd_wdata = rs1 + rs2;
				else if (funct3 == 0b001)
					rd_wdata = rs1 << (rs2 & 0x1f);
				else if (funct3 == 0b010)
					rd_wdata = (sx_t)rs1 < (sx_t)rs2;
				else if (funct3 == 0b011)
					rd_wdata = rs1 < rs2;
				else if (funct3 == 0b100)
					rd_wdata = rs1 ^ rs2;
				else if (funct3 == 0b101)
					rd_wdata = rs1  >> (rs2 & 0x1f);
				else if (funct3 == 0b110)
					rd_wdata = rs1 | rs2;
				else if (funct3 == 0b111)
					rd_wdata = rs1 & rs2;
				else
					exception_cause = XCAUSE_INSTR_ILLEGAL;
			} else if (funct7 == 0b00'00001) {
				if (funct3 < 0b100) {
					sdx_t mul_op_a = rs1;
					sdx_t mul_op_b = rs2;
					if (funct3 != 0b011)
						mul_op_a -= (mul_op_a & (1 << XLEN - 1)) << 1;
					if (funct3 < 0b010)
						mul_op_b -= (mul_op_b & (1 << XLEN - 1)) << 1;
					sdx_t mul_result = mul_op_a * mul_op_b;
					if (funct3 == 0b000)
						rd_wdata = mul_result;
					else
						rd_wdata = mul_result >> XLEN;
				}
				else {
					if (funct3 == 0b100) {
						if (rs2 == 0)
							rd_wdata = -1;
						else if (rs2 == ~0u)
							rd_wdata = -rs1;
						else
							rd_wdata = (sx_t)rs1 / (sx_t)rs2;
					}
					else if (funct3 == 0b101) {
						rd_wdata = rs2 ? rs1 / rs2 : ~0ul;
					}
					else if (funct3 == 0b110) {
						if (rs2 == 0)
							rd_wdata = rs1;
						else if (rs2 == ~0u) // potential overflow of division
							rd_wdata = 0;
						else
							rd_wdata = (sx_t)rs1 % (sx_t)rs2;
					}
					else if (funct3 == 0b111) {
						rd_wdata = rs2 ? rs1 % rs2 : rs1;
					}
				}
			} else if (funct7 == 0b01'00000) {
				if (funct3 == 0b000)
					rd_wdata = rs1 - rs2;
				else if (funct3 == 0b100)
					rd_wdata = rs1 ^ ~rs2; // Zbb xnor
				else if (funct3 == 0b101)
					rd_wdata = (sx_t)rs1 >> (rs2 & 0x1f);
				else if (funct3 == 0b110)
					rd_wdata = rs1 | ~rs2; // Zbb orn
				else if (funct3 == 0b111)
					rd_wdata = rs1 & ~rs2; // Zbb andn
				else
					exception_cause = XCAUSE_INSTR_ILLEGAL;
			} else if (RVOPC_MATCH(instr, BCLR)) {
				rd_wdata = rs1 & ~(1u << (rs2 & 0x1f));
			} else if (RVOPC_MATCH(instr, BEXT)) {
				rd_wdata = (rs1 >> (rs2 & 0x1f)) & 0x1u;
			} else if (RVOPC_MATCH(instr, BINV)) {
				rd_wdata = rs1 ^ (1u << (rs2 & 0x1f));
			} else if (RVOPC_MATCH(instr, BSET)) {
				rd_wdata = rs1 | (1u << (rs2 & 0x1f));
			} else if (RVOPC_MATCH(instr, SH1ADD)) {
				rd_wdata = (rs1 << 1) + rs2;
			} else if (RVOPC_MATCH(instr, SH2ADD)) {
				rd_wdata = (rs1 << 2) + rs2;
			} else if (RVOPC_MATCH(instr, SH3ADD)) {
				rd_wdata = (rs1 << 3) + rs2;
			} else if (RVOPC_MATCH(instr, MAX)) {
				rd_wdata = (sx_t)rs1 > (sx_t)rs2 ? rs1 : rs2;
			} else if (RVOPC_MATCH(instr, MAXU)) {
				rd_wdata = rs1 > rs2 ? rs1 : rs2;
			} else if (RVOPC_MATCH(instr, MIN)) {
				rd_wdata = (sx_t)rs1 < (sx_t)rs2 ? rs1 : rs2;
			} else if (RVOPC_MATCH(instr, MINU)) {
				rd_wdata = rs1 < rs2 ? rs1 : rs2;
			} else if (RVOPC_MATCH(instr, ROR)) {
				uint shamt = rs2 & 0x1f;
				rd_wdata = shamt ? (rs1 >> shamt) | (rs1 << (32 - shamt)) : rs1;
			} else if (RVOPC_MATCH(instr, ROL)) {
				uint shamt = rs2 & 0x1f;
				rd_wdata = shamt ? (rs1 << shamt) | (rs1 >> (32 - shamt)) : rs1;
			} else if (RVOPC_MATCH(instr, PACK)) {
				rd_wdata = (rs1 & 0xffffu) | (rs2 << 16);
			} else if (RVOPC_MATCH(instr, PACKH)) {
				rd_wdata = (rs1 & 0xffu) | ((rs2 & 0xffu) << 8);
			} else if (RVOPC_MATCH(instr, CLMUL) || RVOPC_MATCH(instr, CLMULH) || RVOPC_MATCH(instr, CLMULR)) {
				uint64_t product = 0;
				for (int i = 0; i < 32; ++i) {
					if (rs2 & (1u << i)) {
						product ^= (uint64_t)rs1 << i;
					}
				}
				if (RVOPC_MATCH(instr, CLMUL)) {
					rd_wdata = product;
				} else if (RVOPC_MATCH(instr, CLMULH)) {
					rd_wdata = product >> 32;
				} else {
					rd_wdata = product >> 31;
				}
			} else {
				exception_cause = XCAUSE_INSTR_ILLEGAL;
			}
			break;
		}

		case OPC_OP_IMM: {
			ux_t imm = imm_i(instr);
			if (funct3 == 0b000)
				rd_wdata = rs1 + imm;
			else if (funct3 == 0b010)
				rd_wdata = !!((sx_t)rs1 < (sx_t)imm);
			else if (funct3 == 0b011)
				rd_wdata = !!(rs1 < imm);
			else if (funct3 == 0b100)
				rd_wdata = rs1 ^ imm;
			else if (funct3 == 0b110)
				rd_wdata = rs1 | imm;
			else if (funct3 == 0b111)
				rd_wdata = rs1 & imm;
			else if (funct3 == 0b001 || funct3 == 0b101) {
				// shamt is regnum_rs2
				if (funct7 == 0b00'00000 && funct3 == 0b001) {
					rd_wdata = rs1 << regnum_rs2;
				} else if (funct7 == 0b00'00000 && funct3 == 0b101) {
					rd_wdata = rs1 >> regnum_rs2;
				} else if (funct7 == 0b01'00000 && funct3 == 0b101) {
					rd_wdata = (sx_t)rs1 >> regnum_rs2;
				} else if (RVOPC_MATCH(instr, BCLRI)) {
					rd_wdata = rs1 & ~(1u << regnum_rs2);
				} else if (RVOPC_MATCH(instr, BINVI)) {
					rd_wdata = rs1 ^ (1u << regnum_rs2);
				} else if (RVOPC_MATCH(instr, BSETI)) {
					rd_wdata = rs1 | (1u << regnum_rs2);
				} else if (RVOPC_MATCH(instr, CLZ)) {
					rd_wdata = rs1 ? __builtin_clz(rs1) : 32;
				} else if (RVOPC_MATCH(instr, CPOP)) {
					rd_wdata = __builtin_popcount(rs1);
				} else if (RVOPC_MATCH(instr, CTZ)) {
					rd_wdata = rs1 ? __builtin_ctz(rs1) : 32;
				} else if (RVOPC_MATCH(instr, SEXT_B)) {
					rd_wdata = (rs1 & 0xffu) - ((rs1 & 0x80u) << 1);
				} else if (RVOPC_MATCH(instr, SEXT_H)) {
					rd_wdata = (rs1 & 0xffffu) - ((rs1 & 0x8000u) << 1);
				} else if (RVOPC_MATCH(instr, ZIP)) {
					ux_t accum = 0;
					for (int i = 0; i < 32; ++i) {
						if (rs1 & (1u << i)) {
							accum |= 1u << ((i >> 4) | ((i & 0xf) << 1));
						}
					}
					rd_wdata = accum;
				} else if (RVOPC_MATCH(instr, UNZIP)) {
					ux_t accum = 0;
					for (int i = 0; i < 32; ++i) {
						if (rs1 & (1u << i)) {
							accum |= 1u << ((i >> 1) | ((i & 1) << 4));
						}
					}
					rd_wdata = accum;
				} else if (RVOPC_MATCH(instr, BEXTI)) {
					rd_wdata = (rs1 >> regnum_rs2) & 0x1u;
				} else if (RVOPC_MATCH(instr, BREV8)) {
					rd_wdata =
						((rs1 & 0x80808080u) >> 7) | ((rs1 & 0x01010101u) << 7) |
						((rs1 & 0x40404040u) >> 5) | ((rs1 & 0x02020202u) << 5) |
						((rs1 & 0x20202020u) >> 3) | ((rs1 & 0x04040404u) << 3) |
						((rs1 & 0x10101010u) >> 1) | ((rs1 & 0x08080808u) << 1);
				} else if (RVOPC_MATCH(instr, ORC_B)) {
					rd_wdata =
						(rs1 & 0xff000000u ? 0xff000000u : 0u) |
						(rs1 & 0x00ff0000u ? 0x00ff0000u : 0u) |
						(rs1 & 0x0000ff00u ? 0x0000ff00u : 0u) |
						(rs1 & 0x000000ffu ? 0x000000ffu : 0u);
				} else if (RVOPC_MATCH(instr, REV8)) {
					rd_wdata = __builtin_bswap32(rs1);
				} else if (RVOPC_MATCH(instr, RORI)) {
					rd_wdata = regnum_rs2 ? ((rs1 << (32 - regnum_rs2)) | (rs1 >> regnum_rs2)) : rs1;
				} else {
					exception_cause = XCAUSE_INSTR_ILLEGAL;
				}
			}
			else {
				exception_cause = XCAUSE_INSTR_ILLEGAL;
			}
			break;
		}

		case OPC_BRANCH: {
			ux_t target = pc + imm_b(instr);
			bool taken = false;
			if ((funct3 & 0b110) == 0b000)
				taken = rs1 == rs2;
			else if ((funct3 & 0b110) == 0b100)
				taken = (sx_t)rs1 < (sx_t) rs2;
			else if ((funct3 & 0b110) == 0b110)
				taken = rs1 < rs2;
			else
				exception_cause = XCAUSE_INSTR_ILLEGAL;
			if (!exception_cause && funct3 & 0b001)
				taken = !taken;
			if (taken)
				pc_wdata = target;
			break;
		}

		case OPC_LOAD: {
			ux_t load_addr = rs1 + imm_i(instr);
			ux_t align_mask = ~(-1u << (funct3 & 0x3));
			bool misalign = load_addr & align_mask;
			if (funct3 == 0b011 || funct3 > 0b101) {
				exception_cause = XCAUSE_INSTR_ILLEGAL;
			} else if (misalign) {
				exception_cause = XCAUSE_LOAD_ALIGN;
			} else if (funct3 == 0b000) {
				rd_wdata = r8(load_addr);
				if (rd_wdata) {
					rd_wdata = sext(*rd_wdata, 7);
				} else {
					exception_cause = XCAUSE_LOAD_FAULT;
				}
			} else if (funct3 == 0b001) {
				rd_wdata = r16(load_addr);
				if (rd_wdata) {
					rd_wdata = sext(*rd_wdata, 15);
				} else {
					exception_cause = XCAUSE_LOAD_FAULT;
				}
			} else if (funct3 == 0b010) {
				rd_wdata = r32(load_addr);
				if (!rd_wdata) {
					exception_cause = XCAUSE_LOAD_FAULT;
				}
			} else if (funct3 == 0b100) {
				rd_wdata = r8(load_addr);
				if (!rd_wdata) {
					exception_cause = XCAUSE_LOAD_FAULT;
				}
			} else if (funct3 == 0b101) {
				rd_wdata = r16(load_addr);
				if (!rd_wdata) {
					exception_cause = XCAUSE_LOAD_FAULT;
				}
			}
			break;
		}

		case OPC_STORE: {
			ux_t store_addr = rs1 + imm_s(instr);
			ux_t align_mask = ~(-1u << (funct3 & 0x3));
			bool misalign = store_addr & align_mask;
			if (funct3 > 0b010) {
				exception_cause = XCAUSE_INSTR_ILLEGAL;
			} else if (misalign) {
				exception_cause = XCAUSE_STORE_ALIGN;
			} else {
				if (funct3 == 0b000) {
					if (!w8(store_addr, rs2 & 0xffu)) {
						exception_cause = XCAUSE_STORE_FAULT;
					}
				} else if (funct3 == 0b001) {
					if (!w16(store_addr, rs2 & 0xffffu)) {
						exception_cause = XCAUSE_STORE_FAULT;
					}
				} else if (funct3 == 0b010) {
					if (!w32(store_addr, rs2)) {
						exception_cause = XCAUSE_STORE_FAULT;
					}
				}
			}
			break;
		}

		case OPC_AMO: {
			if (RVOPC_MATCH(instr, LR_W)) {
				if (rs1 & 0x3) {
					exception_cause = XCAUSE_LOAD_ALIGN;
				} else {
					rd_wdata = r32(rs1);
					if (rd_wdata) {
						load_reserved = true;
					} else {
						exception_cause = XCAUSE_LOAD_FAULT;
					}
				}
			} else if (RVOPC_MATCH(instr, SC_W)) {
				if (rs1 & 0x3) {
					exception_cause = XCAUSE_STORE_ALIGN;
				} else {
					if (load_reserved) {
						load_reserved = false;
						if (w32(rs1, rs2)) {
							rd_wdata = 0;
						} else {
							exception_cause = XCAUSE_STORE_FAULT;
						}
					} else {
						rd_wdata = 1;
					}
				}
			} else if (
					RVOPC_MATCH(instr, AMOSWAP_W) ||
					RVOPC_MATCH(instr, AMOADD_W) ||
					RVOPC_MATCH(instr, AMOXOR_W) ||
					RVOPC_MATCH(instr, AMOAND_W) ||
					RVOPC_MATCH(instr, AMOOR_W) ||
					RVOPC_MATCH(instr, AMOMIN_W) ||
					RVOPC_MATCH(instr, AMOMAX_W) ||
					RVOPC_MATCH(instr, AMOMINU_W) ||
					RVOPC_MATCH(instr, AMOMAXU_W)) {
				if (rs1 & 0x3) {
					exception_cause = XCAUSE_STORE_ALIGN;
				} else {
					rd_wdata = r32(rs1);
					if (!rd_wdata) {
						exception_cause = XCAUSE_STORE_FAULT; // Yes, AMO/Store
					} else {
						bool write_success = false;
						switch (instr & RVOPC_AMOSWAP_W_MASK) {
							case RVOPC_AMOSWAP_W_BITS: write_success = w32(rs1, rs2);                                            break;
							case RVOPC_AMOADD_W_BITS:  write_success = w32(rs1, *rd_wdata + rs2);                                break;
							case RVOPC_AMOXOR_W_BITS:  write_success = w32(rs1, *rd_wdata ^ rs2);                                break;
							case RVOPC_AMOAND_W_BITS:  write_success = w32(rs1, *rd_wdata & rs2);                                break;
							case RVOPC_AMOOR_W_BITS:   write_success = w32(rs1, *rd_wdata | rs2);                                break;
							case RVOPC_AMOMIN_W_BITS:  write_success = w32(rs1, (sx_t)*rd_wdata < (sx_t)rs2 ? *rd_wdata : rs2);  break;
							case RVOPC_AMOMAX_W_BITS:  write_success = w32(rs1, (sx_t)*rd_wdata > (sx_t)rs2 ? *rd_wdata : rs2);  break;
							case RVOPC_AMOMINU_W_BITS: write_success = w32(rs1, *rd_wdata < rs2 ? *rd_wdata : rs2);              break;
							case RVOPC_AMOMAXU_W_BITS: write_success = w32(rs1, *rd_wdata > rs2 ? *rd_wdata : rs2);              break;
							default:                   assert(false);                                                break;
						}
						if (!write_success) {
							exception_cause = XCAUSE_STORE_FAULT;
							rd_wdata = {};
						}
					}
				}
			} else {
				exception_cause = XCAUSE_INSTR_ILLEGAL;
			}
			break;
		}

		case OPC_JAL:
			rd_wdata = pc + 4;
			pc_wdata = pc + imm_j(instr);
			break;

		case OPC_JALR:
			rd_wdata = pc + 4;
			pc_wdata = (rs1 + imm_i(instr)) & -2u;
			break;

		case OPC_LUI:
			rd_wdata = imm_u(instr);
			break;

		case OPC_AUIPC:
			rd_wdata = pc + imm_u(instr);
			break;

		case OPC_SYSTEM: {
			uint16_t csr_addr = instr >> 20;
			if (funct3 >= 0b001 && funct3 <= 0b011) {
				// csrrw, csrrs, csrrc
				uint write_op = funct3 - 0b001;
				if (write_op != RVCSR::WRITE || regnum_rd != 0) {
					rd_wdata = csr.read(csr_addr);
					if (!rd_wdata) {
						exception_cause = XCAUSE_INSTR_ILLEGAL;
					}
				}
				else if (write_op == RVCSR::WRITE || regnum_rs1 != 0) {
					if (!csr.write(csr_addr, rs1, write_op)) {
						exception_cause = XCAUSE_INSTR_ILLEGAL;
					}
				}
			}
			else if (funct3 >= 0b101 && funct3 <= 0b111) {
				// csrrwi, csrrsi, csrrci
				uint write_op = funct3 - 0b101;
				if (write_op != RVCSR::WRITE || regnum_rd != 0)
					rd_wdata = csr.read(csr_addr);
				if (write_op == RVCSR::WRITE || regnum_rs1 != 0)
					csr.write(csr_addr, regnum_rs1, write_op);
			} else if (RVOPC_MATCH(instr, MRET)) {
				if (csr.getpriv() == PRV_M) {
					pc_wdata = csr.trap_mret();
				} else {
					exception_cause = XCAUSE_INSTR_ILLEGAL;
				}
			} else if (RVOPC_MATCH(instr, ECALL)) {
				exception_cause = XCAUSE_ECALL_U + csr.getpriv();
			} else if (RVOPC_MATCH(instr, EBREAK)) {
				exception_cause = XCAUSE_EBREAK;
			} else {
				exception_cause = XCAUSE_INSTR_ILLEGAL;
			}
			break;
		}

	case OPC_CUSTOM0: {
		if (RVOPC_MATCH(instr, H3_BEXTM)) {
			uint size = GETBITS(instr, 28, 26) + 1;
			rd_wdata = (rs1 >> (rs2 & 0x1f)) & ~(-1u << size);
		} else if (RVOPC_MATCH(instr, H3_BEXTMI)) {
			uint size = GETBITS(instr, 28, 26) + 1;
			rd_wdata = (rs1 >> regnum_rs2) & ~(-1u << size);
		} else {
			exception_cause = XCAUSE_INSTR_ILLEGAL;
		}
		break;
	}

		default:
			exception_cause = XCAUSE_INSTR_ILLEGAL;
			break;
		}
	} else if ((instr & 0x3) == 0x0) {
		// RVC Quadrant 00:
		if (RVOPC_MATCH(instr, ILLEGAL16)) {
			exception_cause = XCAUSE_INSTR_ILLEGAL;
		} else if (RVOPC_MATCH(instr, C_ADDI4SPN)) {
			regnum_rd = c_rs2_s(instr);
			rd_wdata = regs[2]
				+ (GETBITS(instr, 12, 11) << 4)
				+ (GETBITS(instr, 10, 7) << 6)
				+ (GETBIT(instr, 6) << 2)
				+ (GETBIT(instr, 5) << 3);
		} else if (RVOPC_MATCH(instr, C_LW)) {
			regnum_rd = c_rs2_s(instr);
			uint32_t addr = regs[c_rs1_s(instr)]
				+ (GETBIT(instr, 6) << 2)
				+ (GETBITS(instr, 12, 10) << 3)
				+ (GETBIT(instr, 5) << 6);
			rd_wdata = r32(addr);
			if (!rd_wdata) {
				exception_cause = XCAUSE_LOAD_FAULT;
			}
		} else if (RVOPC_MATCH(instr, C_SW)) {
			uint32_t addr = regs[c_rs1_s(instr)]
				+ (GETBIT(instr, 6) << 2)
				+ (GETBITS(instr, 12, 10) << 3)
				+ (GETBIT(instr, 5) << 6);
			if (!w32(addr, regs[c_rs2_s(instr)])) {
				exception_cause = XCAUSE_STORE_FAULT;
			}
		} else {
			exception_cause = XCAUSE_INSTR_ILLEGAL;
		}
	} else if ((instr & 0x3) == 0x1) {
		// RVC Quadrant 01:
		if (RVOPC_MATCH(instr, C_ADDI)) {
			regnum_rd = c_rs1_l(instr);
			rd_wdata = regs[c_rs1_l(instr)] + imm_ci(instr);
		} else if (RVOPC_MATCH(instr, C_JAL)) {
			pc_wdata = pc + imm_cj(instr);
			regnum_rd = 1;
			rd_wdata = pc + 2;
		} else if (RVOPC_MATCH(instr, C_LI)) {
			regnum_rd = c_rs1_l(instr);
			rd_wdata = imm_ci(instr);
		} else if (RVOPC_MATCH(instr, C_LUI)) {
			regnum_rd = c_rs1_l(instr);
			// ADDI16SPN if rd is sp
			if (regnum_rd == 2) {
				rd_wdata = regs[2]
					- (GETBIT(instr, 12) << 9)
					+ (GETBIT(instr, 6) << 4)
					+ (GETBIT(instr, 5) << 6)
					+ (GETBITS(instr, 4, 3) << 7)
					+ (GETBIT(instr, 2) << 5);
			} else {
				rd_wdata = -(GETBIT(instr, 12) << 17)
				+ (GETBITS(instr, 6, 2) << 12);
			}
		} else if (RVOPC_MATCH(instr, C_SRLI)) {
			regnum_rd = c_rs1_s(instr);
			rd_wdata = regs[regnum_rd] >> GETBITS(instr, 6, 2);
		} else if (RVOPC_MATCH(instr, C_SRAI)) {
			regnum_rd = c_rs1_s(instr);
			rd_wdata = (sx_t)regs[regnum_rd] >> GETBITS(instr, 6, 2);
		} else if (RVOPC_MATCH(instr, C_ANDI)) {
			regnum_rd = c_rs1_s(instr);
			rd_wdata = regs[regnum_rd] & imm_ci(instr);
		} else if (RVOPC_MATCH(instr, C_SUB)) {
			regnum_rd = c_rs1_s(instr);
			rd_wdata = regs[c_rs1_s(instr)] - regs[c_rs2_s(instr)];
		} else if (RVOPC_MATCH(instr, C_XOR)) {
			regnum_rd = c_rs1_s(instr);
			rd_wdata = regs[c_rs1_s(instr)] ^ regs[c_rs2_s(instr)];
		} else if (RVOPC_MATCH(instr, C_OR)) {
			regnum_rd = c_rs1_s(instr);
			rd_wdata = regs[c_rs1_s(instr)] | regs[c_rs2_s(instr)];
		} else if (RVOPC_MATCH(instr, C_AND)) {
			regnum_rd = c_rs1_s(instr);
			rd_wdata = regs[c_rs1_s(instr)] & regs[c_rs2_s(instr)];
		} else if (RVOPC_MATCH(instr, C_J)) {
			pc_wdata = pc + imm_cj(instr);
		} else if (RVOPC_MATCH(instr, C_BEQZ)) {
			if (regs[c_rs1_s(instr)] == 0) {
				pc_wdata = pc + imm_cb(instr);
			}
		} else if (RVOPC_MATCH(instr, C_BNEZ)) {
			if (regs[c_rs1_s(instr)] != 0) {
				pc_wdata = pc + imm_cb(instr);
			}
		} else {
			exception_cause = XCAUSE_INSTR_ILLEGAL;
		}
	} else {
		// RVC Quadrant 10:
		if (RVOPC_MATCH(instr, C_SLLI)) {
			regnum_rd = c_rs1_l(instr);
			rd_wdata = regs[regnum_rd] << GETBITS(instr, 6, 2);
		} else if (RVOPC_MATCH(instr, C_MV)) {
			if (c_rs2_l(instr) == 0) {
				// c.jr
				pc_wdata = regs[c_rs1_l(instr)] & -2u;;
			} else {
				regnum_rd = c_rs1_l(instr);
				rd_wdata = regs[c_rs2_l(instr)];
			}
		} else if (RVOPC_MATCH(instr, C_ADD)) {
			if (c_rs2_l(instr) == 0) {
				if (c_rs1_l(instr) == 0) {
					// c.ebreak
					exception_cause = XCAUSE_EBREAK;
				} else {
					// c.jalr
					pc_wdata = regs[c_rs1_l(instr)] & -2u;
					regnum_rd = 1;
					rd_wdata = pc + 2;
				}
			} else {
				regnum_rd = c_rs1_l(instr);
				rd_wdata = regs[c_rs1_l(instr)] + regs[c_rs2_l(instr)];
			}
		} else if (RVOPC_MATCH(instr, C_LWSP)) {
			regnum_rd = c_rs1_l(instr);
			ux_t addr = regs[2]
				+ (GETBIT(instr, 12) << 5)
				+ (GETBITS(instr, 6, 4) << 2)
				+ (GETBITS(instr, 3, 2) << 6);
			rd_wdata = r32(addr);
			if (!rd_wdata) {
				exception_cause = XCAUSE_LOAD_FAULT;
			}
		} else if (RVOPC_MATCH(instr, C_SWSP)) {
			ux_t addr = regs[2]
				+ (GETBITS(instr, 12, 9) << 2)
				+ (GETBITS(instr, 8, 7) << 6);
			if (!w32(addr, regs[c_rs2_l(instr)])) {
				exception_cause = XCAUSE_STORE_FAULT;
			}
		// Zcmp:
		} else if (RVOPC_MATCH(instr, CM_PUSH)) {
			ux_t addr = regs[2];
			bool fail = false;
			for (uint i = 31; i > 0 && !fail; --i) {
				if (zcmp_reg_mask(instr) & (1u << i)) {
					addr -= 4;
					fail = fail || !w32(addr, regs[i]);
				}
			}
			if (fail) {
				exception_cause = XCAUSE_STORE_FAULT;
			} else {
				regnum_rd = 2;
				rd_wdata = regs[2] - zcmp_stack_adj(instr);
			}
		} else if (RVOPC_MATCH(instr, CM_POP) || RVOPC_MATCH(instr, CM_POPRET) || RVOPC_MATCH(instr, CM_POPRETZ)) {
			bool clear_a0 = RVOPC_MATCH(instr, CM_POPRETZ);
			bool ret = clear_a0 || RVOPC_MATCH(instr, CM_POPRET);
			ux_t addr = regs[2] + zcmp_stack_adj(instr);
			bool fail = false;
			for (uint i = 31; i > 0 && !fail; --i) {
				if (zcmp_reg_mask(instr) & (1u << i)) {
					addr -= 4;
					std::optional<ux_t> load_result = r32(addr);
					fail = fail || !load_result;
					if (load_result) {
						regs[i] = *load_result;
					}
				}
			}
			if (fail) {
				exception_cause = XCAUSE_LOAD_FAULT;
			} else {
				if (clear_a0)
					regs[10] = 0;
				if (ret)
					pc_wdata = regs[1];
				regnum_rd = 2;
				rd_wdata = regs[2] + zcmp_stack_adj(instr);
			}
		} else if (RVOPC_MATCH(instr, CM_MVSA01)) {
			regs[zcmp_s_mapping(GETBITS(instr, 9, 7))] = regs[10];
			regs[zcmp_s_mapping(GETBITS(instr, 4, 2))] = regs[11];
		} else if (RVOPC_MATCH(instr, CM_MVA01S)) {
			regs[10] = regs[zcmp_s_mapping(GETBITS(instr, 9, 7))];
			regs[11] = regs[zcmp_s_mapping(GETBITS(instr, 4, 2))];
		} else {
			exception_cause = XCAUSE_INSTR_ILLEGAL;
		}
	}


	if (trace) {
		printf("%08x: ", pc);
		if ((instr & 0x3) == 0x3) {
			printf("%08x : ", instr);
		} else {
			printf("    %04x : ", instr & 0xffffu);
		}
		if (regnum_rd != 0 && rd_wdata) {
			printf("%-3s <- %08x ", friendly_reg_names[regnum_rd], *rd_wdata);
		} else {
			printf("                ");
		}
		if (pc_wdata) {
			printf(": pc <- %08x\n", *pc_wdata);
		} else {
			printf(":\n");
		}
	}

	if (exception_cause) {
		pc_wdata = csr.trap_enter(*exception_cause, pc);
		if (trace) {
			printf("Trap cause %2u: pc <- %08x\n", *exception_cause, *pc_wdata);
		}
	}

	if (pc_wdata)
		pc = *pc_wdata;
	else
		pc = pc + ((instr & 0x3) == 0x3 ? 4 : 2);
	if (rd_wdata && regnum_rd != 0)
		regs[regnum_rd] = *rd_wdata;
	csr.step();
}
