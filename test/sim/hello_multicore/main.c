#include "tb_cxxrtl_io.h"

extern volatile uintptr_t core1_entry_vector;

void launch_core1(void (*entry)(void)) {
	core1_entry_vector = (uintptr_t)entry;
	tb_set_softirq(1);
}

void core1_main() {
	tb_clr_softirq(1);
	tb_puts("Hello world from core 1\n");
	tb_exit(0);
}

int main() {
	tb_puts("Hello world from core 0!\n");
	launch_core1(core1_main);
	asm volatile (
		"1:  wfi\n"
		"    j 1b\n"
	);
}
