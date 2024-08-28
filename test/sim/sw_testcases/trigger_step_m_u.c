#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "pmp.h"

// Test single-stepping of M-mode and U-mode code from an M-mode exception
// handler, using the icount trigger.

/*EXPECTED-OUTPUT***************************************************************

Smoke test
mcause = 3
Return to M, step on M
mcause = 3
Return to M, step on U
mcause = 11
Return to U, step on M
mcause = 8
Return to U, step on U
mcause = 3

*******************************************************************************/

void __attribute__((naked)) test_func() {
	asm volatile (
		"addi a0, a0, 123\n" // (always 32-bit)
		"ecall\n"            // (always 32-bit)
		"unimp\n"
	);
}

// Result mostly "returned" in mcause and mepc
// Returns `arg` in a0, possibly incremented by 123 (decimal)
uint32_t __attribute__((naked)) invoke_test_func(uint32_t arg, unsigned int priv) {
	asm volatile (
		// Set mpp as requested
		"li a2, 0x1800\n"
		"csrc mstatus, a2\n"
		"andi a1, a1, 0x3\n"
		"slli a1, a1, 11\n"
		"csrs mstatus, a1\n"
		// One way or another we're returning via trap
		"la a2, 1f\n"
		"csrw mtvec, a2\n"
		// Return to test_func() in the requested mode
		"la a2, test_func\n"
		"csrw mepc, a2\n"
		"mret\n"
	".p2align 2\n"
	"1:\n"
		"ret\n"
	);
}

void enable_step_on_mret(uint32_t mode_mask) {
	write_csr(tdata1, (mode_mask & 0xf) << 6);
	set_csr(tcontrol, 0x80); // mpte
}

uint32_t get_step_mode_mask() {
	return (read_csr(tdata1) >> 6) & 0xf;
}

int main() {
	// Grant U-mode execute permission (only) on all addresses
	write_pmpaddr(0, -1u);
	write_pmpcfg(0, PMPCFG_A_NAPOT << PMPCFG_A_LSB | PMPCFG_X_BITS);

	// Discover tselect for the breakpoint trigger
	bool found = false;
	uint32_t tselect = 0;
	while (!found) {
		write_csr(tselect, tselect);
		if (read_csr(tselect) != tselect) {
			// Exhausted tselect space
			break;
		}
		uint32_t tinfo = read_csr(tinfo);
		if (tinfo & (1u << 0)) {
			// Reached an unimplemented trigger
			break;
		}
		if (tinfo & (1u << 3)) {
			// Support for type=3 means this trigger supports icount
			found = true;
			break;
		}
		++tselect;
	}
	tb_assert(found, "Failed to find an icount trigger\n");
	// The tselect CSR will remain at its current value for the rest of the
	// test.

	tb_printf("Smoke test\n");
	asm volatile (
		"csrw mcause, zero\n"
		"la a0, 1f\n"
		"csrw mtvec, a0\n"
		// Enable M-mode step-break on the currently selected trigger
		"li a0, 1 << 9\n"
		"csrw tdata1, a0\n"
		// Enable M-mode triggers via tcontrol.mte
		"csrsi tcontrol, 0x8\n"
		// This instruction executes under the step
		"nop\n"
	".global smoke_test_break_addr\n"
	"smoke_test_break_addr:\n"
		// This instruction gets breakpointed
		"nop\n"
		// Breakpoint exception handler is here:
	".p2align 2\n"
	"1:\n"
	);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == 3, "Should get a breakpoint exception\n");
	tb_assert(read_csr(tcontrol) == 0x80, "Should have mpte set following trigger trap\n");
	extern char smoke_test_break_addr;
	tb_assert(read_csr(mepc) == (uintptr_t)&smoke_test_break_addr, "Wrong breakpoint address\n");

	tb_printf("Return to M, step on M\n");
	enable_step_on_mret(1u << 3);
	uint32_t ret;
	ret = invoke_test_func(456, 3);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == 3, "Bad exception cause\n"); // (ebreak)
	tb_assert(read_csr(mepc) == (uintptr_t)test_func + 4, "Bad exception pc\n");
	tb_assert(ret == 123 + 456, "Bad return value\n");
	tb_assert(get_step_mode_mask() == 0, "Bad enable mask\n");

	tb_printf("Return to M, step on U\n");
	enable_step_on_mret(1u << 0);
	ret = invoke_test_func(456, 3);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == 11, "Bad exception cause\n"); // (ecall from M-mode)
	tb_assert(read_csr(mepc) == (uintptr_t)test_func + 4, "Bad exception pc\n");
	tb_assert(ret == 123 + 456, "Bad return value\n");
	tb_assert(get_step_mode_mask() == (1u << 0), "Bad enable mask\n");


	tb_printf("Return to U, step on M\n");
	enable_step_on_mret(1u << 3);
	ret = invoke_test_func(456, 0);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == 8, "Bad exception cause\n"); // (ecall from U-mode)
	tb_assert(read_csr(mepc) == (uintptr_t)test_func + 4, "Bad exception pc\n");
	tb_assert(ret == 123 + 456, "Bad return value\n");
	tb_assert(get_step_mode_mask() == (1u << 3), "Bad enable mask\n");

	tb_printf("Return to U, step on U\n");
	enable_step_on_mret(1u << 0);
	ret = invoke_test_func(456, 0);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == 3, "Bad exception cause\n"); // (ebreak)
	tb_assert(read_csr(mepc) == (uintptr_t)test_func + 4, "Bad exception pc\n");
	tb_assert(ret == 123 + 456, "Bad return value\n");
	tb_assert(get_step_mode_mask() == 0, "Bad enable mask\n");

	return 0;
}
