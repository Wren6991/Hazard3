#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Check load/stores which generate a bus fault generate an exception, and
// report the correct mcause and mepc.

/*EXPECTED-OUTPUT***************************************************************

-> exception, mcause = 7
exception instr: 0007a023
-> exception, mcause = 7
exception instr: 00079023
-> exception, mcause = 7
exception instr: 00078023
-> exception, mcause = 5
exception instr: 0007a003
-> exception, mcause = 5
exception instr: 00079003
-> exception, mcause = 5
exception instr: 0007d003
-> exception, mcause = 5
exception instr: 00078003
-> exception, mcause = 5
exception instr: 0007c003
Done.

*******************************************************************************/

int main() {
	// Word-aligned address which generates an access fault. Constrained to a
	// particular register, because the instructions appear in the test log to
	// confirm mepc value.
	register void *bad_addr asm ("a5") = (void*)0xcdef1234u;

	asm volatile (
		"sw zero, (%0)\n"
		"sh zero, (%0)\n"
		"sb zero, (%0)\n"
		"lw zero, (%0)\n"
		"lh zero, (%0)\n"
		"lhu zero, (%0)\n"
		"lb zero, (%0)\n"
		"lbu zero, (%0)\n"
		: : "r" (bad_addr)
	);
	tb_puts("Done.\n");
	return 0;
}

void __attribute__((interrupt)) handle_exception() {
	tb_printf("-> exception, mcause = %u\n", read_csr(mcause));
	write_csr(mcause, 0);
	uint32_t mepc = read_csr(mepc);
	if ((*(uint16_t*)mepc & 0x3) == 0x3) {
		tb_printf("exception instr: %04x%04x\n", *(uint16_t*)(mepc + 2), *(uint16_t*)mepc);
		write_csr(mepc, mepc + 4);
	}
	else {
		tb_printf("exception instr: %04x\n", *(uint16_t*)(mepc + 2), *(uint16_t*)mepc);
		write_csr(mepc, mepc + 2);
	}
}
