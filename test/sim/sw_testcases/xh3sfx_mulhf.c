#include "tb_cxxrtl_io.h"

// Test for Xh3sfx half-precision multiply routine

// ebreak is easier to find in waves.
#if 1
#define check_equal(a, b) tb_assert((a) == (b), "Line %d: " #a " == " #b "\nGot: %08x != %08x\n", __LINE__, (a), (b))
#else
#define check_equal(a, b) if ((a) != (b)) {asm ("ebreak");}
#endif

uint32_t __h3_mulhf3(uint32_t lhs, uint32_t rhs);

int main() {
    // 1 * 1 = 1
    check_equal(__h3_mulhf3(0x3c00u, 0x3c00u), 0x00003c00u);
    // 1 * -1 = -1
    check_equal(__h3_mulhf3(0x3c00u, 0xbc00u), 0xffffbc00u);
    // -1 * 1 = -1
    check_equal(__h3_mulhf3(0xbc00u, 0x3c00u), 0xffffbc00u);
    // -1 * -1 = 1
    check_equal(__h3_mulhf3(0xbc00u, 0xbc00u), 0x00003c00u);
    // -0 * 0 = -0
    check_equal(__h3_mulhf3(0x8000u, 0x0000u), 0xffff8000u);
    // 0 * -0 = - 0
    check_equal(__h3_mulhf3(0x0000u, 0x8000u), 0xffff8000u);
    // +0 * +0 = +0
    check_equal(__h3_mulhf3(0x0000u, 0x0000u), 0x00000000u);
    // -0 * -0 = +0 (sign XOR of two negatives)
    check_equal(__h3_mulhf3(0x8000u, 0x8000u), 0x00000000u);
    // 1 * 2 = 2
    check_equal(__h3_mulhf3(0x3c00u, 0x4000u), 0x00004000u);
    // 2 * 1 = 2
    check_equal(__h3_mulhf3(0x4000u, 0x3c00u), 0x00004000u);
    // inf * inf = inf
    check_equal(__h3_mulhf3(0x7c00u, 0x7c00u), 0x00007c00u);
    // inf * -inf = -inf
    check_equal(__h3_mulhf3(0x7c00u, 0xfc00u), 0xfffffc00u);
    // -inf * inf = -inf
    check_equal(__h3_mulhf3(0xfc00u, 0x7c00u), 0xfffffc00u);
    // -inf * -inf = inf
    check_equal(__h3_mulhf3(0xfc00u, 0xfc00u), 0x00007c00u);
    // inf * 0 = nan
    check_equal(__h3_mulhf3(0x7c00u, 0x0000u), 0xffffffffu);
    // 0 * inf = nan
    check_equal(__h3_mulhf3(0x0000u, 0x7c00u), 0xffffffffu);
    // inf * -0 = nan
    check_equal(__h3_mulhf3(0x7c00u, 0x8000u), 0xffffffffu);
    // -0 * inf = nan
    check_equal(__h3_mulhf3(0x8000u, 0x7c00u), 0xffffffffu);
    // 1 * -inf = -inf
    check_equal(__h3_mulhf3(0x3c00u, 0xfc00u), 0xfffffc00u);
    // -inf * 1 = -inf
    check_equal(__h3_mulhf3(0xfc00u, 0x3c00u), 0xfffffc00u);
    // -1 * inf = -inf
    check_equal(__h3_mulhf3(0xbc00u, 0x7c00u), 0xfffffc00u);
    // inf * -1 = -inf
    check_equal(__h3_mulhf3(0x7c00u, 0xbc00u), 0xfffffc00u);
    // 1 * nonzero subnormal = exactly 0
    check_equal(__h3_mulhf3(0x3c00u, 0x03ffu), 0x00000000u);
    // nonzero subnormal * -1 = exactly -0
    check_equal(__h3_mulhf3(0x03ffu, 0xbc00u), 0xffff8000u);
    // -subnormal * 1 = -0 (negative subnormal flushed to -0)
    check_equal(__h3_mulhf3(0x83ffu, 0x3c00u), 0xffff8000u);
    // -subnormal * -1 = +0 (sign XOR of -0 and -1)
    check_equal(__h3_mulhf3(0x83ffu, 0xbc00u), 0x00000000u);
    // nan * 0 = same nan
    check_equal(__h3_mulhf3(0xfc12u, 0x0000u), 0xfffffc12u);
    // nan * nan = first nan (implementation detail)
    check_equal(__h3_mulhf3(0x7f34u, 0x7f56u), 0x00007f34u);
    // 0 * nan = same nan
    check_equal(__h3_mulhf3(0x0000u, 0xfc12u), 0xfffffc12u);
    // nan * 1 = same nan
    check_equal(__h3_mulhf3(0xfc12u, 0x3c00u), 0xfffffc12u);
    // 1 * nan = same nan
    check_equal(__h3_mulhf3(0x3c00u, 0xfc12u), 0xfffffc12u);
    // nan * inf = same nan
    check_equal(__h3_mulhf3(0xfc12u, 0x7c00u), 0xfffffc12u);
    // inf * nan = same nan
    check_equal(__h3_mulhf3(0x7c00u, 0xfc12u), 0xfffffc12u);
    // (2 - 0.5 ulp) x (2 - 0.5 ulp) = 4 - 1 ulp
    check_equal(__h3_mulhf3(0x3fffu, 0x3fffu), 0x000043feu);
    // -(2 - 0.5 ulp) x (1 + 1 ulp) = 2 exactly
    check_equal(__h3_mulhf3(0xbfffu, 0x3c01u), 0xffffc000u);
    // 1.666... * 1.333.. = 2.222... (rounds up)
    check_equal(__h3_mulhf3(0x3eabu, 0x3d55u), 0x00004072u);
    // 1.25 x 2^-7 x 1.25 x 2^-8 = 0
    // (normal inputs with subnormal output, and we claim to be FTZ)
    check_equal(__h3_mulhf3(0x2100u, 0x1d00u), 0x00000000u);
    // 1.5 x 2^-7 x 1.5 x 2^-8 = 0
    // (normal inputs with barely-normal output; same exponents as previous but product is >2)
    check_equal(__h3_mulhf3(0x2200u, 0x1e00u), 0x00000480u);
    // 1.333333 (rounded down) x 1.5 = 2 exactly
    check_equal(__h3_mulhf3(0x3d55u, 0x3e00u), 0x00004000u);
    // 1.333333 (rounded down) x (1.5 + 1 ulp) = 2 exactly
    check_equal(__h3_mulhf3(0x3d55u, 0x3e01u), 0x00004000u);
    // (1.333333 (rounded down) + 1 ulp) x 1.5 = 2 exactly
    check_equal(__h3_mulhf3(0x3d56u, 0x3e00u), 0x00004000u);
    // (1.333333 (rounded down) + 1 ulp) x (1.5 + 1 ulp) = 2 + 1 ulp
    check_equal(__h3_mulhf3(0x3d56u, 0x3e01u), 0x00004001u);
    // 1.0010010010 * 1.1100000000 = 10.0 exactly (exponent increase after rounding)
    check_equal(__h3_mulhf3(0x3c92u, 0x3f00u), 0x00004000u);
    // as above, but overflow on exponent increase -> +inf
    check_equal(__h3_mulhf3(0x7892u, 0x3f00u), 0x00007c00u);
    check_equal(__h3_mulhf3(0xf892u, 0x3f00u), 0xfffffc00u);
    // subtract 1 ulp from rhs -> largest normal - 1 ulp
    check_equal(__h3_mulhf3(0x7892u, 0x3effu), 0x00007bfeu);
    // Round up from subnormal (all signs), no flush:
    // product here is 1.1111111111:10... so rounds up even with unbounded exponent.
    check_equal(__h3_mulhf3(0x1f00u, 0x2092u), 0x00000400u);
    check_equal(__h3_mulhf3(0x1f00u, 0xa092u), 0xffff8400u);
    check_equal(__h3_mulhf3(0x9f00u, 0x2092u), 0xffff8400u);
    check_equal(__h3_mulhf3(0x9f00u, 0xa092u), 0x00000400u);
    // (1 + 2^-5)^2: exact tie, even LSB, rounds down
    check_equal(__h3_mulhf3(0x3c10u, 0x3c10u), 0x00003c20u);
    // (1 + 2^-10) * 1.5: exact tie, odd LSB, rounds up
    check_equal(__h3_mulhf3(0x3c01u, 0x3e00u), 0x00003e02u);
    // (1 + 2^-23) * (1.5 + 2^-23): even LSB, guard=1, sticky set only at
    // lowest product bit, rounds up
    check_equal(__h3_mulhf3(0x3c01u, 0x3e01u), 0x00003e03u);
    // Half-way between largest subnormal and smallest normal: does not round
    // when exponent is unlimited as there are no sub-fractional 1s.
    check_equal(__h3_mulhf3(0x07ffu, 0x3800u), 0x00000000u);
    // Subnormal result that rounds up to normal even when rounded with
    // unlimited exponent:
    check_equal(__h3_mulhf3(0x07feu, 0x3801u), 0x00000400u);

	return 0;
}