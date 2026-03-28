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

#error "Oops not done yet"

#endif

#endif