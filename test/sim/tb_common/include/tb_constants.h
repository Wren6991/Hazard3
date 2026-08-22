#pragma once

#ifdef __x86_64__
#define I64_FMT "%ld"
#else
#define I64_FMT "%lld"
#endif

#define MEM_BASE 0x80000000
#define MEM_SIZE (16 * 1024 * 1024)
#define N_RESERVATIONS (2)
// 64-byte granule: matches smallest configurable in SAIL sim.
#define RESERVATION_ADDR_MASK (0xffffffc0u)

static const unsigned int IO_BASE = 0xc0000000;
enum {
	IO_PRINT_CHAR  = 0x000,
	IO_PRINT_U32   = 0x004,
	IO_EXIT        = 0x008,
	IO_SET_SOFTIRQ = 0x010,
	IO_CLR_SOFTIRQ = 0x014,
	IO_GLOBMON_EN  = 0x018,
	IO_POISON_ADDR = 0x01c,
	IO_SET_IRQ     = 0x020,
	IO_CLR_IRQ     = 0x030,
	IO_MTIME       = 0x100,
	IO_MTIMEH      = 0x104,
	IO_MTIMECMP0   = 0x108,
	IO_MTIMECMP0H  = 0x10c,
	IO_MTIMECMP1   = 0x110,
	IO_MTIMECMP1H  = 0x114
};

typedef enum {
	SIZE_BYTE = 0,
	SIZE_HWORD = 1,
	SIZE_WORD = 2
} bus_size_t;
