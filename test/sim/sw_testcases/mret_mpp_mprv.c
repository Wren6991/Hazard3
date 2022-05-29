#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "pmp.h"

// Check MPRV is cleared when returning to U mode, but not when returning to M
// mode. Check that mret clears MPP, no matter which mode is returned to.

/*EXPECTED-OUTPUT***************************************************************

Enabling MPRV, with MPP=M
mret to M, check MPRV
mstatus   = 00020080  // mprv=1 mpp=U mpie=1
mret to M, check MPP affects load/store
mcause    = 7         // store fault
mstatus   = 00021880  // mprv=1 mpp=M mpie=1
mem[mepc] = c108
mret to U, check MPRV
mcause    = 1         // instr access fault
mstatus   = 00000080  // mprv=0 mpp=U mpie=1
mem[mepc] = 0001      // c.nop

*******************************************************************************/

volatile uint32_t scratch_word;

#define MPRV (1u << 17)
#define MPP (3u << 11)

extern void handle_exception();

int main() {
	// Leave PMP in default state (no U permissions).
	scratch_word = 0;

	tb_puts("Enabling MPRV, with MPP=M\n");
	set_csr(mstatus, MPP | MPRV);

	// Check that mret to M does not clear MPRV (also, opportunistically,
	// check that mret to M clears MPP)
	tb_puts("mret to M, check MPRV\n");
	write_csr(mtvec, (uintptr_t)&handle_exception);
	uint32_t mstatus_check;
	asm volatile (
		"la %0, 1f\n"
		"csrw mepc, %0\n"
		"mret\n"
		".p2align 2\n"
		"1:\n"
		// Note MPP is cleared by the MRET, so must be re-set immediately so
		// we can do load/stores again. We read out the current mstatus value
		// at the same time we modify it.
		"li %0, 0x1800\n"
		"csrrs %0, mstatus, %0\n"
		: "+r" (mstatus_check)
	);
	// MPP should be U. MPRV should still be set.
	tb_printf("mstatus   = %08x\n", mstatus_check);
	// The actual value of MPP is now M again, since we fixed it up.

	// Check that clearing of MPP upon mret immediately affects the
	// MPRV-modified load/store privilege level.
	tb_puts("mret to M, check MPP affects load/store\n");
	write_csr(mcause, 0);
	asm (
		"la a0, 1f\n"
		"csrw mepc, a0\n"
		"la a0, 2f\n"
		"csrw mtvec, a0\n"
		"la a0, scratch_word\n"
		"mret\n"
		".p2align 2\n"
		"1:\n"
		// We just executed a return from M mode to M mode, but our MPP was
		// cleared in the process, and our MPRV should still be set.
		// Therefore our effective load/store privilege is U:
		"c.sw a0, (a0)\n"
		// Catch the trap we just caused, and restore MPP to M.
		".p2align 2\n"
		"2:\n"
		"li a0, 0x1800\n"
		"csrs mstatus, a0\n"
		: : : "a0"
	);
	tb_printf("mcause    = %u\n", read_csr(mcause));
	tb_printf("mstatus   = %08x\n", read_csr(mstatus));
	tb_printf("mem[mepc] = %04x\n", *(uint16_t*)read_csr(mepc));

	// Check that mret to U (followed by trapping back to M, as we can't
	// actually check MPRV from U) *does* clear MPRV
	tb_puts("mret to U, check MPRV\n");
	asm (
		"la a0, 1f\n"
		"csrw mepc, a0\n"
		"csrw mtvec, a0\n"
		"li a0, 0x1800\n"
		"csrc mstatus, a0\n"
		"mret\n"
		".p2align 2\n"
		// We execute this address twice, first in U-mode then in M-mode:
		"1:\n"
		"c.nop\n"
		: : : "a0"
	);
	tb_printf("mcause    = %u\n", read_csr(mcause));
	tb_printf("mstatus   = %08x\n", read_csr(mstatus));
	tb_printf("mem[mepc] = %04x\n", *(uint16_t*)read_csr(mepc));
	tb_assert(read_csr(mepc) == read_csr(mtvec), "Should trap to same address that trapped\n");


	return 0;
}
