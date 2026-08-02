#ifndef _HAZARD3_INSTR_H
#define _HAZARD3_INSTR_H

#include <stdint.h>

// C macros for Hazard3 custom instructions

// nbits must be a constant expression
#define __hazard3_bextm(nbits, rs1, rs2) ({\
	uint32_t __h3_bextm_rd; \
	asm (".insn r 0x0b, 0, %3, %0, %1, %2"\
		: "=r" (__h3_bextm_rd) \
		: "r" (rs1), "r" (rs2), "i" ((((nbits) - 1) & 0x7) << 1)\
	); \
	__h3_bextm_rd; \
})

// nbits and shamt must be constant expressions
#define __hazard3_bextmi(nbits, rs1, shamt) ({\
	uint32_t __h3_bextmi_rd; \
	asm (".insn i 0x0b, 0x4, %0, %1, %2"\
		: "=r" (__h3_bextmi_rd) \
		: "r" (rs1), "i" ((((nbits) - 1) & 0x7) << 6 | ((shamt) & 0x1f)) \
	); \
	__h3_bextmi_rd; \
})

#define __hazard3_block() asm ("slt x0, x0, x0" : : : "memory")

#define __hazard3_unblock() asm ("slt x0, x0, x1" : : : "memory")

#endif
