#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "pmp.h"

// Check that PMP correctly controls U-mode R/W permissions, for all three
// access sizes.

#define MCAUSE_LOAD_FAULT 5
#define MCAUSE_STORE_FAULT 7
#define MCAUSE_ECALL_UMODE 8

/*EXPECTED-OUTPUT***************************************************************

Initial word read/write check
mcause = 8
mcause = 8
Remove read permission, word read/write
mcause = 8
mcause = 5
Restore read permission, remove write permission, word read/write
mcause = 7
mcause = 8
Remove read permission, halfword read/write
mcause = 8
mcause = 5
Restore read permission, remove write permission, halfword read/write
mcause = 7
mcause = 8
Remove read permission, byte read/write
mcause = 8
mcause = 5
Restore read permission, remove write permission, byte read/write
mcause = 7
mcause = 8

*******************************************************************************/

typedef uint32_t uxlen_t;
typedef uxlen_t (*umode_func_2a_1r)(uxlen_t, uxlen_t);

// /!\ Unconventional control flow ahead

// Call a function in U-mode, from M-mode, with two register arguments and one
// register result. If the function traps, mcause/mepc indicate the trap
// cause. Otherwise mcause is set to U-mode ecall (= 8).	

uxlen_t __attribute__((naked)) call_umode(umode_func_2a_1r f, uxlen_t a0, uxlen_t a1) {
	asm (
		"addi sp, sp, -16                                                     \n"
		"sw s0, 0(sp)                                                         \n"
		"sw ra, 4(sp)                                                         \n"
		// Set up mret target address and mode
		"csrw mepc, a0                                                        \n"
		"li a0, 0x1800                                                        \n"
		"csrc mstatus, a0                                                     \n"
		// Set up arguments
		"mv a0, a1                                                            \n"
		"mv a1, a2                                                            \n"
		// Set up two return paths: trap -> mtvec, or ret -> ecall -> mtvec
		"la s0, 1f                                                            \n"
		"addi ra, s0, -4                                                      \n"
		"csrrw s0, mtvec, s0                                                  \n"
		// Call the function
		"mret                                                                 \n"
		// Join return paths and restore mtvec
		".p2align 2                                                           \n"
		"ecall                                                                \n"
		"1:                                                                   \n"
		"csrw mtvec, s0                                                       \n"
		// Then return via saved ra
		"lw s0, 0(sp)                                                         \n"
		"lw ra, 4(sp)                                                         \n"
		"addi sp, sp, 16                                                      \n"
		"ret                                                                  \n"
	);
}

void __attribute__((naked)) do_sw(uxlen_t a, uxlen_t d) {
	asm volatile (
		"sw a1, (a0)\n"
		"ecall\n"
	);
}

void __attribute__((naked)) do_sh(uxlen_t a, uxlen_t d) {
	asm volatile (
		"sh a1, (a0)\n"
		"ecall\n"
	);
}

void __attribute__((naked)) do_sb(uxlen_t a, uxlen_t d) {
	asm volatile (
		"sb a1, (a0)\n"
		"ecall\n"
	);
}

uxlen_t __attribute__((naked)) do_lw(uxlen_t a) {
	asm volatile (
		"lw a0, (a0)\n"
		"ecall"
	);
}

uxlen_t __attribute__((naked)) do_lhu(uxlen_t a) {
	asm volatile (
		"lhu a0, (a0)\n"
		"ecall"
	);
}

uxlen_t __attribute__((naked)) do_lbu(uxlen_t a) {
	asm volatile (
		"lbu a0, (a0)\n"
		"ecall"
	);
}

volatile uint32_t scratch_word;

