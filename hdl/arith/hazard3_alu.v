/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module hazard3_alu #(
`include "hazard3_config.vh"
,
`include "hazard3_width_const.vh"
) (
	input  wire [W_ALUOP-1:0] aluop,
	input  wire [6:0]         funct7_32b,
	input  wire [2:0]         funct3_32b,
	input  wire [W_DATA-1:0]  op_a,
	input  wire [W_DATA-1:0]  op_b,
	output reg  [W_DATA-1:0]  result
);

`include "hazard3_ops.vh"

// ----------------------------------------------------------------------------
// Fiddle around with add/sub, comparisons etc (all related).

wire sub = !(aluop == ALUOP_ADD || (|EXTENSION_ZBA && aluop == ALUOP_SHXADD));

wire inv_op_b = sub && !(
	aluop == ALUOP_AND || aluop == ALUOP_OR || aluop == ALUOP_XOR || aluop == ALUOP_RS2
);

wire [W_DATA-1:0] op_a_shifted =
	|EXTENSION_ZBA && aluop == ALUOP_SHXADD ? (
		!funct3_32b[2] ? op_a << 1 :
		!funct3_32b[1] ? op_a << 2 : op_a << 3
	) : op_a;

wire [W_DATA-1:0] op_b_inv = op_b ^ {W_DATA{inv_op_b}};

wire [W_DATA-1:0] sum  = op_a_shifted + op_b_inv + {{W_DATA-1{1'b0}}, sub};
wire [W_DATA-1:0] op_xor = op_a ^ op_b;

wire cmp_is_unsigned = aluop == ALUOP_LTU ||
	|EXTENSION_ZBB && aluop == ALUOP_MAXU ||
	|EXTENSION_ZBB && aluop == ALUOP_MINU;

wire lt = op_a[W_DATA-1] == op_b[W_DATA-1] ? sum[W_DATA-1]  :
          cmp_is_unsigned                  ? op_b[W_DATA-1] : op_a[W_DATA-1] ;

// ----------------------------------------------------------------------------
// Separate units for shift, ctz etc

wire [W_DATA-1:0] shift_dout;
wire shift_right_nleft =
	aluop == ALUOP_SRL ||
	aluop == ALUOP_SRA ||
	(|EXTENSION_ZBB      && aluop == ALUOP_ROR  ) ||
	(|EXTENSION_ZBS      && aluop == ALUOP_BEXT ) ||
	(|EXTENSION_XH3BEXTM && aluop == ALUOP_BEXTM);

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
// "leading" is reversed and "trailing" is not.
wire [W_DATA-1:0] ctz_search_mask = aluop == ALUOP_CLZ ? op_a_rev : op_a;
wire [W_SHAMT:0]  ctz_clz;

hazard3_priority_encode #(
	.W_REQ        (W_DATA),
	.HIGHEST_WINS (0)
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
		cpop = cpop + {{W_SHAMT{1'b0}}, op_a[i]};
	end
end

reg [2*W_DATA-1:0] clmul64;

always @ (*) begin: clmul_mul
	integer i;
	clmul64 = {2*W_DATA{1'b0}};
	for (i = 0; i < W_DATA; i = i + 1) begin
		clmul64 = clmul64 ^ (({{W_DATA{1'b0}}, op_a} << i) & {2*W_DATA{op_b[i]}});
	end
end

// funct3: 1=clmul, 2=clmulr, 3=clmulh, never 0.
wire [W_DATA-1:0] clmul =
	!funct3_32b[1] ? clmul64[31: 0] :
	!funct3_32b[0] ? clmul64[62:31] : clmul64[63:32];

reg [W_DATA-1:0] zip;
reg [W_DATA-1:0] unzip;
always @ (*) begin: do_zip_unzip
	integer i;
	for (i = 0; i < W_DATA; i = i + 1) begin
		zip[i]   = op_a[{i[0], i[4:1]}]; // Alternate high/low halves
		unzip[i] = op_a[{i[3:0], i[4]}]; // All even then all odd
	end
end

reg [W_DATA-1:0] xperm8;
always @ (*) begin: do_xperm8
	integer i;
	for (i = 0; i < W_DATA; i = i + 8) begin
		if (|op_b[i + 2 +: 6]) begin
			xperm8[i +: 8] = 8'h00;
		end else begin
			xperm8[i +: 8] = op_a[8 * op_b[i +: 2] +: 8];
		end
	end
end

reg [W_DATA-1:0] xperm4;
always @ (*) begin: do_xperm4
	integer i;
	for (i = 0; i < W_DATA; i = i + 4) begin
		if (op_b[i + 3]) begin
			xperm4[i +: 4] = 4'h0;
		end else begin
			xperm4[i +: 4] = op_a[4 * op_b[i +: 3] +: 4];
		end
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
		ALUOP_OR [1:0]: bitwise = op_a | op_b_inv;
		ALUOP_XOR[1:0]: bitwise = op_a ^ op_b_inv;
		ALUOP_RS2[1:0]: bitwise =        op_b_inv;
	endcase
end

wire [W_DATA-1:0] zbs_mask = {{W_DATA-1{1'b0}}, 1'b1} << op_b[W_SHAMT-1:0];

always @ (*) begin
	casez ({|EXTENSION_A, |EXTENSION_ZBA, |EXTENSION_ZBB, |EXTENSION_ZBC,
	        |EXTENSION_ZBS, |EXTENSION_ZBKB, |EXTENSION_ZBKX, |EXTENSION_XH3BEXTM, aluop})
		// Base ISA
		{8'bzzzzzzzz, ALUOP_ADD    }: result = sum;
		{8'bzzzzzzzz, ALUOP_SUB    }: result = sum;
		{8'bzzzzzzzz, ALUOP_LT     }: result = {{W_DATA-1{1'b0}}, lt};
		{8'bzzzzzzzz, ALUOP_LTU    }: result = {{W_DATA-1{1'b0}}, lt};
		{8'bzzzzzzzz, ALUOP_SRL    }: result = shift_dout;
		{8'bzzzzzzzz, ALUOP_SRA    }: result = shift_dout;
		{8'bzzzzzzzz, ALUOP_SLL    }: result = shift_dout;
		// A or Zbb (written this way to avoid case overlap)
		{8'b1zzzzzzz, ALUOP_MAX    },
		{8'b0z1zzzzz, ALUOP_MAX    }: result = lt ? op_b : op_a;
		{8'b1zzzzzzz, ALUOP_MIN    },
		{8'b0z1zzzzz, ALUOP_MIN    }: result = lt ? op_a : op_b;
		{8'b1zzzzzzz, ALUOP_MAXU   },
		{8'b0z1zzzzz, ALUOP_MAXU   }: result = lt ? op_b : op_a;
		{8'b1zzzzzzz, ALUOP_MINU   },
		{8'b0z1zzzzz, ALUOP_MINU   }: result = lt ? op_a : op_b;
		// Zba
		{8'bz1zzzzzz, ALUOP_SHXADD }: result = sum;
		// Zbb
		{8'bzz1zzzzz, ALUOP_ANDN   }: result = bitwise;
		{8'bzz1zzzzz, ALUOP_ORN    }: result = bitwise;
		{8'bzz1zzzzz, ALUOP_XNOR   }: result = bitwise;
		{8'bzz1zzzzz, ALUOP_CLZ    }: result = {{W_DATA-W_SHAMT-1{1'b0}}, ctz_clz};
		{8'bzz1zzzzz, ALUOP_CTZ    }: result = {{W_DATA-W_SHAMT-1{1'b0}}, ctz_clz};
		{8'bzz1zzzzz, ALUOP_CPOP   }: result = {{W_DATA-W_SHAMT-1{1'b0}}, cpop};
		{8'bzz1zzzzz, ALUOP_SEXT_B }: result = {{W_DATA-8{op_a[7]}}, op_a[7:0]};
		{8'bzz1zzzzz, ALUOP_SEXT_H }: result = {{W_DATA-16{op_a[15]}}, op_a[15:0]};
		{8'bzz1zzzzz, ALUOP_ZEXT_H }: result = {{W_DATA-16{1'b0}}, op_a[15:0]};
		{8'bzz1zzzzz, ALUOP_ORC_B  }: result = {{8{|op_a[31:24]}}, {8{|op_a[23:16]}}, {8{|op_a[15:8]}}, {8{|op_a[7:0]}}};
		{8'bzz1zzzzz, ALUOP_REV8   }: result = {op_a[7:0], op_a[15:8], op_a[23:16], op_a[31:24]};
		{8'bzz1zzzzz, ALUOP_ROL    }: result = shift_dout;
		{8'bzz1zzzzz, ALUOP_ROR    }: result = shift_dout;
		// Zbc
		{8'bzzz1zzzz, ALUOP_CLMUL  }: result = clmul;
		// Zbs
		{8'bzzzz1zzz, ALUOP_BCLR   }: result = op_a & ~zbs_mask;
		{8'bzzzz1zzz, ALUOP_BSET   }: result = op_a |  zbs_mask;
		{8'bzzzz1zzz, ALUOP_BINV   }: result = op_a ^  zbs_mask;
		{8'bzzzz1zzz, ALUOP_BEXT   }: result = {{W_DATA-1{1'b0}}, shift_dout[0]};
		// Zbkb
		{8'bzzzzz1zz, ALUOP_PACK   }: result = {op_b[15:0], op_a[15:0]};
		{8'bzzzzz1zz, ALUOP_PACKH  }: result = {{W_DATA-16{1'b0}}, op_b[7:0], op_a[7:0]};
		{8'bzzzzz1zz, ALUOP_BREV8  }: result = {op_a_rev[7:0], op_a_rev[15:8], op_a_rev[23:16], op_a_rev[31:24]};
		{8'bzzzzz1zz, ALUOP_UNZIP  }: result = unzip;
		{8'bzzzzz1zz, ALUOP_ZIP    }: result = zip;
		// Zbkx
		{8'bzzzzzz1z, ALUOP_XPERM  }: result = funct3_32b[2] ? xperm8 : xperm4;
		// Xh3bextm
		{8'bzzzzzzz1, ALUOP_BEXTM  }: result = shift_dout & {24'h0, {~(8'hfe << funct7_32b[3:1])}};

		default:                    result = bitwise;
	endcase
end

// ----------------------------------------------------------------------------
// Properties for base-ISA instructions

`ifdef HAZARD3_ASSERTIONS
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

`ifndef YOSYS
`default_nettype wire
`endif
