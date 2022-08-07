#include "tb_cxxrtl_io.h"
#include "hazard3_irq.h"

// Similar to the irq_preempt_set_in_irq test, but there are two IRQs at each
// priority level, and rather than posting the high-priority IRQs from within
// lower priority IRQs, we post every single IRQ at once. Check that:
//
// - The IRQS run from highest to lowest priority order (which happens to be
//   opposite to the default tiebreak order for these IRQs)
//
// - Within each priority level, the IRQs are tiebroken lowest-first
//
// - Each IRQ enters and exits before any lower IRQ enters
//
// - The EIRQ vector was entered exactly once (save/restore was shared between
//   all the IRQs at their different priority levels)

/*EXPECTED-OUTPUT***************************************************************

Posting IRQs
Entered IRQ 15
Exiting IRQ 15
Entered IRQ 14
Exiting IRQ 14
Entered IRQ 13
Exiting IRQ 13
Entered IRQ 12
Exiting IRQ 12
Entered IRQ 11
Exiting IRQ 11
Entered IRQ 10
Exiting IRQ 10
Entered IRQ 9
Exiting IRQ 9
Entered IRQ 8
Exiting IRQ 8
Entered IRQ 7
Exiting IRQ 7
Entered IRQ 6
Exiting IRQ 6
Entered IRQ 5
Exiting IRQ 5
Entered IRQ 4
Exiting IRQ 4
Entered IRQ 3
Exiting IRQ 3
Entered IRQ 2
Exiting IRQ 2
Entered IRQ 1
Exiting IRQ 1
Entered IRQ 0
Exiting IRQ 0
EIRQ vector was entered 1 times
gstat
*******************************************************************************/

#define PRIORITY_LEVELS 16
#define NUM_IRQS 32

extern uintptr_t _external_irq_table[NUM_IRQS];
extern uint32_t _external_irq_entry_count;

void handler(void);

int main() {
	// Enable external IRQs globally
	set_csr(mstatus, 0x8);
	set_csr(mie, 0x800);
	// Enable one external IRQ at each priority level
	for (int i = 0; i < PRIORITY_LEVELS * 2; ++i) {
		h3irq_enable(i, true);
		h3irq_set_priority(i, i / 2);
		_external_irq_table[i] = (uintptr_t)handler;
	}
	// Set off the lowest-priority IRQ. The IRQ handler will then set the
	// next-lowest, which will preempt it. So on, up to the highest level,
	// then return all the way back down through the nested frames.
	tb_puts("Posting IRQs\n");
	tb_set_irq_masked(0xffffffffu);
	asm ("wfi");

	tb_printf("EIRQ vector was entered %d times\n", _external_irq_entry_count);
	return 0;
}

void handler(void) {
	int irqnum = h3irq_get_current_irq();
	tb_printf("Entered IRQ %d\n", irqnum);
	tb_clr_irq_masked(1u << irqnum);
	tb_printf("Exiting IRQ %d\n", irqnum);
}
