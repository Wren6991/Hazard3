/*****************************************************************************\
|                         Copyright (C) 2022 Luke Wren                        |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// req: bitmap
// idx: bitmap with all bits clear except the least- (HIGHEST_WINS=0) or
//      most- (HIGHEST_WINS=1) significant set bit in req.

`default_nettype none

module hazard3_onehot_priority #(
	parameter W_REQ        = 16,
	parameter HIGHEST_WINS = 0
) (
	input  wire [W_REQ-1:0] req,
	output reg  [W_REQ-1:0] gnt
);

always @ (*) begin: select
	integer i;
	for (i = 0; i < W_REQ; i = i + 1) begin
		gnt[i] = req[i] && ~|(req & (
			HIGHEST_WINS ? ~({W_REQ{1'b1}} >> (W_REQ - 1 - i)) : ~({W_REQ{1'b1}} << i)
		));
	end
end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
