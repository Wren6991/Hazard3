#include "tb_cxxrtl_io.h"
#include "hazard3_irq.h"

// - Foreground code pends the top-half handler, at maximum priority
// - Each time the top-half handler is called, it installs a bottom half at
//   the next descending priority
// - Each bottom half hander re-pends the top half handler (which immediately
//   preempts it) to set the next lower-numbered bottom handler
// - When top returns to bottom, and that bottom returns to the *next* bottom,
//   which re-pends the top
// - So on until all handlers have fired
// - This should stack within two exception frames and enter the EIRQ vector
//   exactly 16 times (one for each time the top handler runs)

void handler_top() {
	static int next_bottom = MAX_PRIORITY - 1;
	tb_puts("Top\n");
	if (next_bottom >= 0) {
		h3irq_force_pending(next_bottom--, true);
	}
}

void handler_bottom() {
	int irqnum = h3irq_get_current_irq();
	tb_printf("Enter bottom %d\n", irqnum);
	h3irq_force_pending(MAX_PRIORITY, true);
	tb_printf("Exit bottom %d\n", irqnum);
}

int main() {
	global_irq_enable(true);
	external_irq_enable(true);

	// Set up one IRQ at each priority
	for (int i = 0; i <= MAX_PRIORITY; ++i) {
		h3irq_enable(i, true);
		h3irq_set_priority(i, i);
		h3irq_set_handler(i, i == MAX_PRIORITY ? handler_top : handler_bottom);
	}

	h3irq_force_pending(MAX_PRIORITY, true);

	tb_printf("EIRQ vector was entered %d times\n", _external_irq_entry_count);
	return 0;
}

/*EXPECTED-OUTPUT***************************************************************

Top
Enter bottom 14
Top
Exit bottom 14
Enter bottom 13
Top
Exit bottom 13
Enter bottom 12
Top
Exit bottom 12
Enter bottom 11
Top
Exit bottom 11
Enter bottom 10
Top
Exit bottom 10
Enter bottom 9
Top
Exit bottom 9
Enter bottom 8
Top
Exit bottom 8
Enter bottom 7
Top
Exit bottom 7
Enter bottom 6
Top
Exit bottom 6
Enter bottom 5
Top
Exit bottom 5
Enter bottom 4
Top
Exit bottom 4
Enter bottom 3
Top
Exit bottom 3
Enter bottom 2
Top
Exit bottom 2
Enter bottom 1
Top
Exit bottom 1
Enter bottom 0
Top
Exit bottom 0
EIRQ vector was entered 16 times

*******************************************************************************/
