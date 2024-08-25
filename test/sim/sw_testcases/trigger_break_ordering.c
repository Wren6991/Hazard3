#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

#define TCONTROL_MPTE 0x80
#define TCONTROL_MTE 0x08

#define MCONTROL_ACTION_LSB 12
#define MCONTROL_M 0x40
#define MCONTROL_U 0x08
#define MCONTROL_EXECUTE 0x04

// Test intent: check that updates to breakpoint triggers from M-mode are
// reflected in immediately-following instructions, but not in earlier
// instructions or in the updating instruction itself.
//
// There is a hazard here because the breakpoint address match logic is in an
// earlier stage than the CSR writes.

typedef enum {
	timing_before,
	timing_exact,
	timing_after
} timing_t;

void __attribute__((interrupt)) handle_exception() {
	// Ensure triggers remain disabled when we return
	clear_csr(tcontrol, TCONTROL_MPTE);
	// Return directly to excepting instruction -- it should not except the
	// second time because triggers are now disabled (assuming a trigger was
	// the cause for the exception!)
}

// Result is "returned" in mcause and mepc
void test_timing_addr(unsigned int trignum, timing_t timing, bool enabled_before, bool enabled_after) {
	extern char addr_test_csr_write_instr;
	uintptr_t addr = (uintptr_t)&addr_test_csr_write_instr;
	if (timing == timing_before) {
		addr -= 2; // point back to nop
	} else if (timing == timing_after) {
		addr += 4; // point past CSR write
	}
	write_csr(mcause, 0);
	write_csr(mepc, 0);
	write_csr(tselect, trignum);
	if (enabled_before) {
		write_csr(tdata2, addr);
	} else {
		write_csr(tdata2, 0);
	}
	write_csr(tdata1, MCONTROL_M | MCONTROL_EXECUTE);
	set_csr(tcontrol, TCONTROL_MTE);
	asm volatile (
		"nop\n"
	".global addr_test_csr_write_instr\n"
	"addr_test_csr_write_instr:\n"
		"csrw tdata2, %0\n"
		"nop\n"
		: : "r" (enabled_after ? addr : 0)
	);
	write_csr(tdata1, 0);
}

void test_timing_enable(unsigned int trignum, timing_t timing, bool enabled_before, bool enabled_after) {
	extern char enable_test_csr_write_instr;
	uintptr_t addr = (uintptr_t)&enable_test_csr_write_instr;
	if (timing == timing_before) {
		addr -= 2; // point back to nop
	} else if (timing == timing_after) {
		addr += 4; // point past CSR write
	}
	write_csr(mcause, 0);
	write_csr(mepc, 0);
	write_csr(tselect, trignum);
	write_csr(tdata2, addr);
	if (enabled_before) {
		write_csr(tdata1, MCONTROL_M | MCONTROL_EXECUTE);
	} else {
		write_csr(tdata1, 0);
	}
	set_csr(tcontrol, TCONTROL_MTE);
	asm volatile (
		"nop\n"
	".global enable_test_csr_write_instr\n"
	"enable_test_csr_write_instr:\n"
		"csrw tdata1, %0\n"
		"nop\n"
		: : "r" (enabled_after ? MCONTROL_M | MCONTROL_EXECUTE : 0)
	);
	write_csr(tdata1, 0);
}

int main() {
	for (int i = 0; i < 3 * 4 * 2 * 2; ++i) {
		bool enabled_before = i & 0x1;
		bool enabled_after = i & 0x2;
		unsigned int trignum = (i >> 2) & 0x3;
		timing_t timing = (timing_t)(i >> 4);
		tb_printf(
			"Trigger %u, Address match: %c -> %c (match timing = %c)\n",
			trignum,
			"ny"[enabled_before],
			"ny"[enabled_after],
			"bea"[(int)timing]
		);
		test_timing_addr(trignum, timing, enabled_before, enabled_after);
		bool expect_fault = timing == timing_after ? enabled_after : enabled_before;
		tb_printf("mcause = %u\n", read_csr(mcause));
		tb_assert(read_csr(mcause) == (expect_fault ? 3 : 0), "unexpected mcause value\n");		tb_printf(
			"Trigger %u, enabled:       %c -> %c (match timing = %c)\n",
			trignum,
			"ny"[enabled_before],
			"ny"[enabled_after],
			"bea"[(int)timing]
		);
		test_timing_enable(trignum, timing, enabled_before, enabled_after);
		expect_fault = timing == timing_after ? enabled_after : enabled_before;
		tb_printf("mcause = %u\n", read_csr(mcause));
		tb_assert(read_csr(mcause) == (expect_fault ? 3 : 0), "unexpected mcause value\n");
	}
	return 0;
}


