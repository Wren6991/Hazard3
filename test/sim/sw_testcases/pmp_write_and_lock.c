#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "pmp.h"

// Check PMP registers can be written and read back. Check that lock bit
// prevents further writes.

/*EXPECTED-OUTPUT***************************************************************
*******************************************************************************/

// Number of implemented regions configured in the testbench
#define PMP_REGIONS 4
// Number of registers including WARL-0
#define PMP_REGIONS_MAX 16

int main() {
	tb_puts("Reset value check\n");
	for (int i = 0; i < PMP_REGIONS_MAX; ++i)
		tb_printf("%02d: cfg = %02x, addr = %08x\n", i, read_pmpcfg(i), read_pmpaddr(i));

	tb_puts("Write all ones (except lock bit)\n");
	for (int i = 0; i < PMP_REGIONS_MAX; ++i) {
		write_pmpcfg(i, 0x1fu);
		write_pmpaddr(i, -1u);
	}

	for (int i = 0; i < PMP_REGIONS_MAX; ++i)
		tb_printf("%02d: cfg = %02x, addr = %08x\n", i, read_pmpcfg(i), read_pmpaddr(i));

	tb_puts("Write unique values\n");
	for (unsigned int i = 0; i < PMP_REGIONS; ++i) {
		write_pmpcfg(i, i);
		write_pmpaddr(i, (i + 1) * 0x11111111u);
	}

	for (int i = 0; i < PMP_REGIONS; ++i)
		tb_printf("%02d: cfg = %02x, addr = %08x\n", i, read_pmpcfg(i), read_pmpaddr(i));

	tb_puts("Set lock bits\n");
	for (int i = 0; i < PMP_REGIONS; ++i)
		write_pmpcfg(i, PMPCFG_L_BITS);
	tb_puts("Try to set all-ones again\n");
	for (int i = 0; i < PMP_REGIONS_MAX; ++i) {
		write_pmpcfg(i, 0x1fu);
		write_pmpaddr(i, -1u);
	}

	for (int i = 0; i < PMP_REGIONS; ++i)
		tb_printf("%02d: cfg = %02x, addr = %08x\n", i, read_pmpcfg(i), read_pmpaddr(i));

	return 0;
}
