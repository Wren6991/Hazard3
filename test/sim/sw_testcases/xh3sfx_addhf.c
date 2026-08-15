#include "tb_cxxrtl_io.h"

// Test for Xh3sfx half-precision add routine

// ebreak is easier to find in waves.
#if 1
#define check_equal(a, b) tb_assert((a) == (b), "Line %d: " #a " == " #b "\nGot: %08x != %08x\n", __LINE__, (a), (b))
#else
#define check_equal(a, b) if ((a) != (b)) {asm ("ebreak");}
#endif

uint32_t __h3_addhf3(uint32_t lhs, uint32_t rhs);

int main() {

    // f16

    // +0 + +0 = +0
    check_equal(__h3_addhf3(0x0000u, 0x0000u), 0x00000000u);
    // -0 + -0 = -0
    check_equal(__h3_addhf3(0x8000u, 0x8000u), 0xffff8000u);
    // +0 + -0 = +0 (RNE rule: opposite-sign exact-zero result is +0)
    check_equal(__h3_addhf3(0x0000u, 0x8000u), 0x00000000u);
    // -0 + +0 = +0
    check_equal(__h3_addhf3(0x8000u, 0x0000u), 0x00000000u);
    // 1 + +0 = 1
    check_equal(__h3_addhf3(0x3c00u, 0x0000u), 0x00003c00u);
    // +0 + 1 = 1
    check_equal(__h3_addhf3(0x0000u, 0x3c00u), 0x00003c00u);
    // -1 + +0 = -1 (zero identity preserves sign of non-zero operand)
    check_equal(__h3_addhf3(0xbc00u, 0x0000u), 0xffffbc00u);
    // +0 + -1 = -1
    check_equal(__h3_addhf3(0x0000u, 0xbc00u), 0xffffbc00u);
    // 1 + 1 = 2
    check_equal(__h3_addhf3(0x3c00u, 0x3c00u), 0x00004000u);
    // 2 + 1 = 3
    check_equal(__h3_addhf3(0x4000u, 0x3c00u), 0x00004200u);
    // 1 + 2 = 3
    check_equal(__h3_addhf3(0x3c00u, 0x4000u), 0x00004200u);
    // 1 + -1 = +0 (exact cancellation)
    check_equal(__h3_addhf3(0x3c00u, 0xbc00u), 0x00000000u);
    // -1 + 1 = +0 (exact cancellation)
    check_equal(__h3_addhf3(0xbc00u, 0x3c00u), 0x00000000u);
    // 1 + <<1 ulp = 1
    check_equal(__h3_addhf3(0x3c00u, 0x0400u), 0x00003c00u);
    // <<1 ulp + 1 = 1
    check_equal(__h3_addhf3(0x0400u, 0x3c00u), 0x00003c00u);
    // -1 + 1.25 = 0.25
    check_equal(__h3_addhf3(0xbc00u, 0x3d00u), 0x00003400u);
    // -1.5 + 1.25 = -0.25
    check_equal(__h3_addhf3(0xbe00u, 0x3d00u), 0xffffb400u);
    // max normal + 0.5 ulp = +inf
    check_equal(__h3_addhf3(0x7bffu, 0x4c00u), 0x00007c00u);
    // max normal + max normal = +inf
    check_equal(__h3_addhf3(0x7bffu, 0x7bffu), 0x00007c00u);
    // min normal - 0.5 ulp = -inf
    check_equal(__h3_addhf3(0xfbffu, 0xcc00u), 0xfffffc00u);
    // min normal + min_normal = -inf
    check_equal(__h3_addhf3(0xfbffu, 0xfbffu), 0xfffffc00u);
    // max normal + 0.499... ulp = max normal
    check_equal(__h3_addhf3(0x7bffu, 0x4bffu), 0x00007bffu);
    // min normal - 0.499... ulp = min normal
    check_equal(__h3_addhf3(0xfbffu, 0xcbffu), 0xfffffbffu);
    // nan + 0 = same nan
    check_equal(__h3_addhf3(0x7f12u, 0x0000u), 0x00007f12u);
    // 0 + nan = same nan
    check_equal(__h3_addhf3(0x0000u, 0x7f12u), 0x00007f12u);
    // nan + 1 = same nan
    check_equal(__h3_addhf3(0x7f12u, 0x3c00u), 0x00007f12u);
    // 1 + nan = same nan
    check_equal(__h3_addhf3(0x3c00u, 0x7f12u), 0x00007f12u);
    // nan + inf = same nan
    check_equal(__h3_addhf3(0x7f12u, 0x7c00u), 0x00007f12u);
    // inf + nan = same nan
    check_equal(__h3_addhf3(0x7c00u, 0x7f12u), 0x00007f12u);
    // // nan + different nan = first nan's payload propagates (implementation detail of this library)
    check_equal(__h3_addhf3(0x7f12u, 0x7f34u), 0x00007f12u);
    // inf + inf = inf
    check_equal(__h3_addhf3(0x7c00u, 0x7c00u), 0x00007c00u);
    // -inf + -inf = -inf
    check_equal(__h3_addhf3(0xfc00u, 0xfc00u), 0xfffffc00u);
    // inf + -inf = nan (all-ones is our canonical cheap nan)
    check_equal(__h3_addhf3(0x7c00u, 0xfc00u), 0xffffffffu);
    // -inf + inf = nan
    check_equal(__h3_addhf3(0xfc00u, 0x7c00u), 0xffffffffu);
    // inf + 1 = inf (infinity absorbs finite)
    check_equal(__h3_addhf3(0x7c00u, 0x3c00u), 0x00007c00u);
    // 1 + inf = inf
    check_equal(__h3_addhf3(0x3c00u, 0x7c00u), 0x00007c00u);
    // -inf + 1 = -inf
    check_equal(__h3_addhf3(0xfc00u, 0x3c00u), 0xfffffc00u);
    // 1 + -inf = -inf
    check_equal(__h3_addhf3(0x3c00u, 0xfc00u), 0xfffffc00u);
    // inf + 0 = inf
    check_equal(__h3_addhf3(0x7c00u, 0x0000u), 0x00007c00u);
    // 0 + inf = inf
    check_equal(__h3_addhf3(0x0000u, 0x7c00u), 0x00007c00u);
    // subnormal + subnormal = exactly 0
    check_equal(__h3_addhf3(0x03ffu, 0x03ffu), 0x00000000u);
    // -subnormal + -subnormal = exactly -0
    check_equal(__h3_addhf3(0x83ffu, 0x83ffu), 0xffff8000u);
    // Even + 0.5 ulp: tie, round down
    check_equal(__h3_addhf3(0x3c02u, 0x1000u), 0x00003c02u);
    // Even + (0.5-eps) ulp: not a tie, round down
    check_equal(__h3_addhf3(0x3c02u, 0x0fffu), 0x00003c02u);
    // Even + (0.5+eps) ulp: not a tie, round up
    check_equal(__h3_addhf3(0x3c02u, 0x1001u), 0x00003c03u);
    // Even - 0.5 ulp: round up
    check_equal(__h3_addhf3(0x3c02u, 0x9000u), 0x00003c02u);
    // Odd + 0.5 ulp: tie, round up
    check_equal(__h3_addhf3(0x3c01u, 0x1000u), 0x00003c02u);
    // Odd + (0.5-eps) ulp: not a tie, round down
    check_equal(__h3_addhf3(0x3c01u, 0x0fffu), 0x00003c01u);
    // Odd + (0.5+eps) ulp: not a tie, round up
    check_equal(__h3_addhf3(0x3c01u, 0x1001u), 0x00003c02u);
    // Odd - 0.5 ulp: round down
    check_equal(__h3_addhf3(0x3c01u, 0x9000u), 0x00003c00u);
    // 1.111...1 + 0.5 ulp = 2.0 (round-up carry propagates through all significand bits)
    check_equal(__h3_addhf3(0x3fffu, 0x1000u), 0x00004000u);
    // All-zeroes significand - 0.5 ulp: no rounding (exact)
    check_equal(__h3_addhf3(0x3c00u, 0x9000u), 0x00003bffu);
    // Very subnormal difference of normals: flushed to zero
    check_equal(__h3_addhf3(0x1000u, 0x8fffu), 0x00000000u);
    // Difference is 2^(emin+1): not flushed
    check_equal(__h3_addhf3(0x1000u, 0x8e00u), 0x00000800u);
    // Difference is 2^emin: not flushed
    check_equal(__h3_addhf3(0x1000u, 0x8f00u), 0x00000400u);
    // Difference is 2^(emin-1): flushed
    check_equal(__h3_addhf3(0x1000u, 0x8f80u), 0x00000000u);
    // Difference is (2^emin)-eps: flushed
    check_equal(__h3_addhf3(0x1000u, 0x8f01u), 0x00000000u);
    // subnormal + normal = normal (subnormal input flushed to +0)
    check_equal(__h3_addhf3(0x03ffu, 0x3c00u), 0x00003c00u);
    // normal + subnormal = normal
    check_equal(__h3_addhf3(0x3c00u, 0x03ffu), 0x00003c00u);
    // subnormal + (-subnormal) = +0 (both flushed, then +0 + -0 = +0)
    check_equal(__h3_addhf3(0x03ffu, 0x83ffu), 0x00000000u);
    // -subnormal + subnormal = +0
    check_equal(__h3_addhf3(0x83ffu, 0x03ffu), 0x00000000u);
    // -subnormal + -subnormal = -0
    check_equal(__h3_addhf3(0x83ffu, 0x83ffu), 0xffff8000u);

	return 0;
}