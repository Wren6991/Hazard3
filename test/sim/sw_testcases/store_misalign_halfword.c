#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

int main() {
	volatile uint32_t target_word = -1u;
	tb_puts("Store halfword, 1 byte offset\n");
	asm volatile ("sh zero, 1(%0)" : : "r" (&target_word));
	tb_printf("Target value: %08x\n", target_word);
	tb_puts("Store halfword, 3 byte offset\n");
	asm volatile ("sh zero, 3(%0)" : : "r" (&target_word));
	tb_printf("Target value: %08x\n", target_word);
	tb_puts("Aligned store halfword, sanity check\n");
	asm volatile ("sh zero, 0(%0)" : : "r" (&target_word));
	tb_printf("Target value: %08x\n", target_word);
	asm volatile ("sh zero, 2(%0)" : : "r" (&target_word));
	tb_printf("Target value: %08x\n", target_word);

	return 0;
}

void __attribute__((interrupt)) handle_exception() {
	tb_printf("-> exception, mcause = %u\n", read_csr(mcause));
	write_csr(mcause, 0);
	if (*(uint16_t*)read_csr(mepc) & 0x3 == 0x3) {
		write_csr(mepc, read_csr(mepc) + 4);
	}
	else {
		write_csr(mepc, read_csr(mepc) + 2);
	}
}

