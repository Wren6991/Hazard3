#include "tb_cxxrtl_io.h"

#define TIMER_INTERVAL 1000
#define MAX_IRQ_COUNT 10

#define __wfi()         asm volatile ("wfi")
#define __compiler_mb() asm volatile ("" ::: "memory")

typedef struct {
	volatile uint32_t mtime;
	volatile uint32_t mtimeh;
	volatile uint32_t mtimecmp;
	volatile uint32_t mtimecmph;
} timer_hw;

timer_hw *const timer = (timer_hw*)(IO_BASE + 0x100);

int irq_count;
void __attribute__((interrupt)) isr_machine_timer() {
	__compiler_mb();
	++irq_count;
	__compiler_mb();

	tb_printf("IRQ %d\n", irq_count);

	// Disable timer IRQ via MTIE, or set the next timer IRQ
	if (irq_count >= MAX_IRQ_COUNT)
		asm ("csrc mie, %0" :: "r" (1u << 7));
	else
		timer->mtimecmp = timer->mtime + TIMER_INTERVAL;
}

int main() {

	irq_count = 0;
	__compiler_mb();
	// Per-IRQ enable for timer IRQ
	asm ("csrs mie, %0" :: "r" (1u << 7));
	tb_puts("Enabling IRQS...\n");
	// Global IRQ enable. Timer IRQ will fire immediately.
	asm ("csrsi mstatus, 0x8");

	// Count the number of sleep loop iterations to make sure the wfi waits
	int wait_spin_count;
	while (irq_count < MAX_IRQ_COUNT) {
		++wait_spin_count;
		__wfi();
		__compiler_mb();
	}

	tb_printf("Took %d IRQs, span %d times\n", irq_count, wait_spin_count);
	return irq_count != wait_spin_count + 1;
}
