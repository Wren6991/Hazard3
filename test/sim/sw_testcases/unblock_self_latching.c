#include "tb_cxxrtl_io.h"
#include "hazard3_instr.h"
#include "hazard3_csr.h"
#include <stdbool.h>

// In the single core testbench, the unblock_out signal is just looped back to
// unblock_in. Use this to confirm that the unblock is latching, i.e. an
// earlier unblock will cause the next block to fall through immediately.
//
// Also check that a block *without* an earlier unblock will timeout. Testing
// of unblock-while-blocked needs two processors.

/*EXPECTED-OUTPUT***************************************************************

Test 1: block without prior unblock
Timed out
Test 2: block with prior unblock
Unblocked
Test 3: block without prior unblock, again
Timed out
Test 4: unblock, wfi, block
Unblocked

*******************************************************************************/

void set_timer_wfi_timeout(unsigned int t) {
	// Use the machine timer to wake if the block instruction gets stuck. This
	// relies on the fact that WFI wake respects the individual IRQ enables
	// in mie, but ignores mstatus.mie, so we can use the timer to wake
	// without getting an interrupt.
	clear_csr(mstatus, 0x8);
	set_csr(mie, 0x80);

	// Set timer in future, and ensure the pending bit has cleared (may not be immediate)
	mm_timer->mtimecmp = mm_timer->mtime + 1000;
	while (read_csr(mip) & 0x80)
		;
}

bool block_with_timeout() {
	set_timer_wfi_timeout(1000);
	__hazard3_block();
	bool timed_out = !!(read_csr(mip) & 0x80);
	clear_csr(mie, 0x80);
	return timed_out;
}

int main() {
	tb_puts("Test 1: block without prior unblock\n");
	tb_puts(block_with_timeout() ? "Timed out\n" : "Unblocked\n");

	// Make sure the unblock latch sets.
	tb_puts("Test 2: block with prior unblock\n");
	__hazard3_unblock();
	tb_puts(block_with_timeout() ? "Timed out\n" : "Unblocked\n");

	// Make sure the unblock latch clears
	tb_puts("Test 3: block without prior unblock, again\n");
	tb_puts(block_with_timeout() ? "Timed out\n" : "Unblocked\n");

	// Make sure a WFI does not clear the latch
	tb_puts("Test 4: unblock, wfi, block\n");
	__hazard3_unblock();
	set_timer_wfi_timeout(1000);
	asm ("wfi");
	clear_csr(mie, 0x80);
	tb_puts(block_with_timeout() ? "Timed out\n" : "Unblocked\n");

	return 0;
}
