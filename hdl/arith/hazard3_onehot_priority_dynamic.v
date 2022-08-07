/*****************************************************************************\
|                         Copyright (C) 2022 Luke Wren                        |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// req:      bitmap of requests
// priority: packed array of dynamic priority level of each request
// gnt:      one-hot bitmap with the highest-priority request.

`default_nettype none

module hazard3_onehot_priority_dynamic #(
	parameter W_REQ                 = 8,
	parameter N_PRIORITIES          = 2,
	parameter PRIORITY_HIGHEST_WINS = 1, // If 1, numerically highest level has greatest priority.
	                                     // Otherwise, numerically lowest wins.
	parameter TIEBREAK_HIGHEST_WINS = 0, // If 1, highest-numbered request at the highest priority
	                                     // level wins the tiebreak. Otherwise, lowest-numbered.
	// Do not modify:
	parameter W_PRIORITY            = $clog2(N_PRIORITIES)
) (
	input  wire [W_REQ*W_PRIORITY-1:0] pri,
	input  wire [W_REQ-1:0]            req,
	output wire [W_REQ-1:0]            gnt
);

// 1. Stratify requests according to their level
reg [W_REQ-1:0]        req_stratified [0:N_PRIORITIES-1];
reg [N_PRIORITIES-1:0] level_has_req;

always @ (*) begin: stratify
	integer i, j;
	for (i = 0; i < N_PRIORITIES; i = i + 1) begin
		for (j = 0; j < W_REQ; j = j + 1) begin
			req_stratified[i][j] = req[j] && pri[W_PRIORITY * j +: W_PRIORITY] == i;
		end
		level_has_req[i] = |req_stratified[i];
	end
end

// 2. Select the highest level with active requests
wire [N_PRIORITIES-1:0] active_layer_sel;

hazard3_onehot_priority #(
	.W_REQ        (N_PRIORITIES),
	.HIGHEST_WINS (PRIORITY_HIGHEST_WINS)
) prisel_layer (
	.req (level_has_req),
	.gnt (active_layer_sel)
);

// 3. Mask only those requests at this level
reg [W_REQ-1:0] reqs_from_highest_layer;

always @ (*) begin: mux_reqs_by_layer
	integer i;
	reqs_from_highest_layer = {W_REQ{1'b0}};
	for (i = 0; i < N_PRIORITIES; i = i + 1)
		reqs_from_highest_layer = reqs_from_highest_layer |
			(req_stratified[i] & {W_REQ{active_layer_sel[i]}});
end

// 4. Do a standard priority select on those requests as a tie break
hazard3_onehot_priority #(
	.W_REQ        (W_REQ),
	.HIGHEST_WINS (TIEBREAK_HIGHEST_WINS)
) prisel_tiebreak (
	.req (reqs_from_highest_layer),
	.gnt (gnt)
);

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
