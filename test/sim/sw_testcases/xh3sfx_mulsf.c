#include "tb_cxxrtl_io.h"

// Test for Xh3sfx single-precision multiply routine

// ebreak is easier to find in waves.
#if 1
#define check_equal(a, b) tb_assert((a) == (b), "Line %d: " #a " == " #b "\nGot: %08x != %08x\n", __LINE__, (a), (b))
#else
#define check_equal(a, b) if ((a) != (b)) {asm ("ebreak");}
#endif

uint32_t __mulsf3(uint32_t lhs, uint32_t rhs);

int main() {
    // 1 * 1 = 1
    check_equal(__mulsf3(0x3f800000u, 0x3f800000u), 0x3f800000u);
    // 1 * -1 = -1
    check_equal(__mulsf3(0x3f800000u, 0xbf800000u), 0xbf800000u);
    // -1 * 1 = -1
    check_equal(__mulsf3(0xbf800000u, 0x3f800000u), 0xbf800000u);
    // -1 * -1 = 1
    check_equal(__mulsf3(0xbf800000u, 0xbf800000u), 0x3f800000u);
    // -0 * 0 = -0
    check_equal(__mulsf3(0x80000000u, 0x00000000u), 0x80000000u);
    // 0 * -0 = - 0
    check_equal(__mulsf3(0x00000000u, 0x80000000u), 0x80000000u);    
    // 1 * 2 = 2
    check_equal(__mulsf3(0x3f800000u, 0x40000000u), 0x40000000u);
    // 2 * 1 = 2
    check_equal(__mulsf3(0x40000000u, 0x3f800000u), 0x40000000u);
    // inf * inf = inf
    check_equal(__mulsf3(0x7f800000u, 0x7f800000u), 0x7f800000u);
    // inf * -inf = -inf
    check_equal(__mulsf3(0x7f800000u, 0xff800000u), 0xff800000u);
    // inf * 0 = nan
    check_equal(__mulsf3(0x7f800000u, 0x00000000u), 0xffffffffu);
    // 0 * inf = nan
    check_equal(__mulsf3(0x00000000u, 0x7f800000u), 0xffffffffu);
    // 1 * -inf = -inf
    check_equal(__mulsf3(0x3f800000u, 0xff800000u), 0xff800000u);
    // -inf * 1 = -inf
    check_equal(__mulsf3(0xff800000u, 0x3f800000u), 0xff800000u);
    // -1 * inf = -inf
    check_equal(__mulsf3(0xbf800000u, 0x7f800000u), 0xff800000u);
    // inf * -1 = -inf
    check_equal(__mulsf3(0x7f800000u, 0xbf800000u), 0xff800000u);
    // 1 * nonzero subnormal = exactly 0
    check_equal(__mulsf3(0x3f800000u, 0x007fffffu), 0x00000000u);
    // nonzero subnormal * -1 = exactly -0
    check_equal(__mulsf3(0x007fffffu, 0xbf800000u), 0x80000000u);
    // nan * 0 = same nan
    check_equal(__mulsf3(0xffff1234u, 0x00000000u), 0xffff1234u);
    // 0 * nan = same nan
    check_equal(__mulsf3(0x00000000u, 0xffff1234u), 0xffff1234u);
    // nan * 1 = same nan
    check_equal(__mulsf3(0xffff1234u, 0x3f800000u), 0xffff1234u);
    // 1 * nan = same nan
    check_equal(__mulsf3(0x3f800000u, 0xffff1234u), 0xffff1234u);
    // nan * inf = same nan
    check_equal(__mulsf3(0xffff1234u, 0x7f800000u), 0xffff1234u);
    // inf * nan = same nan
    check_equal(__mulsf3(0x7f800000u, 0xffff1234u), 0xffff1234u);
    // (2 - 0.5 ulp) x (2 - 0.5 ulp) = 4 - 0.5 ulp
    check_equal(__mulsf3(0x3fffffffu, 0x3fffffffu), 0x407ffffeu);
    // (2 - 0.5 ulp) x (1 + 1 ulp) = 2 exactly
    check_equal(__mulsf3(0xbfffffffu, 0x3f800001u), 0xc0000000u);
    // 1.666... * 1.333.. = 2.222...
    check_equal(__mulsf3(0x3fd55555u, 0x3faaaaaau), 0x400e38e3u);
    // 1.25 x 2^-63 x 1.25 x 2^-64 = 0
    // (normal inputs with subnormal output, and we claim to be FTZ)
    check_equal(__mulsf3(0x20200000u, 0x1fa00000u), 0x00000000u);
    // 1.333333 (rounded down) x 1.5 = 2 - 1 ulp
    check_equal(__mulsf3(0x3faaaaaau, 0x3fc00000u), 0x3fffffffu);
    // 1.333333 (rounded down) x (1.5 + 1 ulp) = 2 exactly
    check_equal(__mulsf3(0x3faaaaaau, 0x3fc00001u), 0x40000000u);
    // (1.333333 (rounded down) + 1 ulp) x 1.5 = 2 exactly
    check_equal(__mulsf3(0x3faaaaabu, 0x3fc00000u), 0x40000000u);
    // (1.25 - 1 ulp) x (0.8 + 1 ulp) = 1 exactly (exponent increases after rounding)
    check_equal(__mulsf3(0x3f9fffffu, 0x3f4cccceu), 0x3f800000u);
    // as above, but overflow on exponent increase -> +inf
    check_equal(__mulsf3(0x3f9fffffu, 0x7f4cccceu), 0x7f800000u);
    // subtract 1 ulp from rhs -> largest normal
    check_equal(__mulsf3(0x3f9fffffu, 0x7f4ccccdu), 0x7f7fffffu);
    // Round up from subnormal with tricky sign correction:
    check_equal(__mulsf3(0x0ffffffeu, 0x30000001u), 0x00800000u);
    check_equal(__mulsf3(0x0ffffffeu, 0xb0000001u), 0x80800000u);
    check_equal(__mulsf3(0x8ffffffeu, 0x30000001u), 0x80800000u);
    check_equal(__mulsf3(0x8ffffffeu, 0xb0000001u), 0x00800000u);
	return 0;
}