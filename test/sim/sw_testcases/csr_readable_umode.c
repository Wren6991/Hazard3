#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Check all implemented M-mode and D-mode CSRs are unreadable in U mode.
// Check that an M-mode trap taken from U mode is able to access the M-mode
// trap CSRs.

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
-> exception, mcause = 2, mpp = 0 // mvendorid
CSR was f11
-> exception, mcause = 2, mpp = 0 // marchid
CSR was f12
-> exception, mcause = 2, mpp = 0 // mimpid
CSR was f13
-> exception, mcause = 2, mpp = 0 // mhartid
CSR was f14
-> exception, mcause = 2, mpp = 0 // mconfigptr
CSR was f15
-> exception, mcause = 2, mpp = 0 // misa
CSR was 301
-> exception, mcause = 2, mpp = 0 // mstatus
CSR was 300
-> exception, mcause = 2, mpp = 0 // mstatush
CSR was 310
-> exception, mcause = 2, mpp = 0 // mie
CSR was 304
-> exception, mcause = 2, mpp = 0 // mip
CSR was 344
-> exception, mcause = 2, mpp = 0 // mtvec
CSR was 305
-> exception, mcause = 2, mpp = 0 // mscratch
CSR was 340
-> exception, mcause = 2, mpp = 0 // mepc
CSR was 341
-> exception, mcause = 2, mpp = 0 // mcause
CSR was 342
-> exception, mcause = 2, mpp = 0 // mtval
CSR was 343
-> exception, mcause = 2, mpp = 0 // mcounteren
CSR was 306
-> exception, mcause = 2, mpp = 0 // mcycle
CSR was b00
-> exception, mcause = 2, mpp = 0 // mcycleh
CSR was b80
-> exception, mcause = 2, mpp = 0 // minstret
CSR was b02
-> exception, mcause = 2, mpp = 0 // minstreth
CSR was b82
-> exception, mcause = 2, mpp = 0 // mphmcounter3
CSR was b03
-> exception, mcause = 2, mpp = 0 // ...
CSR was b04
-> exception, mcause = 2, mpp = 0
CSR was b05
-> exception, mcause = 2, mpp = 0
CSR was b06
-> exception, mcause = 2, mpp = 0
CSR was b07
-> exception, mcause = 2, mpp = 0
CSR was b08
-> exception, mcause = 2, mpp = 0
CSR was b09
-> exception, mcause = 2, mpp = 0
CSR was b0a
-> exception, mcause = 2, mpp = 0
CSR was b0b
-> exception, mcause = 2, mpp = 0
CSR was b0c
-> exception, mcause = 2, mpp = 0
CSR was b0d
-> exception, mcause = 2, mpp = 0
CSR was b0e
-> exception, mcause = 2, mpp = 0
CSR was b0f
-> exception, mcause = 2, mpp = 0
CSR was b10
-> exception, mcause = 2, mpp = 0
CSR was b11
-> exception, mcause = 2, mpp = 0
CSR was b12
-> exception, mcause = 2, mpp = 0
CSR was b13
-> exception, mcause = 2, mpp = 0
CSR was b14
-> exception, mcause = 2, mpp = 0
CSR was b15
-> exception, mcause = 2, mpp = 0
CSR was b16
-> exception, mcause = 2, mpp = 0
CSR was b17
-> exception, mcause = 2, mpp = 0
CSR was b18
-> exception, mcause = 2, mpp = 0
CSR was b19
-> exception, mcause = 2, mpp = 0
CSR was b1a
-> exception, mcause = 2, mpp = 0
CSR was b1b
-> exception, mcause = 2, mpp = 0
CSR was b1c
-> exception, mcause = 2, mpp = 0
CSR was b1d
-> exception, mcause = 2, mpp = 0
CSR was b1e
-> exception, mcause = 2, mpp = 0 // ... mhpmcounter31
CSR was b1f
-> exception, mcause = 2, mpp = 0 // mhpmcounter3h
CSR was b83
-> exception, mcause = 2, mpp = 0 // ...
CSR was b84
-> exception, mcause = 2, mpp = 0
CSR was b85
-> exception, mcause = 2, mpp = 0
CSR was b86
-> exception, mcause = 2, mpp = 0
CSR was b87
-> exception, mcause = 2, mpp = 0
CSR was b88
-> exception, mcause = 2, mpp = 0
CSR was b89
-> exception, mcause = 2, mpp = 0
CSR was b8a
-> exception, mcause = 2, mpp = 0
CSR was b8b
-> exception, mcause = 2, mpp = 0
CSR was b8c
-> exception, mcause = 2, mpp = 0
CSR was b8d
-> exception, mcause = 2, mpp = 0
CSR was b8e
-> exception, mcause = 2, mpp = 0
CSR was b8f
-> exception, mcause = 2, mpp = 0
CSR was b90
-> exception, mcause = 2, mpp = 0
CSR was b91
-> exception, mcause = 2, mpp = 0
CSR was b92
-> exception, mcause = 2, mpp = 0
CSR was b93
-> exception, mcause = 2, mpp = 0
CSR was b94
-> exception, mcause = 2, mpp = 0
CSR was b95
-> exception, mcause = 2, mpp = 0
CSR was b96
-> exception, mcause = 2, mpp = 0
CSR was b97
-> exception, mcause = 2, mpp = 0
CSR was b98
-> exception, mcause = 2, mpp = 0
CSR was b99
-> exception, mcause = 2, mpp = 0
CSR was b9a
-> exception, mcause = 2, mpp = 0
CSR was b9b
-> exception, mcause = 2, mpp = 0
CSR was b9c
-> exception, mcause = 2, mpp = 0
CSR was b9d
-> exception, mcause = 2, mpp = 0
CSR was b9e
-> exception, mcause = 2, mpp = 0 // ... mhpmcounter31h
CSR was b9f                       // followed by U-mode counters, which shouldn't trap...
-> exception, mcause = 2, mpp = 0 // mcountinhibit
CSR was 320
-> exception, mcause = 2, mpp = 0 // mhpmevent3
CSR was 323
-> exception, mcause = 2, mpp = 0 // tselect
CSR was 7a0
-> exception, mcause = 2, mpp = 0 // tdata1
CSR was 7a1
-> exception, mcause = 2, mpp = 0 // dcsr
CSR was 7b0
-> exception, mcause = 2, mpp = 0 // dpc
CSR was 7b1
-> exception, mcause = 2, mpp = 0 // dscratch0
CSR was 7b2
-> exception, mcause = 2, mpp = 0 // dscratch1
CSR was 7b3
-> exception, mcause = 2, mpp = 0 // hazard3 dmdata0
CSR was bff
-> exception, mcause = 2, mpp = 0 // hazard3 meie0
CSR was be0
-> exception, mcause = 2, mpp = 0 // hazard3 meip0
CSR was fe0
-> exception, mcause = 2, mpp = 0 // hazard3 mlei
CSR was fe4
-> exception, mcause = 3, mpp = 0 // This is the ebreak that ends the test

