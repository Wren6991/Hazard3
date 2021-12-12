#ifndef _AMO_OUTLINE_H
#define _AMO_OUTLINE_H

// "what if -moutline-atomics but manually" (abusing calling convention to get
//  stable register allocation, since we may log these instructions to
//  confirm mepc

static uint32_t __attribute__((naked, noinline)) amoswap(uint32_t val, uint32_t *addr) {
	asm volatile (
		"amoswap.w a0, a0, (a1)\n"
		"ret\n"
	);
}

static uint32_t __attribute__((naked, noinline)) amoadd(uint32_t val, uint32_t *addr) {
	asm volatile (
		"amoadd.w a0, a0, (a1)\n"
		"ret\n"
	);
}

static uint32_t __attribute__((naked, noinline)) amoxor(uint32_t val, uint32_t *addr) {
	asm volatile (
		"amoxor.w a0, a0, (a1)\n"
		"ret\n"
	);
}

static uint32_t __attribute__((naked, noinline)) amoand(uint32_t val, uint32_t *addr) {
	asm volatile (
		"amoand.w a0, a0, (a1)\n"
		"ret\n"
	);
}

static uint32_t __attribute__((naked, noinline)) amoor(uint32_t val, uint32_t *addr) {
	asm volatile (
		"amoor.w a0, a0, (a1)\n"
		"ret\n"
	);
}

static uint32_t __attribute__((naked, noinline)) amomin(uint32_t val, uint32_t *addr) {
	asm volatile (
		"amomin.w a0, a0, (a1)\n"
		"ret\n"
	);
}

static uint32_t __attribute__((naked, noinline)) amomax(uint32_t val, uint32_t *addr) {
	asm volatile (
		"amomax.w a0, a0, (a1)\n"
		"ret\n"
	);
}

static uint32_t __attribute__((naked, noinline)) amominu(uint32_t val, uint32_t *addr) {
	asm volatile (
		"amominu.w a0, a0, (a1)\n"
		"ret\n"
	);
}

static uint32_t __attribute__((naked, noinline)) amomaxu(uint32_t val, uint32_t *addr) {
	asm volatile (
		"amomaxu.w a0, a0, (a1)\n"
		"ret\n"
	);
}

#endif
