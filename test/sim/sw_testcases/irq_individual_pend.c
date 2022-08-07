#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "hazard3_irq.h"

// Set IRQ mask (meie0) wide-open, then pend the IRQs one by one and log their
// firing.

#define mie_meie 0x800u

int main() {
	asm volatile ("csrsi mstatus, 0x8");

	h3irq_array_write(hazard3_csr_meiea, 0, 0xffffu);
	h3irq_array_write(hazard3_csr_meiea, 1, 0xffffu);
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
	// External IRQ does not appear pending because, after taking the
	// interrupt, it no longer has sufficient priority to preempt.
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

Setting IRQ 0
-> external irq handler
meinext = 0
meipa   = 00000001
Setting IRQ 1
-> external irq handler
meinext = 4
meipa   = 00000002
Setting IRQ 2
-> external irq handler
meinext = 8
meipa   = 00000004
Setting IRQ 3
-> external irq handler
meinext = 12
meipa   = 00000008
Setting IRQ 4
-> external irq handler
meinext = 16
meipa   = 00000010
Setting IRQ 5
-> external irq handler
meinext = 20
meipa   = 00000020
Setting IRQ 6
-> external irq handler
meinext = 24
meipa   = 00000040
Setting IRQ 7
-> external irq handler
meinext = 28
meipa   = 00000080
Setting IRQ 8
-> external irq handler
meinext = 32
meipa   = 00000100
Setting IRQ 9
-> external irq handler
meinext = 36
meipa   = 00000200
Setting IRQ 10
-> external irq handler
meinext = 40
meipa   = 00000400
Setting IRQ 11
-> external irq handler
meinext = 44
meipa   = 00000800
Setting IRQ 12
-> external irq handler
meinext = 48
meipa   = 00001000
Setting IRQ 13
-> external irq handler
meinext = 52
meipa   = 00002000
Setting IRQ 14
-> external irq handler
meinext = 56
meipa   = 00004000
Setting IRQ 15
-> external irq handler
meinext = 60
meipa   = 00008000
Setting IRQ 16
-> external irq handler
meinext = 64
meipa   = 00010000
Setting IRQ 17
-> external irq handler
meinext = 68
meipa   = 00020000
Setting IRQ 18
-> external irq handler
meinext = 72
meipa   = 00040000
Setting IRQ 19
-> external irq handler
meinext = 76
meipa   = 00080000
Setting IRQ 20
-> external irq handler
meinext = 80
meipa   = 00100000
Setting IRQ 21
-> external irq handler
meinext = 84
meipa   = 00200000
Setting IRQ 22
-> external irq handler
meinext = 88
meipa   = 00400000
Setting IRQ 23
-> external irq handler
meinext = 92
meipa   = 00800000
Setting IRQ 24
-> external irq handler
meinext = 96
meipa   = 01000000
Setting IRQ 25
-> external irq handler
meinext = 100
meipa   = 02000000
Setting IRQ 26
-> external irq handler
meinext = 104
meipa   = 04000000
Setting IRQ 27
-> external irq handler
meinext = 108
meipa   = 08000000
Setting IRQ 28
-> external irq handler
meinext = 112
meipa   = 10000000
Setting IRQ 29
-> external irq handler
meinext = 116
meipa   = 20000000
Setting IRQ 30
-> external irq handler
meinext = 120
meipa   = 40000000
Setting IRQ 31
-> external irq handler
meinext = 124
meipa   = 80000000

*******************************************************************************/