/*EXPECTED-OUTPUT***************************************************************

Trigger 0, Address match: n -> n (match timing = b)
mcause = 0
Trigger 0, enabled:       n -> n (match timing = b)
mcause = 0
Trigger 0, Address match: y -> n (match timing = b)
mcause = 3
Trigger 0, enabled:       y -> n (match timing = b)
mcause = 3
Trigger 0, Address match: n -> y (match timing = b)
mcause = 0
Trigger 0, enabled:       n -> y (match timing = b)
mcause = 0
Trigger 0, Address match: y -> y (match timing = b)
mcause = 3
Trigger 0, enabled:       y -> y (match timing = b)
mcause = 3
Trigger 1, Address match: n -> n (match timing = b)
mcause = 0
Trigger 1, enabled:       n -> n (match timing = b)
mcause = 0
Trigger 1, Address match: y -> n (match timing = b)
mcause = 3
Trigger 1, enabled:       y -> n (match timing = b)
mcause = 3
Trigger 1, Address match: n -> y (match timing = b)
mcause = 0
Trigger 1, enabled:       n -> y (match timing = b)
mcause = 0
Trigger 1, Address match: y -> y (match timing = b)
mcause = 3
Trigger 1, enabled:       y -> y (match timing = b)
mcause = 3
Trigger 2, Address match: n -> n (match timing = b)
mcause = 0
Trigger 2, enabled:       n -> n (match timing = b)
mcause = 0
Trigger 2, Address match: y -> n (match timing = b)
mcause = 3
Trigger 2, enabled:       y -> n (match timing = b)
mcause = 3
Trigger 2, Address match: n -> y (match timing = b)
mcause = 0
Trigger 2, enabled:       n -> y (match timing = b)
mcause = 0
Trigger 2, Address match: y -> y (match timing = b)
mcause = 3
Trigger 2, enabled:       y -> y (match timing = b)
mcause = 3
Trigger 3, Address match: n -> n (match timing = b)
mcause = 0
Trigger 3, enabled:       n -> n (match timing = b)
mcause = 0
Trigger 3, Address match: y -> n (match timing = b)
mcause = 3
Trigger 3, enabled:       y -> n (match timing = b)
mcause = 3
Trigger 3, Address match: n -> y (match timing = b)
mcause = 0
Trigger 3, enabled:       n -> y (match timing = b)
mcause = 0
Trigger 3, Address match: y -> y (match timing = b)
mcause = 3
Trigger 3, enabled:       y -> y (match timing = b)
mcause = 3
Trigger 0, Address match: n -> n (match timing = e)
mcause = 0
Trigger 0, enabled:       n -> n (match timing = e)
mcause = 0
Trigger 0, Address match: y -> n (match timing = e)
mcause = 3
Trigger 0, enabled:       y -> n (match timing = e)
mcause = 3
Trigger 0, Address match: n -> y (match timing = e)
mcause = 0
Trigger 0, enabled:       n -> y (match timing = e)
mcause = 0
Trigger 0, Address match: y -> y (match timing = e)
mcause = 3
Trigger 0, enabled:       y -> y (match timing = e)
mcause = 3
Trigger 1, Address match: n -> n (match timing = e)
mcause = 0
Trigger 1, enabled:       n -> n (match timing = e)
mcause = 0
Trigger 1, Address match: y -> n (match timing = e)
mcause = 3
Trigger 1, enabled:       y -> n (match timing = e)
mcause = 3
Trigger 1, Address match: n -> y (match timing = e)
mcause = 0
Trigger 1, enabled:       n -> y (match timing = e)
mcause = 0
Trigger 1, Address match: y -> y (match timing = e)
mcause = 3
Trigger 1, enabled:       y -> y (match timing = e)
mcause = 3
Trigger 2, Address match: n -> n (match timing = e)
mcause = 0
Trigger 2, enabled:       n -> n (match timing = e)
mcause = 0
Trigger 2, Address match: y -> n (match timing = e)
mcause = 3
Trigger 2, enabled:       y -> n (match timing = e)
mcause = 3
Trigger 2, Address match: n -> y (match timing = e)
mcause = 0
Trigger 2, enabled:       n -> y (match timing = e)
mcause = 0
Trigger 2, Address match: y -> y (match timing = e)
mcause = 3
Trigger 2, enabled:       y -> y (match timing = e)
mcause = 3
Trigger 3, Address match: n -> n (match timing = e)
mcause = 0
Trigger 3, enabled:       n -> n (match timing = e)
mcause = 0
Trigger 3, Address match: y -> n (match timing = e)
mcause = 3
Trigger 3, enabled:       y -> n (match timing = e)
mcause = 3
Trigger 3, Address match: n -> y (match timing = e)
mcause = 0
Trigger 3, enabled:       n -> y (match timing = e)
mcause = 0
Trigger 3, Address match: y -> y (match timing = e)
mcause = 3
Trigger 3, enabled:       y -> y (match timing = e)
mcause = 3
Trigger 0, Address match: n -> n (match timing = a)
mcause = 0
Trigger 0, enabled:       n -> n (match timing = a)
mcause = 0
Trigger 0, Address match: y -> n (match timing = a)
mcause = 0
Trigger 0, enabled:       y -> n (match timing = a)
mcause = 0
Trigger 0, Address match: n -> y (match timing = a)
mcause = 3
Trigger 0, enabled:       n -> y (match timing = a)
mcause = 3
Trigger 0, Address match: y -> y (match timing = a)
mcause = 3
Trigger 0, enabled:       y -> y (match timing = a)
mcause = 3
Trigger 1, Address match: n -> n (match timing = a)
mcause = 0
Trigger 1, enabled:       n -> n (match timing = a)
mcause = 0
Trigger 1, Address match: y -> n (match timing = a)
mcause = 0
Trigger 1, enabled:       y -> n (match timing = a)
mcause = 0
Trigger 1, Address match: n -> y (match timing = a)
mcause = 3
Trigger 1, enabled:       n -> y (match timing = a)
mcause = 3
Trigger 1, Address match: y -> y (match timing = a)
mcause = 3
Trigger 1, enabled:       y -> y (match timing = a)
mcause = 3
Trigger 2, Address match: n -> n (match timing = a)
mcause = 0
Trigger 2, enabled:       n -> n (match timing = a)
mcause = 0
Trigger 2, Address match: y -> n (match timing = a)
mcause = 0
Trigger 2, enabled:       y -> n (match timing = a)
mcause = 0
Trigger 2, Address match: n -> y (match timing = a)
mcause = 3
Trigger 2, enabled:       n -> y (match timing = a)
mcause = 3
Trigger 2, Address match: y -> y (match timing = a)
mcause = 3
Trigger 2, enabled:       y -> y (match timing = a)
mcause = 3
Trigger 3, Address match: n -> n (match timing = a)
mcause = 0
Trigger 3, enabled:       n -> n (match timing = a)
mcause = 0
Trigger 3, Address match: y -> n (match timing = a)
mcause = 0
Trigger 3, enabled:       y -> n (match timing = a)
mcause = 0
Trigger 3, Address match: n -> y (match timing = a)
mcause = 3
Trigger 3, enabled:       n -> y (match timing = a)
mcause = 3
Trigger 3, Address match: y -> y (match timing = a)
mcause = 3
Trigger 3, enabled:       y -> y (match timing = a)
mcause = 3

*******************************************************************************/
