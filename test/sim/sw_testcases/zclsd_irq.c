#include "tb_cxxrtl_io.h"
#include "zilsd_macros.h"
#include <stdint.h>

// Test intent: cover various cases of interrupts vs ld/sd:
//
// * interrupting first and second phase of instruction (by randomising IRQ timing)
// * restart of loads which clobber the base with the destination
// * both orders of reg swap (alias base with both halves of destination pair)
//
// (this is the same as zilsd_irq, just using zclsd equivalent instructions)

#define BUF_WORDS (4 * 1024)

// prime number:
#define IRQ_INTERVAL 97

volatile uint32_t amo_count, irq_count;

void __attribute__((interrupt)) isr_machine_timer() {
	mm_timer->mtimecmp = mm_timer->mtimecmp + IRQ_INTERVAL;
}

static inline uint32_t test_pattern(uint32_t i) {
	return (i + 1) * 0x07050301u;
}

void __attribute__((naked)) copy1(__attribute__((unused)) void *dst, __attribute__((unused)) const void *src, __attribute__((unused)) uint32_t len) {
	asm volatile (
		"add a2, a2, a1\n"
		"bgeu a1, a2, 2f\n"
	"1:\n"
		// plain
		"zclsd.ld x_a4, x_a1, 0\n"
		"zclsd.sd x_a4, x_a0, 0\n"

		// clobber even base (and get an odd base on sw, which also swaps even
		// though it's not required to)
		"mv a4, a1\n"
		"zclsd.ld x_a4, x_a4, 8\n"
		"mv a3, a0\n"
		"zclsd.sd x_a4, x_a3, 8\n"
		// clobber odd base
		"mv a5, a1\n"
		"zclsd.ld x_a4, x_a5, 16\n"
		"zclsd.sd x_a4, x_a3, 16\n"
		// turn IRQs off and on
		"csrci mstatus, 0x8\n"
		"zclsd.ld x_a4, x_a1, 24\n"
		"csrsi mstatus, 0x8\n"

		"csrci mstatus, 0x8\n"
		"zclsd.sd x_a4, x_a0, 24\n"
		"csrsi mstatus, 0x8\n"

		"addi a0, a0, 32\n"
		"addi a1, a1, 32\n"
		"bltu a1, a2, 1b\n"

	"2:\n"
		"ret\n"
	);
}

uint32_t buf0[BUF_WORDS];
uint32_t buf1[BUF_WORDS];

void init_zero(uint32_t *buf) {
	for (int i = 0; i < BUF_WORDS; ++i) {
		buf[i] = 0;
	}
}

void init_pattern(uint32_t *buf) {
	for (int i = 0; i < BUF_WORDS; ++i) {
		buf[i] = test_pattern(i);
	}
}

void check_pattern(uint32_t *buf) {
	for (int i = 0; i < BUF_WORDS; ++i) {
		tb_assert(
			buf[i] == test_pattern(i),
			"Failure at %08x: expected %08x, got %08x\n",
			(uintptr_t)&buf[i],
			test_pattern(i),
			buf[i]
		);
	}
}


typedef void (*copy_func_t)(void *, const void *, uint32_t);

void test_copy_func(copy_func_t func) {
	init_pattern(buf0);
	init_zero(buf1);
	func(buf1, buf0, sizeof(buf0));
	check_pattern(buf1);
}

int main(void) {
	asm volatile ("csrw mie, %0" : : "r" (0x80));
	mm_timer->mtime = 0;
	// Will take first timer interrupt immediately:
	tb_puts("Starting IRQs\n");
	asm volatile ("csrsi mstatus, 0x8");

	tb_puts("Starting copy\n");
	test_copy_func(copy1);
	tb_puts("Done\n");
	return 0;
}
