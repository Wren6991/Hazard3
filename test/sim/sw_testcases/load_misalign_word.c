#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

/*EXPECTED-OUTPUT***************************************************************

Load word, 1 byte offset
-> exception, mcause = 4
Result: 00000000
Load word, 2 byte offset
-> exception, mcause = 4
Result: 00000000
Load word, 3 byte offset
-> exception, mcause = 4
Result: 00000000
Load word aligned (sanity check)
Result: ffffffff

*******************************************************************************/

int main() {
	volatile uint32_t target_word = -1u;
	volatile uint32_t result_word = 0;
	tb_puts("Load word, 1 byte offset\n");
	asm volatile("lw %0, 1(%1)" : "+r" (result_word) : "r" (&target_word));
	tb_printf("Result: %08x\n", result_word);
	tb_puts("Load word, 2 byte offset\n");
	asm volatile("lw %0, 2(%1)" : "+r" (result_word) : "r" (&target_word));
	tb_printf("Result: %08x\n", result_word);
	tb_puts("Load word, 3 byte offset\n");
	asm volatile("lw %0, 3(%1)" : "+r" (result_word) : "r" (&target_word));
	tb_printf("Result: %08x\n", result_word);
	tb_puts("Load word aligned (sanity check)\n");
	asm volatile("lw %0, 0(%1)" : "+r" (result_word) : "r" (&target_word));
	tb_printf("Result: %08x\n", result_word);
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

