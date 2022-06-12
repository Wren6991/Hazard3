/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module hazard3_frontend #(
`include "hazard3_config.vh"
) (
	input  wire              clk,
	input  wire              rst_n,

	// Fetch interface
	// addr_vld may be asserted at any time, but after assertion,
	// neither addr nor addr_vld may change until the cycle after addr_rdy.
	// There is no backpressure on the data interface; the front end
	// must ensure it does not request data it cannot receive.
	// addr_rdy and dat_vld may be functions of hready, and
	// may not be used to compute combinational outputs.
	output wire              mem_size, // 1'b1 -> 32 bit access
	output wire [W_ADDR-1:0] mem_addr,
	output wire              mem_priv,
	output wire              mem_addr_vld,
	input  wire              mem_addr_rdy,
	input  wire [W_DATA-1:0] mem_data,
	input  wire              mem_data_err,
	input  wire              mem_data_vld,

	// Jump/flush interface
	// Processor may assert vld at any time. The request will not go through
	// unless rdy is high. Processor *may* alter request during this time.
	// Inputs must not be a function of hready.
	input  wire [W_ADDR-1:0] jump_target,
	input  wire              jump_priv,
	input  wire              jump_target_vld,
	output wire              jump_target_rdy,

	// Interface to Decode
	output wire [31:0]       cir,
	output reg  [1:0]        cir_vld, // number of valid halfwords in CIR
	input  wire [1:0]        cir_use, // number of halfwords D intends to consume
	                                  // *may* be a function of hready
	output wire [1:0]        cir_err, // Bus error on upper/lower halfword of CIR.
	input  wire              cir_lock,// Lock-in current contents and level of CIR.
	                                  // Assert simultaneously with a jump request,
	                                  // if decode is going to stall. This stops the CIR
	                                  // from being trashed by incoming fetch data;
	                                  // jump instructions have other side effects besides jumping!

	// Provide the rs1/rs2 register numbers which will be in CIR next cycle.
	// Coarse: valid if this instruction has a nonzero register operand.
	// (Suitable for regfile read)
	output reg  [4:0]        predecode_rs1_coarse,
	output reg  [4:0]        predecode_rs2_coarse,
	// Fine: like coarse, but accurate zeroing when the operand is implicit.
	// (Suitable for bypass. Still not precise enough for stall logic.)
	output reg  [4:0]        predecode_rs1_fine,
	output reg  [4:0]        predecode_rs2_fine,


	// Debugger instruction injection: instruction fetch is suppressed when in
	// debug halt state, and the DM can then inject instructions into the last
	// entry of the prefetch queue using the vld/rdy handshake.
	input  wire              debug_mode,
	input  wire [W_DATA-1:0] dbg_instr_data,
	input  wire              dbg_instr_data_vld,
	output wire              dbg_instr_data_rdy
);

`include "rv_opcodes.vh"

// This is the minimum size (in halfwords) for full fetch throughput, and
// there is little benefit to increasing it:
localparam FIFO_DEPTH = 7;

localparam W_BUNDLE = W_DATA / 2;

// ----------------------------------------------------------------------------
// Fetch Queue (FIFO)

wire jump_now = jump_target_vld && jump_target_rdy;

// Note these registers have more than FIFO_DEPTH bits: these extras won't
// synthesise to registers, and are just there for loop boundary conditions.

// Errors travel alongside data until the processor actually tries to decode
// an instruction whose fetch errored. Up until this point, errors can be
// flushed harmlessly.

reg [W_BUNDLE-1:0]    fifo_mem [0:FIFO_DEPTH+1];
reg [FIFO_DEPTH+1:0]  fifo_err;
reg [FIFO_DEPTH+1:-1] fifo_valid;

wire [1:0] mem_data_hwvalid;

wire fifo_empty = !fifo_valid[0];
// Full: will overflow after one 32b fetch. Almost full: after two of them.
wire fifo_full = fifo_valid[FIFO_DEPTH - 2];
wire fifo_almost_full = fifo_valid[FIFO_DEPTH - 4];

