#ifndef _TB_CXXRTL_IO_H
#define _TB_CXXRTL_IO_H

#include <stdint.h>

#define IO_BASE 0x80000000

struct io_hw {
	volatile uint32_t print_char;
	volatile uint32_t print_u32;
	volatile uint32_t exit;
};

#define mm_io ((struct io_hw *const)IO_BASE)

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

#endif