*******************************************************************************/

// This function is run in U mode. It returns to a trampoline that ebreaks to M mode.
void read_all_csrs() {
	(void)read_csr(mvendorid);
	(void)read_csr(marchid);
	(void)read_csr(mimpid);
	(void)read_csr(mhartid);
	(void)read_csr(mconfigptr);
	(void)read_csr(misa);

	(void)read_csr(mstatus);
	(void)read_csr(mstatush);
	(void)read_csr(mie);
	(void)read_csr(mip);
	(void)read_csr(mtvec);
	(void)read_csr(mscratch);
	(void)read_csr(mepc);
	(void)read_csr(mcause);
	(void)read_csr(mtval);
	(void)read_csr(mcounteren);

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
	(void)read_csr(hazard3_csr_meie0);
	(void)read_csr(hazard3_csr_meip0);
	(void)read_csr(hazard3_csr_mlei);
}

void __attribute__((naked)) ebreak_trampoline() {
	asm ("ebreak");
}

int main() {
	// Make counters accessible to U mode
	write_csr(mcounteren, -1u);

	// Enter function in U mode, return via ebreak trampoline
	write_csr(mstatus, read_csr(mstatus) & ~0x1800u);
	write_csr(mepc, &read_all_csrs);
	asm (
		"la ra, ebreak_trampoline\n"
		"mret\n"
	);

	return 0;
}

void __attribute__((interrupt)) handle_exception() {
	uint32_t mcause = read_csr(mcause);
	tb_printf("-> exception, mcause = %u, mpp = %u\n", mcause, read_csr(mstatus) >> 11 & 0x3u);
	write_csr(mcause, 0);
	if (mcause == 3) {
		// ebreak -> end of test
		tb_exit(0);
	}

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
