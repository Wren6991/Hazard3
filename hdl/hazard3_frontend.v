/*****************************************************************************\
|                        Copyright (C) 2021 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module hazard3_frontend #(
	parameter FIFO_DEPTH = 2,  // power of 2, >= 1
`include "hazard3_config.vh"
) (
	input wire clk,
	input wire rst_n,

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
	// Note reg/wire distinction
	// => decode is providing live feedback on the CIR it is decoding,
	//    which we fetched previously
	// This works OK because size is decoded from 2 LSBs of instruction, so cheap.
	output reg  [31:0]       cir,
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

localparam W_BUNDLE = W_DATA / 2;
parameter W_FIFO_LEVEL = $clog2(FIFO_DEPTH + 1);

// ----------------------------------------------------------------------------
// Fetch Queue (FIFO)
//
// This is a little different from either a normal sync fifo or sync fwft fifo
// so it's worth implementing from scratch

wire jump_now = jump_target_vld && jump_target_rdy;

// mem has an extra entry which is equal to next-but-last entry, and valid has
// an extra entry which is constant-0. These are just there to handle loop
// boundary conditions.

// err has an error (HRESP) bit associated with each FIFO entry, so that we
// can correctly speculate and flush fetch errors. The error bit moves
// through the prefetch queue alongside the corresponding bus data. We sample
// bus errors like an extra data bit -- fetch continues to speculate forward
// past an error, and we eventually flush and redirect the frontent if an
// errored fetch makes it to the execute stage.

reg [W_DATA-1:0]   fifo_mem [0:FIFO_DEPTH];
reg [FIFO_DEPTH:0] fifo_err;
reg [FIFO_DEPTH:0] fifo_valid;

wire [W_DATA-1:0] fifo_wdata = mem_data;
wire [W_DATA-1:0] fifo_rdata = fifo_mem[0];
always @ (*) fifo_mem[FIFO_DEPTH] = fifo_wdata;

wire fifo_full = fifo_valid[FIFO_DEPTH - 1];
wire fifo_empty = !fifo_valid[0];
wire fifo_almost_full = FIFO_DEPTH == 1 || (!fifo_valid[FIFO_DEPTH - 1] && fifo_valid[FIFO_DEPTH - 2]);

wire fifo_push;
wire fifo_pop;
wire fifo_dbg_inject = DEBUG_SUPPORT && dbg_instr_data_vld && dbg_instr_data_rdy;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		fifo_valid <= {FIFO_DEPTH+1{1'b0}};
	end else if (jump_now) begin
		fifo_valid <= {FIFO_DEPTH+1{1'b0}};
	end else if (fifo_push || fifo_pop || fifo_dbg_inject) begin
		fifo_valid <= {1'b0, ~(~fifo_valid << (fifo_push || fifo_dbg_inject)) >> fifo_pop};
	end
end

always @ (posedge clk) begin: fifo_data_shift
	integer i;
	for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
		if (fifo_pop || (fifo_push && !fifo_valid[i])) begin
			fifo_mem[i] <= fifo_valid[i + 1] ? fifo_mem[i + 1] : fifo_wdata;
			fifo_err[i] <= fifo_err[i + 1] ? fifo_err[i + 1] : mem_data_err;
		end
	end
	// Allow DM to inject instructions directly into the lowest-numbered queue
	// entry. This mux should not extend critical path since it is balanced
	// with the instruction-assembly muxes on the queue bypass path.
	if (fifo_dbg_inject) begin
		fifo_mem[0] <= dbg_instr_data;
		fifo_err[0] <= 1'b0;
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

wire cir_must_refill;
// If fetch data is forwarded past the FIFO, ensure it is not also written to it.
assign fifo_push = mem_data_vld && ~|ctr_flush_pending && !(cir_must_refill && fifo_empty)
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

// Using the non-registered version of pending_fetches would improve FIFO
// utilisation, but create a combinatorial path from hready to address phase!
wire fetch_stall = fifo_full
	|| fifo_almost_full && |pending_fetches    // TODO causes issue with depth 1: only one in flight, so bus rate halved.
	|| pending_fetches > 2'h1;


// unaligned jump is handled in two different places:
// - during address phase, offset may be applied to fetch_addr if hready was low when jump_target_vld was high
// - during data phase, need to assemble CIR differently.


wire unaligned_jump_now = EXTENSION_C && jump_now && jump_target[1];
reg unaligned_jump_aph;
reg unaligned_jump_dph;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		unaligned_jump_aph <= 1'b0;
		unaligned_jump_dph <= 1'b0;
	end else if (EXTENSION_C) begin
		if (mem_addr_rdy || (jump_now && !unaligned_jump_now)) begin
			unaligned_jump_aph <= 1'b0;
		end
		if ((mem_data_vld && ~|ctr_flush_pending && !cir_lock)
			|| (jump_now && !unaligned_jump_now)) begin
			unaligned_jump_dph <= 1'b0;
		end
		if (fifo_pop) begin
			// Following a lock/unlock of the CIR, we may have an unaligned fetch in
			// the FIFO, rather than consuming straight from the bus.
			unaligned_jump_dph <= 1'b0;
		end
		if (unaligned_jump_now) begin
			unaligned_jump_dph <= 1'b1;
			unaligned_jump_aph <= !mem_addr_rdy;
		end
	end
end

`ifdef FORMAL
reg property_after_aligned_jump;
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		property_after_aligned_jump <= 1'b0;
	end else begin
		// Every unaligned jump that requires care in aphase also requires care in dphase.
		assert(!(unaligned_jump_aph && !unaligned_jump_dph));

		property_after_aligned_jump <= jump_now && !jump_target[1];
		if (property_after_aligned_jump) begin
			// Make sure these clear properly (have been subtle historic bugs here)
			assert(!unaligned_jump_aph);
			assert(!unaligned_jump_dph);
		end
	end
end
`endif


// Combinatorially generate the address-phase request

reg reset_holdoff;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		reset_holdoff <= 1'b1;
	else
		reset_holdoff <= 1'b0;

reg [W_ADDR-1:0] mem_addr_r;
reg              mem_priv_r;
reg              mem_addr_vld_r;

// Downstream accesses are always word-sized word-aligned.
assign mem_addr = mem_addr_r;
assign mem_priv = mem_addr_r;
assign mem_addr_vld = mem_addr_vld_r && !reset_holdoff;
assign mem_size = 1'b1;

always @ (*) begin
	mem_addr_r = {W_ADDR{1'b0}};
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

// buf_level is the number of valid halfwords in {hwbuf, cir}.
reg [1:0] buf_level;
reg [W_BUNDLE-1:0] hwbuf;

wire [W_DATA-1:0] fetch_data = fifo_empty ? mem_data : fifo_rdata;
wire fetch_data_vld = !fifo_empty || (mem_data_vld && ~|ctr_flush_pending && !debug_mode);

// Shift any recycled instruction data down to backfill D's consumption
// We don't care about anything which is invalid or will be overlaid with fresh data,
// so choose these values in a way that minimises muxes
wire [3*W_BUNDLE-1:0] instr_data_shifted =
	cir_use[1]                ? {hwbuf, cir[W_BUNDLE +: W_BUNDLE], hwbuf} :
	cir_use[0] && EXTENSION_C ? {hwbuf, hwbuf, cir[W_BUNDLE +: W_BUNDLE]} :
	                            {hwbuf, cir};

// Saturating subtraction: on cir_lock dassertion,
// buf_level will be 0 but cir_use will be positive!
wire [1:0] cir_use_clipped = |buf_level ? cir_use : 2'h0;

wire [1:0] level_next_no_fetch = buf_level - cir_use_clipped;

// Overlay fresh fetch data onto the shifted/recycled instruction data
// Again, if something won't be looked at, generate cheapest possible garbage.
// Don't care if fetch data is valid or not, as will just retry next cycle (as long as flags set correctly)
wire instr_fetch_overlay_blocked = cir_lock || (level_next_no_fetch[1] && !unaligned_jump_dph);

wire [3*W_BUNDLE-1:0] instr_data_plus_fetch =
	instr_fetch_overlay_blocked           ? instr_data_shifted :
	unaligned_jump_dph     && EXTENSION_C ? {instr_data_shifted[W_BUNDLE +: 2*W_BUNDLE], fetch_data[W_BUNDLE +: W_BUNDLE]} :
	level_next_no_fetch[0] && EXTENSION_C ? {fetch_data, instr_data_shifted[0 +: W_BUNDLE]} :
	                         {instr_data_shifted[2*W_BUNDLE +: W_BUNDLE], fetch_data};

assign cir_must_refill = !cir_lock && !level_next_no_fetch[1];
assign fifo_pop = cir_must_refill && !fifo_empty;

wire [1:0] buf_level_next =
	jump_now || |ctr_flush_pending || cir_lock ? 2'h0 :
	fetch_data_vld && unaligned_jump_dph ? 2'h1 :
	buf_level + {cir_must_refill && fetch_data_vld, 1'b0} - cir_use_clipped;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		buf_level <= 2'h0;
		cir_vld <= 2'h0;
	end else begin
`ifdef FORMAL
		assert(cir_vld <= 2);
 		assert(cir_use <= cir_vld);
`endif
		// Update CIR flags
		buf_level <= buf_level_next;
		if (!cir_lock)
			cir_vld <= buf_level_next & ~(buf_level_next >> 1'b1);
		// Update CIR contents
	end
end

// No need to reset these as they will be written before first use
always @ (posedge clk)
	{hwbuf, cir} <= instr_data_plus_fetch;

`ifdef FORMAL
reg [1:0] property_past_buf_level; // Workaround for weird non-constant $past reset issue
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		property_past_buf_level <= 2'h0;
	end else begin
		property_past_buf_level <= buf_level;
		// We fetch 32 bits per cycle, max. If this happens it's due to negative overflow.
		if (property_past_buf_level == 2'h0)
			assert(buf_level != 2'h3);
	end
end
`endif

// Also keep track of bus errors associated with CIR contents, shifted in the
// same way as instruction data. Errors may come straight from the bus, or
// may be buffered in the prefetch queue.

wire fetch_bus_err = fifo_empty ? mem_data_err : fifo_err[0];

reg  [2:0] cir_bus_err;
wire [2:0] cir_bus_err_shifted =
	cir_use[1]                ? cir_bus_err >> 2 :
	cir_use[0] && EXTENSION_C ? cir_bus_err >> 1 : cir_bus_err;

wire [2:0] cir_bus_err_plus_fetch =
	instr_fetch_overlay_blocked        ? cir_bus_err_shifted :
	unaligned_jump_dph  && EXTENSION_C ? {cir_bus_err_shifted[2:1], fetch_bus_err} :
	level_next_no_fetch && EXTENSION_C ? {{2{fetch_bus_err}}, cir_bus_err_shifted[0]} :
                                         {cir_bus_err_shifted[2], {2{fetch_bus_err}}};

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		cir_bus_err <= 3'h0;
	end else if (CSR_M_TRAP) begin
		cir_bus_err <= cir_bus_err_plus_fetch;
	end
end

assign cir_err = cir_bus_err[1:0];

// ----------------------------------------------------------------------------
// Register number predecode

wire [31:0] next_instr = instr_data_plus_fetch[31:0];
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