wire fifo_push;
wire fifo_dbg_inject = DEBUG_SUPPORT && dbg_instr_data_vld && dbg_instr_data_rdy;

// Boundary conditions
always @ (*) begin
	fifo_mem[FIFO_DEPTH] = mem_data[31:16];
	fifo_mem[FIFO_DEPTH + 1] = mem_data[31:16];
	fifo_err[FIFO_DEPTH + 1 -: 2] = 2'b00;
	fifo_valid[FIFO_DEPTH + 1 -: 2] = 2'b00;
	fifo_valid[-1] = 1'b1;
end

// Apply fetch, then shift out data consumed by decoder

reg [W_BUNDLE-1:0]   fifo_plus_fetch [0:FIFO_DEPTH+1];
reg [W_BUNDLE-1:0]   fifo_mem_next   [0:FIFO_DEPTH-1];
reg [FIFO_DEPTH+1:0] fifo_err_plus_fetch;
reg [FIFO_DEPTH-1:0] fifo_err_next;
reg [FIFO_DEPTH-1:0] fifo_valid_next;

always @ (*) begin: fifo_shift
	integer i;
	for (i = 0; i < FIFO_DEPTH + 2; i = i + 1) begin
		if (fifo_valid[i]) begin
			fifo_plus_fetch[i] = fifo_mem[i];
			fifo_err_plus_fetch[i] = fifo_err[i];
		end else if (fifo_valid[i - 1] && mem_data_hwvalid[0]) begin
			fifo_plus_fetch[i] = mem_data[0 * W_BUNDLE +: W_BUNDLE];
			fifo_err_plus_fetch[i] = mem_data_err;
		end else begin
			fifo_plus_fetch[i] = mem_data[1 * W_BUNDLE +: W_BUNDLE];
			fifo_err_plus_fetch[i] = mem_data_err;
		end
	end
	for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
		if (cir_use[1]) begin
			fifo_mem_next[i] = fifo_plus_fetch[i + 2];
		end else if (cir_use[0]) begin
			fifo_mem_next[i] = fifo_plus_fetch[i + 1];
		end else begin
			fifo_mem_next[i] = fifo_plus_fetch[i];
		end
	end
	if (jump_now) begin
		fifo_err_next = {FIFO_DEPTH{1'b0}};
		if (cir_lock) begin
			// Flush all but oldest instruction
			fifo_valid_next = {{FIFO_DEPTH-2{1'b0}}, fifo_mem[0][1:0] == 2'b11, 1'b1};
		end else begin
			fifo_valid_next = {FIFO_DEPTH{1'b0}};
		end
	end else begin
		fifo_valid_next = ~(~fifo_valid[FIFO_DEPTH-1:0]
			<< (fifo_push && mem_data_hwvalid[0])
			<< (fifo_push && mem_data_hwvalid[1])
		) >> cir_use;
		fifo_err_next = fifo_err_plus_fetch >> cir_use;
	end
end

// TODO: instruction injection.
// TODO: CIR locking.

always @ (posedge clk or negedge rst_n) begin: fifo_update
	integer i;
	if (!rst_n) begin
		for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
			fifo_mem[i] <= {W_BUNDLE{1'b0}};
		end
		fifo_valid[FIFO_DEPTH-1:0] <= {FIFO_DEPTH{1'b0}};
	end else begin
		// Don't clock registers whose contents we won't care about on the
		// next cycle (note: inductively, if we don't care about it now we
		// will never care about it until we write new data to it.)
		for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
			if (fifo_valid_next[i]) begin
				fifo_mem[i] <= fifo_mem_next[i];
			end
		end
		fifo_valid[FIFO_DEPTH-1:0] <= fifo_valid_next;
		fifo_err[FIFO_DEPTH-1:0] <= fifo_err_next;
	end
end

// ----------------------------------------------------------------------------
// Fetch Request + State Logic

// Keep track of some useful state of the memory interface

reg        mem_addr_hold;
reg  [1:0] pending_fetches;
reg  [1:0] ctr_flush_pending;
wire [1:0] pending_fetches_next = pending_fetches + (mem_addr_vld && !mem_addr_hold) - mem_data_vld;

// Debugger only injects instructions when the frontend is at rest and empty.
assign dbg_instr_data_rdy = DEBUG_SUPPORT && !fifo_valid[0] && ~|ctr_flush_pending;

assign fifo_push = mem_data_vld && ~|ctr_flush_pending
	&& !(DEBUG_SUPPORT && debug_mode);

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mem_addr_hold <= 1'b0;
		pending_fetches <= 2'h0;
		ctr_flush_pending <= 2'h0;
	end else begin
`ifdef FORMAL
		assert(ctr_flush_pending <= pending_fetches);
		assert(pending_fetches < 2'd3);
		assert(!(mem_data_vld && !pending_fetches));
`endif
		mem_addr_hold <= mem_addr_vld && !mem_addr_rdy;
		pending_fetches <= pending_fetches_next;
		if (jump_now) begin
			ctr_flush_pending <= pending_fetches - mem_data_vld;
		end else if (|ctr_flush_pending && mem_data_vld) begin
			ctr_flush_pending <= ctr_flush_pending - 1'b1;
		end
	end
end

// Fetch addr runs ahead of the PC, in word increments.
reg [W_ADDR-1:0] fetch_addr;
reg              fetch_priv;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		fetch_addr <= RESET_VECTOR;
		// M-mode at reset:
		fetch_priv <= 1'b1;
	end else begin
		if (jump_now) begin
			// Post-increment if jump request is going straight through
			fetch_addr <= {jump_target[W_ADDR-1:2] + (mem_addr_rdy && !mem_addr_hold), 2'b00};
			fetch_priv <= jump_priv || !U_MODE;
		end else if (mem_addr_vld && mem_addr_rdy) begin
			fetch_addr <= fetch_addr + 32'h4;
		end
	end
end

wire unaligned_jump_now = EXTENSION_C && jump_now && jump_target[1];
reg unaligned_jump_dph;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		unaligned_jump_dph <= 1'b0;
	end else if (EXTENSION_C) begin
		if ((mem_data_vld && ~|ctr_flush_pending)
			|| (jump_now && !unaligned_jump_now)) begin
			unaligned_jump_dph <= 1'b0;
		end
		if (unaligned_jump_now) begin
			unaligned_jump_dph <= 1'b1;
		end
	end
end

`ifdef FORMAL
reg property_after_aligned_jump;
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		property_after_aligned_jump <= 1'b0;
	end else begin
		property_after_aligned_jump <= jump_now && !jump_target[1];
		if (property_after_aligned_jump) begin
			// Make sure this clears properly (have been subtle historic bugs here)
			assert(!unaligned_jump_dph);
		end
	end
end
`endif

assign mem_data_hwvalid = {1'b1, !unaligned_jump_dph};

// Combinatorially generate the address-phase request

reg reset_holdoff;
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		reset_holdoff <= 1'b1;
	end else begin
		reset_holdoff <= 1'b0;
		// This should be impossible, but assert to be sure, because it *will*
		// change the fetch address (and we can avoid checking in hardware if
		// we can prove it doesn't happen)
`ifdef FORMAL
		assert(!(jump_target_vld && reset_holdoff));
`endif
	end
end

reg [W_ADDR-1:0] mem_addr_r;
reg              mem_priv_r;
reg              mem_addr_vld_r;

// Downstream accesses are always word-sized word-aligned.
assign mem_addr = mem_addr_r;
assign mem_priv = mem_priv_r;
assign mem_addr_vld = mem_addr_vld_r && !reset_holdoff;
assign mem_size = 1'b1;

// Using the non-registered version of pending_fetches would improve FIFO
// utilisation, but create a combinatorial path from hready to address phase!
// This means at least a 2-word FIFO is required for full fetch throughput.
wire fetch_stall = fifo_full
	|| fifo_almost_full && |pending_fetches
	|| pending_fetches > 2'h1;

always @ (*) begin
	mem_addr_r = fetch_addr;
	mem_priv_r = fetch_priv;
	mem_addr_vld_r = 1'b1;
	case (1'b1)
		mem_addr_hold               : begin mem_addr_r = fetch_addr; end
		jump_target_vld             : begin
		                                    mem_addr_r = {jump_target[W_ADDR-1:2], 2'b00};
		                                    mem_priv_r = jump_priv || !U_MODE;
		end
		DEBUG_SUPPORT && debug_mode : begin mem_addr_vld_r = 1'b0; end
		!fetch_stall                : begin mem_addr_r = fetch_addr; end
		default                     : begin mem_addr_vld_r = 1'b0; end
	endcase
end

assign jump_target_rdy = !mem_addr_hold;

// ----------------------------------------------------------------------------
// Instruction assembly yard

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		cir_vld <= 2'h0;
	end else begin
`ifdef FORMAL
		assert(cir_vld <= 2);
 		assert(cir_use <= cir_vld);
`endif
		cir_vld <= {fifo_valid_next[1], fifo_valid_next[0] && !fifo_valid_next[1]};
	end
end

assign cir = {fifo_mem[1], fifo_mem[0]};
assign cir_err = fifo_err[1:0];

// ----------------------------------------------------------------------------
// Register number predecode

wire [31:0] next_instr = {fifo_mem_next[1], fifo_mem_next[0]};
wire next_instr_is_32bit = next_instr[1:0] == 2'b11 || ~|EXTENSION_C;

always @ (*) begin

	casez ({next_instr_is_32bit, next_instr[1:0], next_instr[15:13]})
	{1'b1, 2'bzz, 3'bzzz}: predecode_rs1_coarse = next_instr[19:15]; // 32-bit R, S, B formats
	{1'b0, 2'b00, 3'bz00}: predecode_rs1_coarse = 5'd2;              // c.addi4spn + don't care
	{1'b0, 2'b01, 3'b0zz}: predecode_rs1_coarse = next_instr[11:7];  // c.addi, c.addi16sp + don't care (jal, li)
	{1'b0, 2'b10, 3'bz1z}: predecode_rs1_coarse = 5'd2;              // c.lwsp, c.lwsp + don't care
	{1'b0, 2'b10, 3'bz0z}: predecode_rs1_coarse = next_instr[11:7];
	default:               predecode_rs1_coarse = {2'b01, next_instr[9:7]};
	endcase

	casez ({next_instr_is_32bit, next_instr[1:0]})
	{1'b1, 2'bzz}: predecode_rs2_coarse = next_instr[24:20];
	{1'b0, 2'b10}: predecode_rs2_coarse = next_instr[6:2];
	default:       predecode_rs2_coarse = {2'b01, next_instr[4:2]};
	endcase

	// The "fine" predecode targets those instructions which either:
	// - Have an implicit zero-register operand in their expanded form (e.g. c.beqz)
	// - Do not have a register operand on that port, but rely on the port being 0
	// We don't care about instructions which ignore the reg ports, e.g. ebreak

	casez ({|EXTENSION_C, next_instr})
	// -> addi rd, x0, imm:
	{1'b1, 16'hzzzz, RV_C_LI  }: predecode_rs1_fine = 5'd0;
	{1'b1, 16'hzzzz, RV_C_MV  }: begin
		if (next_instr[6:2] == 5'd0) begin
			// c.jr has rs1 as normal
			predecode_rs1_fine = predecode_rs1_coarse;
		end else begin
			// -> add rd, x0, rs2:
			predecode_rs1_fine = 5'd0;
		end
	end
	default: predecode_rs1_fine = predecode_rs1_coarse;
	endcase

	casez ({|EXTENSION_C, next_instr})
	{1'b1, 16'hzzzz, RV_C_BEQZ}: predecode_rs2_fine = 5'd0;    // -> beq rs1, x0, label
	{1'b1, 16'hzzzz, RV_C_BNEZ}: predecode_rs2_fine = 5'd0;    // -> bne rs1, x0, label
	default:                     predecode_rs2_fine = predecode_rs2_coarse;
	endcase


end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
