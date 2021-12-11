#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

/*EXPECTED-OUTPUT***************************************************************

Entering test section
mcause = 3
Offset into test: 0, 32-bit ebreak
mcause = 3
Offset into test: 4, 16-bit ebreak
mcause = 3
Offset into test: 6, 32-bit ebreak
mcause = 3
Offset into test: 10, 16-bit ebreak
Done

*******************************************************************************/

// This is naked so we can take its address and get accurate offsets for the
// breakpoints, which we can then check. Otherwise, we would have issues with
// the size of the prologue potentially varying between builds etc.
//
// There is also a GCC extension for taking the address of a label, but GCC
// takes artistic liberty in deciding where that label actually "is".

void __attribute__((naked)) test() {
	asm volatile (
		// Word-aligned word-sized
		".option norvc\n"
		"ebreak\n"
		".option rvc\n"
		// Word-aligned halfword-sized
		"c.ebreak\n"
		// Halfword-aligned word-sized
		".option norvc\n"
		"ebreak\n"
		".option rvc\n"
		// Halfword-aligned halfword-sized
		"c.ebreak\n"

		"ret\n"
	);
}

int main() {
	tb_puts("Entering test section\n");
	test();
	tb_puts("Done\n");
}

void __attribute__((interrupt)) handle_exception() {
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_printf("Offset into test: %u, ", read_csr(mepc) - (uintptr_t)&test);
	if ((*(uint16_t*)read_csr(mepc) & 0x3) == 0x3) {
		tb_puts("32-bit ebreak\n");
		write_csr(mepc, read_csr(mepc) + 4);
	}
	else {
		tb_puts("16-bit ebreak\n");
		write_csr(mepc, read_csr(mepc) + 2);
	}
	write_csr(mcause, 0);
}
