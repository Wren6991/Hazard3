/*****************************************************************************\
|                      Copyright (C) 2021-2023 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module hazard3_core #(
`include "hazard3_config.vh"
,
`include "hazard3_width_const.vh"
) (
	// Global signals
	input wire                 clk,
	input wire                 clk_always_on,
	input wire                 rst_n,

	// Power control signals
	output wire                pwrup_req,
	input  wire                pwrup_ack,
	output wire                clk_en,
	output reg                 unblock_out,
	input  wire                unblock_in,

	`ifdef RISCV_FORMAL
	`RVFI_OUTPUTS ,
	`endif

	// Instruction fetch port
	output wire                bus_aph_req_i,
	output wire                bus_aph_panic_i, // e.g. branch mispredict + flush
	input  wire                bus_aph_ready_i,
	input  wire                bus_dph_ready_i,
	input  wire                bus_dph_err_i,

	output wire [W_ADDR-1:0]   bus_haddr_i,
	output wire [2:0]          bus_hsize_i,
	output wire                bus_priv_i,
	input  wire [W_DATA-1:0]   bus_rdata_i,

	// Load/store port
	output reg                 bus_aph_req_d,
	output wire                bus_aph_excl_d,
	input  wire                bus_aph_ready_d,
	input  wire                bus_dph_ready_d,
	input  wire                bus_dph_err_d,
	input  wire                bus_dph_exokay_d,

	output reg  [W_ADDR-1:0]   bus_haddr_d,
	output reg  [2:0]          bus_hsize_d,
	output reg                 bus_priv_d,
	output reg                 bus_hwrite_d,
	output reg  [W_DATA-1:0]   bus_wdata_d,
	input  wire [W_DATA-1:0]   bus_rdata_d,

	// Debugger run/halt control
	input  wire                dbg_req_halt,
	input  wire                dbg_req_halt_on_reset,
	input  wire                dbg_req_resume,
	output wire                dbg_halted,
	output wire                dbg_running,
	// Debugger access to data0 CSR
	input  wire [W_DATA-1:0]   dbg_data0_rdata,
	output wire [W_DATA-1:0]   dbg_data0_wdata,
	output wire                dbg_data0_wen,
	// Debugger instruction injection
	input  wire [W_DATA-1:0]   dbg_instr_data,
	input  wire                dbg_instr_data_vld,
	output wire                dbg_instr_data_rdy,
	output wire                dbg_instr_caught_exception,
	output wire                dbg_instr_caught_ebreak,

	// Level-sensitive interrupt sources
	input  wire [NUM_IRQS-1:0] irq,       // -> mip.meip
	input  wire                soft_irq,  // -> mip.msip
	input  wire                timer_irq  // -> mip.mtip
);

`include "hazard3_ops.vh"

wire x_stall;
wire m_stall;

localparam HSIZE_WORD  = 3'd2;
localparam HSIZE_HWORD = 3'd1;
localparam HSIZE_BYTE  = 3'd0;

wire debug_mode;
assign dbg_halted = DEBUG_SUPPORT && debug_mode;
assign dbg_running = DEBUG_SUPPORT && !debug_mode;

// ----------------------------------------------------------------------------
// Pipe Stage F

wire                 f_jump_req;
wire [W_ADDR-1:0]    f_jump_target;
wire                 f_jump_priv;
wire                 f_jump_rdy;
wire                 f_jump_now = f_jump_req && f_jump_rdy;

wire                 f_frontend_pwrdown_ok;

// Predecoded register numbers, for register file access
wire [W_REGADDR-1:0] f_rs1_coarse;
wire [W_REGADDR-1:0] f_rs2_coarse;
wire [W_REGADDR-1:0] f_rs1_fine;
wire [W_REGADDR-1:0] f_rs2_fine;

wire [31:0]          fd_cir;
wire [1:0]           fd_cir_err;
wire [1:0]           fd_cir_predbranch;
wire [1:0]           fd_cir_vld;
wire [1:0]           df_cir_use;
wire                 df_cir_flush_behind;
wire [3:0]           df_uop_step_next;

wire                 x_btb_set;
wire [W_ADDR-1:0]    x_btb_set_src_addr;
wire                 x_btb_set_src_size;
wire [W_ADDR-1:0]    x_btb_set_target_addr;
wire                 x_btb_clear;

wire [W_ADDR-1:0]    d_btb_target_addr;

assign bus_aph_panic_i = 1'b0;

wire f_mem_size;
assign bus_hsize_i = f_mem_size ? HSIZE_WORD : HSIZE_HWORD;

hazard3_frontend #(
`include "hazard3_config_inst.vh"
) frontend (
	.clk                  (clk),
	.rst_n                (rst_n),

	.mem_size             (f_mem_size),
	.mem_addr             (bus_haddr_i),
	.mem_priv             (bus_priv_i),
	.mem_addr_vld         (bus_aph_req_i),
	.mem_addr_rdy         (bus_aph_ready_i),

	.mem_data             (bus_rdata_i),
	.mem_data_err         (bus_dph_err_i),
	.mem_data_vld         (bus_dph_ready_i),

	.jump_target          (f_jump_target),
	.jump_priv            (f_jump_priv),
	.jump_target_vld      (f_jump_req),
	.jump_target_rdy      (f_jump_rdy),

	.btb_set              (x_btb_set),
	.btb_set_src_addr     (x_btb_set_src_addr),
	.btb_set_src_size     (x_btb_set_src_size),
	.btb_set_target_addr  (x_btb_set_target_addr),
	.btb_clear            (x_btb_clear),
	.btb_target_addr_out  (d_btb_target_addr),

	.cir                  (fd_cir),
	.cir_err              (fd_cir_err),
	.cir_predbranch       (fd_cir_predbranch),
	.cir_vld              (fd_cir_vld),
	.cir_use              (df_cir_use),
	.cir_flush_behind     (df_cir_flush_behind),
	.df_uop_step_next     (df_uop_step_next),

	.pwrdown_ok           (f_frontend_pwrdown_ok),
	.delay_first_fetch    (!pwrup_ack),

	.predecode_rs1_coarse (f_rs1_coarse),
	.predecode_rs2_coarse (f_rs2_coarse),
	.predecode_rs1_fine   (f_rs1_fine),
	.predecode_rs2_fine   (f_rs2_fine),

	.debug_mode           (debug_mode),
	.dbg_instr_data       (dbg_instr_data),
	.dbg_instr_data_vld   (dbg_instr_data_vld),
	.dbg_instr_data_rdy   (dbg_instr_data_rdy)
);

// ----------------------------------------------------------------------------
// Pipe Stage X (Decode Logic)

// X-check on pieces of instruction which frontend claims are valid
`ifdef HAZARD3_X_CHECKS
always @ (posedge clk) begin
	if (rst_n) begin
		if (|fd_cir_vld && (^fd_cir[15:0] === 1'bx)) begin
			$display("CIR LSBs are X, should be valid!");
			$finish;
		end
		if (fd_cir_vld[1] && (^fd_cir === 1'bX)) begin
			$display("CIR contains X, should be fully valid!");
			$finish;
		end
	end
end
`endif

// To X
wire                 d_starved;
wire [W_DATA-1:0]    d_imm;
wire [W_REGADDR-1:0] d_rs1;
wire [W_REGADDR-1:0] d_rs2;
wire [W_REGADDR-1:0] d_rd;
wire [2:0]           d_funct3_32b;
wire [6:0]           d_funct7_32b;
wire [W_ALUSRC-1:0]  d_alusrc_a;
wire [W_ALUSRC-1:0]  d_alusrc_b;
wire [W_ALUOP-1:0]   d_aluop;
wire [W_MEMOP-1:0]   d_memop;
wire [W_MULOP-1:0]   d_mulop;
wire [W_BCOND-1:0]   d_branchcond;
wire [W_ADDR-1:0]    d_addr_offs;
wire                 d_addr_is_regoffs;
wire [W_ADDR-1:0]    d_pc;
wire [W_EXCEPT-1:0]  d_except;
wire                 d_sleep_wfi;
wire                 d_sleep_block;
wire                 d_sleep_unblock;
wire                 d_no_pc_increment;
wire                 d_uninterruptible;
wire                 d_fence_i;
wire                 d_csr_ren;
wire                 d_csr_wen;
wire [1:0]           d_csr_wtype;
wire                 d_csr_w_imm;

wire                 x_jump_not_except;
wire                 x_mmode_execution;
wire                 x_trap_wfi;

wire [W_ADDR-1:0]    debug_dpc_wdata;
wire                 debug_dpc_wen;
wire [W_ADDR-1:0]    debug_dpc_rdata;

hazard3_decode #(
`include "hazard3_config_inst.vh"
) decode_u (
	.clk                  (clk),
	.rst_n                (rst_n),

	.fd_cir               (fd_cir),
	.fd_cir_err           (fd_cir_err),
	.fd_cir_predbranch    (fd_cir_predbranch),
	.fd_cir_vld           (fd_cir_vld),
	.df_cir_use           (df_cir_use),
	.df_cir_flush_behind  (df_cir_flush_behind),
	.df_uop_step_next     (df_uop_step_next),
	.d_pc                 (d_pc),
	.x_jump_not_except    (x_jump_not_except),

	.debug_mode           (debug_mode),
	.m_mode               (x_mmode_execution),
	.trap_wfi             (x_trap_wfi),

	.debug_dpc_wdata      (debug_dpc_wdata),
	.debug_dpc_wen        (debug_dpc_wen),
	.debug_dpc_rdata      (debug_dpc_rdata),

	.d_starved            (d_starved),
	.x_stall              (x_stall),
	.f_jump_now           (f_jump_now),
	.f_jump_target        (f_jump_target),
	.d_btb_target_addr    (d_btb_target_addr),

	.d_imm                (d_imm),
	.d_rs1                (d_rs1),
	.d_rs2                (d_rs2),
	.d_rd                 (d_rd),
	.d_funct3_32b         (d_funct3_32b),
	.d_funct7_32b         (d_funct7_32b),
	.d_alusrc_a           (d_alusrc_a),
	.d_alusrc_b           (d_alusrc_b),
	.d_aluop              (d_aluop),
	.d_memop              (d_memop),
	.d_mulop              (d_mulop),
	.d_csr_ren            (d_csr_ren),
	.d_csr_wen            (d_csr_wen),
	.d_csr_wtype          (d_csr_wtype),
	.d_csr_w_imm          (d_csr_w_imm),
	.d_branchcond         (d_branchcond),
	.d_addr_offs          (d_addr_offs),
	.d_addr_is_regoffs    (d_addr_is_regoffs),
	.d_except             (d_except),
	.d_sleep_wfi          (d_sleep_wfi),
	.d_sleep_block        (d_sleep_block),
	.d_sleep_unblock      (d_sleep_unblock),
	.d_no_pc_increment    (d_no_pc_increment),
	.d_uninterruptible    (d_uninterruptible),
	.d_fence_i            (d_fence_i)
);

// ----------------------------------------------------------------------------
// Pipe Stage X (Execution Logic)

// Register the write which took place to the regfile on previous cycle, and bypass.
// This is an alternative to a write -> read bypass in the regfile,
// which we can't implement whilst maintaining BRAM inference compatibility (iCE40).
reg  [W_REGADDR-1:0] mw_rd;
reg  [W_DATA-1:0]    mw_result;

// From register file:
wire [W_DATA-1:0]    x_rdata1;
wire [W_DATA-1:0]    x_rdata2;

// Combinational regs for muxing
reg   [W_DATA-1:0]   x_rs1_bypass;
reg   [W_DATA-1:0]   x_rs2_bypass;
reg   [W_DATA-1:0]   x_op_a;
reg   [W_DATA-1:0]   x_op_b;
wire  [W_DATA-1:0]   x_alu_result;
wire                 x_alu_cmp;

wire [W_DATA-1:0]    m_trap_addr;
wire                 m_trap_is_irq;
wire                 m_trap_is_debug_entry;
wire                 m_trap_enter_vld;
wire                 m_trap_enter_soon;
wire                 m_trap_enter_rdy = f_jump_rdy;

wire                 x_mmode_loadstore;
wire                 m_mmode_trap_entry;

reg  [W_REGADDR-1:0] xm_rs1;
reg  [W_REGADDR-1:0] xm_rs2;
reg  [W_REGADDR-1:0] xm_rd;
reg  [W_DATA-1:0]    xm_result;
reg  [1:0]           xm_addr_align;
reg  [W_MEMOP-1:0]   xm_memop;
reg  [W_EXCEPT-1:0]  xm_except;
reg                  xm_except_to_d_mode;
reg                  xm_no_pc_increment;
reg                  xm_sleep_wfi;
reg                  xm_sleep_block;
reg                  xm_delay_irq_entry_on_ls_stagex;

// ----------------------------------------------------------------------------
// Stall logic

// IRQs squeeze in between the instructions in X and M, so in this case X
// stalls but M can continue. -> X always stalls on M trap, M *may* stall.
wire x_stall_on_trap = m_trap_enter_vld && !m_trap_enter_rdy ||
	m_trap_enter_soon && !m_trap_enter_vld;

// Stall inserted to avoid illegal pipelining of exclusive accesses on the bus
// (also gives time to update local monitor on direct lr.w -> sc.w instruction
// sequences). Note we don't check for AMOs in stage M, because AMOs fully
// fence off on their own completion before passing down the pipe.

wire d_memop_is_amo = |EXTENSION_A && d_memop == MEMOP_AMO;

wire x_stall_on_exclusive_overlap = |EXTENSION_A && (
	(d_memop_is_amo || d_memop == MEMOP_SC_W || d_memop == MEMOP_LR_W) &&
	(xm_memop == MEMOP_SC_W || xm_memop	== MEMOP_LR_W)
);

// AMOs are issued completely from X. We keep X stalled, and pass bubbles into
// M. Otherwise the exception handling would be even more of a mess. Phases
// 0-3 are read/write address/data phases. Phase 4 is error, due to HRESP or
// due to low HEXOKAY response to read.

// Also need to clear AMO if it follows an excepting instruction. Note we
// still stall on phase 3 when hready is high if hresp is also high, since we
// then proceed to phase 4 for the error response.

reg [2:0] x_amo_phase;
wire x_stall_on_amo = |EXTENSION_A && d_memop_is_amo && !m_trap_enter_soon && (
	x_amo_phase < 3'h3 || (x_amo_phase == 3'h3 && (!bus_dph_ready_d || !bus_dph_exokay_d || bus_dph_err_d))
);

// Read-after-write hazard detection (e.g. load-use)

wire m_fast_mul_result_vld;
wire m_generating_result =
	xm_memop < MEMOP_SW ||
	|EXTENSION_A && xm_memop == MEMOP_LR_W ||
	|EXTENSION_A && xm_memop == MEMOP_SC_W || // sc.w success result is data phase
	|EXTENSION_M && m_fast_mul_result_vld;

reg x_stall_on_raw;

always @ (*) begin
	x_stall_on_raw = 1'b0;
	if (REDUCED_BYPASS) begin
		x_stall_on_raw =
			|xm_rd && (xm_rd == d_rs1 || xm_rd == d_rs2) ||
			|mw_rd && (mw_rd == d_rs1 || mw_rd == d_rs2);
	end else if (m_generating_result) begin
		// With the full bypass network, load-use (or fast multiply-use) is the only RAW stall
		if (|xm_rd && xm_rd == d_rs1) begin
			// Store addresses cannot be bypassed later, so there is no exception here.
			x_stall_on_raw = 1'b1;
		end else if (|xm_rd && xm_rd == d_rs2) begin
			// Store data can be bypassed in M. Any other instructions must stall.
			x_stall_on_raw = !(d_memop == MEMOP_SW || d_memop == MEMOP_SH || d_memop == MEMOP_SB);
		end
	end
end

wire x_stall_muldiv;
wire x_jump_req;

assign x_stall =
	m_stall ||
	x_stall_on_trap ||
	x_stall_on_exclusive_overlap ||
	x_stall_on_amo ||
	x_stall_on_raw ||
	x_stall_muldiv ||
	bus_aph_req_d && !bus_aph_ready_d ||
	x_jump_req && !f_jump_rdy;

wire m_sleep_stall_release;

wire x_loadstore_pmp_fail;
wire x_exec_pmp_fail;
wire x_trig_break;
wire x_trig_break_d_mode;

// ----------------------------------------------------------------------------
// Execution logic

// ALU, operand muxes and bypass

// Approximate regnums were predecoded in stage 1, for regfile read.
// (Approximate in the sense that they are invalid when the instruction
// doesn't *have* a register operand on that port.) These aren't usable for
// hazard checking but are fine for bypass, and make the bypass mux
// independent of stage 2 decode.

reg [W_REGADDR-1:0] d_rs1_predecoded;
reg [W_REGADDR-1:0] d_rs2_predecoded;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		d_rs1_predecoded <= {W_REGADDR{1'b0}};
		d_rs2_predecoded <= {W_REGADDR{1'b0}};
	end else if (d_starved || !x_stall) begin
		d_rs1_predecoded <= f_rs1_fine;
		d_rs2_predecoded <= f_rs2_fine;
	end
end

`ifdef HAZARD3_ASSERTIONS
always @ (posedge clk) if (rst_n && !x_stall) begin
	// If stage 2 sees a reg operand, it must have been correctly predecoded too.
	if (|d_rs1)
		assert(d_rs1_predecoded == d_rs1);
	if (|d_rs2)
		assert(d_rs2_predecoded == d_rs2);
	// If no reg was predecoded, stage 2 decode must agree there is no reg operand.
	if (~|d_rs1_predecoded)
		assert(~|d_rs1);
	if (~|d_rs2_predecoded)
		assert(~|d_rs2);
end
`endif

always @ (*) begin
	if (~|d_rs1_predecoded) begin
		x_rs1_bypass = {W_DATA{1'b0}};
	end else if (xm_rd == d_rs1_predecoded) begin
		x_rs1_bypass = xm_result;
	end else if (mw_rd == d_rs1_predecoded && !REDUCED_BYPASS) begin
		x_rs1_bypass = mw_result;
	end else begin
		x_rs1_bypass = x_rdata1;
	end
	if (~|d_rs2_predecoded) begin
		x_rs2_bypass = {W_DATA{1'b0}};
	end else if (xm_rd == d_rs2_predecoded) begin
		x_rs2_bypass = xm_result;
	end else if (mw_rd == d_rs2_predecoded && !REDUCED_BYPASS) begin
		x_rs2_bypass = mw_result;
	end else begin
		x_rs2_bypass = x_rdata2;
	end

	// AMO captures rdata into mw_result at end of read data phase, so we can
	// feed back through the ALU.
	if (|EXTENSION_A && x_amo_phase == 3'h2)
		x_op_a = mw_result;
	else if (d_alusrc_a)
		x_op_a = d_pc;
	else
		x_op_a = x_rs1_bypass;

	if (d_alusrc_b)
		x_op_b = d_imm;
	else
		x_op_b = x_rs2_bypass;
end

hazard3_alu #(
`include "hazard3_config_inst.vh"
) alu (
	.aluop      (d_aluop),
	.funct3_32b (d_funct3_32b),
	.funct7_32b (d_funct7_32b),
	.op_a       (x_op_a),
	.op_b       (x_op_b),
	.result     (x_alu_result),
	.cmp        (x_alu_cmp)
);

// Load/store bus request

wire x_unaligned_addr = d_memop != MEMOP_NONE && (
	bus_hsize_d == HSIZE_WORD && |bus_haddr_d[1:0] ||
	bus_hsize_d == HSIZE_HWORD && bus_haddr_d[0]
);

reg mw_local_exclusive_reserved;

wire x_memop_vld = d_memop != MEMOP_NONE && !(
	|EXTENSION_A && d_memop == MEMOP_SC_W && !mw_local_exclusive_reserved ||
	|EXTENSION_A && d_memop_is_amo && x_amo_phase != 3'h0 && x_amo_phase != 3'h2
);

wire x_memop_write =
	d_memop == MEMOP_SW || d_memop == MEMOP_SH || d_memop == MEMOP_SB ||
	|EXTENSION_A && d_memop == MEMOP_SC_W ||
	|EXTENSION_A && d_memop_is_amo && x_amo_phase == 3'h2;

// Always query the global monitor, except for store-conditional suppressed by local monitor.
assign bus_aph_excl_d = |EXTENSION_A && (
	d_memop == MEMOP_LR_W ||
	d_memop == MEMOP_SC_W ||
	d_memop_is_amo
);

// AMO stalls the pipe, then generates two bus transfers per 4-cycle
// iteration, unless it bails out due to a bus fault or failed load
// reservation.
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		x_amo_phase <= 3'h0;
	end else if (|EXTENSION_A && d_memop_is_amo && (
		bus_aph_ready_d || bus_dph_ready_d ||
		m_trap_enter_vld || x_unaligned_addr ||
		x_amo_phase == 3'h4
	)) begin
		if (m_trap_enter_vld) begin
			// Bail out, squash the in-progress AMO.
			x_amo_phase <= 3'h0;
`ifdef HAZARD3_ASSERTIONS
			// Should only happen during an address phase, *or* the fault phase.
			assert(x_amo_phase == 3'h0 || x_amo_phase == 3'h2 || x_amo_phase == 3'h4);
			// The fault phase only holds when we have a misaligned AMO directly behind
			// a regular memory access that subsequently excepts, and the AMO has gone
			// straight to fault phase due to misalignment.
			if (x_amo_phase == 3'h4)
				assert(x_unaligned_addr);
`endif
		end else if (x_stall_on_raw || x_stall_on_exclusive_overlap || m_trap_enter_soon) begin
			// First address phase stalled due to address dependency on
			// previous load/mul/etc. Shouldn't be possible in later phases.
			x_amo_phase <= 3'h0;
`ifdef HAZARD3_ASSERTIONS
			assert(x_amo_phase == 3'h0);
`endif
		end else if (x_amo_phase == 3'h4) begin
			// Clear fault phase once it goes through to stage 3 and excepts
			if (!x_stall)
				x_amo_phase <= 3'h0;
`ifdef HAZARD3_ASSERTIONS
			// This should only happen when we are stalled on an older load/store etc
			assert(!(x_stall && !m_stall));
`endif
		end else if (x_unaligned_addr) begin
			x_amo_phase <= 3'h4;
		end else if (x_amo_phase == 3'h1 && !bus_dph_exokay_d) begin
			// Load reserve fail indicates the memory region does not support
			// exclusives, so we will never succeed at store. Exception.
			x_amo_phase <= 3'h4;
		end else if ((x_amo_phase == 3'h1 || x_amo_phase == 3'h3) && bus_dph_err_d) begin
			// Bus fault. Exception.
			x_amo_phase <= 3'h4;
		end else if (x_amo_phase == 3'h3) begin
			// Either we're done, or the write failed. Either way, back to the start.
			x_amo_phase <= 3'h0;
		end else begin
			// Default progression: read addr -> read data -> write addr -> write data
			x_amo_phase <= x_amo_phase + 3'h1;
		end
	end
end

`ifdef HAZARD3_ASSERTIONS
always @ (posedge clk) if (rst_n) begin
	// Other states should be unreachable
	assert(x_amo_phase <= 3'h4);
	// First state should be 0 -- don't want anything carried from one AMO to the next.
	if (x_stall_on_amo && !$past(x_stall_on_amo))
		assert(x_amo_phase == 3'h0);
	// Should be in resting state between AMOs
	if (!d_memop_is_amo)
		assert(x_amo_phase == 3'h0);
	// Error phase should have no stage 2 blockers, so it can pass to stage 3 to
	// raise exception entry. It's ok to block behind a younger instruction, but..
	if (x_amo_phase == 3'h4)
		assert(!x_stall || m_stall);
	// ..the only way to reach AMO error phase without stage 3 clearing out should
	// be an unaligned AMO address, which goes straight to error phase.
	if (x_amo_phase == 3'h4 && m_stall)
		assert(x_unaligned_addr);
	// Should be impossible to get an unaligned address in the write address
	// phase, since it would be picked up in the read address phase
	if (x_amo_phase == 3'h2)
		assert(!x_unaligned_addr);
	// Error phase is either due to a bus response, or a misaligned address.
	// Neither of these are write-address-phase.
	if (x_amo_phase == 3'h4)
		assert($past(x_amo_phase) != 3'h2);
	// Make sure M is unstalled for passing store data through in phase 2
	if (x_amo_phase == 3'h2)
		assert(!m_stall);
end
`endif

// This adder is used for both branch targets and load/store addresses.
// Supporting all branch types already requires rs1 + I-fmt, and pc + B-fmt.
// B-fmt are almost identical to S-fmt, so we rs1 + S-fmt is almost free.

wire [W_ADDR-1:0] x_addr_sum = (d_addr_is_regoffs ? x_rs1_bypass : d_pc) + d_addr_offs;

always @ (*) begin
	// Need to be careful not to use anything hready-sourced to gate htrans!
	bus_haddr_d = x_addr_sum;
	bus_hwrite_d = x_memop_write;
	bus_priv_d = x_mmode_loadstore;
	case (d_memop)
		MEMOP_LW:  bus_hsize_d = HSIZE_WORD;
		MEMOP_SW:  bus_hsize_d = HSIZE_WORD;
		MEMOP_LH:  bus_hsize_d = HSIZE_HWORD;
		MEMOP_LHU: bus_hsize_d = HSIZE_HWORD;
		MEMOP_SH:  bus_hsize_d = HSIZE_HWORD;
		MEMOP_LB:  bus_hsize_d = HSIZE_BYTE;
		MEMOP_LBU: bus_hsize_d = HSIZE_BYTE;
		MEMOP_SB:  bus_hsize_d = HSIZE_BYTE;
		default:   bus_hsize_d = HSIZE_WORD;
	endcase
	bus_aph_req_d = x_memop_vld && !(
		x_stall_on_raw ||
		x_stall_on_exclusive_overlap ||
		x_loadstore_pmp_fail ||
		x_exec_pmp_fail ||
		x_trig_break ||
		x_unaligned_addr ||
		m_trap_enter_soon ||
		((xm_sleep_wfi || xm_sleep_block) && !m_sleep_stall_release)
	);
end

// Multiply/divide

wire [W_DATA-1:0] x_muldiv_result;
wire [W_DATA-1:0] m_fast_mul_result;

wire x_use_fast_mul = d_aluop == ALUOP_MULDIV && (
	MUL_FAST  && d_mulop == M_OP_MUL   ||
	MULH_FAST && d_mulop == M_OP_MULH  ||
	MULH_FAST && d_mulop == M_OP_MULHU ||
	MULH_FAST && d_mulop == M_OP_MULHSU
);

generate
if (EXTENSION_M) begin: has_muldiv
	wire              x_muldiv_op_vld;
	wire              x_muldiv_op_rdy;
	wire              x_muldiv_result_vld;
	wire [W_DATA-1:0] x_muldiv_result_h;
	wire [W_DATA-1:0] x_muldiv_result_l;

	reg x_muldiv_posted;
	always @ (posedge clk or negedge rst_n)
		if (!rst_n)
			x_muldiv_posted <= 1'b0;
		else
			x_muldiv_posted <= (x_muldiv_posted || (x_muldiv_op_vld && x_muldiv_op_rdy)) && x_stall;

	wire x_muldiv_kill = m_trap_enter_soon;

	assign x_muldiv_op_vld = (d_aluop == ALUOP_MULDIV && !x_use_fast_mul)
		&& !(x_muldiv_posted || x_stall_on_raw || x_muldiv_kill);

	hazard3_muldiv_seq #(
	`include "hazard3_config_inst.vh"
	) muldiv (
		.clk        (clk),
		.rst_n      (rst_n),
		.op         (d_mulop),
		.op_vld     (x_muldiv_op_vld),
		.op_rdy     (x_muldiv_op_rdy),
		.op_kill    (x_muldiv_kill),
		.op_a       (x_rs1_bypass),
		.op_b       (x_rs2_bypass),

		.result_h   (x_muldiv_result_h),
		.result_l   (x_muldiv_result_l),
		.result_vld (x_muldiv_result_vld)
	);

	wire x_muldiv_result_is_high =
		d_mulop == M_OP_MULH ||
		d_mulop == M_OP_MULHSU ||
		d_mulop == M_OP_MULHU ||
		d_mulop == M_OP_REM ||
		d_mulop == M_OP_REMU;
	assign x_muldiv_result = x_muldiv_result_is_high ? x_muldiv_result_h : x_muldiv_result_l;
	assign x_stall_muldiv = x_muldiv_op_vld || !x_muldiv_result_vld;

	if (MUL_FAST) begin: has_fast_mul

		// If MUL_FASTER is set, the multiplier produces its result
		// combinatorially, so we never have to post a mul result to stage 3.
		wire x_issue_fast_mul = x_use_fast_mul && |d_rd && !x_stall && !MUL_FASTER;

		hazard3_mul_fast #(
		`include "hazard3_config_inst.vh"
		) mul_fast (
			.clk        (clk),
			.rst_n      (rst_n),

			.op_vld     (x_issue_fast_mul),
			.op         (d_mulop),
			.op_a       (x_rs1_bypass),
			.op_b       (x_rs2_bypass),

			.result     (m_fast_mul_result),
			.result_vld (m_fast_mul_result_vld)
		);

	end else begin: no_fast_mul

		assign m_fast_mul_result = {W_DATA{1'b0}};
		assign m_fast_mul_result_vld = 1'b0;

	end

`ifdef HAZARD3_ASSERTIONS
	always @ (posedge clk) if (d_aluop != ALUOP_MULDIV) assert(!x_stall_muldiv);
`endif

end else begin: no_muldiv

	assign x_muldiv_result = {W_DATA{1'b0}};
	assign m_fast_mul_result = {W_DATA{1'b0}};
	assign m_fast_mul_result_vld = 1'b0;
	assign x_stall_muldiv = 1'b0;

end
endgenerate

// Branch handling

// For JALR, the LSB of the result must be cleared by hardware
wire [W_ADDR-1:0] x_jump_target = x_addr_sum & ~32'h1;
wire              x_jump_misaligned = ~|EXTENSION_C && x_addr_sum[1];
wire              x_branch_cmp_noinvert;

wire              x_branch_was_predicted = |BRANCH_PREDICTOR && fd_cir_predbranch[0];
wire              x_branch_cmp = x_branch_cmp_noinvert ^ x_branch_was_predicted;

generate
if (~|FAST_BRANCHCMP) begin: alu_branchcmp

	assign x_branch_cmp_noinvert = x_alu_cmp;

end else begin: fast_branchcmp

	hazard3_branchcmp #(
	`include "hazard3_config_inst.vh"
	) branchcmp_u (
		.aluop (d_aluop),
		.op_a  (x_rs1_bypass),
		.op_b  (x_rs2_bypass),
		.cmp   (x_branch_cmp_noinvert)
	);

end
endgenerate

// Be careful not to take branches whose comparisons depend on a load result
wire x_jump_req_unchecked = !x_stall_on_raw && (
	d_branchcond == BCOND_ALWAYS ||
	d_branchcond == BCOND_ZERO && !x_branch_cmp ||
	d_branchcond == BCOND_NZERO && x_branch_cmp
);

assign x_jump_req = x_jump_req_unchecked && !x_jump_misaligned && !x_exec_pmp_fail && !x_trig_break;

assign x_btb_set = |BRANCH_PREDICTOR && (
	x_jump_req_unchecked && d_addr_offs[W_ADDR - 1] && !x_branch_was_predicted &&
	(d_branchcond == BCOND_NZERO || d_branchcond == BCOND_ZERO)
);

assign x_btb_clear = d_fence_i || (m_trap_enter_vld && m_trap_enter_rdy) || (|BRANCH_PREDICTOR && (
	x_branch_was_predicted && x_jump_req_unchecked
));

assign x_btb_set_src_addr = d_pc;
assign x_btb_set_target_addr = x_jump_target;
assign x_btb_set_src_size = &fd_cir[1:0];

// Memory protection

wire [11:0]       x_pmp_cfg_addr;
wire              x_pmp_cfg_wen;
wire [W_DATA-1:0] x_pmp_cfg_wdata;
wire [W_DATA-1:0] x_pmp_cfg_rdata;

generate
if (PMP_REGIONS > 0) begin: have_pmp

	wire x_loadstore_pmp_badperm;
	assign x_loadstore_pmp_fail = x_loadstore_pmp_badperm && x_memop_vld;

	hazard3_pmp #(
	`include "hazard3_config_inst.vh"
	) pmp (
		.clk              (clk),
		.rst_n            (rst_n),

		.cfg_addr         (x_pmp_cfg_addr),
		.cfg_wen          (x_pmp_cfg_wen),
		.cfg_wdata        (x_pmp_cfg_wdata),
		.cfg_rdata        (x_pmp_cfg_rdata),

		.i_addr           (d_pc),
		.i_instr_is_32bit (&fd_cir[1:0]),
		.i_m_mode         (x_mmode_execution),
		.i_kill           (x_exec_pmp_fail),

		.d_addr           (bus_haddr_d),
		.d_m_mode         (x_mmode_loadstore),
		.d_write          (bus_hwrite_d),
		.d_kill           (x_loadstore_pmp_badperm)
	);

end else begin: no_pmp

	assign x_pmp_cfg_rdata = 1'b0;
	assign x_loadstore_pmp_fail = 1'b0;
	assign x_exec_pmp_fail = 1'b0;

end
endgenerate

// Triggers

wire [11:0]       x_trig_cfg_addr;
wire              x_trig_cfg_wen;
wire [W_DATA-1:0] x_trig_cfg_wdata;
wire [W_DATA-1:0] x_trig_cfg_rdata;
wire              x_trig_m_en;

generate
if (BREAKPOINT_TRIGGERS > 0) begin: have_triggers

	hazard3_triggers #(
	`include "hazard3_config_inst.vh"
	) triggers (
		.clk              (clk),
		.rst_n            (rst_n),

		.cfg_addr         (x_trig_cfg_addr),
		.cfg_wen          (x_trig_cfg_wen),
		.cfg_wdata        (x_trig_cfg_wdata),
		.cfg_rdata        (x_trig_cfg_rdata),
		.trig_m_en        (x_trig_m_en),

		.pc               (d_pc),
		.m_mode           (x_mmode_execution),
		.d_mode           (debug_mode),

		.break_any        (x_trig_break),
		.break_d_mode     (x_trig_break_d_mode)
	);

end else begin: no_triggers

	assign x_trig_cfg_rdata = {W_DATA{1'b0}};
	assign x_trig_break = 1'b0;
	assign x_trig_break_d_mode = 1'b0;

end
endgenerate

// CSRs and Trap Handling

wire [W_DATA-1:0] x_csr_wdata = d_csr_w_imm ?
	{{W_DATA-5{1'b0}}, d_rs1} : x_rs1_bypass;

wire [W_DATA-1:0] x_csr_rdata;
wire              x_csr_illegal_access;

// "Previous" refers to next-most-recent instruction to be in D/X, i.e. the
// most recent instruction to reach stage M (which may or may not still be in M).
reg prev_instr_was_32_bit;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		xm_delay_irq_entry_on_ls_stagex <= 1'b0;
		prev_instr_was_32_bit <= 1'b0;
	end else begin
		// Must hold off IRQ if we are in the second cycle of an address phase or
		// later, since at that point the load/store can't be revoked. The IRQ is
		// taken once this load/store moves to the next stage: if another load/store
		// is chasing down the pipeline then this is immediately suppressed by the
		// IRQ entry, before its address phase can begin.

		// Also hold off on AMOs, unless the AMO is transitioning to an address
		// phase or completing. ("completing" excludes transitions to error phase.)

		xm_delay_irq_entry_on_ls_stagex <= bus_aph_req_d && !bus_aph_ready_d ||
			d_memop_is_amo && !(
				x_amo_phase == 3'h3 && bus_dph_ready_d && !bus_dph_err_d ||
				// Read reservation failure failure also generates error
				x_amo_phase == 3'h1 & bus_dph_ready_d && !bus_dph_err_d && bus_dph_exokay_d
			);

		if (!x_stall)
			prev_instr_was_32_bit <= df_cir_use == 2'd2;
	end
end

wire [W_ADDR-1:0] m_exception_return_addr;

wire [W_EXCEPT-1:0] x_except =
	x_trig_break                                             ? EXCEPT_EBREAK         :
	x_exec_pmp_fail                                          ? EXCEPT_INSTR_FAULT    :
	x_jump_req_unchecked && x_jump_misaligned                ? EXCEPT_INSTR_MISALIGN :
	x_csr_illegal_access                                     ? EXCEPT_INSTR_ILLEGAL  :
	|EXTENSION_A && x_unaligned_addr &&  d_memop_is_amo      ? EXCEPT_STORE_ALIGN    :
	|EXTENSION_A && x_amo_phase == 3'h4 && x_unaligned_addr  ? EXCEPT_STORE_ALIGN    :
	|EXTENSION_A && x_amo_phase == 3'h4                      ? EXCEPT_STORE_FAULT    :
	x_unaligned_addr &&  x_memop_write                       ? EXCEPT_STORE_ALIGN    :
	x_unaligned_addr && !x_memop_write                       ? EXCEPT_LOAD_ALIGN     :
	x_loadstore_pmp_fail && (d_memop_is_amo || bus_hwrite_d) ? EXCEPT_STORE_FAULT    :
	x_loadstore_pmp_fail                                     ? EXCEPT_LOAD_FAULT     : d_except;

// If an instruction causes an exceptional condition we do not consider it to have retired.
wire x_except_counts_as_retire =
	x_except == EXCEPT_EBREAK  ||
	x_except == EXCEPT_MRET    ||
	x_except == EXCEPT_ECALL_M ||
	x_except == EXCEPT_ECALL_U;

wire x_instr_ret = |df_cir_use && (x_except == EXCEPT_NONE || x_except_counts_as_retire);
wire m_dphase_in_flight = xm_memop != MEMOP_NONE && xm_memop != MEMOP_AMO;

// Need to delay IRQ entry on sleep exit because, for deep sleep states, we
// can't access the bus until the power handshake has completed.
wire m_delay_irq_entry = xm_delay_irq_entry_on_ls_stagex ||
	((xm_sleep_wfi || xm_sleep_block) && !m_sleep_stall_release);

wire m_pwr_allow_clkgate;
wire m_pwr_allow_power_down;
wire m_pwr_allow_sleep_on_block;
wire m_wfi_wakeup_req;

hazard3_csr #(
	.XLEN            (W_DATA),
`include "hazard3_config_inst.vh"
) csr_u (
	.clk                        (clk),
	.clk_always_on              (clk_always_on),
	.rst_n                      (rst_n),

	// Debugger signalling
	.debug_mode                 (debug_mode),
	.dbg_req_halt               (dbg_req_halt),
	.dbg_req_halt_on_reset      (dbg_req_halt_on_reset),
	.dbg_req_resume             (dbg_req_resume),

	.dbg_instr_caught_exception (dbg_instr_caught_exception),
	.dbg_instr_caught_ebreak    (dbg_instr_caught_ebreak),

	.dbg_data0_rdata            (dbg_data0_rdata),
	.dbg_data0_wdata            (dbg_data0_wdata),
	.dbg_data0_wen              (dbg_data0_wen),

	.debug_dpc_wdata            (debug_dpc_wdata),
	.debug_dpc_wen              (debug_dpc_wen),
	.debug_dpc_rdata            (debug_dpc_rdata),

	// CSR access port
	// *en_soon are early access strobes which are not a function of bus stall.
	// Can generate access faults (hence traps), but do not actually perform access.
	.addr                       (fd_cir[31:20]), // Always I-type immediate
	.wdata                      (x_csr_wdata),
	.wen_raw                    (d_csr_wen),
	.wen_soon                   (d_csr_wen && !m_trap_enter_soon),
	.wen                        (d_csr_wen && !m_trap_enter_soon && !x_stall),
	.wtype                      (d_csr_wtype),
	.rdata                      (x_csr_rdata),
	.ren_soon                   (d_csr_ren && !m_trap_enter_soon),
	.ren                        (d_csr_ren && !m_trap_enter_soon && !x_stall),
	.illegal                    (x_csr_illegal_access),

	// Trap signalling
	.trap_addr                  (m_trap_addr),
	.trap_is_irq                (m_trap_is_irq),
	.trap_is_debug_entry        (m_trap_is_debug_entry),
	.trap_enter_soon            (m_trap_enter_soon),
	.trap_enter_vld             (m_trap_enter_vld),
	.trap_enter_rdy             (m_trap_enter_rdy),
	.loadstore_dphase_pending   (m_dphase_in_flight),
	.delay_irq_entry            (m_delay_irq_entry || d_uninterruptible),
	.mepc_in                    (m_exception_return_addr),

	.pwr_allow_clkgate          (m_pwr_allow_clkgate),
	.pwr_allow_power_down       (m_pwr_allow_power_down),
	.pwr_allow_sleep_on_block   (m_pwr_allow_sleep_on_block),
	.pwr_wfi_wakeup_req         (m_wfi_wakeup_req),

	.m_mode_execution           (x_mmode_execution),
	.m_mode_loadstore           (x_mmode_loadstore),
	.m_mode_trap_entry          (m_mmode_trap_entry),

	// IRQ and exception requests
	.irq                        (irq),
	.irq_software               (soft_irq),
	.irq_timer                  (timer_irq),
	.except                     (xm_except),
	.except_to_d_mode           (xm_except_to_d_mode),

	.pmp_cfg_addr               (x_pmp_cfg_addr),
	.pmp_cfg_wen                (x_pmp_cfg_wen),
	.pmp_cfg_wdata              (x_pmp_cfg_wdata),
	.pmp_cfg_rdata              (x_pmp_cfg_rdata),

	.trig_cfg_addr              (x_trig_cfg_addr),
	.trig_cfg_wen               (x_trig_cfg_wen),
	.trig_cfg_wdata             (x_trig_cfg_wdata),
	.trig_cfg_rdata             (x_trig_cfg_rdata),
	.trig_m_en                  (x_trig_m_en),

	// Other CSR-specific signalling
	.trap_wfi                   (x_trap_wfi),
	.instr_ret                  (x_instr_ret)
);

// Pipe register

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		xm_memop <= MEMOP_NONE;
		xm_except <= EXCEPT_NONE;
		xm_except_to_d_mode <= 1'b0;
		xm_sleep_wfi <= 1'b0;
		xm_sleep_block <= 1'b0;
		unblock_out <= 1'b0;
		xm_rs1 <= {W_REGADDR{1'b0}};
		xm_rs2 <= {W_REGADDR{1'b0}};
		xm_rd <= {W_REGADDR{1'b0}};
		xm_no_pc_increment <= 1'b0;
	end else begin
		unblock_out <= 1'b0;
		if (!m_stall) begin
			xm_rs1 <= d_rs1;
			xm_rs2 <= d_rs2;
			xm_rd <= d_rd;
			// PC increment is suppressed non-final micro-ops, only needed for Zcmp:
			xm_no_pc_increment <= d_no_pc_increment && |EXTENSION_ZCMP;
			// If some X-sourced exception has squashed the address phase, need to squash the data phase too.
			xm_memop            <= x_except != EXCEPT_NONE ? MEMOP_NONE : d_memop;
			xm_except           <= x_except;
			xm_except_to_d_mode <= x_trig_break_d_mode;
			xm_sleep_wfi        <= x_except == EXCEPT_NONE && d_sleep_wfi;
			xm_sleep_block      <= x_except == EXCEPT_NONE && d_sleep_block;
			unblock_out         <= x_except == EXCEPT_NONE && d_sleep_unblock;
			// Note the d_starved term is required because it is possible
			// (e.g. PMP X permission fail) to except when the frontend is
			// starved, and we get a bad mepc if we let this jump ahead:
			if (x_stall || d_starved || m_trap_enter_soon) begin
				// Insert bubble
				xm_rd               <= {W_REGADDR{1'b0}};
				xm_memop            <= MEMOP_NONE;
				xm_except           <= EXCEPT_NONE;
				xm_except_to_d_mode <= 1'b0;
				xm_sleep_wfi        <= 1'b0;
				xm_sleep_block      <= 1'b0;
				unblock_out         <= 1'b0;
			end
`ifdef HAZARD3_ASSERTIONS
			// Assuming downstream bus is compliant, err && !stalled is the
			// last cycle of an error response, in which case this must have
			// been previously captured as an exception.
			if (bus_dph_err_d && x_amo_phase == 3'h0) begin
				assert(xm_except == EXCEPT_LOAD_FAULT || xm_except == EXCEPT_STORE_FAULT);
			end
`endif
		end else if (bus_dph_err_d) begin
			// First phase of 2-phase AHB5 error response. Pass the exception along on
			// this cycle, and on the next cycle the trap entry will be asserted,
			// suppressing any load/store that may currently be in stage X.
			xm_except <=
				|EXTENSION_A && xm_memop == MEMOP_LR_W ? EXCEPT_LOAD_FAULT :
				                xm_memop <= MEMOP_LBU  ? EXCEPT_LOAD_FAULT : EXCEPT_STORE_FAULT;
`ifdef HAZARD3_ASSERTIONS
			// There should be a bus transfer in stage 3 corresponding to this bus error
			assert(xm_memop != MEMOP_NONE);
			// We should capture this error exactly once, and if there were
			// any other source of exception then the load/store should not
			// have happened in the first place. Only exception is when the
			// entry of the load/store trap is stalled on the frontend.
			assert(xm_except == EXCEPT_NONE || (!m_trap_enter_rdy && (
				xm_except == EXCEPT_LOAD_FAULT || xm_except == EXCEPT_STORE_FAULT
			)));
			// Make sure we don't have to clear any of the other stage 3 flags
			assert(!xm_except_to_d_mode);
			assert(!xm_sleep_wfi);
			assert(!xm_sleep_block);
			assert(!unblock_out);
`endif
		end
`ifdef HAZARD3_ASSERTIONS
		// Some of the exception->ls paths are cut as they are supposed to be
		// impossible -- make sure there is no way to have a load/store that
		// is not squashed. (This includes debug entry!)
		if (m_trap_enter_vld) begin
			assert(!bus_aph_req_d);
		end
`endif
	end
end

`ifdef HAZARD3_ASSERTIONS
always @ (posedge clk) if (rst_n) begin
	// D bus errors must always squash younger load/stores
	if ($past(bus_dph_err_d && !bus_dph_ready_d))
		assert(!bus_aph_req_d);
	// Nonsensical to have an active stage 3 memop aligned with a
	// stage-2-generated exception -- ought to be squashed. The outlier is an
	// M-generated exception, i.e. a dataphase bus fault. Also AMOs are different.
	if (xm_except != EXCEPT_NONE && !(bus_dph_err_d || $past(!m_trap_enter_rdy)))
		assert(xm_memop == MEMOP_NONE || xm_memop == MEMOP_AMO);
end
`endif

// Datapath flops
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		xm_result <= {W_DATA{1'b0}};
		xm_addr_align <= 2'b00;
	end else if (!m_stall && !(|EXTENSION_A && x_amo_phase == 3'h3 && !bus_dph_ready_d)) begin
		// AMOs need special attention (of course):
		// - Steer captured read phase data in mw_result back through xm_result at end of AMO
		// - Make sure xm_result (store data) doesn't transition during stalled write dphase
		xm_result <=
			d_csr_ren                               ? x_csr_rdata       :
			|EXTENSION_A && x_amo_phase == 3'h3     ? mw_result         :
			|MUL_FASTER  && x_use_fast_mul          ? m_fast_mul_result :
			|EXTENSION_M && d_aluop == ALUOP_MULDIV ? x_muldiv_result   :
			                                          x_alu_result;
		xm_addr_align <= x_addr_sum[1:0];
	end
end

// ----------------------------------------------------------------------------
//                               Pipe Stage M

reg [W_DATA-1:0] m_rdata_pick_sext;
reg [W_DATA-1:0] m_wdata;
reg [W_DATA-1:0] m_result;

assign f_jump_req = x_jump_req || m_trap_enter_vld;
assign f_jump_target = m_trap_enter_vld	? m_trap_addr : x_jump_target;
assign f_jump_priv = m_trap_enter_vld ? m_mmode_trap_entry : x_mmode_execution;
assign x_jump_not_except = !m_trap_enter_vld;

// Stalls and sleep control

// EXCEPT_NONE clause is needed in the following sequence:
// - Cycle 0: hresp asserted, hready low. We set the exception to squash behind us. Bus stall high.
// - Cycle 1: hready high. For whatever reason, the frontend can't accept the trap address this cycle.
// - Cycle 2: Our dataphase has ended, so bus_dph_ready_d doesn't pulse again. m_bus_stall stuck high.
wire m_bus_stall = m_dphase_in_flight && !bus_dph_ready_d && xm_except == EXCEPT_NONE && !(
	|EXTENSION_A && xm_memop == MEMOP_SC_W && !mw_local_exclusive_reserved
);

assign m_stall = m_bus_stall ||
	(m_trap_enter_vld && !m_trap_enter_rdy && !m_trap_is_irq) ||
	((xm_sleep_wfi || xm_sleep_block) && !m_sleep_stall_release);

// Exception is taken against the instruction currently in M, so walk the PC
// back. IRQ is taken "in between" the instruction in M and the instruction
// in X, so set return to X program counter. Note that, if taking an
// exception, we know that the previous instruction to be in X (now in M)
// was *not* a taken branch, which is why we can just walk back the PC.
assign m_exception_return_addr = d_pc - (
	m_trap_is_irq         ? 32'h0 :
	xm_no_pc_increment    ? 32'h0 :
	prev_instr_was_32_bit ? 32'h4 : 32'h2
);

hazard3_power_ctrl power_ctrl (
	.clk_always_on          (clk_always_on),
	.rst_n                  (rst_n),

	.pwrup_req              (pwrup_req),
	.pwrup_ack              (pwrup_ack),
	.clk_en                 (clk_en),

	.allow_clkgate          (m_pwr_allow_clkgate),
	.allow_power_down       (m_pwr_allow_power_down),
	.allow_sleep_on_block   (m_pwr_allow_sleep_on_block),

	.frontend_pwrdown_ok    (f_frontend_pwrdown_ok),

	.sleeping_on_wfi        (xm_sleep_wfi),
	.wfi_wakeup_req         (m_wfi_wakeup_req),
	.sleeping_on_block      (xm_sleep_block),
	.block_wakeup_req_pulse (unblock_in),
	.stall_release          (m_sleep_stall_release)
);

// Load/store data handling

always @ (*) begin
	// Local forwarding of store data
	if (|mw_rd && xm_rs2 == mw_rd && !REDUCED_BYPASS) begin
		m_wdata = mw_result;
	end else begin
		m_wdata = xm_result;
	end
	// Replicate store data to ensure appropriate byte lane is driven
	case (xm_memop)
		MEMOP_SH: bus_wdata_d = {2{m_wdata[15:0]}};
		MEMOP_SB: bus_wdata_d = {4{m_wdata[7:0]}};
		default:  bus_wdata_d = m_wdata;
	endcase

	casez ({xm_memop, xm_addr_align[1:0]})
		{MEMOP_LH  , 2'b0z}: m_rdata_pick_sext = {{16{bus_rdata_d[15]}}, bus_rdata_d[15: 0]};
		{MEMOP_LH  , 2'b1z}: m_rdata_pick_sext = {{16{bus_rdata_d[31]}}, bus_rdata_d[31:16]};
		{MEMOP_LHU , 2'b0z}: m_rdata_pick_sext = {{16{1'b0           }}, bus_rdata_d[15: 0]};
		{MEMOP_LHU , 2'b1z}: m_rdata_pick_sext = {{16{1'b0           }}, bus_rdata_d[31:16]};
		{MEMOP_LB  , 2'b00}: m_rdata_pick_sext = {{24{bus_rdata_d[ 7]}}, bus_rdata_d[ 7: 0]};
		{MEMOP_LB  , 2'b01}: m_rdata_pick_sext = {{24{bus_rdata_d[15]}}, bus_rdata_d[15: 8]};
		{MEMOP_LB  , 2'b10}: m_rdata_pick_sext = {{24{bus_rdata_d[23]}}, bus_rdata_d[23:16]};
		{MEMOP_LB  , 2'b11}: m_rdata_pick_sext = {{24{bus_rdata_d[31]}}, bus_rdata_d[31:24]};
		{MEMOP_LBU , 2'b00}: m_rdata_pick_sext = {{24{1'b0           }}, bus_rdata_d[ 7: 0]};
		{MEMOP_LBU , 2'b01}: m_rdata_pick_sext = {{24{1'b0           }}, bus_rdata_d[15: 8]};
		{MEMOP_LBU , 2'b10}: m_rdata_pick_sext = {{24{1'b0           }}, bus_rdata_d[23:16]};
		{MEMOP_LBU , 2'b11}: m_rdata_pick_sext = {{24{1'b0           }}, bus_rdata_d[31:24]};
		{MEMOP_LW  , 2'bzz}: m_rdata_pick_sext = bus_rdata_d;
		{MEMOP_LR_W, 2'bzz}: m_rdata_pick_sext = bus_rdata_d;
		default:             m_rdata_pick_sext = 32'hxxxx_xxxx;
	endcase

	if (|EXTENSION_A && x_amo_phase == 3'h1) begin
		// Capture AMO read data into mw_result for feeding back through the ALU.
		m_result = bus_rdata_d;
	end else if (|EXTENSION_A && xm_memop == MEMOP_SC_W) begin
		// sc.w may fail due to negative response from either local or global monitor.
		// Note the polarity of the result: 0 for success, 1 for failure.
		m_result = {31'h0, !(mw_local_exclusive_reserved && bus_dph_exokay_d)};
	end else if (xm_memop != MEMOP_NONE && xm_memop != MEMOP_AMO) begin
		m_result = m_rdata_pick_sext;
	end else if (MUL_FAST && m_fast_mul_result_vld) begin
		m_result = m_fast_mul_result;
	end else begin
		m_result = xm_result;
	end
end

// Local monitor update.
// - Set on a load-reserved with good response from global monitor
// - Cleared by any store-conditional
// - Cleared by non-debug-related trap entry/exit

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mw_local_exclusive_reserved <= 1'b0;
	end else begin
		if (|EXTENSION_A && (!m_stall || bus_dph_err_d)) begin
			if (d_memop_is_amo) begin
				mw_local_exclusive_reserved <= 1'b0;
			end else if (xm_memop == MEMOP_SC_W && (bus_dph_ready_d || bus_dph_err_d)) begin
				mw_local_exclusive_reserved <= 1'b0;
			end else if (xm_memop == MEMOP_LR_W && bus_dph_ready_d) begin
				// In theory, the bus should never report HEXOKAY when HRESP is asserted.
				// Still might happen (e.g. if HEXOKAY is tied high), so mask HEXOKAY with
				// HREADY to be sure a failed lr.w clears the monitor.
				mw_local_exclusive_reserved <= bus_dph_exokay_d && !bus_dph_err_d;
			end
		end
		if (m_trap_enter_vld && m_trap_enter_rdy && !(debug_mode || m_trap_is_debug_entry)) begin
			mw_local_exclusive_reserved <= 1'b0;
		end
	end
end

// Note that exception entry prevents writeback, because the exception entry
// replaces the instruction in M. Interrupt entry does not prevent writeback,
// because the interrupt is notionally inserted in between the instruction in
// M and the instruction in X.

wire m_reg_wen_if_nonzero = !m_bus_stall && xm_except == EXCEPT_NONE;
wire m_reg_wen = |xm_rd && m_reg_wen_if_nonzero;

`ifdef HAZARD3_X_CHECKS
always @ (posedge clk) begin
	if (rst_n) begin
		if (m_reg_wen && (^m_result === 1'bX)) begin
			$display("Writing X to register file!");
			$finish;
		end
	end
end
`endif

`ifdef HAZARD3_ASSERTIONS
// We borrow mw_result during an AMO to capture rdata and feed back through
// the ALU, since it already has the right paths. Make sure this is safe.
// (Whatever instruction is in M ahead of AMO should have passed through by
// the time AMO has reached read dphase)
always @ (posedge clk) if (rst_n) begin
	if (x_amo_phase == 3'h1)
		assert(m_reg_wen_if_nonzero);
	if (x_amo_phase == 3'h1)
		assert(~|xm_rd);
end
`endif

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mw_result <= {W_DATA{1'b0}};
	end else if (m_reg_wen_if_nonzero && !(|EXTENSION_A && x_amo_phase[1])) begin
		// (don't trash the captured AMO read phase data during stage 2/3 of AMO -- we need it!)
		mw_result <= m_result;
	end
end

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mw_rd <= {W_REGADDR{1'b0}};
	end else begin
`ifdef HAZARD3_X_CHECKS
		if (!m_stall && ^bus_wdata_d === 1'bX) begin
			$display("Writing Xs to memory!");
			$finish;
		end
`endif
		if (m_reg_wen_if_nonzero)
			mw_rd <= xm_rd;
	end
end

hazard3_regfile_1w2r #(
	.RESET_REGS (RESET_REGFILE),
	.N_REGS     (32),
	.W_DATA     (W_DATA)
) regs (
	.clk    (clk),
	.rst_n  (rst_n),
	// On downstream stall, we feed D's addresses back into regfile
	// so that output does not change.
	.raddr1 (x_stall && !d_starved ? d_rs1 : f_rs1_coarse),
	.rdata1 (x_rdata1),
	.raddr2 (x_stall && !d_starved ? d_rs2 : f_rs2_coarse),
	.rdata2 (x_rdata2),

	.waddr  (xm_rd),
	.wdata  (m_result),
	.wen    (m_reg_wen)
);

`ifdef RISCV_FORMAL
`include "hazard3_rvfi_monitor.vh"
`endif

`ifdef HAZARD3_FORMAL_REGRESSION
// Each formal regression provides its own file with the below name:
`include "hazard3_formal_regression.vh"
`endif

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
