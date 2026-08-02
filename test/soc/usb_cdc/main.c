#include "tb_cxxrtl_io.h"

#define TEST_MB (1<<20)
static char buf[4096];

int main() {
	for (int i=0;i<sizeof(buf);++i)
		buf[i]=i&0xFF;
	uint64_t t0 = read_mtime();
	uint32_t sent = 0;
	while (sent < TEST_MB) {
		for (int i=0;i<sizeof(buf);++i)
			usb_cdc_putc_blocking(buf[i]);
		sent += sizeof(buf);
	}

	uint64_t t1 = read_mtime();

	uart_init();
	uart_puts("\r\nt1: ");
	uart_puts_32((uint32_t)t1);
	uart_puts("\r\nt0: ");
	uart_puts_32((uint32_t)t0);
	uart_puts("\r\nsent: ");
	uart_puts_32(sent);

	// print mbps using simple itoa or %f if stdio available
	while(1);
}