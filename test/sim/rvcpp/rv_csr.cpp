#include "rv_csr.h"
#include "encoding/rv_csr.h"

#include <cassert>
#include <cstdio>

// Inclusive msb:lsb style, like Verilog (and like the ISA manual)
#define BITS_UPTO(msb) (~((-1u << (msb)) << 1))
#define BITRANGE(msb, lsb) (BITS_UPTO((msb) - (lsb)) << (lsb))
#define GETBITS(x, msb, lsb) (((x) & BITRANGE(msb, lsb)) >> (lsb))
#define GETBIT(x, bit) (((x) >> (bit)) & 1u)


ux_t RVCSR::get_effective_xip() {
	return mip |
		(irq_s ? MIP_MSIP : 0) |
		(irq_t ? MIP_MTIP : 0) |
		(irq_e ? MIP_MEIP : 0);
}

void RVCSR::step() {
	uint64_t mcycle_64 = ((uint64_t)mcycleh << 32) | mcycle;
	uint64_t minstret_64 = ((uint64_t)minstreth << 32) | minstret;
	if (!(mcountinhibit & 0x1u)) {
		++mcycle_64;
	}
	if (!(mcountinhibit & 0x4u)) {
		++minstret_64;
	}
	if (!(pending_write_addr && *pending_write_addr == CSR_MCYCLEH)) {
		mcycleh = mcycle_64 >> 32;
	}
	if (!(pending_write_addr && *pending_write_addr == CSR_MCYCLE)) {
		mcycle = mcycle_64 & 0xffffffffu;
	}
	if (!(pending_write_addr && *pending_write_addr == CSR_MINSTRETH)) {
		minstreth = minstret_64 >> 32;
	}
	if (!(pending_write_addr && *pending_write_addr == CSR_MINSTRET)) {
		minstret = minstret_64 & 0xffffffffu;
	}
	if (pending_write_addr) {
		switch (*pending_write_addr) {
			case CSR_MSTATUS:        mstatus        = pending_write_data;               break;
			case CSR_MIE:            mie            = pending_write_data;               break;
			case CSR_MTVEC:          mtvec          = pending_write_data & 0xfffffffdu; break;
			case CSR_MSCRATCH:       mscratch       = pending_write_data;               break;
			case CSR_MEPC:           mepc           = pending_write_data & 0xfffffffeu; break;
			case CSR_MCAUSE:         mcause         = pending_write_data & 0x8000000fu; break;

			case CSR_MCYCLE:         mcycle         = pending_write_data;               break;
			case CSR_MCYCLEH:        mcycleh        = pending_write_data;               break;
			case CSR_MINSTRET:       minstret       = pending_write_data;               break;
			case CSR_MINSTRETH:      minstreth      = pending_write_data;               break;
			case CSR_MCOUNTINHIBIT:  mcountinhibit  = pending_write_data & 0x7u;        break;

			case CSR_HAZARD3_MSLEEP: hazard3_msleep = pending_write_data & 0x7u;        break;

			default:                                                                    break;
		}

		for (uint i = 0; i < IMPLEMENTED_PMP_REGIONS; ++i) {
			if (pmpcfg_l(i)) {
				continue;
			}
			if (*pending_write_addr == CSR_PMPADDR0 + i) {
				pmpaddr[i] = pending_write_data & 0x3fffffffu;
			} else if (*pending_write_addr == CSR_PMPCFG0 + i / 4) {
				uint field_lsb = 8 * (i % 4);
				pmpcfg[i / 4] = (pmpcfg[i / 4] & ~(0xffu << field_lsb))
					| (pending_write_data & (0x9fu << field_lsb));
			}
		}

		pending_write_addr = {};
	}
}


