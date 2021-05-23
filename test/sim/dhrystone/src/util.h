#ifndef _UTIL_H
#define _UTIL_H

#include <stdint.h>

#define setStats(x)

#define read_csr(csrname) ({ \
	uint32_t __csr_tmp_u32; \
	__asm__ volatile ("csrr %0, " #csrname : "=r" (__csr_tmp_u32)); \
	__csr_tmp_u32; \
})

#endif
