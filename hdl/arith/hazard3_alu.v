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

`default_nettype none

module hazard3_alu #(
`include "hazard3_config.vh"
,
`include "hazard3_width_const.vh"
) (
	input  wire [3:0]        aluop,
	input  wire [W_DATA-1:0] op_a,
	input  wire [W_DATA-1:0] op_b,
	output reg  [W_DATA-1:0] result,
	output wire [W_DATA-1:0] result_add,
	output wire              cmp
);

`include "hazard3_ops.vh"

// ----------------------------------------------------------------------------
// Fiddle around with add/sub, comparisons etc (all related).

// This adder is exposed directly on the result_add port, since it may be used
// for load/store addresses.

function msb;
input [W_DATA-1:0] x;
begin
	msb = x[W_DATA-1];
end
endfunction

wire sub = !(aluop == ALUOP_ADD || (|EXTENSION_ZBA && (
	aluop == ALUOP_ADD_SH1 || aluop == ALUOP_ADD_SH2 || aluop == ALUOP_ADD_SH3
)));

wire inv_op_b = sub || (|EXTENSION_ZBB && (
	aluop == ALUOP_ANDN || aluop == ALUOP_ORN || aluop == ALUOP_XNOR
));

wire [W_DATA-1:0] op_a_shifted =
	|EXTENSION_ZBA && aluop == ALUOP_ADD_SH1 ? op_a << 1 :
	|EXTENSION_ZBA && aluop == ALUOP_ADD_SH2 ? op_a << 2 :
	|EXTENSION_ZBA && aluop == ALUOP_ADD_SH3 ? op_a << 3 : op_a;

wire [W_DATA-1:0] op_b_inv = op_b ^ {W_DATA{inv_op_b}};

wire [W_DATA-1:0] sum  = op_a_shifted + op_b_inv + sub;
wire [W_DATA-1:0] op_xor = op_a ^ op_b;

wire cmp_is_unsigned = aluop == ALUOP_LTU ||
	|EXTENSION_ZBB && aluop == ALUOP_MAXU ||
	|EXTENSION_ZBB && aluop == ALUOP_MINU;

wire lt = msb(op_a) == msb(op_b) ? msb(sum)  :
          cmp_is_unsigned        ? msb(op_b) :
                                   msb(op_a) ;

assign cmp = aluop == ALUOP_SUB ? |op_xor : lt;
assign result_add = sum;


// ----------------------------------------------------------------------------
// Separate units for shift, ctz etc

wire [W_DATA-1:0] shift_dout;
wire shift_right_nleft = aluop == ALUOP_SRL || aluop == ALUOP_SRA ||
	|EXTENSION_ZBB && aluop == ALUOP_ROR ||
	|EXTENSION_ZBS && aluop == ALUOP_BEXT;

wire shift_arith = aluop == ALUOP_SRA;
wire shift_rotate = |EXTENSION_ZBB & (aluop == ALUOP_ROR || aluop == ALUOP_ROL);