// Returns None on permission/decode fail
std::optional<ux_t> RVCSR::read(uint16_t addr, bool side_effect) {
	if (addr >= 1u << 12 || GETBITS(addr, 9, 8) > priv)
		return {};

	switch (addr) {
		case CSR_MISA:           return 0x40901105;  // RV32IMACX + U
		case CSR_MHARTID:        return 0;
		case CSR_MARCHID:        return 0x1b;        // Hazard3
		case CSR_MIMPID:         return 0x12345678u; // Match testbench value
		case CSR_MVENDORID:      return 0xdeadbeefu; // Match testbench value
		case CSR_MCONFIGPTR:     return 0x9abcdef0u; // Match testbench value

		case CSR_MSTATUS:        return mstatus;
		case CSR_MIE:            return mie;
		case CSR_MIP:            return get_effective_xip();
		case CSR_MTVEC:          return mtvec;
		case CSR_MSCRATCH:       return mscratch;
		case CSR_MEPC:           return mepc;
		case CSR_MCAUSE:         return mcause;
		case CSR_MTVAL:          return 0;

		case CSR_MCOUNTINHIBIT:  return mcountinhibit;
		case CSR_MCYCLE:         return mcycle;
		case CSR_MCYCLEH:        return mcycleh;
		case CSR_MINSTRET:       return minstret;
		case CSR_MINSTRETH:      return minstreth;

		case CSR_PMPCFG0:        return pmpcfg[0];
		case CSR_PMPCFG1:        return pmpcfg[1];
		case CSR_PMPCFG2:        return pmpcfg[2];
		case CSR_PMPCFG3:        return pmpcfg[3];

		case CSR_PMPADDR0:       return pmpaddr[0];
		case CSR_PMPADDR1:       return pmpaddr[1];
		case CSR_PMPADDR2:       return pmpaddr[2];
		case CSR_PMPADDR3:       return pmpaddr[3];
		case CSR_PMPADDR4:       return pmpaddr[4];
		case CSR_PMPADDR5:       return pmpaddr[5];
		case CSR_PMPADDR6:       return pmpaddr[6];
		case CSR_PMPADDR7:       return pmpaddr[7];
		case CSR_PMPADDR8:       return pmpaddr[8];
		case CSR_PMPADDR9:       return pmpaddr[9];
		case CSR_PMPADDR10:      return pmpaddr[10];
		case CSR_PMPADDR11:      return pmpaddr[11];
		case CSR_PMPADDR12:      return pmpaddr[12];
		case CSR_PMPADDR13:      return pmpaddr[13];
		case CSR_PMPADDR14:      return pmpaddr[14];
		case CSR_PMPADDR15:      return pmpaddr[15];

		case CSR_HAZARD3_MSLEEP: return hazard3_msleep;

		default:                 return {};
	}
}

// Returns false on permission/decode fail
bool RVCSR::write(uint16_t addr, ux_t data, uint op) {
	if (addr >= 1u << 12 || GETBITS(addr, 9, 8) > priv)
		return false;
	if (op == WRITE_CLEAR || op == WRITE_SET) {
		std::optional<ux_t> rdata = read(addr, false);
		if (!rdata)
			return false;
		if (op == WRITE_CLEAR)
			data = *rdata & ~data;
		else
			data = *rdata | data;
	}
	pending_write_addr = addr;
	pending_write_data = data;
	// Actual write is applied at end of step() -- ordering is important
	// e.g. for mcycle updates. However we validate address for
	// writability immediately.
	switch (addr) {
		case CSR_MISA:           break;
		case CSR_MHARTID:        break;
		case CSR_MARCHID:        break;
		case CSR_MIMPID:         break;

		case CSR_MSTATUS:        break;
		case CSR_MIE:            break;
		case CSR_MIP:            break;
		case CSR_MTVEC:          break;
		case CSR_MSCRATCH:       break;
		case CSR_MEPC:           break;
		case CSR_MCAUSE:         break;
		case CSR_MTVAL:          break;

		case CSR_MCYCLE:         break;
		case CSR_MCYCLEH:        break;
		case CSR_MINSTRET:       break;
		case CSR_MINSTRETH:      break;
		case CSR_MCOUNTINHIBIT:  break;

		case CSR_PMPCFG0:        break;
		case CSR_PMPCFG1:        break;
		case CSR_PMPCFG2:        break;
		case CSR_PMPCFG3:        break;

		case CSR_PMPADDR0:       break;
		case CSR_PMPADDR1:       break;
		case CSR_PMPADDR2:       break;
		case CSR_PMPADDR3:       break;
		case CSR_PMPADDR4:       break;
		case CSR_PMPADDR5:       break;
		case CSR_PMPADDR6:       break;
		case CSR_PMPADDR7:       break;
		case CSR_PMPADDR8:       break;
		case CSR_PMPADDR9:       break;
		case CSR_PMPADDR10:      break;
		case CSR_PMPADDR11:      break;
		case CSR_PMPADDR12:      break;
		case CSR_PMPADDR13:      break;
		case CSR_PMPADDR14:      break;
		case CSR_PMPADDR15:      break;

		case CSR_HAZARD3_MSLEEP: break;

		default:                 return false;
	}
	return true;
}

