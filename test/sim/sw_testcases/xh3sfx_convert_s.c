#include "tb_cxxrtl_io.h"

#include <stdint.h>
#include <stddef.h>
#include <limits.h>

// Test for Xh3sfx conversion from f32 to/from other types (including f32 <-> f16).

// ebreak is easier to find in waves.
#if 1
#define check_equal(a, b) tb_assert((a) == (b), "Line %d: " #a " == " #b "\nGot: %08x != %08x\n", __LINE__, (a), (b))
#define check_equal64(a, b) tb_assert((a) == (b), "Line %d: " #a " == " #b "\nGot: %016llx != %16llx\n", __LINE__, (a), (b))
#else
#define check_equal(a, b) if ((a) != (b)) {asm ("ebreak");}
#define check_equal64(a, b) if ((a) != (b)) {asm ("ebreak");}
#endif

// Data types other than unsigned bit vector are not real and cannot hurt you
uint32_t __h3_extendhfsf2(uint16_t x); // f16 -> f32
uint32_t __h3_truncsfhf2(uint32_t x);  // f32 -> f16

uint32_t __h3_fixsfsi(uint32_t x);     // f32 -> i32
uint32_t __h3_fixunssfsi(uint32_t x);  // f32 -> u32

uint32_t __h3_floatsisf(uint32_t x);   // i32 -> f32
uint32_t __h3_floatunsisf(uint32_t x); // u32 -> f32

uint64_t __h3_fixsfdi(uint32_t x);     // f32 -> i64
uint64_t __h3_fixunssfdi(uint32_t x);  // f32 -> u64

