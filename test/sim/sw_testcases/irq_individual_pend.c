#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Set IRQ mask (meie0) wide-open, then pend the IRQs one by one and log their
// firing.

#define mie_meie 0x800u

int main() {
	asm volatile ("csrsi mstatus, 0x8");
	write_csr(hazard3_csr_meie0, -1u);
	write_csr(mie, mie_meie);

	for (int i = 0; i < 32; ++i) {
		tb_printf("Setting IRQ %d\n", i);
		tb_set_irq_masked(1u << i);
	}

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

Setting IRQ 0
-> external irq handler
mlei    = 0
meip0   = 00000001
Setting IRQ 1
-> external irq handler
mlei    = 4
meip0   = 00000002
Setting IRQ 2
-> external irq handler
mlei    = 8
meip0   = 00000004
Setting IRQ 3
-> external irq handler
mlei    = 12
meip0   = 00000008
Setting IRQ 4
-> external irq handler
mlei    = 16
meip0   = 00000010
Setting IRQ 5
-> external irq handler
mlei    = 20
meip0   = 00000020
Setting IRQ 6
-> external irq handler
mlei    = 24
meip0   = 00000040
Setting IRQ 7
-> external irq handler
mlei    = 28
meip0   = 00000080
Setting IRQ 8
-> external irq handler
mlei    = 32
meip0   = 00000100
Setting IRQ 9
-> external irq handler
mlei    = 36
meip0   = 00000200
Setting IRQ 10
-> external irq handler
mlei    = 40
meip0   = 00000400
Setting IRQ 11
-> external irq handler
mlei    = 44
meip0   = 00000800
Setting IRQ 12
-> external irq handler
mlei    = 48
meip0   = 00001000
Setting IRQ 13
-> external irq handler
mlei    = 52
meip0   = 00002000
Setting IRQ 14
-> external irq handler
mlei    = 56
meip0   = 00004000
Setting IRQ 15
-> external irq handler
mlei    = 60
meip0   = 00008000
Setting IRQ 16
-> external irq handler
mlei    = 64
meip0   = 00010000
Setting IRQ 17
-> external irq handler
mlei    = 68
meip0   = 00020000
Setting IRQ 18
-> external irq handler
mlei    = 72
meip0   = 00040000
Setting IRQ 19
-> external irq handler
mlei    = 76
meip0   = 00080000
Setting IRQ 20
-> external irq handler
mlei    = 80
meip0   = 00100000
Setting IRQ 21
-> external irq handler
mlei    = 84
meip0   = 00200000
Setting IRQ 22
-> external irq handler
mlei    = 88
meip0   = 00400000
Setting IRQ 23
-> external irq handler
mlei    = 92
meip0   = 00800000
Setting IRQ 24
-> external irq handler
mlei    = 96
meip0   = 01000000
Setting IRQ 25
-> external irq handler
mlei    = 100
meip0   = 02000000
Setting IRQ 26
-> external irq handler
mlei    = 104
meip0   = 04000000
Setting IRQ 27
-> external irq handler
mlei    = 108
meip0   = 08000000
Setting IRQ 28
-> external irq handler
mlei    = 112
meip0   = 10000000
Setting IRQ 29
-> external irq handler
mlei    = 116
meip0   = 20000000
Setting IRQ 30
-> external irq handler
mlei    = 120
meip0   = 40000000
Setting IRQ 31
-> external irq handler
mlei    = 124
meip0   = 80000000

*******************************************************************************/
