#include "xh3sfx_intrinsics.h"
#include "xh3bextm_intrinsics.h"

// Soft float library for Xh3sfx

#define funcname(name) __ ## name
#define funcsection(name) .section .text. ## name

// ----------------------------------------------------------------------------
// Single-precision add and subtract

funcsection(addsf3)
.global funcname(subsf3)
.p2align 2
funcname(subsf3):
    binvi a1, a1, 31
.global funcname(addsf3)
funcname(addsf3):
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

// ----------------------------------------------------------------------------
// Single-precision multiply

funcsection(mulsf3)
.global funcname(mulsf3)
.p2align 2
funcname(mulsf3):
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

// ----------------------------------------------------------------------------
// Other single-precision arithmetic

funcsection(negsf2)
.global funcname(negsf2)
.p2align 2
funcname(negsf2):
    binvi a0, a0, 31
    ret

// Concatenation of exponent and significand is correctly ordered with respect
// to magnitude. This is a 31-bit value; convert sign-magnitude to two's
// complement to get a fully correctly ordered 32-bit integer. This doesn't
// handle NaNs gracefully but, quote libgcc docs, "you should not rely on
// this; if NaN is a possibility, use one of the higher-level comparison
// functions"
funcsection(fcmpsf2)
.global funcname(fcmpsf2)
.p2align 2
funcname(fcmpsf2):
    bclri a2, a0, 31
    bclri a3, a1, 31
    h3.xorsign a2, a2, a0
    h3.xorsign a3, a3, a1
    blt a2, a3, __fcmpsf2_lt
    bgt a2, a3, __fcmpsf2_gt
    li a0, 0
    ret
__fcmpsf2_lt:
    li a0, -1
    ret
__fcmpsf2_gt:
    li a0, 1
    ret

// ----------------------------------------------------------------------------
// Conversions

// Convert single-precision to half-precision
funcsection(truncsfhf2)
.global funcname(truncsfhf2)
.p2align 2
funcname(truncsfhf2):
	h3.funpackq3.s a1, a0
	h3.bextmi a2, a0, 23, 8
    addi t0, a2, -255
    beqz t0, 2f
1:
	addi a2, a2, -127 + 15
	h3.fpackrq3.h a0, a1, a2
	ret
2:
    // Return canonical NaN on NaN input.
    slli a0, a0, 9
    beqz a0, 1b
    li a0, -1
    ret

// Convert half-precision to single-precision
funcsection(extendhfsf2)
.global funcname(extendhfsf2)
.p2align 2
funcname(extendhfsf2):
    h3.funpackq3.h a1, a0
    h3.bextmi a2, a0, 10, 5
    addi t0, a2, -31
    beqz t0, 2f
1:
    addi a2, a2, -15 + 127
    h3.fpackrq3.s a0, a1, a2
    ret
2:
    slli a0, a0, 22
    beqz a0, 1b
    li a0, -1
    ret


// Convert single-precision to signed integer
funcsection(fixsfsi)
.global funcname(fixsfsi)
.p2align 2
funcname(fixsfsi):
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
	li a1, 1 << 31
    srai a0, a0, 31
    xor a0, a0, a1
	ret

// Convert single-precision to unsigned integer
funcsection(fixunsfsi)
.global funcname(fixunsfsi)
.p2align 2
funcname(fixunsfsi):
    bltz a0, __fixunsfi_neg
    h3.bextmi a1, a0, 23, 8
    li t0, 127 + 31
    bgtu a1, t0, __fixunsfsi_large_exponent
    h3.funpackq3.s a0, a0
    addi a1, a1, -127 - 29
    h3.ssll a2, a2, a1
    ret
__fixunsfsi_large_exponent:
    li a0, -1
    ret
__fixunsfi_neg:
    li a0, 0
    ret

// Convert signed integer to single-precision
funcsection(floatsisf)
.global funcname(floatsisf)
funcname(floatsisf):
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
funcsection(floatunsisf)
.global funcname(floatunsisf)
funcname(floatunsisf):
	beqz a0, 1f
	// Normalise to Q3.29
    h3.feadju3 a1, a0
	h3.ssrlsticky a0, a0, a1
	// Calculate exponent
	addi a1, a1, 127 - 29
	// Round and pack
	h3.fpackrq3.s a0, a0, a1
1:
	ret