int main() {
    // ------------------------------------------------------------------------
    // f32 <-> f16

    // Check some round-trips f16 -> f32 -> f16
    check_equal(0x0000, 0xffff & __h3_truncsfhf2(__h3_extendhfsf2(0x0000)));
    check_equal(0x8000, 0xffff & __h3_truncsfhf2(__h3_extendhfsf2(0x8000)));
    check_equal(0x7c00, 0xffff & __h3_truncsfhf2(__h3_extendhfsf2(0x7c00)));
    check_equal(0xfc00, 0xffff & __h3_truncsfhf2(__h3_extendhfsf2(0xfc00)));
    check_equal(0x7bff, 0xffff & __h3_truncsfhf2(__h3_extendhfsf2(0x7bff)));
    check_equal(0xfbff, 0xffff & __h3_truncsfhf2(__h3_extendhfsf2(0xfbff)));
    check_equal(0x0400, 0xffff & __h3_truncsfhf2(__h3_extendhfsf2(0x0400)));
    check_equal(0x8400, 0xffff & __h3_truncsfhf2(__h3_extendhfsf2(0x8400)));
    check_equal(0x0401, 0xffff & __h3_truncsfhf2(__h3_extendhfsf2(0x0401)));
    check_equal(0x8401, 0xffff & __h3_truncsfhf2(__h3_extendhfsf2(0x8401)));

    // Check f16 subnormals flush to +-0 on f32 conversion
    check_equal(__h3_extendhfsf2(0x0000), 0x00000000);
    check_equal(__h3_extendhfsf2(0x8000), 0x80000000);
    check_equal(__h3_extendhfsf2(0x0001), 0x00000000);
    check_equal(__h3_extendhfsf2(0x8001), 0x80000000);
    check_equal(__h3_extendhfsf2(0x03ff), 0x00000000);
    check_equal(__h3_extendhfsf2(0x83ff), 0x80000000);

    // Check f32 subnormals flush to +-0 on f16 conversion
    check_equal(0xffff & __h3_truncsfhf2(0x00000000), 0x0000);
    check_equal(0xffff & __h3_truncsfhf2(0x80000000), 0x8000);
    check_equal(0xffff & __h3_truncsfhf2(0x00000001), 0x0000);
    check_equal(0xffff & __h3_truncsfhf2(0x80000001), 0x8000);
    check_equal(0xffff & __h3_truncsfhf2(0x007fffff), 0x0000);
    check_equal(0xffff & __h3_truncsfhf2(0x807fffff), 0x8000);

    // Check exponent saturation on f32 -> f16
    check_equal(0xffff & __h3_truncsfhf2(0x7f800000), 0x7c00); // f32 inf
    check_equal(0xffff & __h3_truncsfhf2(0xff800000), 0xfc00);
    check_equal(0xffff & __h3_truncsfhf2(0x47800000), 0x7c00); // exact f16 max exp
    check_equal(0xffff & __h3_truncsfhf2(0xc7800000), 0xfc00);
    check_equal(0xffff & __h3_truncsfhf2(0x47c00000), 0x7c00); // same, with nonzero significand (should clear)
    check_equal(0xffff & __h3_truncsfhf2(0xc7c00000), 0xfc00);
    check_equal(0xffff & __h3_truncsfhf2(0x47000000), 0x7800); // one less than f16 max exp
    check_equal(0xffff & __h3_truncsfhf2(0xc7000000), 0xf800);
    check_equal(0xffff & __h3_truncsfhf2(0x47400000), 0x7a00); // same, with nonzero significand:
    check_equal(0xffff & __h3_truncsfhf2(0xc7400000), 0xfa00);
    check_equal(0xffff & __h3_truncsfhf2(0x477fffff), 0x7c00); // round up to f16 max exp
    check_equal(0xffff & __h3_truncsfhf2(0xc77fffff), 0xfc00);
    check_equal(0xffff & __h3_truncsfhf2(0x47ffffff), 0x7c00); // round up above f16 max exp
    check_equal(0xffff & __h3_truncsfhf2(0xc7ffffff), 0xfc00);

    // Check rounding on f32 -> f16
    check_equal(0xffff & __h3_truncsfhf2(0x3f800000), 0x3c00); // 1.f
    check_equal(0xffff & __h3_truncsfhf2(0x3f800fff), 0x3c00); // round down
    check_equal(0xffff & __h3_truncsfhf2(0x3f801000), 0x3c00); // tie-break down
    check_equal(0xffff & __h3_truncsfhf2(0x3f801001), 0x3c01); // round up
    check_equal(0xffff & __h3_truncsfhf2(0x3f802000), 0x3c01); // exact
    check_equal(0xffff & __h3_truncsfhf2(0x3f802fff), 0x3c01); // round down
    check_equal(0xffff & __h3_truncsfhf2(0x3f803000), 0x3c02); // tie-break up
    check_equal(0xffff & __h3_truncsfhf2(0x3f803001), 0x3c02); // round up

    // Check canonical NaNs
    check_equal(__h3_truncsfhf2(0xffffffff), 0xffffffff);
    check_equal(__h3_extendhfsf2(0xffff), 0xffffffff);

    // ------------------------------------------------------------------------
    // f32 <-> i32

    check_equal(__h3_fixsfsi(0x00000000),  0                       ); // +- 0
    check_equal(__h3_fixsfsi(0x80000000),  0                       );
    check_equal(__h3_fixsfsi(0x007fffff),  0                       ); // +- subnormal
    check_equal(__h3_fixsfsi(0x807fffff),  0                       );
    check_equal(__h3_fixsfsi(0x3f000000),  0                       ); // +- 1/2 (note GCC requires truncate-to-zero)
    check_equal(__h3_fixsfsi(0xbf000000),  0                       );
    check_equal(__h3_fixsfsi(0x3f800000),  1                       ); // +- 1
    check_equal(__h3_fixsfsi(0xbf800000), -1                       );
    check_equal(__h3_fixsfsi(0x3f7fffff),  0                       ); //  1 - 1ulp
    check_equal(__h3_fixsfsi(0xbf7fffff),  0                       ); // -1 + 1ulp
    check_equal(__h3_fixsfsi(0x4f000000), INT_MAX                  ); // max exponent
    check_equal(__h3_fixsfsi(0xcf000000), INT_MIN                  );
    check_equal(__h3_fixsfsi(0x4e800000), -(INT_MIN >> 1)          );
    check_equal(__h3_fixsfsi(0xce800000), INT_MIN >> 1             );
    check_equal(__h3_fixsfsi(0x4f7fffff), INT_MAX                  );
    check_equal(__h3_fixsfsi(0xcf7fffff), INT_MIN                  );
    check_equal(__h3_fixsfsi(0x4f800000), INT_MAX                  );
    check_equal(__h3_fixsfsi(0xcf800000), INT_MIN                  );
    check_equal(__h3_fixsfsi(0x7f800000), INT_MAX                  ); // +-inf
    check_equal(__h3_fixsfsi(0xff800000), INT_MIN                  );
    check_equal(__h3_fixsfsi(0x7fffffff), INT_MAX                  ); // "+-nan"
    check_equal(__h3_fixsfsi(0xffffffff), INT_MIN                  );
    check_equal(__h3_fixsfsi(0x4b7fffff), (1 << 24) - 1            ); // largest odd number
    check_equal(__h3_fixsfsi(0xcb7fffff), -(1 << 24) + 1           ); // smallest odd number
    check_equal(__h3_fixsfsi(0x4effffff), INT_MAX - (1 << 7) + 1   ); // largest non-saturated
    check_equal(__h3_fixsfsi(0xceffffff), -(INT_MAX - (1 << 7) + 1)); // smallest non-saturated

    // Reverse of above, with rhs canonicalised and NaNs and infinities removed
    check_equal(__h3_floatsisf( 0                       ), 0x00000000);
    check_equal(__h3_floatsisf( 1                       ), 0x3f800000); // +- 1
    check_equal(__h3_floatsisf(-1                       ), 0xbf800000);
    check_equal(__h3_floatsisf(INT_MAX                  ), 0x4f000000); // max exponent
    check_equal(__h3_floatsisf(INT_MIN                  ), 0xcf000000);
    check_equal(__h3_floatsisf(-(INT_MIN >> 1)          ), 0x4e800000);
    check_equal(__h3_floatsisf(INT_MIN >> 1             ), 0xce800000);
    check_equal(__h3_floatsisf((1 << 24) - 1            ), 0x4b7fffff); // largest odd number
    check_equal(__h3_floatsisf(-(1 << 24) + 1           ), 0xcb7fffff); // smallest odd number
    check_equal(__h3_floatsisf(INT_MAX - (1 << 7) + 1   ), 0x4effffff); // largest non-saturated
    check_equal(__h3_floatsisf(-(INT_MAX - (1 << 7) + 1)), 0xceffffff); // smallest non-saturated

    // ------------------------------------------------------------------------
    // f32 <-> u32

    check_equal(__h3_fixunssfsi(0x00000000),  0                       ); // +- 0
    check_equal(__h3_fixunssfsi(0x80000000),  0                       );
    check_equal(__h3_fixunssfsi(0x007fffff),  0                       ); // +- subnormal
    check_equal(__h3_fixunssfsi(0x807fffff),  0                       );
    check_equal(__h3_fixunssfsi(0x3f000000),  0                       ); // +- 1/2 (note GCC requires truncate-to-zero)
    check_equal(__h3_fixunssfsi(0xbf000000),  0                       );
    check_equal(__h3_fixunssfsi(0xff800000),  0                       ); // -inf: clamped to 0
    check_equal(__h3_fixunssfsi(0x3f800000),  1                       ); // 1
    check_equal(__h3_fixunssfsi(0x3f7fffff),  0                       ); // 1 - 1ulp
    check_equal(__h3_fixunssfsi(0x40000000),  2                       ); // 2
    check_equal(__h3_fixunssfsi(0x3fffffff),  1                       ); // 2 - 1ulp
    check_equal(__h3_fixunssfsi(0x4b7fffff), (1 << 24) - 1            ); // largest odd number
    check_equal(__h3_fixunssfsi(0x4f7fffff), UINT_MAX - (1 << 8) + 1  ); // largest non-saturated
    check_equal(__h3_fixunssfsi(0x4f000000), (UINT_MAX >> 1) + 1      ); // one less than max exponent
    check_equal(__h3_fixunssfsi(0x4f800000), UINT_MAX                 ); // max exponent
    check_equal(__h3_fixunssfsi(0x7f800000), UINT_MAX                 ); // inf
    check_equal(__h3_fixunssfsi(0x7fffffff), UINT_MAX                 ); // "+nan"

    check_equal(__h3_floatunsisf( 0                     ), 0x00000000); // +- 0
    check_equal(__h3_floatunsisf( 1                     ), 0x3f800000); // 1
    check_equal(__h3_floatunsisf( 2                     ), 0x40000000); // 2
    check_equal(__h3_floatunsisf((1 << 24) - 1          ), 0x4b7fffff); // largest odd number
    check_equal(__h3_floatunsisf(UINT_MAX - (1 << 8) + 1), 0x4f7fffff); // largest non-saturated
    check_equal(__h3_floatunsisf((UINT_MAX >> 1) + 1    ), 0x4f000000); // one less than max exponent
    check_equal(__h3_floatunsisf(UINT_MAX               ), 0x4f800000); // max exponent

    // ------------------------------------------------------------------------
    // f32 <-> i64

    check_equal64(__h3_fixsfdi(0x00000000u), 0x0000000000000000u); // +-0
    check_equal64(__h3_fixsfdi(0x80000000u), 0x0000000000000000u);
    check_equal64(__h3_fixsfdi(0x3f800000u), 0x0000000000000001u); // +- 1 (note all negatives should be clamped to 0)
    check_equal64(__h3_fixsfdi(0xbf800000u), 0xffffffffffffffffu);
    check_equal64(__h3_fixsfdi(0x3f000000u), 0x0000000000000000u); // +- 1/2
    check_equal64(__h3_fixsfdi(0xbf000000u), 0x0000000000000000u);
    check_equal64(__h3_fixsfdi(0x7f800000u), 0x7fffffffffffffffu); // +- inf
    check_equal64(__h3_fixsfdi(0xff800000u), 0x8000000000000000u);
    for (unsigned int i = 0; i < 63u; ++i) {
        check_equal64(__h3_fixsfdi(0x3f800001u + (i << 23)), i < 23 ?   0x800001ll >> (23 - i)  :   0x800001ll << (i - 23) );
        check_equal64(__h3_fixsfdi(0xbf800001u + (i << 23)), i < 23 ? -(0x800001ll >> (23 - i)) : -(0x800001ll << (i - 23)));
    }
    check_equal64(__h3_fixsfdi(0x3f800001u + (64 << 23)), 0x7fffffffffffffffu);
    check_equal64(__h3_fixsfdi(0xbf800001u + (64 << 23)), 0x8000000000000000u);

    // ------------------------------------------------------------------------
    // f32 <-> u64

    check_equal64(__h3_fixunssfdi(0x00000000u), 0x0000000000000000u); // +-0
    check_equal64(__h3_fixunssfdi(0x80000000u), 0x0000000000000000u);
    check_equal64(__h3_fixunssfdi(0x3f800000u), 0x0000000000000001u); // +- 1 (note all negatives should be clamped to 0)
    check_equal64(__h3_fixunssfdi(0xbf800000u), 0x0000000000000000u);
    check_equal64(__h3_fixunssfdi(0x3f000000u), 0x0000000000000000u); // +- 1/2
    check_equal64(__h3_fixunssfdi(0xbf000000u), 0x0000000000000000u);
    check_equal64(__h3_fixunssfdi(0x7f800000u), 0xffffffffffffffffu); // +- inf
    check_equal64(__h3_fixunssfdi(0xff800000u), 0x0000000000000000u);
    for (unsigned int i = 0; i < 64u; ++i) {
        check_equal64(__h3_fixunssfdi(0x3f800001u + (i << 23)), i < 23 ? 0x800001ull >> (23 - i) : 0x800001ull << (i - 23));
    }



	return 0;
}