int main() {
	// We will keep PMP region 1 as an all-permission grant on all of memory,
	// and then use PMP region 0 to alter the permissions of only the
	// targeted scratch word.
	write_pmpcfg(1, PMPCFG_A_NAPOT << PMPCFG_A_LSB | PMPCFG_R_BITS | PMPCFG_W_BITS | PMPCFG_X_BITS);
	write_pmpaddr(1, -1u);
	write_pmpaddr(0, (uint32_t)&scratch_word >> 2);

	// Region 1 is not yet active, so we should have full permissions on this word.
	tb_puts("Initial word read/write check\n");
	scratch_word = 0;
	(void)call_umode((umode_func_2a_1r)&do_sw, (uintptr_t)&scratch_word, 0x12345678);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(scratch_word == 0x12345678, "Failed to write\n");

	uint32_t readback = call_umode((umode_func_2a_1r)&do_lw, (uintptr_t)&scratch_word, 0);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(readback == scratch_word, "Failed to read\n");

	// Change permissions to WX, and repeat previous test, making sure we get
	// the correct traps from the correct places, and trapped instructions
	// have their side effects suppressed.
	tb_puts("Remove read permission, word read/write\n");
	write_pmpcfg(0, PMPCFG_A_NA4 << PMPCFG_A_LSB | PMPCFG_W_BITS | PMPCFG_X_BITS);
	scratch_word = 0;
	(void)call_umode((umode_func_2a_1r)&do_sw, (uintptr_t)&scratch_word, 0x12345678);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(scratch_word == 0x12345678, "Failed to write\n");

	readback = call_umode((umode_func_2a_1r)&do_lw, (uintptr_t)&scratch_word, 0);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mepc) == (uint32_t)&do_lw, "Trap should come from load instruction\n");
	tb_assert(readback == (uintptr_t)&scratch_word, "Load instruction should not have written back\n");

	// Now again, with permissions set to RX.
	tb_puts("Restore read permission, remove write permission, word read/write\n");
	write_pmpcfg(0, PMPCFG_A_NA4 << PMPCFG_A_LSB | PMPCFG_R_BITS | PMPCFG_X_BITS);
	scratch_word = 0xdeadbeefu;
	(void)call_umode((umode_func_2a_1r)&do_sw, (uintptr_t)&scratch_word, 0x12345678);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mepc) == (uint32_t)&do_sw, "Trap should come from store instruction\n");
	tb_assert(scratch_word == 0xdeadbeefu, "Should not have written to memory\n");

	readback = call_umode((umode_func_2a_1r)&do_lw, (uintptr_t)&scratch_word, 0);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(readback == scratch_word, "Failed to read\n");

	// Repeat previous two tests with halfword access at top of region
	tb_puts("Remove read permission, halfword read/write\n");
	write_pmpcfg(0, PMPCFG_A_NA4 << PMPCFG_A_LSB | PMPCFG_W_BITS | PMPCFG_X_BITS);
	scratch_word = 0;
	(void)call_umode((umode_func_2a_1r)&do_sh, (uintptr_t)&scratch_word + 2, 0x12345678);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(scratch_word == 0x56780000u, "Failed to write\n");

	readback = call_umode((umode_func_2a_1r)&do_lhu, (uintptr_t)&scratch_word + 2, 0);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mepc) == (uint32_t)&do_lhu, "Trap should come from load instruction\n");
	tb_assert(readback == (uintptr_t)&scratch_word + 2, "Load instruction should not have written back\n");

	tb_puts("Restore read permission, remove write permission, halfword read/write\n");
	write_pmpcfg(0, PMPCFG_A_NA4 << PMPCFG_A_LSB | PMPCFG_R_BITS | PMPCFG_X_BITS);
	scratch_word = 0xdeadbeefu;
	(void)call_umode((umode_func_2a_1r)&do_sh, (uintptr_t)&scratch_word + 2, 0x12345678);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mepc) == (uint32_t)&do_sh, "Trap should come from store instruction\n");
	tb_assert(scratch_word == 0xdeadbeefu, "Should not have written to memory\n");

	readback = call_umode((umode_func_2a_1r)&do_lhu, (uintptr_t)&scratch_word + 2, 0);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(readback == scratch_word >> 16, "Failed to read\n");

	// Repeat previous two tests with byte access at top of region
	tb_puts("Remove read permission, byte read/write\n");
	write_pmpcfg(0, PMPCFG_A_NA4 << PMPCFG_A_LSB | PMPCFG_W_BITS | PMPCFG_X_BITS);
	scratch_word = 0;
	(void)call_umode((umode_func_2a_1r)&do_sb, (uintptr_t)&scratch_word + 3, 0x12345678);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(scratch_word == 0x78000000u, "Failed to write\n");

	readback = call_umode((umode_func_2a_1r)&do_lbu, (uintptr_t)&scratch_word + 3, 0);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mepc) == (uint32_t)&do_lbu, "Trap should come from load instruction\n");
	tb_assert(readback == (uintptr_t)&scratch_word + 3, "Load instruction should not have written back\n");

	tb_puts("Restore read permission, remove write permission, byte read/write\n");
	write_pmpcfg(0, PMPCFG_A_NA4 << PMPCFG_A_LSB | PMPCFG_R_BITS | PMPCFG_X_BITS);
	scratch_word = 0xdeadbeefu;
	(void)call_umode((umode_func_2a_1r)&do_sb, (uintptr_t)&scratch_word + 3, 0x12345678);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mepc) == (uint32_t)&do_sb, "Trap should come from store instruction\n");
	tb_assert(scratch_word == 0xdeadbeefu, "Should not have written to memory\n");

	readback = call_umode((umode_func_2a_1r)&do_lbu, (uintptr_t)&scratch_word + 3, 0);
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(readback == scratch_word >> 24, "Failed to read\n");

	return 0;
}
