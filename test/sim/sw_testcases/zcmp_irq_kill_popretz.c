#include "tb_cxxrtl_io.h"
#include "hazard3_irq.h"
#include <stdlib.h>

// Test intent: check that IRQs interrupting PC-setting phase of cm.popretz does
// not cause stack corruption. (This is not covered by zmp_irq_kill)

uint32_t __attribute__((naked)) foreground_task(uint32_t iters) {
	asm volatile (
		// Save sp and ra
		"addi sp, sp, -16\n"
		"sw s0, 0(sp)\n"
		"sw ra, 4(sp)\n"
		"mv s0, sp\n"
		// a0 is going to be trashed by the popretz, so use a different arg reg
		"mv a2, a0\n"
		"li a1, 0xf00b0000\n"
		// Short push + popret sequence
	"1:\n"
		"la ra, 2f\n"
		".hword 0xb852\n" // cm.push    {ra,s0},-16
		".hword 0xbc52\n" // cm.popretz {ra,s0}, 16
	"2:\n"
		// Check we haven't moved the stack pointer or lost our s0 contents
		"bne s0, sp, 3f\n"
		"addi a2, a2, -1\n"
		"addi a1, a1, 1\n"
		"bgtz a2, 1b\n"
		// Normal return -- we've been counting up in a1 as we count down in a2,
		// so return a1 to confirm we iterated the expected number of times
		"mv a0, a1\n"
		"lw s0, 0(sp)\n"
		"lw ra, 4(sp)\n"
		"addi sp, sp, 16\n"
		"ret\n"
	"3:\n"
		// Uh oh, either sp or s0 changed. Panic!
		"mv sp, s0\n"
		"j panic_sp_changed\n"
	);
}

void __attribute__((noreturn)) panic_sp_changed(void) {
	tb_puts("Stack pointer changed, that wasn't supposed to happen!\n");
	tb_exit(-1);
	__builtin_unreachable();
}

void __attribute__((interrupt)) isr_machine_timer(void) {
	unsigned int dwell = rand() % 301;
	mm_timer->mtimecmp = mm_timer->mtime + dwell;
}

int main() {
	tb_puts("Starting\n");
	timer_irq_enable(true);
	global_irq_enable(true);
	const uint32_t expected_iterations = 1000;
	tb_printf("Running %u iterations\n", expected_iterations);
	uint32_t result = foreground_task(expected_iterations);
	tb_printf("Result: %08x\n", result);
	tb_assert(result == 0xf00b0000u + expected_iterations, "Wrong number of iterations");

	return 0;
}

/*EXPECTED-OUTPUT***************************************************************
Starting
Running 1000 iterations
Result: f00b03e8
*******************************************************************************/
