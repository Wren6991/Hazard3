#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "pmp.h"

// Check that PMP correctly controls U-mode X permissions, with precedence to
// the lowest-numbered matching region. Check that partial region matches
// cause failure no matter the permission, unless there is a lower-numbered
// fully matching region.
//
// Check that jumping to a branch in non-X-permitted memory points mepc at the
// branch, not its target (known corner case)

/*EXPECTED-OUTPUT***************************************************************

Initial
mcause = 1
4-byte region
mcause = 8
Large region
mcause = 8
X under !X
mcause = 8
!X under X
mcause = 1
Full match under partial match, positive overhang
mcause = 8
Partial match under full match, positive overhang
mcause = 1
Full match under partial match, negative overhang
mcause = 8
Partial match under full match, negative overhang
mcause = 1
Jump to bad jump
OK

*******************************************************************************/

static inline void enter_umode(void (*f)(void)) {
	clear_csr(mstatus, 0x1800u);
	write_csr(mepc, f);
	// This function assumes that the U-mode callee will trap rather than
	// returning via ra.
	asm (
		"la s0, 1f\n"
		"csrrw s0, mtvec, s0\n"
		"mret\n"
		".p2align 2\n"
		"1:\n"
		"csrw mtvec, s0\n"
		: : : "s0"
	);
}

void __attribute__((aligned(4), naked)) do_ecall() {
	asm ("ecall");
}

// A 2-byte nop followed by a 4-byte nop, so that the second nop is only
// 2-byte-aligned. Useful for checking partial match detection.
void __attribute__((aligned(4), naked)) do_nops() {
	asm (
		"c.nop\n"
		".option push\n"
		".option norvc\n"
		"nop\n"
		".option pop\n"
		"ecall\n"
	);
}

void __attribute__((naked)) do_jump() {
	asm (
		"j 1f\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"nop\n"
		"1:\n"
		"ret\n"
	);
}

#define MCAUSE_INSTR_FAULT 1
#define MCAUSE_ECALL_UMODE 8

