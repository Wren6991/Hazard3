#include "tb_cxxrtl_io.h"
#include "zibi_macros.h"

// rhs must be compile-time constant!
static inline __attribute__((always_inline)) void test_beqi(int lhs, int rhs) {
	int x = lhs;
	asm volatile (
		"zibi.beqi %0, %1, 1f\n"
		"li %0, 0\n"
		"j 2f\n"
	"1:\n"
		"li %0, 1\n"
	"2:\n"
		: "+r" (x)
		: "i" (rhs)
	);
	tb_printf("beqi %3d, %3d => %d\n", lhs, rhs, x);
	tb_assert(x == (lhs == rhs), "miscompare\n");
}

static inline __attribute__((always_inline)) void test_bnei(int lhs, int rhs) {
	int x = lhs;
	asm volatile (
		"zibi.bnei %0, %1, 1f\n"
		"li %0, 0\n"
		"j 2f\n"
	"1:\n"
		"li %0, 1\n"
	"2:\n"
		: "+r" (x)
		: "i" (rhs)
	);
	tb_printf("bnei %3d, %3d => %d\n", lhs, rhs, x);
	tb_assert(x == (lhs != rhs), "miscompare\n");
}

int main() {
	test_beqi(-1, -1);
	test_beqi( 0,  0);
	test_beqi( 1,  1);
	test_beqi( 2,  2);
	test_beqi( 3,  3);
	test_beqi( 4,  4);
	test_beqi( 5,  5);
	test_beqi( 6,  6);
	test_beqi( 7,  7);
	test_beqi( 8,  8);
	test_beqi( 9,  9);
	test_beqi(10, 10);
	test_beqi(11, 11);
	test_beqi(12, 12);
	test_beqi(13, 13);
	test_beqi(14, 14);
	test_beqi(15, 15);
	test_beqi(16, 16);
	test_beqi(17, 17);
	test_beqi(18, 18);
	test_beqi(19, 19);
	test_beqi(20, 20);
	test_beqi(21, 21);
	test_beqi(22, 22);
	test_beqi(23, 23);
	test_beqi(24, 24);
	test_beqi(25, 25);
	test_beqi(26, 26);
	test_beqi(27, 27);
	test_beqi(28, 28);
	test_beqi(29, 29);
	test_beqi(30, 30);
	test_beqi(31, 31);

	test_beqi(123, -1);
	test_beqi(123,  0);
	test_beqi(123,  1);
	test_beqi(123,  2);
	test_beqi(123,  3);
	test_beqi(123,  4);
	test_beqi(123,  5);
	test_beqi(123,  6);
	test_beqi(123,  7);
	test_beqi(123,  8);
	test_beqi(123,  9);
	test_beqi(123, 10);
	test_beqi(123, 11);
	test_beqi(123, 12);
	test_beqi(123, 13);
	test_beqi(123, 14);
	test_beqi(123, 15);
	test_beqi(123, 16);
	test_beqi(123, 17);
	test_beqi(123, 18);
	test_beqi(123, 19);
	test_beqi(123, 20);
	test_beqi(123, 21);
	test_beqi(123, 22);
	test_beqi(123, 23);
	test_beqi(123, 24);
	test_beqi(123, 25);
	test_beqi(123, 26);
	test_beqi(123, 27);
	test_beqi(123, 28);
	test_beqi(123, 29);
	test_beqi(123, 30);
	test_beqi(123, 31);

	test_bnei(-1, -1);
	test_bnei( 0,  0);
	test_bnei( 1,  1);
	test_bnei( 2,  2);
	test_bnei( 3,  3);
	test_bnei( 4,  4);
	test_bnei( 5,  5);
	test_bnei( 6,  6);
	test_bnei( 7,  7);
	test_bnei( 8,  8);
	test_bnei( 9,  9);
	test_bnei(10, 10);
	test_bnei(11, 11);
	test_bnei(12, 12);
	test_bnei(13, 13);
	test_bnei(14, 14);
	test_bnei(15, 15);
	test_bnei(16, 16);
	test_bnei(17, 17);
	test_bnei(18, 18);
	test_bnei(19, 19);
	test_bnei(20, 20);
	test_bnei(21, 21);
	test_bnei(22, 22);
	test_bnei(23, 23);
	test_bnei(24, 24);
	test_bnei(25, 25);
	test_bnei(26, 26);
	test_bnei(27, 27);
	test_bnei(28, 28);
	test_bnei(29, 29);
	test_bnei(30, 30);
	test_bnei(31, 31);

	test_bnei(123, -1);
	test_bnei(123,  0);
	test_bnei(123,  1);
	test_bnei(123,  2);
	test_bnei(123,  3);
	test_bnei(123,  4);
	test_bnei(123,  5);
	test_bnei(123,  6);
	test_bnei(123,  7);
	test_bnei(123,  8);
	test_bnei(123,  9);
	test_bnei(123, 10);
	test_bnei(123, 11);
	test_bnei(123, 12);
	test_bnei(123, 13);
	test_bnei(123, 14);
	test_bnei(123, 15);
	test_bnei(123, 16);
	test_bnei(123, 17);
	test_bnei(123, 18);
	test_bnei(123, 19);
	test_bnei(123, 20);
	test_bnei(123, 21);
	test_bnei(123, 22);
	test_bnei(123, 23);
	test_bnei(123, 24);
	test_bnei(123, 25);
	test_bnei(123, 26);
	test_bnei(123, 27);
	test_bnei(123, 28);
	test_bnei(123, 29);
	test_bnei(123, 30);
	test_bnei(123, 31);
}