ux_t RVCSR::trap_enter_exception(uint xcause, ux_t xepc) {
	assert(xcause < 32);
	assert(!pending_write_addr);
	return trap_enter(xcause, xepc);
}

std::optional<ux_t> RVCSR::trap_check_enter_irq(ux_t xepc) {
	ux_t m_targeted_irqs = get_effective_xip() & mie;
	bool take_m_irq = m_targeted_irqs && ((mstatus & MSTATUS_MIE) || priv < PRV_M);
	if (take_m_irq) {
		ux_t cause = (1u << 31) | __builtin_ctz(m_targeted_irqs);
		return trap_enter(cause, xepc);
	} else {
		return std::nullopt;
	}
}

// Update trap state (including change of privilege level), return trap target PC
ux_t RVCSR::trap_enter(uint xcause, ux_t xepc) {
	mstatus = (mstatus & ~MSTATUS_MPP) | (priv << 11);
	priv = PRV_M;

	if (mstatus & MSTATUS_MIE)
		mstatus |= MSTATUS_MPIE;
	mstatus &= ~MSTATUS_MIE;

	mcause = xcause;
	mepc = xepc;
	if ((mtvec & 0x1) && (xcause & (1u << 31))) {
		return (mtvec & -2) + 4 * (xcause & ~(1u << 31));
	} else {
		return mtvec & -2;
	}
}

// Update trap state, return mepc:
ux_t RVCSR::trap_mret() {
	priv = GETBITS(mstatus, 12, 11);
	mstatus &= ~MSTATUS_MPP;
	if (priv != PRV_M)
		mstatus &= ~MSTATUS_MPRV;

	if (mstatus & MSTATUS_MPIE)
		mstatus |= MSTATUS_MIE;
	mstatus &= ~MSTATUS_MPIE;

	return mepc;
}

int RVCSR::get_pmp_match(ux_t addr) {
	for (int i = 0; i < PMP_REGIONS; ++i) {
		if (pmpcfg_a(i) == 0u) {
			continue;
		}
		ux_t mask = 0xffffffffu;
		if (pmpcfg_a(i) == 3) {
			if (pmpaddr[i] == 0xffffffffu) {
				mask = 0u;
			} else {
				mask = 0xfffffffeu << __builtin_ctz(~pmpaddr[i]);
			}
		}
		bool match = ((addr >> 2) & mask) == (pmpaddr[i] & mask);
		if (match) {
			// Lowest-numbered match determines success/failure:
			return i;
		}
	}
	return -1;
}

uint RVCSR::get_pmp_xwr(ux_t addr) {
	int region = get_pmp_match(addr);
	bool match = false;
	uint matching_xwr = 0;
	uint matching_l = 0;
	if (region >= 0) {
		match = true;
		matching_xwr = pmpcfg_xwr(region);
		matching_l = pmpcfg_l(region);
	}
	if (match) {
		// TODO MPRV
		if (get_true_priv() == PRV_M && !matching_l) {
			return 0x7u;
		} else {
			return matching_xwr;
		}
	} else {
		return get_true_priv() == PRV_M ? 0x7u : 0x0u;
	}
}
