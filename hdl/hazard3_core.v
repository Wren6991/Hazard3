/**********************************************************************
 * DO WHAT THE FUCK YOU WANT TO AND DON'T BLAME US PUBLIC LICENSE     *
 *                    Version 3, April 2008                           *
 *                                                                    *
 * Copyright (C) 2018 Luke Wren                                       *
 *                                                                    *
 * Everyone is permitted to copy and distribute verbatim or modified  *
 * copies of this license document and accompanying software, and     *
 * changing either is allowed.                                        *
 *                                                                    *
 *   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION  *
 *                                                                    *
 * 0. You just DO WHAT THE FUCK YOU WANT TO.                          *
 * 1. We're NOT RESPONSIBLE WHEN IT DOESN'T FUCKING WORK.             *
 *                                                                    *
 *********************************************************************/

module hazard3_core #(
`include "hazard3_config.vh"
,
`include "hazard3_width_const.vh"
) (
	// Global signals
	input wire               clk,
	input wire               rst_n,

	`ifdef RISCV_FORMAL
	`RVFI_OUTPUTS ,
	`endif

	// Instruction fetch port
	output wire              bus_aph_req_i,
	output wire              bus_aph_panic_i, // e.g. branch mispredict + flush
	input  wire              bus_aph_ready_i,
	input  wire              bus_dph_ready_i,
	input  wire              bus_dph_err_i,

	output wire [2:0]        bus_hsize_i,
	output wire [W_ADDR-1:0] bus_haddr_i,
	input  wire [W_DATA-1:0] bus_rdata_i,

	// Load/store port
	output reg               bus_aph_req_d,
	input  wire              bus_aph_ready_d,
	input  wire              bus_dph_ready_d,
	input  wire              bus_dph_err_d,

	output reg  [W_ADDR-1:0] bus_haddr_d,
	output reg  [2:0]        bus_hsize_d,
	output reg               bus_hwrite_d,
	output reg  [W_DATA-1:0] bus_wdata_d,
	input  wire [W_DATA-1:0] bus_rdata_d,

	// External level-sensitive interrupt sources (tie 0 if unused)
	input wire [15:0]        irq
);

`include "hazard3_ops.vh"

`ifdef FORMAL
// Only yosys-smtbmc seems to support immediate assertions
`ifdef RISCV_FORMAL
`define ASSERT(x)
`else
`define ASSERT(x) assert(x)
`endif
`else
`define ASSERT(x)
//synthesis translate_off
`undef ASSERT
`define ASSERT(x) if (!x) begin $display("Assertion failed!"); $finish(1); end
//synthesis translate_on
`endif

wire d_stall;
wire x_stall;
wire m_stall;

localparam HSIZE_WORD  = 3'd2;
localparam HSIZE_HWORD = 3'd1;
localparam HSIZE_BYTE  = 3'd0;

// ----------------------------------------------------------------------------
// Pipe Stage F


wire                 f_jump_req;
wire [W_ADDR-1:0]    f_jump_target;
wire                 f_jump_rdy;
wire                 f_jump_now = f_jump_req && f_jump_rdy;

// Predecoded register numbers, for register file access
wire                 f_regnum_vld;
wire [W_REGADDR-1:0] f_rs1;
wire [W_REGADDR-1:0] f_rs2;

wire [31:0]          fd_cir;
wire [1:0]           fd_cir_vld;
wire [1:0]           df_cir_use;
wire                 df_cir_lock;

assign bus_aph_panic_i = 1'b0;

wire f_mem_size;
assign bus_hsize_i = f_mem_size ? HSIZE_WORD : HSIZE_HWORD;

hazard3_frontend #(
	.FIFO_DEPTH(2),
`include "hazard3_config_inst.vh"
) frontend (
	.clk             (clk),
	.rst_n           (rst_n),

	.mem_size        (f_mem_size),
	.mem_addr        (bus_haddr_i),
	.mem_addr_vld    (bus_aph_req_i),
	.mem_addr_rdy    (bus_aph_ready_i),

	.mem_data        (bus_rdata_i),
	.mem_data_vld    (bus_dph_ready_i),

	.jump_target     (f_jump_target),
	.jump_target_vld (f_jump_req),
	.jump_target_rdy (f_jump_rdy),

	.cir             (fd_cir),
	.cir_vld         (fd_cir_vld),
	.cir_use         (df_cir_use),
	.cir_lock        (df_cir_lock),

	.next_regs_rs1   (f_rs1),
	.next_regs_rs2   (f_rs2),
	.next_regs_vld   (f_regnum_vld)
);

// ----------------------------------------------------------------------------
// Pipe Stage X (Decode Logic)

