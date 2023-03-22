#include "tb_cxxrtl_io.h"

// Test intent: check that killing and restarting of push/pop instructions
// due to IRQs does not cause stack corruption

volatile uint32_t results[13];

void foreground_task() {
	asm volatile (
		// First push is an actual save of the registers
		".hword 0xb8f6\n" // cm.push {ra,s0-s11},-80
		"sw a0, 0(sp)\n"
		"sw a1, 4(sp)\n"
		"li a1, 13 * 100\n"
		"li x1,  0xa5000000 + 1\n"
		"li x8,  0xa5000000 + 8\n"
		"li x9,  0xa5000000 + 9\n"
		"li x18, 0xa5000000 + 18\n"
		"li x19, 0xa5000000 + 19\n"
		"li x20, 0xa5000000 + 20\n"
		"li x21, 0xa5000000 + 21\n"
		"li x22, 0xa5000000 + 22\n"
		"li x23, 0xa5000000 + 23\n"
		"li x24, 0xa5000000 + 24\n"
		"li x25, 0xa5000000 + 25\n"
		"li x26, 0xa5000000 + 26\n"
		"li x27, 0xa5000000 + 27\n"
		"1:\n"
		".hword 0xb8f2\n" // cm.push {ra,s0-s11},-64
		// Rotate the contents of the stack frame
		"lw s0,  12(sp)\n"
		"lw s1,  16(sp)\n"
		"lw s2,  20(sp)\n"
		"lw s3,  24(sp)\n"
		"lw s4,  28(sp)\n"
		"lw s5,  32(sp)\n"
		"lw s6,  36(sp)\n"
		"lw s7,  40(sp)\n"
		"lw s8,  44(sp)\n"
		"lw s9,  48(sp)\n"
		"lw s10, 52(sp)\n"
		"lw s11, 56(sp)\n"
		"lw a0,  60(sp)\n"

		"lw a0,  12(sp)\n"
		"lw s0,  16(sp)\n"
		"lw s1,  20(sp)\n"
		"lw s2,  24(sp)\n"
		"lw s3,  28(sp)\n"
		"lw s4,  32(sp)\n"
		"lw s5,  36(sp)\n"
		"lw s6,  40(sp)\n"
		"lw s7,  44(sp)\n"
		"lw s8,  48(sp)\n"
		"lw s9,  52(sp)\n"
		"lw s10, 56(sp)\n"
		"lw s11, 60(sp)\n"
		// Re-pop. Doing this a multiple of 13 times will restore the original contents.
		".hword 0xbaf2\n" // cm.pop {ra, s0-s11},64
		"addi a1, a1, -1\n"
		"bnez a1, 1b\n"
		// Write out results
		"la a1, results\n"
		"sw x1,  4*0(a1)\n"
		"sw x8,  4*1(a1)\n"
		"sw x9,  4*2(a1)\n"
		"sw x18, 4*3(a1)\n"
		"sw x19, 4*4(a1)\n"
		"sw x20, 4*5(a1)\n"
		"sw x21, 4*6(a1)\n"
		"sw x22, 4*7(a1)\n"
		"sw x23, 4*8(a1)\n"
		"sw x24, 4*9(a1)\n"
		"sw x25, 4*10(a1)\n"
		"sw x26, 4*11(a1)\n"
		"sw x27, 4*12(a1)\n"
		// Restore original register values
		"lw a0, 0(sp)\n"
		"lw a1, 4(sp)\n"
		".hword 0xbaf6\n" // cm.pop {ra,s0-s11},80
	);
}

// Note not using attribute interrupt due to stack corruption bug in current
// CORE-V toolchain
void __attribute__((naked)) isr_machine_timer() {
	asm volatile (
		".hword 0xb852\n"  // cm.push {ra,s0},-16
		"li ra, %0\n"
		"lw s0, (ra)\n"
		"addi s0, s0, 421\n"   // Prime number
		"sw s0, (ra)\n"
		".hword 0xba52\n"  // cm.pop {ra,s0},16
		"mret\n"
		: : "i" ((uintptr_t)&mm_timer->mtimecmp)
	);
}

int main() {
	asm volatile ("csrw mie, %0" : : "r" (0x80));
	mm_timer->mtime = 0;
	// Will take first timer interrupt immediately:
	asm volatile ("csrsi mstatus, 0x8");

	foreground_task();
	for (int i = 0; i < 13; ++i) {
		tb_put_u32(results[i]);
	}
	return 0;
}

/*EXPECTED-OUTPUT***************************************************************

a5000001
a5000008
a5000009
a5000012
a5000013
a5000014
a5000015
a5000016
a5000017
a5000018
a5000019
a500001a
a500001b

*******************************************************************************/
