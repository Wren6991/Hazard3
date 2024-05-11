#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Check that U-mode execution of a wfi causes an illegal opcode exception if
// and only if the mstatus timeout wait bit is set.
//
// Also check that a U-mode WFI which fails PMP X check or TW=1 check does not
// stall the processor.

/*EXPECTED-OUTPUT***************************************************************

Do WFI with TW=0:
mcause = 8                            // = ecall, meaning normal exit.
Do WFI with TW=1:
mstatus = 00200000                    // Check TW write is reflected in readback
mcause = 2                            // = illegal instruction
Do WFI with TW=1, IRQs disabled:
mcause = 2                            // = illegal instruction
Do PMP-failed WFI, IRQs disabled:
mcause = 1                            // = instruction access fault.
Do PMP-failed WFI, IRQs enabled:
mcause = 1                            // = instruction access fault.

*******************************************************************************/

// Naked so the address can be checked
void __attribute__((naked)) do_wfi() {
	asm (
		"wfi\n"
		"ret\n"
	);;
}

void __attribute__((naked)) do_ecall() {
	asm ("ecall");
}

// /!\ Unconventional control flow ahead

// Call function in U mode, from M mode. Catch exception, or break back to M
// mode if the function returned normally (via dummy ecall), and then return.
static void __attribute__((naked)) umode_call_and_catch(void (*f)(void)) {
	(void)f;
	asm volatile (
		// Set up return-from-M-mode to U-mode at *f
		" csrw mepc, a0\n"
		" li a0, 0x1800\n"
		" csrc mstatus, a0\n"
		// Save ra, we will pick it up in handle_exception()
		" addi sp, sp, -16\n"
		" sw ra, (sp)\n"
		// Set up return to ecall if there is no other exception
		" la ra, do_ecall\n"
		// Enter function pointer
		" mret\n"
	);
}

void __attribute__((naked)) handle_exception(void) {
	asm volatile (
		// Pick up saved ra and return through it -- from the caller's pov we
		// have returned from umode_call_and_catch()
		" lw ra, (sp)\n"
		" addi sp, sp, 16\n"
		" ret\n"
	);
}

volatile bool timer_has_fired = false;
void __attribute__((interrupt)) isr_machine_timer(void) {
	timer_has_fired = true;
	mm_timer->mtimecmp = mm_timer->mtime + 100;
}

int main() {
	// Ensure WFI doesn't block by enabling timer IRQ but leaving IRQs globally disabled.
	// (They will still fire in U-mode, as mstatus.mie is treated as set when priv < M)
	set_csr(mie, -1u);

	// Give U mode RWX permission on all of memory.
	write_csr(pmpcfg0, 0x1fu);
	write_csr(pmpaddr0, -1u);

	tb_puts("Do WFI with TW=0:\n");
	tb_assert(!timer_has_fired, "Timer should not have fired whilst still in M-mode\n");
	umode_call_and_catch(&do_wfi);
	tb_assert(timer_has_fired, "Timer should have fired upon entering U-mode\n");
	tb_printf("mcause = %u\n", read_csr(mcause));
	if (read_csr(mepc) != (uint32_t)&do_ecall) {
		tb_puts("Non-normal return detected\n");
		return -1;
	}

	tb_puts("Do WFI with TW=1:\n");
	set_csr(mstatus, 1u << 21);
	tb_printf("mstatus = %08x\n", read_csr(mstatus));
	umode_call_and_catch(&do_wfi);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mepc) == (uint32_t)&do_wfi, "mepc doesn't point to wfi\n");

	tb_puts("Do WFI with TW=1, IRQs disabled:\n");
	// Disable IRQ sources so that WFI will stall forever
	write_csr(mie, 0);
	// This checks that setting TW stops the WFI state from being entered, as
	// well as just raising an exception.
	timer_has_fired = false;
	umode_call_and_catch(&do_wfi);
	tb_assert(!timer_has_fired, "Even in U-mode, timer should not fire when disabled.\n");
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mepc) == (uint32_t)&do_wfi, "mepc doesn't point to wfi\n");

	// This was broken at one point: WFI which failed X permission check would
	// still enter WFI halt state!
	tb_puts("Do PMP-failed WFI, IRQs disabled:\n");
	// Clear TW bit again
	clear_csr(mstatus, 1u << 21);
	// Revoke all U-mode PMP permissions
	write_csr(pmpcfg0, 0);
	umode_call_and_catch(&do_wfi);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mepc) == (uint32_t)&do_wfi, "mepc doesn't point to wfi\n");

	tb_puts("Do PMP-failed WFI, IRQs enabled:\n");
	// The expected sequence here is: return to U-mode, enter timer IRQ in
	// M-mode, return to U-mode again, take PMP fault back to M-mode.
	set_csr(mie, -1u);
	timer_has_fired = false;
	umode_call_and_catch(&do_wfi);
	tb_assert(timer_has_fired, "Timer should fire immediately on U-mode entry\n");
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mepc) == (uint32_t)&do_wfi, "mepc doesn't point to wfi\n");

	return 0;
}
