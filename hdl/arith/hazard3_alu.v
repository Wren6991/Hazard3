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
	(|EXTENSION_ZBB      && aluop == ALUOP_ROR                   ) ||
	(|EXTENSION_ZBS      && aluop == ALUOP_BEXT                  ) ||
	(|EXTENSION_XH3BEXTM && aluop == ALUOP_BEXTM                 ) ||
	(|EXTENSION_XH3SFX   && aluop == ALUOP_SSRASTICKY && !op_b[8]) ||
	(|EXTENSION_XH3SFX   && aluop == ALUOP_SSRLSTICKY && !op_b[8]) ||
	(|EXTENSION_XH3SFX   && aluop == ALUOP_SSLA       &&  op_b[8]);

wire shift_arith =
	aluop == ALUOP_SRA ||
	(|EXTENSION_XH3SFX && aluop == ALUOP_SSRASTICKY) ||
	(|EXTENSION_XH3SFX && aluop == ALUOP_SSLA);

wire shift_rotate = |EXTENSION_ZBB & (aluop == ALUOP_ROR || aluop == ALUOP_ROL);

wire shamt_is_bidirectional =
	(|EXTENSION_XH3SFX   && aluop == ALUOP_SSRASTICKY) ||
	(|EXTENSION_XH3SFX   && aluop == ALUOP_SSRLSTICKY) ||
	(|EXTENSION_XH3SFX   && aluop == ALUOP_SSLA      );

wire [8:0] shamt_abs = shamt_is_bidirectional && op_b[8] ? -op_b[8:0] : op_b[8:0];
wire       shamt_over = |shamt_abs[8:5];

