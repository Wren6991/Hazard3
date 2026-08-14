/*****************************************************************************\
|                      Copyright (C) 2021-2025 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// ----------------------------------------------------------------------------
// RVFI Instrumentation
// ----------------------------------------------------------------------------
// To be included into hazard3_core.v for use with riscv-formal.
// Contains some state modelling to diagnose exactly what the core is doing,
// and report this in a way RVFI understands.
// We consider instructions to "retire" as they cross the M/W pipe register.
//
// All modelling signals prefixed with rvfm (riscv-formal monitor)

// ----------------------------------------------------------------------------
// Instruction monitor

// Diagnose whether X, M contain valid in-flight instructions, to produce
// rvfi_valid signal.

wire rvfm_x_valid = fd_cir_vld >= 2 || (fd_cir_vld >= 1 && fd_cir_raw[1:0] != 2'b11);

reg rvfm_m_valid;
reg [31:0] rvfm_m_instr;

// Exclude "traps" which are microarchitectural rather than architectural
wire rvfm_m_take_exception =
	xm_except != EXCEPT_NONE    &&
	xm_except != EXCEPT_REFETCH &&
	xm_except != EXCEPT_MRET    &&
	m_trap_enter_rdy;

wire rvfm_m_take_irq =
	m_trap_enter_vld &&
	m_trap_enter_rdy &&
	m_trap_is_irq;

reg        rvfi_valid_r;
reg [31:0] rvfi_insn_r;
reg        rvfi_trap_r;

assign rvfi_valid = rvfi_valid_r;
assign rvfi_insn = rvfi_insn_r;
assign rvfi_trap = rvfi_trap_r;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		rvfm_m_valid <= 1'b0;
		rvfi_valid_r <= 1'b0;
		rvfi_trap_r <= 1'b0;
		rvfi_insn_r <= 32'h0;
	end else begin
		if (!x_stall) begin
			// X instruction squashed by any trap, as it's in the branch
			// shadow.
			rvfm_m_valid <= |df_cir_use && !(m_trap_enter_vld && m_trap_enter_rdy);
			rvfm_m_instr <= {fd_cir_raw[31:16] & {16{df_cir_use[1]}}, fd_cir_raw[15:0]};
		end else if (!m_stall) begin
			rvfm_m_valid <= 1'b0;
		end
		rvfi_valid_r <= rvfm_m_valid && !m_stall;
		// Instructions which experienced fetch faults are reported as
		// all-zeroes, per riscv-formal docs.
		rvfi_insn_r <= rvfm_m_instr & {32{
			xm_except != EXCEPT_INSTR_FAULT &&
			xm_except != EXCEPT_INSTR_MISALIGN
		}};
		rvfi_trap_r <= rvfm_m_take_exception;
	end
end

`ifdef HAZARD3_ASSERTIONS
always @ (posedge clk) if (rst_n) begin
	// Sanity checks for above
	if (d_rd != 5'h0)
		assert(rvfm_x_valid);
	if (xm_rd != 5'h0)
		assert(rvfm_m_valid);
end
`endif

// Track whether an instruction is the first of an interrupt or exception;
// when a trap happens, a flag is installed in stage X, and once a new
// instruction arrives the flag travels alongside it down to the RVFI port.
reg rvfm_x_intr;
reg rvfm_m_intr;
reg rvfi_intr_r;

wire rvfm_x_intr_retained =
	x_stall ||
	d_starved ||
	fd_cir_uop_nonfinal ||
	df_lspair_phase_next;

always @ (posedge clk) begin
	if (!rst_n) begin
		rvfm_x_intr <= 1'b0;
		rvfm_m_intr <= 1'b0;
		rvfi_intr_r <= 1'b0;
	end else begin
		rvfm_x_intr <=
			(rvfm_x_intr && rvfm_x_intr_retained) ||
			rvfm_m_take_exception ||
			rvfm_m_take_irq;
		if (!x_stall) begin
			rvfm_m_intr <= rvfm_x_intr;
		end
		if (!m_stall) begin
			rvfi_intr_r <= rvfm_m_intr;
		end
	end
end


// Hazard3 is an in-order core:
reg [63:0] rvfm_retire_ctr;
assign rvfi_order = rvfm_retire_ctr;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		rvfm_retire_ctr <= 0;
	else if (rvfi_valid)
		rvfm_retire_ctr <= rvfm_retire_ctr + 1;

assign rvfi_intr = rvfi_intr_r && rvfi_valid;

// ----------------------------------------------------------------------------
// PC and jump monitor

reg [31:0] rvfm_xm_pc;
reg [31:0] rvfm_xm_pc_next;

// Record a jump target that was issued while stalled
reg        rvfm_x_saw_f_jump;
reg [31:0] rvfm_x_saw_f_jump_target;
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		rvfm_x_saw_f_jump <= 1'b0;
		rvfm_x_saw_f_jump_target <= 32'd0;
	end else if (f_jump_now && !(m_trap_enter_vld && m_trap_enter_rdy) && (x_stall || (fd_cir_is_uop && fd_cir_uop_nonfinal))) begin
		// Record fetch address issued by instruction. Note this case is gated
		// on m_trap_enter_vld && m_trap_enter_rdy (not just vld). If
		// !m_trap_enter_rdy it is still possible to get a new fetch address
		// in the following case:
		//
		// * M instr is a load/store (in dphase)
		//
		// * IRQ is asserted, but blocked by the load/store dphase to avoid
		//   trashing exception PC of a potential data-phase bus fault
		//
		// * X instr is a jump, which stalls due to the IRQ assertion
		//
		// * X instr's PC goes through to frontend during stall (and would be
		//   flushed if the IRQ went through) because stall cannot gate fetch
		//   address request to avoid AHB through-path.
		//
		// * IRQ's trap address is not immediately accepted by frontend due to
		//   address-phase stall on issuing jump instr's address
		//
		// * IRQ deasserts on the next cycle, so its trap address is not accepted.
		rvfm_x_saw_f_jump <= 1'b1;
		rvfm_x_saw_f_jump_target <= f_jump_target;
	end else if (!x_stall && !(fd_cir_is_uop && fd_cir_uop_nonfinal)) begin
		rvfm_x_saw_f_jump <= 1'b0;
	end else if (m_trap_enter_vld && m_trap_enter_rdy) begin
		// E.g. trap during uop sequence
		rvfm_x_saw_f_jump <= 1'b0;
	end
end

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		rvfm_xm_pc <= 0;
		rvfm_xm_pc_next <= 0;
	end else begin
		if (!x_stall) begin
			// For cm.popret and cm.popretz the PC actually changes on the
			// penultimate uop; ignore this and retain the initial PC. Abuse
			// knowledge that the PC update is always in the atomic section,
			// and the first instruction is always interruptible.
			if (!(fd_cir_is_uop && fd_cir_uop_atomic)) begin
				rvfm_xm_pc <= d_pc;
			end
			rvfm_xm_pc_next <=
				f_jump_now        ? f_jump_target            :
				rvfm_x_saw_f_jump ? rvfm_x_saw_f_jump_target :
				                    d_pc + (fd_cir_raw[1:0] == 2'b11 ? 32'h4 : 32'h2);
		end
	end
end

reg [31:0] rvfi_pc_rdata_r;
reg [31:0] rvfi_pc_wdata_r;

assign rvfi_pc_rdata = rvfi_pc_rdata_r;
assign rvfi_pc_wdata = rvfi_pc_wdata_r;

always @ (posedge clk) begin
	if (!m_stall) begin
		rvfi_pc_rdata_r <= rvfm_xm_pc;
		rvfi_pc_wdata_r <=
			m_trap_enter_vld && m_trap_enter_rdy && xm_except != EXCEPT_NONE ?
				m_trap_addr : rvfm_xm_pc_next;
	end
end

// ----------------------------------------------------------------------------
// Register file monitor:

// When writeback is suppressed due to trap, the previous instruction is left
// in the writeback buffer (and can be re-bypassed from there). Make sure not
// to report this as a writeback on RVFI.
reg rvfm_writeback_mask;
always @ (posedge clk) begin
	if (!m_stall) begin
		rvfm_writeback_mask <= m_reg_wen_if_nonzero;
	end
end

assign rvfi_rd_addr = mw_rd & {5{rvfm_writeback_mask}};
assign rvfi_rd_wdata = |mw_rd && rvfm_writeback_mask ? mw_result : 32'h0;

// Do not reimplement internal bypassing logic. Danger of implementing
// it correctly here but incorrectly in core.

reg [31:0] rvfm_xm_rdata1;
reg [31:0] rvfm_xm_rdata2;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		rvfm_xm_rdata1 <= 32'h0;
		rvfm_xm_rdata2 <= 32'h0;
	end else if (!x_stall) begin
		// rs*_bypass may have garbage on them for instructions with *no*
		// register operands (due to some interesting optimisations), though
		// d_rs* is still driven to 0 to disable stalling on that register
		// lane. riscv-formal still likes to see zeroes from x0, so fix that
		// up here. This shouldn't cover up any bugs, since a
		// register-operand instruction would still *use* the garbage value.
		rvfm_xm_rdata1 <= |d_rs1 ? x_rs1_bypass : 32'h0;
		rvfm_xm_rdata2 <= |d_rs2 ? x_rs2_bypass : 32'h0;
	end
end

reg [4:0]  rvfi_rs1_addr_r;
reg [4:0]  rvfi_rs2_addr_r;
reg [31:0] rvfi_rs1_rdata_r;
reg [31:0] rvfi_rs2_rdata_r;

assign rvfi_rs1_addr = rvfi_rs1_addr_r;
assign rvfi_rs2_addr = rvfi_rs2_addr_r;
assign rvfi_rs1_rdata = rvfi_rs1_rdata_r;
assign rvfi_rs2_rdata = rvfi_rs2_rdata_r;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		rvfi_rs1_addr_r <= 5'h0;
		rvfi_rs2_addr_r <= 5'h0;
		rvfi_rs1_rdata_r <= 32'h0;
		rvfi_rs2_rdata_r <= 32'h0;
	end else begin
		rvfi_rs1_addr_r <= m_stall ? 5'h0 : xm_rs1;
		rvfi_rs2_addr_r <= m_stall ? 5'h0 : xm_rs2;
		rvfi_rs1_rdata_r <= rvfm_xm_rdata1;
		rvfi_rs2_rdata_r <= xm_rs2 == mw_rd && |xm_rs2 ? m_wdata : rvfm_xm_rdata2;
	end
end

// ----------------------------------------------------------------------------
// Load/store monitor: based on bus signals, NOT processor internals.
// Marshal up a description of the current data phase, and then register this
// into the RVFI signals.

`ifdef HAZARD3_ASSERTIONS
`ifndef RISCV_FORMAL_ALIGNED_MEM
initial $fatal;
`endif
`endif

reg [31:0] rvfm_haddr_dph;
reg        rvfm_hwrite_dph;
reg [1:0]  rvfm_htrans_dph;
reg [2:0]  rvfm_hsize_dph;
reg        rvfm_hexcl_dph;

always @ (posedge clk) begin
	if (bus_aph_ready_d) begin
		rvfm_htrans_dph <= {bus_aph_req_d, 1'b0};
		rvfm_haddr_dph <= bus_haddr_d;
		rvfm_hwrite_dph <= bus_hwrite_d;
		rvfm_hsize_dph <= bus_hsize_d;
		rvfm_hexcl_dph <= bus_aph_excl_d;
	end
end

wire [3:0] rvfm_mem_bytemask_dph = (
	rvfm_hsize_dph == 3'h0 ? 4'h1 :
	rvfm_hsize_dph == 3'h1 ? 4'h3 :
	                         4'hf
	) << rvfm_haddr_dph[1:0];

reg [31:0] rvfi_mem_addr_r;
reg [3:0]  rvfi_mem_rmask_r;
reg [31:0] rvfi_mem_rdata_r;
reg [3:0]  rvfi_mem_wmask_r;
reg [31:0] rvfi_mem_wdata_r;
reg        rvfi_mem_fault_r;
// May have to hold the strobes for multiple cycles following a bus
// fault, as the trap entry may not go through immediately (depending
// on instruction-side bus stall):
reg        rvfm_mem_hold;

assign rvfi_mem_addr = rvfi_mem_addr_r;
assign rvfi_mem_rdata = rvfi_mem_rdata_r;
assign rvfi_mem_wdata = rvfi_mem_wdata_r;

assign rvfi_mem_fault       = rvfi_mem_fault_r;
assign rvfi_mem_wmask       = rvfi_mem_wmask_r & {4{!rvfi_mem_fault_r}};
assign rvfi_mem_rmask       = rvfi_mem_rmask_r & {4{!rvfi_mem_fault_r}};
assign rvfi_mem_fault_rmask = rvfi_mem_rmask_r & {4{ rvfi_mem_fault_r}};
assign rvfi_mem_fault_wmask = rvfi_mem_wmask_r & {4{ rvfi_mem_fault_r}};

always @ (posedge clk) begin
	rvfm_mem_hold <= (rvfm_mem_hold || (rvfm_htrans_dph && bus_dph_ready_d)) && m_stall;
	if (xm_memop == MEMOP_AMO) begin
		// AMO has completed in stage X. Progressing to stage M without MEMOP
		// going to NONE means there has been no trap, therefore no stall,
		// therefore no time for another address to have issued:
`ifndef HAZARD3_RVFI_STANDALONE
		// ifdef as this is non-synthesisable
		assert(!m_stall);
`endif
		rvfi_mem_addr_r <= rvfm_haddr_dph;
		// Always 32-bit, always both read and write:
		rvfi_mem_rmask_r <= 4'hf;
		rvfi_mem_wmask_r <= 4'hf;
		// Has been juggled since the read that matched the winning write:
		rvfi_mem_rdata_r <= xm_result;
		// Incidentally captured on previous cycle:
		rvfi_mem_wdata_r <= rvfi_mem_wdata_r;
	end else if (bus_dph_ready_d) begin
		// RVFI has an AXI-like concept of byte strobes, rather than AHB-like
		rvfi_mem_addr_r <= rvfm_haddr_dph & 32'hffff_fffc;
		{rvfi_mem_rmask_r, rvfi_mem_wmask_r} <= 0;
		if (rvfm_htrans_dph[1] && rvfm_hwrite_dph && rvfm_hexcl_dph && !bus_dph_exokay_d) begin
			// data-phase failure of exclusive write (declined by global monitor)
			rvfi_mem_wmask_r <= 4'h0;
		end else if (rvfm_htrans_dph[1] && rvfm_hwrite_dph) begin
			rvfi_mem_wmask_r <= rvfm_mem_bytemask_dph;
			rvfi_mem_wdata_r <= bus_wdata_d;
		end else if (rvfm_htrans_dph[1] && !rvfm_hwrite_dph) begin
			rvfi_mem_rmask_r <= rvfm_mem_bytemask_dph;
			rvfi_mem_rdata_r <= bus_rdata_d;
		end
		rvfi_mem_fault_r <= bus_dph_err_d;
	end else if (!rvfm_mem_hold) begin
		rvfi_mem_rmask_r <= 4'h0;
		rvfi_mem_wmask_r <= 4'h0;
		rvfi_mem_fault_r <= 1'b0;
	end
	// Also need to report rvfi_mem_fault on a fetch fault
	if (xm_except == EXCEPT_INSTR_FAULT && m_trap_enter_vld && m_trap_enter_rdy) begin
		rvfi_mem_fault_r <= 1'b1;
	end
end

// ----------------------------------------------------------------------------
// Constraints

// Trying to keep internal constraints to a minimum.

// Limit sleep duration for liveness checks
// TODO is it possible to do this in a way that doesn't assume the wakeup logic is functional?
`ifdef RISCV_FORMAL_FAIRNESS
reg [7:0] rvfm_sleep_counter;
always @ (posedge clk) begin
	if (!rst_n) begin
		rvfm_sleep_counter <= 8'd00;
	end else if (xm_sleep_wfi || xm_sleep_block) begin
		rvfm_sleep_counter <= rvfm_sleep_counter + 8'h01;
		assume(rvfm_sleep_counter < 8'd5);
	end else begin
		rvfm_sleep_counter <= 8'd00;
	end
end
`endif

// ----------------------------------------------------------------------------
// Tie-offs

// Note: Hazard3 does not have any instructions which irreversibly halt
// execution. For the liveness check (RISCV_FORMAL_FAIRNESS is defined),
// length of stalls is constrained and WFI is assumed to wake immediately
// after going to sleep.
assign rvfi_halt = 1'b0;

// Note: this always reports M-mode, which is not correct if the U_MODE config
// is set. However no riscv-formal checks currently use this signal.
assign rvfi_mode = 2'h3;

// Maximum XLEN is always 32 bits
assign rvfi_ixl = 2'h1;


