#include "tb_cxxrtl_io.h"

/*EXPECTED-OUTPUT***************************************************************

Hello world from Hazard3 + CXXRTL!

*******************************************************************************/

int main() {
	tb_puts("Hello world from RV64I!\n");
	return 0;
}
