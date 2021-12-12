#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "amo_outline.h"

// Check AMOs which are not word-aligned generate exceptions with correct mepc
// and mcause

int main() {
	volatile uint32_t target_word = -1u;
	uint32_t tmp = 0;

	tb_puts("amoswap.w\n");
	tmp = amoswap(123, (uint32_t*)((uintptr_t)&target_word + 1));
	tb_assert(tmp == 123, "bad");
	tmp = amoswap(123, (uint32_t*)((uintptr_t)&target_word + 2));
	tb_assert(tmp == 123, "bad");
	tmp = amoswap(123, (uint32_t*)((uintptr_t)&target_word + 3));
	tb_assert(tmp == 123, "bad");

	tb_puts("amoadd.w\n");
	tmp = amoadd(123, (uint32_t*)((uintptr_t)&target_word + 1));
	tb_assert(tmp == 123, "bad");
	tmp = amoadd(123, (uint32_t*)((uintptr_t)&target_word + 2));
	tb_assert(tmp == 123, "bad");
	tmp = amoadd(123, (uint32_t*)((uintptr_t)&target_word + 3));
	tb_assert(tmp == 123, "bad");

	tb_puts("amoxor.w\n");
	tmp = amoxor(123, (uint32_t*)((uintptr_t)&target_word + 1));
	tb_assert(tmp == 123, "bad");
	tmp = amoxor(123, (uint32_t*)((uintptr_t)&target_word + 2));
	tb_assert(tmp == 123, "bad");
	tmp = amoxor(123, (uint32_t*)((uintptr_t)&target_word + 3));
	tb_assert(tmp == 123, "bad");

	tb_puts("amoand.w\n");
	tmp = amoand(123, (uint32_t*)((uintptr_t)&target_word + 1));
	tb_assert(tmp == 123, "bad");
	tmp = amoand(123, (uint32_t*)((uintptr_t)&target_word + 2));
	tb_assert(tmp == 123, "bad");
	tmp = amoand(123, (uint32_t*)((uintptr_t)&target_word + 3));
	tb_assert(tmp == 123, "bad");

	tb_puts("amoor.w\n");
	tmp = amoor(123, (uint32_t*)((uintptr_t)&target_word + 1));
	tb_assert(tmp == 123, "bad");
	tmp = amoor(123, (uint32_t*)((uintptr_t)&target_word + 2));
	tb_assert(tmp == 123, "bad");
	tmp = amoor(123, (uint32_t*)((uintptr_t)&target_word + 3));
	tb_assert(tmp == 123, "bad");

	tb_puts("amomin.w\n");
	tmp = amomin(123, (uint32_t*)((uintptr_t)&target_word + 1));
	tb_assert(tmp == 123, "bad");
	tmp = amomin(123, (uint32_t*)((uintptr_t)&target_word + 2));
	tb_assert(tmp == 123, "bad");
	tmp = amomin(123, (uint32_t*)((uintptr_t)&target_word + 3));
	tb_assert(tmp == 123, "bad");

	tb_puts("amomax.w\n");
	tmp = amomax(123, (uint32_t*)((uintptr_t)&target_word + 1));
	tb_assert(tmp == 123, "bad");
	tmp = amomax(123, (uint32_t*)((uintptr_t)&target_word + 2));
	tb_assert(tmp == 123, "bad");
	tmp = amomax(123, (uint32_t*)((uintptr_t)&target_word + 3));
	tb_assert(tmp == 123, "bad");

	tb_puts("amominu.w\n");
	tmp = amominu(123, (uint32_t*)((uintptr_t)&target_word + 1));
	tb_assert(tmp == 123, "bad");
	tmp = amominu(123, (uint32_t*)((uintptr_t)&target_word + 2));
	tb_assert(tmp == 123, "bad");
	tmp = amominu(123, (uint32_t*)((uintptr_t)&target_word + 3));
	tb_assert(tmp == 123, "bad");

	tb_puts("amomaxu.w\n");
	tmp = amomaxu(123, (uint32_t*)((uintptr_t)&target_word + 1));
	tb_assert(tmp == 123, "bad");
	tmp = amomaxu(123, (uint32_t*)((uintptr_t)&target_word + 2));
	tb_assert(tmp == 123, "bad");
	tmp = amomaxu(123, (uint32_t*)((uintptr_t)&target_word + 3));
	tb_assert(tmp == 123, "bad");

	return 0;
}

void __attribute__((interrupt)) handle_exception() {
	tb_printf("-> exception, mcause = %u\n", read_csr(mcause));
	write_csr(mcause, 0);
	uint32_t mepc = read_csr(mepc);
	tb_printf("instr: %04x%04x\n", *(uint16_t*)(mepc + 2), *(uint16_t*)mepc);

	if ((*(uint16_t*)mepc & 0x3) == 0x3) {
		write_csr(mepc, mepc + 4);
	}
	else {
		write_csr(mepc, mepc + 2);
	}
}

/*EXPECTED-OUTPUT***************************************************************

amoswap.w
-> exception, mcause = 6
instr: 08a5a52f
-> exception, mcause = 6
instr: 08a5a52f
-> exception, mcause = 6
instr: 08a5a52f
amoadd.w
-> exception, mcause = 6
instr: 00a5a52f
-> exception, mcause = 6
instr: 00a5a52f
-> exception, mcause = 6
instr: 00a5a52f
amoxor.w
-> exception, mcause = 6
instr: 20a5a52f
-> exception, mcause = 6
instr: 20a5a52f
-> exception, mcause = 6
instr: 20a5a52f
amoand.w
-> exception, mcause = 6
instr: 60a5a52f
-> exception, mcause = 6
instr: 60a5a52f
-> exception, mcause = 6
instr: 60a5a52f
amoor.w
-> exception, mcause = 6
instr: 40a5a52f
-> exception, mcause = 6
instr: 40a5a52f
-> exception, mcause = 6
instr: 40a5a52f
amomin.w
-> exception, mcause = 6
instr: 80a5a52f
-> exception, mcause = 6
instr: 80a5a52f
-> exception, mcause = 6
instr: 80a5a52f
amomax.w
-> exception, mcause = 6
instr: a0a5a52f
-> exception, mcause = 6
instr: a0a5a52f
-> exception, mcause = 6
instr: a0a5a52f
amominu.w
-> exception, mcause = 6
instr: c0a5a52f
-> exception, mcause = 6
instr: c0a5a52f
-> exception, mcause = 6
instr: c0a5a52f
amomaxu.w
-> exception, mcause = 6
instr: e0a5a52f
-> exception, mcause = 6
instr: e0a5a52f
-> exception, mcause = 6
instr: e0a5a52f

*******************************************************************************/
