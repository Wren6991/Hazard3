#ifndef _TB_CXXRTL_IO_H
#define _TB_CXXRTL_IO_H

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

// ----------------------------------------------------------------------------
// Testbench IO hardware layout

#define IO_BASE 0x80000000

typedef struct {
	volatile uint32_t print_char;
	volatile uint32_t print_u32;
	volatile uint32_t exit;
	uint32_t _pad0;
	volatile uint32_t set_softirq;
	volatile uint32_t clr_softirq;
	volatile uint32_t globmon_en;
	uint32_t _pad1[1];
	volatile uint32_t set_irq;
	uint32_t _pad2[3];
	volatile uint32_t clr_irq;
	uint32_t _pad3[3];
} io_hw_t;

#define mm_io ((io_hw_t *const)IO_BASE)

typedef struct {
	volatile uint32_t mtime;
	volatile uint32_t mtimeh;
	volatile uint32_t mtimecmp;
	volatile uint32_t mtimecmph;
} timer_hw_t;

#define mm_timer ((timer_hw_t *const)(IO_BASE + 0x100))

// ----------------------------------------------------------------------------
// Testbench IO convenience functions

static inline void tb_putc(char c) {
	mm_io->print_char = (uint32_t)c;
}

static inline void tb_puts(const char *s) {
	while (*s)
		tb_putc(*s++);
}

static inline void tb_put_u32(uint32_t x) {
	mm_io->print_u32 = x;
}

static inline void tb_exit(uint32_t ret) {
	mm_io->exit = ret;
}

#ifndef PRINTF_BUF_SIZE
#define PRINTF_BUF_SIZE 256
#endif

static inline void tb_printf(const char *fmt, ...) {
	char buf[PRINTF_BUF_SIZE];
	va_list args;
	va_start(args, fmt);
	vsnprintf(buf, PRINTF_BUF_SIZE, fmt, args);
	tb_puts(buf);
	va_end(args);
}

#define tb_assert(cond, ...) if (!(cond)) {tb_printf(__VA_ARGS__); tb_exit(-1);}

static inline void tb_set_softirq(int idx) {
	mm_io->set_softirq = 1u << idx;
}

static inline void tb_clr_softirq(int idx) {
	mm_io->clr_softirq = 1u << idx;
}

static inline bool tb_get_softirq(int idx) {
	return (bool)(mm_io->set_softirq & (1u << idx));
}

static inline void tb_enable_global_monitor(bool en) {
	mm_io->globmon_en = en;
}

static inline void tb_set_irq_masked(uint32_t mask) {
	mm_io->set_irq = mask;
}

static inline void tb_clr_irq_masked(uint32_t mask) {
	mm_io->clr_irq = mask;
}

static inline uint32_t tb_get_irq_mask() {
	return mm_io->set_irq;
}

extern volatile uintptr_t core1_entry_vector;

static inline void tb_launch_core1(void (*entry)(void)) {
	core1_entry_vector = (uintptr_t)entry;
	tb_set_softirq(1);
}

#endif
