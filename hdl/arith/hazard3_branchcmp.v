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
	input  wire [31:0]        cir,
	input  wire [W_DATA-1:0]  op_a,
	input  wire [W_DATA-1:0]  op_b,
	output wire               cmp
);

`include "hazard3_ops.vh"

wire [W_DATA-1:0] diff = op_a - op_b;

// funct3 instruction
// ------------------
// 000    BEQ
// 001    BNE
// 010    BEQI (Zibi only)
// 011    BNEI (Zibi only)
// 100    BLT
// 101    BGE
// 110    BLTU
// 111    BGEU

wire cmp_is_unsigned = cir[13];

wire lt = op_a[W_DATA-1] == op_b[W_DATA-1] ? diff[W_DATA-1] :
          cmp_is_unsigned                  ? op_b[W_DATA-1] :
                                             op_a[W_DATA-1] ;

wire [31:0] zibi_imm = {27'd0, cir[24:20]} | {32{~|cir[24:20]}};
wire eq = op_a == (cir[13] && |EXTENSION_ZIBI ? zibi_imm : op_b);

assign cmp = cir[14] ? lt : eq;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
