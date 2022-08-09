#include "tb_cxxrtl_io.h"
#include "hazard3_irq.h"

/*EXPECTED-OUTPUT***************************************************************

Posting first IRQ
Entered IRQ 0
Entered IRQ 1
Entered IRQ 2
Entered IRQ 3
Entered IRQ 4
Entered IRQ 5
Entered IRQ 6
Entered IRQ 7
Entered IRQ 8
Entered IRQ 9
Entered IRQ 10
Entered IRQ 11
Entered IRQ 12
Entered IRQ 13
Entered IRQ 14
Entered IRQ 15
Exiting IRQ 15
Exiting IRQ 14
Exiting IRQ 13
Exiting IRQ 12
Exiting IRQ 11
Exiting IRQ 10
Exiting IRQ 9
Exiting IRQ 8
Exiting IRQ 7
Exiting IRQ 6
Exiting IRQ 5
Exiting IRQ 4
Exiting IRQ 3
Exiting IRQ 2
Exiting IRQ 1
Exiting IRQ 0
EIRQ vector was entered 16 times

*******************************************************************************/

#define MAX_PRIORITY 15

void handler(void);

int main() {
	global_irq_enable(true);
	external_irq_enable(true);
	// Enable one external IRQ at each priority level
	for (int i = 0; i <= MAX_PRIORITY; ++i) {
		h3irq_enable(i, true);
		h3irq_set_priority(i, i);
		h3irq_set_handler(i, handler);
	}
	// Set off the lowest-priority IRQ. The IRQ handler will then set the
	// next-lowest, which will preempt it. So on, up to the highest level,
	// then return all the way back down through the nested frames.
	tb_puts("Posting first IRQ\n");
	tb_set_irq_masked(0x1);
	asm ("wfi");

	tb_printf("EIRQ vector was entered %d times\n", _external_irq_entry_count);
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
