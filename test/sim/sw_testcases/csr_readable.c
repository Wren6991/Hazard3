#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Check all implemented M-mode CSRs are readable, without exception (haha).
// Check reading D-mode CSRs generates illegal instruction exceptions in M-mode.

// These are new (priv-1.12) and may not be recognised by the toolchain:
#define mconfigptr 0xf15
#define mstatush 0x310

// Exceptions here are: medeleg, mideleg, tdata1, dcsr, dpc, dscratch1,
// dscratch0, dmdata0 (custom). medeleg/mideleg are just a couple of
// unimplemented registers sprinkled in for a sanity check, and the remainder
// are D-mode registers.
//
// Note we permit reads but not writes to tselect, to work around a logic
// error in openocd. Planning to implement triggers at some point, so this
// oddity will vanish.

/*EXPECTED-OUTPUT***************************************************************

-> exception, mcause = 2
CSR was 302
-> exception, mcause = 2
CSR was 303
-> exception, mcause = 2
CSR was 7a1
-> exception, mcause = 2
CSR was 7b0
-> exception, mcause = 2
CSR was 7b1
-> exception, mcause = 2
CSR was 7b2
-> exception, mcause = 2
CSR was 7b3
-> exception, mcause = 2
CSR was bff

*******************************************************************************/

int main() {
	(void)read_csr(mvendorid);
	(void)read_csr(marchid);
	(void)read_csr(mimpid);
	(void)read_csr(mhartid);
	(void)read_csr(mconfigptr);
	(void)read_csr(misa);

	(void)read_csr(mstatus);
	(void)read_csr(mstatush);
	(void)read_csr(medeleg);
	(void)read_csr(mideleg);
	(void)read_csr(mie);
	(void)read_csr(mip);
	(void)read_csr(mtvec);
	(void)read_csr(mscratch);
	(void)read_csr(mepc);
	(void)read_csr(mcause);
	(void)read_csr(mtval);

	(void)read_csr(mcycle);
	(void)read_csr(mcycleh);
	(void)read_csr(minstret);
	(void)read_csr(minstreth);

	(void)read_csr(mhpmcounter3);
	(void)read_csr(mhpmcounter4);
	(void)read_csr(mhpmcounter5);
	(void)read_csr(mhpmcounter6);
	(void)read_csr(mhpmcounter7);
	(void)read_csr(mhpmcounter8);
	(void)read_csr(mhpmcounter9);
	(void)read_csr(mhpmcounter10);
	(void)read_csr(mhpmcounter11);
	(void)read_csr(mhpmcounter12);
	(void)read_csr(mhpmcounter13);
	(void)read_csr(mhpmcounter14);
	(void)read_csr(mhpmcounter15);
	(void)read_csr(mhpmcounter16);
	(void)read_csr(mhpmcounter17);
	(void)read_csr(mhpmcounter18);
	(void)read_csr(mhpmcounter19);
	(void)read_csr(mhpmcounter20);
	(void)read_csr(mhpmcounter21);
	(void)read_csr(mhpmcounter22);
	(void)read_csr(mhpmcounter23);
	(void)read_csr(mhpmcounter24);
	(void)read_csr(mhpmcounter25);
	(void)read_csr(mhpmcounter26);
	(void)read_csr(mhpmcounter27);
	(void)read_csr(mhpmcounter28);
	(void)read_csr(mhpmcounter29);
	(void)read_csr(mhpmcounter30);
	(void)read_csr(mhpmcounter31);

	(void)read_csr(mhpmcounter3h);
	(void)read_csr(mhpmcounter4h);
	(void)read_csr(mhpmcounter5h);
	(void)read_csr(mhpmcounter6h);
	(void)read_csr(mhpmcounter7h);
	(void)read_csr(mhpmcounter8h);
	(void)read_csr(mhpmcounter9h);
	(void)read_csr(mhpmcounter10h);
	(void)read_csr(mhpmcounter11h);
	(void)read_csr(mhpmcounter12h);
	(void)read_csr(mhpmcounter13h);
	(void)read_csr(mhpmcounter14h);
	(void)read_csr(mhpmcounter15h);
	(void)read_csr(mhpmcounter16h);
	(void)read_csr(mhpmcounter17h);
	(void)read_csr(mhpmcounter18h);
	(void)read_csr(mhpmcounter19h);
	(void)read_csr(mhpmcounter20h);
	(void)read_csr(mhpmcounter21h);
	(void)read_csr(mhpmcounter22h);
	(void)read_csr(mhpmcounter23h);
	(void)read_csr(mhpmcounter24h);
	(void)read_csr(mhpmcounter25h);
	(void)read_csr(mhpmcounter26h);
	(void)read_csr(mhpmcounter27h);
	(void)read_csr(mhpmcounter28h);
	(void)read_csr(mhpmcounter29h);
	(void)read_csr(mhpmcounter30h);
	(void)read_csr(mhpmcounter31h);

	(void)read_csr(cycle);
	(void)read_csr(cycleh);
	(void)read_csr(instret);
	(void)read_csr(instreth);

	(void)read_csr(mcountinhibit);
	(void)read_csr(mhpmevent3);
	(void)read_csr(tselect);
	(void)read_csr(tdata1);
	(void)read_csr(dcsr);
	(void)read_csr(dpc);
	(void)read_csr(dscratch0);
	(void)read_csr(dscratch1);
	(void)read_csr(hazard3_csr_dmdata0);
	(void)read_csr(hazard3_csr_meiea);
	(void)read_csr(hazard3_csr_meipa);
	(void)read_csr(hazard3_csr_meifa);
	(void)read_csr(hazard3_csr_meipra);
	(void)read_csr(hazard3_csr_meinext);
	(void)read_csr(hazard3_csr_meicontext);

	return 0;
}

void __attribute__((interrupt)) handle_exception() {
	tb_printf("-> exception, mcause = %u\n", read_csr(mcause));
	write_csr(mcause, 0);
	uint32_t mepc = read_csr(mepc);
	if ((*(uint16_t*)mepc & 0x3) == 0x3) {
		tb_printf("CSR was %03x\n", *(uint16_t*)(mepc + 2) >> 4);
		mepc += 4;
	}
	else {
		tb_puts("Exception on 16-bit instruction?!\n");
		tb_exit(-1);
	}
	write_csr(mepc, mepc);
}
