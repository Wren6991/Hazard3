#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

#include <stdint.h>

int main() {
	uintptr_t illegal_addr = 0x56789abc;
	asm volatile ("jr %0" : : "r" (illegal_addr));
}

void __attribute__((interrupt)) handle_exception() {
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_printf("mepc = %08x\n", read_csr(mepc));
	tb_exit(0);
}
