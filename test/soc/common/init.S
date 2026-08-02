#include "hazard3_csr.h"

#define IO_BASE 0x4000400C
#define IO_PRINT_CHAR (IO_BASE + 0x0)
#define IO_PRINT_U32  (IO_BASE + 0x4)
#define IO_EXIT       (IO_BASE + 0x8)

// Provide trap vector table, reset handler and weak default trap handlers for
// Hazard3. This is not a crt0: the reset handler calls an external _start

.option push
.option norelax

.section .vectors

.macro VEC name:req
.p2align 2
j \name
.p2align 2
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

// ----------------------------------------------------------------------------
// Reset handler


.global reset_handler
reset_handler:
	// Set counters running, as they are off by default. This may trap if counters
	// are unimplemented, so catch the trap and continue.
	la a0, 1f
	csrw mtvec, a0
	csrci mcountinhibit, 0x5
	j 2f
.p2align 2
1:
	csrw mcause, zero
2:

	// Set up trap vector table. mtvec LSB enables vectoring
	la a0, .vector_table + 1
	csrw mtvec, a0

	// Ensure gp is initialised on all cores -- don't wait for newlib _start
	// as that is core-0-only
.option push
.option norelax
	la gp, __global_pointer$
.option pop

	// Put spare cores to sleep before setting up core 0 stack
	// Note csrr is a NOP when there are no CSRs at all (no traps!):
	li a0, 0
	csrr a0, mhartid
	bnez a0, .core1_wait

	// Set up stack pointer before doing anything else
	la sp, __stack_top

	// newlib _start expects argc, argv on the stack. Leave stack 16-byte aligned.
	addi sp, sp, -16
	li a0, 1
	sw a0, (sp)
	la a0, progname
	sw a0, 4(sp)

	jal _start
	j .halt

.core1_wait:
	// IRQs disabled, but soft IRQ unmasked -> soft IRQ will exit WFI.
	csrci mstatus, 0x8
	csrw mie, 0x8
.core1_wait_loop:
	wfi
	la a0, core1_entry_vector
	lw a0, (a0)
	beqz a0, .core1_wait_loop
	la sp, __stack_top - 0x10000
	jalr a0
.core1_finish:
	wfi
	j .core1_finish

.p2align 2
.global core1_entry_vector
core1_entry_vector:
	.word 0

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
	.asciz "hazard3-testbench"

.p2align 2

// ----------------------------------------------------------------------------
// Weak handler/ISR symbols

// Routine to print out trap name, trap address, and some core registers
// (x8..x15, ra, sp). The default  handlers are all patched into this routine,
// so the CPU will print some basic diagnostics on any unhandled trap
// (assuming the processor is not internally completely broken)

// argument in t0, IO pointer in t1, return in tp, trashes t0 and t2;
_tb_puts:
1:
	lbu t2, (t0)
	addi t0, t0, 1
	beqz t2, 2f
	sw t2, IO_PRINT_CHAR - IO_BASE(t1)
	j 1b
2:
	jr tp

.macro print_reg str reg
	la t0, \str
	jal tp, _tb_puts
	sw \reg, IO_PRINT_U32 - IO_BASE(t1)
.endm

_weak_handler_name_in_gp:
	la t0, _str_unhandled_trap
	li t1, IO_BASE
	jal tp, _tb_puts
	mv t0, gp
	jal tp, _tb_puts
	la t0, _str_at_mepc
	jal tp, _tb_puts
	csrr t0, mepc
	sw t0, IO_PRINT_U32 - IO_BASE(t1)
	csrr gp, mcause
	bltz gp, 1f
	print_reg _str_mcause gp
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
	li t2, -1
	sw t2, IO_EXIT - IO_BASE(t1)
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
.p2align 2

// Provide a default weak handler for each trap, which calls into the above
// diagnostic routine with the trap name (a null-terminated string) in gp

.macro weak_handler name:req
.p2align 2
.global \name
.weak \name
\name:
	la gp, _str_\name
	j _weak_handler_name_in_gp
_str_\name:
	.asciz "\name"
.endm

weak_handler handle_exception
weak_handler isr_machine_softirq
weak_handler isr_machine_timer
weak_handler isr_external_irq

// You can relax now
.option pop
