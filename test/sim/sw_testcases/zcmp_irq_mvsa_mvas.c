#include "tb_cxxrtl_io.h"
#include "hazard3_irq.h"
#include <stdlib.h>

// Test intent: check that IRQs interrupting cm.mvsa01 and cm.mva01s do not
// observe any intermediate states that are disallowed by the ISA manual.
// These instructions expand to two movs, and an interrupt must not observe
// the state between the two movs. The Hazard3 implementation should allow
// the first expanded mov instruction to be interrupted, but not the second.

uint64_t __attribute__((naked)) foreground_task(uint32_t iters) {
	asm volatile (
		// Move the iters argument to a different areg, as a0/a1 are special
		// wrt cm.mv* instructions
		"mv a4, a0\n"
		"li a5, 0xf00b0000\n"
		// Save s regs which we're about to trash
		"addi sp, sp, -16\n"
		"sw s0, 0(sp)\n"
		"sw s1, 4(sp)\n"
		"sw s2, 8(sp)\n"
		"sw s3, 12(sp)\n"
		// Give each s reg a recognisable token in the upper half, containing
		// a-reg and s-reg index it will be found in:
		"li s0, 0xa0500000\n"
		"li s1, 0xa1510000\n"
		"li s2, 0xa0520000\n"
		"li s3, 0xa1530000\n"
		// Instructions under test: bounce both s-register pairs in and out of
		// a01, incrementing them each time. IRQs are disabled when
		// incrementing the two a registers, to avoid misdiagnosing this as
		// tearing of a cm.mva01s instruction.
	"1:\n"
	".rept 2\n"
		".hword 0xac66\n"      // cm.mva01s s0, s1
		"csrci mstatus, 0x8\n" // IRQs OFF
		"addi a0, a0, 1\n"
		"addi a1, a1, 1\n"
		"csrsi mstatus, 0x8\n" // IRQs ON
		".hword 0xac26\n"      // cm.mvsa01 s0, s1
		".hword 0xad6e\n"      // cm.mva01s s2, s3
		"csrci mstatus, 0x8\n" // IRQs OFF
		"addi a0, a0, 1\n"
		"addi a1, a1, 1\n"
		"csrsi mstatus, 0x8\n" // IRQs ON
		".hword 0xad2e\n"      // cm.mvsa01 s2, s3
	".endr\n"
		"addi a4, a4, -1\n"
		"addi a5, a5, 1\n"
		"bgtz a4, 1b\n"
		// Done. We've been counting up in a5 as we count down in a4, so
		// return a5 to confirm we iterated the expected number of times. a1
		// is also returned in a1 -- the lower half should be double the
		// iteration count.
		"csrci mstatus, 0x8\n" // IRQs OFF
		"mv a0, a5\n"
		"lw s0, 0(sp)\n"
		"lw s1, 4(sp)\n"
		"lw s2, 8(sp)\n"
		"lw s3, 12(sp)\n"
		"addi sp, sp, 16\n"
		"ret\n"
	);
}

void isr_machine_timer_c(uint32_t a0, uint32_t a1, uint32_t s0, uint32_t s1, uint32_t s2, uint32_t s3) {
	tb_assert((a0 & 0xffffu) == (a1 & 0xffffu), "Low-half tearing of a0,a1");
	tb_assert((s0 & 0xffffu) == (s1 & 0xffffu), "Low-half tearing of s0,s1");
	tb_assert((s2 & 0xffffu) == (s3 & 0xffffu), "Low-half tearing of s2,s3");
	unsigned int dwell = rand() % 301;
	mm_timer->mtimecmp = mm_timer->mtime + dwell;
}

// Trampoline into the actual ISR: make a0-1 and s0-3 *in the interrupted
// code* available as arguments.
void __attribute__((naked)) isr_machine_timer(void) {
	asm volatile (
		// Save all caller-saved regs
		"addi sp, sp, -80\n"
		"sw ra,  0(sp)\n"
		"sw t0,  4(sp)\n"
		"sw t1,  8(sp)\n"
		"sw t2, 12(sp)\n"
		"sw a0, 16(sp)\n"
		"sw a1, 20(sp)\n"
		"sw a2, 24(sp)\n"
		"sw a3, 28(sp)\n"
		"sw a4, 32(sp)\n"
		"sw a5, 36(sp)\n"
		"sw a6, 40(sp)\n"
		"sw a7, 44(sp)\n"
		"sw t3, 48(sp)\n"
		"sw t4, 52(sp)\n"
		"sw t5, 56(sp)\n"
		"sw t6, 60(sp)\n"
		// Pass first 4 s regs as arguments
		"mv a2, s0\n"
		"mv a3, s1\n"
		"mv a4, s2\n"
		"mv a5, s3\n"
		// Call actual IRQ, written in C
		"jal isr_machine_timer_c\n"
		// Restore caller saves, then return through mepc
		"lw ra,  0(sp)\n"
		"lw t0,  4(sp)\n"
		"lw t1,  8(sp)\n"
		"lw t2, 12(sp)\n"
		"lw a0, 16(sp)\n"
		"lw a1, 20(sp)\n"
		"lw a2, 24(sp)\n"
		"lw a3, 28(sp)\n"
		"lw a4, 32(sp)\n"
		"lw a5, 36(sp)\n"
		"lw a6, 40(sp)\n"
		"lw a7, 44(sp)\n"
		"lw t3, 48(sp)\n"
		"lw t4, 52(sp)\n"
		"lw t5, 56(sp)\n"
		"lw t6, 60(sp)\n"
		"addi sp, sp, 80\n"
		"mret\n"
	);
}


int main() {
	tb_puts("Starting\n");
	timer_irq_enable(true);
	// Note we do not globally enable IRQs, the code-under-test enables them
	// once it has set up the necessary register tokens
	const uint32_t expected_iterations = 1000;
	tb_printf("Running %u iterations\n", expected_iterations);
	uint64_t result_a1a0 = foreground_task(expected_iterations);
	uint32_t result_iters = result_a1a0 & 0xffffffffu;
	uint32_t result_a1ctr = result_a1a0 >> 32;
	tb_printf("Result: %08x %08x\n", result_iters, result_a1ctr);
	tb_assert(result_iters == 0xf00b0000u + expected_iterations, "Wrong number of iterations");
	tb_assert(result_a1ctr == (0xa1530000 + 2 * expected_iterations), "Wrong a1 counter value");
	return 0;
}

/*EXPECTED-OUTPUT***************************************************************
Starting
Running 1000 iterations
Result: f00b03e8 a15307d0
*******************************************************************************/
