#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Check all implemented M-mode CSRs generate exceptions when written, *if and
// only if* they are read-only.

// These are new (priv-1.12) and may not be recognised by the toolchain:
#define mconfigptr 0xf15
#define mstatush 0x310

// Explanations in inline comments within the expected output:

/*EXPECTED-OUTPUT***************************************************************

-> exception, mcause = 2 // write to mvendorid, read-only
CSR was f11
-> exception, mcause = 2 // write to marchid, read-only
CSR was f12
-> exception, mcause = 2 // write to mimpid, read-only
CSR was f13
-> exception, mcause = 2 // write to mhartid, read-only
CSR was f14
-> exception, mcause = 2 // write to mconfigptr, read-only
CSR was f15
-> exception, mcause = 2 // read of medeleg, unimplemented
CSR was 302
-> exception, mcause = 2 // write to medegeleg, unimplemented
CSR was 302
-> exception, mcause = 2 // read of mideleg, unimplemented
CSR was 303
-> exception, mcause = 2 // write to medeleg, unimplemented
CSR was 303
-> exception, mcause = 2 // write to cycle, read-only
CSR was c00
-> exception, mcause = 2 // write to cycleh, read-only
CSR was c80
-> exception, mcause = 2 // write to instret, read-only
CSR was c02
-> exception, mcause = 2 // write to instreth, read-only
CSR was c82
-> exception, mcause = 2 // read of dcsr, D-mode
CSR was 7b0
-> exception, mcause = 2 // write to dcsr, D-mode
CSR was 7b0
-> exception, mcause = 2 // read of dpc, D-mode
CSR was 7b1
-> exception, mcause = 2 // write to dpc, D-mode
CSR was 7b1
-> exception, mcause = 2 // read of dscratch0, unimplemented, D-mode
CSR was 7b2
-> exception, mcause = 2 // write to dscratch0, unimplemented, D-mode
CSR was 7b2
-> exception, mcause = 2 // read of dscratch1, unimplemented, D-mode
CSR was 7b3
-> exception, mcause = 2 // write to dscratch1, unimplemented, D-mode
CSR was 7b3
-> exception, mcause = 2 // read of dmdata0, D-mode
CSR was bff
-> exception, mcause = 2 // write to dmdata0, D-mode
CSR was bff

*******************************************************************************/

