#include "tb_cxxrtl_io.h"
#include <stdint.h>

volatile uint32_t scratch[2];

#define test_assert(cond, ...) if (!(cond)) {tb_printf(__VA_ARGS__); return -1;}

int main() {

	scratch[0] = 0;

	tb_puts("Initial value: 0\n");
	for (int i = 1; i <= 10; ++i) {
		uint32_t fetched;
		asm volatile (
			"amoadd.w %0, %1, (%2)\n"
			: "=r" (fetched)
			: "r" (i), "r" (&scratch[0])
		);
		tb_printf("amoadd.w rd, %d, (&addr) -> fetched %d\n", i, fetched);
	}
	tb_printf("Final value: %d\n", scratch[0]);

	return 0;
}
