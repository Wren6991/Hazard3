#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Check that U-mode execution of an mret causes an illegal opcode exception.

/*EXPECTED-OUTPUT***************************************************************

-> exception, mcause = 2, mpp = 0 // should indicate U-mode illegal opcode
Excepting instr: 30200073         // mret

*******************************************************************************/

void __attribute__((naked)) do_mret() {
	asm ("mret");
}

int main() {
	// Give U mode RWX permission on all of memory.
	write_csr(pmpcfg0, 0x1fu);
	write_csr(pmpaddr0, -1u);

	// Jump to do_mret() in U mode
	write_csr(mstatus, read_csr(mstatus) & ~0x1800u);
	write_csr(mepc, &do_mret);
	asm ("mret");

	return 0;
}

void __attribute__((interrupt)) handle_exception() {
	uint32_t mcause = read_csr(mcause);
	tb_printf("-> exception, mcause = %u, mpp = %u\n", mcause, read_csr(mstatus) >> 11 & 0x3u);
	write_csr(mcause, 0);
	if (mcause == 3) {
		// ebreak -> end of test
		tb_exit(0);
	}

	uint32_t mepc = read_csr(mepc);
	if (mepc != (uint32_t)&do_mret) {
		tb_printf("Bad mepc: %08x\n", mepc);
		tb_exit(-1);
	}

	tb_printf("Excepting instr: %04x%04x\n", *(uint16_t*)(mepc + 2), *(uint16_t*)mepc);

	tb_exit(0);
}
