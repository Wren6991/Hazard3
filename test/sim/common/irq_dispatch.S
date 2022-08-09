#include "hazard3_csr.h"

.global isr_external_irq
isr_external_irq:
	// Save caller saves and exception return state whilst IRQs are disabled.
	// We can't be pre-empted during this time, but if a higher-priority IRQ
	// arrives ("late arrival"), that will be the one displayed in meinext. 
	addi sp, sp, -80
	sw ra,  0(sp)
	sw t0,  4(sp)
	sw t1,  8(sp)
	sw t2, 12(sp)
	sw a0, 16(sp)
	sw a1, 20(sp)
	sw a2, 24(sp)
	sw a3, 28(sp)
	sw a4, 32(sp)
	sw a5, 36(sp)
	sw a6, 40(sp)
	sw a7, 44(sp)
	sw t3, 48(sp)
	sw t4, 52(sp)
	sw t5, 56(sp)
	sw t6, 60(sp)

	// Update a count of the number of external IRQ vector entries (just for
	// use in tests)
	la a0, _external_irq_entry_count
	lw a1, (a0)
	addi a1, a1, 1
	sw a1, (a0)
	// Make sure to delete the above ^^^ if you use this code for real!

	csrr a0, mepc
	sw a0, 64(sp)
	// Make sure to set meicontext.clearts to clear and save mie.msie/mtie
	// when saving context.
	csrrsi a0, hazard3_csr_meicontext, 0x2
	sw a0, 68(sp)
	csrr a0, mstatus
	sw a0, 72(sp)

	j get_next_irq

dispatch_irq:
	// Preemption priority was configured by meinext update, so enable preemption:
	csrsi mstatus, 0x8
	// meinext is pre-shifted by 2, so only an add is required to index table
	la a1, _external_irq_table
	add a1, a1, a0
	lw a1, (a1)
	jalr ra, a1

	// Disable IRQs on returning so we can sample the next IRQ
	csrci mstatus, 0x8

get_next_irq:
	// Sample the current highest-priority active IRQ (left-shifted by 2) from
	// meinext, and write 1 to the LSB to tell hardware to tell hw to update
	// meicontext with the preemption priority (and IRQ number) of this IRQ
	csrrsi a0, hazard3_csr_meinext, 0x1
	// MSB will be set if there is no active IRQ at the current priority level
	bgez a0, dispatch_irq

no_more_irqs:
	// Restore saved context and return from IRQ
	lw a0, 64(sp)
	csrw mepc, a0
	lw a0, 68(sp)
	csrw hazard3_csr_meicontext, a0
	lw a0, 72(sp)
	csrw mstatus, a0

	lw ra,  0(sp)
	lw t0,  4(sp)
	lw t1,  8(sp)
	lw t2, 12(sp)
	lw a0, 16(sp)
	lw a1, 20(sp)
	lw a2, 24(sp)
	lw a3, 28(sp)
	lw a4, 32(sp)
	lw a5, 36(sp)
	lw a6, 40(sp)
	lw a7, 44(sp)
	lw t3, 48(sp)
	lw t4, 52(sp)
	lw t5, 56(sp)
	lw t6, 60(sp)
	addi sp, sp, 80
	mret

// ------------------------------------------------------------
// Handler table and default handler symbols

// Provide weak symbol for all IRQs, pointing to a breakpoint instruction:

.macro decl_eirq num
.weak isr_irq\num
isr_irq\num:
.endm

.macro ref_eirq num
.word isr_irq\num
.endm

#define NUM_IRQS 32

.equ i, 0
.rept NUM_IRQS
decl_eirq i
.equ i, i + 1
.endr
	ebreak

// Soft vector table is preloaded to RAM, and by default contains the weak ISR
// symbols, but can also be patched at runtime:

.section .data
.global _external_irq_table
_external_irq_table:

.equ i, 0
.rept NUM_IRQS
ref_eirq i
.equ i, i + 1
.endr

.global _external_irq_entry_count
_external_irq_entry_count:
.word 0
