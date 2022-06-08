/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Really something like this should be in a utility library (or the language!),
// but Hazard3 is supposed to be self-contained

`default_nettype none

module hazard3_priority_encode #(
	parameter W_REQ = 16,
	parameter W_GNT = $clog2(W_REQ) // do not modify
) (
	input  wire [W_REQ-1:0] req,
	output wire [W_GNT-1:0] gnt
);

// First do a priority-select of the input bitmap.

reg [W_REQ-1:0] gnt_onehot;

always @ (*) begin: smear
	integer i;
	for (i = 0; i < W_REQ; i = i + 1)
		gnt_onehot[i] = req[i] && ~|(req & ~({W_REQ{1'b1}} << i));
end

// As the result is onehot, we can now just OR in the representation of each
// encoded integer.

reg [W_GNT-1:0] gnt_accum;

always @ (*) begin: encode
	reg [W_GNT:0] i;
	gnt_accum = {W_GNT{1'b0}};
	for (i = 0; i < W_REQ; i = i + 1) begin
		gnt_accum = gnt_accum | ({W_GNT{gnt_onehot[i]}} & i[W_GNT-1:0]);
	end
end

assign gnt = gnt_accum;

endmodule

`default_nettype wire
