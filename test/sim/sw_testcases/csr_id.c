#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// This is a new CSR for priv-1.12. Most compilers (maybe binutils?) don't know about it.
#define mconfigptr 0xf15

/*EXPECTED-OUTPUT***************************************************************

mvendorid:  deadbeef
marchid:    0000001b
mimpid:     12345678
mhartid:    00000000
mconfigptr: 9abcdef0
misa:       40901105 // RV32IMACX + U

*******************************************************************************/

int main() {
	// Expected value: 32'hdeadbeef, set in tb Makefile
	tb_printf("mvendorid:  %08x\n", read_csr(mvendorid ));
	// Expected value: 27, the registered ID for Hazard3
	tb_printf("marchid:    %08x\n", read_csr(marchid   ));
	// Expected value: 32'h12345678, set in tb Makefile
	tb_printf("mimpid:     %08x\n", read_csr(mimpid    ));
	// Expected value: 0
	tb_printf("mhartid:    %08x\n", read_csr(mhartid   ));
	// Expected value: 32'h9abcdef0, set in tb Makefile
	tb_printf("mconfigptr: %08x\n", read_csr(mconfigptr));
	// Expected value: 40801105, RV32I + A C M X
	tb_printf("misa:       %08x\n", read_csr(misa      ));
	return 0;
}
