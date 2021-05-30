#define COLLAPSE_WEAK_HANDLERS

#define IO_BASE 0x80000000
#define IO_PRINT_CHAR (IO_BASE + 0x0)
#define IO_PRINT_U32  (IO_BASE + 0x4)
#define IO_EXIT       (IO_BASE + 0x8)

// Provide trap vector table, reset handler and weak default trap handlers for
// Hazard5. This is not a crt0: the reset handler calls an external _start


.option push
.option norelax
.option norvc

.section .vectors

.macro VEC name:req
.p2align 2
j \name
.endm

// ----------------------------------------------------------------------------
// Vector table (must be at least aligned to its size rounded up to power of 2)

.p2align 8
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
	VEC .halt
	VEC .halt
	VEC .halt
	VEC .halt
	VEC .halt

// External interrupts, if vectoring is enabled

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


// ----------------------------------------------------------------------------
// Reset handler


.reset_handler:
	la sp, __stack_top
	la t0, .vector_table
	// Set mtvec LSB to enable vectoring
	ori t0, t0, 1
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

heap_ptr:
	.word _end

.global .halt
.halt:
	j .halt

progname:
	.asciz "hazard5-testbench"

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
.type \name,%function
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

// You can relax now
.option pop
