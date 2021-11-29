#include "hazard3_csr.h"

#define IO_BASE 0x80000000
#define IO_PRINT_CHAR (IO_BASE + 0x0)
#define IO_PRINT_U32  (IO_BASE + 0x4)
#define IO_EXIT       (IO_BASE + 0x8)

// Provide trap vector table, reset handler and weak default trap handlers for
// Hazard5. This is not a crt0: the reset handler calls an external _start


.option push
.option norelax

.section .vectors

.macro VEC name:req
.p2align 2
j \name
.endm

// ----------------------------------------------------------------------------
// Vector table (must be at least aligned to its size rounded up to power of 2)

.p2align 12
.vector_table:

// Single exception vector, also takes IRQs if vectoring is disabled

	VEC handle_exception

// Standard interrupts, if vectoring is enabled
// Note: global EIRQ does not fire. Instead we have 16 separate vectors

	// handle_exception ^^^ takes the slot where U-mode softirq would be
	VEC .halt
	VEC .halt
	VEC isr_machine_softirq
	VEC .halt
	VEC .halt
	VEC .halt
	VEC isr_machine_timer
	VEC .halt
	VEC .halt
	VEC .halt
	VEC isr_external_irq
	VEC .halt
	VEC .halt
	VEC .halt
	VEC .halt

// When midcr.eivect is 1, hardware vectors IRQs directly to the
// platform-specific part of the vector table. Otherwise, software indexes
// this table in the prologue of a shared external IRQ handler.

.p2align 2
platform_vectors:

	VEC isr_irq0
	VEC isr_irq1
	VEC isr_irq2
	VEC isr_irq3
	VEC isr_irq4
	VEC isr_irq5
	VEC isr_irq6
	VEC isr_irq7
	VEC isr_irq8
	VEC isr_irq9
	VEC isr_irq10
	VEC isr_irq11
	VEC isr_irq12
	VEC isr_irq13
	VEC isr_irq14
	VEC isr_irq15
	VEC isr_irq16
	VEC isr_irq17
	VEC isr_irq18
	VEC isr_irq19
	VEC isr_irq20
	VEC isr_irq21
	VEC isr_irq22
	VEC isr_irq23
	VEC isr_irq24
	VEC isr_irq25
	VEC isr_irq26
	VEC isr_irq27
	VEC isr_irq28
	VEC isr_irq29
	VEC isr_irq30
	VEC isr_irq31


// ----------------------------------------------------------------------------
// Reset handler


.reset_handler:
	la sp, __stack_top
	// mtvec LSB enables vectoring
	la t0, .vector_table + 1
	csrw mtvec, t0

	// newlib _start expects argc, argv on the stack. Leave stack 16-byte aligned.
	addi sp, sp, -16
	li a0, 1
	sw a0, (sp)
	la a0, progname
	sw a0, 4(sp)

	jal _start
	j .halt

.global _exit
_exit:
	li a1, IO_EXIT
	sw a0, (a1)

.global _sbrk
_sbrk:
	la a1, heap_ptr
	lw a2, (a1)
	add a0, a0, a2
	sw a0, (a1)
	mv a0, a2
	ret

.p2align 2
heap_ptr:
	.word _end

.global .halt
.halt:
	j .halt

progname:
	.asciz "hazard5-testbench"

// ----------------------------------------------------------------------------
// Soft external IRQ dispatch

// Vector isr_external_irq to the relevant ISR, based on mcause. The ISR can
// be a standard C-ABI function. This method also leaves the possibility of
// using addresses in the IRQ vector table, rather than jump instructions.

.global isr_external_irq
.weak isr_external_irq
isr_external_irq:
	// Save all caller-saves, plus three callee saves for CSR saving
	addi sp, sp, -80
	sw ra,  0(sp)
	sw t0,  4(sp)
	sw t1,  8(sp)
	sw t2, 12(sp)
	sw t3, 16(sp)
	sw t4, 20(sp)
	sw t5, 24(sp)
	sw t6, 28(sp)
	sw a0, 32(sp)
	sw a1, 36(sp)
	sw a2, 40(sp)
	sw a3, 44(sp)
	sw a4, 48(sp)
	sw a5, 52(sp)
	sw a6, 56(sp)
	sw a7, 60(sp)
	sw s0, 64(sp)
	sw s1, 68(sp)
	sw s2, 72(sp)

	// Save exception state to callee-saves so we can use it for return
	csrr s0, mepc
	csrr s1, mstatus
	csrr s2, hazard3_csr_meie0

	// Calculate IRQ entry point
	csrr a0, mcause
	slli a0, a0, 2
	csrr a1, mtvec
	andi a1, a1, -4
	add a1, a1, a0

	// Mask off higher-numbered IRQs (and this IRQ), then re-enable IRQs so we
	// can be preempted. Could have some other priority scheme here.
	srli a0, a0, 2
	addi a0, a0, -16
	li a2, -1
	sll a2, a2, a0
	csrc hazard3_csr_meie0, a2
	csrsi mstatus, 8

	// Enter IRQ
	jalr a1
