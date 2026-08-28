#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "pmp.h"

// Check setting region i + 1 to TOR and locking it also locks address for
// region i. The pmpcfg for region i should still change.

/*EXPECTED-OUTPUT***************************************************************

Initialise
pmpaddr0 = 00000001
pmpaddr1 = 00000002
pmpaddr2 = 00000003
pmpaddr3 = 00000004
Lock region 3
Clear all regions
pmpaddr0 = 00000000 pmpcfg[0] = 00
pmpaddr1 = 00000000 pmpcfg[1] = 00
pmpaddr2 = 00000003 pmpcfg[2] = 00
pmpaddr3 = 00000004 pmpcfg[3] = 88
Restore all regions
pmpaddr0 = 00000001 pmpcfg[0] = 00
pmpaddr1 = 00000002 pmpcfg[1] = 00
pmpaddr2 = 00000003 pmpcfg[2] = 00
pmpaddr3 = 00000004 pmpcfg[3] = 88
Lock region 1
Clear all regions
pmpaddr0 = 00000001 pmpcfg[0] = 00
pmpaddr1 = 00000002 pmpcfg[1] = 88
pmpaddr2 = 00000003 pmpcfg[2] = 00
pmpaddr3 = 00000004 pmpcfg[3] = 88
Restore all regions
pmpaddr0 = 00000001 pmpcfg[0] = 00
pmpaddr1 = 00000002 pmpcfg[1] = 88
pmpaddr2 = 00000003 pmpcfg[2] = 00
pmpaddr3 = 00000004 pmpcfg[3] = 88

*******************************************************************************/

int main() {
	tb_printf("Initialise\n");
	for (int i = 0; i < PMP_REGIONS; ++i) {
		write_pmpaddr(i, i + 1);
	}
	for (int i = 0; i < PMP_REGIONS; ++i) {
		tb_printf("pmpaddr%d = %08x\n", i, read_pmpaddr(i));
	}
	for (int i = PMP_REGIONS - 2; i >= 0; i -= 2) {
		tb_printf("Lock region %d\n", i + 1);
		write_pmpcfg(i, PMPCFG_R_BITS); // arbitrary non-zero non-enabled
		write_pmpcfg(i + 1, PMPCFG_L_BITS | (PMPCFG_A_TOR << PMPCFG_A_LSB));
		tb_printf("Clear all regions\n");
		for (int j = 0; j < PMP_REGIONS; ++j) {
			write_pmpaddr(j, 0);
			write_pmpcfg(j, 0);
			tb_printf("pmpaddr%d = %08x pmpcfg[%d] = %02x\n", j, read_pmpaddr(j), j, read_pmpcfg(j));
		}
		tb_assert(read_pmpcfg(i) == 0, "Bad pmpcfg readback i after clear\n");
		tb_assert(read_pmpcfg(i + 1) == (PMPCFG_L_BITS | (PMPCFG_A_TOR << PMPCFG_A_LSB)), "Bad pmpcfg readback i+1 after clear\n");
		tb_assert(read_pmpaddr(i) == i + 1, "Bad pmpaddr readback i+1 after clear\n");
		tb_assert(read_pmpaddr(i + 1) == i + 2, "Bad pmpaddr readback i+1 after clear\n");
		tb_printf("Restore all regions\n");
		for (int j = 0; j < PMP_REGIONS; ++j) {
			write_pmpaddr(j, j + 1);
			tb_printf("pmpaddr%d = %08x pmpcfg[%d] = %02x\n", j, read_pmpaddr(j), j, read_pmpcfg(j));
		}
		// Should still be unchanged as it's locked! Same asserts as above
		tb_assert(read_pmpcfg(i) == 0, "Bad pmpcfg readback i after restore\n");
		tb_assert(read_pmpcfg(i + 1) == (PMPCFG_L_BITS | (PMPCFG_A_TOR << PMPCFG_A_LSB)), "Bad pmpcfg readback i+1 after restore\n");
		tb_assert(read_pmpaddr(i) == i + 1, "Bad pmpaddr readback i+1 after restore\n");
		tb_assert(read_pmpaddr(i + 1) == i + 2, "Bad pmpaddr readback i+1 after restore\n");
	}

	return 0;
}
