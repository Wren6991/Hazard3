#ifndef _HAZARD3_CSR_H
#define _HAZARD3_CSR_H

#ifndef __ASSEMBLER__
#include "stdint.h"
#endif

#define hazard3_csr_dmdata0 0xbff // Debug-mode shadow CSR for DM data transfer
#define hazard3_csr_meie0   0xbe0 // External interrupt enable IRQ0 -> 31
#define hazard3_csr_meip0   0xfe0 // External interrupt pending IRQ0 -> 31
#define hazard3_csr_mlei    0xfe4 // Lowest external interrupt (pending & enabled)

#define _read_csr(csrname) ({ \
  uint32_t __csr_tmp_u32; \
  asm volatile ("csrr %0, " #csrname : "=r" (__csr_tmp_u32)); \
  __csr_tmp_u32; \
})

#define _write_csr(csrname, data) ({ \
	asm volatile ("csrw " #csrname ", %0" : : "r" (data)); \
})

// Argument macro expansion layer
#define read_csr(csrname) _read_csr(csrname)
#define write_csr(csrname, data) _write_csr(csrname, data)

#endif
