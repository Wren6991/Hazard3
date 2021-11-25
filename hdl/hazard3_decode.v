/******************************************************************************
 *     DO WHAT THE FUCK YOU WANT TO AND DON'T BLAME US PUBLIC LICENSE         *
 *                        Version 3, April 2008                               *
 *                                                                            *
 *     Copyright (C) 2021 Luke Wren                                           *
 *                                                                            *
 *     Everyone is permitted to copy and distribute verbatim or modified      *
 *     copies of this license document and accompanying software, and         *
 *     changing either is allowed.                                            *
 *                                                                            *
 *       TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION      *
 *                                                                            *
 *     0. You just DO WHAT THE FUCK YOU WANT TO.                              *
 *     1. We're NOT RESPONSIBLE WHEN IT DOESN'T FUCKING WORK.                 *
 *                                                                            *
 *****************************************************************************/

`default_nettype none

module hazard3_decode #(
`include "hazard3_config.vh"
,
`include "hazard3_width_const.vh"
) (
	input wire clk,
	input wire rst_n,

	input wire  [31:0]          fd_cir,
	input wire  [1:0]           fd_cir_err,
	input wire  [1:0]           fd_cir_vld,
	output wire [1:0]           df_cir_use,
	output wire                 df_cir_lock,
	output wire [W_ADDR-1:0]    d_pc,

	input wire                  debug_mode,

	output wire                 d_starved,
	input wire                  x_stall,
	input wire                  f_jump_now,
	input wire  [W_ADDR-1:0]    f_jump_target,
	input wire                  x_jump_not_except,

	output reg  [W_DATA-1:0]    d_imm,
	output reg  [W_REGADDR-1:0] d_rs1,
	output reg  [W_REGADDR-1:0] d_rs2,
	output reg  [W_REGADDR-1:0] d_rd,
	output reg  [W_ALUSRC-1:0]  d_alusrc_a,
	output reg  [W_ALUSRC-1:0]  d_alusrc_b,
	output reg  [W_ALUOP-1:0]   d_aluop,
	output reg  [W_MEMOP-1:0]   d_memop,
	output reg  [W_MULOP-1:0]   d_mulop,
	output reg                  d_csr_ren,
	output reg                  d_csr_wen,
	output reg  [1:0]           d_csr_wtype,
	output reg                  d_csr_w_imm,
	output reg  [W_BCOND-1:0]   d_branchcond,
	output reg  [W_ADDR-1:0]    d_jump_offs,
	output reg                  d_jump_is_regoffs,
	output reg  [W_EXCEPT-1:0]  d_except,
	output reg                  d_wfi
);

`include "rv_opcodes.vh"
`include "hazard3_ops.vh"

localparam HAVE_CSR = CSR_M_MANDATORY || CSR_M_TRAP || CSR_COUNTER;

// ----------------------------------------------------------------------------
// Expand compressed instructions

wire [31:0] d_instr;
wire        d_instr_is_32bit;
wire        d_invalid_16bit;
reg         d_invalid_32bit;
wire        d_invalid = d_invalid_16bit || d_invalid_32bit;

hazard3_instr_decompress #(
	.PASSTHROUGH(!EXTENSION_C)
) decomp (
	.instr_in       (fd_cir),
	.instr_is_32bit (d_instr_is_32bit),
	.instr_out      (d_instr),
	.invalid        (d_invalid_16bit)
);

// Decode various immmediate formats
wire [31:0] d_imm_i = {{21{d_instr[31]}}, d_instr[30:20]};
wire [31:0] d_imm_s = {{21{d_instr[31]}}, d_instr[30:25], d_instr[11:7]};
wire [31:0] d_imm_b = {{20{d_instr[31]}}, d_instr[7], d_instr[30:25], d_instr[11:8], 1'b0};
wire [31:0] d_imm_u = {d_instr[31:12], {12{1'b0}}};
wire [31:0] d_imm_j = {{12{d_instr[31]}}, d_instr[19:12], d_instr[20], d_instr[30:21], 1'b0};


// ----------------------------------------------------------------------------
// PC/CIR control

// Must not flag bus error for a valid 16-bit instruction *followed by* an
// error, because instruction fetch errors are speculative, and can be
// flushed by e.g. a branch instruction. Note the 16 LSBs must be valid for
// us to know an instruction's size.
wire d_except_instr_bus_fault = fd_cir_vld > 2'd0 && fd_cir_err[0] ||
	fd_cir_vld > 2'd1 && d_instr_is_32bit && fd_cir_err[1];

assign d_starved = ~|fd_cir_vld || fd_cir_vld[0] && d_instr_is_32bit;
wire d_stall = x_stall || d_starved;

assign df_cir_use =
	d_starved || d_stall ? 2'h0 :
	d_instr_is_32bit ? 2'h2 : 2'h1;

// CIR Locking is required if we successfully assert a jump request, but decode is stalled.
// (This only happens if decode stall is caused by X stall, not if fetch is starved!)
// The reason for this is that, if the CIR is not locked in, it can be trashed by
// incoming fetch data before the roadblock clears ahead of us, which will squash any other
// side effects this instruction may have besides jumping! This includes:
// - Linking for JAL
// - Mispredict recovery for branches
// Note that it is not possible to simply gate the jump request based on X stalling,
// because X stall is a function of hready, and jump request feeds haddr htrans etc.

wire jump_caused_by_d = f_jump_now && x_jump_not_except;
wire assert_cir_lock = jump_caused_by_d && d_stall;
wire deassert_cir_lock = !d_stall;
reg cir_lock_prev;

assign df_cir_lock = (cir_lock_prev && !deassert_cir_lock) || assert_cir_lock;

always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		cir_lock_prev <= 1'b0;
	else
		cir_lock_prev <= df_cir_lock;

reg  [W_ADDR-1:0]    pc;
wire [W_ADDR-1:0]    pc_next = pc + (d_instr_is_32bit ? 32'h4 : 32'h2);
assign d_pc = pc;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		pc <= RESET_VECTOR;
	end else begin
		if ((f_jump_now && !assert_cir_lock) || (cir_lock_prev && deassert_cir_lock)) begin
			pc <= f_jump_target;
`ifdef FORMAL
			// Being cheeky above to save a 32 bit mux. Check that we never get an M target by mistake.

			// FIXME disabled this for now -- we do sometimes see an exception taking
			// place during the stall, which then leads to a different branch target
			// appearing. (i.e. f_jump_now is asserted for two cycles, the first one
			// from this instruction and the second from the exception; this is ok,
			// because the exception will return to this branch when done.)

			// if (cir_lock_prev && deassert_cir_lock)
			// 	assert(f_jump_target == d_jump_target);
