#include "tb_cxxrtl_io.h"

// Test for Xh3sfx single-precision add routine

// ebreak is easier to find in waves.
#if 1
#define check_equal(a, b) tb_assert((a) == (b), "Line %d: " #a " == " #b "\nGot: %08x != %08x\n", __LINE__, (a), (b))
#else
#define check_equal(a, b) if ((a) != (b)) {asm ("ebreak");}
#endif

uint32_t __addsf3(uint32_t lhs, uint32_t rhs);

int main() {
    // 1 + 1 = 2
    check_equal(__addsf3(0x3f800000u, 0x3f800000u), 0x40000000u);
    // 2 + 1 = 3
    check_equal(__addsf3(0x40000000u, 0x3f800000u), 0x40400000u);
    // 1 + 2 = 3
    check_equal(__addsf3(0x3f800000u, 0x40000000u), 0x40400000u);
    // 1 + -1 = +0 (exact cancellation)
    check_equal(__addsf3(0x3f800000u, 0xbf800000u), 0x00000000u);
    // -1 + 1 = +0 (exact cancellation)
    check_equal(__addsf3(0xbf800000u, 0x3f800000u), 0x00000000u);
    // 1 + <<1 ulp = 1
    check_equal(__addsf3(0x3f800000u, 0x2f800000u), 0x3f800000u);
    // <<1 ulp + 1 = 1
    check_equal(__addsf3(0x2f800000u, 0x3f800000u), 0x3f800000u);
    // -1 + 1.25 = 0.25
    check_equal(__addsf3(0xbf800000u, 0x3fa00000u), 0x3e800000u);
    // max normal + 0.5 ulp = +inf
    check_equal(__addsf3(0x7f7fffffu, 0x73000000u), 0x7f800000u);
    // max normal + max normal = +inf
    check_equal(__addsf3(0x7f7fffffu, 0x7f7fffffu), 0x7f800000u);
    // min normal - 0.5 ulp = -inf
    check_equal(__addsf3(0xff7fffffu, 0xf3000000u), 0xff800000u);
    // min normal + min_normal = -inf
    check_equal(__addsf3(0xff7fffffu, 0xff7fffffu), 0xff800000u);
    // max normal + 0.499... ulp = max normal
    check_equal(__addsf3(0x7f7fffffu, 0x72ffffffu), 0x7f7fffffu);
    // min normal - 0.499... ulp = min normal
    check_equal(__addsf3(0xff7fffffu, 0xf2ffffffu), 0xff7fffffu);
    // nan + 0 = same nan
    check_equal(__addsf3(0xffff1234u, 0x00000000u), 0xffff1234u);
    // 0 + nan = same nan
    check_equal(__addsf3(0x00000000u, 0xffff1234u), 0xffff1234u);
    // nan + 1 = same nan
    check_equal(__addsf3(0xffff1234u, 0x3f800000u), 0xffff1234u);
    // 1 + nan = same nan
    check_equal(__addsf3(0x3f800000u, 0xffff1234u), 0xffff1234u);
    // nan + inf = same nan
    check_equal(__addsf3(0xffff1234u, 0x7f800000u), 0xffff1234u);
    // inf + nan = same nan
    check_equal(__addsf3(0x7f800000u, 0xffff1234u), 0xffff1234u);
    // inf + inf = inf
    check_equal(__addsf3(0x7f800000u, 0x7f800000u), 0x7f800000u);
    // -inf + -inf = -inf
    check_equal(__addsf3(0xff800000u, 0xff800000u), 0xff800000u);
    // inf + -inf = nan (all-ones is our canonical cheap nan)
    check_equal(__addsf3(0x7f800000u, 0xff800000u), 0xffffffffu);
    // -inf + inf = nan
    check_equal(__addsf3(0xff800000u, 0x7f800000u), 0xffffffffu);
    // subnormal + subnormal = exactly 0
    check_equal(__addsf3(0x007fffffu, 0x007fffffu), 0x00000000u);
    // -subnormal + -subnormal = exactly -0
    check_equal(__addsf3(0x807fffffu, 0x807fffffu), 0x80000000u);
    // Even + 0.5 ulp: round down
    check_equal(__addsf3(0x3f800002u, 0x33800000u), 0x3f800002u);
    // Even - 0.5 ulp: round up
    check_equal(__addsf3(0x3f800002u, 0xb3800000u), 0x3f800002u);
    // Odd + 0.5 ulp: round up
    check_equal(__addsf3(0x3f800001u, 0x33800000u), 0x3f800002u);
    // Odd - 0.5 ulp: round down
    check_equal(__addsf3(0x3f800001u, 0xb3800000u), 0x3f800000u);
    // All-zeroes significand - 0.5 ulp: no rounding (exact)
    check_equal(__addsf3(0x3f800000u, 0xb3800000u), 0x3f7fffffu);
    // Very subnormal difference of normals: flushed to zero
    check_equal(__addsf3(0x03800000u, 0x837fffffu), 0x00000000u);
    // Barely subnormal difference of normals: also flushed (unflushed result is 2^(emin-1))
    check_equal(__addsf3(0x03800000u, 0x837e0000u), 0x00000000u);
	return 0;
}