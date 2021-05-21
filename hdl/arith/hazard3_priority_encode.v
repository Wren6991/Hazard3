/******************************************************************************
 *     DO WHAT THE FUCK YOU WANT TO AND DON'T BLAME US PUBLIC LICENSE         *
 *                        Version 3, April 2008                               *
 *                                                                            *
 *     Copyright (C) 2019 Luke Wren                                           *
 *                                                                            *
 *     Everyone is permitted to copy and distribute verbatim or modified      *
 *     copies of this license document and accompanying software, and         *
 *     changing either is allowed.                                            *
 *                                                                            *
 *       TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION      *
 *                                                                            *
 *     0. You just DO WHAT THE FUCK YOU WANT TO.                              *
 *     1. We're NOT RESPONSIBLE WHEN IT DOESN'T FUCKING WORK.                 *
 *                                                                            *
 *****************************************************************************/

// Really something like this should be in a utility library (or the language!),
// but Hazard3 is supposed to be self-contained

module hazard3_priority_encode #(
	parameter W_REQ = 16,
	parameter W_GNT = $clog2(W_REQ) // do not modify
) (
	input  wire [W_REQ-1:0] req,
	output wire [W_GNT-1:0] gnt
);

// First do a priority-select of the input bitmap.

reg [W_REQ-1:0] deny;

always @ (*) begin: smear
	integer i;
	deny[0] = 1'b0;
	for (i = 1; i < W_REQ; i = i + 1)
		deny[i] = deny[i - 1] || req[i - 1];
end

wire [W_REQ-1:0] gnt_onehot = req & ~deny;

// As the result is onehot, we can now just OR in the representation of each
// encoded integer.

reg [W_GNT-1:0] gnt_accum;

always @ (*) begin: encode
	integer i;
	gnt_accum = {W_GNT{1'b0}};
	for (i = 0; i < W_REQ; i = i + 1) begin
		gnt_accum = gnt_accum | ({W_GNT{gnt_onehot[i]}} & i[W_GNT-1:0]);
	end
end

assign gnt = gnt_accum;

endmodule
