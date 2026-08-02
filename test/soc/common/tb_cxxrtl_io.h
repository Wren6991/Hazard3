#ifndef _TB_CXXRTL_IO_H
#define _TB_CXXRTL_IO_H

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

// ----------------------------------------------------------------------------
// SOC IO hardware layout

#define TIMER_BASE 0x40000000
#define UART_BASE 0x40004000
#define USB_CDC_BASE 0x40008000

typedef struct {
	volatile uint32_t ctrl;
	uint32_t _pad0;
	volatile uint32_t mtime;
	volatile uint32_t mtimeh;
	volatile uint32_t mtimecmp;
	volatile uint32_t mtimecmph;
} timer_hw_t;

#define mm_timer ((timer_hw_t *const)(TIMER_BASE))

typedef union {
	uint32_t value;
	struct {
		uint32_t en : 1;
		uint32_t busy : 1;
		uint32_t txie : 1;
		uint32_t rxie : 1;
		uint32_t ctsen : 1;
		uint32_t _reserved0 : 3;
		uint32_t loopback : 1;
		uint32_t _reserved1 : 23;
	} bits;
} uart_csr_hw_t;

typedef union {
	uint32_t value;
	struct {
		uint32_t frac : 4;
		uint32_t intgr : 10;
		uint32_t _reserved0 : 18;
	} bits;
} uart_div_hw_t;

typedef union {
	uint32_t value;
	struct {
		uint32_t txlevel : 8;
		uint32_t txfull : 1;
		uint32_t txempty : 1;
		uint32_t txover : 1;
		uint32_t txunder : 1;
		uint32_t _reserved0 : 4;
		uint32_t rxlevel : 8;
		uint32_t rxfull : 1;
		uint32_t rxempty : 1;
		uint32_t rxover : 1;
		uint32_t rxunder : 1;
		uint32_t _reserved1 : 4;
	} bits;
} uart_fstat_hw_t;

typedef struct {
	volatile uart_csr_hw_t csr;
	volatile uart_div_hw_t div;
	volatile uart_fstat_hw_t fstat;
	volatile uint32_t tx;
	volatile uint32_t rx;
} uart_hw_t;

#define mm_uart ((uart_hw_t *const)(UART_BASE))

typedef union {
	uint32_t value;
	struct {
		uint32_t in_ready : 1;
		uint32_t out_valid : 1;
		uint32_t _reserved0 : 30;
	} bits;
} usb_cdc_fstat_hw_t;

typedef struct {
	volatile usb_cdc_fstat_hw_t fstat;
	volatile uint32_t tx_data;
	volatile uint32_t rx_data;
} usb_cdc_hw_t;

#define mm_usb_cdc ((usb_cdc_hw_t *const)(USB_CDC_BASE))

// ----------------------------------------------------------------------------
// SOC IO convenience functions

#define UART_U32_BUF_SIZE 11u
 
static inline uint64_t read_mtime(void) {
	volatile uint32_t *lo = &(mm_timer->mtime);
	volatile uint32_t *hi = &(mm_timer->mtimeh);

	uint32_t h1, l, h2;
	do {
		h1 = *hi;
		l  = *lo;
		h2 = *hi;
	} while (h1 != h2);

	return ((uint64_t)h1 << 32) | l;
}

void usleep(uint32_t usec) {
	uint64_t start = read_mtime();
	while ((read_mtime() - start) < usec);
}

static inline void usb_cdc_putc_blocking(char c) {
	while (!(mm_usb_cdc->fstat.bits.in_ready));
	mm_usb_cdc->tx_data = (uint32_t)c;
}

void usb_cdc_puts(const char *s) {
	while (*s) {
		usb_cdc_putc_blocking(*s++);
	}
}

static void uart_init(void) {
	uart_csr_hw_t csr = {.value = 0u};
	uart_div_hw_t div = {.value = 0u};

	csr.bits.en = 1u;
	mm_uart->csr = csr;

	// 115200 baudrate with 48 MHz clock
	// 48 MHz / 115200 / 8 = 52.083333333 = 52 + 0.083333333 ≈ 52 + 1/16
	div.bits.intgr = 52u;
	div.bits.frac = 1u;
	mm_uart->div = div;
}

static inline void uart_putc_blocking(char c) {
	while (mm_uart->fstat.bits.txfull);
	mm_uart->tx = (uint32_t)c;
}

void uart_puts(const char *s) {
	while (*s) {
		uart_putc_blocking(*s++);
	}
}

static inline void uart_u32_to_buf(uint32_t value, char *buf) {
	char scratch[UART_U32_BUF_SIZE];
	uint32_t i = 0u;

	do {
		scratch[i++] = (char)('0' + value % 10u);
		value /= 10u;
	} while (value);

	for (uint32_t j = 0u; j < i; ++j)
		buf[j] = scratch[i - j - 1u];
	buf[i] = '\0';
}

void uart_puts_32(uint32_t value) {
	char buf[UART_U32_BUF_SIZE];
	uart_u32_to_buf(value, buf);
	uart_puts(buf);
}

static inline char uart_getc_blocking(void) {
	while (mm_uart->fstat.bits.rxempty);
	return (char)mm_uart->rx;
}

void uart_gets(char *s, uint32_t maxlen) {
    uint32_t i = 0;
	char c;

	if (maxlen <= 1)
		return;

	while (true) {
		if (i + 1 < maxlen) {
			c = uart_getc_blocking();
			c = (c == '\r') ? '\n' : c;
			s[i++] = c;
			if (c == '\n')
			{
				s[i] = '\r';
				break;
			}
		} else {
			s[i] = '\0';
			break;
		}
	}
}

#endif
