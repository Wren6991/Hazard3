#ifndef _XH3BEXTM_INTRINSICS_H
#define _XH3BEXTM_INTRINSICS_H

#ifndef __ASSEMBLER__

// nbits must be a constant expression
#define __h3_bextm(nbits, rs1, rs2) ({\
	uint32_t __h3_bextm_rd; \
	asm (".insn r 0x0b, 0, %3, %0, %1, %2"\
		: "=r" (__h3_bextm_rd) \
		: "r" (rs1), "r" (rs2), "i" ((((nbits) - 1) & 0x7) << 1)\
	); \
	__h3_bextm_rd; \
})

// nbits and shamt must be constant expressions
#define __h3_bextmi(nbits, rs1, shamt) ({\
	uint32_t __h3_bextmi_rd; \
	asm (".insn i 0x0b, 0x4, %0, %1, %2"\
		: "=r" (__h3_bextmi_rd) \
		: "r" (rs1), "i" ((((nbits) - 1) & 0x7) << 6 | ((shamt) & 0x1f)) \
	); \
	__h3_bextmi_rd; \
})

#else // !__ASSEMBLER__

// rd = (rs1 >> rs2[4:0]) & ~(-1 << nbits)
.macro h3.bextm rd rs1 rs2 nbits
.if (\nbits < 1) || (\nbits > 8)
.err
.endif
#if NO_HAZARD3_CUSTOM
    srl  \rd, \rs1, \rs2
    andi \rd, \rd, ((1 << \nbits) - 1)
#else
.insn r 0x0b, 0x0, (((\nbits - 1) & 0x7 ) << 1), \rd, \rs1, \rs2
#endif
.endm

// rd = (rs1 >> shamt) & ~(-1 << nbits)
.macro h3.bextmi rd rs1 shamt nbits
.if (\nbits < 1) || (\nbits > 8)
.err
.endif
.if (\shamt < 0) || (\shamt > 31)
.err
.endif
#if NO_HAZARD3_CUSTOM
    srli \rd, \rs1, \shamt
    andi \rd, \rd, ((1 << \nbits) - 1)
#else
.insn i 0x0b, 0x4, \rd, \rs1, (\shamt & 0x1f) | (((\nbits - 1) & 0x7 ) << 6)
#endif
.endm

#endif

#endif