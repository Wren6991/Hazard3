/*****************************************************************************\
|                        Copyright (C) 2026 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Soft float library for Hazard3, using custom Xh3sfx and Xh3bextm extensions.
// Also uses the following standard ISA extensions:
//
// * RV32EMZbbZbs (all routines)
// * Zba (single-precision mul, if XH3SFX_AVOID_HIGH_IMUL is defined)
// * RV32I (double-precision add, sub, mul; these require full 31 GPRs)
//
// When building for RV32E, the double-precision add/sub/mul are excluded from
// the build, and the linker falls back to whatever your compiler provides.

#include "xh3sfx_intrinsics.h"
#include "xh3bextm_intrinsics.h"

// ----------------------------------------------------------------------------
// Library configuration

// Redefine XH3SFX_LIB_SECTION to move library functions to a different
// section, e.g. RAM vs flash. Functions are still put in individual sections,
// with the function name applied as a suffix on the section name.
#ifndef XH3SFX_LIB_SECTION
#define XH3SFX_LIB_SECTION .text
#endif

// Redefine XH3SFX_LIB_PREFIX to apply a different prefix to the name of all
// functions in this file. The default __ will result in names like __addsf3,
// which replace the libgcc functions.
#ifndef XH3SFX_LIB_PREFIX
#define XH3SFX_LIB_PREFIX __
#endif

// Prefer multi-mul sequences over mulh/mulhu/mulhsu:
#ifndef XH3SFX_AVOID_HIGH_IMUL
#define XH3SFX_AVOID_HIGH_IMUL 0
#endif

// ----------------------------------------------------------------------------
// Feature configuration

// A feature is enabled if its feature macro is undefined, or defined to 1.
// A feature is disabled if its feature macro is defined to 0.
//
// To disable individual features:
//
//    -DXH3SFX_FEAT_xxx=0
//
// To disable all features, then re-enable individual ones:
//
//    -DXH3SFX_FEAT_OPT_IN
//    -DXH3SFX_FEAT_xxx=1
//
// The "opt-in" flag defines all undefined feature macros to 0. Note that,
// since each function is emitted in its own section (except for those like
// addsf3/subsf3 that share a lot of code), your linker should be able to drop
// unused functions if you pass -Wl,--gc-sections or similar. The main reason
// to disable a feature is if it does something you disagree with, not to
// reduce your binary size.

#ifdef XH3SFX_FEAT_OPT_IN
// Single-precision add and subtract:
#ifndef XH3SFX_FEAT_ADDS
#define XH3SFX_FEAT_ADDS 0
#endif
// Half-precision add and subtract:
#ifndef XH3SFX_FEAT_ADDH
#define XH3SFX_FEAT_ADDH 0
#endif
// Single-precision multiply:
#ifndef XH3SFX_FEAT_MULS
#define XH3SFX_FEAT_MULS 0
#endif
// Half-precision multiply:
#ifndef XH3SFX_FEAT_MULH
#define XH3SFX_FEAT_MULH 0
#endif
// Single-precision negate:
#ifndef XH3SFX_FEAT_NEGS
#define XH3SFX_FEAT_NEGS 0
#endif
// Half-precision negate:
#ifndef XH3SFX_FEAT_NEGH
#define XH3SFX_FEAT_NEGH 0
#endif
// Single-precision compare (orders NaN > inf):
#ifndef XH3SFX_FEAT_FCMPS
#define XH3SFX_FEAT_FCMPS 0
#endif
// Half-precision compare (orders NaN > inf):
#ifndef XH3SFX_FEAT_FCMPH
#define XH3SFX_FEAT_FCMPH 0
#endif
// Conversions between single- and half-precision:
#ifndef XH3SFX_FEAT_S2H_H2S
#define XH3SFX_FEAT_S2H_H2S 0
#endif
// Single-precision float-to-int and int-to-float conversions:
#ifndef XH3SFX_FEAT_F2I_I2F
#define XH3SFX_FEAT_F2I_I2F 0
#endif
// Half-precision float-to-int and int-to-float conversions:
#ifndef XH3SFX_FEAT_H2I_I2H
#define XH3SFX_FEAT_H2I_I2H 0
#endif
// 64-bit integer shifts
#ifndef XH3SFX_FEAT_LONGSHIFT
#define XH3SFX_FEAT_LONGSHIFT 0
#endif
// Double-precision add and subtract (non-RVE):
#ifndef XH3SFX_FEAT_ADDD
#define XH3SFX_FEAT_ADDD 0
#endif
// Double-precision mul (non-RVE):
#ifndef XH3SFX_FEAT_MULD
#define XH3SFX_FEAT_MULD 0
#endif
#endif

// ----------------------------------------------------------------------------
// Helper macros

.macro decl_func name
.p2align 2
.global XH3SFX_LIB_PREFIX\name
XH3SFX_LIB_PREFIX\name:
.endm

.macro decl_func_with_section name
.section XH3SFX_LIB_SECTION.xh3sfxlib.\name
decl_func \name
.endm

// Helper macro to get symbol name for intra-library calls (note middle CATX
// layer is required for expansion of literal XH3SFX_LIB_PREFIX):
#define _XH3SFX_CAT(a, b) a ## b
#define _XH3SFX_CATX(a, b) _XH3SFX_CAT(a, b)
#define XH3SFX_FUNCNAME(name) _XH3SFX_CATX(XH3SFX_LIB_PREFIX, name)

// ----------------------------------------------------------------------------
// Add and subtract (f32 and f16)

#if !defined(XH3SFX_FEAT_ADDS) || XH3SFX_FEAT_ADDS
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
#endif // XH3SFX_FEAT_ADDS

// Half-precision: essentially the same as single-precision
#if !defined(XH3SFX_FEAT_ADDH) || XH3SFX_FEAT_ADDH
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
#endif // XH3SFX_FEAT_ADDH


// ----------------------------------------------------------------------------
// Multiply (f32 and f16)

#if !defined(XH3SFX_FEAT_MULS) || XH3SFX_FEAT_MULS
decl_func_with_section mulsf3
	h3.bextmi a2, a0, 23, 8
	h3.bextmi a3, a1, 23, 8
	h3.fcheck2e.s t0, a2, a3
	bnez t0, __mulsf_special_exponent
#if !XH3SFX_AVOID_HIGH_IMUL
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
	// Path for when mul is faster than mulh. This uses a variant of Mark
	// Owen's trick for calculating a 23 x 23 -> 46-bit product with two
	// 32-bit multiplies.
	li t2, -1 << 23
	andn a4, a0, t2           // x - 1, U0.23
	andn a5, a1, t2           // y - 1, U0.23
	bseti t2, a4, 23
	add t2, t2, a5            // x + y - 1, U2.23 (useful later)
	xor a0, a0, a1            // sign
	add a1, a3, a2            // a2/a3 now free
	addi a1, a1, -127 + 3     // exponent
	mul a2, a4, a5            // exact[31:0]
	srli a4, a4, 7
	srli a5, a5, 7
	mul a4, a4, a5            // approx[45:14]
	// Error on approx[45:0] is slightly better than -2^31 < err <= 0.
	// Only two possibilities:
	//
	// * approx[45:31] is equal to exact[45:31]
	//
	// * approx[31] differs from exact[31]; adding 2^31 corrects bits 45:31
	//
	// Carry into approx[32] occurs when approx[31] is set and exact[31] is
	// clear. So, adding !exact[31] to approx[31] corrects bits 45:32 (only).
	srli a4, a4, 17
	bltz a2, 1f
	addi a4, a4, 1
1:
	srli a4, a4, 1
	// Now: exact[45:32] in a4, exact[31:0] in a2. Pack U6.26 with sticky LSB.
	slli a4, a4, 12
	li a5, 20
	h3.ssrlsticky a2, a2, a5
	or a4, a4, a2
	// Just got:     p = (x - 2^23)(y - 2^23)
	//                 = xy - (x + y) * 2^23 + 2^46
	// Already had:  s = x + y - 2^23
	//
	// Want:        xy = p + (s + 2^23) * 2^23 - 2^46
	//                 = p + s * 2^23
	sh3add a4, t2, a4
	// Normalise to U3.29
	h3.feadju3 a5, a4
	h3.ssrlsticky a4, a4, a5
	add a1, a1, a5
	// Apply sign before packing.
	h3.xorsign a4, a0, a4
	h3.fpackrq3.s a0, a4, a1
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
#endif // XH3SFX_FEAT_MULS

// Half-precision: essentially the same as single-precision.
#if !defined(XH3SFX_FEAT_MULH) || XH3SFX_FEAT_MULH
decl_func_with_section mulhf3
	h3.bextmi a2, a0, 10, 5
	h3.bextmi a3, a1, 10, 5
	h3.fcheck2e.h t0, a2, a3
	bnez t0, __mulhf_special_exponent
	h3.funpackq3.h a4, a0
	h3.funpackq3.h a5, a1
	// Scale down so multiply result is Q3.29. Shift is exact as we're
	// shifting zeroes (19 trailing zeroes on unpacked f16).
	srai a4, a4, 14
	srai a5, a5, 15
	mul a4, a4, a5
	h3.feadjq3 a5, a4
	h3.ssra a4, a4, a5
	add a2, a2, a3
	add a2, a2, a5
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
	// Return signed 0 for 0 * 0 and 0 * norm
	bne a3, t0, __mulhf_return_flushed_x
	// Generate nan for 0 * inf
	beqz a5, 1f
	// Propagate nan for 0 * nan
__mulhf_return_y:
	sext.h a0, a1
	ret

__mulhf_y_0:
	// Return signed 0 for norm * 0
	bne a2, t0, __mulhf_return_flushed_x
	// Propagate nan for nan * 0
	bnez a4, 2f
	// Generate nan for inf * 0
1:
	li a0, -1
2:
	sext.h a0, a0
	ret

__mulhf_return_flushed_x:
	// Return +-0 (always sign-extended from 15 to match Zhinx)
	srli a0, a0, 15
	slli a0, a0, 15
__mulhf_return_x:
	sext.h a0, a0
	ret

__mulhf_x_nan_inf:
	// Propagate first nan for nan * norm, nan * nan, nan * inf
	bnez a4, __mulhf_return_x
	// Propagate inf for inf * norm
	bne a3, t0, __mulhf_return_x
	// Propagate nan for inf * nan
	bnez a5, __mulhf_return_y
	// Propagate inf for inf * inf
	sext.h a0, a0
	ret
#endif // XH3SFX_FEAT_MULH

// ----------------------------------------------------------------------------
// Other arithmetic

#if !defined(XH3SFX_FEAT_NEGS) || XH3SFX_FEAT_NEGS
decl_func_with_section negsf2
	binvi a0, a0, 31
	ret
#endif

#if !defined(XH3SFX_FEAT_NEGH) || XH3SFX_FEAT_NEGH
decl_func_with_section neghf2
	binvi a0, a0, 15
	ret
#endif

// Concatenation of exponent and significand is correctly ordered with respect
// to magnitude. This is a 31-bit value; convert sign-magnitude to two's
// complement to get a fully correctly ordered 32-bit integer. This doesn't
// handle NaNs gracefully but, quote libgcc docs, "you should not rely on
// this".
#if !defined(XH3SFX_FEAT_FCMPS) || XH3SFX_FEAT_FCMPS
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
#endif

#if !defined(XH3SFX_FEAT_FCMPH) || XH3SFX_FEAT_FCMPH
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
#endif

// ----------------------------------------------------------------------------
// Conversions: f32 <-> f16

#if !defined(XH3SFX_FEAT_S2H_H2S) || XH3SFX_FEAT_S2H_H2S
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
#endif

// ----------------------------------------------------------------------------
// Conversions: f32 <-> i32, u32

#if !defined(XH3SFX_FEAT_F2I_I2F) || XH3SFX_FEAT_F2I_I2F
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
#endif

// ----------------------------------------------------------------------------
// Conversions: f32 <-> i64, u64

#if !defined(XH3SFX_FEAT_F2I_I2F) || XH3SFX_FEAT_F2I_I2F
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
	h3.ssll a0, a2, a1
	addi a1, a1, -32
	h3.ssll a1, a2, a1
	ret
1:
	h3.ssll a0, a2, a1
	addi a1, a1, -32
	h3.ssll a1, a2, a1
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

// Convert signed 64-bit integer to single-precision float
decl_func_with_section floatdisf
	// Convert to sign-magnitude (sign in a5)
	srai a5, a1, 31
	bgez a5, 1f
	seqz t0, a0
	neg a0, a0
	not a1, a1
	add a1, a1, t0
1:
	// Perform unsigned conversion, then re-apply sign
	mv t0, ra
	jal XH3SFX_FUNCNAME(floatundisf)
	bgez a5, 1f
	binvi a0, a0, 31
1:
	jr t0

// Convert unsigned 64-bit integer to single-precision float
decl_func_with_section floatundisf
	beqz a1, __floatundisf_small
	h3.feadju3 a2, a1
	h3.ssrlsticky a1, a1, a2
	addi a2, a2, 32
	h3.ssrlsticky a0, a0, a2
	or a1, a1, a0
	addi a2, a2, 127 + 29
	h3.fpackrq3.s a0, a1, a2
	ret
__floatundisf_small:
	// This is really the same thing as floatunsisf, but it's small, so put a
	// copy in the same section to avoid branch relaxation on the beqz
	h3.feadju3 a1, a0
	h3.ssrlsticky a0, a0, a1
	addi a1, a1, 127 + 29
	h3.fpackrq3.s a0, a0, a1
	ret

#endif

// ----------------------------------------------------------------------------
// Conversions: f16 <-> i32, u32

#if !defined(XH3SFX_FEAT_H2I_I2H) || XH3SFX_FEAT_H2I_I2H
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
#endif

// ----------------------------------------------------------------------------
// i64 and u64

// Yes it's floating point, the point just floats in one place
#if !defined(XH3SFX_FEAT_LONGSHIFT) || XH3SFX_FEAT_LONGSHIFT
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
#endif

// ----------------------------------------------------------------------------
// Add, subtract and multiply (f64)

// Double on RV32E? Here's a nickel, kid. Go buy yourself a real computer.
#ifndef __riscv_i
#if defined(XH3SFX_FEAT_ADDD) && XH3SFX_FEAT_ADDD
#error "Requested feature XH3SFX_FEAT_ADDD is incompatible with RVE"
#elif !defined(XH3SFX_FEAT_ADDD)
#define XH3SFX_FEAT_ADDD 0
#endif
#if defined(XH3SFX_FEAT_MULD) && XH3SFX_FEAT_MULD
#error "Requested feature XH3SFX_FEAT_MULD is incompatible with RVE"
#elif !defined(XH3SFX_FEAT_MULD)
#define XH3SFX_FEAT_MULD 0
#endif
#endif // !__riscv_i

// Double-precision add
#if !defined(XH3SFX_FEAT_ADDD) || XH3SFX_FEAT_ADDD
decl_func_with_section subdf3
	binvi a3, a3, 31
decl_func adddf3
	// Extract exponents
	slli t4, a1, 1
	srli t4, t4, 21
	slli t5, a3, 1
	srli t5, t5, 21
	// Divert special-case exponents from main path; t6 is useful again later
	li t6, 0x7ff
	beqz t4, __adddf_return_y_flushed
	beqz t5, __adddf_return_x
	beq t4, t6, __adddf_x_nan_inf
	beq t5, t6, __adddf_y_nan_inf

	// a1:a0 is packed x
	// a3:a2 is packed y
	// a4-a7, t0-t3 are scratch (a4, a5 preferred for code size)
	// t4, t5 are exp.
	// t6 is preserved biased emax

	// el >= er.
.macro adddf_core ll, lh, rl, rh, el, er, l_is_x
	// Exponent difference may be out of h3.* shift range, so need a branch.
	// Since we already have the branch, also use it as early-out for addends
	// too small to change the result.
	sub \er, \el, \er
	li a4, 54
.if \l_is_x
	bgeu \er, a4, __adddf_return_x
.else
	bgeu \er, a4, __adddf_return_y
.endif
	// Preserve: t2[31] is lhs sign, t3[31] is xor of signs
	mv t2, \lh
	xor t3, \lh, \rh
	// No longer need to preserve packed x/y. Extract lhs in-place as U9.55
	// (need three extra fractional bits for rounding)
	slli \lh, \lh, 12
	srli \lh, \lh, 9
	bseti \lh, \lh, 23
	srli a4, \ll, 29
	add \lh, \lh, a4
	slli \ll, \ll, 3
	// Extract rhs significand as U9.55 (note: it might seem cheaper to
	// extract as U12.52 to avoid shifting the low bits, but this would make
	// the alignment shift bidirectional, which has additional cost at 64-bit.)
	slli \rh, \rh, 12
	srli \rh, \rh, 9
	bseti \rh, \rh, 23
	srli a4, \rl, 29
	add \rh, \rh, a4
	slli \rl, \rl, 3
	// Shift rhs by (non-negative) exponent difference
	addi t0, \er, -32
	h3.ssrasticky a4, \rh, t0
	h3.ssrlsticky \rl, \rl, \er
	h3.ssra \rh, \rh, \er
	or \rl, \rl, a4
	// Subtract lhs - rhs if signs different. Result in a5:a4
	bgez t3, 1f
	sub a5, \lh, \rh
	sltu \rh, \ll, \rl
	sub a5, a5, \rh
	sub a4, \ll, \rl
	j 2f
.p2align 2
1:
	// Add lhs + rhs if signs same. Result in a5:a4
	add a4, \ll, \rl
	sltu \ll, a4, \ll
	add a5, \lh, \rh
.option push
.option norvc // (maintain alignment of 2f without NOP)
	add a5, a5, \ll
.option pop
2:
	// Calculate final sign as XOR of sign of lhs with sign of sum/difference.
	xor t3, t2, a5
	// Split sign/magnitude of result
	bgez a5, 1f
	seqz t1, a4
	neg a4, a4
	not a5, a5
	add a5, a5, t1
1:
	// Renormalise as U1.63; case where a5 is all-zero is
	// non-fallthrough as this amount of cancellation is uncommon. U1 makes
	// it cheap to detect exponent increase on rounding.
	beqz a5, 3f
	clz t0, a5
4:
	// This shift is always to-left due to the change from U9 to U1; this
	// ensures it is exact and avoids calculating the H->L shift contribution.
	addi t1, t0, -32
	h3.ssll t1, a4, t1
	h3.ssll a5, a5, t0
	h3.ssll a4, a4, t0
	or a5, a5, t1
	// Calculate new exponent
	sub \el, \el, t0
	addi \el, \el, 8
	// Calculate rounding bias: U1.63 => 11 excess fractional bits.
	li t1, 0x3ff
	bexti t0, a4, 11
	add t1, t1, t0
	// Add rounding bias. Rounded result is lh:ll
	add \ll, a4, t1
	sltu a4, \ll, a4
	add \lh, a5, a4
	// Check for exponent increase due to rounding
	bgez \lh, 5f
6:
	// Check for exponent saturation; t6 = biased emax preserved since start
	bgeu \el, t6, 7f
	beqz \el, 7f
	// Pack normal result
	srli t3, t3, 31
	slli t3, t3, 11
	add t3, t3, \el
	slli t3, t3, 20 // {sign, exp, 20'd0}

	srli t2, \ll, 11
	slli t1, \lh, 21
	or a0, t1, t2

	slli \lh, \lh, 1
	srli \lh, \lh, 12
	or a1, t3, \lh
	ret

	// Special cases follow.
3:
	// Renormalisation case for upper word all-zeroes after absl(). If lower
	// word is also all-zeroes, this is an exact cancellation. Prioritise the
	// speed of non-exact cancellation.
	clz t0, a4
	addi t0, t0, 32
	bnez a4, 4b
	// Return +0 for exact cancellation
	li a0, 0
	li a1, 0
	ret
5:
	// Handle exponent increase due to rounding
	addi \el, \el, 1
	slli t0, \lh, 31
	srli \lh, \lh, 1
	srli \ll, \ll, 1
	add \er, \er, t0
	j 6b
7:
	// Handle exponent saturation
	li a0, 0
	srli t3, t3, 31
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
.endm

	bltu t4, t5, __adddf_ye_gt_xe
__adddf_xe_ge_ye:
	adddf_core a0, a1, a2, a3, t4, t5, 1
__adddf_ye_gt_xe:
	adddf_core a2, a3, a0, a1, t5, t4, 0

__adddf_x_nan_inf:
	// x is nan -> propagate it
	bnez a0, __adddf_return_x
	slli t3, a1, 12
	bnez t3, __adddf_return_x
__adddf_x_inf:
	// We know that x is +-inf, and y is nonzero. If y is normal, propagate inf.
	bne  t5, t6, __adddf_return_x
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
	bne  t4, t6, __adddf_return_y
	// x is nan or inf. If nan, propagate x.
	bnez a0, __adddf_return_x
	slli t3, a1, 12
	bnez t3, __adddf_return_x
	j __adddf_both_inf

__adddf_return_y_flushed:
	bnez t5, 1f
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
#endif

// Double-precision multiply
#if !defined(XH3SFX_FEAT_MULD) || XH3SFX_FEAT_MULD
decl_func_with_section muldf3
	// Extract exponents
	slli t4, a1, 1
	srli t4, t4, 21
	slli t5, a3, 1
	srli t5, t5, 21
	// Divert special-case exponents from main path; t6 is useful again later
	li t6, 0x7ff
	beqz t4, __muldf_x_0
	beqz t5, __muldf_y_0
	beq t4, t6, __muldf_x_nan_inf
	beq t5, t6, __muldf_y_nan_inf
	// Approximate final exponent:
	add t4, t4, t5
	addi t4, t4, -1023
	// Final sign is XOR of input signs:
	xor t5, a1, a3
	// Extract significands as U12.52
	slli a1, a1, 12
	srli a1, a1, 12
	bseti a1, a1, 20
	slli a3, a3, 12
	srli a3, a3, 12
	bseti a3, a3, 20
	// Compute exact product before rounding: 53x53->106-bit. Assuming mulhu
	// is not drastically slower than mul, we can use 32x32->64-bit partial
	// product multiplies, so there is no benefit to going smaller than a
	// full 64x64->128-bit product. Product expansion is:
	//
	// 	* P.0 = (X.0 * Y.0).0
	// 	* P.1 = (X.0 * Y.1).0 + (X.1 * Y.0).0 + (X.0 * Y.0).1
	// 	* P.2 = (X.1 * Y.1).0 + (X.1 * Y.0).1 + (X.0 * Y.1).1 + P.1 carry-out
	// 	* P.3 = (X.1 * Y.1).1 + P.2 carry-out

	// P.1 = (X.0 * Y.1).0 + (X.1 * Y.0).0 + (X.0 * Y.0).1
	mul t0, a0, a3
	mul t1, a1, a2
	mulhu t2, a0, a2
	add t1, t0, t1
	sltu t0, t1, t0
	add a7, t1, t2
	sltu t1, a7, t1
	add a6, t0, t1
	// Now: a7 = P.1, a6 = carry-out

	// P.2 = (X.1 * Y.1).0 + (X.1 * Y.0).1 + (X.0 * Y.1).1 + P.1 carry-out
	mul t0, a1, a3
	mulhu t1, a1, a2
	mulhu t2, a0, a3
	add t1, t0, t1
	sltu t0, t1, t0
	add t2, t1, t2
	sltu t1, t2, t1
	add a5, a6, t2
	sltu a6, a5, a6
	add a6, a6, t0
	add a6, a6, t1
	// Now: a7 = P.1, a5 = P.2, a6 = carry-out

	// P.3 = (X.1 * Y.1).1 + P.2 carry-out
	mulhu a4, a1, a3
	add a4, a4, a6
	// P.0 = (X.0 * Y.0).0
	mul a6, a0, a2
	// Now:
	// * Shape of P: U24.104
	// * Range of P: 1 <= P < 4
	// * a4 = P.3
	// * a5 = P.2
	// * a7 = P.1
	// * a6 = P.0

	// Change shape to U4.60 with sticky bits collected in LSB
	slli a4, a4, 20
	srli t0, a5, 12
	or a4, a4, t0
	slli a5, a5, 20
	li t1, 12
	h3.ssrlsticky t0, a7, t1
	or a5, a5, t0
	snez a6, a6
	or a5, a5, a6
	// Now: a4:a5 is U4.60

	// Reduce range to 1 <= P < 2 prior to rounding
	bexti t0, a4, 29
	beqz t0, 1f
	li t0, 1
	h3.ssrlsticky a5, a5, t0
	slli t0, a4, 31
	or a5, a5, t0
	srli a4, a4, 1
	addi t4, t4, 1
1:
	// 8 excess fractional bits. Rounding bias is 2^7 - 1
	bexti t0, a5, 8
	addi t0, t0, 127
	add a3, a5, t0
	sltu a5, a3, a5
	add a4, a4, a5
	// Now: rounded U4.60 in a4:a3.
	// Check exponent increase due to rounding (uncommon)
	bexti t0, a4, 29
	bnez t0, 2f
3:
	// Check exponent saturation
	bgeu t4, t6, 4f
	beqz t4, 4f
	// Pack normal result
	srli a3, a3, 8
	slli t0, a4, 24
	or a0, a3, t0
	srli a4, a4, 8
	slli a4, a4, 12
	add a4, a4, t4
	srli t5, t5, 31
	slli t5, t5, 11
	add a4, a4, t5
	rori a1, a4, 12
	ret
2:
	// Handle exponent increase due to rounding
	li t0, 1
	h3.ssrlsticky a3, a3, t0
	slli t0, a4, 31
	or a3, a3, t0
	srli a4, a4, 1
	addi t4, t4, 1
	j 3b
4:
	// Handle subnormal, underflow or overflow: result is signed infinity for
	// positive exponent, else signed zero.
	li a0, 0
	srli a1, t5, 31
	slli a1, a1, 31
	blez t4, 1f
	lui a2, 0x7ff00
	or a1, a1, a2
1:
	ret

__muldf_x_0:
	bne t5, t6, __muldf_return_flushed
	bnez a2, __muldf_propagate_nan_y
	slli t0, a3, 12
	beqz t0, __muldf_generate_nan
__muldf_propagate_nan_y:
	mv a0, a2
	mv a1, a3
	ret

__muldf_y_0:
	bne t4, t6, __muldf_return_flushed
	bnez a0, __muldf_propagate_nan_x
	slli t0, a1, 12
	beqz t0, __muldf_generate_nan
__muldf_propagate_nan_x:
	ret

__muldf_generate_nan:
	li a0, -1
	li a1, -1
	ret

__muldf_return_flushed:
	xor a1, a1, a3
	srli a1, a1, 31
	slli a1, a1, 31
	li a0, 0
	ret

__muldf_x_nan_inf:
	// Neither x nor y is zero. Therefore we can only propagate NaNs, not
	// generate them. Propagate x if NaN:
	bnez a0, __muldf_propagate_nan_x
	slli t0, a1, 12
	bnez t0, __muldf_propagate_nan_x
	// Propagate y if NaN, else return infinity
	bne t5, t6, __muldf_return_inf
	bnez a2, __muldf_propagate_nan_y
	slli t0, a3, 12
	bnez t0, __muldf_propagate_nan_y
	j __muldf_return_inf

__muldf_y_nan_inf:
	// x is normal, y is nan or infinity. Propagate y if NaN:
	bnez a2, __muldf_propagate_nan_y
	slli t0, a1, 12
	bnez t0, __muldf_propagate_nan_y
	// fall through

__muldf_return_inf:
	xor a1, a1, a3
	srli a1, a1, 31
	slli a1, a1, 11
	addi a1, a1, 0x7ff
	slli a1, a1, 20
	li a0, 0
	ret
#endif
