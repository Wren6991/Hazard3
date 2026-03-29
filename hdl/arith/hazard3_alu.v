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
// Shifter and shifter control decode

wire       shamt_neg = op_b[8];
wire       shamt_is_bidir = |EXTENSION_XH3SFX && aluop == ALUOP_SFX;
wire [8:0] shamt_abs = shamt_is_bidir && shamt_neg ? -op_b[8:0] : op_b[8:0];
wire       shamt_over = |shamt_abs[8:5];

wire shift_right_nleft =
	aluop == ALUOP_SRL ||
	aluop == ALUOP_SRA ||
	(|EXTENSION_ZBB      && aluop == ALUOP_ROR                   ) ||
	(|EXTENSION_ZBS      && aluop == ALUOP_BEXT                  ) ||
	(|EXTENSION_XH3BEXTM && aluop == ALUOP_BEXTM                 ) ||
	(|EXTENSION_XH3SFX   && aluop == ALUOP_SFX && (shamt_neg == funct7_32b[2]));

wire shift_arith =
	aluop == ALUOP_SRA ||
	(|EXTENSION_XH3SFX && aluop == ALUOP_SFX && funct7_32b[0] && shamt_neg == funct7_32b[2]);

wire shift_rotate = |EXTENSION_ZBB & (aluop == ALUOP_ROR || aluop == ALUOP_ROL);

wire [W_DATA-1:0] shift_dout;

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

// ----------------------------------------------------------------------------
// Bit manipulation functions

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
			|EXTENSION_ZBB    && aluop == ALUOP_CLZ                   ? op_a[W_DATA - 1 - i]     :
			|EXTENSION_XH3SFX && aluop == ALUOP_SFX &&  funct7_32b[0] ? op_a[W_DATA - 1 - i]     :
			|EXTENSION_XH3SFX && aluop == ALUOP_SFX && !funct7_32b[0] ? op_a_abs[W_DATA - 1 - i] : op_a[i];
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

// ----------------------------------------------------------------------------
// Xh3sfx operations

// Q3 format has 29 fractional bits. For single-precision this is 6 excess
// bits, and for half-precision it's 19 excess bits.

wire xh3sfx_pack_is_s = funct7_32b[6];

