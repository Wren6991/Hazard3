#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Fire all IRQs simultaneously, and log the resulting handler calls

#define mie_meie 0x800u

int main() {
	asm volatile ("csrsi mstatus, 0x8");
	write_csr(mie, mie_meie);
	write_csr(hazard3_csr_meie0, -1u);

	tb_puts("Firing all IRQs\n");
	tb_set_irq_masked(-1u);
	tb_puts("Returned OK\n");

	return 0;
}

void __attribute__((interrupt)) isr_external_irq() {
	tb_puts("-> external irq handler\n");
	tb_assert(read_csr(mcause) == 0x8000000bu, "mcause should indicate external IRQ\n");
	tb_assert(read_csr(mip) == 0x880u, "mip should indicate external + timer IRQ\n");

	// mlei updates dynamically, should be read exactly once at the start of an
	// IRQ handler.
	uint32_t mlei = read_csr(hazard3_csr_mlei);
	tb_printf("mlei    = %u\n", mlei);
	tb_printf("meip0   = %08x\n", read_csr(hazard3_csr_meip0));

	// mlei is scaled by 4 to make it cheaper to index a software vector table.
	tb_assert(read_csr(hazard3_csr_meip0) & (1u << (mlei >> 2)), "IRQ indicated by mlei is not pending\n");
	tb_clr_irq_masked(1u << (mlei >> 2));
}

/*EXPECTED-OUTPUT***************************************************************

Firing all IRQs
-> external irq handler
mlei    = 0
meip0   = ffffffff
-> external irq handler
mlei    = 4
meip0   = fffffffe
-> external irq handler
mlei    = 8
meip0   = fffffffc
-> external irq handler
mlei    = 12
meip0   = fffffff8
-> external irq handler
mlei    = 16
meip0   = fffffff0
-> external irq handler
mlei    = 20
meip0   = ffffffe0
-> external irq handler
mlei    = 24
meip0   = ffffffc0
-> external irq handler
mlei    = 28
meip0   = ffffff80
-> external irq handler
mlei    = 32
meip0   = ffffff00
-> external irq handler
mlei    = 36
meip0   = fffffe00
-> external irq handler
mlei    = 40
meip0   = fffffc00
-> external irq handler
mlei    = 44
meip0   = fffff800
-> external irq handler
mlei    = 48
meip0   = fffff000
-> external irq handler
mlei    = 52
meip0   = ffffe000
-> external irq handler
mlei    = 56
meip0   = ffffc000
-> external irq handler
mlei    = 60
meip0   = ffff8000
-> external irq handler
mlei    = 64
meip0   = ffff0000
-> external irq handler
mlei    = 68
meip0   = fffe0000
-> external irq handler
mlei    = 72
meip0   = fffc0000
-> external irq handler
mlei    = 76
meip0   = fff80000
-> external irq handler
mlei    = 80
meip0   = fff00000
-> external irq handler
mlei    = 84
meip0   = ffe00000
-> external irq handler
mlei    = 88
meip0   = ffc00000
-> external irq handler
mlei    = 92
meip0   = ff800000
-> external irq handler
mlei    = 96
meip0   = ff000000
-> external irq handler
mlei    = 100
meip0   = fe000000
-> external irq handler
mlei    = 104
meip0   = fc000000
-> external irq handler
mlei    = 108
meip0   = f8000000
-> external irq handler
mlei    = 112
meip0   = f0000000
-> external irq handler
mlei    = 116
meip0   = e0000000
-> external irq handler
mlei    = 120
meip0   = c0000000
-> external irq handler
mlei    = 124
meip0   = 80000000
Returned OK


*******************************************************************************/
