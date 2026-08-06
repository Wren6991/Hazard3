#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Test that a breakpoint at the return target of a cm.popret(z) observes the
// correct exception PC.

/*EXPECTED-OUTPUT***************************************************************

Case 0: popret, ra only
Exception, mcause = 3
mepc = target0
Case 1: popret, multiple regs
Exception, mcause = 3
mepc = target1
Case 2: popretz, ra only
Exception, mcause = 3
mepc = target2
Case 3: popretz, multiple regs
Exception, mcause = 3
mepc = target3

*******************************************************************************/

extern uint16_t target0;
extern uint16_t target1;
extern uint16_t target2;
extern uint16_t target3;

#define N_TRIGGERS 4

#define TCONTROL_MPTE 0x80
#define TCONTROL_MTE 0x08

#define MCONTROL_M 0x40
#define MCONTROL_U 0x08
#define MCONTROL_EXECUTE 0x04

void deinit_breakpoints() {
	write_csr(tcontrol, 0);
	for (int i = 0; i < N_TRIGGERS; ++i) {
		write_csr(tselect, i);
		write_csr(tdata1, 0);
		write_csr(tdata2, 0);
	}
}

void set_mmode_breakpoint(int trigger, uint16_t* addr) {
	write_csr(tcontrol, TCONTROL_MPTE | TCONTROL_MTE);
	write_csr(tselect, trigger);
	write_csr(tdata2, (uintptr_t)addr); // set address *first*
	write_csr(tdata1, MCONTROL_M | MCONTROL_EXECUTE);
}

int main() {
	deinit_breakpoints();

	tb_puts("Case 0: popret, ra only\n");
	set_mmode_breakpoint(0, &target0);
	asm volatile (
		"la ra, target0\n"
		".insn 2, 0xb842\n" // cm.push {ra}, -16
		".insn 2, 0xbe42\n" // cm.popret {ra},16
		"1: j 1b\n" // death on fallthrough
	".global target0\n"
	"target0:\n"
		"nop\n"
		: : : "ra"
	);

	tb_puts("Case 1: popret, multiple regs\n");
	set_mmode_breakpoint(0, &target1);
	asm volatile (
		"la ra, target1\n"
		".insn 2, 0xb872\n" // cm.push {ra,s0-s2}, -16
		".insn 2, 0xbe72\n" // cm.popret {ra,s0-s2}, 16
		"1: j 1b\n" // death on fallthrough
	".global target1\n"
	"target1:\n"
		"nop\n"
		: : : "ra"
	);

	tb_puts("Case 2: popretz, ra only\n");
	set_mmode_breakpoint(0, &target2);
	asm volatile (
		"la ra, target2\n"
		".insn 2, 0xb842\n" // cm.push {ra}, -16
		".insn 2, 0xbc42\n" // cm.popretz {ra},16
		"1: j 1b\n" // death on fallthrough
	".global target2\n"
	"target2:\n"
		"nop\n"
		: : : "ra", "a0"
	);

	tb_puts("Case 3: popretz, multiple regs\n");
	set_mmode_breakpoint(0, &target3);
	asm volatile (
		"la ra, target3\n"
		".insn 2, 0xb872\n" // cm.push {ra,s0-s2}, -16
		".insn 2, 0xbc72\n" // cm.popretz {ra,s0-s2}, 16
		"1: j 1b\n" // death on fallthrough
	".global target3\n"
	"target3:\n"
		"nop\n"
		: : : "ra", "a0"
	);
}

void __attribute__((interrupt)) handle_exception(void) {
	tb_printf("Exception, mcause = %d\n", read_csr(mcause));
	uintptr_t mepc = read_csr(mepc);
	// Keep prints position-independent for passing test runs:
	if (mepc == (uintptr_t)&target0) {
		tb_puts("mepc = target0\n");
	} else if (mepc == (uintptr_t)&target1) {
		tb_puts("mepc = target1\n");
	} else if (mepc == (uintptr_t)&target2) {
		tb_puts("mepc = target2\n");
	} else if (mepc == (uintptr_t)&target3) {
		tb_puts("mepc = target3\n");
	} else {
		tb_printf("mepc = %08x\n", mepc);
	}
	deinit_breakpoints();
}
