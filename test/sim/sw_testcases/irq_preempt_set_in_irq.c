#include "tb_cxxrtl_io.h"
#include "hazard3_irq.h"

#define MAX_PRIORITY 15
#define NUM_IRQS 64

extern uintptr_t _external_irq_table[NUM_IRQS];

void handler(void);

int main() {
	// Enable external IRQs globally
	set_csr(mstatus, 0x8);
	set_csr(mie, 0x800);
	// Enable one external IRQ at each priority level
	for (int i = 0; i <= MAX_PRIORITY; ++i) {
		h3irq_enable(i, true);
		h3irq_set_priority(i, i);
		_external_irq_table[i] = (uintptr_t)handler;
	}
	// Set off the lowest-priority IRQ. The IRQ handler will then set the
	// next-lowest, which will preempt it. So on, up to the highest level,
	// then return all the way back down through the nested frames.
	tb_puts("Posting first IRQ\n");
	tb_set_irq_masked(0x1);
	asm ("wfi");

	tb_puts("Done.\n");
	return 0;
}

void handler(void) {
	int irqnum = h3irq_get_current_irq();
	tb_printf("Entered IRQ %d\n", irqnum);
	if (irqnum < MAX_PRIORITY)
		tb_set_irq_masked(1u << (irqnum + 1));
	// !!! Get preempted here
	tb_clr_irq_masked(1u << irqnum);
	// Make sure context save/restore tracks as expected:
	irqnum = h3irq_get_current_irq();
	tb_printf("Exiting IRQ %d\n", irqnum);
}
