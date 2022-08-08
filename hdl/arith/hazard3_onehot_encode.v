/*****************************************************************************\
|                         Copyright (C) 2022 Luke Wren                        |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// req: one-hot bitmap
// idx: index of the sole set bit in req

`default_nettype none

module hazard3_onehot_encode #(
	parameter W_REQ = 16,
	parameter W_GNT = $clog2(W_REQ) // do not modify
) (
	input  wire [W_REQ-1:0] req,
	output reg  [W_GNT-1:0] gnt
);

always @ (*) begin: encode
	reg [W_GNT:0] i;
	gnt = {W_GNT{1'b0}};
	for (i = 0; i < W_REQ; i = i + 1) begin
		gnt = gnt | ({W_GNT{req[i]}} & i[W_GNT-1:0]);
	end
end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
