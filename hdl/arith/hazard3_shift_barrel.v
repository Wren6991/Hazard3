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

// Implement the three shifts (left logical, right logical, right arithmetic)
// using a single log-type barrel shifter. Around 240 LUTs for 32 bits.
// (7 layers of 32 2-input muxes, some extra LUTs and LUT inputs used for arith)

`default_nettype none

module hazard3_shift_barrel #(
`include "hazard3_config.vh"
,
`include "hazard3_width_const.vh"
) (
	input wire [W_DATA-1:0]  din,
	input wire [W_SHAMT-1:0] shamt,
	input wire               right_nleft,
	input wire               rotate,
	input wire               arith,
	output reg [W_DATA-1:0]  dout
);

reg [W_DATA-1:0] din_rev;
reg [W_DATA-1:0] shift_accum;
reg sext; // haha

always @ (*) begin: shift
	integer i;

	for (i = 0; i < W_DATA; i = i + 1)
		din_rev[i] = right_nleft ? din[W_DATA - 1 - i] : din[i];

	sext = arith && din_rev[0];

	shift_accum = din_rev;
	for (i = 0; i < W_SHAMT; i = i + 1) begin
		if (shamt[i]) begin
			shift_accum = (shift_accum << (1 << i)) |
				({W_DATA{sext}} & ~({W_DATA{1'b1}} << (1 << i))) |
				({W_DATA{rotate && |EXTENSION_ZBB}} & (shift_accum >> (W_DATA - (1 << i))));
		end
	end

	for (i = 0; i < W_DATA; i = i + 1)
		dout[i] = right_nleft ? shift_accum[W_DATA - 1 - i] : shift_accum[i];
end

`ifdef FORMAL
always @ (*) begin
	if (right_nleft && arith) begin: asr
		assert($signed(dout) == $signed(din) >>> $signed(shamt));
	end else if (right_nleft && !arith) begin
		assert(dout == din >> shamt);
	end else if (!right_nleft && !arith) begin
		assert(dout == din << shamt);
	end
end
`endif

endmodule

`default_nettype wire
