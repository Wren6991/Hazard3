#ifdef SPIKE
#include <stdio.h>
#include <stdint.h>
#define tb_puts(s) printf(s)
#define tb_put_u32(x) printf("%08x\n", x)
#else
#include "tb_cxxrtl_io.h"
#endif

// To get the full list of opcodes I assembled then disassembled this file:
//
// .set i, 0
// .rept 64
// .if (i & 0x3c) >= 16
// .hword 0xb802 | (i << 2)
// .endif
// .set i, i + 1
// .endr

#define FRAME_SIZE_WORDS 32
uint32_t test_frame[FRAME_SIZE_WORDS];

#define test_zcmp_push(instr, test_frame) \
	test_sp = &test_frame[FRAME_SIZE_WORDS];\
	tb_puts("Test: " instr "\n"); \
	tb_puts("Initial sp:\n"); \
	tb_put_u32((uint32_t)test_sp); \
	for (int i = 0; i < 32; ++i) test_frame[i] = 0xdead0000 + i; \
	asm volatile ( \
		/* Save all clobbered registers on the real stack */ \
		"_test_%=:\n" \
		"addi sp, sp, -64\n" \
		"sw x1,   0(sp)\n" \
		"sw x8,   4(sp)\n" \
		"sw x9,   8(sp)\n" \
		"sw x18, 12(sp)\n" \
		"sw x19, 16(sp)\n" \
		"sw x20, 20(sp)\n" \
		"sw x21, 24(sp)\n" \
		"sw x22, 28(sp)\n" \
		"sw x23, 32(sp)\n" \
		"sw x24, 36(sp)\n" \
		"sw x25, 40(sp)\n" \
		"sw x26, 44(sp)\n" \
		"sw x27, 48(sp)\n" \
		/* Save stack pointer and install test sp */ \
		"csrw mscratch, sp\n" \
		"mv sp, %0\n" \
		/* Give unique values to all registers that can be pushed */ \
		"li x1,  0xa5000000 + 1\n" \
		"li x8,  0xa5000000 + 8\n" \
		"li x9,  0xa5000000 + 9\n" \
		"li x18, 0xa5000000 + 18\n" \
		"li x19, 0xa5000000 + 19\n" \
		"li x20, 0xa5000000 + 20\n" \
		"li x21, 0xa5000000 + 21\n" \
		"li x22, 0xa5000000 + 22\n" \
		"li x23, 0xa5000000 + 23\n" \
		"li x24, 0xa5000000 + 24\n" \
		"li x25, 0xa5000000 + 25\n" \
		"li x26, 0xa5000000 + 26\n" \
		"li x27, 0xa5000000 + 27\n" \
		/* Let's go */ \
		instr "\n" \
		/* Updated test sp is returned  */ \
		"mv a0, sp\n" \
		/* Restore original sp, and clobbered registers */ \
		"csrr sp, mscratch\n" \
		"lw x1,   0(sp)\n" \
		"lw x8,   4(sp)\n" \
		"lw x9,   8(sp)\n" \
		"lw x18, 12(sp)\n" \
		"lw x19, 16(sp)\n" \
		"lw x20, 20(sp)\n" \
		"lw x21, 24(sp)\n" \
		"lw x22, 28(sp)\n" \
		"lw x23, 32(sp)\n" \
		"lw x24, 36(sp)\n" \
		"lw x25, 40(sp)\n" \
		"lw x26, 44(sp)\n" \
		"lw x27, 48(sp)\n" \
		"addi sp, sp, 64\n" \
		"mv %0, a0\n" \
		: "+r"(test_sp) : : "a0"\
	); \
	tb_puts("Final sp:\n"); \
	tb_put_u32((uint32_t)test_sp); \
	tb_puts("Frame data\n"); \
	for (int i = 0; i < FRAME_SIZE_WORDS; ++i) tb_put_u32(test_frame[i]); \
	tb_puts("\n");

int main() {
	volatile uint32_t *test_sp;
	test_zcmp_push("cm.push {ra},-16"         , test_frame);
	test_zcmp_push("cm.push {ra},-32"         , test_frame);
	test_zcmp_push("cm.push {ra},-48"         , test_frame);
	test_zcmp_push("cm.push {ra},-64"         , test_frame);
	test_zcmp_push("cm.push {ra,s0},-16"      , test_frame);
	test_zcmp_push("cm.push {ra,s0},-32"      , test_frame);
	test_zcmp_push("cm.push {ra,s0},-48"      , test_frame);
	test_zcmp_push("cm.push {ra,s0},-64"      , test_frame);
	test_zcmp_push("cm.push {ra,s0-s1},-16"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s1},-32"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s1},-48"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s1},-64"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s2},-16"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s2},-32"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s2},-48"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s2},-64"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s3},-32"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s3},-48"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s3},-64"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s3},-80"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s4},-32"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s4},-48"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s4},-64"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s4},-80"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s5},-32"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s5},-48"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s5},-64"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s5},-80"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s6},-32"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s6},-48"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s6},-64"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s6},-80"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s7},-48"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s7},-64"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s7},-80"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s7},-96"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s8},-48"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s8},-64"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s8},-80"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s8},-96"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s9},-48"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s9},-64"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s9},-80"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s9},-96"   , test_frame);
	test_zcmp_push("cm.push {ra,s0-s11},-64"  , test_frame);
	test_zcmp_push("cm.push {ra,s0-s11},-80"  , test_frame);
	test_zcmp_push("cm.push {ra,s0-s11},-96"  , test_frame);
	test_zcmp_push("cm.push {ra,s0-s11},-112" , test_frame);

	return 0;
}

/*EXPECTED-OUTPUT***************************************************************

*******************************************************************************/
