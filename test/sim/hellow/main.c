#include "tb_cxxrtl_io.h"

int main() {
	tb_puts("Hello world from Hazard3 + CXXRTL!\n");
	asm volatile(
		"cm.push {ra, s0-s2}, -16\n"
		"cm.pop  {ra, s0-s2}, +16\n"
	);
	return 123;
}
