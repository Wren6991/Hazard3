/******************************************************************************
 *     DO WHAT THE FUCK YOU WANT TO AND DON'T BLAME US PUBLIC LICENSE         *
 *                        Version 3, April 2008                               *
 *                                                                            *
 *     Copyright (C) 2019 Luke Wren                                           *
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

module hazard3_decode #(
`include "hazard3_config.vh"
,
`include "hazard3_width_const.vh"
) (
	input wire clk,
	input wire rst_n,

	input wire  [31:0]          fd_cir,
	input wire  [1:0]           fd_cir_vld,
	output wire [1:0]           df_cir_use,
	output wire                 df_cir_lock,
	output reg                  d_jump_req,
	output reg  [W_ADDR-1:0]    d_jump_target,
	output wire [W_ADDR-1:0]    d_pc, // FIXME only added for riscv-formal

	output wire                 d_stall,
	input wire                  x_stall,
	input wire                  flush_d_x,
	input wire                  f_jump_rdy,
	input wire                  f_jump_now,
	input wire  [W_ADDR-1:0]    f_jump_target,

	output reg  [W_REGADDR-1:0] d_rs1, // combinatorial
	output reg  [W_REGADDR-1:0] d_rs2, // combinatorial

	output reg  [W_DATA-1:0]    dx_imm,
	output reg  [W_REGADDR-1:0] dx_rs1,
	output reg  [W_REGADDR-1:0] dx_rs2,
	output reg  [W_REGADDR-1:0] dx_rd,
	output reg  [W_ALUSRC-1:0]  dx_alusrc_a,
	output reg  [W_ALUSRC-1:0]  dx_alusrc_b,
	output reg  [W_ALUOP-1:0]   dx_aluop,
	output reg  [W_MEMOP-1:0]   dx_memop,
	output reg  [W_MULOP-1:0]   dx_mulop,
	output reg                  dx_csr_ren,
	output reg                  dx_csr_wen,
	output reg  [1:0]           dx_csr_wtype,
	output reg                  dx_csr_w_imm,
	output reg  [W_BCOND-1:0]   dx_branchcond,
	output reg  [W_ADDR-1:0]    dx_jump_target,
	output reg                  dx_jump_is_regoffs,
	output reg                  dx_result_is_linkaddr,
	output reg  [W_ADDR-1:0]    dx_pc,
	output reg  [W_ADDR-1:0]    dx_mispredict_addr,
	output reg  [2:0]           dx_except
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

wire d_starved = ~|fd_cir_vld || fd_cir_vld[0] && d_instr_is_32bit;
assign d_stall = x_stall ||
	d_starved || (d_jump_req && !f_jump_rdy);
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

// Note it is possible for d_jump_req and m_jump_req to be asserted
// simultaneously, hence checking flush:
wire jump_caused_by_d = d_jump_req && f_jump_rdy && !flush_d_x;
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
			if (cir_lock_prev && deassert_cir_lock)
				assert(f_jump_target == d_jump_target);
`endif
		end else if (!d_stall && !df_cir_lock) begin
			pc <= pc_next;
		end
	end
end

// If the current CIR is there due to locking, it is a jump which has already had primary effect.
wire jump_enable = !d_starved && !cir_lock_prev && !d_invalid;
reg [W_ADDR-1:0] d_jump_offs;


always @ (*) begin
	// JAL is major opcode 1101111,
	// branches are        1100011.
	case (d_instr[3])
	1'b1:    d_jump_offs = d_imm_j;
	default: d_jump_offs = d_imm_b;
	endcase

	d_jump_target = pc + d_jump_offs;

	casez ({d_instr[31], d_instr})
	{1'b1, RV_BEQ }: d_jump_req = jump_enable;
	{1'b1, RV_BNE }: d_jump_req = jump_enable;
	{1'b1, RV_BLT }: d_jump_req = jump_enable;
	{1'b1, RV_BGE }: d_jump_req = jump_enable;
	{1'b1, RV_BLTU}: d_jump_req = jump_enable;
	{1'b1, RV_BGEU}: d_jump_req = jump_enable;
	{1'bz, RV_JAL }: d_jump_req = jump_enable;
	default: d_jump_req = 1'b0;
	endcase
end

// ----------------------------------------------------------------------------
// Decode X controls

// Combinatorials:
reg  [W_REGADDR-1:0] d_rd;
reg  [W_DATA-1:0]    d_imm;
reg  [W_DATA-1:0]    d_branchoffs;
reg  [W_ALUSRC-1:0]  d_alusrc_a;
reg  [W_ALUSRC-1:0]  d_alusrc_b;
reg  [W_ALUOP-1:0]   d_aluop;
reg  [W_MEMOP-1:0]   d_memop;
reg  [W_MULOP-1:0]   d_mulop;
reg  [W_BCOND-1:0]   d_branchcond;
reg                  d_jump_is_regoffs;
reg                  d_result_is_linkaddr;
reg                  d_csr_ren;
reg                  d_csr_wen;
reg  [1:0]           d_csr_wtype;
reg                  d_csr_w_imm;
reg  [W_EXCEPT-1:0]  d_except;

localparam X0 = {W_REGADDR{1'b0}};

always @ (*) begin
	// Assign some defaults
	d_rs1 = d_instr[19:15];
	d_rs2 = d_instr[24:20];
	d_rd  = d_instr[11: 7];
	d_imm = d_imm_i;
	d_branchoffs = d_imm_i;
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
	d_result_is_linkaddr = 1'b0;
	d_invalid_32bit = 1'b0;
	d_except = EXCEPT_NONE;

	casez (d_instr)
	RV_BEQ:     begin d_rd = X0; d_aluop = ALUOP_SUB; d_branchcond = BCOND_ZERO;  end
	RV_BNE:     begin d_rd = X0; d_aluop = ALUOP_SUB; d_branchcond = BCOND_NZERO; end
	RV_BLT:     begin d_rd = X0; d_aluop = ALUOP_LT;  d_branchcond = BCOND_NZERO; end
	RV_BGE:     begin d_rd = X0; d_aluop = ALUOP_LT;  d_branchcond = BCOND_ZERO; end
	RV_BLTU:    begin d_rd = X0; d_aluop = ALUOP_LTU; d_branchcond = BCOND_NZERO; end
	RV_BGEU:    begin d_rd = X0; d_aluop = ALUOP_LTU; d_branchcond = BCOND_ZERO; end
	RV_JALR:    begin d_result_is_linkaddr = 1'b1; d_jump_is_regoffs = 1'b1; d_aluop = ALUOP_ADD; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; d_branchcond = BCOND_ALWAYS; end
	RV_JAL:     begin d_result_is_linkaddr = 1'b1; d_rs2 = X0; d_rs1 = X0; end
	RV_LUI:     begin d_aluop = ALUOP_ADD; d_imm = d_imm_u; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; d_rs1 = X0; end
	RV_AUIPC:   begin d_aluop = ALUOP_ADD; d_imm = d_imm_u; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; d_alusrc_a = ALUSRCA_PC;  d_rs1 = X0; end
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
	RV_FENCE:   begin d_rd = X0; end  // NOP
	RV_FENCE_I: begin d_rd = X0; d_rs1 = X0; d_rs2 = X0; d_branchcond = BCOND_NZERO; d_imm[31] = 1'b1; end // Pretend we are recovering from a mispredicted-taken backward branch. Mispredict recovery flushes frontend.
	RV_CSRRW:   if (HAVE_CSR) begin d_imm = d_imm_i; d_csr_wen = 1'b1  ; d_csr_ren = |d_rd; d_csr_wtype = CSR_WTYPE_W; end else begin d_invalid_32bit = 1'b1; end
	RV_CSRRS:   if (HAVE_CSR) begin d_imm = d_imm_i; d_csr_wen = |d_rs1; d_csr_ren = 1'b1 ; d_csr_wtype = CSR_WTYPE_S; end else begin d_invalid_32bit = 1'b1; end
	RV_CSRRC:   if (HAVE_CSR) begin d_imm = d_imm_i; d_csr_wen = |d_rs1; d_csr_ren = 1'b1 ; d_csr_wtype = CSR_WTYPE_C; end else begin d_invalid_32bit = 1'b1; end
	RV_CSRRWI:  if (HAVE_CSR) begin d_imm = d_imm_i; d_csr_wen = 1'b1  ; d_csr_ren = |d_rd; d_csr_wtype = CSR_WTYPE_W; d_csr_w_imm = 1'b1; end else begin d_invalid_32bit = 1'b1; end
	RV_CSRRSI:  if (HAVE_CSR) begin d_imm = d_imm_i; d_csr_wen = |d_rs1; d_csr_ren = 1'b1 ; d_csr_wtype = CSR_WTYPE_S; d_csr_w_imm = 1'b1; end else begin d_invalid_32bit = 1'b1; end
	RV_CSRRCI:  if (HAVE_CSR) begin d_imm = d_imm_i; d_csr_wen = |d_rs1; d_csr_ren = 1'b1 ; d_csr_wtype = CSR_WTYPE_C; d_csr_w_imm = 1'b1; end else begin d_invalid_32bit = 1'b1; end
	RV_ECALL:   if (HAVE_CSR) begin d_except = EXCEPT_ECALL;  d_rs2 = X0; d_rs1 = X0; d_rd = X0; end else begin d_invalid_32bit = 1'b1; end
	RV_EBREAK:  if (HAVE_CSR) begin d_except = EXCEPT_EBREAK; d_rs2 = X0; d_rs1 = X0; d_rd = X0; end else begin d_invalid_32bit = 1'b1; end
	RV_MRET:    if (HAVE_CSR) begin d_except = EXCEPT_MRET;   d_rs2 = X0; d_rs1 = X0; d_rd = X0; end else begin d_invalid_32bit = 1'b1; end
	default:    begin d_invalid_32bit = 1'b1; end
	endcase
end


always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		{dx_rs1, dx_rs2, dx_rd} <= {(3 * W_REGADDR){1'b0}};
		dx_alusrc_a <= ALUSRCA_RS1;
		dx_alusrc_b <= ALUSRCB_RS2;
		dx_aluop <= ALUOP_ADD;
		dx_memop <= MEMOP_NONE;
		dx_mulop <= M_OP_MUL;
		dx_csr_ren <= 1'b0;
		dx_csr_wen <= 1'b0;
		dx_csr_wtype <= CSR_WTYPE_W;
		dx_csr_w_imm <= 1'b0;
		dx_branchcond <= BCOND_NEVER;
		dx_jump_is_regoffs <= 1'b0;
		dx_result_is_linkaddr <= 1'b0;
		dx_except <= EXCEPT_NONE;
	end else if (flush_d_x || (d_stall && !x_stall)) begin
		// Bubble insertion
		dx_branchcond <= BCOND_NEVER;
		dx_memop <= MEMOP_NONE;
		dx_rd <= 5'h0;
		dx_except <= EXCEPT_NONE;
		dx_csr_ren <= 1'b0;
		dx_csr_wen <= 1'b0;
		// Don't start a multiply in a pipe bubble
		if (EXTENSION_M)
			dx_aluop <= ALUOP_ADD;
		// Also need to clear rs1, rs2, due to a nasty sequence of events:
		// Suppose we have a load, followed by a dependent branch, which is predicted taken
		// - branch will stall in D until AHB master becomes free
		// - on next cycle, prediction causes jump, and bubble is in X
		// - if X gets branch's rs1, rs2, it will cause spurious RAW stall
		// - on next cycle, branch will not progress into X due to RAW stall, but *will* be replaced in D due to jump
		// - branch mispredict now cannot be corrected
		dx_rs1 <= 5'h0;
		dx_rs2 <= 5'h0;
	end else if (!x_stall) begin
		// These ones can have side effects
		dx_rs1        <= d_invalid ? {W_REGADDR{1'b0}}    : d_rs1;
		dx_rs2        <= d_invalid ? {W_REGADDR{1'b0}}    : d_rs2;
		dx_rd         <= d_invalid ? {W_REGADDR{1'b0}}    : d_rd;
		dx_memop      <= d_invalid ? MEMOP_NONE           : d_memop;
		dx_branchcond <= d_invalid ? BCOND_NEVER          : d_branchcond;
		dx_csr_ren    <= d_invalid ? 1'b0                 : d_csr_ren;
		dx_csr_wen    <= d_invalid ? 1'b0                 : d_csr_wen;
		dx_except     <= d_invalid ? EXCEPT_INSTR_ILLEGAL : d_except;
		dx_aluop      <= d_invalid && EXTENSION_M ? ALUOP_ADD : d_aluop;

		// These can't
		dx_alusrc_a <= d_alusrc_a;
		dx_alusrc_b <= d_alusrc_b;
		dx_mulop <= d_mulop;
		dx_jump_is_regoffs <= d_jump_is_regoffs;
		dx_result_is_linkaddr <= d_result_is_linkaddr;
		dx_csr_wtype <= d_csr_wtype;
		dx_csr_w_imm <= d_csr_w_imm;
	end
end

// No reset required on these; will be masked by the resettable pipeline controls until they're valid
always @ (posedge clk) begin
	if (!x_stall) begin
		dx_imm <= d_imm;
		dx_jump_target <= d_jump_target;
		dx_mispredict_addr <= pc_next;
		dx_pc <= pc;
	end
	if (flush_d_x) begin
		// The target of a late jump must be propagated *immediately* to X PC, as
		// mepc may sample X PC at any time due to IRQ, and must not capture
		// misprediction.
		// Also required for flush while X stalled (e.g. if a muldiv enters X while
		// a 1 cycle bus stall holds off the jump request in M)
		dx_pc <= f_jump_target;
		`ifdef FORMAL
		// This should only be caused by late jumps
		assert(f_jump_now);
		`endif
	end
end

endmodule