hazard3_shift_barrel #(
`include "hazard3_config_inst.vh"
) shifter (
	.din         (op_a),
	.shamt       (op_b[4:0]),
	.right_nleft (shift_right_nleft),
	.rotate      (shift_rotate),
	.arith       (shift_arith),
	.dout        (shift_dout)
);

reg [W_DATA-1:0] op_a_rev;
always @ (*) begin: rev_op_a
	integer i;
	for (i = 0; i < W_DATA; i = i + 1) begin
		op_a_rev[i] = op_a[W_DATA - 1 - i];
	end
end

// "leading" means starting at MSB. This is an LSB-first priority encoder, so
// ""leading" is reversed and "trailing" is not.
wire [W_DATA-1:0] ctz_search_mask = aluop == ALUOP_CLZ ? op_a_rev : op_a;
wire [W_SHAMT:0]  ctz_clz;

hazard3_priority_encode #(
	.W_REQ (W_DATA)
) ctz_priority_encode (
	.req (ctz_search_mask),
	.gnt (ctz_clz[W_SHAMT-1:0])
);
// Special case: all-zeroes returns XLEN
assign ctz_clz[W_SHAMT] = ~|op_a;

reg [W_SHAMT:0] cpop;
always @ (*) begin: cpop_count
	integer i;
	cpop = {W_SHAMT+1{1'b0}};
	for (i = 0; i < W_DATA; i = i + 1) begin
		cpop = cpop + op_a[i];
	end
end

reg [2*W_DATA-1:0] clmul;
always @ (*) begin: clmul_mul
	integer i;
	clmul = {2*W_DATA{1'b0}};
	for (i = 0; i < W_DATA; i = i + 1) begin
		clmul = clmul ^ (({{W_DATA{1'b0}}, op_a} << i) & {2*W_DATA{op_b[i]}});
	end
end

// ----------------------------------------------------------------------------
// Output mux, with simple operations inline

// iCE40: We can implement all bitwise ops with 1 LUT4/bit total, since each
// result bit uses only two operand bits. Much better than feeding each into
// main mux tree. Doesn't matter for big-LUT FPGAs or for implementations with
// bitmanip extensions enabled.

reg [W_DATA-1:0] bitwise;

always @ (*) begin: bitwise_ops
	case (aluop[1:0])
		ALUOP_AND[1:0]: bitwise = op_a & op_b_inv;
		ALUOP_OR[1:0]:  bitwise = op_a | op_b_inv;
		default:        bitwise = op_a ^ op_b_inv;
	endcase
end

wire [W_DATA-1:0] zbs_mask = {{W_DATA-1{1'b0}}, 1'b1} << op_b[W_SHAMT-1:0];

always @ (*) begin
	casez ({|EXTENSION_ZBA, |EXTENSION_ZBB, EXTENSION_ZBC, |EXTENSION_ZBS, aluop})
		// Base ISA
		{4'bzzzz, ALUOP_ADD    }: result = sum;
		{4'bzzzz, ALUOP_SUB    }: result = sum;
		{4'bzzzz, ALUOP_LT     }: result = {{W_DATA-1{1'b0}}, lt};
		{4'bzzzz, ALUOP_LTU    }: result = {{W_DATA-1{1'b0}}, lt};
		{4'bzzzz, ALUOP_SRL    }: result = shift_dout;
		{4'bzzzz, ALUOP_SRA    }: result = shift_dout;
		{4'bzzzz, ALUOP_SLL    }: result = shift_dout;
		{4'bzzzz, ALUOP_SLL    }: result = shift_dout;
		// Zba
		{4'b1zzz, ALUOP_ADD_SH1}: result = sum;
		{4'b1zzz, ALUOP_ADD_SH2}: result = sum;
		{4'b1zzz, ALUOP_ADD_SH3}: result = sum;
		// Zbb
		{4'bz1zz, ALUOP_ANDN   }: result = bitwise;
		{4'bz1zz, ALUOP_ORN    }: result = bitwise;
		{4'bz1zz, ALUOP_XNOR   }: result = bitwise;
		{4'bz1zz, ALUOP_CLZ    }: result = ctz_clz;
		{4'bz1zz, ALUOP_CTZ    }: result = ctz_clz;
		{4'bz1zz, ALUOP_CPOP   }: result = cpop;
		{4'bz1zz, ALUOP_MAX    }: result = lt ? op_b : op_a;
		{4'bz1zz, ALUOP_MAXU   }: result = lt ? op_b : op_a;
		{4'bz1zz, ALUOP_MIN    }: result = lt ? op_a : op_b;
		{4'bz1zz, ALUOP_MINU   }: result = lt ? op_a : op_b;
		{4'bz1zz, ALUOP_SEXT_B }: result = {{W_DATA-8{op_a[7]}}, op_a[7:0]};
		{4'bz1zz, ALUOP_SEXT_H }: result = {{W_DATA-16{op_a[15]}}, op_a[15:0]};
		{4'bz1zz, ALUOP_ZEXT_H }: result = {{W_DATA-16{1'b0}}, op_a[15:0]};
		{4'bz1zz, ALUOP_ORC_B  }: result = {{8{|op[31:24]}}, {8{|op[23:16]}}, {8{|op[15:8]}}, {8{|op[7:0]}}};
		{4'bz1zz, ALUOP_REV8   }: result = {op[7:0], op[15:8], op[23:16], op[31:24]};
		{4'bz1zz, ALUOP_ROL    }: result = shift_dout;
		{4'bz1zz, ALUOP_ROR    }: result = shift_dout;
		// Zbc
		{4'bzz1z, ALUOP_CLMUL  }: result = clmul[W_DATA-1:0];
		{4'bzz1z, ALUOP_CLMULH }: result = clmul[2*W_DATA-1:W_DATA];
		{4'bzz1z, ALUOP_CLMULR }: result = clmul[2*W_DATA-2:W_DATA-1];
		// Zbs
		{4'bzzz1, ALUOP_BCLR   }: result = op_a & ~zbs_mask;
		{4'bzzz1, ALUOP_BSET   }: result = op_a |  zbs_mask;
		{4'bzzz1, ALUOP_BINV   }: result = op_a ^ ~zbs_mask;
		{4'bzzz1, ALUOP_BEXT   }: result = {{W_DATA-1{1'b0}}, shift_dout[0]};

		default:   begin result = bitwise; end
	endcase
end

// ----------------------------------------------------------------------------
// Properties for base-ISA instructions

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

`default_nettype wire
