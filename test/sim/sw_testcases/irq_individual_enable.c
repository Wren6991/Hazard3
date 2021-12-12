#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Pend all IRQs, enable them one-by-one and log their firing.

#define mie_meie 0x800u

int main() {
	asm volatile ("csrsi mstatus, 0x8");
	write_csr(hazard3_csr_meie0, 0u);
	write_csr(mie, mie_meie);

	tb_set_irq_masked(-1u);

	for (int i = 31; i >= 0; --i) {
		tb_printf("Enabling IRQ %d\n", i);
		write_csr(hazard3_csr_meie0, 1u << i);
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

Enabling IRQ 31
-> external irq handler
mlei    = 124
meip0   = ffffffff
Enabling IRQ 30
-> external irq handler
mlei    = 120
meip0   = 7fffffff
Enabling IRQ 29
-> external irq handler
mlei    = 116
meip0   = 3fffffff
Enabling IRQ 28
-> external irq handler
mlei    = 112
meip0   = 1fffffff
Enabling IRQ 27
-> external irq handler
mlei    = 108
meip0   = 0fffffff
Enabling IRQ 26
-> external irq handler
mlei    = 104
meip0   = 07ffffff
Enabling IRQ 25
-> external irq handler
mlei    = 100
meip0   = 03ffffff
Enabling IRQ 24
-> external irq handler
mlei    = 96
meip0   = 01ffffff
Enabling IRQ 23
-> external irq handler
mlei    = 92
meip0   = 00ffffff
Enabling IRQ 22
-> external irq handler
mlei    = 88
meip0   = 007fffff
Enabling IRQ 21
-> external irq handler
mlei    = 84
meip0   = 003fffff
Enabling IRQ 20
-> external irq handler
mlei    = 80
meip0   = 001fffff
Enabling IRQ 19
-> external irq handler
mlei    = 76
meip0   = 000fffff
Enabling IRQ 18
-> external irq handler
mlei    = 72
meip0   = 0007ffff
Enabling IRQ 17
-> external irq handler
mlei    = 68
meip0   = 0003ffff
Enabling IRQ 16
-> external irq handler
mlei    = 64
meip0   = 0001ffff
Enabling IRQ 15
-> external irq handler
mlei    = 60
meip0   = 0000ffff
Enabling IRQ 14
-> external irq handler
mlei    = 56
meip0   = 00007fff
Enabling IRQ 13
-> external irq handler
mlei    = 52
meip0   = 00003fff
Enabling IRQ 12
-> external irq handler
mlei    = 48
meip0   = 00001fff
Enabling IRQ 11
-> external irq handler
mlei    = 44
meip0   = 00000fff
Enabling IRQ 10
-> external irq handler
mlei    = 40
meip0   = 000007ff
Enabling IRQ 9
-> external irq handler
mlei    = 36
meip0   = 000003ff
Enabling IRQ 8
-> external irq handler
mlei    = 32
meip0   = 000001ff
Enabling IRQ 7
-> external irq handler
mlei    = 28
meip0   = 000000ff
Enabling IRQ 6
-> external irq handler
mlei    = 24
meip0   = 0000007f
Enabling IRQ 5
-> external irq handler
mlei    = 20
meip0   = 0000003f
Enabling IRQ 4
-> external irq handler
mlei    = 16
meip0   = 0000001f
Enabling IRQ 3
-> external irq handler
mlei    = 12
meip0   = 0000000f
Enabling IRQ 2
-> external irq handler
mlei    = 8
meip0   = 00000007
Enabling IRQ 1
-> external irq handler
mlei    = 4
meip0   = 00000003
Enabling IRQ 0
-> external irq handler
mlei    = 0
meip0   = 00000001

*******************************************************************************/
