#include "tb_cxxrtl_io.h"
#include <stdint.h>

// Serve timer IRQs in the background whilst performing AMOs in a loop in the
// foreground.

#define IRQ_INTERVAL 201
#define N_AMOS 1000

volatile uint32_t amo_count, irq_count;

void __attribute__((interrupt)) isr_machine_timer() {
	mm_timer->mtimecmp = mm_timer->mtimecmp + IRQ_INTERVAL;
	++irq_count;
}

int main() {
	amo_count = 0;
	irq_count = 0;

	asm volatile ("csrw mie, %0" : : "r" (0x80));
	mm_timer->mtime = 0;
	// Will take first timer interrupt immediately:
	asm volatile ("csrsi mstatus, 0x8");

	for (uint32_t i = 0; i < N_AMOS; i = i + 1) {
		uint32_t fetch;
		asm volatile (
			"amoadd.w %0, %1, (%2)"
			: "=r" (fetch)
			: "r" (1), "r" (&amo_count)
		);
		tb_assert(fetch == i, "Bad fetch, expected %u, got %u\n", i, fetch);
	}

	asm volatile ("csrci mstatus, 0x8");
	uint32_t current_time = mm_timer->mtime;
	tb_printf("At time %u, received %u IRQs\n", current_time, irq_count);
	tb_assert(current_time / IRQ_INTERVAL + 1 == irq_count, "Bad IRQ count\n");
	tb_assert(amo_count == N_AMOS, "Bad final AMO count %u\n", N_AMOS);

	return 0;
}
