#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "pmp.h"

// Check PMP registers can be written and read back. Check that lock bit
// prevents further writes.

/*EXPECTED-OUTPUT***************************************************************

Reset value check
00: cfg = 00, addr = 00000000
01: cfg = 00, addr = 00000000
02: cfg = 00, addr = 00000000
03: cfg = 00, addr = 00000000
04: cfg = 00, addr = 00000000
05: cfg = 00, addr = 00000000
06: cfg = 00, addr = 00000000
07: cfg = 00, addr = 00000000
08: cfg = 00, addr = 00000000
09: cfg = 00, addr = 00000000
10: cfg = 00, addr = 00000000
11: cfg = 00, addr = 00000000
12: cfg = 00, addr = 00000000
13: cfg = 00, addr = 00000000
14: cfg = 00, addr = 00000000
15: cfg = 00, addr = 00000000
Write all ones (except lock bit)
00: cfg = 1f, addr = 3fffffff    // Note bits 31:30 aren't writable as the address is
01: cfg = 1f, addr = 3fffffff    // left-shifted by 2 and we only have a 4 GiB
02: cfg = 1f, addr = 3fffffff    // physical address space.
03: cfg = 1f, addr = 3fffffff
04: cfg = 00, addr = 00000000
05: cfg = 00, addr = 00000000
06: cfg = 00, addr = 00000000
07: cfg = 00, addr = 00000000
08: cfg = 00, addr = 00000000
09: cfg = 00, addr = 00000000
10: cfg = 00, addr = 00000000
11: cfg = 00, addr = 00000000
12: cfg = 00, addr = 00000000
13: cfg = 00, addr = 00000000
14: cfg = 00, addr = 00000000
15: cfg = 00, addr = 00000000
Write unique values
00: cfg = 00, addr = 11111111
01: cfg = 01, addr = 22222222
02: cfg = 02, addr = 33333333
03: cfg = 03, addr = 04444444
Set lock bits
Try to set all-ones again
00: cfg = 80, addr = 11111111
01: cfg = 80, addr = 22222222
02: cfg = 80, addr = 33333333
03: cfg = 80, addr = 04444444

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
