#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Cribbed heavily from csr_mcycle

/*EXPECTED-OUTPUT***************************************************************

Clear, read, read
minstret = 0, 1
Clear, delay, read
minstret = 4
Repeated carry into minstreth
minstreth = 4, 5
minstret = 1
64-bit wrap
minstreth = 4294967295, 0
minstret = 1
Set mcountinhibit, clear, read, read
minstret = 0, 0
Clear mcountinhibit, clear, read, read
minstret = 0, 1

*******************************************************************************/

int main() {
	tb_puts("Clear, read, read\n");
	uint32_t tmp0, tmp1, tmp2;

	// RISC-V priv-1.12 spec has this to say about minstret: "Any CSR write
	// takes effect after the writing instruction has otherwise completed."
	//
	// (it's not clear on the read -- assume this is just the Q output of the
	// register on the read cycle.)
	//
	// This means if you write and read on consecutive cycles, there is no
	// increment in between.
	asm volatile (
		"csrw minstret, zero\n"
		"csrr %0, minstret\n"
		"csrr %1, minstret\n"
		: "=r" (tmp0), "=r" (tmp1)
	);
	// Should give 0, 1 due to above
	tb_printf("minstret = %u, %u\n", tmp0, tmp1);

	tb_puts("Clear, delay, read\n");
	asm volatile (
		"  csrw minstret, zero\n"
		"  j 1f\n"
		"1:\n"
		"  div %0, %0, %0\n"
		"  j 1f\n"
		"1:\n"
		"  nop\n"
		"  csrr %0, minstret\n"
		: "=r" (tmp0)
	);
	// Should give 4
	tb_printf("minstret = %u\n", tmp0);

	tb_puts("Repeated carry into minstreth\n");
	asm volatile (
		"csrw minstret, zero \n"
		"csrw minstreth, zero\n" // in-cycle register values:
		"csrw minstret,%3    \n" // minstret ==  1, minstreth == 0
		"csrw minstret,%3    \n" // minstret == -1, minstreth == 0
		"csrw minstret,%3    \n" // minstret == -1, minstreth == 1
		"csrw minstret,%3    \n" // minstret == -1, minstreth == 2
		"csrw minstret,%3    \n" // minstret == -1, minstreth == 3
		"csrr %0, minstreth  \n" // minstret == -1, minstreth == 4
		"csrr %1, minstreth  \n" // minstret ==  0, minstreth == 5
		"csrr %2, minstret   \n" // minstret ==  1, minstreth == 5
		: "=r" (tmp0), "=r" (tmp1), "=r" (tmp2)
		: "r" (0xffffffffu)
	);
	// Should give 4, 5, 1
	tb_printf("minstreth = %u, %u\n", tmp0, tmp1);
	tb_printf("minstret = %u\n", tmp2);


	tb_puts("64-bit wrap\n");
	asm volatile (
		"csrw minstret, zero \n"
		"csrw minstreth, zero\n" // in-cycle register values:
		"csrw minstret, %3   \n" // minstret ==  1, minstreth ==  0
		"csrw minstreth, %4  \n" // minstret == -2, minstreth ==  0
		"csrr %0, minstreth  \n" // minstret == -1, minstreth == -1
		"csrr %1, minstreth  \n" // minstret ==  0, minstreth ==  0
		"csrr %2, minstret   \n" // minstret ==  1, minstreth ==  0
		: "=r" (tmp0), "=r" (tmp1), "=r" (tmp2)
		: "r" (0xfffffffeu), "r" (0xffffffffu)
	);
	// Should give UINT_MAX, 0, 1
	tb_printf("minstreth = %u, %u\n", tmp0, tmp1);
	tb_printf("minstret = %u\n", tmp2);


	tb_puts("Set mcountinhibit, clear, read, read\n");
	// mcountinhibit.ir is bit 2
	write_csr(mcountinhibit, 0x4u);
	asm volatile (
		"csrw minstret, zero\n"
		"csrr %0, minstret\n"
		"csrr %1, minstret\n"
		: "=r" (tmp0), "=r" (tmp1)
	);
	// Should give 0, 0
	tb_printf("minstret = %u, %u\n", tmp0, tmp1);

	tb_puts("Clear mcountinhibit, clear, read, read\n");
	write_csr(mcountinhibit, 0x0u);
	asm volatile (
		"csrw minstret, zero\n"
		"csrr %0, minstret\n"
		"csrr %1, minstret\n"
		: "=r" (tmp0), "=r" (tmp1)
	);
	// Should give 0, 1
	tb_printf("minstret = %u, %u\n", tmp0, tmp1);

	return 0;
}
