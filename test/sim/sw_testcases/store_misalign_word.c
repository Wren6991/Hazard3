#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Check misaligned word stores generate exception with correct mcause

/*EXPECTED-OUTPUT***************************************************************

Store word, 1 byte offset
-> exception, mcause = 6
Target value: ffffffff
Store word, 2 byte offset
-> exception, mcause = 6
Target value: ffffffff
Store word, 3 byte offset
-> exception, mcause = 6
Target value: ffffffff
Aligned store word, sanity check
Target value: 00000000

*******************************************************************************/

int main() {
	volatile uint32_t target_word = -1u;
	tb_puts("Store word, 1 byte offset\n");
	asm volatile ("sw zero, 1(%0)" : : "r" (&target_word));
	tb_printf("Target value: %08x\n", target_word);
	tb_puts("Store word, 2 byte offset\n");
	asm volatile ("sw zero, 2(%0)" : : "r" (&target_word));
	tb_printf("Target value: %08x\n", target_word);
	tb_puts("Store word, 3 byte offset\n");
	asm volatile ("sw zero, 3(%0)" : : "r" (&target_word));
	tb_printf("Target value: %08x\n", target_word);
	tb_puts("Aligned store word, sanity check\n");
	asm volatile ("sw zero, 0(%0)" : : "r" (&target_word));
	tb_printf("Target value: %08x\n", target_word);

	return 0;
}

void __attribute__((interrupt)) handle_exception() {
	tb_printf("-> exception, mcause = %u\n", read_csr(mcause));
	write_csr(mcause, 0);
	if ((*(uint16_t*)read_csr(mepc) & 0x3) == 0x3) {
		write_csr(mepc, read_csr(mepc) + 4);
	}
	else {
		write_csr(mepc, read_csr(mepc) + 2);
	}
}

