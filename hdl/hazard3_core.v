/**********************************************************************
 * DO WHAT THE FUCK YOU WANT TO AND DON'T BLAME US PUBLIC LICENSE     *
 *                    Version 3, April 2008                           *
 *                                                                    *
 * Copyright (C) 2021 Luke Wren                                       *
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

`default_nettype none

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

wire [W_DATA-1:0]    m_trap_addr;
wire                 m_trap_is_irq;
wire                 m_trap_enter_vld;
wire                 m_trap_enter_rdy = f_jump_rdy;

reg  [W_REGADDR-1:0] xm_rs1;
reg  [W_REGADDR-1:0] xm_rs2;
reg  [W_REGADDR-1:0] xm_rd;
reg  [W_DATA-1:0]    xm_result;
reg  [W_DATA-1:0]    xm_store_data;
reg  [W_MEMOP-1:0]   xm_memop;
reg  [W_EXCEPT-1:0]  xm_except;
reg                  xm_delay_irq_entry;


reg x_stall_raw;
wire x_stall_muldiv;
wire x_jump_req;

// IRQs squeeze in between the instructions in X and M, so in this case X
// stalls but M can continue. -> X always stalls on M trap, M *may* stall.
wire x_stall_on_trap = m_trap_enter_vld && !m_trap_enter_rdy;

assign x_stall =
	m_stall ||
	x_stall_on_trap ||
	x_stall_raw || x_stall_muldiv ||
	bus_aph_req_d && !bus_aph_ready_d ||
	x_jump_req && !f_jump_rdy;

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
	bus_aph_req_d = x_memop_vld && !(x_stall_raw || x_unaligned_addr || m_trap_enter_vld);
end

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

	wire x_muldiv_kill = m_trap_enter_vld;

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

// CSRs and Trap Handling

wire [W_DATA-1:0] x_csr_wdata = d_csr_w_imm ?
	{{W_DATA-5{1'b0}}, d_rs1} : x_rs1_bypass;

wire [W_DATA-1:0] x_csr_rdata;
wire              x_csr_illegal_access;

reg prev_instr_was_32_bit;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		xm_delay_irq_entry <= 1'b0;
		prev_instr_was_32_bit <= 1'b0;
	end else begin
		// Must hold off IRQ if we are in the second cycle of an address phase or
		// later, since at that point the load/store can't be revoked. The IRQ is
		// taken once this load/store moves to the next stage: if another load/store
		// is chasing down the pipeline then this is immediately suppressed by the
		// IRQ entry, before its address phase can begin.
		xm_delay_irq_entry <= bus_aph_req_d && !bus_aph_ready_d;
		if (!x_stall)
			prev_instr_was_32_bit <= df_cir_use == 2'd2;
	end
end

wire [W_ADDR-1:0] m_exception_return_addr;

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
	.wen_soon                (d_csr_wen && !m_trap_enter_vld),
	.wen                     (d_csr_wen && !m_trap_enter_vld && !x_stall),
	.wtype                   (d_csr_wtype),
	.rdata                   (x_csr_rdata),
	.ren_soon                (d_csr_ren && !m_trap_enter_vld),
	.ren                     (d_csr_ren && !m_trap_enter_vld && !x_stall),
	.illegal                 (x_csr_illegal_access),

	// Trap signalling
	.trap_addr               (m_trap_addr),
	.trap_is_irq             (m_trap_is_irq),
	.trap_enter_vld          (m_trap_enter_vld),
	.trap_enter_rdy          (m_trap_enter_rdy),
	.mepc_in                 (m_exception_return_addr),

	// IRQ and exception requests
	.delay_irq_entry         (xm_delay_irq_entry),
	.irq                     (irq),
	.except                  (xm_except),

	// Other CSR-specific signalling
	.instr_ret               (|df_cir_use)
);

wire [W_EXCEPT-1:0] x_except =
	x_csr_illegal_access               ? EXCEPT_INSTR_ILLEGAL :
	x_unaligned_addr &&  x_memop_write ? EXCEPT_STORE_ALIGN   :
	x_unaligned_addr && !x_memop_write ? EXCEPT_LOAD_ALIGN    : d_except;

// Pipe register

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		xm_memop <= MEMOP_NONE;
		xm_except <= EXCEPT_NONE;
		{xm_rs1, xm_rs2, xm_rd} <= {3 * W_REGADDR{1'b0}};
	end else begin
		if (!m_stall) begin
			{xm_rs1, xm_rs2, xm_rd} <= {d_rs1, d_rs2, d_rd};
			// If the transfer is unaligned, make sure it is completely NOP'd on the bus
			xm_memop <= d_memop | {x_unaligned_addr, 3'h0};
			if (x_stall || m_trap_enter_vld) begin
				// Insert bubble
				xm_rd <= {W_REGADDR{1'b0}};
				xm_memop <= MEMOP_NONE;
				xm_except <= EXCEPT_NONE;
			end
			xm_except <= x_except;
		end else if (bus_dph_err_d) begin
			// First phase of 2-phase AHBL error response. Pass the exception along on
			// this cycle, and on the next cycle the trap entry will be asserted,
			// suppressing any load/store that may currently be in stage X.
`ifdef FORMAL
			assert(!xm_memop[3]); // Not NONE
`endif
			xm_except <= xm_memop <= MEMOP_LBU ? EXCEPT_LOAD_FAULT : EXCEPT_STORE_FAULT;
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
wire [W_ADDR-1:0] x_jump_target = ((d_jump_is_regoffs ? x_rs1_bypass : d_pc) + d_jump_offs) & ~32'h1;

// Be careful not to take branches whose comparisons depend on a load result
assign x_jump_req = !x_stall_raw && (
	d_branchcond == BCOND_ALWAYS ||
	d_branchcond == BCOND_ZERO && !x_alu_cmp ||
	d_branchcond == BCOND_NZERO && x_alu_cmp
);

// ----------------------------------------------------------------------------
//                               Pipe Stage M

reg [W_DATA-1:0] m_rdata_shift;
reg [W_DATA-1:0] m_wdata;
reg [W_DATA-1:0] m_result;

assign f_jump_req = x_jump_req || m_trap_enter_vld;
assign f_jump_target = m_trap_enter_vld	? m_trap_addr : x_jump_target;
assign x_jump_not_except = !m_trap_enter_vld;

wire m_bus_stall = !xm_memop[3] && !bus_dph_ready_d; 
assign m_stall = m_bus_stall || (m_trap_enter_vld && !m_trap_enter_rdy && !m_trap_is_irq);

// Exception is taken against the instruction currently in M, so walk the PC
// back. IRQ is taken "in between" the instruction in M and the instruction
// in X, so set return to X program counter. Note that, if taking an
// exception, we know that the previous instruction to be in X (now in M)
// was *not* a branch, which is why we can just walk back the PC.
assign m_exception_return_addr = d_pc - (
	m_trap_is_irq         ? 32'h0 :
	prev_instr_was_32_bit ? 32'h4 : 32'h2
);

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


// Note that exception entry prevents writeback, because the exception entry
// replaces the instruction in M. Interrupt entry does not prevent writeback,
// because the interrupt is notionally inserted in between the instruction in
// M and the instruction in X.
wire m_reg_wen_if_nonzero = !m_bus_stall && xm_except == EXCEPT_NONE;
wire m_reg_wen = |xm_rd && m_reg_wen_if_nonzero;

//synthesis translate_off
always @ (posedge clk) begin
	if (rst_n) begin
		if (m_reg_wen && (^m_result === 1'bX)) begin
			$display("Writing X to register file!");
			$finish;
		end
	end
end
//synthesis translate_on

// No need to reset result register, as reset on mw_rd protects register file from it
always @ (posedge clk)
	if (m_reg_wen_if_nonzero)
		mw_result <= m_result;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mw_rd <= {W_REGADDR{1'b0}};
	end else begin
		//synthesis translate_off
		if (!m_stall && ^bus_wdata_d === 1'bX) begin
			$display("Writing Xs to memory!");
			$finish;
		end
		//synthesis translate_on
		if (m_reg_wen_if_nonzero)
			mw_rd <= xm_rd;
	end
end


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
