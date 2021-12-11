#include "tb_cxxrtl_io.h"
#include <stdint.h>

/*EXPECTED-OUTPUT***************************************************************

Test 1: lr.w -> nop -> sc.w
OK
Test 2: lr.w -> sc.w
OK
Test 3: sc.w with no preceding lr.w
OK
Test 4: lr.w -> sw -> sc.w
OK

*******************************************************************************/

volatile uint32_t scratch[2];

int main() {
	uint32_t load_result, success;
	tb_puts("Test 1: lr.w -> nop -> sc.w\n");
	scratch[0] = 0x1234;
	asm volatile (
		"lr.w %0, (%2)\n"
		"nop\n"
		"sc.w %1, %3, (%2)\n"
		// Note the "&": this marks an "earlyclobber" operand, telling GCC it can't
		// allocate this output to an input register. (particularly, %0 to %2)
		: "=&r" (load_result), "=r" (success)
		: "r" (&scratch[0]), "r" (0x5678)
	);
	tb_assert(load_result == 0x1234, "Bad load result %08x\n", load_result);
	tb_assert(scratch[0] == 0x5678, "Store didn't write memory\n");
	tb_assert(success == 1, "Should report success\n");
	tb_puts("OK\n");

	tb_puts("Test 2: lr.w -> sc.w\n");
	scratch[0] = 0xabcd;
	asm volatile (
		"lr.w %0, (%2)\n"
		"sc.w %1, %3, (%2)\n"
		: "=&r" (load_result), "=r" (success)
		: "r" (&scratch[0]), "r" (0xa5a5)
	);
	tb_assert(load_result == 0xabcd, "Bad load result %08x\n", load_result);
	tb_assert(scratch[0] == 0xa5a5, "Store didn't write memory\n");
	tb_assert(success == 1, "Should report success\n");
	tb_puts("OK\n");

	tb_puts("Test 3: sc.w with no preceding lr.w\n");
	scratch[0] = 0x1234;
	asm volatile (
		"sc.w %0, %2, (%1)\n"
		: "=r" (success)
		: "r" (&scratch[0]), "r" (0x5678)
	);
	tb_assert(scratch[0] == 0x1234, "Store shouldn't write memory\n");
	tb_assert(success == 0, "Should report failure\n");
	tb_puts("OK\n");

	// Reservation is only cleared by other harts' stores.
	tb_puts("Test 4: lr.w -> sw -> sc.w\n");
	scratch[0] = 0x1234;
	scratch[1] = 0;
	asm volatile (
		"lr.w %0, (%2)\n"
		"sw %3, 4(%2)\n"
		"sc.w %1, %4, (%2)\n"
		: "=&r" (load_result), "=r" (success)
		: "r" (&scratch[0]), "r" (0xabcd), "r" (0x5678)
	);
	tb_assert(scratch[1] == 0xabcd, "Regular store should succeed\n");
	tb_assert(scratch[0] == 0x5678, "sc didn't write memory\n");
	tb_assert(success == 1, "Should report success\n");
	tb_puts("OK\n");

	return 0;
}