wire [31:0] xh3sfx_sig_abs = op_a[31] ? -op_a : op_a;
wire [31:0] xh3sfx_rnd_bias = xh3sfx_pack_is_s ? 32'h0000001f : 32'h0003ffff;
wire [31:0] xh3sfx_odd_bias = {
	31'd0,
	xh3sfx_pack_is_s ? xh3sfx_sig_abs[29 - 23] : xh3sfx_sig_abs[29 - 10]
};
wire [31:0] xh3sfx_sig_rnd = xh3sfx_sig_abs + xh3sfx_rnd_bias + xh3sfx_odd_bias;
wire [9:0]  xh3sfx_exp_adj = op_b[9:0] + {9'd0, xh3sfx_sig_rnd[30]};
wire [31:0] xh3sfx_sig_norm = xh3sfx_sig_rnd >> xh3sfx_sig_rnd[30];

wire [31:0] xh3sfx_fpackrq3_s =
	~|op_a[31:6]                  ? 32'd0                      :  // Exact cancellation
	xh3sfx_exp_adj[9]             ? {op_a[31], 31'd0}          :  // Underflow
	xh3sfx_exp_adj[8:0] == 9'h000 ? {op_a[31], 31'd0}          :  // Flushed subnormal
	xh3sfx_exp_adj[8:0] >= 9'h0ff ? {op_a[31], 8'hff, 23'd0}   :  // Overflow
	                                {op_a[31], xh3sfx_exp_adj[7:0], xh3sfx_sig_norm[28:6]};

wire [15:0] xh3sfx_fpackrq3_h =
	~|op_a[31:19]                 ? 16'd0                      :  // Exact cancellation
	xh3sfx_exp_adj[9]             ? {op_a[31], 15'd0}          :  // Underflow
	xh3sfx_exp_adj[8:0] == 9'h000 ? {op_a[31], 15'd0}          :  // Flushed subnormal
	xh3sfx_exp_adj[8:0] >= 9'h01f ? {op_a[31], 5'h1f, 10'd0}   :  // Overflow
	                                {op_a[31], xh3sfx_exp_adj[4:0], xh3sfx_sig_norm[28:19]};

wire [W_SHAMT:0] xh3sfx_feadj = 6'h2 - ctz_clz;

wire xh3sfx_sr_sticky = !op_b[8] && (
	shamt_over ? |op_a : |(op_a & ~({32{1'b1}} << op_b[4:0]))
);

reg [W_DATA-1:0] sfx_result;
always @ (*) begin
	case (funct7_32b)
		SFX_OP_FUNPACKQ3_H: sfx_result = ({3'd1, op_a[9:0], 19'd0} ^ {32{op_a[15]}}) + {31'd0, op_a[15]};
		SFX_OP_FUNPACKQ3_S: sfx_result = ({3'd1, op_a[22:0], 6'd0} ^ {32{op_a[31]}}) + {31'd0, op_a[31]};
		SFX_OP_FCHECK2E_H:  sfx_result = {31'd0, &op_a[4:0] || ~|op_a[4:0] || &op_b[4:0] || ~|op_b[4:0]};
		SFX_OP_FCHECK2E_S:  sfx_result = {31'd0, &op_a[7:0] || ~|op_a[7:0] || &op_b[7:0] || ~|op_b[7:0]};
		SFX_OP_FPACKRQ3_H:  sfx_result = {16'd0, xh3sfx_fpackrq3_h};
		SFX_OP_FPACKRQ3_S:  sfx_result = xh3sfx_fpackrq3_s;
		SFX_OP_FEADJQ3:     sfx_result = {{W_DATA-W_SHAMT-1{xh3sfx_feadj[W_SHAMT]}}, xh3sfx_feadj};
		SFX_OP_FEADJU3:     sfx_result = {{W_DATA-W_SHAMT-1{xh3sfx_feadj[W_SHAMT]}}, xh3sfx_feadj};
		SFX_OP_XORSIGN:     sfx_result = op_b[31] ? -op_a :  op_a;
		SFX_OP_XNORSIGN:    sfx_result = op_b[31] ? op_a  : -op_a;
		SFX_OP_SSRASTICKY:  sfx_result = (shamt_over ? {32{op_a[31] && !op_b[8]}} : shift_dout) | {31'd0, xh3sfx_sr_sticky};
		SFX_OP_SSRLSTICKY:  sfx_result = (shamt_over ? 32'd0                      : shift_dout) | {31'd0, xh3sfx_sr_sticky};
		SFX_OP_SSLL:        sfx_result =  shamt_over ? 32'd0                      : shift_dout;
		SFX_OP_SSLA:        sfx_result =  shamt_over ? {32{op_a[31] && op_b[8]}}  : shift_dout;
		default:            sfx_result = 32'hxxxxxxxx;
	endcase
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
	casez (aluop)
	// Base ISA
	ALUOP_ADD: result = sum;
	ALUOP_SUB: result = sum;
	ALUOP_LT:  result = {{W_DATA-1{1'b0}}, lt};
	ALUOP_LTU: result = {{W_DATA-1{1'b0}}, lt};
	ALUOP_SRL: result = shift_dout;
	ALUOP_SRA: result = shift_dout;
	ALUOP_SLL: result = shift_dout;
	// A or Zbb
	ALUOP_MAX:    if (~|EXTENSION_ZBB && ~|EXTENSION_A) result = 32'hxxxxxxxx; else result = lt ? op_b : op_a;
	ALUOP_MIN:    if (~|EXTENSION_ZBB && ~|EXTENSION_A) result = 32'hxxxxxxxx; else result = lt ? op_a : op_b;
	ALUOP_MAXU:   if (~|EXTENSION_ZBB && ~|EXTENSION_A) result = 32'hxxxxxxxx; else result = lt ? op_b : op_a;
	ALUOP_MINU:   if (~|EXTENSION_ZBB && ~|EXTENSION_A) result = 32'hxxxxxxxx; else result = lt ? op_a : op_b;
	// Zba
	ALUOP_SHXADD: if (~|EXTENSION_ZBA)       result = 32'hxxxxxxxx; else result = sum;
	// Zbb
	ALUOP_ANDN:   if (~|EXTENSION_ZBB)       result = 32'hxxxxxxxx; else result = bitwise;
	ALUOP_ORN:    if (~|EXTENSION_ZBB)       result = 32'hxxxxxxxx; else result = bitwise;
	ALUOP_XNOR:   if (~|EXTENSION_ZBB)       result = 32'hxxxxxxxx; else result = bitwise;
	ALUOP_CLZ:    if (~|EXTENSION_ZBB)       result = 32'hxxxxxxxx; else result = {{W_DATA-W_SHAMT-1{1'b0}}, ctz_clz};
	ALUOP_CTZ:    if (~|EXTENSION_ZBB)       result = 32'hxxxxxxxx; else result = {{W_DATA-W_SHAMT-1{1'b0}}, ctz_clz};
	ALUOP_CPOP:   if (~|EXTENSION_ZBB)       result = 32'hxxxxxxxx; else result = {{W_DATA-W_SHAMT-1{1'b0}}, cpop};
	ALUOP_SEXT_B: if (~|EXTENSION_ZBB)       result = 32'hxxxxxxxx; else result = {{W_DATA-8{op_a[7]}}, op_a[7:0]};
	ALUOP_SEXT_H: if (~|EXTENSION_ZBB)       result = 32'hxxxxxxxx; else result = {{W_DATA-16{op_a[15]}}, op_a[15:0]};
	ALUOP_ZEXT_H: if (~|EXTENSION_ZBB)       result = 32'hxxxxxxxx; else result = {{W_DATA-16{1'b0}}, op_a[15:0]};
	ALUOP_ORC_B:  if (~|EXTENSION_ZBB)       result = 32'hxxxxxxxx; else result = {{8{|op_a[31:24]}}, {8{|op_a[23:16]}}, {8{|op_a[15:8]}}, {8{|op_a[7:0]}}};
	ALUOP_REV8:   if (~|EXTENSION_ZBB)       result = 32'hxxxxxxxx; else result = {op_a[7:0], op_a[15:8], op_a[23:16], op_a[31:24]};
	ALUOP_ROL:    if (~|EXTENSION_ZBB)       result = 32'hxxxxxxxx; else result = shift_dout;
	ALUOP_ROR:    if (~|EXTENSION_ZBB)       result = 32'hxxxxxxxx; else result = shift_dout;
	// Zbc
	ALUOP_CLMUL:  if (~|EXTENSION_ZBC)       result = 32'hxxxxxxxx; else result = clmul;
	// Zbs
	ALUOP_BCLR:   if (~|EXTENSION_ZBS)       result = 32'hxxxxxxxx; else result = op_a & ~zbs_mask;
	ALUOP_BSET:   if (~|EXTENSION_ZBS)       result = 32'hxxxxxxxx; else result = op_a |  zbs_mask;
	ALUOP_BINV:   if (~|EXTENSION_ZBS)       result = 32'hxxxxxxxx; else result = op_a ^  zbs_mask;
	ALUOP_BEXT:   if (~|EXTENSION_ZBS)       result = 32'hxxxxxxxx; else result = {{W_DATA-1{1'b0}}, shift_dout[0]};
	// Zbkb
	ALUOP_PACK:   if (~|EXTENSION_ZBKB)      result = 32'hxxxxxxxx; else result = {op_b[15:0], op_a[15:0]};
	ALUOP_PACKH:  if (~|EXTENSION_ZBKB)      result = 32'hxxxxxxxx; else result = {{W_DATA-16{1'b0}}, op_b[7:0], op_a[7:0]};
	ALUOP_BREV8:  if (~|EXTENSION_ZBKB)      result = 32'hxxxxxxxx; else result = {op_a_rev[7:0], op_a_rev[15:8], op_a_rev[23:16], op_a_rev[31:24]};
	ALUOP_ZIP:    if (~|EXTENSION_ZBKB)      result = 32'hxxxxxxxx; else result = funct3_32b[2] ? unzip : zip;
	// Zbkx
	ALUOP_XPERM:  if (~|EXTENSION_ZBKX)      result = 32'hxxxxxxxx; else result = funct3_32b[2] ? xperm8 : xperm4;
	// Xh3bextm
	ALUOP_BEXTM:  if (~|EXTENSION_XH3BEXTM)  result = 32'hxxxxxxxx; else result = shift_dout & {24'h0, {~(8'hfe << funct7_32b[3:1])}};
	// Xh3sfx
	ALUOP_SFX:    if (~|EXTENSION_XH3SFX)    result = 32'hxxxxxxxx; else result = sfx_result;
	default:                                                             result = bitwise;
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
