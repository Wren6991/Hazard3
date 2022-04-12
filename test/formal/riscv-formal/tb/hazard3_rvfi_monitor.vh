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

// TODO fix all the redundant RVFI registers in a nice way

wire rvfm_x_valid = fd_cir_vld >= 2 || (fd_cir_vld >= 1 && fd_cir[1:0] != 2'b11);

reg rvfm_m_valid;
reg [31:0] rvfm_m_instr;

wire rvfm_m_trap = xm_except != EXCEPT_NONE && xm_except != EXCEPT_MRET && m_trap_enter_rdy;
reg rvfm_entered_intr;

reg        rvfi_valid_r;
reg [31:0] rvfi_insn_r;
reg        rvfi_trap_r;

assign rvfi_valid = rvfi_valid_r;
assign rvfi_insn = rvfi_insn_r;
assign rvfi_trap = rvfi_trap_r;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		rvfm_m_valid <= 1'b0;
		rvfm_entered_intr <= 1'b0;
		rvfi_valid_r <= 1'b0;
		rvfi_trap_r <= 1'b0;
		rvfi_insn_r <= 32'h0;
	end else begin
		if (!x_stall) begin
			// X instruction squashed by any trap, as it's in the branch shadow
			rvfm_m_valid <= |df_cir_use && !m_trap_enter_vld;
			rvfm_m_instr <= {fd_cir[31:16] & {16{df_cir_use[1]}}, fd_cir[15:0]};
		end else if (!m_stall) begin
			rvfm_m_valid <= 1'b0;
		end
		rvfi_valid_r <= rvfm_m_valid && !m_stall;
		rvfi_insn_r <= rvfm_m_instr;
		rvfi_trap_r <= rvfm_m_trap;

		rvfm_entered_intr <= rvfm_entered_intr && !rvfi_valid;

		// Sanity checks
		if (d_rd != 5'h0)
			assert(rvfm_x_valid);
		if (xm_rd != 5'h0)
			assert(rvfm_m_valid);
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

assign rvfi_mode = 2'h3; // M-mode only
assign rvfi_intr = rvfi_valid && rvfm_entered_intr;
assign rvfi_halt = 1'b0; // TODO

// ----------------------------------------------------------------------------
// PC and jump monitor

reg [31:0] rvfm_xm_pc;
reg [31:0] rvfm_xm_pc_next;

// Get a strange error from Yosys with $past() on this signal (possibly due to
// comb terms), so just flop it explicitly
reg rvfm_past_df_cir_lock;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		rvfm_past_df_cir_lock <= 1'b0;
	else
		rvfm_past_df_cir_lock <= df_cir_lock;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		rvfm_xm_pc <= 0;
		rvfm_xm_pc_next <= 0;
	end else begin
		if (!x_stall) begin
			rvfm_xm_pc <= d_pc;
			rvfm_xm_pc_next <= f_jump_now || rvfm_past_df_cir_lock ? x_jump_target : d_pc + (fd_cir[1:0] == 2'b11 ? 32'h4 : 32'h2);
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
		rvfi_pc_wdata_r <= m_trap_enter_vld && m_trap_enter_rdy ? m_trap_addr : rvfm_xm_pc_next;
	end
end

// ----------------------------------------------------------------------------
// Register file monitor:
assign rvfi_rd_addr = mw_rd;
assign rvfi_rd_wdata = mw_rd ? mw_result : 32'h0;

// Do not reimplement internal bypassing logic. Danger of implementing
// it correctly here but incorrectly in core.

reg [31:0] rvfm_xm_rdata1;
reg [31:0] rvfm_xm_rdata2;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		rvfm_xm_rdata1 <= 32'h0;
		rvfm_xm_rdata2 <= 32'h0;
	end else if (!x_stall) begin
		rvfm_xm_rdata1 <= x_rs1_bypass;
		rvfm_xm_rdata2 <= x_rs2_bypass;
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
		rvfi_rs2_rdata_r <= rvfm_xm_rdata2;
	end
end

// ----------------------------------------------------------------------------
// Load/store monitor: based on bus signals, NOT processor internals.
// Marshal up a description of the current data phase, and then register this
// into the RVFI signals.

`ifndef RISCV_FORMAL_ALIGNED_MEM
initial $fatal;
`endif

reg [31:0] rvfm_haddr_dph;
reg        rvfm_hwrite_dph;
reg [1:0]  rvfm_htrans_dph;
reg [2:0]  rvfm_hsize_dph;

always @ (posedge clk) begin
	if (bus_aph_ready_d) begin
		rvfm_htrans_dph <= {bus_aph_req_d, 1'b0};
		rvfm_haddr_dph <= bus_haddr_d;
		rvfm_hwrite_dph <= bus_hwrite_d;
		rvfm_hsize_dph <= bus_hsize_d;
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

assign rvfi_mem_addr = rvfi_mem_addr_r;
assign rvfi_mem_rmask = rvfi_mem_rmask_r;
assign rvfi_mem_rdata = rvfi_mem_rdata_r;
assign rvfi_mem_wmask = rvfi_mem_wmask_r;
assign rvfi_mem_wdata = rvfi_mem_wdata_r;

always @ (posedge clk) begin
	if (bus_dph_ready_d) begin
		// RVFI has an AXI-like concept of byte strobes, rather than AHB-like
		rvfi_mem_addr_r <= rvfm_haddr_dph & 32'hffff_fffc;
		{rvfi_mem_rmask_r, rvfi_mem_wmask_r} <= 0;
		if (rvfm_htrans_dph[1] && rvfm_hwrite_dph) begin
			rvfi_mem_wmask_r <= rvfm_mem_bytemask_dph;
			rvfi_mem_wdata_r <= bus_wdata_d;
		end else if (rvfm_htrans_dph[1] && !rvfm_hwrite_dph) begin
			rvfi_mem_rmask_r <= rvfm_mem_bytemask_dph;
			rvfi_mem_rdata_r <= bus_rdata_d;
		end
	end else begin
		// As far as RVFI is concerned nothing happens except final cycle of dphase
		{rvfi_mem_rmask_r, rvfi_mem_wmask_r} <= 0;
	end
end
