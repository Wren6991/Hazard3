#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

#include <stdint.h>

// Test intent: check edge cases for instruction faults, particularly the
// flushing of speculative faults casued by fetching linearly past a jump
// instruction at the edge of a faulting region.

/*EXPECTED-OUTPUT***************************************************************

Case 1: Store-to-fetch delay slot
mcause = 00000000
Case 2: Store-to-fetch, with fence.i
mcause = 00000001
Case 3: flushed fault
mcause = 00000000
Case 4: flushed fault, from FIFO
mcause = 00000000

*******************************************************************************/

int main() {
	tb_printf("Case 1: Store-to-fetch delay slot\n");
	// Set poison_addr to the address of the next instruction, and check that
	// it does *not* fault since the prefetch buffer reorders the fetch
	// before the store. This is not required behaviour but it's a useful
	// sanity check before we really get into it with the following tests.
	write_csr(mcause, 0);
	asm volatile (
		"la a0, 99f\n"
		"csrw mtvec, a0\n"
		"la a0, 1f\n"
	".p2align 2\n"
		"nop\n" // for alignment
		"sw a0, (%0)\n"
	"1:\n"
		"nop\n"
		"nop\n"
	".p2align 2\n"
	"99:\n"
		"nop\n"
		:
		: "r" ((uintptr_t)&mm_io->poison_addr)
		: "a0"
	);
	// Should not have faulted (based on our understanding of our own
	// implementation, not based on architecture rules)
	tb_printf("mcause = %08x\n", read_csr(mcause));


	tb_printf("Case 2: Store-to-fetch, with fence.i\n");
	// Same as previous, but insert a fence.i to order the store before the
	// following fetch. In hardware terms this flushes the prefetch buffer,
	// triggering a re-fetch, which then faults.
	write_csr(mcause, 0);
	asm volatile (
		"la a0, 99f\n"
		"csrw mtvec, a0\n"
		"la a0, 1f\n"
	".p2align 2\n"
		"nop\n" // for alignment
		"sw a0, (%0)\n"
		"fence.i\n"
	"1:\n"
		"nop\n"
		"nop\n"
	".p2align 2\n"
	"99:\n"
		"nop\n"
		:
		: "r" ((uintptr_t)&mm_io->poison_addr)
		: "a0"
	);
	// Should fault
	tb_printf("mcause = %08x\n", read_csr(mcause));

	tb_printf("Case 3: flushed fault\n");
	// Instruction fetch runs ahead of decode and encounters a bus fault, but
	// the fault is flushed before it escalates to a trap.
	write_csr(mcause, 0);
	asm volatile (
		"la a0, 99f\n"
		"csrw mtvec, a0\n"
		"la a0, 1f\n"
		"sw a0, (%0)\n"
		"fence.i\n"
		".p2align 2\n"
		"j 99f\n"
		".p2align 2\n"
	"1:\n"
		".word 0x0\n"
		".p2align 2\n"
	"99:\n"
		"nop\n"
		:
		: "r" ((uintptr_t)&mm_io->poison_addr)
		: "a0"
	);
	tb_printf("mcause = %08x\n", read_csr(mcause));

	tb_printf("Case 4: flushed fault, from FIFO\n");
	// Same as previous, but issue a divide instruction to ensure the prefetch
	// FIFO backs up
	write_csr(mcause, 0);
	asm volatile (
		"la a0, 99f\n"
		"csrw mtvec, a0\n"
		"la a0, 1f\n"
		"sw a0, (%0)\n"
		"fence.i\n"
		".p2align 2\n"
#ifdef __riscv_m
		"divu a0, a0, a0\n"
#endif
		"j 99f\n"
		".p2align 2\n"
	"1:\n"
		".word 0x0\n"
		".p2align 2\n"
	"99:\n"
		"nop\n"
		:
		: "r" ((uintptr_t)&mm_io->poison_addr)
		: "a0"
	);
	tb_printf("mcause = %08x\n", read_csr(mcause));
}
