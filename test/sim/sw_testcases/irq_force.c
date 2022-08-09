#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "hazard3_irq.h"

// Fire all IRQs simultaneously, and log the resulting handler calls

#define mie_meie 0x800u

void handler(void);

int main() {
	tb_assert(NUM_IRQS <= 32, "Test invalid for >32 IRQs");
	global_irq_enable(true);
	external_irq_enable(true);
	// Dry run: Check that IRQ force array can be written/read and that it
	// sets the pending array appropriately
	for (int i = 0; i < NUM_IRQS; ++i) {
		h3irq_force_pending(i, true);
		uint32_t expect_pending = i == 31 ? 0xffffffffu : (1u << (i + 1)) - 1;
		tb_assert(
			expect_pending == (
				h3irq_array_read(hazard3_csr_meifa, 0) |
				(h3irq_array_read(hazard3_csr_meifa, 1) << 16)
			),
			"Bad meifa readback\n"
		);
		tb_assert(
			expect_pending == (
				h3irq_array_read(hazard3_csr_meipa, 0) |
				(h3irq_array_read(hazard3_csr_meipa, 1) << 16)
			),
			"Bad meipa readback\n"
		);
	}
	for (int i = 0; i < NUM_IRQS; ++i) {
		h3irq_force_pending(i, false);
	}
	tb_assert(h3irq_array_read(hazard3_csr_meifa, 0) == 0, "Failed to clear meifa\n");
	tb_assert(h3irq_array_read(hazard3_csr_meifa, 1) == 0, "Failed to clear meifa\n");
	tb_assert(h3irq_array_read(hazard3_csr_meipa, 0) == 0, "Failed to clear meipa\n");
	tb_assert(h3irq_array_read(hazard3_csr_meipa, 1) == 0, "Failed to clear meipa\n");

	// Now fire each interrupt for real and make sure that the meinext read
	// clears the force bit as it should, so that each interrupt fires
	// exactly once.
	for (int i = 0; i < NUM_IRQS; ++i) {
		h3irq_enable(i, true);
		h3irq_set_handler(i, handler);
	}

	h3irq_array_write(hazard3_csr_meifa, 0, 0xffffu);
	h3irq_array_write(hazard3_csr_meifa, 1, 0xffffu);

	while (h3irq_pending(31))
		;
	tb_printf("EIRQ vector entered %d times\n", _external_irq_entry_count);

	return 0;
}

void handler(void) {
	tb_printf("IRQ %02x\n", h3irq_get_current_irq());
}

/*EXPECTED-OUTPUT***************************************************************

IRQ 00
IRQ 01
IRQ 02
IRQ 03
IRQ 04
IRQ 05
IRQ 06
IRQ 07
IRQ 08
IRQ 09
IRQ 0a
IRQ 0b
IRQ 0c
IRQ 0d
IRQ 0e
IRQ 0f
IRQ 10
IRQ 11
IRQ 12
IRQ 13
IRQ 14
IRQ 15
IRQ 16
IRQ 17
IRQ 18
IRQ 19
IRQ 1a
IRQ 1b
IRQ 1c
IRQ 1d
IRQ 1e
IRQ 1f
EIRQ vector entered 2 times

*******************************************************************************/