int main() {
	// Initially, there are no permissions active in the PMP, so we should get
	// an instruction access fault at the entry point.
	tb_puts("Initial\n");
	enter_umode(&do_ecall);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == MCAUSE_INSTR_FAULT, "Should get instruction fault when no X permission\n");
	tb_assert(read_csr(mepc) == (uint32_t)&do_ecall, "Bad mepc\n");

	// Setting a 4-byte X region on the ecall should let us call it in U mode.
	tb_puts("4-byte region\n");
	write_pmpcfg(0, PMPCFG_A_NA4 << PMPCFG_A_LSB | PMPCFG_X_BITS);
	write_pmpaddr(0, (uint32_t)&do_ecall >> 2);

	enter_umode(&do_ecall);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == MCAUSE_ECALL_UMODE, "Should successfully execute ecall\n");
	tb_assert(read_csr(mepc) == (uint32_t)&do_ecall, "Bad mepc\n");

	// Make the region larger (all of memory) -- should still pass.
	tb_puts("Large region\n");
	write_pmpcfg(0, PMPCFG_A_NAPOT << PMPCFG_A_LSB |PMPCFG_X_BITS);
	write_pmpaddr(0, -1u);

	enter_umode(&do_ecall);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == MCAUSE_ECALL_UMODE, "Should successfully execute ecall\n");
	tb_assert(read_csr(mepc) == (uint32_t)&do_ecall, "Bad mepc\n");

	// Put another region on top, with no permissions -- should still pass
	// because lower-numbered regions take precedence.
	tb_puts("X under !X\n");
	write_pmpcfg(0, PMPCFG_A_NAPOT << PMPCFG_A_LSB | PMPCFG_X_BITS);
	write_pmpaddr(0, -1u);
	write_pmpcfg(1, PMPCFG_A_NAPOT << PMPCFG_A_LSB);
	write_pmpaddr(1, -1u);

	enter_umode(&do_ecall);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == MCAUSE_ECALL_UMODE, "Should successfully execute ecall\n");
	tb_assert(read_csr(mepc) == (uint32_t)&do_ecall, "Bad mepc\n");

	// Swap the two regions. Should now fail, because lower-numbered region
	// revokes permissions of higher-numbered region.
	tb_puts("!X under X\n");
	write_pmpcfg(1, PMPCFG_A_NAPOT << PMPCFG_A_LSB | PMPCFG_X_BITS);
	write_pmpcfg(0, PMPCFG_A_NAPOT << PMPCFG_A_LSB);

	enter_umode(&do_ecall);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == MCAUSE_INSTR_FAULT, "Should get instruction fault when no X permission\n");
	tb_assert(read_csr(mepc) == (uint32_t)&do_ecall, "Bad mepc\n");

	// Now we'll use two regions, both with X permission, one matching all of
	// memory and one matching the first 4 bytes of a function. The function
	// is crafted to have a 4-byte instruction starting 2 bytes into the
	// function, so will partially match the small region.

	// First of all: small region at higher region number. Should pass,
	// because the lower-numbered region overrides the bad match.
	tb_puts("Full match under partial match, positive overhang\n");
	write_pmpcfg(0, PMPCFG_A_NAPOT << PMPCFG_A_LSB | PMPCFG_X_BITS);
	write_pmpaddr(0, -1u);
	write_pmpcfg(1, PMPCFG_A_NA4 << PMPCFG_A_LSB | PMPCFG_X_BITS);
	write_pmpaddr(1, (uint32_t)&do_nops >> 2);

	enter_umode(&do_nops);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == MCAUSE_ECALL_UMODE, "Should successfully execute ecall\n");
	tb_assert(read_csr(mepc) == (uint32_t)&do_nops + 6, "Bad mepc\n");

	// Now swap the order of the regions. The partial match of the
	// lower-numbered region should override its permissions and the
	// permissions of the higher-numbered region.
	tb_puts("Partial match under full match, positive overhang\n");
	write_pmpcfg(0, PMPCFG_A_NA4 << PMPCFG_A_LSB | PMPCFG_X_BITS);
	write_pmpaddr(0, (uint32_t)&do_nops >> 2);
	write_pmpcfg(1, PMPCFG_A_NAPOT << PMPCFG_A_LSB | PMPCFG_X_BITS);
	write_pmpaddr(1, -1u);

	enter_umode(&do_nops);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == MCAUSE_INSTR_FAULT, "Should get instruction fault on partial match\n");
	tb_assert(read_csr(mepc) == (uint32_t)&do_nops + 2, "Bad mepc\n");

	// Now do the same two tests, but with the partial match on the second
	// half of the instruction rather than the first half
	tb_puts("Full match under partial match, negative overhang\n");
	write_pmpcfg(0, PMPCFG_A_NAPOT << PMPCFG_A_LSB | PMPCFG_X_BITS);
	write_pmpaddr(0, -1u);
	write_pmpcfg(1, PMPCFG_A_NA4 << PMPCFG_A_LSB | PMPCFG_X_BITS);
	write_pmpaddr(1, ((uint32_t)&do_nops + 4) >> 2);

	enter_umode(&do_nops);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == MCAUSE_ECALL_UMODE, "Should successfully execute ecall\n");
	tb_assert(read_csr(mepc) == (uint32_t)&do_nops + 6, "Bad mepc\n");

	tb_puts("Partial match under full match, negative overhang\n");
	write_pmpcfg(0, PMPCFG_A_NA4 << PMPCFG_A_LSB | PMPCFG_X_BITS);
	write_pmpaddr(0, ((uint32_t)&do_nops + 4) >> 2);
	write_pmpcfg(1, PMPCFG_A_NAPOT << PMPCFG_A_LSB | PMPCFG_X_BITS);
	write_pmpaddr(1, -1u);

	enter_umode(&do_nops);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == MCAUSE_INSTR_FAULT, "Should get instruction fault on partial match\n");
	tb_assert(read_csr(mepc) == (uint32_t)&do_nops + 2, "Bad mepc\n");

	tb_puts("Jump to bad jump\n");
	write_pmpcfg(0, 0);
	write_pmpcfg(1, 0);
	enter_umode(&do_jump);
	tb_assert(read_csr(mepc) == (uint32_t)&do_jump, "Bad mepc\n");
	tb_puts("OK\n");

	return 0;
}
