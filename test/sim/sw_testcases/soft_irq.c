#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

/*EXPECTED-OUTPUT***************************************************************

Dry run
Set mie only
Then set IRQ
-> handle_soft_irq
mip     = 00000088  // mtip is also set, because mtimecmp is 0
mie     = 00000008  // only msie is set
mcause  = 80000003  // MSB indicates IRQ. LSBs are index of mip.
mstatus = 00001880  // MPP = 3. mpie = 1, mie = 0, since we just took an IRQ.
Returned from IRQ
Clear mie, do another dry run

*******************************************************************************/

#define mip_msip 0x8u
#define mie_msie mip_msip

int main() {
	tb_assert(!(read_csr(mip) & mip_msip), "mip.msip should be clear at start of test\n");

	tb_puts("Dry run\n");
	tb_set_softirq(0);
	tb_assert(tb_get_softirq(0), "Failed to set soft_irq through tb\n");
	tb_assert(read_csr(mip) & mip_msip, "soft_irq not reflected in mip\n");

	tb_clr_softirq(0);
	tb_assert(!tb_get_softirq(0), "Failed to clear soft_irq through tb\n");
	tb_assert(!(read_csr(mip) & mip_msip), "soft_irq clear not reflected in mip\n");

	tb_puts("Set mie only\n");
	write_csr(mie, mie_msie);
	asm volatile ("csrsi mstatus, 0x8");
	// IRQ should not fire yet.

	tb_puts("Then set IRQ\n");
	tb_set_softirq(0); 
	tb_assert(!(read_csr(mip) & mip_msip), "soft_irq should have been cleared by IRQ\n");
	tb_puts("Returned from IRQ\n");

	tb_puts("Clear mie, do another dry run\n");
	write_csr(mie, 0);
	tb_set_softirq(0);
	tb_assert(tb_get_softirq(0), "Failed to set soft_irq through tb\n");
	tb_assert(read_csr(mip) & mip_msip, "soft_irq not reflected in mip\n");

	tb_clr_softirq(0);
	tb_assert(!tb_get_softirq(0), "Failed to clear soft_irq through tb\n");
	tb_assert(!(read_csr(mip) & mip_msip), "soft_irq clear not reflected in mip\n");

	return 0;
}

void __attribute__((interrupt)) isr_machine_softirq() {
	tb_puts("-> handle_soft_irq\n");
	tb_printf("mip     = %08x\n", read_csr(mip));
	tb_printf("mie     = %08x\n", read_csr(mie));
	tb_clr_softirq(0);
	tb_printf("mcause  = %08x\n", read_csr(mcause));
	tb_printf("mstatus = %08x\n", read_csr(mstatus));
}
