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

module hazard3_alu #(
	parameter W_DATA = 32
) (
	input  wire [3:0]        aluop,
	input  wire [W_DATA-1:0] op_a,
	input  wire [W_DATA-1:0] op_b,
	output reg  [W_DATA-1:0] result,
	output wire [W_DATA-1:0] result_add, // for load/stores
	output wire              cmp
);

`include "hazard3_ops.vh"

function msb;
input [W_DATA-1:0] x;
begin
	msb = x[W_DATA-1];
end
endfunction

wire sub = aluop != ALUOP_ADD;
wire [W_DATA-1:0] sum  = op_a + (op_b ^ {W_DATA{sub}}) + sub;
wire [W_DATA-1:0] op_xor = op_a ^ op_b;

wire lt = msb(op_a) == msb(op_b) ? msb(sum)  :
              aluop == ALUOP_LTU ? msb(op_b) :
                                   msb(op_a) ;

assign cmp = aluop == ALUOP_SUB ? |op_xor : lt;
assign result_add = sum;


wire [W_DATA-1:0] shift_dout;
reg shift_right_nleft;
reg shift_arith;

hazard3_shift_barrel #(
	.W_DATA(W_DATA),
	.W_SHAMT(5)
) shifter (
	.din(op_a),
	.shamt(op_b[4:0]),
	.right_nleft(shift_right_nleft),
	.arith(shift_arith),
	.dout(shift_dout)
);

// We can implement all bitwise ops with 1 LUT4/bit total, since each result bit
// uses only two operand bits. Much better than feeding each into main mux tree.

reg [W_DATA-1:0] bitwise;

always @ (*) begin: bitwise_ops
	case (aluop[1:0])
		ALUOP_AND[1:0]: bitwise = op_a & op_b;
		ALUOP_OR[1:0]:  bitwise = op_a | op_b;
		default:        bitwise = op_a ^ op_b;
	endcase
end

always @ (*) begin
	shift_right_nleft = 1'b0;
	shift_arith = 1'b0;
	case (aluop)
		ALUOP_ADD: begin result = sum; end
		ALUOP_SUB: begin result = sum; end
		ALUOP_LT:  begin result = {{W_DATA-1{1'b0}}, lt}; end
		ALUOP_LTU: begin result = {{W_DATA-1{1'b0}}, lt}; end
		ALUOP_SRL: begin shift_right_nleft = 1'b1; result = shift_dout; end
		ALUOP_SRA: begin shift_right_nleft = 1'b1; shift_arith = 1'b1; result = shift_dout; end
		ALUOP_SLL: begin result = shift_dout; end
		default:   begin result = bitwise; end
	endcase
end

`ifdef FORMAL
`ifndef RISCV_FORMAL
// Really we're just interested in the shifts and comparisons, as these are
// the nontrivial ones. However, easier to test everything!

wire clk;
always @ (posedge clk) begin
	case(aluop)
	default: begin end
	ALUOP_ADD: assert(result == op_a + op_b);
	ALUOP_SUB: assert(result == op_a - op_b);
	ALUOP_LT:  assert(result == $signed(op_a) < $signed(op_b));
	ALUOP_LTU: assert(result == op_a < op_b);
	ALUOP_AND: assert(result == (op_a & op_b));
	ALUOP_OR:  assert(result == (op_a | op_b));
	ALUOP_XOR: assert(result == (op_a ^ op_b));
	ALUOP_SRL: assert(result == op_a >> op_b[4:0]);
	ALUOP_SRA: assert($signed(result) == $signed(op_a) >>> $signed(op_b[4:0]));
	ALUOP_SLL: assert(result == op_a << op_b[4:0]);
	endcase
end
`endif
`endif

endmodule