// X-check on pieces of instruction which frontend claims are valid
//synthesis translate_off
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
//synthesis translate_on

// To X
wire [W_DATA-1:0]    d_imm;
wire [W_REGADDR-1:0] d_rs1;
wire [W_REGADDR-1:0] d_rs2;
wire [W_REGADDR-1:0] d_rd;
wire [W_ALUSRC-1:0]  d_alusrc_a;
wire [W_ALUSRC-1:0]  d_alusrc_b;
wire [W_ALUOP-1:0]   d_aluop;
wire [W_MEMOP-1:0]   d_memop;
wire [W_MULOP-1:0]   d_mulop;
wire [W_BCOND-1:0]   d_branchcond;
wire [W_ADDR-1:0]    d_jump_offs;
wire                 d_jump_is_regoffs;
wire [W_ADDR-1:0]    d_pc;
wire [W_EXCEPT-1:0]  d_except;
wire                 d_csr_ren;
wire                 d_csr_wen;
wire [1:0]           d_csr_wtype;
wire                 d_csr_w_imm;

wire x_jump_not_except;

hazard3_decode #(
`include "hazard3_config_inst.vh"
) inst_hazard3_decode (
	.clk                  (clk),
	.rst_n                (rst_n),

	.fd_cir               (fd_cir),
	.fd_cir_vld           (fd_cir_vld),
	.df_cir_use           (df_cir_use),
	.df_cir_lock          (df_cir_lock),
	.d_pc                 (d_pc),
	.x_jump_not_except    (x_jump_not_except),

	.d_stall              (d_stall),
	.x_stall              (x_stall),
	.f_jump_rdy           (f_jump_rdy),
	.f_jump_now           (f_jump_now),
	.f_jump_target        (f_jump_target),

	.d_imm                (d_imm),
	.d_rs1                (d_rs1),
	.d_rs2                (d_rs2),
	.d_rd                 (d_rd),
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
	.d_jump_offs          (d_jump_offs),
	.d_jump_is_regoffs    (d_jump_is_regoffs),
	.d_pc                 (d_pc),
	.d_except             (d_except)
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
wire  [W_DATA-1:0]   x_alu_add;
wire                 x_alu_cmp;

wire [W_DATA-1:0]    x_trap_addr;
wire [W_DATA-1:0]    x_mepc;
wire                 x_trap_enter;
wire                 x_trap_exit;

reg  [W_REGADDR-1:0] xm_rs1;
reg  [W_REGADDR-1:0] xm_rs2;
reg  [W_REGADDR-1:0] xm_rd;
reg  [W_DATA-1:0]    xm_result;
reg  [W_DATA-1:0]    xm_store_data;
reg  [W_MEMOP-1:0]   xm_memop;

reg x_stall_raw;
wire x_stall_muldiv;

assign x_stall =
	m_stall ||
	x_stall_raw || x_stall_muldiv ||
	bus_aph_req_d && !bus_aph_ready_d ||
	f_jump_req && !f_jump_rdy;

wire m_fast_mul_result_vld;
wire m_generating_result = xm_memop < MEMOP_SW || m_fast_mul_result_vld;

// Load-use hazard detection
always @ (*) begin
	x_stall_raw = 1'b0;
	if (REDUCED_BYPASS) begin
		x_stall_raw =
			|xm_rd && (xm_rd == d_rs1 || xm_rd == d_rs2) ||
			|mw_rd && (mw_rd == d_rs1 || mw_rd == d_rs2);
	end else if (m_generating_result) begin
		// With the full bypass network, load-use (or fast multiply-use) is the only RAW stall
		if (|xm_rd && xm_rd == d_rs1) begin
			// Store addresses cannot be bypassed later, so there is no exception here.
			x_stall_raw = 1'b1;
		end else if (|xm_rd && xm_rd == d_rs2) begin
			// Store data can be bypassed in M. Any other instructions must stall.
			x_stall_raw = !(d_memop == MEMOP_SW || d_memop == MEMOP_SH || d_memop == MEMOP_SB);
		end
	end
end

// ALU, operand muxes and bypass

always @ (*) begin
	if (~|d_rs1) begin
		x_rs1_bypass = {W_DATA{1'b0}};
	end else if (xm_rd == d_rs1) begin
		x_rs1_bypass = xm_result;
	end else if (mw_rd == d_rs1 && !REDUCED_BYPASS) begin
		x_rs1_bypass = mw_result;
	end else begin
		x_rs1_bypass = x_rdata1;
	end
	if (~|d_rs2) begin
		x_rs2_bypass = {W_DATA{1'b0}};
	end else if (xm_rd == d_rs2) begin
		x_rs2_bypass = xm_result;
	end else if (mw_rd == d_rs2 && !REDUCED_BYPASS) begin
		x_rs2_bypass = mw_result;
	end else begin
		x_rs2_bypass = x_rdata2;
	end

	if (|d_alusrc_a)
		x_op_a = d_pc;
	else
		x_op_a = x_rs1_bypass;

	if (|d_alusrc_b)
		x_op_b = d_imm;
	else
		x_op_b = x_rs2_bypass;
end

hazard3_alu alu (
	.aluop      (d_aluop),
	.op_a       (x_op_a),
	.op_b       (x_op_b),
	.result     (x_alu_result),
	.result_add (x_alu_add),
	.cmp        (x_alu_cmp)
);

// AHB transaction request

wire x_memop_vld = !d_memop[3];
wire x_memop_write = d_memop == MEMOP_SW || d_memop == MEMOP_SH || d_memop == MEMOP_SB;
wire x_unaligned_addr =
	bus_hsize_d == HSIZE_WORD && |bus_haddr_d[1:0] ||
	bus_hsize_d == HSIZE_HWORD && bus_haddr_d[0];

wire x_except_load_misaligned = x_memop_vld && x_unaligned_addr && !x_memop_write;
wire x_except_store_misaligned = x_memop_vld && x_unaligned_addr && x_memop_write;

always @ (*) begin
	// Need to be careful not to use anything hready-sourced to gate htrans!
	bus_haddr_d = x_alu_add;
	bus_hwrite_d = x_memop_write;
	case (d_memop)
		MEMOP_LW:  bus_hsize_d = HSIZE_WORD;
		MEMOP_SW:  bus_hsize_d = HSIZE_WORD;
		MEMOP_LH:  bus_hsize_d = HSIZE_HWORD;
		MEMOP_LHU: bus_hsize_d = HSIZE_HWORD;
		MEMOP_SH:  bus_hsize_d = HSIZE_HWORD;
		default:   bus_hsize_d = HSIZE_BYTE;
	endcase
	bus_aph_req_d = x_memop_vld && !(x_stall_raw || x_trap_enter);
end

// CSRs and Trap Handling

wire   x_except_ecall         = d_except == EXCEPT_ECALL;
wire   x_except_breakpoint    = d_except == EXCEPT_EBREAK;
wire   x_except_invalid_instr = d_except == EXCEPT_INSTR_ILLEGAL;
assign x_trap_exit            = d_except == EXCEPT_MRET;
wire   x_trap_enter_rdy       = !(x_stall || x_trap_exit);
wire   x_trap_is_exception; // diagnostic

`ifdef FORMAL
always @ (posedge clk) begin
	if (x_trap_exit)
		assert(!bus_aph_req_d);
