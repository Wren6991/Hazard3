#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Check lr/sc which encounter bus faults generate exceptions, and report the
// correct mcause and mepc.

/*EXPECTED-OUTPUT***************************************************************

Failed load, suppressed store
-> exception, mcause = 5
exception instr: 100627af
sc.w result: 0
Good load, failed store
-> exception, mcause = 7
exception instr: 18a5a52f
sc.w result: 123
Repeated failed store
sc.w result: 0

*******************************************************************************/

// Calling convention abuse to get stable register allocation without cursed
// register keyword. We need stable registers because the excepting
// instructions are in the test log.
uint32_t __attribute__((naked)) do_lr_sc(uint32_t initial_sc, uint32_t *dst, const uint32_t *src) {
	asm volatile (
		// a5 used as a dumpster
		"lr.w a5, (a2)\n"
		// a0 not written if sc.w suppressed -> return value == initial_sc
		"sc.w a0, a0, (a1)\n"
		"ret"
	);
}

int main() {
	uint32_t scratch_word;
	uint32_t sc_result;
	uint32_t *bad_addr = (uint32_t*)0xcdef1234u;
	uint32_t *good_addr = &scratch_word;

	// Only the lr.w should except, because failed lr.w clears the local monitor,
	// suppressing the sc.w.
	tb_puts("Failed load, suppressed store\n");
	sc_result = do_lr_sc(123, bad_addr, bad_addr);
	// Failing sc.w must write 0 to the success register.
	tb_printf("sc.w result: %u\n", sc_result);

	// This time the sc.w should fault, after the successful lr.w.
	tb_puts("Good load, failed store\n");
	sc_result = do_lr_sc(123, bad_addr, good_addr);
	// Excepted sc.w must not write the success register.
	tb_printf("sc.w result: %u\n", sc_result);

	tb_puts("Repeated failed store\n");
	// Repeat just the sc.w. This should now be suppressed, because the prior
	// faulting sc.w should clear the monitor bit.
	asm volatile (
		"sc.w %0, zero, (%1)\n"
		: "+r" (sc_result) : "r" (bad_addr)
	);
	// Failing sc.w must write 0 to result register.
	tb_printf("sc.w result: %u\n", sc_result);

	return 0;
}

void __attribute__((interrupt)) handle_exception() {
	tb_printf("-> exception, mcause = %u\n", read_csr(mcause));
	write_csr(mcause, 0);
	uint32_t mepc = read_csr(mepc);
	if ((*(uint16_t*)mepc & 0x3) == 0x3) {
		tb_printf("exception instr: %04x%04x\n", *(uint16_t*)(mepc + 2), *(uint16_t*)mepc);
		write_csr(mepc, mepc + 4);
	}
	else {
		tb_printf("exception instr: %04x\n", *(uint16_t*)(mepc + 2), *(uint16_t*)mepc);
		write_csr(mepc, mepc + 2);
	}
}
