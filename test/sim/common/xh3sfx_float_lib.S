/*****************************************************************************\
|                        Copyright (C) 2026 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Soft float library for Hazard3, using custom Xh3sfx and Xh3bextm extensions.
// Also uses the following standard ISA extensions: RV32EMZbbZbs

#include "xh3sfx_intrinsics.h"
#include "xh3bextm_intrinsics.h"

// Redefine XH3SFX_LIB_SECTION move library functions to a different section,
// e.g. RAM vs flash. Functions are still put in individual sections, with
// the function name applied as a suffix on the section name.
#ifndef XH3SFX_LIB_SECTION
#define XH3SFX_LIB_SECTION .text
#endif

// Redefine XH3SFX_LIB_PREFIX to apply a different prefix to the name of all
// functions in this file. The default __ will result in names like __addsf3,
// which replace the libgcc functions.
#ifndef XH3SFX_LIB_PREFIX
#define XH3SFX_LIB_PREFIX __
#endif

.macro decl_func name
.p2align 2
.global XH3SFX_LIB_PREFIX\name
XH3SFX_LIB_PREFIX\name:
.endm

.macro decl_func_with_section name
.section XH3SFX_LIB_SECTION.xh3sfxlib.\name
decl_func \name
.endm

// ----------------------------------------------------------------------------
// Add and subtract (f32 and f16)

decl_func_with_section subsf3
	binvi a1, a1, 31
decl_func addsf3
	h3.bextmi a2, a0, 23, 8
	h3.bextmi a3, a1, 23, 8
	h3.fcheck2e.s t0, a2, a3
	bnez t0, __addsf_special_exponent
	h3.funpackq3.s a4, a0
	h3.funpackq3.s a5, a1

	bltu a2, a3, __addsf_ye_gt_xe

.macro addsf_core packed_lhs, packed_rhs, sig_lhs, sig_rhs, exp_lhs, exp_rhs
	sub \packed_rhs, \exp_lhs, \exp_rhs
	h3.ssrasticky \packed_lhs, \sig_rhs, \packed_rhs
	add \sig_lhs, \sig_lhs, \packed_lhs
	h3.feadjq3 \packed_lhs, \sig_lhs
	h3.ssrasticky \sig_lhs, \sig_lhs, \packed_lhs
	add \exp_lhs, \exp_lhs, \packed_lhs
	h3.fpackrq3.s a0, \sig_lhs, \exp_lhs
	ret
.endm

__addsf_xe_gte_ye:
	addsf_core a0, a1, a4, a5, a2, a3
.p2align 2
__addsf_ye_gt_xe:
	addsf_core a1, a0, a5, a4, a3, a2

__addsf_special_exponent:
	// Flush-to-zero => 0 + y = y applies, including nan, with the sole
	// exception of y being subnormal (which also needs to be flushed)
	beqz a2, __addsf_return_y_flushed
	// Don't have to handle this case for x + 0 = 0 because we already know x
	// is nonzero
	beqz a3, __addsf_return_x
	// check nan/inf on input
	li t0, 255
	slli a4, a0, 9
	slli a5, a1, 9

	// This branch is taken when y is nan or inf, and x is normal. Correct
	// answer is always y, either due to inf-absorption or nan-propagation.
	bne a2, t0, __addsf_return_y
	// fall through: x is nan or inf. y is nan, inf or normal.

__addsf_x_nan_inf:
	// When at least one operand is nan, we must propagate at least one of
	// those nan payloads (sign of nan result is unspecified, which we take
	// advantage of by implementing x - y as x + -y). Check x nan vs inf:
	bnez a4, __addsf_return_x
__addsf_x_inf:
	// If x is +-inf, need to distinguish the following cases:
	bne  a3, t0, __addsf_return_x // y is neither inf nor nan   -> return x (propagate inf)
	bnez a5,     __addsf_return_y // y is nan:                  -> return y (propagate nan)
__addsf_both_inf:
	beq a0, a1,  __addsf_return_x // y is inf of same sign      -> return either x or y (x is faster)
	li a0, -1                     // y is inf of different sign -> return nan
	ret

	// Edge case: adding zeroes is +0 in all cases except for -0 + -0.
	// Difference of zeroes falls under exact cancellation rule, but summing
	// negative zeroes does not.
__addsf_return_y_flushed:
	bnez a3, 1f
	srli a1, a1, 23
	slli a1, a1, 23
	and a1, a1, a0
1:
__addsf_return_y:
	mv a0, a1
__addsf_return_x:
	ret

// Half-precision: essentially the same as single-precision
decl_func_with_section subhf3
	binvi a1, a1, 31
decl_func addhf3
	h3.bextmi a2, a0, 10, 5
	h3.bextmi a3, a1, 10, 5
	h3.fcheck2e.h t0, a2, a3
	bnez t0, __addhf_special_exponent
	h3.funpackq3.h a4, a0
	h3.funpackq3.h a5, a1

	bltu a2, a3, __addhf_ye_gt_xe

.macro addhf_core packed_lhs, packed_rhs, sig_lhs, sig_rhs, exp_lhs, exp_rhs
	sub \packed_rhs, \exp_lhs, \exp_rhs
	h3.ssrasticky \packed_lhs, \sig_rhs, \packed_rhs
	add \sig_lhs, \sig_lhs, \packed_lhs
	h3.feadjq3 \packed_lhs, \sig_lhs
	h3.ssrasticky \sig_lhs, \sig_lhs, \packed_lhs
	add \exp_lhs, \exp_lhs, \packed_lhs
	h3.fpackrq3.h a0, \sig_lhs, \exp_lhs
	ret
.endm

__addhf_xe_gte_ye:
	addhf_core a0, a1, a4, a5, a2, a3
.p2align 2
__addhf_ye_gt_xe:
	addhf_core a1, a0, a5, a4, a3, a2

__addhf_special_exponent:
	beqz a2, __addhf_return_y_flushed
	beqz a3, __addhf_return_x
	li t0, 31
	slli a4, a0, 22
	slli a5, a1, 22
	bne a2, t0, __addhf_return_y

__addhf_x_nan_inf:
	bnez a4, __addhf_return_x
__addhf_x_inf:
	bne  a3, t0, __addhf_return_x
	bnez a5,     __addhf_return_y
__addhf_both_inf:
	beq a0, a1,  __addhf_return_x
	li a0, -1
	ret

__addhf_return_y_flushed:
	bnez a3, 1f
	andi a1, a1, -1 << 10
	and a1, a1, a0
1:
__addhf_return_y:
	mv a0, a1
__addhf_return_x:
	sext.h a0, a0
	ret


// ----------------------------------------------------------------------------
// Multiply (f32 and f16)

decl_func_with_section mulsf3
	h3.bextmi a2, a0, 23, 8
	h3.bextmi a3, a1, 23, 8
	h3.fcheck2e.s t0, a2, a3
	bnez t0, __mulsf_special_exponent
#ifndef XH3SFX_AVOID_MULH
	// Path for when mul and mulh are equally fast
	h3.funpackq3.s a4, a0
	h3.funpackq3.s a5, a1
	// Multiply Q3.29 x Q3.29 -> Q6.58
	mul a1, a4, a5
	mulh a4, a4, a5
	// Gather sticky bits from low fraction; a4 now effectively Q6.26
	snez a1, a1
	or a4, a4, a1
	// Shift up to Q3: this shift is exact as it's always to-left
	h3.feadjq3 a5, a4
	h3.ssra a4, a4, a5
	// Calculate new exponent;
	// -127 is for redundant bias, +3 is for Q6 -> Q3 offset
	add a2, a2, a3
	add a2, a2, a5
	addi a2, a2, -127 + 3
	h3.fpackrq3.s a0, a4, a2
	ret
#else
	// Path for when mul is much faster than mulh. Only worth it when mulh is
	// 32+ cycles and mul is 1 cycle (MULDIV_UNROLL=1 MUL_FAST=1 MULH_FAST=0).
	// Unpack sign separately from significand:
	h3.funpacku3.s a4, a0
	h3.funpacku3.s a5, a1
	// Calculate sign and exponent; free up a2/a3
	xor a0, a0, a1
	add a1, a3, a2
	addi a1, a1, -127 + 3
	// Multiply U3.29 x U3.29 -> U6.58. (32 x 32 -> 64)
	srli a2, a4, 16
	srli a3, a5, 16
	zext.h a4, a4
	zext.h a5, a5
	mul t0, a2, a3  // A_h * B_h
	mul t1, a2, a5  // A_h * B_l
	mul a2, a4, a3  // A_l * B_h
	mul a4, a4, a5  // A_l * B_l
	// Sum the crossed terms, save carry-in for hi[16]
	add t1, a2, t1
	sltu t2, t1, a2
	// Add crossed terms to low word, save carry-in for hi[0]
	slli a2, t1, 16
	add a4, a4, a2
	sltu a3, a4, a2
	// Pack carries with correct significance
	pack a3, a3, t2
	// High word: A_h * B_h + (crossed terms >> 16) + ci0 + (ci1 << 16)
	srli t1, t1, 16
	add a5, t0, t1
	add a5, a5, a3
	// Final product complete: U6.58 in a5:a4. Collect low sticky bits.
	snez a4, a4
	or a5, a5, a4
	// Renormalise to Q3
	h3.feadju3 a4, a5
	h3.ssra a5, a5, a4
	add a1, a1, a4
	// Apply sign before packing. Only upper U3.29 is relevant.
	h3.xorsign a5, a0, a5
	h3.fpackrq3.s a0, a5, a1
	ret
#endif

.p2align 2
__mulsf_special_exponent:
	// Force y to be positive (by possibly negating x) *before* unpacking.
	// This allows many special cases to be handled without repacking.
	bgez a1, 1f
	binvi a0, a0, 31
1:
	li t0, 255
	slli a4, a0, 9
	slli a5, a1, 9
	beqz a2, __mulsf_x_0
	beqz a3, __mulsf_y_0
	beq a2, t0, __mulsf_x_nan_inf
	// fall through:
__mulsf_y_nan_inf:
	// We know that x is not zero, nan, nor inf. That just leaves normals.
	// y is nan -> return y
	// y is inf -> return inf * sgn(x) (since we already merged the signs)
	bnez a5, __mulsf_return_y
	// Works because we have nonzero "significand" and exp=255:
	h3.fpackrq3.s a0, a0, a3
	ret

__mulsf_x_0:
	// 0 times nan    -> propagate nan
	// 0 times inf    -> generate nan
	// 0 times others -> 0 (need to flush significand too as we are FTZ)
	bne a3, t0, __mulsf_return_flushed_x
	beqz a5, 1f
	// Propagate nan from y
__mulsf_return_y:
	mv a0, a1
	ret

__mulsf_y_0:
	// Mirror image of x_0 except we still return x for signed 0, since the
	// signs were already resolved.
	bne a2, t0, __mulsf_return_flushed_x
	bnez a4, 2f
1:
	// Generate new nan
	li a0, -1
2:
	// Propagate nan from x
	ret

__mulsf_return_flushed_x:
	// If we don't support subnormals we at least need to flush to a canonical
	// zero. This is just a sign bit in bit 31.
	srli a0, a0, 31
	slli a0, a0, 31
__mulsf_return_x:
	ret

__mulsf_x_nan_inf:
	// We know that y is not zero and is positive. So...
	//      x is nan    -> return x
	// else y is nan    -> return y
	// else y is inf    -> return x
	// else y is normal -> return x
	// (the order of the first two clauses is actually our free choice)
	bnez a4, __mulsf_return_x
	bne a3, t0, __mulsf_return_x
	bnez a5, __mulsf_return_y
	ret // return x


// Half-precision: essentially the same as single-precision
decl_func_with_section mulhf3
	h3.bextmi a2, a0, 10, 5
	h3.bextmi a3, a1, 10, 5
	h3.fcheck2e.h t0, a2, a3
	bnez t0, __mulhf_special_exponent
	h3.funpackq3.h a4, a0
	h3.funpackq3.h a5, a1
	// Scale down so multiply result is Q3.29. Shift is exact as we're
	// shifting zeroes.
	srai a4, a4, 14
	srai a5, a5, 15
	mul a4, a4, a5
	// Result is in range 1 <= |x| < 4. For f16 inputs it's guaranteed not to
	// round up to 4 (both inputs all-ones -> ~2 ulps below). Therefore
	// within normalisation range of fpackrq3.h (max shift >>1)
	add a2, a2, a3
	addi a2, a2, -15
	h3.fpackrq3.h a0, a4, a2
	ret

.p2align 2
__mulhf_special_exponent:
	bexti t1, a1, 15
	slli t1, t1, 15
	xor a0, a0, t1
	li t0, 31
	slli a4, a0, 22
	slli a5, a1, 22
	beqz a2, __mulhf_x_0
	beqz a3, __mulhf_y_0
	beq a2, t0, __mulhf_x_nan_inf
__mulhf_y_nan_inf:
	bnez a5, __mulhf_return_y
	sext.h a0, a0
	h3.fpackrq3.h a0, a0, a3
	ret

__mulhf_x_0:
	bne a3, t0, __mulhf_return_flushed_x
	beqz a5, 1f
__mulhf_return_y:
	mv a0, a1
	ret

__mulhf_y_0:
	bne a2, t0, __mulhf_return_flushed_x
	bnez a4, 2f
1:
	li a0, -1
2:
	ret

__mulhf_return_flushed_x:
	srli a0, a0, 15
	slli a0, a0, 15
__mulhf_return_x:
	ret

__mulhf_x_nan_inf:
	bnez a4, __mulhf_return_x
	bne a3, t0, __mulhf_return_x
	bnez a5, __mulhf_return_y
	ret

// ----------------------------------------------------------------------------
// Other arithmetic

decl_func_with_section negsf2
	binvi a0, a0, 31
	ret

decl_func_with_section neghf2
	binvi a0, a0, 15
	ret

// Concatenation of exponent and significand is correctly ordered with respect
// to magnitude. This is a 31-bit value; convert sign-magnitude to two's
// complement to get a fully correctly ordered 32-bit integer. This doesn't
// handle NaNs gracefully but, quote libgcc docs, "you should not rely on
// this".
decl_func_with_section fcmpsf2
decl_func lesf2
decl_func ltsf2
decl_func gesf2
decl_func gtsf2
	bclri a2, a0, 31
	bclri a3, a1, 31
	h3.xorsign a2, a0, a2
	h3.xorsign a3, a1, a3
	slt a1, a2, a3
	slt a0, a3, a2
	sub a0, a0, a1
	ret

decl_func_with_section fcmphf2
decl_func lehf2
decl_func lthf2
decl_func gehf2
decl_func gthf2
	slli a0, a0, 16
	slli a1, a1, 16
	bclri a2, a0, 31
	bclri a3, a1, 31
	h3.xorsign a2, a0, a2
	h3.xorsign a3, a1, a3
	slt a1, a2, a3
	slt a0, a3, a2
	sub a0, a0, a1
	ret

// ----------------------------------------------------------------------------
// Conversions: f32 <-> f16

// Convert single-precision to half-precision
decl_func_with_section truncsfhf2
	h3.funpackq3.s a1, a0
	h3.bextmi a2, a0, 23, 8
	addi t0, a2, -255
	beqz t0, 2f
1:
	addi a2, a2, -127 + 15
	h3.fpackrq3.h a0, a1, a2
	ret
2:
	// Return canonical NaN on NaN input. Use a sign-extended value for
	// consistency with other half-precision results.
	slli a0, a0, 9
	beqz a0, 1b
	li a0, -1
	ret

// Convert half-precision to single-precision
decl_func_with_section extendhfsf2
	h3.funpackq3.h a1, a0
	h3.bextmi a2, a0, 10, 5
	h3.fcheck2e.h t0, a2, a2
	bnez t0, 2f
	addi a2, a2, -15 + 127
1:
	h3.fpackrq3.s a0, a1, a2
	ret
2:
	// Zero, infinity or NaN. Zero will underflow correctly if re-packed
	// without re-biasing exponent:
	beqz a2, 1b
	// Distinguish infinity from NaN:
	slli a0, a0, 22
	beqz a0, 3f
	// Canonicalise NaN
	li a0, -1
	ret
3:
	// Force exponent overflow to generate signed infinity:
	slli a2, a2, 4
	j 1b

// ----------------------------------------------------------------------------
// Conversions: f32 <-> i32, u32

// Convert single-precision to signed integer
decl_func_with_section fixsfsi
	h3.bextmi a1, a0, 23, 8
	sltiu a5, a1, 127 + 31
	beqz a5, __fixsfsi_large_exponent
	h3.funpacku3.s a2, a0
	addi a1, a1, -127 - 29
	h3.ssla a2, a2, a1
	h3.xorsign a0, a0, a2
	ret
__fixsfsi_large_exponent:
	srai a0, a0, 31
	li a1, -1
	srli a1, a1, 1
	xor a0, a0, a1
	ret

// Convert single-precision to unsigned integer
decl_func_with_section fixunssfsi
	bltz a0, __fixunssfsi_neg
	h3.bextmi a1, a0, 23, 8
	sltiu a5, a1, 127 + 32
	beqz a5, __fixunssfsi_large_exponent
	h3.funpackq3.s a0, a0
	addi a1, a1, -127 - 29
	h3.ssll a0, a0, a1
	ret
__fixunssfsi_large_exponent:
	li a0, -1
	ret
__fixunssfsi_neg:
	li a0, 0
	ret

// Convert signed integer to single-precision
decl_func_with_section floatsisf
	beqz a0, 1f
	h3.feadjq3 a1, a0
	h3.ssrasticky a0, a0, a1
	// E.g.: integer 1 will have Q3 normalisation shift of -29, and
	// should have unbiased exponent of 0. Larger values have smaller
	// (i.e. more-positive) normalisation shifts.
	addi a1, a1, 127 + 29
	h3.fpackrq3.s a0, a0, a1
1:
	ret

// Convert unsigned integer to single-precision
// Note: for "float" functions the unsigned prefix is "un" instead of "uns"
decl_func_with_section floatunsisf
	beqz a0, 1f
	// Normalise to U3.29
	h3.feadju3 a1, a0
	h3.ssrlsticky a0, a0, a1
	// Calculate exponent
	addi a1, a1, 127 + 29
	// Round and pack
	h3.fpackrq3.s a0, a0, a1
1:
	ret

// ----------------------------------------------------------------------------
// Conversions: f32 <-> i64, u64

// Convert single-precision to signed 64-bit integer
decl_func_with_section fixsfdi
	h3.bextmi a1, a0, 23, 8
	sltiu a5, a1, 127 + 63
	beqz a5, __fixsfdi_large_exponent
	// It's tempting to use h3.ssla for the signed shift, but we need to do an
	// unsigned shift of absolute value to get truncation towards zero.
	h3.funpacku3.s a2, a0
	addi a1, a1, -127 - 29
	bltz a0, 1f
	h3.ssll a0, a3, a1
	addi a1, a1, -32
	h3.ssll a1, a3, a1
	ret
1:
	h3.ssll a0, a3, a1
	addi a1, a1, -32
	h3.ssll a1, a3, a1
	// 64-bit negation; a0 carries out only if zero
	seqz a2, a0
	neg a0, a0
	not a1, a1
	add a1, a1, a2
	ret
__fixsfdi_large_exponent:
	srai a0, a0, 31
	li a1, -1
	srli a1, a1, 1
	xor a1, a1, a0
	not a0, a0
	ret

// Convert single-precision to unsigned 64-bit integer
decl_func_with_section fixunssfdi
	bltz a0, __fixunssfdi_neg
	h3.bextmi a1, a0, 23, 8
	sltiu a5, a1, 127 + 64
	beqz a5, __fixunssfdi_large_exponent
	h3.funpacku3.s a2, a0
	addi a1, a1, -127 - 29
	h3.ssll a0, a2, a1
	addi a1, a1, -32
	h3.ssll a1, a2, a1
	ret
__fixunssfdi_large_exponent:
	li a0, -1
	li a1, -1
	ret
__fixunssfdi_neg:
	li a0, 0
	li a1, 0
	ret

// ----------------------------------------------------------------------------
// Conversions: f16 <-> i32, u32

// Convert half-precision to signed integer
decl_func_with_section fixhfsi
	h3.bextmi a1, a0, 10, 5
	h3.funpackq3.h a0, a0
	li t0, 31
	beq a1, t0, __fixhfsi_inf_nan
	addi a1, a1, -15 - 29
	h3.xorsign a2, a0, a0
	h3.ssla a2, a2, a1
	h3.xorsign a0, a0, a2
	ret
.p2align 2
__fixhfsi_inf_nan:
	srai a0, a0, 31
	li a1, -1
	srli a1, a1, 1
	xor a0, a0, a1
	ret

// Convert half-precision to unsigned integer
decl_func_with_section fixunshfsi
	h3.bextmi a1, a0, 10, 5
	h3.funpackq3.h a0, a0
	bltz a0, __fixunshfsi_neg
	li t0, 31
	beq a1, t0, __fixunshfsi_inf_nan
	addi a1, a1, -15 - 29
	h3.ssll a0, a0, a1
	ret
__fixunshfsi_inf_nan:
	li a0, -1
	ret
__fixunshfsi_neg:
	li a0, 0
	ret

// Convert signed integer to half-precision
decl_func_with_section floatsihf
	beqz a0, 1f
	h3.feadjq3 a1, a0
	h3.ssrasticky a0, a0, a1
	// E.g.: integer 1 will have Q3 normalisation shift of -29, and
	// should have unbiased exponent of 0. Larger values have smaller
	// (i.e. more-positive) normalisation shifts.
	addi a1, a1, 15 + 29
	h3.fpackrq3.h a0, a0, a1
1:
	ret

// Convert unsigned integer to half-precision
// Note: for "float" functions the unsigned prefix is "un" instead of "uns"
decl_func_with_section floatunsihf
	beqz a0, 1f
	// Normalise to U3.29
	h3.feadju3 a1, a0
	h3.ssrlsticky a0, a0, a1
	// Calculate exponent
	addi a1, a1, 15 + 29
	// Round and pack
	h3.fpackrq3.h a0, a0, a1
1:
	ret


// ----------------------------------------------------------------------------
// i64 and u64

// Yes it's floating point, the point just floats in one place

decl_func_with_section ashldi3
    addi a3, a2, -32
    h3.ssll a4, a0, a3
    h3.ssll a1, a1, a2
    h3.ssll a0, a0, a2
    or a1, a1, a4
    ret

decl_func_with_section lshrdi3
    addi a3, a2, -32
    h3.ssrl a4, a1, a3
    h3.ssrl a1, a1, a2
    h3.ssrl a0, a0, a2
    or a0, a0, a4
    ret

decl_func_with_section ashrdi3
    addi a3, a2, -32
    h3.ssra a4, a1, a3
    h3.ssra a1, a1, a2
    h3.ssrl a0, a0, a2
    or a0, a0, a4
    ret

// ----------------------------------------------------------------------------
// f64 arithmetic

// Double on RV32E? Here's a nickel, kid. Go buy yourself a real computer.
#ifdef __riscv_i

decl_func_with_section subdf3
	binvi a3, a3, 31
decl_func adddf3
	// Extract exponents
	slli a4, a1, 1
	srli a4, a4, 21
	slli a5, a3, 1
	srli a5, a5, 21
	// Divert special-case exponents from main path; t0 is useful again later
	li t0, 0x7ff
	beqz a4, __adddf_return_y_flushed
	beqz a5, __adddf_return_x
	beq a4, t0, __adddf_x_nan_inf
	beq a5, t0, __adddf_y_nan_inf
	// Extract significand as U9.55 (need three extra fractional bits for rounding)
	// x is a6:a0
	slli a6, a1, 12
	srli a6, a6, 9
	bseti a6, a6, 23
	srli t1, a0, 29
	add a6, a6, t1
	slli a0, a0, 3
	// y is a7:a2
	slli a7, a3, 12
	srli a7, a7, 9
	bseti a7, a7, 23
	srli t1, a2, 29
	add a7, a7, t1
	slli a2, a2, 3
	// Sign-magnitude conversion: U8.56 -> Q8.56
	bgez a1, 1f
	seqz t1, a0
	neg a0, a0
	not a6, a6
	add a6, a6, t1
1:
	bgez a3, 1f
	seqz t1, a2
	neg a2, a2
	not a7, a7
	add a7, a7, t1
1:
	// a3, a1 now free.
	// a4, a5 are exp.

	// el >= er.
.macro adddf_core ll, lh, rl, rh, el, er, l_is_x
	// Exponent difference may be out of h3.* shift range, so need a branch.
	// Since we already have the branch, also use it as early-out for addends
	// too small to change the result. This could be improved if we hadn't
	// already trashed a0-a3.
	sub \er, \el, \er
	li t1, 54
	bgeu \er, t1, 11f
	// Shift rhs by exponent difference
	addi t2, \er, -32
	h3.ssrasticky t1, \rh, t2
	h3.ssrlsticky \rl, \rl, \er
	h3.ssra \rh, \rh, \er
	or \rl, \rl, t1
	// Add significands; sum in lh:er
	add \er, \ll, \rl
	sltu \ll, \er, \ll
	add \lh, \lh, \rh
	add \lh, \lh, \ll
12:
	// Split sign/magnitude; keep sign in t3
	srai t3, \lh, 31
	bgez t3, 1f
	seqz t1, \er
	neg \er, \er
	not \lh, \lh
	add \lh, \lh, t1
1:
	// Renormalise as U1.63; case where upper U9.23 is all-zero is
	// non-fallthrough as this amount of cancellation is uncommon. U1 makes
	// it cheap to detect exponent increase on rounding.
	beqz \lh, 3f
	clz t1, \lh
4:
	// Take this opportunity to move back to lh:ll as it's confusing. Note
	// this shift is always to-left due to the change from U8 to U1; this
	// ensures it is exact and avoids calculating the H->L shift contribution.
	addi t2, t1, -32
	h3.ssll \ll, \er, t1
	h3.ssll \lh, \lh, t1
	h3.ssll \er, \er, t2
	or \lh, \lh, \er
	// Calculate new exponent
	sub \el, \el, t1
	addi \el, \el, 8
	// Calculate rounding bias: U1.63 => 11 excess fractional bits.
	li t2, 0x3ff
	bexti t1, \ll, 11
	add t2, t2, t1
	// Add rounding bias. Rounded result is lh:er
	add \er, \ll, t2
	sltu \ll, \er, \ll
	add \lh, \lh, \ll
	// Check for exponent increase due to rounding
	bgez \lh, 5f
6:
	// Check for exponent saturation; t0 = biased emax preserved since start
	bgeu \el, t0, 7f
	// Pack normal result
	slli t3, t3, 11
	add t3, t3, \el
	slli t3, t3, 20 // {sign, exp, 20'd0}

	srli t2, \er, 11
	slli t1, \lh, 21
	or a0, t1, t2

	srli \lh, \lh, 11
	bclri \lh, \lh, 20
	or a1, t3, \lh
	ret

	// Special cases follow.
3:
	// Renormalisation case for upper word all-zeroes after absl(). If lower
	// word is also all-zeroes, this is an exact cancellation. Prioritise the
	// speed of non-exact cancellation.
	clz t1, \er
	addi t1, t1, 32
	bnez \er, 4b
	// Return +0 for exact cancellation
	li a0, 0
	li a1, 0
	ret
5:
	// Handle exponent increase due to rounding
	addi \el, \el, 1
	slli t2, \lh, 31
	srli \lh, \lh, 1
	srli \er, \er, 1
	add \er, \er, t2
	j 6b
7:
	// Handle exponent saturation
	li a0, 0
	bgtz \el, 9f
	// Return signed zero on subnormal or underflow
	slli a1, t3, 31
	ret
9:
	// Return signed infinity on overflow
	slli a1, t3, 11
	addi a1, a1, 0x7ff
	slli a1, a1, 20
	ret
11:
	// Skip addition, fix up register allocation
	mv \er, \ll
	j 12b
.endm

	bltu a4, a5, __adddf_ye_gt_xe
__adddf_xe_ge_ye:
	adddf_core a0, a6, a2, a7, a4, a5, 1
__adddf_ye_gt_xe:
	adddf_core a2, a7, a0, a6, a5, a4, 0

__adddf_x_nan_inf:
	// x is nan -> propagate it
	bnez a0, __adddf_return_x
	slli t3, a1, 12
	bnez t3, __adddf_return_x
__adddf_x_inf:
	// We know that x is +-inf, and y is nonzero. If y is normal, propagate inf.
	bne  a5, t0, __adddf_return_x
	// y is nan or inf. If nan, propagate y.
	bnez a2, __adddf_return_y
	slli t3, a3, 12
	bnez t3, __adddf_return_y
__adddf_both_inf:
	// Adding same infinity -> same infinity.
	beq a1, a3, __adddf_return_x
	// Adding different infinities -> nan.
	li a1, -1
	li a0, -1
	ret

__adddf_y_nan_inf:
	// y is nan -> propagate it.
	bnez a2, __adddf_return_y
	slli t3, a3, 12
	bnez t3, __adddf_return_y
__adddf_y_inf:
	// We know that y is +-inf, and x is nonzero. If x is normal, propagate inf.
	bne  a4, t0, __adddf_return_y
	// x is nan or inf. If nan, propagate x.
	bnez a0, __adddf_return_x
	slli t3, a1, 12
	bnez t3, __adddf_return_x
	j __adddf_both_inf

__adddf_return_y_flushed:
	bnez a5, 1f
	li a2, 0
	srli a3, a3, 20
	slli a3, a3, 20
	// only -0 + -0 is -0; other +-0 combinations yield +0.
	and a3, a3, a1
1:
__adddf_return_y:
	mv a0, a2
	mv a1, a3
__adddf_return_x:
	ret

#endif // __riscv_i

