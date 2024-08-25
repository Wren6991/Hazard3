#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "pmp.h"

#define N_TRIGGERS 4
#define N_NOPS 4

#define TCONTROL_MPTE 0x80
#define TCONTROL_MTE 0x08

#define MCONTROL_U 0x08
#define MCONTROL_EXECUTE 0x04

// Basic test for M-mode installing hardware breakpoints which trigger in U-mode.

void __attribute__((naked)) umode_nops() {
	asm volatile (
	".rept 4\n"
		"nop\n"
	".endr\n"
		"ecall\n"
	);
}

// result "returned" in mcause and mepc
void run_umode_nops() {
	asm volatile (
		"csrw mcause, zero\n"
		"li t0, 0x1800\n" // MPP
		"csrc mstatus, t0\n"
		"la t0, 1f\n"
		"csrw mtvec, t0\n"
		"csrw mepc, %0\n"
		"mret\n"
	".p2align 2\n"
	"1:\n"
		:
		: "r" ((uintptr_t)umode_nops)
		: "t0"
	);
}

void deinit_breakpoints() {
	write_csr(tcontrol, 0);
	for (int i = 0; i < N_TRIGGERS; ++i) {
		write_csr(tselect, i);
		write_csr(tdata1, 0);
		write_csr(tdata2, 0);
	}
}

void set_umode_breakpoint(int trigger, uintptr_t addr) {
	// Setting MPTE rather than MTE because we want the trigger to become
	// enabled upon returning to U-mode via mret.
	write_csr(tcontrol, TCONTROL_MPTE);
	write_csr(tselect, trigger);
	write_csr(tdata2, addr); // set address *first*
	write_csr(tdata1, MCONTROL_U | MCONTROL_EXECUTE);
}

int main() {
	// Grant U-mode execute permission (only) on all addresses
	write_pmpaddr(0, -1u);
	write_pmpcfg(0, PMPCFG_A_NAPOT << PMPCFG_A_LSB | PMPCFG_X_BITS);

	deinit_breakpoints();
	tb_printf("Sanity check: no breakpoints set\n");
	run_umode_nops();
	tb_printf("mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mcause) == 8, "should be U-mode ecall\n");

#if defined(__riscv_c) || defined(__riscv_zca)
	const int nop_size = 2;
#else
	const int nop_size = 4;
#endif

	for (int t = 0; t < N_TRIGGERS; ++t) {
		tb_printf("Testing trigger %d\n", t);
		deinit_breakpoints();
		for (int n = 0; n < N_NOPS + 2; ++n) {
			tb_printf("  offset = %d nops\n", n);
			set_umode_breakpoint(t, (uintptr_t)umode_nops + n * nop_size);
			run_umode_nops();
			unsigned int mcause = read_csr(mcause);
			uintptr_t offset = read_csr(mepc) - (uintptr_t)umode_nops;
			tb_printf("  -> mcause = %u\n", read_csr(mcause));
			tb_printf("  -> mepc   = umode_nops + %02x\n", offset);
			if (n == N_NOPS + 1) {
				tb_assert(mcause == 8, "should be ecall\n");
				tb_assert(offset == nop_size * N_NOPS, "should point to ecall\n");
			} else {
				tb_assert(mcause == 3, "should be breakpoint\n");
				tb_assert(offset == nop_size * n, "should point to breakpoint\n");
			}
		}
	}

	return 0;
}

/*EXPECTED-OUTPUT***************************************************************

Sanity check: no breakpoints set
mcause = 8
Testing trigger 0
  offset = 0 nops
  -> mcause = 3
  -> mepc   = umode_nops + 00
  offset = 1 nops
  -> mcause = 3
  -> mepc   = umode_nops + 02
  offset = 2 nops
  -> mcause = 3
  -> mepc   = umode_nops + 04
  offset = 3 nops
  -> mcause = 3
  -> mepc   = umode_nops + 06
  offset = 4 nops
  -> mcause = 3
  -> mepc   = umode_nops + 08
  offset = 5 nops
  -> mcause = 8
  -> mepc   = umode_nops + 08
Testing trigger 1
  offset = 0 nops
  -> mcause = 3
  -> mepc   = umode_nops + 00
  offset = 1 nops
  -> mcause = 3
  -> mepc   = umode_nops + 02
  offset = 2 nops
  -> mcause = 3
  -> mepc   = umode_nops + 04
  offset = 3 nops
  -> mcause = 3
  -> mepc   = umode_nops + 06
  offset = 4 nops
  -> mcause = 3
  -> mepc   = umode_nops + 08
  offset = 5 nops
  -> mcause = 8
  -> mepc   = umode_nops + 08
Testing trigger 2
  offset = 0 nops
  -> mcause = 3
  -> mepc   = umode_nops + 00
  offset = 1 nops
  -> mcause = 3
  -> mepc   = umode_nops + 02
  offset = 2 nops
  -> mcause = 3
  -> mepc   = umode_nops + 04
  offset = 3 nops
  -> mcause = 3
  -> mepc   = umode_nops + 06
  offset = 4 nops
  -> mcause = 3
  -> mepc   = umode_nops + 08
  offset = 5 nops
  -> mcause = 8
  -> mepc   = umode_nops + 08
Testing trigger 3
  offset = 0 nops
  -> mcause = 3
  -> mepc   = umode_nops + 00
  offset = 1 nops
  -> mcause = 3
  -> mepc   = umode_nops + 02
  offset = 2 nops
  -> mcause = 3
  -> mepc   = umode_nops + 04
  offset = 3 nops
  -> mcause = 3
  -> mepc   = umode_nops + 06
  offset = 4 nops
  -> mcause = 3
  -> mepc   = umode_nops + 08
  offset = 5 nops
  -> mcause = 8
  -> mepc   = umode_nops + 08

*******************************************************************************/
