#include "tb_cxxrtl_io.h"

// Check that lr->sc, lr->alu and sc->alu bypass/stall work as expected. This
// logic is not currently covered by e.g. riscv-formal, so is worth a simple
// directed test.

/*EXPECTED-OUTPUT***************************************************************

lr -> mv: 12345678
lr -> sc: sc returned 1
scratch[1] = deadbeef
sc -> mv: sc returned 0
scratch[0] = 5678a5a5

*******************************************************************************/

volatile uint32_t scratch[2];

// lr.w -> alu
uint32_t __attribute__((naked, noinline)) test1(volatile uint32_t *src) {
	asm volatile (
		"lr.w a1, (a0)\n"
		"mv a0, a1\n"
		"ret"
	);
}

// lr.w -> sc.w
uint32_t __attribute__((naked, noinline)) test2(volatile uint32_t *src, volatile uint32_t *dst) {
	asm volatile (
		"lr.w a2, (a0)\n"
		"sc.w a0, a2, (a1)\n"
		"ret"
	);
}

// sc.w -> alu
uint32_t __attribute__((naked, noinline)) test3(uint32_t initial_sc, volatile uint32_t *dst) {
	asm volatile (
		"sc.w a1, a0, (a1)\n"
		"mv a0, a1\n"
		"ret"
	);
}

int main() {
	scratch[0] = 0x12345678;
	scratch[1] = 0;
	tb_printf("lr -> mv: %08x\n", test1(&scratch[0]));

	scratch[0] = 0xdeadbeef;
	scratch[1] = 0;
	tb_printf("lr -> sc: sc returned %u\n", test2(&scratch[0], &scratch[1]));
	tb_printf("scratch[1] = %08x\n", scratch[1]);

	scratch[0] = 0x5678a5a5;
	tb_printf("sc -> mv: sc returned %u\n", test3(123, &scratch[0]));
	tb_printf("scratch[0] = %08x\n", scratch[0]);

	return 0;
}