hazard3_shift_barrel #(
`include "hazard3_config_inst.vh"
) shifter (
	.din         (op_a),
	.shamt       (shamt_abs[4:0]),
	.right_nleft (shift_right_nleft),
	.rotate      (shift_rotate),
	.arith       (shift_arith),
	.dout        (shift_dout)
);

// Only used for h3.feadjq3; hopefully the carry chain is folded into the
// lookahead on the priority encode.
wire [W_DATA-1:0] op_a_abs = op_a[W_DATA-1] ? -op_a : op_a;

reg  [W_DATA-1:0] op_a_rev;
reg  [W_DATA-1:0] ctz_search_mask;

always @ (*) begin: rev_op_a
	integer i;
	for (i = 0; i < W_DATA; i = i + 1) begin
		op_a_rev[i] = op_a[W_DATA - 1 - i];
		// "leading" means starting at MSB. Using an LSB-first priority encoder, so
		// "leading" is reversed and "trailing" is not.
		ctz_search_mask[i] =
			|EXTENSION_ZBB    && aluop == ALUOP_CLZ     ? op_a[W_DATA - 1 - i]     :
			|EXTENSION_XH3SFX && aluop == ALUOP_FEADJU3 ? op_a[W_DATA - 1 - i]     :
			|EXTENSION_XH3SFX && aluop == ALUOP_FEADJQ3 ? op_a_abs[W_DATA - 1 - i] : op_a[i];
	end
end

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

// Q3 format has 29 fractional bits. For single-precision this is 6 excess
// bits, and for half-precision it's 19 excess bits.
wire [31:0] xh3sfx_sig_abs = op_a[31] ? -op_a : op_a;
wire [31:0] xh3sfx_rnd_bias = aluop == ALUOP_FPACKRQ3_H ? 32'h0007ffff : 32'h0000003f;
wire [31:0] xh3sfx_odd_bias = {
	31'd0,
	aluop == ALUOP_FPACKRQ3_H ? xh3sfx_sig_abs[29 - 10] : xh3sfx_sig_abs[29 - 23]
};
wire [31:0] xh3sfx_sig_rnd = xh3sfx_sig_abs + xh3sfx_rnd_bias + xh3sfx_odd_bias;
wire [9:0]  xh3sfx_exp_adj = op_b[9:0] + {9'd0, xh3sfx_sig_rnd[30]};
wire [31:0] xh3sfx_sig_norm = xh3sfx_sig_rnd >> xh3sfx_sig_rnd[30];

wire [31:0] xh3sfx_fpackrq3_s =
	~|op_a[28:6]                  ? 32'd0                      :                  // Exact cancellation
	xh3sfx_exp_adj[9]             ? {op_a[31], 31'd0}          :                  // Underflow
	~|xh3sfx_exp_adj[8:0]         ? {op_a[31], 31'd0}          :                  // Flushed subnormal
	xh3sfx_exp_adj[8:0] >= 9'h0ff ? {op_a[31], 8'hff, 23'd0}   :                  // Overflow
	                                {op_a[31], xh3sfx_exp_adj[7:0], op_a[28:6]};  // Normal result

wire [15:0] xh3sfx_fpackrq3_h =
	~|op_a[28:19]                 ? 16'd0                      :                  // Exact cancellation
	xh3sfx_exp_adj[9]             ? {op_a[31], 15'd0}          :                  // Underflow
	~|xh3sfx_exp_adj[8:0]         ? {op_a[31], 15'd0}          :                  // Flushed subnormal
	xh3sfx_exp_adj[8:0] >= 9'h01f ? {op_a[31], 5'h1f, 10'd0}   :                  // Overflow
	                                {op_a[31], xh3sfx_exp_adj[4:0], op_a[28:19]}; // Normal result

wire [W_SHAMT:0] xh3sfx_feadj = 6'h2 - ctz_clz;

wire xh3sfx_sr_sticky = !op_b[8] && (
	shamt_over ? |op_a : |(op_a & ~({32{1'b1}} << op_b[4:0]))
);

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
	        |EXTENSION_ZBS, |EXTENSION_ZBKB, |EXTENSION_ZBKX, |EXTENSION_XH3BEXTM,
	        |EXTENSION_XH3SFX, aluop})
		// Base ISA
		{9'bzzzzzzzzz, ALUOP_ADD        }: result = sum;
		{9'bzzzzzzzzz, ALUOP_SUB        }: result = sum;
		{9'bzzzzzzzzz, ALUOP_LT         }: result = {{W_DATA-1{1'b0}}, lt};
		{9'bzzzzzzzzz, ALUOP_LTU        }: result = {{W_DATA-1{1'b0}}, lt};
		{9'bzzzzzzzzz, ALUOP_SRL        }: result = shift_dout;
		{9'bzzzzzzzzz, ALUOP_SRA        }: result = shift_dout;
		{9'bzzzzzzzzz, ALUOP_SLL        }: result = shift_dout;
		// A or Zbb (written this way to avoid case overlap)
		{9'b1zzzzzzzz, ALUOP_MAX        },
		{9'b0z1zzzzzz, ALUOP_MAX        }: result = lt ? op_b : op_a;
		{9'b1zzzzzzzz, ALUOP_MIN        },
		{9'b0z1zzzzzz, ALUOP_MIN        }: result = lt ? op_a : op_b;
		{9'b1zzzzzzzz, ALUOP_MAXU       },
		{9'b0z1zzzzzz, ALUOP_MAXU       }: result = lt ? op_b : op_a;
		{9'b1zzzzzzzz, ALUOP_MINU       },
		{9'b0z1zzzzzz, ALUOP_MINU       }: result = lt ? op_a : op_b;
		// Zba
		{9'bz1zzzzzzz, ALUOP_SHXADD     }: result = sum;
		// Zbb
		{9'bzz1zzzzzz, ALUOP_ANDN       }: result = bitwise;
		{9'bzz1zzzzzz, ALUOP_ORN        }: result = bitwise;
		{9'bzz1zzzzzz, ALUOP_XNOR       }: result = bitwise;
		{9'bzz1zzzzzz, ALUOP_CLZ        }: result = {{W_DATA-W_SHAMT-1{1'b0}}, ctz_clz};
		{9'bzz1zzzzzz, ALUOP_CTZ        }: result = {{W_DATA-W_SHAMT-1{1'b0}}, ctz_clz};
		{9'bzz1zzzzzz, ALUOP_CPOP       }: result = {{W_DATA-W_SHAMT-1{1'b0}}, cpop};
		{9'bzz1zzzzzz, ALUOP_SEXT_B     }: result = {{W_DATA-8{op_a[7]}}, op_a[7:0]};
		{9'bzz1zzzzzz, ALUOP_SEXT_H     }: result = {{W_DATA-16{op_a[15]}}, op_a[15:0]};
		{9'bzz1zzzzzz, ALUOP_ZEXT_H     }: result = {{W_DATA-16{1'b0}}, op_a[15:0]};
		{9'bzz1zzzzzz, ALUOP_ORC_B      }: result = {{8{|op_a[31:24]}}, {8{|op_a[23:16]}}, {8{|op_a[15:8]}}, {8{|op_a[7:0]}}};
		{9'bzz1zzzzzz, ALUOP_REV8       }: result = {op_a[7:0], op_a[15:8], op_a[23:16], op_a[31:24]};
		{9'bzz1zzzzzz, ALUOP_ROL        }: result = shift_dout;
		{9'bzz1zzzzzz, ALUOP_ROR        }: result = shift_dout;
		// Zbc
		{9'bzzz1zzzzz, ALUOP_CLMUL      }: result = clmul;
		// Zbs
		{9'bzzzz1zzzz, ALUOP_BCLR       }: result = op_a & ~zbs_mask;
		{9'bzzzz1zzzz, ALUOP_BSET       }: result = op_a |  zbs_mask;
		{9'bzzzz1zzzz, ALUOP_BINV       }: result = op_a ^  zbs_mask;
		{9'bzzzz1zzzz, ALUOP_BEXT       }: result = {{W_DATA-1{1'b0}}, shift_dout[0]};
		// Zbkb
		{9'bzzzzz1zzz, ALUOP_PACK       }: result = {op_b[15:0], op_a[15:0]};
		{9'bzzzzz1zzz, ALUOP_PACKH      }: result = {{W_DATA-16{1'b0}}, op_b[7:0], op_a[7:0]};
		{9'bzzzzz1zzz, ALUOP_BREV8      }: result = {op_a_rev[7:0], op_a_rev[15:8], op_a_rev[23:16], op_a_rev[31:24]};
		{9'bzzzzz1zzz, ALUOP_UNZIP      }: result = unzip;
		{9'bzzzzz1zzz, ALUOP_ZIP        }: result = zip;
		// Zbkx
		{9'bzzzzzz1zz, ALUOP_XPERM      }: result = funct3_32b[2] ? xperm8 : xperm4;
		// Xh3bextm
		{9'bzzzzzzz1z, ALUOP_BEXTM      }: result = shift_dout & {24'h0, {~(8'hfe << funct7_32b[3:1])}};
		// Xh3sfx
		{9'bzzzzzzzz1, ALUOP_FUNPACKQ3_H}: result = ({3'd1, op_a[10:0], 18'd0} ^ {32{op_a[15]}}) + {31'd0, op_a[15]};
		{9'bzzzzzzzz1, ALUOP_FUNPACKQ3_S}: result = ({3'd1, op_a[22:0],  6'd0} ^ {32{op_a[31]}}) + {31'd0, op_a[31]}; 
		{9'bzzzzzzzz1, ALUOP_FCHECK2E_H }: result = {31'd0, &op_a[4:0] || ~|op_a[4:0] || &op_b[4:0] || |op_a[4:0]};
		{9'bzzzzzzzz1, ALUOP_FCHECK2E_S }: result = {31'd0, &op_a[7:0] || ~|op_a[7:0] || &op_b[7:0] || |op_a[7:0]};
		{9'bzzzzzzzz1, ALUOP_FPACKRQ3_H }: result = {16'd0, xh3sfx_fpackrq3_h};
		{9'bzzzzzzzz1, ALUOP_FPACKRQ3_S }: result = xh3sfx_fpackrq3_s;
		{9'bzzzzzzzz1, ALUOP_FEADJQ3    }: result = {{W_DATA-W_SHAMT-1{xh3sfx_feadj[W_SHAMT]}}, xh3sfx_feadj};
		{9'bzzzzzzzz1, ALUOP_FEADJU3    }: result = {{W_DATA-W_SHAMT-1{xh3sfx_feadj[W_SHAMT]}}, xh3sfx_feadj};
		{9'bzzzzzzzz1, ALUOP_XORSIGN    }: result = op_b[31] ? -op_a :  op_a;
		{9'bzzzzzzzz1, ALUOP_XNORSIGN   }: result = op_b[31] ? op_a  : -op_a;
		{9'bzzzzzzzz1, ALUOP_SSRASTICKY }: result = (shamt_over ? {32{op_a[31] && !op_b[8]}} : shift_dout) | {31'd0, xh3sfx_sr_sticky};
		{9'bzzzzzzzz1, ALUOP_SSRLSTICKY }: result = (shamt_over ? 32'd0                      : shift_dout) | {31'd0, xh3sfx_sr_sticky};
		{9'bzzzzzzzz1, ALUOP_SSLA       }: result = shamt_over ? {32{op_a[31] && op_b[8]}} : shift_dout;

		default:                           result = bitwise;
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
