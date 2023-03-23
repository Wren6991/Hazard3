/*****************************************************************************\
|                      Copyright (C) 2021-2023 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module hazard3_decode #(
`include "hazard3_config.vh"
,
`include "hazard3_width_const.vh"
) (
	input  wire                 clk,
	input  wire                 rst_n,

	input  wire [31:0]          fd_cir,
	input  wire [1:0]           fd_cir_err,
	input  wire [1:0]           fd_cir_predbranch,
	input  wire [1:0]           fd_cir_vld,
	output wire [1:0]           df_cir_use,
	output wire                 df_cir_flush_behind,
	output wire [3:0]           df_uop_step_next,
	output wire [W_ADDR-1:0]    d_pc,

	input  wire                 debug_mode,
	input  wire                 m_mode,
	input  wire                 trap_wfi,

	input  wire [W_ADDR-1:0]    debug_dpc_wdata,
	input  wire                 debug_dpc_wen,
	output wire [W_ADDR-1:0]    debug_dpc_rdata,

	output wire                 d_starved,
	input  wire                 x_stall,
	input  wire                 f_jump_now,
	input  wire [W_ADDR-1:0]    f_jump_target,
	input  wire                 x_jump_not_except,
	input  wire [W_ADDR-1:0]    d_btb_target_addr,

	output reg  [W_DATA-1:0]    d_imm,
	output reg  [W_REGADDR-1:0] d_rs1,
	output reg  [W_REGADDR-1:0] d_rs2,
	output reg  [W_REGADDR-1:0] d_rd,
	output reg  [2:0]           d_funct3_32b,
	output reg  [6:0]           d_funct7_32b,
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
	output reg  [W_ADDR-1:0]    d_addr_offs,
	output reg                  d_addr_is_regoffs,
	output reg  [W_EXCEPT-1:0]  d_except,
	output reg                  d_sleep_wfi,
	output reg                  d_sleep_block,
	output reg                  d_sleep_unblock,
	output wire                 d_no_pc_increment,
	output wire                 d_uninterruptible,
	output reg                  d_fence_i
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

wire        uop_seq_raw;
wire        uop_final;
wire        uop_no_pc_update;
wire        uop_atomic;
wire        uop_stall;
wire        uop_clear;

hazard3_instr_decompress #(
`include "hazard3_config_inst.vh"
) decomp (
	.clk                        (clk),
	.rst_n                      (rst_n),

	.instr_in                   (fd_cir),
	.instr_is_32bit             (d_instr_is_32bit),
	.instr_out                  (d_instr),
	.instr_out_is_uop           (uop_seq_raw),
	.instr_out_is_final_uop     (uop_final),
	.instr_out_uop_no_pc_update (uop_no_pc_update),
	.instr_out_uop_atomic       (uop_atomic),
	.instr_out_uop_stall        (uop_stall),
	.instr_out_uop_clear        (uop_clear),

	.df_uop_step_next           (df_uop_step_next),

	.invalid                    (d_invalid_16bit)
);

wire   uop_seq           = uop_seq_raw && !d_starved;
wire   uop_nonfinal      = uop_seq && !uop_final;
assign uop_stall         = x_stall || d_starved;

assign d_uninterruptible = uop_atomic && !d_invalid;

// Signal to null the mepc offset when taking an exception on this
// instruction (because uops in a sequence *which can except*, so excluding
// the final sp adjust on popret/popretz, will all have the same PC as the
// next uop, which will be in stage 2 when they take their exception)
assign d_no_pc_increment = uop_nonfinal;

// Note !df_cir_flush_behind because the jump in cm.popret/popretz is
// the *penultimate* instruction: we execute the stack adjustment in the
// fetch bubble to save a cycle, still need to finish the uop sequence.
assign uop_clear         = f_jump_now && !df_cir_flush_behind;

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
wire d_stall = x_stall || d_starved || uop_nonfinal;

assign df_cir_use =
	d_starved || d_stall ? 2'h0 :
	d_instr_is_32bit ? 2'h2 : 2'h1;

// CIR Locking is required if we successfully assert a jump request, but
// decode is stalled. It is not possible to gate the jump request if the
// stall depends on bus stall (as this would create a through-path from bus
// stall to bus request) so instead we instruct the frontent to preserve the
// stalled instruction when flushing, and fill in behind it.
//
// Once the stall clears, the stalled instruction can execute its remaining
// side effects e.g. writing a link value to the register file.
wire jump_caused_by_d = f_jump_now && x_jump_not_except;
wire assert_cir_lock = jump_caused_by_d && d_stall;
wire deassert_cir_lock = !d_stall;
reg cir_lock_prev;

wire cir_lock = (cir_lock_prev && !deassert_cir_lock) || assert_cir_lock;
assign df_cir_flush_behind = assert_cir_lock && !cir_lock_prev;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		cir_lock_prev <= 1'b0;
	end else begin
		cir_lock_prev <= cir_lock;
	end
end

reg  [W_ADDR-1:0] pc;
wire [W_ADDR-1:0] pc_seq_next = pc + (
	|EXTENSION_ZCMP && uop_seq && uop_no_pc_update ? 32'h0 :
	d_instr_is_32bit                               ? 32'h4 : 32'h2
);

assign d_pc = pc;
assign debug_dpc_rdata = pc;

// Frontend should mark the whole instruction, and nothing but the
// instruction, as a predicted branch. This goes wrong when we execute the
// address containing the predicted branch twice with different 16-bit
// alignments (!). We need to issue a branch-to-self to get back on a linear
// path, otherwise PC and CIR will diverge and we will misexecute.
wire partial_predicted_branch = !d_starved &&
	|BRANCH_PREDICTOR && d_instr_is_32bit && ^fd_cir_predbranch;

wire predicted_branch = |BRANCH_PREDICTOR && fd_cir_predbranch[0];

// Generally locking takes place on a stalled jump/branch, which may need the
// original PC available to produce a link address when it unstalls. An
// exception to this is jumps in micro-op sequences: in this case the jump is
// the penultimate instruction in the sequence (ret before addi sp) and we
// need to capture the pc mid-uop-sequence.
wire hold_pc_on_cir_lock = assert_cir_lock && !(uop_seq && !uop_no_pc_update);
wire update_pc_on_cir_unlock = cir_lock_prev && deassert_cir_lock && !(uop_seq && uop_no_pc_update);

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		pc <= RESET_VECTOR;
	end else begin
		if (debug_dpc_wen) begin
			pc <= debug_dpc_wdata;
		end else if (debug_mode) begin
			pc <= pc;
		end else if ((f_jump_now && !hold_pc_on_cir_lock) || update_pc_on_cir_unlock) begin
			pc <= f_jump_target;
		end else if (!d_stall && !cir_lock) begin
			// If this instruction is a predicted-taken branch (and has not
			// generated a mispredict recovery jump) then set PC to the
			// prediction target instead of the sequentially next PC
			pc <= predicted_branch ? d_btb_target_addr : pc_seq_next;
		end
	end
end

wire [W_ADDR-1:0] branch_offs =
	!d_instr_is_32bit && fd_cir_predbranch[0] && |BRANCH_PREDICTOR ? 32'h2 :
	 d_instr_is_32bit && fd_cir_predbranch[1] && |BRANCH_PREDICTOR ? 32'h4 : d_imm_b;

always @ (*) begin
	casez ({|EXTENSION_A, |EXTENSION_ZIFENCEI, d_instr[6:2]})
	{1'bz, 1'bz, 5'b11011}: d_addr_offs = d_imm_j      ; // JAL
	{1'bz, 1'bz, 5'b11000}: d_addr_offs = branch_offs  ; // Branches
	{1'bz, 1'bz, 5'b01000}: d_addr_offs = d_imm_s      ; // Store
	{1'bz, 1'bz, 5'b11001}: d_addr_offs = d_imm_i      ; // JALR
	{1'bz, 1'bz, 5'b00000}: d_addr_offs = d_imm_i      ; // Loads
	{1'b1, 1'bz, 5'b01011}: d_addr_offs = 32'h0000_0000; // Atomics
	{1'bz, 1'b1, 5'b00011}: d_addr_offs = 32'h0000_0004; // Zifencei
	default:                d_addr_offs = 32'hxxxx_xxxx;
	endcase
	if (partial_predicted_branch) begin
		d_addr_offs = 32'h0000_0000;
	end
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
	d_addr_is_regoffs = 1'b0;
	d_invalid_32bit = 1'b0;
	d_except = EXCEPT_NONE;
	d_sleep_wfi = 1'b0;
	d_sleep_block = 1'b0;
	d_sleep_unblock = 1'b0;
	d_fence_i = 1'b0;
	// Note this funct3/funct7 are valid only for 32-bit instructions. They
	// are useful for clusters of related ALU ops, such as sh*add, clmul.
	d_funct3_32b = fd_cir[14:12];
	d_funct7_32b = fd_cir[31:25];

	casez (d_instr)
	`RVOPC_BEQ:       begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_rd = X0; d_aluop = ALUOP_SUB; d_branchcond = BCOND_ZERO;  end
	`RVOPC_BNE:       begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_rd = X0; d_aluop = ALUOP_SUB; d_branchcond = BCOND_NZERO; end
	`RVOPC_BLT:       begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_rd = X0; d_aluop = ALUOP_LT;  d_branchcond = BCOND_NZERO; end
	`RVOPC_BGE:       begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_rd = X0; d_aluop = ALUOP_LT;  d_branchcond = BCOND_ZERO; end
	`RVOPC_BLTU:      begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_rd = X0; d_aluop = ALUOP_LTU; d_branchcond = BCOND_NZERO; end
	`RVOPC_BGEU:      begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_rd = X0; d_aluop = ALUOP_LTU; d_branchcond = BCOND_ZERO; end
	`RVOPC_JALR:      begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_branchcond = BCOND_ALWAYS; d_addr_is_regoffs = 1'b1; d_rs2 = X0; d_aluop = ALUOP_ADD; d_alusrc_a = ALUSRCA_PC; d_alusrc_b = ALUSRCB_IMM; d_imm = d_instr_is_32bit ? 32'h4 : 32'h2; end
	`RVOPC_JAL:       begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_branchcond = BCOND_ALWAYS; d_rs1 = X0;               d_rs2 = X0; d_aluop = ALUOP_ADD; d_alusrc_a = ALUSRCA_PC; d_alusrc_b = ALUSRCB_IMM; d_imm = d_instr_is_32bit ? 32'h4 : 32'h2; end
	`RVOPC_LUI:       begin d_aluop = ALUOP_RS2; d_imm = d_imm_u; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; d_rs1 = X0; end
	`RVOPC_AUIPC:     begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_aluop = ALUOP_ADD; d_imm = d_imm_u; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; d_alusrc_a = ALUSRCA_PC;  d_rs1 = X0; end
	`RVOPC_ADDI:      begin d_aluop = ALUOP_ADD; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	`RVOPC_SLLI:      begin d_aluop = ALUOP_SLL; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	`RVOPC_SLTI:      begin d_aluop = ALUOP_LT;  d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	`RVOPC_SLTIU:     begin d_aluop = ALUOP_LTU; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	`RVOPC_XORI:      begin d_aluop = ALUOP_XOR; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	`RVOPC_SRLI:      begin d_aluop = ALUOP_SRL; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	`RVOPC_SRAI:      begin d_aluop = ALUOP_SRA; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	`RVOPC_ORI:       begin d_aluop = ALUOP_OR;  d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	`RVOPC_ANDI:      begin d_aluop = ALUOP_AND; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; d_rs2 = X0; end
	`RVOPC_ADD:       begin d_aluop = ALUOP_ADD; end
	`RVOPC_SUB:       begin d_aluop = ALUOP_SUB; end
	`RVOPC_SLL:       begin d_aluop = ALUOP_SLL; end
	`RVOPC_SLTU:      begin d_aluop = ALUOP_LTU; end
	`RVOPC_XOR:       begin d_aluop = ALUOP_XOR; end
	`RVOPC_SRL:       begin d_aluop = ALUOP_SRL; end
	`RVOPC_SRA:       begin d_aluop = ALUOP_SRA; end
	`RVOPC_OR:        begin d_aluop = ALUOP_OR;  end
	`RVOPC_AND:       begin d_aluop = ALUOP_AND; end
	`RVOPC_LB:        begin d_addr_is_regoffs = 1'b1; d_rs2 = X0; d_memop = MEMOP_LB;  end
	`RVOPC_LH:        begin d_addr_is_regoffs = 1'b1; d_rs2 = X0; d_memop = MEMOP_LH;  end
	`RVOPC_LW:        begin d_addr_is_regoffs = 1'b1; d_rs2 = X0; d_memop = MEMOP_LW;  end
	`RVOPC_LBU:       begin d_addr_is_regoffs = 1'b1; d_rs2 = X0; d_memop = MEMOP_LBU; end
	`RVOPC_LHU:       begin d_addr_is_regoffs = 1'b1; d_rs2 = X0; d_memop = MEMOP_LHU; end
	`RVOPC_SB:        begin d_addr_is_regoffs = 1'b1; d_aluop = ALUOP_RS2; d_memop = MEMOP_SB;  d_rd = X0; end
	`RVOPC_SH:        begin d_addr_is_regoffs = 1'b1; d_aluop = ALUOP_RS2; d_memop = MEMOP_SH;  d_rd = X0; end
	`RVOPC_SW:        begin d_addr_is_regoffs = 1'b1; d_aluop = ALUOP_RS2; d_memop = MEMOP_SW;  d_rd = X0; end

	`RVOPC_SLT:       begin
		d_aluop = ALUOP_LT;
		if (|EXTENSION_XH3POWER && ~|d_rd && ~|d_rs1) begin
			if (d_rs2 == 5'h00) begin
				// h3.block (power management hint)
				d_invalid_32bit = trap_wfi;
				d_sleep_block = !trap_wfi;
			end else if (d_rs2 == 5'h01) begin
				// h3.unblock (power management hint)
				d_invalid_32bit = trap_wfi;
				d_sleep_unblock = !trap_wfi;
			end
		end
	end

	`RVOPC_MUL:       if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_MUL;    end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_MULH:      if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_MULH;   end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_MULHSU:    if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_MULHSU; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_MULHU:     if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_MULHU;  end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_DIV:       if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_DIV;    end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_DIVU:      if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_DIVU;   end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_REM:       if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_REM;    end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_REMU:      if (EXTENSION_M) begin d_aluop = ALUOP_MULDIV; d_mulop = M_OP_REMU;   end else begin d_invalid_32bit = 1'b1; end

	`RVOPC_LR_W:      if (EXTENSION_A) begin d_addr_is_regoffs = 1'b1; d_memop = MEMOP_LR_W; d_rs2 = X0;           end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_SC_W:      if (EXTENSION_A) begin d_addr_is_regoffs = 1'b1; d_memop = MEMOP_SC_W; d_aluop = ALUOP_RS2;  end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_AMOSWAP_W: if (EXTENSION_A) begin d_addr_is_regoffs = 1'b1; d_memop = MEMOP_AMO;  d_aluop = ALUOP_RS2;  end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_AMOADD_W:  if (EXTENSION_A) begin d_addr_is_regoffs = 1'b1; d_memop = MEMOP_AMO;  d_aluop = ALUOP_ADD;  end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_AMOXOR_W:  if (EXTENSION_A) begin d_addr_is_regoffs = 1'b1; d_memop = MEMOP_AMO;  d_aluop = ALUOP_XOR;  end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_AMOAND_W:  if (EXTENSION_A) begin d_addr_is_regoffs = 1'b1; d_memop = MEMOP_AMO;  d_aluop = ALUOP_AND;  end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_AMOOR_W:   if (EXTENSION_A) begin d_addr_is_regoffs = 1'b1; d_memop = MEMOP_AMO;  d_aluop = ALUOP_OR;   end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_AMOMIN_W:  if (EXTENSION_A) begin d_addr_is_regoffs = 1'b1; d_memop = MEMOP_AMO;  d_aluop = ALUOP_MIN;  end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_AMOMAX_W:  if (EXTENSION_A) begin d_addr_is_regoffs = 1'b1; d_memop = MEMOP_AMO;  d_aluop = ALUOP_MAX;  end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_AMOMINU_W: if (EXTENSION_A) begin d_addr_is_regoffs = 1'b1; d_memop = MEMOP_AMO;  d_aluop = ALUOP_MINU; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_AMOMAXU_W: if (EXTENSION_A) begin d_addr_is_regoffs = 1'b1; d_memop = MEMOP_AMO;  d_aluop = ALUOP_MAXU; end else begin d_invalid_32bit = 1'b1; end

	`RVOPC_SH1ADD:    if (EXTENSION_ZBA)  begin d_aluop = ALUOP_SHXADD;                                                        end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_SH2ADD:    if (EXTENSION_ZBA)  begin d_aluop = ALUOP_SHXADD;                                                        end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_SH3ADD:    if (EXTENSION_ZBA)  begin d_aluop = ALUOP_SHXADD;                                                        end else begin d_invalid_32bit = 1'b1; end

	`RVOPC_ANDN:      if (EXTENSION_ZBB)  begin d_aluop = ALUOP_ANDN;                                                          end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_CLZ:       if (EXTENSION_ZBB)  begin d_aluop = ALUOP_CLZ;    d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_CPOP:      if (EXTENSION_ZBB)  begin d_aluop = ALUOP_CPOP;   d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_CTZ:       if (EXTENSION_ZBB)  begin d_aluop = ALUOP_CTZ;    d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_MAX:       if (EXTENSION_ZBB)  begin d_aluop = ALUOP_MAX;                                                           end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_MAXU:      if (EXTENSION_ZBB)  begin d_aluop = ALUOP_MAXU;                                                          end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_MIN:       if (EXTENSION_ZBB)  begin d_aluop = ALUOP_MIN;                                                           end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_MINU:      if (EXTENSION_ZBB)  begin d_aluop = ALUOP_MINU;                                                          end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_ORC_B:     if (EXTENSION_ZBB)  begin d_aluop = ALUOP_ORC_B;  d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_ORN:       if (EXTENSION_ZBB)  begin d_aluop = ALUOP_ORN;                                                           end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_REV8:      if (EXTENSION_ZBB)  begin d_aluop = ALUOP_REV8;   d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_ROL:       if (EXTENSION_ZBB)  begin d_aluop = ALUOP_ROL;                                                           end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_ROR:       if (EXTENSION_ZBB)  begin d_aluop = ALUOP_ROR;                                                           end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_RORI:      if (EXTENSION_ZBB)  begin d_aluop = ALUOP_ROR;    d_rs2 = X0; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_SEXT_B:    if (EXTENSION_ZBB)  begin d_aluop = ALUOP_SEXT_B; d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_SEXT_H:    if (EXTENSION_ZBB)  begin d_aluop = ALUOP_SEXT_H; d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_XNOR:      if (EXTENSION_ZBB)  begin d_aluop = ALUOP_XNOR;                                                          end else begin d_invalid_32bit = 1'b1; end
	// Note: ZEXT_H is a subset of PACK from Zbkb. This is fine as long as
	// this case appears first, since Zbkb implies Zbb on Hazard3.
	`RVOPC_ZEXT_H:    if (EXTENSION_ZBB)  begin d_aluop = ALUOP_ZEXT_H; d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end

	`RVOPC_CLMUL:     if (EXTENSION_ZBC)  begin d_aluop = ALUOP_CLMUL;                                                         end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_CLMULH:    if (EXTENSION_ZBC)  begin d_aluop = ALUOP_CLMUL;                                                         end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_CLMULR:    if (EXTENSION_ZBC)  begin d_aluop = ALUOP_CLMUL;                                                         end else begin d_invalid_32bit = 1'b1; end

	`RVOPC_BCLR:      if (EXTENSION_ZBS)  begin d_aluop = ALUOP_BCLR;                                                          end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_BCLRI:     if (EXTENSION_ZBS)  begin d_aluop = ALUOP_BCLR;   d_rs2 = X0; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_BEXT:      if (EXTENSION_ZBS)  begin d_aluop = ALUOP_BEXT;                                                          end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_BEXTI:     if (EXTENSION_ZBS)  begin d_aluop = ALUOP_BEXT;   d_rs2 = X0; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_BINV:      if (EXTENSION_ZBS)  begin d_aluop = ALUOP_BINV;                                                          end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_BINVI:     if (EXTENSION_ZBS)  begin d_aluop = ALUOP_BINV;   d_rs2 = X0; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_BSET:      if (EXTENSION_ZBS)  begin d_aluop = ALUOP_BSET;                                                          end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_BSETI:     if (EXTENSION_ZBS)  begin d_aluop = ALUOP_BSET;   d_rs2 = X0; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; end else begin d_invalid_32bit = 1'b1; end

	`RVOPC_PACK:      if (EXTENSION_ZBKB) begin d_aluop = ALUOP_PACK;                                                          end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_PACKH:     if (EXTENSION_ZBKB) begin d_aluop = ALUOP_PACKH;                                                         end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_BREV8:     if (EXTENSION_ZBKB) begin d_aluop = ALUOP_BREV8;  d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_UNZIP:     if (EXTENSION_ZBKB) begin d_aluop = ALUOP_UNZIP;  d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_ZIP:       if (EXTENSION_ZBKB) begin d_aluop = ALUOP_ZIP;    d_rs2 = X0;                                            end else begin d_invalid_32bit = 1'b1; end

	`RVOPC_H3_BEXTM:  if (EXTENSION_XH3BEXTM) begin d_aluop = ALUOP_BEXTM;                                                         end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_H3_BEXTMI: if (EXTENSION_XH3BEXTM) begin d_aluop = ALUOP_BEXTM;  d_rs2 = X0; d_imm = d_imm_i; d_alusrc_b = ALUSRCB_IMM; end else begin d_invalid_32bit = 1'b1; end

	`RVOPC_FENCE:     begin d_rs2 = X0; end  // NOP, note rs1/rd are zero in instruction
	`RVOPC_FENCE_I:   if (EXTENSION_ZIFENCEI)    begin d_invalid_32bit = DEBUG_SUPPORT && debug_mode; d_branchcond = BCOND_ALWAYS; d_fence_i = 1'b1; end else begin d_invalid_32bit = 1'b1; end // note rs1/rs2/rd are zero in instruction
	`RVOPC_CSRRW:     if (HAVE_CSR)              begin d_imm = d_imm_i; d_csr_wen = 1'b1  ; d_csr_ren = |d_rd; d_csr_wtype = CSR_WTYPE_W; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_CSRRS:     if (HAVE_CSR)              begin d_imm = d_imm_i; d_csr_wen = |d_rs1; d_csr_ren = 1'b1 ; d_csr_wtype = CSR_WTYPE_S; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_CSRRC:     if (HAVE_CSR)              begin d_imm = d_imm_i; d_csr_wen = |d_rs1; d_csr_ren = 1'b1 ; d_csr_wtype = CSR_WTYPE_C; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_CSRRWI:    if (HAVE_CSR)              begin d_imm = d_imm_i; d_csr_wen = 1'b1  ; d_csr_ren = |d_rd; d_csr_wtype = CSR_WTYPE_W; d_csr_w_imm = 1'b1; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_CSRRSI:    if (HAVE_CSR)              begin d_imm = d_imm_i; d_csr_wen = |d_rs1; d_csr_ren = 1'b1 ; d_csr_wtype = CSR_WTYPE_S; d_csr_w_imm = 1'b1; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_CSRRCI:    if (HAVE_CSR)              begin d_imm = d_imm_i; d_csr_wen = |d_rs1; d_csr_ren = 1'b1 ; d_csr_wtype = CSR_WTYPE_C; d_csr_w_imm = 1'b1; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_ECALL:     if (HAVE_CSR)              begin d_except = m_mode || !U_MODE ? EXCEPT_ECALL_M : EXCEPT_ECALL_U;  d_rs2 = X0; d_rs1 = X0; d_rd = X0; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_EBREAK:    if (HAVE_CSR)              begin d_except = EXCEPT_EBREAK; d_rs2 = X0; d_rs1 = X0; d_rd = X0; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_MRET:      if (HAVE_CSR && m_mode)    begin d_except = EXCEPT_MRET;   d_rs2 = X0; d_rs1 = X0; d_rd = X0; end else begin d_invalid_32bit = 1'b1; end
	`RVOPC_WFI:       if (HAVE_CSR && !trap_wfi) begin d_sleep_wfi = 1'b1;       d_rs2 = X0; d_rs1 = X0; d_rd = X0; end else begin d_invalid_32bit = 1'b1; end

	default:      begin d_invalid_32bit = 1'b1; end
	endcase

	if (d_invalid || d_starved || d_except_instr_bus_fault || partial_predicted_branch) begin
		d_rs1             = {W_REGADDR{1'b0}};
		d_rs2             = {W_REGADDR{1'b0}};
		d_rd              = {W_REGADDR{1'b0}};
		d_memop           = MEMOP_NONE;
		d_branchcond      = BCOND_NEVER;
		d_csr_ren         = 1'b0;
		d_csr_wen         = 1'b0;
		d_except          = EXCEPT_NONE;
		d_sleep_wfi       = 1'b0;
		d_sleep_block     = 1'b0;
		d_sleep_unblock   = 1'b0;
		// Ensure address bus is 0 in reset if register file is resettable:
		d_addr_is_regoffs = 1'b1;

		if (EXTENSION_M)
			d_aluop = ALUOP_ADD;

		if (d_except_instr_bus_fault)
			d_except = EXCEPT_INSTR_FAULT;
		else if (d_invalid && !d_starved)
			d_except = EXCEPT_INSTR_ILLEGAL;
	end
	if (partial_predicted_branch) begin
		d_addr_is_regoffs = 1'b0;
		d_branchcond = BCOND_ALWAYS;
	end
	if (cir_lock_prev) begin
		d_branchcond = BCOND_NEVER;
	end
end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
