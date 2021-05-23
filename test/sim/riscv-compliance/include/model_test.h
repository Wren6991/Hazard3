#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

// Modified version of riscv-arch-test/riscv-target/example-target/model_test.h

#define IO_BASE 0x80000000
#define IO_PRINT_CHAR (IO_BASE + 0x0)
#define IO_PRINT_U32  (IO_BASE + 0x4)
#define IO_EXIT       (IO_BASE + 0x8)

#define RVMODEL_DATA_SECTION \
        .pushsection .testdata,"aw",@progbits;                          \
        .align 8; .global tohost; tohost: .dword 0;                     \
        .align 8; .global fromhost; fromhost: .dword 0;                 \
        .popsection;                                                    \
        .align 8; .global begin_regstate; begin_regstate:               \
        .word 128;                                                      \
        .align 8; .global end_regstate; end_regstate:                   \
        .word 4;


#define RVMODEL_HALT                                                 ;  \
        li a0, IO_EXIT                                               ;  \
        li a1, 0                                                     ;  \
        sw a1, (a0)                                                  ;  \
        1: j 1b                                                         \

//TODO: declare the start of your signature region here. Nothing else to be used here.
// The .align 4 ensures that the signature ends at a 16-byte boundary
#define RVMODEL_DATA_BEGIN                                              \
  .section .testdata, "aw"; \
  .align 4; .global begin_signature; begin_signature:

//TODO: declare the end of the signature region here. Add other target specific contents here.
#define RVMODEL_DATA_END                                                      \
  .align 4; .global end_signature; end_signature:                             \
  RVMODEL_DATA_SECTION                                                        


#define RVMODEL_BOOT

// _SP = (volatile register)
//TODO: Macro to output a string to IO
#define LOCAL_IO_WRITE_STR(_STR) RVMODEL_IO_WRITE_STR(x31, _STR)

// Shut up
#define RVMODEL_IO_WRITE_STR(_STR, ...)

// #define RVMODEL_IO_WRITE_STR(_SP, _STR)                                 \
//     .section .data.string;                                              \
// 20001:                                                                  \
//     .string _STR;                                                       \
//     .section .text.init;                                                \
//     la a0, 20001b;                                                      \
//     jal FN_WriteStr;

#define RSIZE 4
// _SP = (volatile register)
#define LOCAL_IO_PUSH(_SP)                                              \
    la      _SP,  begin_regstate;                                       \
    sw      ra,   (1*RSIZE)(_SP);                                       \
    sw      t0,   (2*RSIZE)(_SP);                                       \
    sw      t1,   (3*RSIZE)(_SP);                                       \
    sw      t2,   (4*RSIZE)(_SP);                                       \
    sw      t3,   (5*RSIZE)(_SP);                                       \
    sw      t4,   (6*RSIZE)(_SP);                                      \
    sw      s0,   (7*RSIZE)(_SP);                                      \
    sw      a0,   (8*RSIZE)(_SP);

// _SP = (volatile register)
#define LOCAL_IO_POP(_SP)                                               \
    la      _SP,   begin_regstate;                                      \
    lw      ra,   (1*RSIZE)(_SP);                                       \
    lw      t0,   (2*RSIZE)(_SP);                                       \
    lw      t1,   (3*RSIZE)(_SP);                                       \
    lw      t2,   (4*RSIZE)(_SP);                                       \
    lw      t3,   (5*RSIZE)(_SP);                                       \
    lw      t4,   (6*RSIZE)(_SP);                                       \
    lw      s0,   (7*RSIZE)(_SP);                                       \
    lw      a0,   (8*RSIZE)(_SP);

#define RVMODEL_IO_ASSERT_GPR_EQ(_SP, _R, _I)

//RVTEST_IO_ASSERT_SFPR_EQ
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
//RVTEST_IO_ASSERT_DFPR_EQ
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

// TODO: specify the routine for setting machine software interrupt
#define RVMODEL_SET_MSW_INT

// TODO: specify the routine for clearing machine software interrupt
#define RVMODEL_CLEAR_MSW_INT

// TODO: specify the routine for clearing machine timer interrupt
#define RVMODEL_CLEAR_MTIMER_INT

// TODO: specify the routine for clearing machine external interrupt
#define RVMODEL_CLEAR_MEXT_INT

#endif // _COMPLIANCE_MODEL_H

