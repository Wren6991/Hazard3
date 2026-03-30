/*****************************************************************************\
|                        Copyright (C) 2026 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Soft float library for Hazard3, using custom Xh3sfx and Xh3bextm extensions.
// Also uses the following standard ISA extensions: RV32IMZbbZbs

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
// Add and subtract

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
	beq a2, t0, __addsf_x_nan_inf
	// fall through:

__addsf_y_nan_inf:
	// Mirror of __addsf_x_nan_inf
	bnez a5, __addsf_return_y
__addsf_y_inf:
	bne  a2, t0, __addsf_return_y
	bnez a4,     __addsf_return_x
	j __addsf_both_inf

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
	xor a1, a1, a0
	bgez a1,     __addsf_return_x // y is inf of same sign      -> return either x or y (x is faster)
	li a0, -1                     // y is inf of different sign -> return nan
	ret

__addsf_return_y_flushed:
	bnez a3, 1f
	srli a1, a1, 23
	slli a1, a1, 23
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
	beq a2, t0, __addhf_x_nan_inf

__addhf_y_nan_inf:
	bnez a5, __addhf_return_y
__addhf_y_inf:
	bne  a2, t0, __addhf_return_y
	bnez a4,     __addhf_return_x
	j __addhf_both_inf

__addhf_x_nan_inf:
	bnez a4, __addhf_return_x
__addhf_x_inf:
	bne  a3, t0, __addhf_return_x
	bnez a5,     __addhf_return_y
__addhf_both_inf:
	xor a1, a1, a0
	bgez a1,     __addhf_return_x
	li a0, -1
	ret

__addhf_return_y_flushed:
	bnez a3, 1f
	andi a1, a1, -1 << 10
1:
__addhf_return_y:
	mv a0, a1
__addhf_return_x:
	ret


// ----------------------------------------------------------------------------
// Multiply

decl_func_with_section mulsf3
	h3.bextmi a2, a0, 23, 8
	h3.bextmi a3, a1, 23, 8
	h3.fcheck2e.s t0, a2, a3
	bnez t0, __mulsf_special_exponent
	h3.funpackq3.s a4, a0
	h3.funpackq3.s a5, a1

	// Multiply Q3.29 x Q3.29 -> Q6.58
	mul a1, a4, a5
	mulh a4, a4, a5
	// Gather sticky bits from low fraction; a4 now effectively Q6.26
	snez a1, a1
	or a4, a4, a1
	// Normalise (shift left by either 2 or 3)
	h3.feadjq3 a0, a4
	h3.ssrasticky a4, a4, a0
	// Calculate new exponent;
	// -127 is for redundant bias, +3 is for Q6 -> Q3 compensation
	add a2, a2, a0
	add a2, a2, a3
	addi a2, a2, -127 + 3
	h3.fpackrq3.s a0, a4, a2
	ret

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

	mul a1, a4, a5
	mulh a4, a4, a5
	snez a1, a1
	or a4, a4, a1
	h3.feadjq3 a0, a4
	h3.ssrasticky a4, a4, a0

	add a2, a2, a0
	add a2, a2, a3
	addi a2, a2, -15 + 3
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
	// Return canonical NaN on NaN input. Use a zero-extended value for
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
	li t0, 127 + 31
	bgeu a1, t0, __fixsfsi_large_exponent
	h3.funpackq3.s a0, a0
	addi a1, a1, -127 - 29
	h3.xorsign a2, a0, a0
	h3.ssla a2, a2, a1
	h3.xorsign a0, a0, a2
	ret
.p2align 2
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
	li t0, 127 + 31
	bgtu a1, t0, __fixunssfsi_large_exponent
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
decl_func_with_section floatunssisf
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
