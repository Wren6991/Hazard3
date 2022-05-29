#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "pmp.h"

// Check that PMP enforces U-mode read/write permissions in M-mode, if both
// MPRV=1 and MPP=U.
//
// Check that this does not affect execute permissions.

/*EXPECTED-OUTPUT***************************************************************

Enabling MPRV, with MPP=M
Set MPP=U, then read memory
mcause    = 5         // load fault
mstatus   = 00021800  // mprv=1 mpp=M
mem[mepc] = 4108      // c.lw
Set MPP=U, then write memory
mcause    = 7         // store fault
mstatus   = 00021800  // mprv=1 mpp=M
mem[mepc] = c108      // c.sw

*******************************************************************************/

volatile uint32_t scratch_word;

#define MPRV (1u << 17)
#define MPP (3u << 11)

int main() {
	// Leave PMP in default state (no U permissions).
	scratch_word = 0;

	tb_puts("Enabling MPRV, with MPP=M\n");
	set_csr(mstatus, MPP | MPRV);
	// Effective privilege is still M mode, so we can do whatever we want. Go
	// nuts. Read and write some memory.
	scratch_word = 0x12345678u;
	tb_assert(scratch_word == 0x12345678u, "Bad readback somehow\n");

	write_csr(mcause, 0);
	write_csr(mepc, 0);

	tb_puts("Set MPP=U, then read memory\n");
	asm (
		"la a0, 1f\n"
		"csrw mtvec, a0\n"
		"la a0, scratch_word\n"
		"li a1, 0x1800\n"

		// Note the nop is to check that we have not lost X permissions. The
		// trap should come from the lw.
		"csrc mstatus, a1\n"
		"nop\n"
		"c.lw a0, (a0)\n"

		".p2align 2\n"
		"1:"
		: : : "a0", "a1"
	);
	// We should have instantly trapped, and set MPP back to M upon trapping,
	// restoring read/write permissions.
	tb_printf("mcause    = %u\n", read_csr(mcause));
	tb_printf("mstatus   = %08x\n", read_csr(mstatus));
	tb_printf("mem[mepc] = %04x\n", *(uint16_t*)read_csr(mepc));

	// Same trick but writes. We should get a different mcause value.
	tb_puts("Set MPP=U, then write memory\n");
	asm (
		"la a0, 1f\n"
		"csrw mtvec, a0\n"
		"la a0, scratch_word\n"
		"li a1, 0x1800\n"

		"csrc mstatus, a1\n"
		"nop\n"
		"c.sw a0, (a0)\n"

		".p2align 2\n"
		"1:"
		: : : "a0", "a1"
	);
	tb_printf("mcause    = %u\n", read_csr(mcause));
	tb_printf("mstatus   = %08x\n", read_csr(mstatus));
	tb_printf("mem[mepc] = %04x\n", *(uint16_t*)read_csr(mepc));

	return 0;
}
