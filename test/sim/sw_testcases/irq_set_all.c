#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "hazard3_irq.h"

// Fire all IRQs simultaneously, and log the resulting handler calls

#define mie_meie 0x800u

int main() {
	asm volatile ("csrsi mstatus, 0x8");
	write_csr(mie, mie_meie);
	h3irq_array_write(hazard3_csr_meiea, 0, 0xffffu);
	h3irq_array_write(hazard3_csr_meiea, 1, 0xffffu);

	tb_puts("Firing all IRQs\n");
	tb_set_irq_masked(-1u);
	tb_puts("Returned OK\n");

	return 0;
}

void __attribute__((interrupt)) isr_external_irq() {
	tb_puts("-> external irq handler\n");
	tb_assert(read_csr(mcause) == 0x8000000bu, "mcause should indicate external IRQ\n");
	// Once an interrupt has fired, it does not appear pending in mip since it
	// can't preempt itself unless its priority is raised.
	tb_assert(read_csr(mip) == 0x080u, "mip should indicate timer IRQ only\n");

	// meinext updates dynamically, should be read exactly once at the start of an
	// IRQ handler.
	uint32_t meinext = read_csr(hazard3_csr_meinext);
	tb_printf("meinext = %u\n", meinext);
	tb_printf(
		"meipa   = %08x\n",
		h3irq_array_read(hazard3_csr_meipa, 0) |
		((uint32_t)h3irq_array_read(hazard3_csr_meipa, 1) << 16)
	);

	// meinext is scaled by 4 to make it cheaper to index a software vector table.
	tb_assert(h3irq_pending(meinext >> 2), "IRQ indicated by meinext is not pending\n");
	tb_clr_irq_masked(1u << (meinext >> 2));
}

/*EXPECTED-OUTPUT***************************************************************

Firing all IRQs
-> external irq handler
meinext = 0
meipa   = ffffffff
-> external irq handler
meinext = 4
meipa   = fffffffe
-> external irq handler
meinext = 8
meipa   = fffffffc
-> external irq handler
meinext = 12
meipa   = fffffff8
-> external irq handler
meinext = 16
meipa   = fffffff0
-> external irq handler
meinext = 20
meipa   = ffffffe0
-> external irq handler
meinext = 24
meipa   = ffffffc0
-> external irq handler
meinext = 28
meipa   = ffffff80
-> external irq handler
meinext = 32
meipa   = ffffff00
-> external irq handler
meinext = 36
meipa   = fffffe00
-> external irq handler
meinext = 40
meipa   = fffffc00
-> external irq handler
meinext = 44
meipa   = fffff800
-> external irq handler
meinext = 48
meipa   = fffff000
-> external irq handler
meinext = 52
meipa   = ffffe000
-> external irq handler
meinext = 56
meipa   = ffffc000
-> external irq handler
meinext = 60
meipa   = ffff8000
-> external irq handler
meinext = 64
meipa   = ffff0000
-> external irq handler
meinext = 68
meipa   = fffe0000
-> external irq handler
meinext = 72
meipa   = fffc0000
-> external irq handler
meinext = 76
meipa   = fff80000
-> external irq handler
meinext = 80
meipa   = fff00000
-> external irq handler
meinext = 84
meipa   = ffe00000
-> external irq handler
meinext = 88
meipa   = ffc00000
-> external irq handler
meinext = 92
meipa   = ff800000
-> external irq handler
meinext = 96
meipa   = ff000000
-> external irq handler
meinext = 100
meipa   = fe000000
-> external irq handler
meinext = 104
meipa   = fc000000
-> external irq handler
meinext = 108
meipa   = f8000000
-> external irq handler
meinext = 112
meipa   = f0000000
-> external irq handler
meinext = 116
meipa   = e0000000
-> external irq handler
meinext = 120
meipa   = c0000000
-> external irq handler
meinext = 124
meipa   = 80000000
Returned OK


*******************************************************************************/