int main() {
	write_csr(mvendorid,           read_csr(mvendorid          ));
	write_csr(marchid,             read_csr(marchid            ));
	write_csr(mimpid,              read_csr(mimpid             ));
	write_csr(mhartid,             read_csr(mhartid            ));
	write_csr(mconfigptr,          read_csr(mconfigptr         ));
	write_csr(misa,                read_csr(misa               ));

	write_csr(mstatus,             read_csr(mstatus            ));
	write_csr(mstatush,            read_csr(mstatush           ));
	write_csr(medeleg,             read_csr(medeleg            ));
	write_csr(mideleg,             read_csr(mideleg            ));
	write_csr(mie,                 read_csr(mie                ));
	write_csr(mip,                 read_csr(mip                ));
	write_csr(mtvec,               read_csr(mtvec              ));
	write_csr(mscratch,            read_csr(mscratch           ));
	write_csr(mepc,                read_csr(mepc               ));
	write_csr(mcause,              read_csr(mcause             ));
	write_csr(mtval,               read_csr(mtval              ));

	write_csr(mcycle,              read_csr(mcycle             ));
	write_csr(mcycleh,             read_csr(mcycleh            ));
	write_csr(minstret,            read_csr(minstret           ));
	write_csr(minstreth,           read_csr(minstreth          ));

	write_csr(mhpmcounter3,        read_csr(mhpmcounter3       ));
	write_csr(mhpmcounter4,        read_csr(mhpmcounter4       ));
	write_csr(mhpmcounter5,        read_csr(mhpmcounter5       ));
	write_csr(mhpmcounter6,        read_csr(mhpmcounter6       ));
	write_csr(mhpmcounter7,        read_csr(mhpmcounter7       ));
	write_csr(mhpmcounter8,        read_csr(mhpmcounter8       ));
	write_csr(mhpmcounter9,        read_csr(mhpmcounter9       ));
	write_csr(mhpmcounter10,       read_csr(mhpmcounter10      ));
	write_csr(mhpmcounter11,       read_csr(mhpmcounter11      ));
	write_csr(mhpmcounter12,       read_csr(mhpmcounter12      ));
	write_csr(mhpmcounter13,       read_csr(mhpmcounter13      ));
	write_csr(mhpmcounter14,       read_csr(mhpmcounter14      ));
	write_csr(mhpmcounter15,       read_csr(mhpmcounter15      ));
	write_csr(mhpmcounter16,       read_csr(mhpmcounter16      ));
	write_csr(mhpmcounter17,       read_csr(mhpmcounter17      ));
	write_csr(mhpmcounter18,       read_csr(mhpmcounter18      ));
	write_csr(mhpmcounter19,       read_csr(mhpmcounter19      ));
	write_csr(mhpmcounter20,       read_csr(mhpmcounter20      ));
	write_csr(mhpmcounter21,       read_csr(mhpmcounter21      ));
	write_csr(mhpmcounter22,       read_csr(mhpmcounter22      ));
	write_csr(mhpmcounter23,       read_csr(mhpmcounter23      ));
	write_csr(mhpmcounter24,       read_csr(mhpmcounter24      ));
	write_csr(mhpmcounter25,       read_csr(mhpmcounter25      ));
	write_csr(mhpmcounter26,       read_csr(mhpmcounter26      ));
	write_csr(mhpmcounter27,       read_csr(mhpmcounter27      ));
	write_csr(mhpmcounter28,       read_csr(mhpmcounter28      ));
	write_csr(mhpmcounter29,       read_csr(mhpmcounter29      ));
	write_csr(mhpmcounter30,       read_csr(mhpmcounter30      ));
	write_csr(mhpmcounter31,       read_csr(mhpmcounter31      ));

	write_csr(mhpmcounter3h,       read_csr(mhpmcounter3h      ));
	write_csr(mhpmcounter4h,       read_csr(mhpmcounter4h      ));
	write_csr(mhpmcounter5h,       read_csr(mhpmcounter5h      ));
	write_csr(mhpmcounter6h,       read_csr(mhpmcounter6h      ));
	write_csr(mhpmcounter7h,       read_csr(mhpmcounter7h      ));
	write_csr(mhpmcounter8h,       read_csr(mhpmcounter8h      ));
	write_csr(mhpmcounter9h,       read_csr(mhpmcounter9h      ));
	write_csr(mhpmcounter10h,      read_csr(mhpmcounter10h     ));
	write_csr(mhpmcounter11h,      read_csr(mhpmcounter11h     ));
	write_csr(mhpmcounter12h,      read_csr(mhpmcounter12h     ));
	write_csr(mhpmcounter13h,      read_csr(mhpmcounter13h     ));
	write_csr(mhpmcounter14h,      read_csr(mhpmcounter14h     ));
	write_csr(mhpmcounter15h,      read_csr(mhpmcounter15h     ));
	write_csr(mhpmcounter16h,      read_csr(mhpmcounter16h     ));
	write_csr(mhpmcounter17h,      read_csr(mhpmcounter17h     ));
	write_csr(mhpmcounter18h,      read_csr(mhpmcounter18h     ));
	write_csr(mhpmcounter19h,      read_csr(mhpmcounter19h     ));
	write_csr(mhpmcounter20h,      read_csr(mhpmcounter20h     ));
	write_csr(mhpmcounter21h,      read_csr(mhpmcounter21h     ));
	write_csr(mhpmcounter22h,      read_csr(mhpmcounter22h     ));
	write_csr(mhpmcounter23h,      read_csr(mhpmcounter23h     ));
	write_csr(mhpmcounter24h,      read_csr(mhpmcounter24h     ));
	write_csr(mhpmcounter25h,      read_csr(mhpmcounter25h     ));
	write_csr(mhpmcounter26h,      read_csr(mhpmcounter26h     ));
	write_csr(mhpmcounter27h,      read_csr(mhpmcounter27h     ));
	write_csr(mhpmcounter28h,      read_csr(mhpmcounter28h     ));
	write_csr(mhpmcounter29h,      read_csr(mhpmcounter29h     ));
	write_csr(mhpmcounter30h,      read_csr(mhpmcounter30h     ));
	write_csr(mhpmcounter31h,      read_csr(mhpmcounter31h     ));

	write_csr(cycle,               read_csr(cycle              ));
	write_csr(cycleh,              read_csr(cycleh             ));
	write_csr(instret,             read_csr(instret            ));
	write_csr(instreth,            read_csr(instreth           ));

	write_csr(mcountinhibit,       read_csr(mcountinhibit      ));
	write_csr(mhpmevent3,          read_csr(mhpmevent3         ));
	write_csr(tselect,             read_csr(tselect            ));
	write_csr(tdata1,              read_csr(tdata1             ));
	write_csr(tdata2,              read_csr(tdata2             ));
	write_csr(tinfo,               read_csr(tinfo              ));
	write_csr(tcontrol,            read_csr(tcontrol           ));
	write_csr(dcsr,                read_csr(dcsr               ));
	write_csr(dpc,                 read_csr(dpc                ));
	write_csr(dscratch0,           read_csr(dscratch0          ));
	write_csr(dscratch1,           read_csr(dscratch1          ));
	write_csr(hazard3_csr_dmdata0, read_csr(hazard3_csr_dmdata0));

	write_csr(hazard3_csr_meiea,      read_csr(hazard3_csr_meiea     ));
	write_csr(hazard3_csr_meipa,      read_csr(hazard3_csr_meipa     ));
	write_csr(hazard3_csr_meifa,      read_csr(hazard3_csr_meifa     ));
	write_csr(hazard3_csr_meipra,     read_csr(hazard3_csr_meipra    ));
	write_csr(hazard3_csr_meinext,    read_csr(hazard3_csr_meinext   ));
	write_csr(hazard3_csr_meicontext, read_csr(hazard3_csr_meicontext));

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
