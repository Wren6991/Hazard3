#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

int main() {
	volatile uint32_t target_word = 0x1234cdefu;
	volatile uint32_t result_word = 0;
	tb_puts("Load halfword signed, 1 byte offset\n");
	asm volatile("lh %0, 1(%1)" : "+r" (result_word) : "r" (&target_word));
	tb_printf("Result: %08x\n", result_word);
	tb_puts("Load halfword signed, 3 byte offset\n");
	asm volatile("lh %0, 3(%1)" : "+r" (result_word) : "r" (&target_word));
	tb_printf("Result: %08x\n", result_word);
	tb_puts("Load halfword signed aligned (sanity check)\n");
	asm volatile("lh %0, 0(%1)" : "+r" (result_word) : "r" (&target_word));
	tb_printf("Result: %08x\n", result_word);
	asm volatile("lh %0, 2(%1)" : "+r" (result_word) : "r" (&target_word));
	tb_printf("Result: %08x\n", result_word);

	result_word = 0;
	tb_puts("Load halfword unsigned, 1 byte offset\n");
	asm volatile("lhu %0, 1(%1)" : "+r" (result_word) : "r" (&target_word));
	tb_printf("Result: %08x\n", result_word);
	tb_puts("Load halfword unsigned, 3 byte offset\n");
	asm volatile("lhu %0, 3(%1)" : "+r" (result_word) : "r" (&target_word));
	tb_printf("Result: %08x\n", result_word);
	tb_puts("Load halfword unsigned aligned (sanity check)\n");
	asm volatile("lhu %0, 0(%1)" : "+r" (result_word) : "r" (&target_word));
	tb_printf("Result: %08x\n", result_word);
	asm volatile("lhu %0, 2(%1)" : "+r" (result_word) : "r" (&target_word));
	tb_printf("Result: %08x\n", result_word);

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

