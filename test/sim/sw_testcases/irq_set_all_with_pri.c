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
Entered IRQ 30
Entered IRQ 31
Entered IRQ 28
Entered IRQ 29
Entered IRQ 26
Entered IRQ 27
Entered IRQ 24
Entered IRQ 25
Entered IRQ 22
Entered IRQ 23
Entered IRQ 20
Entered IRQ 21
Entered IRQ 18
Entered IRQ 19
Entered IRQ 16
Entered IRQ 17
Entered IRQ 14
Entered IRQ 15
Entered IRQ 12
Entered IRQ 13
Entered IRQ 10
Entered IRQ 11
Entered IRQ 8
Entered IRQ 9
Entered IRQ 6
Entered IRQ 7
Entered IRQ 4
Entered IRQ 5
Entered IRQ 2
Entered IRQ 3
Entered IRQ 0
Entered IRQ 1
EIRQ vector was entered 1 times

*******************************************************************************/

#define PRIORITY_LEVELS (MAX_PRIORITY + 1)

void handler(void);

int main() {
	global_irq_enable(true);
	external_irq_enable(true);
	// Enable one external IRQ at each priority level
	for (int i = 0; i < PRIORITY_LEVELS * 2; ++i) {
		h3irq_enable(i, true);
		h3irq_set_priority(i, i / 2);
		h3irq_set_handler(i, handler);
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
}