end
`endif

wire [W_DATA-1:0] x_csr_wdata = d_csr_w_imm ?
	{{W_DATA-5{1'b0}}, d_rs1} : x_rs1_bypass;

wire [W_DATA-1:0] x_csr_rdata;

hazard3_csr #(
	.XLEN            (W_DATA),
`include "hazard3_config_inst.vh"
) inst_hazard3_csr (
	.clk                     (clk),
	.rst_n                   (rst_n),
	// CSR access port
	// *en_soon are early access strobes which are not a function of bus stall.
	// Can generate access faults (hence traps), but do not actually perform access.
	.addr                    (d_imm[11:0]), // todo could just connect this to the instruction bits
	.wdata                   (x_csr_wdata),
	.wen_soon                (d_csr_wen),
	.wen                     (d_csr_wen && !x_stall),
	.wtype                   (d_csr_wtype),
	.rdata                   (x_csr_rdata),
	.ren_soon                (d_csr_ren),
	.ren                     (d_csr_ren && !x_stall),
	// Trap signalling
	.trap_addr               (x_trap_addr),
	.trap_enter_vld          (x_trap_enter),
	.trap_enter_rdy          (x_trap_enter_rdy),
	.trap_exit               (x_trap_exit && !x_stall),
	.trap_is_exception       (x_trap_is_exception),
	.mepc_in                 (d_pc),
	.mepc_out                (x_mepc),
	// IRQ and exception requests
	.irq                     (irq),
	.except_instr_misaligned (1'b0), // TODO
	.except_instr_fault      (1'b0), // TODO
	.except_instr_invalid    (x_except_invalid_instr),
	.except_breakpoint       (x_except_breakpoint),
	.except_load_misaligned  (x_except_load_misaligned),
	.except_load_fault       (1'b0), // TODO
	.except_store_misaligned (x_except_store_misaligned),
	.except_store_fault      (1'b0), // TODO
	.except_ecall            (x_except_ecall),
	// Other CSR-specific signalling
	.instr_ret               (1'b0)  // TODO
);

// Multiply/divide

wire [W_DATA-1:0] x_muldiv_result;
wire [W_DATA-1:0] m_fast_mul_result;

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

	wire x_muldiv_kill = x_trap_enter; // TODO this takes an extra cycle to kill muldiv before trap entry

	wire x_use_fast_mul = MUL_FAST && d_aluop == ALUOP_MULDIV && d_mulop == M_OP_MUL;

	assign x_muldiv_op_vld = (d_aluop == ALUOP_MULDIV && !x_use_fast_mul)
		&& !(x_muldiv_posted || x_stall_raw || x_muldiv_kill);

	hazard3_muldiv_seq #(
		.XLEN   (W_DATA),
		.UNROLL (MULDIV_UNROLL)
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

	// TODO fusion of MULHx->MUL and DIVy->REMy sequences
	wire x_muldiv_result_is_high =
		d_mulop == M_OP_MULH ||
		d_mulop == M_OP_MULHSU ||
		d_mulop == M_OP_MULHU ||
		d_mulop == M_OP_REM ||
		d_mulop == M_OP_REMU;
	assign x_muldiv_result = x_muldiv_result_is_high ? x_muldiv_result_h : x_muldiv_result_l;
	assign x_stall_muldiv = x_muldiv_op_vld || !x_muldiv_result_vld;

	if (MUL_FAST) begin: has_fast_mul

		wire x_issue_fast_mul = x_use_fast_mul && |d_rd && !x_stall;

		hazard3_mul_fast #(
			.XLEN(W_DATA)
		) inst_hazard3_mul_fast (
			.clk        (clk),
			.rst_n      (rst_n),

			.op_a       (x_rs1_bypass),
			.op_b       (x_rs2_bypass),
			.op_vld     (x_issue_fast_mul),

			.result     (m_fast_mul_result),
			.result_vld (m_fast_mul_result_vld)
		);

	end else begin: no_fast_mul

		assign m_fast_mul_result = {W_DATA{1'b0}};
		assign m_fast_mul_result_vld = 1'b0;

	end

`ifdef FORMAL
	always @ (posedge clk) if (d_aluop != ALUOP_MULDIV) assert(!x_stall_muldiv);
`endif

end else begin: no_muldiv

	assign x_muldiv_result = {W_DATA{1'b0}};
	assign m_fast_mul_result = {W_DATA{1'b0}};
	assign m_fast_mul_result_vld = 1'b0;
	assign x_stall_muldiv = 1'b0;

end
endgenerate

// State machine
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		xm_memop <= MEMOP_NONE;
		{xm_rs1, xm_rs2, xm_rd} <= {3 * W_REGADDR{1'b0}};
	end else begin
		if (!m_stall) begin
			{xm_rs1, xm_rs2, xm_rd} <= {d_rs1, d_rs2, d_rd};
			// If the transfer is unaligned, make sure it is completely NOP'd on the bus
			xm_memop <= d_memop | {x_unaligned_addr, 3'h0};
			if (x_stall || x_trap_enter) begin
				// Insert bubble
				xm_rd <= {W_REGADDR{1'b0}};
				xm_memop <= MEMOP_NONE;
			end
		end
	end
end

// No reset on datapath flops
always @ (posedge clk)
	if (!m_stall) begin
		xm_result <=
			d_csr_ren                              ? x_csr_rdata :
			EXTENSION_M && d_aluop == ALUOP_MULDIV ? x_muldiv_result :
			                                         x_alu_result;
		xm_store_data <= x_rs2_bypass;
	end

// Branch handling

// For JALR, the LSB of the result must be cleared by hardware
wire [W_ADDR-1:0] x_taken_jump_target = ((d_jump_is_regoffs ? x_rs1_bypass : d_pc) + d_jump_offs) & ~32'h1;

wire [W_ADDR-1:0] x_jump_target =
	x_trap_exit                                 ? x_mepc             : // Note precedence -- it's possible to have enter && exit, but in this case enter_rdy is false.
	x_trap_enter                                ? x_trap_addr        :
	                                              x_taken_jump_target;

// Be careful not to take branches whose comparisons depend on a load result
wire x_jump_req = x_trap_enter || x_trap_exit || !x_stall_raw && (
	d_branchcond == BCOND_ALWAYS ||
	d_branchcond == BCOND_ZERO && !x_alu_cmp ||
	d_branchcond == BCOND_NZERO && x_alu_cmp
);

assign f_jump_req = x_jump_req;
assign f_jump_target = x_jump_target;
assign x_jump_not_except = !(x_trap_enter || x_trap_exit);


// ----------------------------------------------------------------------------
//                               Pipe Stage M

reg [W_DATA-1:0] m_rdata_shift;
reg [W_DATA-1:0] m_wdata;
reg [W_DATA-1:0] m_result;

assign m_stall = !xm_memop[3] && !bus_dph_ready_d;

wire m_except_bus_fault = bus_dph_err_d; // TODO: handle differently for LSU/ifetch?

always @ (*) begin
	// Local forwarding of store data
	if (|mw_rd && xm_rs2 == mw_rd && !REDUCED_BYPASS) begin
		m_wdata = mw_result;
	end else begin
		m_wdata = xm_store_data;
	end
	// Replicate store data to ensure appropriate byte lane is driven
	case (xm_memop)
		MEMOP_SW: bus_wdata_d = m_wdata;
		MEMOP_SH: bus_wdata_d = {2{m_wdata[15:0]}};
		MEMOP_SB: bus_wdata_d = {4{m_wdata[7:0]}};
		default:  bus_wdata_d = 32'h0;
	endcase
	// Pick out correct data from load access, and sign/unsign extend it.
	// This is slightly cheaper than a normal shift:
	case (xm_result[1:0])
		2'b00: m_rdata_shift = bus_rdata_d;
		2'b01: m_rdata_shift = {bus_rdata_d[31:8],  bus_rdata_d[15:8]};
		2'b10: m_rdata_shift = {bus_rdata_d[31:16], bus_rdata_d[31:16]};
		2'b11: m_rdata_shift = {bus_rdata_d[31:8],  bus_rdata_d[31:24]};
	endcase

	case (xm_memop)
		MEMOP_LW:  m_result = m_rdata_shift;
		MEMOP_LH:  m_result = {{16{m_rdata_shift[15]}}, m_rdata_shift[15:0]};
		MEMOP_LHU: m_result = {16'h0, m_rdata_shift[15:0]};
		MEMOP_LB:  m_result = {{24{m_rdata_shift[7]}}, m_rdata_shift[7:0]};
		MEMOP_LBU: m_result = {24'h0, m_rdata_shift[7:0]};
		default:   begin
			if (MUL_FAST && m_fast_mul_result_vld) begin
				m_result = m_fast_mul_result;
			end else begin
				m_result = xm_result;
			end
		end
	endcase
end

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mw_rd <= {W_REGADDR{1'b0}};
	end else if (!m_stall) begin
		//synthesis translate_off
		// TODO: proper exception support
		if (m_except_bus_fault) begin
			$display("Bus fault!");
			$finish;
		end
		if (^bus_wdata_d === 1'bX) begin
			$display("Writing Xs to memory!");
			$finish;
		end
		//synthesis translate_on
		mw_rd <= xm_rd;
	end
end

// No need to reset result register, as reset on mw_rd protects register file from it
always @ (posedge clk)
	if (!m_stall)
		mw_result <= m_result;

// ----------------------------------------------------------------------------
//                               Pipe Stage W

// mw_result and mw_rd register the most recent write to the register file,
// so that X can bypass them in.

wire w_reg_wen = |xm_rd && !m_stall;

//synthesis translate_off
always @ (posedge clk) begin
	if (rst_n) begin
		if (w_reg_wen && (^m_result === 1'bX)) begin
			$display("Writing X to register file!");
			$finish;
		end
	end
end
//synthesis translate_on

hazard3_regfile_1w2r #(
	.FAKE_DUALPORT(0),
`ifdef SIM
	.RESET_REGS(1),
`elsif FORMAL
	.RESET_REGS(1),
`else
	.RESET_REGS(0),
`endif
	.N_REGS(32),
	.W_DATA(W_DATA)
) inst_regfile_1w2r (
	.clk    (clk),
	.rst_n  (rst_n),
	// On downstream stall, we feed D's addresses back into regfile
	// so that output does not change.
	.raddr1 (x_stall ? d_rs1 : f_rs1),
	.rdata1 (x_rdata1),
	.raddr2 (x_stall ? d_rs2 : f_rs2),
	.rdata2 (x_rdata2),

	.waddr  (xm_rd),
	.wdata  (m_result),
	.wen    (w_reg_wen)
);

`ifdef RISCV_FORMAL
`include "hazard3_rvfi_monitor.vh"
`endif

`ifdef HAZARD3_FORMAL_REGRESSION
// Each formal regression provides its own file with the below name:
`include "hazard3_formal_regression.vh"
`endif

endmodule
