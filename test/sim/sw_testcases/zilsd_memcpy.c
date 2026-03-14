#include "tb_cxxrtl_io.h"
#include "zilsd_macros.h"
#include <stdint.h>

// Test intent: basic coverage of ld and sd instructions in copy loops.
// Intended to be easy to debug.

#define BUF_WORDS 256

static inline uint32_t test_pattern(uint32_t i) {
	return (i + 1) * 0x07050301u;
}

// Loop 1: single ld, two sw
void __attribute__((naked)) copy1(__attribute__((unused)) void *dst, __attribute__((unused)) const void *src, __attribute__((unused)) uint32_t len) {
	asm volatile (
		"add a2, a2, a1\n"
		"bgeu a1, a2, 2f\n"
	"1:\n"
		"zilsd.ld x_a4, x_a1, 0\n"
		"sw a4, 0(a0)\n"
		"sw a5, 4(a0)\n"
		"addi a0, a0, 8\n"
		"addi a1, a1, 8\n"
		"bltu a1, a2, 1b\n"
	"2:\n"
		"ret\n"
	);
}


// Loop 2: two lw, single sd
void __attribute__((naked)) copy2(__attribute__((unused)) void *dst, __attribute__((unused)) const void *src, __attribute__((unused)) uint32_t len) {
	asm volatile (
		"add a2, a2, a1\n"
		"bgeu a1, a2, 2f\n"
	"1:\n"
		"lw a4, 0(a1)\n"
		"lw a5, 4(a1)\n"
		"zilsd.sd x_a4, x_a0, 0\n"
		"addi a0, a0, 8\n"
		"addi a1, a1, 8\n"
		"bltu a1, a2, 1b\n"
	"2:\n"
		"ret\n"
	);
}

// Loop 3: two ld, two sd (use some immediate bits)
void __attribute__((naked)) copy3(__attribute__((unused)) void *dst, __attribute__((unused)) const void *src, __attribute__((unused)) uint32_t len) {
	asm volatile (
		"add a2, a2, a1\n"
		"bgeu a1, a2, 2f\n"
	"1:\n"
		"zilsd.ld x_a4, x_a1, 0\n"
		"zilsd.ld x_a6, x_a1, 8\n"
		"zilsd.sd x_a4, x_a0, 0\n"
		"zilsd.sd x_a6, x_a0, 8\n"
		"addi a0, a0, 16\n"
		"addi a1, a1, 16\n"
		"bltu a1, a2, 1b\n"
	"2:\n"
		"ret\n"
	);
}


uint32_t buf0[BUF_WORDS];
uint32_t buf1[BUF_WORDS];

void init_zero(uint32_t *buf) {
	for (int i = 0; i < BUF_WORDS; ++i) {
		buf[i] = 0;
	}
}

void init_pattern(uint32_t *buf) {
	for (int i = 0; i < BUF_WORDS; ++i) {
		buf[i] = test_pattern(i);
	}
}

void check_pattern(uint32_t *buf) {
	for (int i = 0; i < BUF_WORDS; ++i) {
		tb_assert(
			buf[i] == test_pattern(i),
			"Failure at %08x: expected %08x, got %08x\n",
			(uintptr_t)&buf[i],
			test_pattern(i),
			buf[i]
		);
	}
}


typedef void (*copy_func_t)(void *, const void *, uint32_t);

void test_copy_func(copy_func_t func) {
	init_pattern(buf0);
	init_zero(buf1);
	func(buf1, buf0, sizeof(buf0));
	check_pattern(buf1);
}

int main(void) {
	tb_puts("Single ld\n");
	test_copy_func(copy1);
	tb_puts("Single sd\n");
	test_copy_func(copy2);
	tb_puts("Two ld, two sd\n");
	test_copy_func(copy3);
	return 0;
}
