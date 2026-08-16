#include "tb_cxxrtl_io.h"

#include <stdint.h>
#include <stddef.h>
#include <limits.h>

// Test for Xh3sfx conversion: f16 to/from integers

// ebreak is easier to find in waves.
#if 1
#define check_equal(a, b) tb_assert((a) == (b), "Line %d: " #a " == " #b "\nGot: %08x != %08x\n", __LINE__, (a), (b))
#else
#define check_equal(a, b) if ((a) != (b)) {asm ("ebreak");}
#endif

uint32_t __h3_fixhfsi(uint32_t x);     // f16 -> i32
uint32_t __h3_fixunshfsi(uint32_t x);  // f16 -> u32
uint32_t __h3_floatsihf(uint32_t x);   // i32 -> f16
uint32_t __h3_floatunsihf(uint32_t x); // u32 -> f16

int main() {
    // ------------------------------------------------------------------------
    // f16 <-> i32

    check_equal(__h3_fixhfsi(0x0000),  0                       ); // +- 0
    check_equal(__h3_fixhfsi(0x8000),  0                       );
    check_equal(__h3_fixhfsi(0x03ff),  0                       ); // +- subnormal
    check_equal(__h3_fixhfsi(0x83ff),  0                       );
    check_equal(__h3_fixhfsi(0x3800),  0                       ); // +- 1/2 (note GCC requires truncate-to-zero)
    check_equal(__h3_fixhfsi(0xb800),  0                       );
    check_equal(__h3_fixhfsi(0x3c00),  1                       ); // +- 1
    check_equal(__h3_fixhfsi(0xbc00), -1                       );
    check_equal(__h3_fixhfsi(0x3bff),  0                       ); //  1 - 1ulp
    check_equal(__h3_fixhfsi(0xbbff),  0                       ); // -1 + 1ulp
    check_equal(__h3_fixhfsi(0x7c00), INT_MAX                  ); // +inf
    check_equal(__h3_fixhfsi(0xfc00), INT_MIN                  ); // -inf
    for (int i = 0; i < 16; ++i) {
        check_equal(__h3_fixhfsi(0x3c01 + (i << 10)),   i < 10 ? 0x401 >> (10 - i) : 0x401 << (i - 10) );
        check_equal(__h3_fixhfsi(0xbc01 + (i << 10)), -(i < 10 ? 0x401 >> (10 - i) : 0x401 << (i - 10)));
    }

    check_equal(__h3_floatsihf( 0),                    0x00000000);
    check_equal(__h3_floatsihf( 1),                    0x00003c00);
    check_equal(__h3_floatsihf(-1),                    0xffffbc00);
    check_equal(__h3_floatsihf(INT_MAX),               0x00007c00); // +inf
    check_equal(__h3_floatsihf(INT_MIN),               0xfffffc00); // -inf
    check_equal(__h3_floatsihf(1 << 15),               0x00007800); // max exponent
    check_equal(__h3_floatsihf((1 << 15) + (1 << 5)),  0x00007801); // ... +1ulp
    check_equal(__h3_floatsihf((1 << 15) - (1 << 4)),  0x000077ff); // ... -0.5ulp (exact)
    check_equal(__h3_floatsihf(-1 << 15),              0xfffff800); // previous three tests, negated
    check_equal(__h3_floatsihf((-1 << 15) - (1 << 5)), 0xfffff801);
    check_equal(__h3_floatsihf((-1 << 15) + (1 << 4)), 0xfffff7ff);
    check_equal(__h3_floatsihf(0x4008),                0x00007400); // exact tie, even, round down
    check_equal(__h3_floatsihf(0x4009),                0x00007401); // above tie, round up
    check_equal(__h3_floatsihf(0x4007),                0x00007400); // below tie, round down
    check_equal(__h3_floatsihf(0x4018),                0x00007402); // exact tie, odd, round up
    check_equal(__h3_floatsihf(0x4019),                0x00007402); // above tie, round up
    check_equal(__h3_floatsihf(0x4017),                0x00007401); // below tie, round down

    // ------------------------------------------------------------------------
    // f16 <-> u32

    check_equal(__h3_fixunshfsi(0x0000),  0                       ); // +- 0
    check_equal(__h3_fixunshfsi(0x8000),  0                       );
    check_equal(__h3_fixunshfsi(0x03ff),  0                       ); // +- subnormal
    check_equal(__h3_fixunshfsi(0x83ff),  0                       );
    check_equal(__h3_fixunshfsi(0x3800),  0                       ); // +- 1/2 (note GCC requires truncate-to-zero)
    check_equal(__h3_fixunshfsi(0xb800),  0                       );
    check_equal(__h3_fixunshfsi(0x3c00),  1                       ); // +- 1
    check_equal(__h3_fixunshfsi(0xbc00),  0                       );
    check_equal(__h3_fixunshfsi(0x3bff),  0                       ); //  1 - 1ulp
    check_equal(__h3_fixunshfsi(0xbbff),  0                       ); // -1 + 1ulp
    check_equal(__h3_fixunshfsi(0x7c00), UINT_MAX                 ); // +inf
    check_equal(__h3_fixunshfsi(0xfc00), 0                        ); // -inf
    for (int i = 0; i < 16; ++i) {
        check_equal(__h3_fixunshfsi(0x3c01 + (i << 10)), i < 10 ? 0x401 >> (10 - i) : 0x401 << (i - 10));
        check_equal(__h3_fixunshfsi(0xbc01 + (i << 10)), 0                                             );
    }

    check_equal(__h3_floatunsihf( 0),                    0x00000000);
    check_equal(__h3_floatunsihf( 1),                    0x00003c00);
    check_equal(__h3_floatunsihf(UINT_MAX),              0x00007c00); // +inf
    check_equal(__h3_floatunsihf(1 << 15),               0x00007800); // max exponent
    check_equal(__h3_floatunsihf((1 << 15) + (1 << 5)),  0x00007801); // ... +1ulp
    check_equal(__h3_floatunsihf((1 << 15) - (1 << 4)),  0x000077ff); // ... -0.5ulp (exact)
    check_equal(__h3_floatunsihf(0x4008),                0x00007400); // exact tie, even, round down
    check_equal(__h3_floatunsihf(0x4009),                0x00007401); // above tie, round up
    check_equal(__h3_floatunsihf(0x4007),                0x00007400); // below tie, round down
    check_equal(__h3_floatunsihf(0x4018),                0x00007402); // exact tie, odd, round up
    check_equal(__h3_floatunsihf(0x4019),                0x00007402); // above tie, round up
    check_equal(__h3_floatunsihf(0x4017),                0x00007401); // below tie, round down

	return 0;
}
