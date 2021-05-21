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

// Implement the three shifts using a single log-sequential shifter.
// On each clock, the shifter can left-shift by a power-of-two amount (arith or
// logical), OR it can reverse the accumulator.
//
// The accumulator is wired in reverse to the output. So the sequences are:
// - Right shift: flip, then shift. Output wiring flips again. Internal left-shifts
//   are effectively right shifts.
// - Left shift: perform shift ops, then flip, so that reversed output cancels.
//
// An additional cycle is consumed to load the input into the accumulator; this
// simplifies muxing. In total, a shift consumes between 2 and 7 cycles on a
// 32-bit machine, depending on the bit weight of shamt.

module hazard5_shift_log_seq #(
	parameter W_DATA = 32,
	parameter W_SHAMT = 5
) (
	input wire               clk,
	input wire               rst_n,

	input wire [W_DATA-1:0]  din,
	input wire               din_vld, // can be asserted at any time, we always respond
	input wire [W_SHAMT-1:0] shamt,
	input wire               right_nleft,
	input wire               arith,
	output reg [W_DATA-1:0]  dout,
	output reg               dout_vld,
);

reg [W_DATA-1:0]  accum;
reg [W_DATA-1:0]  accum_next;
reg [W_SHAMT-1:0] shamt_remaining;
reg               flipped;

// Handle actual shifting

wire flip = !flipped && (right_nleft || ~|shamt_remaining);
wire sext = arith && accum[0]; // "Left arithmetic" shifting

always @ (*) begin: shift_unit
	integer i;
	accum_next = accum;
	// The following is a priority mux tree (honest) which the synthesis tool should balance
	if (din_vld) begin
		accum_next = din;
	end else if (flip) begin
		for (i = 0; i < W_DATA; i = i + 1)
			accum_next[i] = accum[W_DATA - 1 - i];
	end else if (shamt_remaining) begin
		// Smallest shift first
		for (i = 0; i < W_SHAMT; i = i + 1) begin
			if (shamt_remaining[i] && ~|(shamt_remaining & ~({W_SHAMT{1'b1}} << i))) begin
				accum_next = (accum << (1 << i)) |
					({W_DATA{sext}} & ~({W_DATA{1'b1}} << (1 << i)));
			end
		end
	end
end

// No reset on datapath
always @ (posedge clk)
	accum <= accum_next;

// State machine

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		shamt_remaining <= {W_SHAMT{1'b0}};
		flipped <= 1'b0;
	end else if (din_vld) begin
		shamt_remaining <= shamt;
		flipped <= 1'b0;
	end else begin
		if (flip)
			flipped <= 1'b1;
		else
			shamt_remaining <= shamt_remaining & {shamt_remaining - 1'b1};
	end
end


always @ (*) begin: connect_output
	dout_vld = flipped && ~|shamt_remaining;
	integer i;
	for (i = 0; i < W_DATA; i = i + 1)
		dout[i] = accum[W_DATA - 1 - i];
end

endmodule
