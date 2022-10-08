/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Combined multiply/divide/modulo circuit. All operations performed at 1 bit
// per clock; aiming for minimal resource usage on iCE40 FPGA. Optionally the
// circuit can be unrolled for slightly higher performance.
//
// When op_kill is high, the current calculation halts immediately. op_vld can
// be asserted on the same cycle, and the new calculation begins without
// delay, regardless of op_rdy. This may be used by the processor on e.g.
// mispredict or trap.
//
// The actual multiply/divide hardware is unsigned. We handle signedness at
// input/output.

`default_nettype none

module hazard3_muldiv_seq #(
`include "hazard3_config.vh"
,
`include "hazard3_width_const.vh"
) (
	input  wire               clk,
	input  wire               rst_n,
	input  wire [W_MULOP-1:0] op,
	input  wire               op_vld,
	output wire               op_rdy,
	input  wire               op_kill,
	input  wire [W_DATA-1:0]  op_a,
	input  wire [W_DATA-1:0]  op_b,

	output wire [W_DATA-1:0]  result_h, // mulh* or rem*
	output wire [W_DATA-1:0]  result_l, // mul   or div*
	output wire               result_vld
);

`include "hazard3_ops.vh"

//synthesis translate_off
generate if (MULDIV_UNROLL & (MULDIV_UNROLL - 1) || ~|MULDIV_UNROLL)
	initial $fatal("%m: MULDIV_UNROLL must be a positive power of 2");
endgenerate
//synthesis translate_on

localparam XLEN = W_DATA;
parameter W_CTR = $clog2(XLEN + 1);

// ----------------------------------------------------------------------------
// Operation decode, operand sign adjustment

// On the first cycle, op_a and op_b go straight through to the accumulator
// and the divisor/multiplicand register. They are then adjusted in-place
// on the next cycle. This allows the same circuits to be reused for sign
// adjustment before output (and helps input timing).

reg [W_MULOP-1:0] op_r;
reg [2*XLEN-1:0]  accum;
reg               op_a_neg_r;
reg               op_b_neg_r;

reg               prenegate_op_b;

wire op_a_signed =
	op_r == M_OP_MULH ||
	op_r == M_OP_MULHSU ||
	op_r == M_OP_DIV ||
	op_r == M_OP_REM;

wire op_b_signed =
	op_r == M_OP_MULH ||
	op_r == M_OP_DIV ||
	op_r == M_OP_REM;

wire op_a_neg = op_a_signed && accum[XLEN-1];
wire op_b_neg = op_b_signed && op_b[XLEN-1];

// Non-divide parts of the circuit should be constant-folded if all the MUL
// operations are handled by the fast multiplier

wire is_div = op_r[2] || (MUL_FAST && MULH_FAST);


wire [XLEN-1:0] op_b_sign_adj = prenegate_op_b ? -op_b : op_b;

// Controls for modifying sign of all/part of accumulator
wire accum_neg_l;
wire accum_inv_h;
wire accum_incr_h;

// ----------------------------------------------------------------------------
// Arithmetic circuit

// Combinatorials:
reg [2*XLEN-1:0] accum_next;
reg [2*XLEN-1:0] addend;
reg [2*XLEN-1:0] shift_tmp;
reg [2*XLEN-1:0] addsub_tmp;
reg              neg_l_borrow;