trap_return:
	// No more preemption until we mret.
	csrci mstatus, 8
	
	csrw mepc, s0
	csrw mstatus, s1
	csrw hazard3_csr_meie0, s2
	lw ra,  0(sp)
	lw t0,  4(sp)
	lw t1,  8(sp)
	lw t2, 12(sp)
	lw t3, 16(sp)
	lw t4, 20(sp)
	lw t5, 24(sp)
	lw t6, 28(sp)
	lw a0, 32(sp)
	lw a1, 36(sp)
	lw a2, 40(sp)
	lw a3, 44(sp)
	lw a4, 48(sp)
	lw a5, 52(sp)
	lw a6, 56(sp)
	lw a7, 60(sp)
	lw s0, 64(sp)
	lw s1, 68(sp)
	lw s2, 72(sp)
	addi sp, sp, 80
	mret


// ----------------------------------------------------------------------------
// Weak handler/ISR symbols

// Routine to print out trap name, trap address, and some core registers
// (x8..x15, ra, sp). The default  handlers are all patched into this routine,
// so the CPU will print some basic diagnostics on any unhandled trap
// (assuming the processor is not internally completely broken)

// argument in x28, return in x27, trashes x28...x30
_tb_puts:
	li x29, IO_PRINT_CHAR
1:
	lbu x30, (x28)
	addi x28, x28, 1
	beqz x30, 2f
	sw x30, (x29)
	j 1b
2:
	jr x27

.macro print_reg str reg
	la x28, \str
	jal x27, _tb_puts
	sw \reg, (x31)
.endm

_weak_handler_name_in_x31:
	la x28, _str_unhandled_trap
	jal x27, _tb_puts
	mv x28, x31
	jal x27, _tb_puts
	la x28, _str_at_mepc
	jal x27, _tb_puts
	li x31, IO_PRINT_U32
	csrr x28, mepc
	sw x28, (x31)
	csrr x26, mcause
	bltz x26, 1f
	print_reg _str_mcause x26
1:
	print_reg _str_s0 s0
	print_reg _str_s1 s1
	print_reg _str_a0 a0
	print_reg _str_a1 a1
	print_reg _str_a2 a2
	print_reg _str_a3 a3
	print_reg _str_a4 a4
	print_reg _str_a5 a5
	print_reg _str_ra ra
	print_reg _str_sp sp
	li x31, IO_EXIT
	li x30, -1
	sw x30, (x31)
	// Should be unreachable:
	j .halt

_str_unhandled_trap: .asciz "*** Unhandled trap ***\n"
_str_at_mepc:        .asciz " @ mepc = "
_str_mcause:         .asciz "                 mcause = "
_str_s0:             .asciz "s0: "
_str_s1:             .asciz "s1: "
_str_a0:             .asciz "a0: "
_str_a1:             .asciz "a1: "
_str_a2:             .asciz "a2: "
_str_a3:             .asciz "a3: "
_str_a4:             .asciz "a4: "
_str_a5:             .asciz "a5: "
_str_ra:             .asciz "ra: "
_str_sp:             .asciz "sp: "

// Provide a default weak handler for each trap, which calls into the above
// diagnostic routine with the trap name (a null-terminated string) in x31

.macro weak_handler name:req
.p2align 2
.global \name
.weak \name
\name:
	la x31, _str_\name
	j _weak_handler_name_in_x31
_str_\name:
	.asciz "\name"
.endm

weak_handler handle_exception
weak_handler isr_machine_softirq
weak_handler isr_machine_timer
weak_handler isr_irq0
weak_handler isr_irq1
weak_handler isr_irq2
weak_handler isr_irq3
weak_handler isr_irq4
weak_handler isr_irq5
weak_handler isr_irq6
weak_handler isr_irq7
weak_handler isr_irq8
weak_handler isr_irq9
weak_handler isr_irq10
weak_handler isr_irq11
weak_handler isr_irq12
weak_handler isr_irq13
weak_handler isr_irq14
weak_handler isr_irq15
weak_handler isr_irq16
weak_handler isr_irq17
weak_handler isr_irq18
weak_handler isr_irq19
weak_handler isr_irq20
weak_handler isr_irq21
weak_handler isr_irq22
weak_handler isr_irq23
weak_handler isr_irq24
weak_handler isr_irq25
weak_handler isr_irq26
weak_handler isr_irq27
weak_handler isr_irq28
weak_handler isr_irq29
weak_handler isr_irq30
weak_handler isr_irq31

// You can relax now
.option pop
