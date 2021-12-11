#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

/*EXPECTED-OUTPUT***************************************************************

1: defined illegal all-zeroes
Exception, mcause = 2
16-bit illegal instruction: 0000
2: defined illegal all-ones
Exception, mcause = 2
32-bit illegal instruction: ffffffff
3: unimplemented CSR 0xfff
Exception, mcause = 2
32-bit illegal instruction: fff027f3
4: write to read-only CSR
Exception, mcause = 2
32-bit illegal instruction: f1101073
5: unimplemented instruction (F extension)
Exception, mcause = 2
32-bit illegal instruction: 00052087

*******************************************************************************/

int main() {
	tb_puts("1: defined illegal all-zeroes\n");
	asm volatile (".hword 0x0000");

	tb_puts("2: defined illegal all-ones\n");
	asm volatile (".word 0xffffffff");

	tb_puts("3: unimplemented CSR 0xfff\n");
	uint32_t junk;
	asm volatile ("csrr %0, 0xfff" : "=r" (junk));

	tb_puts("4: write to read-only CSR\n");
	asm volatile ("csrw mvendorid, zero");
	// However a clear/set with zero value does not count as a write, so this
	// won't appear in the printf output:
	asm volatile ("csrs mvendorid, zero");

	tb_puts("5: unimplemented instruction (F extension)\n");
	asm volatile (".word 0x00052087"); // flw ft1, (a0)

	return 0;
}

void __attribute__((interrupt)) handle_exception() {
	uintptr_t mepc = read_csr(mepc);
	uint32_t mcause = read_csr(mcause);
	tb_printf("Exception, mcause = %u\n", mcause);

	uint16_t i0 = *(uint16_t*)mepc;
	if (i0 & 0x3u == 0x3u) {
		uint16_t i1 = *(uint16_t*)(mepc + 2);
		tb_printf("32-bit illegal instruction: %04x%04x\n", i1, i0);
		mepc += 4;
	}
	else {
		tb_printf("16-bit illegal instruction: %04x\n", i0);
		mepc += 2;
	}
	write_csr(mepc, mepc);
}