always @ (*) begin: alu
	integer i;
	// Multiply/divide iteration layers
	accum_next = accum;
	addend = {2*XLEN{1'b0}};
	addsub_tmp = {2*XLEN{1'b0}};
	neg_l_borrow = 1'b0;
	for (i = 0; i < MULDIV_UNROLL; i = i + 1) begin
		addend = {is_div && |op_b_sign_adj, op_b_sign_adj, {XLEN-1{1'b0}}};
		shift_tmp = is_div ? accum_next : accum_next >> 1;
		addsub_tmp = shift_tmp + addend;
		accum_next = (is_div ? !addsub_tmp[2 * XLEN - 1] : accum_next[0]) ?
			addsub_tmp : shift_tmp;
		if (is_div)
			accum_next = {accum_next[2*XLEN-2:0], !addsub_tmp[2 * XLEN - 1]};
	end
	// Alternative path for negation of all/part of accumulator
	if (accum_neg_l)
		{neg_l_borrow, accum_next[XLEN-1:0]} = {~accum[XLEN-1:0]} + 1'b1;
	if (accum_incr_h || accum_inv_h)
		accum_next[XLEN +: XLEN] = (accum[XLEN +: XLEN] ^ {XLEN{accum_inv_h}})
			+ accum_incr_h;
end

// ----------------------------------------------------------------------------
// Main state machine

reg sign_preadj_done;
reg [W_CTR-1:0] ctr;
reg sign_postadj_done;
reg sign_postadj_carry;

localparam CTR_TOP = XLEN[W_CTR-1:0];

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		ctr <= {W_CTR{1'b0}};
		sign_preadj_done <= 1'b1;
		sign_postadj_done <= 1'b1;
		sign_postadj_carry <= 1'b0;
		op_r <= {W_MULOP{1'b0}};
		op_a_neg_r <= 1'b0;
		op_b_neg_r <= 1'b0;
		prenegate_op_b <= 1'b0;
		accum <= {XLEN*2{1'b0}};
	end else if (op_kill || (op_vld && op_rdy)) begin
		// Initialise circuit with operands + state
		ctr <= op_vld ? CTR_TOP : {W_CTR{1'b0}};
		sign_preadj_done <= !op_vld;
		sign_postadj_done <= !op_vld;
		sign_postadj_carry <= 1'b0;
		prenegate_op_b <= 1'b0;
		op_r <= op;
		accum <= {{XLEN{1'b0}}, op_a};
	end else if (!sign_preadj_done) begin
		// Pre-adjust sign if necessary, else perform first iteration immediately
		op_a_neg_r <= op_a_neg;
		op_b_neg_r <= op_b_neg;
		sign_preadj_done <= 1'b1;
		if (accum_neg_l || (op_b_neg ^ is_div)) begin
			if (accum_neg_l)
				accum[0 +: XLEN] <= accum_next[0 +: XLEN];
			if (op_b_neg ^ is_div) begin
				prenegate_op_b <= 1'b1;
			end
		end else begin
			ctr <= ctr - MULDIV_UNROLL[W_CTR-1:0];
			accum <= accum_next;
		end
	end else if (|ctr) begin
		ctr <= ctr - MULDIV_UNROLL[W_CTR-1:0];
		accum <= accum_next;
	end else if (!sign_postadj_done || sign_postadj_carry) begin
		sign_postadj_done <= 1'b1;
		if (accum_inv_h || accum_incr_h)
			accum[XLEN +: XLEN] <= accum_next[XLEN +: XLEN];
		if (accum_neg_l) begin
			accum[0 +: XLEN] <= accum_next[0 +: XLEN];
			if (!is_div) begin
				sign_postadj_carry <= neg_l_borrow;
				sign_postadj_done <= !neg_l_borrow;
			end
		end
	end
end

// ----------------------------------------------------------------------------
// Sign adjustment control

// Pre-adjustment: for any a, b we want |a|, |b|. Note that the magnitude of any
// 32-bit signed integer is representable by a 32-bit unsigned integer.

// Post-adjustment for division:
// We seek q, r to satisfy a = b * q + r, where a and b are given,
// and |r| < |b|. One way to do this is if
// sgn(r) = sgn(a)
// sgn(q) = sgn(a) ^ sgn(b)
// This has additional nice properties like
// -(a / b) = (-a) / b = a / (-b)

// Post-adjustment for multiplication:
// We have calculated the 2*XLEN result of |a| * |b|.
// Negate the entire accumulator if sgn(a) ^ sgn(b).
// This is done in two steps (to share div/mod circuit, and avoid 64-bit carry):
// - Negate lower half of accumulator, and invert upper half
// - Increment upper half if lower half carried

wire do_postadj = ~|{ctr, sign_postadj_done};
wire op_signs_differ = op_a_neg_r ^ op_b_neg_r;

assign accum_neg_l =
	!sign_preadj_done && op_a_neg ||
	do_postadj && !sign_postadj_carry && op_signs_differ && !(is_div && ~|op_b_sign_adj);

assign {accum_incr_h, accum_inv_h} =
	do_postadj &&  is_div && op_a_neg_r                             ? 2'b11 :
	do_postadj && !is_div && op_signs_differ && !sign_postadj_carry ? 2'b01 :
	do_postadj && !is_div && op_signs_differ &&  sign_postadj_carry ? 2'b10 :
	                                                                  2'b00 ;

// ----------------------------------------------------------------------------
// Outputs

assign op_rdy = ~|{ctr, accum_neg_l, accum_incr_h, accum_inv_h};
assign result_vld = op_rdy;

`ifndef RISCV_FORMAL_ALTOPS

assign {result_h, result_l} = accum;

`else

// Provide arithmetically simpler alternative operations, to speed up formal checks
always assert(XLEN == 32);

reg [XLEN-1:0] fml_a_saved;
reg [XLEN-1:0] fml_b_saved;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		fml_a_saved <= {XLEN{1'b0}};
		fml_b_saved <= {XLEN{1'b0}};
	end else if (op_vld && op_rdy) begin
		fml_a_saved <= op_a;
		fml_b_saved <= op_b;
	end
end

assign result_h =
	op_r == M_OP_MULH   ? (fml_a_saved + fml_b_saved) ^ 32'hf6583fb7 :
	op_r == M_OP_MULHSU ? (fml_a_saved - fml_b_saved) ^ 32'hecfbe137 :
	op_r == M_OP_MULHU  ? (fml_a_saved + fml_b_saved) ^ 32'h949ce5e8 :
	op_r == M_OP_REM    ? (fml_a_saved - fml_b_saved) ^ 32'h8da68fa5 :
	op_r == M_OP_REMU   ? (fml_a_saved - fml_b_saved) ^ 32'h3138d0e1 : 32'hdeadbeef;

assign result_l =
	op_r == M_OP_MUL    ? (fml_a_saved + fml_b_saved) ^ 32'h5876063e :
	op_r == M_OP_DIV    ? (fml_a_saved - fml_b_saved) ^ 32'h7f8529ec :
	op_r == M_OP_DIVU   ? (fml_a_saved - fml_b_saved) ^ 32'h10e8fd70 : 32'hdeadbeef;

`endif

// ----------------------------------------------------------------------------
// Interface properties

`ifdef HAZARD3_ASSERTIONS

always @ (posedge clk) if (rst_n && $past(rst_n)) begin: properties
	integer i;
	reg alive;

	if ($past(op_rdy && !op_vld))
		assert(op_rdy);

	if (result_vld && $past(result_vld) && !$past(op_kill))
		assert($stable({result_h, result_l}));

	// Kill will halt an in-progress operation, but a new operation may be
	// asserted simultaneously with kill.
	if ($past(op_kill))
		assert(op_rdy == !$past(op_vld));

	// We should be periodically ready (liveness property), unless new operations
	// are forced in immediately, simultaneous with a kill, in which case there
	// is no intermediate ready state.
	alive = op_rdy || (op_kill && op_vld);
	for (i = 1; i <= XLEN / MULDIV_UNROLL + 3; i = i + 1)
		alive = alive || $past(op_rdy || (op_kill && op_vld), i);
	assert(alive);
end

`endif

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
