/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// req: bitmap
// gnt: index of least set bit (HIGHEST_WINS=0) or most set bit (HIGHEST_WINS=1)

`default_nettype none

module hazard3_priority_encode #(
	parameter W_REQ        = 16,
	parameter HIGHEST_WINS = 0,
	parameter W_GNT        = $clog2(W_REQ) // do not modify
) (
	input  wire [W_REQ-1:0] req,
	output wire [W_GNT-1:0] gnt
);

wire [W_REQ-1:0] gnt_onehot;

hazard3_onehot_priority #(
	.W_REQ        (W_REQ),
	.HIGHEST_WINS (HIGHEST_WINS)
) priority_u (
	.req (req),
	.gnt (gnt_onehot)
);

hazard3_onehot_encode #(
	.W_REQ (W_REQ)
) encode_u (
	.req (gnt_onehot),
	.gnt (gnt)
);

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