`endif
		end else if (!d_stall && !df_cir_lock) begin
			pc <= pc_next;
		end
	end
end

always @ (*) begin
	// JAL is major opcode 1101111,
	// JALR is             1100111,
	// branches are        1100011.
	casez (d_instr[3:2])
	2'b1z:   d_jump_offs = d_imm_j;
	2'b01:   d_jump_offs = d_imm_i;
	default: d_jump_offs = d_imm_b;
	endcase
end

// ----------------------------------------------------------------------------
// Decode X controls

localparam X0 = {W_REGADDR{1'b0}};

always @ (*) begin
	// Assign some defaults
	d_rs1 = d_instr[19:15];
	d_rs2 = d_instr[24:20];
	d_rd  = d_instr[11: 7];
	d_imm = d_imm_i;
	d_alusrc_a = ALUSRCA_RS1;
	d_alusrc_b = ALUSRCB_RS2;
	d_aluop = ALUOP_ADD;
	d_memop = MEMOP_NONE;
	d_mulop = M_OP_MUL;
	d_csr_ren = 1'b0;
	d_csr_wen = 1'b0;
	d_csr_wtype = CSR_WTYPE_W;
	d_csr_w_imm = 1'b0;
	d_branchcond = BCOND_NEVER;
	d_jump_is_regoffs = 1'b0;
	d_invalid_32bit = 1'b0;
	d_except = EXCEPT_NONE;
	d_wfi = 1'b0;

	casez (d_instr)
	RV_BEQ:     begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_rd = X0; d_aluop = ALUOP_SUB; d_branchcond = BCOND_ZERO;  end
	RV_BNE:     begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_rd = X0; d_aluop = ALUOP_SUB; d_branchcond = BCOND_NZERO; end
	RV_BLT:     begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_rd = X0; d_aluop = ALUOP_LT;  d_branchcond = BCOND_NZERO; end
	RV_BGE:     begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_rd = X0; d_aluop = ALUOP_LT;  d_branchcond = BCOND_ZERO; end
	RV_BLTU:    begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_rd = X0; d_aluop = ALUOP_LTU; d_branchcond = BCOND_NZERO; end
	RV_BGEU:    begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_rd = X0; d_aluop = ALUOP_LTU; d_branchcond = BCOND_ZERO; end
	RV_JALR:    begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_branchcond = BCOND_ALWAYS; d_jump_is_regoffs = 1'b1; d_rs2 = X0; d_aluop = ALUOP_ADD; d_alusrc_a = ALUSRCA_PC; d_alusrc_b = ALUSRCB_IMM; d_imm = d_instr_is_32bit ? 32'h4 : 32'h2; end
	RV_JAL:     begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_branchcond = BCOND_ALWAYS; d_rs1 = X0;               d_rs2 = X0; d_aluop = ALUOP_ADD; d_alusrc_a = ALUSRCA_PC; d_alusrc_b = ALUSRCB_IMM; d_imm = d_instr_is_32bit ? 32'h4 : 32'h2; end
	RV_LUI:     begin d_aluop = ALUOP_ADD; d_imm = d_imm_u; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; d_rs1 = X0; end
	RV_AUIPC:   begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_aluop = ALUOP_ADD; d_imm = d_imm_u; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; d_alusrc_a = ALUSRCA_PC;  d_rs1 = X0; end
	RV_ADDI:    begin d_aluop = ALUOP_ADD; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	RV_SLLI:    begin d_aluop = ALUOP_SLL; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	RV_SLTI:    begin d_aluop = ALUOP_LT;  d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	RV_SLTIU:   begin d_aluop = ALUOP_LTU; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	RV_XORI:    begin d_aluop = ALUOP_XOR; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	RV_SRLI:    begin d_aluop = ALUOP_SRL; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	RV_SRAI:    begin d_aluop = ALUOP_SRA; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	RV_ORI:     begin d_aluop = ALUOP_OR;  d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	RV_ANDI:    begin d_aluop = ALUOP_AND; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	RV_ADD:     begin d_aluop = ALUOP_ADD; end
	RV_SUB:     begin d_aluop = ALUOP_SUB; end
	RV_SLL:     begin d_aluop = ALUOP_SLL; end
	RV_SLT:     begin d_aluop = ALUOP_LT;  end
	RV_SLTU:    begin d_aluop = ALUOP_LTU; end
	RV_XOR:     begin d_aluop = ALUOP_XOR; end
	RV_SRL:     begin d_aluop = ALUOP_SRL; end
	RV_SRA:     begin d_aluop = ALUOP_SRA; end
	RV_OR:      begin d_aluop = ALUOP_OR;  end
	RV_AND:     begin d_aluop = ALUOP_AND; end
	RV_LB:      begin d_aluop = ALUOP_ADD; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; d_memop = MEMOP_LB;  end
	RV_LH:      begin d_aluop = ALUOP_ADD; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; d_memop = MEMOP_LH;  end
	RV_LW:      begin d_aluop = ALUOP_ADD; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; d_memop = MEMOP_LW;  end
	RV_LBU:     begin d_aluop = ALUOP_ADD; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; d_memop = MEMOP_LBU; end
	RV_LHU:     begin d_aluop = ALUOP_ADD; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; d_memop = MEMOP_LHU; end
	RV_SB:      begin d_aluop = ALUOP_ADD; d_imm = d_imm_s; d_alusrc_b = ALUSRCB_IMM; d_memop = MEMOP_SB;  d_rd = X0; end
	RV_SH:      begin d_aluop = ALUOP_ADD; d_imm = d_imm_s; d_alusrc_b = ALUSRCB_IMM; d_memop = MEMOP_SH;  d_rd = X0; end
	RV_SW:      begin d_aluop = ALUOP_ADD; d_imm = d_imm_s; d_alusrc_b = ALUSRCB_IMM; d_memop = MEMOP_SW;  d_rd = X0; end
	RV_MUL:     if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_MUL;    end else begin d_invalid_32bit = 1'b1; end
	RV_MULH:    if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_MULH;   end else begin d_invalid_32bit = 1'b1; end
	RV_MULHSU:  if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_MULHSU; end else begin d_invalid_32bit = 1'b1; end
	RV_MULHU:   if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_MULHU;  end else begin d_invalid_32bit = 1'b1; end
	RV_DIV:     if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_DIV;    end else begin d_invalid_32bit = 1'b1; end
	RV_DIVU:    if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_DIVU;   end else begin d_invalid_32bit = 1'b1; end
	RV_REM:     if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_REM;    end else begin d_invalid_32bit = 1'b1; end
	RV_REMU:    if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_REMU;   end else begin d_invalid_32bit = 1'b1; end
	RV_SH1ADD:  if (EXTENSION_ZBA) begin d_aluop = ALUOP_SH1ADD;                                                        end else begin d_invalid_32bit = 1'b1; end
	RV_SH2ADD:  if (EXTENSION_ZBA) begin d_aluop = ALUOP_SH2ADD;                                                        end else begin d_invalid_32bit = 1'b1; end
	RV_SH3ADD:  if (EXTENSION_ZBA) begin d_aluop = ALUOP_SH3ADD;                                                        end else begin d_invalid_32bit = 1'b1; end
	RV_ANDN:    if (EXTENSION_ZBB) begin d_aluop = ALUOP_ANDN;                                                          end else begin d_invalid_32bit = 1'b1; end
	RV_CLZ:     if (EXTENSION_ZBB) begin d_aluop = ALUOP_CLZ;    d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	RV_CPOP:    if (EXTENSION_ZBB) begin d_aluop = ALUOP_CPOP;   d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	RV_CTZ:     if (EXTENSION_ZBB) begin d_aluop = ALUOP_CTZ;    d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	RV_MAX:     if (EXTENSION_ZBB) begin d_aluop = ALUOP_MAX;                                                           end else begin d_invalid_32bit = 1'b1; end
	RV_MAXU:    if (EXTENSION_ZBB) begin d_aluop = ALUOP_MAXU;                                                          end else begin d_invalid_32bit = 1'b1; end
	RV_MIN:     if (EXTENSION_ZBB) begin d_aluop = ALUOP_MIN;                                                           end else begin d_invalid_32bit = 1'b1; end
	RV_MINU:    if (EXTENSION_ZBB) begin d_aluop = ALUOP_MINU;                                                          end else begin d_invalid_32bit = 1'b1; end
	RV_ORC_B:   if (EXTENSION_ZBB) begin d_aluop = ALUOP_ORC_B;  d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	RV_ORN:     if (EXTENSION_ZBB) begin d_aluop = ALUOP_ORN;                                                           end else begin d_invalid_32bit = 1'b1; end
	RV_REV8:    if (EXTENSION_ZBB) begin d_aluop = ALUOP_REV8;   d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	RV_ROL:     if (EXTENSION_ZBB) begin d_aluop = ALUOP_ROL;                                                           end else begin d_invalid_32bit = 1'b1; end
	RV_ROR:     if (EXTENSION_ZBB) begin d_aluop = ALUOP_ROR;                                                           end else begin d_invalid_32bit = 1'b1; end
	RV_RORI:    if (EXTENSION_ZBB) begin d_aluop = ALUOP_ROR;    d_rs2 = X0; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; end else begin d_invalid_32bit = 1'b1; end
	RV_SEXT_B:  if (EXTENSION_ZBB) begin d_aluop = ALUOP_SEXT_B; d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	RV_SEXT_H:  if (EXTENSION_ZBB) begin d_aluop = ALUOP_SEXT_H; d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	RV_XNOR:    if (EXTENSION_ZBB) begin d_aluop = ALUOP_XNOR;                                                          end else begin d_invalid_32bit = 1'b1; end
	RV_ZEXT_H:  if (EXTENSION_ZBB) begin d_aluop = ALUOP_ZEXT_H; d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	RV_CLMUL:   if (EXTENSION_ZBC) begin d_aluop = ALUOP_CLMUL;                                                         end else begin d_invalid_32bit = 1'b1; end
	RV_CLMULH:  if (EXTENSION_ZBC) begin d_aluop = ALUOP_CLMULH;                                                        end else begin d_invalid_32bit = 1'b1; end
	RV_CLMULR:  if (EXTENSION_ZBC) begin d_aluop = ALUOP_CLMULR;                                                        end else begin d_invalid_32bit = 1'b1; end
	RV_BCLR:    if (EXTENSION_ZBC) begin d_aluop = ALUOP_BCLR;                                                          end else begin d_invalid_32bit = 1'b1; end
	RV_BCLRI:   if (EXTENSION_ZBC) begin d_aluop = ALUOP_BCLR;   d_rs2 = X0; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; end else begin d_invalid_32bit = 1'b1; end
	RV_BEXT:    if (EXTENSION_ZBC) begin d_aluop = ALUOP_BEXT;                                                          end else begin d_invalid_32bit = 1'b1; end
	RV_BEXTI:   if (EXTENSION_ZBC) begin d_aluop = ALUOP_BEXT;   d_rs2 = X0; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; end else begin d_invalid_32bit = 1'b1; end
	RV_BINV:    if (EXTENSION_ZBC) begin d_aluop = ALUOP_BINV;                                                          end else begin d_invalid_32bit = 1'b1; end
	RV_BINVI:   if (EXTENSION_ZBC) begin d_aluop = ALUOP_BINV;   d_rs2 = X0; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; end else begin d_invalid_32bit = 1'b1; end
	RV_BSET:    if (EXTENSION_ZBC) begin d_aluop = ALUOP_BSET;                                                          end else begin d_invalid_32bit = 1'b1; end
	RV_BSETI:   if (EXTENSION_ZBC) begin d_aluop = ALUOP_BSET;   d_rs2 = X0; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; end else begin d_invalid_32bit = 1'b1; end
	RV_FENCE:   begin d_rd = X0; end  // NOP
	RV_FENCE_I: begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_rd = X0; d_rs1 = X0; d_rs2 = X0; d_branchcond = BCOND_NZERO; d_imm[31] = 1'b1; end // FIXME this is probably busted now. Maybe implement as an exception?
	RV_CSRRW:   if (HAVE_CSR) begin d_imm = d_imm_i; d_csr_wen = 1'b1  ; d_csr_ren = |d_rd; d_csr_wtype = CSR_WTYPE_W; end else begin d_invalid_32bit = 1'b1; end
	RV_CSRRS:   if (HAVE_CSR) begin d_imm = d_imm_i; d_csr_wen = |d_rs1; d_csr_ren = 1'b1 ; d_csr_wtype = CSR_WTYPE_S; end else begin d_invalid_32bit = 1'b1; end
	RV_CSRRC:   if (HAVE_CSR) begin d_imm = d_imm_i; d_csr_wen = |d_rs1; d_csr_ren = 1'b1 ; d_csr_wtype = CSR_WTYPE_C; end else begin d_invalid_32bit = 1'b1; end
	RV_CSRRWI:  if (HAVE_CSR) begin d_imm = d_imm_i; d_csr_wen = 1'b1  ; d_csr_ren = |d_rd; d_csr_wtype = CSR_WTYPE_W; d_csr_w_imm = 1'b1; end else begin d_invalid_32bit = 1'b1; end
	RV_CSRRSI:  if (HAVE_CSR) begin d_imm = d_imm_i; d_csr_wen = |d_rs1; d_csr_ren = 1'b1 ; d_csr_wtype = CSR_WTYPE_S; d_csr_w_imm = 1'b1; end else begin d_invalid_32bit = 1'b1; end
	RV_CSRRCI:  if (HAVE_CSR) begin d_imm = d_imm_i; d_csr_wen = |d_rs1; d_csr_ren = 1'b1 ; d_csr_wtype = CSR_WTYPE_C; d_csr_w_imm = 1'b1; end else begin d_invalid_32bit = 1'b1; end
	RV_ECALL:   if (HAVE_CSR) begin d_except = EXCEPT_ECALL;  d_rs2 = X0; d_rs1 = X0; d_rd = X0; end else begin d_invalid_32bit = 1'b1; end
	RV_EBREAK:  if (HAVE_CSR) begin d_except = EXCEPT_EBREAK; d_rs2 = X0; d_rs1 = X0; d_rd = X0; end else begin d_invalid_32bit = 1'b1; end
	RV_MRET:    if (HAVE_CSR) begin d_except = EXCEPT_MRET;   d_rs2 = X0; d_rs1 = X0; d_rd = X0; end else begin d_invalid_32bit = 1'b1; end
	RV_WFI:     if (HAVE_CSR) begin d_wfi = 1'b1;             d_rs2 = X0; d_rs1 = X0; d_rd = X0; end else begin d_invalid_32bit = 1'b1; end
	default:    begin d_invalid_32bit = 1'b1; end
	endcase

	if (d_invalid || d_starved || d_except_instr_bus_fault) begin
		d_rs1        = {W_REGADDR{1'b0}};
		d_rs2        = {W_REGADDR{1'b0}};
		d_rd         = {W_REGADDR{1'b0}};
		d_memop      = MEMOP_NONE;
		d_branchcond = BCOND_NEVER;
		d_csr_ren    = 1'b0;
		d_csr_wen    = 1'b0;
		d_except     = EXCEPT_NONE;
		d_wfi        = 1'b0;
		if (EXTENSION_M)
			d_aluop = ALUOP_ADD;

		if (d_except_instr_bus_fault)
			d_except = EXCEPT_INSTR_FAULT;
		else if (d_invalid && !d_starved)
			d_except = EXCEPT_INSTR_ILLEGAL;
	end
	if (cir_lock_prev) begin
		d_branchcond = BCOND_NEVER;
	end
end

endmodule
