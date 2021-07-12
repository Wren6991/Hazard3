/**********************************************************************
 * DO WHAT THE FUCK YOU WANT TO AND DON'T BLAME US PUBLIC LICENSE     *
 *                    Version 3, April 2008                           *
 *                                                                    *
 * Copyright (C) 2021 Luke Wren                                       *
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

// The output is asserted asynchronously when the input is asserted,
// but deasserted synchronously when clocked with the input deasserted.
// Input and output are both active-low.
//
// This is a baseline implementation -- you should replace it with cells
// specific to your FPGA/process

`ifndef HAZARD3_REG_KEEP_ATTRIBUTE
`define HAZARD3_REG_KEEP_ATTRIBUTE (* keep = 1'b1 *)
`endif

module hazard3_reset_sync #(
	parameter N_STAGES = 2 // Should be >= 2
) (
	input  wire clk,
	input  wire rst_n_in,
	output wire rst_n_out
);

`HAZARD3_REG_KEEP_ATTRIBUTE reg [N_STAGES-1:0] delay;

always @ (posedge clk or negedge rst_n_in)
	if (!rst_n_in)
		delay <= {N_STAGES{1'b0}};
	else
		delay <= {delay[N_STAGES-2:0], 1'b1};

assign rst_n_out = delay[N_STAGES-1];

endmodule
