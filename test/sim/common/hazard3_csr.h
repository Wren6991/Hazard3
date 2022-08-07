#ifndef _HAZARD3_CSR_H
#define _HAZARD3_CSR_H

#ifndef __ASSEMBLER__
#include "stdint.h"
#endif

#define hazard3_csr_dmdata0    0xbff // Debug-mode shadow CSR for DM data transfer

#define hazard3_csr_meiea      0xbe0 // External interrupt pending array
#define hazard3_csr_meipa      0xbe1 // External interrupt enable array
#define hazard3_csr_meifa      0xbe2 // External interrupt force array
#define hazard3_csr_meipra     0xbe3 // External interrupt priority array
#define hazard3_csr_meinext    0xbe4 // Next external interrupt
#define hazard3_csr_meicontext 0xbe5 // External interrupt context register

#define hazard3_csr_msleep     0xbf0 // M-mode sleep control register

#define _read_csr(csrname) ({ \
  uint32_t __csr_tmp_u32; \
  asm volatile ("csrr %0, " #csrname : "=r" (__csr_tmp_u32)); \
  __csr_tmp_u32; \
})

#define _write_csr(csrname, data) ({ \
	asm volatile ("csrw " #csrname ", %0" : : "r" (data)); \
})

#define _set_csr(csrname, data) ({ \
  asm volatile ("csrs " #csrname ", %0" : : "r" (data)); \
})

#define _clear_csr(csrname, data) ({ \
  asm volatile ("csrc " #csrname ", %0" : : "r" (data)); \
})

#define _read_write_csr(csrname, data) ({ \
  uint32_t __csr_tmp_u32; \
  asm volatile ("csrrw %0, " #csrname ", %1" : "=r" (__csr_tmp_u32) : "r" (data)); \
  __csr_tmp_u32; \
})

#define _read_set_csr(csrname, data) ({ \
  uint32_t __csr_tmp_u32; \
  asm volatile ("csrrs %0, " #csrname ", %1" : "=r" (__csr_tmp_u32) : "r" (data)); \
  __csr_tmp_u32; \
})

#define _read_clear_csr(csrname, data) ({ \
  uint32_t __csr_tmp_u32; \
  asm volatile ("csrrc %0, " #csrname ", %1" : "=r" (__csr_tmp_u32) : "r" (data)); \
  __csr_tmp_u32; \
})

// Argument macro expansion layer
#define read_csr(csrname)             _read_csr(csrname)
#define write_csr(csrname, data)      _write_csr(csrname, data)
#define set_csr(csrname, data)        _set_csr(csrname, data)
#define clear_csr(csrname, data)      _clear_csr(csrname, data)
#define read_write_csr(csrname, data) _read_write_csr(csrname, data)
#define read_set_csr(csrname, data)   _read_set_csr(csrname, data)
#define read_clear_csr(csrname, data) _read_clear_csr(csrname, data)

#endif