/*EXPECTED-OUTPUT***************************************************************

beqi  -1,  -1 => 1
beqi   0,   0 => 1
beqi   1,   1 => 1
beqi   2,   2 => 1
beqi   3,   3 => 1
beqi   4,   4 => 1
beqi   5,   5 => 1
beqi   6,   6 => 1
beqi   7,   7 => 1
beqi   8,   8 => 1
beqi   9,   9 => 1
beqi  10,  10 => 1
beqi  11,  11 => 1
beqi  12,  12 => 1
beqi  13,  13 => 1
beqi  14,  14 => 1
beqi  15,  15 => 1
beqi  16,  16 => 1
beqi  17,  17 => 1
beqi  18,  18 => 1
beqi  19,  19 => 1
beqi  20,  20 => 1
beqi  21,  21 => 1
beqi  22,  22 => 1
beqi  23,  23 => 1
beqi  24,  24 => 1
beqi  25,  25 => 1
beqi  26,  26 => 1
beqi  27,  27 => 1
beqi  28,  28 => 1
beqi  29,  29 => 1
beqi  30,  30 => 1
beqi  31,  31 => 1
beqi 123,  -1 => 0
beqi 123,   0 => 0
beqi 123,   1 => 0
beqi 123,   2 => 0
beqi 123,   3 => 0
beqi 123,   4 => 0
beqi 123,   5 => 0
beqi 123,   6 => 0
beqi 123,   7 => 0
beqi 123,   8 => 0
beqi 123,   9 => 0
beqi 123,  10 => 0
beqi 123,  11 => 0
beqi 123,  12 => 0
beqi 123,  13 => 0
beqi 123,  14 => 0
beqi 123,  15 => 0
beqi 123,  16 => 0
beqi 123,  17 => 0
beqi 123,  18 => 0
beqi 123,  19 => 0
beqi 123,  20 => 0
beqi 123,  21 => 0
beqi 123,  22 => 0
beqi 123,  23 => 0
beqi 123,  24 => 0
beqi 123,  25 => 0
beqi 123,  26 => 0
beqi 123,  27 => 0
beqi 123,  28 => 0
beqi 123,  29 => 0
beqi 123,  30 => 0
beqi 123,  31 => 0
bnei  -1,  -1 => 0
bnei   0,   0 => 0
bnei   1,   1 => 0
bnei   2,   2 => 0
bnei   3,   3 => 0
bnei   4,   4 => 0
bnei   5,   5 => 0
bnei   6,   6 => 0
bnei   7,   7 => 0
bnei   8,   8 => 0
bnei   9,   9 => 0
bnei  10,  10 => 0
bnei  11,  11 => 0
bnei  12,  12 => 0
bnei  13,  13 => 0
bnei  14,  14 => 0
bnei  15,  15 => 0
bnei  16,  16 => 0
bnei  17,  17 => 0
bnei  18,  18 => 0
bnei  19,  19 => 0
bnei  20,  20 => 0
bnei  21,  21 => 0
bnei  22,  22 => 0
bnei  23,  23 => 0
bnei  24,  24 => 0
bnei  25,  25 => 0
bnei  26,  26 => 0
bnei  27,  27 => 0
bnei  28,  28 => 0
bnei  29,  29 => 0
bnei  30,  30 => 0
bnei  31,  31 => 0
bnei 123,  -1 => 1
bnei 123,   0 => 1
bnei 123,   1 => 1
bnei 123,   2 => 1
bnei 123,   3 => 1
bnei 123,   4 => 1
bnei 123,   5 => 1
bnei 123,   6 => 1
bnei 123,   7 => 1
bnei 123,   8 => 1
bnei 123,   9 => 1
bnei 123,  10 => 1
bnei 123,  11 => 1
bnei 123,  12 => 1
bnei 123,  13 => 1
bnei 123,  14 => 1
bnei 123,  15 => 1
bnei 123,  16 => 1
bnei 123,  17 => 1
bnei 123,  18 => 1
bnei 123,  19 => 1
bnei 123,  20 => 1
bnei 123,  21 => 1
bnei 123,  22 => 1
bnei 123,  23 => 1
bnei 123,  24 => 1
bnei 123,  25 => 1
bnei 123,  26 => 1
bnei 123,  27 => 1
bnei 123,  28 => 1
bnei 123,  29 => 1
bnei 123,  30 => 1
bnei 123,  31 => 1

*******************************************************************************/
