#ifndef _XH3SFX_INTRINSICS_H
#define _XH3SFX_INTRINSICS_H

// Instruction macro header (intrinsics) for Xh3sfx extension

#ifndef __ASSEMBLER__

#define __h3_funpackq3_s(rs1) ({\
    uint32_t __rd; \
    asm (".insn r 0x0b, 0x1, 0x40, %0, %1, zero"\
        : "=r" (__rd) \
        : "r" (rs1) \
    ); \
    __rd; \
})

#define __h3_funpackq3_h(rs1) ({\
    uint32_t __rd; \
    asm (".insn r 0x0b, 0x1, 0x00, %0, %1, zero"\
        : "=r" (__rd) \
        : "r" (rs1) \
    ); \
    __rd; \
})

#define __h3_fcheck2e_s(rs1, rs2) ({\
    uint32_t __rd; \
    asm (".insn r 0x0b, 0x1, 0x41, %0, %1, %2"\
        : "=r" (__rd) \
        : "r" (rs1), "r" (rs2) \
    ); \
    __rd; \
})

#define __h3_fcheck2e_h(rs1, rs2) ({\
    uint32_t __rd; \
    asm (".insn r 0x0b, 0x1, 0x01, %0, %1, %2"\
        : "=r" (__rd) \
        : "r" (rs1), "r" (rs2) \
    ); \
    __rd; \
})

#define __h3_fpackrq3_s(rs1, rs2) ({\
    uint32_t __rd; \
    asm (".insn r 0x0b, 0x1, 0x42, %0, %1, %2"\
        : "=r" (__rd) \
        : "r" (rs1), "r" (rs2) \
    ); \
    __rd; \
})

#define __h3_fpackrq3_h(rs1, rs2) ({\
    uint32_t __rd; \
    asm (".insn r 0x0b, 0x1, 0x02, %0, %1, %2"\
        : "=r" (__rd) \
        : "r" (rs1), "r" (rs2) \
    ); \
    __rd; \
})

#define __h3_feadjq3(rs1) ({\
    uint32_t __rd; \
    asm (".insn r 0x0b, 0x1, 0x04, %0, %1, zero"\
        : "=r" (__rd) \
        : "r" (rs1) \
    ); \
    __rd; \
})

#define __h3_feadju3(rs1) ({\
    uint32_t __rd; \
    asm (".insn r 0x0b, 0x1, 0x05, %0, %1, zero"\
        : "=r" (__rd) \
        : "r" (rs1) \
    ); \
    __rd; \
})

#define __h3_xorsign(rs1, rs2) ({\
    uint32_t __rd; \
    asm (".insn r 0x0b, 0x1, 0x06, %0, %1, %2"\
        : "=r" (__rd) \
        : "r" (rs1), "r" (rs2) \
    ); \
    __rd; \
})

#define __h3_xnorsign(rs1, rs2) ({\
    uint32_t __rd; \
    asm (".insn r 0x0b, 0x1, 0x07, %0, %1, %2"\
        : "=r" (__rd) \
        : "r" (rs1), "r" (rs2) \
    ); \
    __rd; \
})

#define __h3_ssrasticky(rs1, rs2) ({\
    uint32_t __rd; \
    asm (".insn r 0x0b, 0x1, 0x0b, %0, %1, %2"\
        : "=r" (__rd) \
        : "r" (rs1), "r" (rs2) \
    ); \
    __rd; \
})

#define __h3_ssrlsticky(rs1, rs2) ({\
    uint32_t __rd; \
    asm (".insn r 0x0b, 0x1, 0x0a, %0, %1, %2"\
        : "=r" (__rd) \
        : "r" (rs1), "r" (rs2) \
    ); \
    __rd; \
})

#define __h3_ssla(rs1, rs2) ({\
    uint32_t __rd; \
    asm (".insn r 0x0b, 0x1, 0x0d, %0, %1, %2"\
        : "=r" (__rd) \
        : "r" (rs1), "r" (rs2) \
    ); \
    __rd; \
})

#else

.macro h3.funpackq3.s rd, rs1
.insn r 0x0b, 0x1, 0x40, \rd, \rs1, zero
.endm

.macro h3.funpackq3.h rd, rs1
.insn r 0x0b, 0x1, 0x00, \rd, \rs1, zero
.endm

.macro h3.fcheck2e.s rd, rs1, rs2
.insn r 0x0b, 0x1, 0x41, \rd, \rs1, \rs2
.endm

.macro h3.fcheck2e.h rd, rs1, rs2
.insn r 0x0b, 0x1, 0x01, \rd, \rs1, \rs2
.endm

.macro h3.fpackrq3.s rd, rs1, rs2
.insn r 0x0b, 0x1, 0x42, \rd, \rs1, \rs2
.endm

.macro h3.fpackrq3.h rd, rs1, rs2
.insn r 0x0b, 0x1, 0x02, \rd, \rs1, \rs2
.endm

.macro h3.feadjq3 rd, rs1
.insn r 0x0b, 0x1, 0x04, \rd, \rs1, zero
.endm

.macro h3.feadju3 rd, rs1
.insn r 0x0b, 0x1, 0x05, \rd, \rs1, zero
.endm

.macro h3.xorsign rd, rs1, rs2
.insn r 0x0b, 0x1, 0x06, \rd, \rs1, \rs2
.endm

.macro h3.xnorsign rd, rs1, rs2
.insn r 0x0b, 0x1, 0x07, \rd, \rs1, \rs2
.endm

.macro h3.ssrasticky rd, rs1, rs2
.insn r 0x0b, 0x1, 0x0b, \rd, \rs1, \rs2
.endm

.macro h3.ssrlsticky rd, rs1, rs2
.insn r 0x0b, 0x1, 0x0a, \rd, \rs1, \rs2
.endm

.macro h3.ssla rd, rs1, rs2
.insn r 0x0b, 0x1, 0x0d, \rd, \rs1, \rs2
.endm

#endif

#endif