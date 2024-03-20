#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

/*EXPECTED-OUTPUT***************************************************************

Clear, read, read
mcycle = 0, 1
Clear, delay, read
mcycle = 8
Repeated carry into mcycleh
mcycleh = 4, 5
mcycle = 1
64-bit wrap
mcycleh = 4294967295, 0
mcycle = 1
Set mcountinhibit, clear, read, read
mcycle = 0, 0
Clear mcountinhibit, clear, read, read
mcycle = 0, 1

*******************************************************************************/

int main() {
	tb_puts("Clear, read, read\n");
	uint32_t tmp0, tmp1, tmp2;

	// RISC-V priv-1.12 spec has this to say about mcycle: "Any CSR write
	// takes effect after the writing instruction has otherwise completed."
	//
	// (it's not clear on the read -- assume this is just the Q output of the
	// register on the read cycle.)
	//
	// This means if you write and read on consecutive cycles, there is no
	// increment in between.
	asm volatile (
		"csrw mcycle, zero\n"
		"csrr %0, mcycle\n"
		"csrr %1, mcycle\n"
		: "=r" (tmp0), "=r" (tmp1)
	);
	// Should give 0, 1 due to above
	tb_printf("mcycle = %u, %u\n", tmp0, tmp1);

	tb_puts("Clear, delay, read\n");
	asm volatile (
		".p2align 2\n"
		"  csrw mcycle, zero\n"
		".rept 8\n"
		"  nop\n"
		".endr\n"
		"  csrr %0, mcycle\n"
		: "=r" (tmp0)
	);
	// Should give 8
	tb_printf("mcycle = %u\n", tmp0);

	tb_puts("Repeated carry into mcycleh\n");
	asm volatile (
		"csrw mcycle, zero \n"
		"csrw mcycleh, zero\n" // in-cycle register values:
		"csrw mcycle,%3    \n" // mcycle ==  1, mcycleh == 0
		"csrw mcycle,%3    \n" // mcycle == -1, mcycleh == 0
		"csrw mcycle,%3    \n" // mcycle == -1, mcycleh == 1
		"csrw mcycle,%3    \n" // mcycle == -1, mcycleh == 2
		"csrw mcycle,%3    \n" // mcycle == -1, mcycleh == 3
		"csrr %0, mcycleh  \n" // mcycle == -1, mcycleh == 4
		"csrr %1, mcycleh  \n" // mcycle ==  0, mcycleh == 5
		"csrr %2, mcycle   \n" // mcycle ==  1, mcycleh == 5
		: "=r" (tmp0), "=r" (tmp1), "=r" (tmp2)
		: "r" (0xffffffffu)
	);
	// Should give 4, 5, 1
	tb_printf("mcycleh = %u, %u\n", tmp0, tmp1);
	tb_printf("mcycle = %u\n", tmp2);


	tb_puts("64-bit wrap\n");
	asm volatile (
		"csrw mcycle, zero \n"
		"csrw mcycleh, zero\n" // in-cycle register values:
		"csrw mcycle, %3   \n" // mcycle ==  1, mcycleh ==  0
		"csrw mcycleh, %4  \n" // mcycle == -2, mcycleh ==  0
		"csrr %0, mcycleh  \n" // mcycle == -1, mcycleh == -1
		"csrr %1, mcycleh  \n" // mcycle ==  0, mcycleh ==  0
		"csrr %2, mcycle   \n" // mcycle ==  1, mcycleh ==  0
		: "=r" (tmp0), "=r" (tmp1), "=r" (tmp2)
		: "r" (0xfffffffeu), "r" (0xffffffffu)
	);
	// Should give UINT_MAX, 0, 1
	tb_printf("mcycleh = %u, %u\n", tmp0, tmp1);
	tb_printf("mcycle = %u\n", tmp2);


	tb_puts("Set mcountinhibit, clear, read, read\n");
	// mcountinhibit.cy is bit 0
	write_csr(mcountinhibit, 0x1u);
	asm volatile (
		"csrw mcycle, zero\n"
		"csrr %0, mcycle\n"
		"csrr %1, mcycle\n"
		: "=r" (tmp0), "=r" (tmp1)
	);
	// Should give 0, 0
	tb_printf("mcycle = %u, %u\n", tmp0, tmp1);

	tb_puts("Clear mcountinhibit, clear, read, read\n");
	write_csr(mcountinhibit, 0x0u);
	asm volatile (
		"csrw mcycle, zero\n"
		"csrr %0, mcycle\n"
		"csrr %1, mcycle\n"
		: "=r" (tmp0), "=r" (tmp1)
	);
	// Should give 0, 1
	tb_printf("mcycle = %u, %u\n", tmp0, tmp1);

	return 0;
}
