/*****************************************************************************\
|                        Copyright (C) 2022 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

// The branch decision path through the ALU is slow because:
//
// - Sees immediates and PC on its inputs, as well as regs
// - Add/sub rather than just add (with complex decode of the sub condition)
// - 2 extra mux layers in front of adder if Zba extension is enabled
//
// So there is sometimes timing benefit to a dedicated branch comparator.

module hazard3_branchcmp #(
`include "hazard3_config.vh"
,
`include "hazard3_width_const.vh"
) (
	input  wire [W_ALUOP-1:0] aluop,
	input  wire [W_DATA-1:0]  op_a,
	input  wire [W_DATA-1:0]  op_b,
	output wire               cmp
);

`include "hazard3_ops.vh"

wire [W_DATA-1:0] diff = op_a - op_b;

wire cmp_is_unsigned = aluop[2]; // aluop == ALUOP_LTU;

wire lt = op_a[W_DATA-1] == op_b[W_DATA-1] ? diff[W_DATA-1] :
          cmp_is_unsigned                  ? op_b[W_DATA-1] :
                                             op_a[W_DATA-1] ;

// ALUOP_SUB is used for equality check by main ALU
assign cmp = aluop[0] ? op_a != op_b : lt;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
