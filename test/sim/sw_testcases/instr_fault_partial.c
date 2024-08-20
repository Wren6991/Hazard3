#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

#include <stdint.h>

// Test intent: check we get instruction faults for non-naturally-aligned
// 32-bit fetches where only one half of the fetch encountered a bus error.

/*EXPECTED-OUTPUT***************************************************************

Case 1: overlap with fault (before)
mcause = 00000001
Case 2: overlap with fault (after)
mcause = 00000001

*******************************************************************************/

int main() {
	
	tb_printf("Case 1: overlap with fault (before)\n");
	// Execute a 32-bit-sized 16-bit-aligned instruction, with a fetch fault
	// on the second half (only).
	write_csr(mcause, 0);
	asm volatile (
		"la a0, 99f\n"
		"csrw mtvec, a0\n"
		"la a0, 1f\n"
		// poison starts halfway through 32-bit opcode:
		"addi a0, a0, 4\n"
		"sw a0, (%0)\n"
		"fence.i\n"
	".p2align 2\n"
	"1:\n"
		"nop\n"
	".option push\n"
	".option norvc\n"
		// poison on second half of this instruction:
		"j 99f\n"
	".option pop\n"
	".p2align 2\n"
	"99:\n"
		"nop\n"
		:
		: "r" ((uintptr_t)&mm_io->poison_addr)
		: "a0"
	);
	// Should fault because part of the fetch of the 32-bit j instruction
	// failed.
	tb_printf("mcause = %08x\n", read_csr(mcause));

	tb_printf("Case 2: overlap with fault (after)\n");
	// Execute a 32-bit-sized 16-bit-aligned instruction, with a fetch fault
	// on the first half (only).
	write_csr(mcause, 0);
	asm volatile (
		"la a0, 99f\n"
		"csrw mtvec, a0\n"
		"la a0, 1f\n"
		"sw a0, (%0)\n"
		"fence.i\n"
		"j 2f\n"
	".p2align 2\n"
	// poison starts here
	"1:\n"
		"nop\n"
	".option push\n"
	".option norvc\n"
	"2:\n"
		// poison on first half of this instruction:
		"j 99f\n"
	".option pop\n"
	".p2align 2\n"
	"99:\n"
		"nop\n"
		:
		: "r" ((uintptr_t)&mm_io->poison_addr)
		: "a0"
	);
	// Should fault because part of the fetch of the 32-bit j instruction
	// failed.
	tb_printf("mcause = %08x\n", read_csr(mcause));

}
