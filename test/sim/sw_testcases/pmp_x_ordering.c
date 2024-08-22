#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "pmp.h"

// Test intent: check that updates to PMP X permissions reflect on the
// immediately-following instruction, and not on the immediately-preceding.
//
// R and W permissions are not that interesting as everything is resolved in
// stage 2. However X permissions are interesting because they are checked in
// stage 1 but updated in stage 2, so there is a hazard.

/*EXPECTED-OUTPUT***************************************************************

Test: !X -> !X with address before
mcause = 1
Test:  X -> !X with address before
mcause = 0
Test: !X ->  X with address before
mcause = 1
Test:  X ->  X with address before
mcause = 0
Test: !X -> !X with address after
mcause = 1
Test:  X -> !X with address after
mcause = 1
Test: !X ->  X with address after
mcause = 0
Test:  X ->  X with address after
mcause = 0

*******************************************************************************/

// Result is "returned" in mepc and mcause
void __attribute__((naked)) test_x(uint32_t addr, bool permit_before, bool permit_after) {
	asm volatile (
		"csrw mepc, zero\n"
		"csrw mcause, zero\n"
		"la t0, 9f\n"
		"csrw mtvec, t0\n"
		// Prescale address by /4 for NA4
		"srli a0, a0, 2\n"
		// Set NA4 + X/nX
		"slli a1, a1, 2\n"
		"addi a1, a1, 0x2 << 3\n"
		"slli a2, a2, 2\n"
		"addi a2, a2, 0x2 << 3\n"
		// Ensure region 0 is enforced in M-mode
		"csrs 0xbd0, 0x1\n"
		// Set permission before, then have some nops to let everything settle
		"csrw pmpcfg0, zero\n"
		"csrw pmpaddr0, a0\n"
		"csrw pmpcfg0, a1\n"
	".rept 10\n"
		"nop\n"
	".endr\n"
		// nop, CSR update, nop. The PMP address will be one of the two nops.
		// The nops are 32-bit (and aligned) so they can be wholly covered by
		// an NA4 PMP region.
	".p2align 2\n"
	".global test_x_instr_before\n"
	"test_x_instr_before:\n"
		"sltu t0, t0, t0\n" // 32-bit nop-ish
		"csrw pmpcfg0, a2\n"
	".global test_x_instr_after\n"
	"test_x_instr_after:\n"
		"sltu t0, t0, t0\n" // 32-bit nop-ish
	".p2align 2\n"
	"9:\n"
		"ret\n"
	);
}

extern char test_x_instr_before;
extern char test_x_instr_after;

int main() {
	for (int i = 0; i < 8; ++i) {
		bool permit_before = i & (1u << 0);
		bool permit_after  = i & (1u << 1);
		bool address_after = i & (1u << 2);
		tb_printf(
			"Test: %s -> %s with address %s\n",
			permit_before ? " X" : "!X",
			permit_after  ? " X" : "!X",
			address_after ? "after" : "before"
		);
		uintptr_t target_addr = address_after ? (uintptr_t)&test_x_instr_after : (uintptr_t)&test_x_instr_before;
		test_x(
			target_addr,
			permit_before,
			permit_after
		);
		bool expect_fault = address_after ? !permit_after : !permit_before;
		tb_printf("mcause = %u\n", read_csr(mcause));
		tb_assert(expect_fault == (read_csr(mcause) != 0), "unexpected mcause value");
		if (expect_fault) {
			tb_assert(read_csr(mepc) == target_addr, "unexpected mepc value: %08x\n", read_csr(mepc));
		}
	}
}
