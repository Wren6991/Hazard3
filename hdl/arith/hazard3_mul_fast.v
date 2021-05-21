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

module hazard3_mul_fast #(
	parameter XLEN = 32
) (
	input  wire              clk,
	input  wire              rst_n,
	input  wire [XLEN-1:0]   op_a,
	input  wire [XLEN-1:0]   op_b,
	input  wire              op_vld,

	output wire [XLEN-1:0]   result,
	output reg               result_vld
);

// This pipestage is folded into the front of the DSP tiles on UP5k. Note the
// intention is to register the bypassed core regs at the end of X (since
// bypass is quite slow), then perform multiply combinatorially in stage M,
// and mux into MW result register.

reg [XLEN-1:0] op_a_r;
reg [XLEN-1:0] op_b_r;

always @ (posedge clk) begin
	if (op_vld) begin
		op_a_r <= op_a;
		op_b_r <= op_b;
	end
end

// This should be inferred as 3 DSP tiles on UP5k:
//
// 1. Register then multiply a[15: 0] and b[15: 0]
// 2. Register then multiply a[31:16] and b[15: 0], then directly add output of 1
// 3. Register then multiply a[15: 0] and b[31:16], then directly add output of 2
//
// So there is quite a long path (1x 16-bit multiply, then 2x 16-bit add). On
// other platforms you may just end up with a pile of gates.

`ifndef RISCV_FORMAL_ALTOPS

assign result = op_a_r * op_b_r;

`else

// riscv-formal can use a simpler function, since it's just confirming the
// result is correctly hooked up.
assign result = result_vld ? (op_a_r + op_b_r) ^ 32'h5876063e : 32'hdeadbeef;

`endif

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		result_vld <= 1'b0;
	end else begin
		result_vld <= op_vld;
	end
end

endmodule
