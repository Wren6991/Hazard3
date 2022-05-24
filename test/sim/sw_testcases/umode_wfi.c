#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Check that U-mode execution of a wfi causes an illegal opcode exception if
// and only if the mstatus timeout wait bit is set.

/*EXPECTED-OUTPUT***************************************************************

Do WFI with TW=0:
mcause = 11        // = ecall, meaning normal exit. The test also checks mepc.
Do WFI with TW=1:
mstatus = 00200000 // Check TW write is reflected in readback
mcause = 2         // = illegal instruction. The test also checks mepc.

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
// mode if the function returned normally, and then return.
static inline void umode_call_and_catch(void (*f)(void)) {
	clear_csr(mstatus, 0x1800u);
	write_csr(mepc, f);
	uint32_t mtvec_save = read_csr(mtvec);
	asm (
		" la ra, 1f\n"
		" csrw mtvec, ra\n"
		" la ra, do_ecall\n"
		" mret\n"
		// Note mtvec requires 4-byte alignment.
		".p2align 2\n"
		"1:\n"
	: : : "ra"
	);
	write_csr(mtvec, mtvec_save);
}

int main() {
	// Ensure WFI doesn't block by enabling timer IRQ but leaving IRQs globally disabled.
	set_csr(mie, -1u);

	// Give U mode RWX permission on all of memory.
	write_csr(pmpcfg0, 0x1fu);
	write_csr(pmpaddr0, -1u);

	tb_puts("Do WFI with TW=0:\n");
	umode_call_and_catch(&do_wfi);
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
	if (read_csr(mepc) != (uint32_t)&do_wfi) {
		tb_puts("mepc doesn't point to wfi\n");
		return -1;
	}

	return 0;
}
