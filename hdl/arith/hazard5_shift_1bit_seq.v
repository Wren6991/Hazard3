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

module hazard5_shift_1bit_seq #(
	parameter W_DATA = 32,
	parameter W_SHAMT = 5
) (
	input wire                clk,
	input wire                rst_n,

	input wire  [W_DATA-1:0]  din,
	input wire                din_vld, // can be asserted at any time, we always respond
	input wire  [W_SHAMT-1:0] shamt,
	input wire                right_nleft,
	input wire                arith,
	output wire [W_DATA-1:0]  dout,
	output wire               dout_vld,
);

reg [W_DATA-1:0]  accum;
reg [W_DATA-1:0]  accum_next;
reg [W_SHAMT-1:0] shamt_remaining;
reg               flipped;

// Handle actual shifting

wire sext = arith && accum[W_DATA - 1];

always @ (*) begin: shift_unit
	accum_next = accum;
	if (din_vld) begin
		accum_next = din;
	end else if (shamt_remaining) begin
		if (right_nleft)
			accum_next = {sext, accum[W_DATA-1:1]};
		else
			accum_next = {accum << 1};
	end
end

// No reset on datapath
always @ (posedge clk)
	accum <= accum_next;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		shamt_remaining <= {W_SHAMT{1'b0}};
	end else if (din_vld) begin
		shamt_remaining <= shamt;
	end else begin
		shamt_remaining <= shamt_remaining - |shamt_remaining;
	end
end

assign dout_vld = shamt_remaining == 0;
assign dout = accum;

endmodule
