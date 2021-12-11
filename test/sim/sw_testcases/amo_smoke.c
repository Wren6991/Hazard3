#include "tb_cxxrtl_io.h"
#include <stdint.h>

/*EXPECTED-OUTPUT***************************************************************

Initial value: 0
amoadd.w rd, 1, (&addr) -> fetched 0
amoadd.w rd, 2, (&addr) -> fetched 1
amoadd.w rd, 3, (&addr) -> fetched 3
amoadd.w rd, 4, (&addr) -> fetched 6
amoadd.w rd, 5, (&addr) -> fetched 10
amoadd.w rd, 6, (&addr) -> fetched 15
amoadd.w rd, 7, (&addr) -> fetched 21
amoadd.w rd, 8, (&addr) -> fetched 28
amoadd.w rd, 9, (&addr) -> fetched 36
amoadd.w rd, 10, (&addr) -> fetched 45
Final value: 55

*******************************************************************************/

volatile uint32_t scratch[2];

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
