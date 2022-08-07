#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "hazard3_irq.h"

// Pend all IRQs, enable them one-by-one and log their firing.

#define mie_meie 0x800u

int main() {
	asm volatile ("csrsi mstatus, 0x8");
	write_csr(mie, mie_meie);

	tb_set_irq_masked(-1u);

	for (int i = 31; i >= 0; --i) {
		tb_printf("Enabling IRQ %d\n", i);
		h3irq_enable(i, true);
	}

	return 0;
}

void __attribute__((interrupt)) isr_external_irq() {
	tb_puts("-> external irq handler\n");
	tb_assert(read_csr(mcause) == 0x8000000bu, "mcause should indicate external IRQ\n");
	// The external IRQ pending bit should immediately clear due to the
	// premption priority being boosted above the IRQ we took.
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

Enabling IRQ 31
-> external irq handler
meinext = 124
meipa   = ffffffff
Enabling IRQ 30
-> external irq handler
meinext = 120
meipa   = 7fffffff
Enabling IRQ 29
-> external irq handler
meinext = 116
meipa   = 3fffffff
Enabling IRQ 28
-> external irq handler
meinext = 112
meipa   = 1fffffff
Enabling IRQ 27
-> external irq handler
meinext = 108
meipa   = 0fffffff
Enabling IRQ 26
-> external irq handler
meinext = 104
meipa   = 07ffffff
Enabling IRQ 25
-> external irq handler
meinext = 100
meipa   = 03ffffff
Enabling IRQ 24
-> external irq handler
meinext = 96
meipa   = 01ffffff
Enabling IRQ 23
-> external irq handler
meinext = 92
meipa   = 00ffffff
Enabling IRQ 22
-> external irq handler
meinext = 88
meipa   = 007fffff
Enabling IRQ 21
-> external irq handler
meinext = 84
meipa   = 003fffff
Enabling IRQ 20
-> external irq handler
meinext = 80
meipa   = 001fffff
Enabling IRQ 19
-> external irq handler
meinext = 76
meipa   = 000fffff
Enabling IRQ 18
-> external irq handler
meinext = 72
meipa   = 0007ffff
Enabling IRQ 17
-> external irq handler
meinext = 68
meipa   = 0003ffff
Enabling IRQ 16
-> external irq handler
meinext = 64
meipa   = 0001ffff
Enabling IRQ 15
-> external irq handler
meinext = 60
meipa   = 0000ffff
Enabling IRQ 14
-> external irq handler
meinext = 56
meipa   = 00007fff
Enabling IRQ 13
-> external irq handler
meinext = 52
meipa   = 00003fff
Enabling IRQ 12
-> external irq handler
meinext = 48
meipa   = 00001fff
Enabling IRQ 11
-> external irq handler
meinext = 44
meipa   = 00000fff
Enabling IRQ 10
-> external irq handler
meinext = 40
meipa   = 000007ff
Enabling IRQ 9
-> external irq handler
meinext = 36
meipa   = 000003ff
Enabling IRQ 8
-> external irq handler
meinext = 32
meipa   = 000001ff
Enabling IRQ 7
-> external irq handler
meinext = 28
meipa   = 000000ff
Enabling IRQ 6
-> external irq handler
meinext = 24
meipa   = 0000007f
Enabling IRQ 5
-> external irq handler
meinext = 20
meipa   = 0000003f
Enabling IRQ 4
-> external irq handler
meinext = 16
meipa   = 0000001f
Enabling IRQ 3
-> external irq handler
meinext = 12
meipa   = 0000000f
Enabling IRQ 2
-> external irq handler
meinext = 8
meipa   = 00000007
Enabling IRQ 1
-> external irq handler
meinext = 4
meipa   = 00000003
Enabling IRQ 0
-> external irq handler
meinext = 0
meipa   = 00000001

*******************************************************************************/
