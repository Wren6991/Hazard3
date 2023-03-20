#include "tb_cxxrtl_io.h"
#include "hazard3_instr.h"

// Smoke test for instructions in the Xh3b extension (Hazard3 custom
// bitmanip). Currently these are:

// - h3_bextm: multiple bit version of the bext instruction from Zbs (1 to 8 bits)
// - h3_bextmi: immediate version of the above (as bexti is to bext)

// The instruction is just supposed to take a single static size...
__attribute__((noinline)) uint32_t bextm_dynamic_width(unsigned int nbits, uint32_t rs1, uint32_t rs2) {
	switch (nbits) {
	case 1:
		return __hazard3_bextm(1, rs1, rs2);
	case 2:
		return __hazard3_bextm(2, rs1, rs2);
	case 3:
		return __hazard3_bextm(3, rs1, rs2);
	case 4:
		return __hazard3_bextm(4, rs1, rs2);
	case 5:
		return __hazard3_bextm(5, rs1, rs2);
	case 6:
		return __hazard3_bextm(6, rs1, rs2);
	case 7:
		return __hazard3_bextm(7, rs1, rs2);
	case 8:
	default:
		return __hazard3_bextm(8, rs1, rs2);
	}
}

int main() {
	uint32_t x = 0xabcdef5a;
	for (int nbits = 1; nbits <= 8; ++nbits) {
		for (int shamt = 0; shamt < 32; ++shamt) {
			uint32_t expect = (x >> shamt) & ~(~0u << nbits);
			uint32_t actual = bextm_dynamic_width(nbits, x, shamt);
			tb_assert(
				expect == actual,
				"Bad result for rs1=%08x shamt=%d nbits=%d: expected %08x, got %08x\n",
				x, shamt, nbits, expect, actual
			);
		}
	}
	// Quick smoke test for bextmi vs bextm
	tb_assert(__hazard3_bextm(8, x, 0 ) == __hazard3_bextmi(8, x, 0 ), "bextm vs bextmi mismatch shamt=0 \n");
	tb_assert(__hazard3_bextm(8, x, 1 ) == __hazard3_bextmi(8, x, 1 ), "bextm vs bextmi mismatch shamt=1 \n");
	tb_assert(__hazard3_bextm(8, x, 2 ) == __hazard3_bextmi(8, x, 2 ), "bextm vs bextmi mismatch shamt=2 \n");
	tb_assert(__hazard3_bextm(8, x, 3 ) == __hazard3_bextmi(8, x, 3 ), "bextm vs bextmi mismatch shamt=3 \n");
	tb_assert(__hazard3_bextm(8, x, 4 ) == __hazard3_bextmi(8, x, 4 ), "bextm vs bextmi mismatch shamt=4 \n");
	tb_assert(__hazard3_bextm(8, x, 5 ) == __hazard3_bextmi(8, x, 5 ), "bextm vs bextmi mismatch shamt=5 \n");
	tb_assert(__hazard3_bextm(8, x, 6 ) == __hazard3_bextmi(8, x, 6 ), "bextm vs bextmi mismatch shamt=6 \n");
	tb_assert(__hazard3_bextm(8, x, 7 ) == __hazard3_bextmi(8, x, 7 ), "bextm vs bextmi mismatch shamt=7 \n");
	tb_assert(__hazard3_bextm(8, x, 8 ) == __hazard3_bextmi(8, x, 8 ), "bextm vs bextmi mismatch shamt=8 \n");
	tb_assert(__hazard3_bextm(8, x, 9 ) == __hazard3_bextmi(8, x, 9 ), "bextm vs bextmi mismatch shamt=9 \n");
	tb_assert(__hazard3_bextm(8, x, 10) == __hazard3_bextmi(8, x, 10), "bextm vs bextmi mismatch shamt=10\n");
	tb_assert(__hazard3_bextm(8, x, 11) == __hazard3_bextmi(8, x, 11), "bextm vs bextmi mismatch shamt=11\n");
	tb_assert(__hazard3_bextm(8, x, 12) == __hazard3_bextmi(8, x, 12), "bextm vs bextmi mismatch shamt=12\n");
	tb_assert(__hazard3_bextm(8, x, 13) == __hazard3_bextmi(8, x, 13), "bextm vs bextmi mismatch shamt=13\n");
	tb_assert(__hazard3_bextm(8, x, 14) == __hazard3_bextmi(8, x, 14), "bextm vs bextmi mismatch shamt=14\n");
	tb_assert(__hazard3_bextm(8, x, 15) == __hazard3_bextmi(8, x, 15), "bextm vs bextmi mismatch shamt=15\n");
	tb_assert(__hazard3_bextm(8, x, 16) == __hazard3_bextmi(8, x, 16), "bextm vs bextmi mismatch shamt=16\n");
	tb_assert(__hazard3_bextm(8, x, 17) == __hazard3_bextmi(8, x, 17), "bextm vs bextmi mismatch shamt=17\n");
	tb_assert(__hazard3_bextm(8, x, 18) == __hazard3_bextmi(8, x, 18), "bextm vs bextmi mismatch shamt=18\n");
	tb_assert(__hazard3_bextm(8, x, 19) == __hazard3_bextmi(8, x, 19), "bextm vs bextmi mismatch shamt=19\n");
	tb_assert(__hazard3_bextm(8, x, 20) == __hazard3_bextmi(8, x, 20), "bextm vs bextmi mismatch shamt=20\n");
	tb_assert(__hazard3_bextm(8, x, 21) == __hazard3_bextmi(8, x, 21), "bextm vs bextmi mismatch shamt=21\n");
	tb_assert(__hazard3_bextm(8, x, 22) == __hazard3_bextmi(8, x, 22), "bextm vs bextmi mismatch shamt=22\n");
	tb_assert(__hazard3_bextm(8, x, 23) == __hazard3_bextmi(8, x, 23), "bextm vs bextmi mismatch shamt=23\n");
	tb_assert(__hazard3_bextm(8, x, 24) == __hazard3_bextmi(8, x, 24), "bextm vs bextmi mismatch shamt=24\n");
	tb_assert(__hazard3_bextm(8, x, 25) == __hazard3_bextmi(8, x, 25), "bextm vs bextmi mismatch shamt=25\n");
	tb_assert(__hazard3_bextm(8, x, 26) == __hazard3_bextmi(8, x, 26), "bextm vs bextmi mismatch shamt=26\n");
	tb_assert(__hazard3_bextm(8, x, 27) == __hazard3_bextmi(8, x, 27), "bextm vs bextmi mismatch shamt=27\n");
	tb_assert(__hazard3_bextm(8, x, 28) == __hazard3_bextmi(8, x, 28), "bextm vs bextmi mismatch shamt=28\n");
	tb_assert(__hazard3_bextm(8, x, 29) == __hazard3_bextmi(8, x, 29), "bextm vs bextmi mismatch shamt=29\n");
	tb_assert(__hazard3_bextm(8, x, 30) == __hazard3_bextmi(8, x, 30), "bextm vs bextmi mismatch shamt=30\n");
	tb_assert(__hazard3_bextm(8, x, 31) == __hazard3_bextmi(8, x, 31), "bextm vs bextmi mismatch shamt=31\n");

	tb_assert(__hazard3_bextm(1, 0xffu, 0) == __hazard3_bextmi(1, 0xffu, 0), "bextm vs bextmi mismatch nbits=1\n");
	tb_assert(__hazard3_bextm(2, 0xffu, 0) == __hazard3_bextmi(2, 0xffu, 0), "bextm vs bextmi mismatch nbits=2\n");
	tb_assert(__hazard3_bextm(3, 0xffu, 0) == __hazard3_bextmi(3, 0xffu, 0), "bextm vs bextmi mismatch nbits=3\n");
	tb_assert(__hazard3_bextm(4, 0xffu, 0) == __hazard3_bextmi(4, 0xffu, 0), "bextm vs bextmi mismatch nbits=4\n");
	tb_assert(__hazard3_bextm(5, 0xffu, 0) == __hazard3_bextmi(5, 0xffu, 0), "bextm vs bextmi mismatch nbits=5\n");
	tb_assert(__hazard3_bextm(6, 0xffu, 0) == __hazard3_bextmi(6, 0xffu, 0), "bextm vs bextmi mismatch nbits=6\n");
	tb_assert(__hazard3_bextm(7, 0xffu, 0) == __hazard3_bextmi(7, 0xffu, 0), "bextm vs bextmi mismatch nbits=7\n");
	tb_assert(__hazard3_bextm(8, 0xffu, 0) == __hazard3_bextmi(8, 0xffu, 0), "bextm vs bextmi mismatch nbits=8\n");

	return 0;
}
