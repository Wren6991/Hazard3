/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// MUL-only (cfg: MUL_FAST) and MUL/MULH/MULHU/MULHSU (cfg: MUL_FAST &&
// MULH_FAST) are handled by different circuits. In either case it's a simple
// behavioural multiply, and we rely on inference to get good performance on
// FPGA.

`default_nettype none

module hazard3_mul_fast #(
`include "hazard3_config.vh"
,
`include "hazard3_width_const.vh"
) (
	input  wire               clk,
	input  wire               rst_n,

	input  wire [W_MULOP-1:0] op,
	input  wire               op_vld,
	input  wire [W_DATA-1:0]  op_a,
	input  wire [W_DATA-1:0]  op_b,

	output wire [W_DATA-1:0] result,
	output reg               result_vld
);

`include "hazard3_ops.vh"

localparam XLEN = W_DATA;

//synthesis translate_off
generate if (MULH_FAST && !MUL_FAST)
	initial $fatal("%m: MULH_FAST requires that MUL_FAST is also set.");
endgenerate
generate if (MUL_FASTER && !MUL_FAST)
	initial $fatal("%m: MUL_FASTER requires that MUL_FAST is also set.");
endgenerate
//synthesis translate_on

// Latency of 1:
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		result_vld <= 1'b0;
	end else begin
		result_vld <= op_vld;
	end
end

// ----------------------------------------------------------------------------
// Fast MUL only

generate
if (!MULH_FAST) begin: mul_only

// This pipestage is folded into the front of the DSP tiles on UP5k. Note the
// intention is to register the bypassed core regs at the end of X (since
// bypass is quite slow), then perform multiply combinatorially in stage M,
// and mux into MW result register.

reg [XLEN-1:0] op_a_r;
reg [XLEN-1:0] op_b_r;

if (MUL_FASTER) begin: op_passthrough
	always @ (*) begin
		op_a_r = op_a;
		op_b_r = op_b;
	end
end else begin: op_register
	always @ (posedge clk) begin
		if (op_vld) begin
			op_a_r <= op_a;
			op_b_r <= op_b;
		end
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

// ----------------------------------------------------------------------------
// Fast MUL/MULH/MULHU/MULHSU

end else begin: mul_and_mulh

reg [XLEN-1:0]    op_a_r;
reg [XLEN-1:0]    op_b_r;
reg [W_MULOP-1:0] op_r;

if (MUL_FASTER) begin: op_passthrough
	always @ (*) begin
		op_a_r = op_a;
		op_b_r = op_b;
		op_r = op;
	end
end else begin: op_register
	always @ (posedge clk) begin
		if (op_vld) begin
			op_a_r <= op_a;
			op_b_r <= op_b;
			op_r <= op;
		end
	end
end

wire op_a_signed = op_r == M_OP_MULH || op_r == M_OP_MULHSU;
wire op_b_signed = op_r == M_OP_MULH;

wire [2*XLEN-1:0] op_a_sext = {
	{XLEN{op_a_r[XLEN - 1] && op_a_signed}},
	op_a_r
};

wire [2*XLEN-1:0] op_b_sext = {
	{XLEN{op_b_r[XLEN - 1] && op_b_signed}},
	op_b_r
};

wire [2*XLEN-1:0] result_full = op_a_sext * op_b_sext;

`ifndef RISCV_FORMAL_ALTOPS

assign result = op_r == M_OP_MUL ? result_full[0 +: XLEN] : result_full[XLEN +: XLEN];

`else

assign result =
	op_r == M_OP_MULH   ? (op_a_r + op_b_r) ^ 32'hf6583fb7 :
	op_r == M_OP_MULHSU ? (op_a_r - op_b_r) ^ 32'hecfbe137 :
	op_r == M_OP_MULHU  ? (op_a_r + op_b_r) ^ 32'h949ce5e8 :
	op_r == M_OP_MUL    ? (op_a_r + op_b_r) ^ 32'h5876063e : 32'hdeadbeef;

`endif

end
endgenerate

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
