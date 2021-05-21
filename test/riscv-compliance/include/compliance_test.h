#ifndef _COMPLIANCE_TEST_H_
#define _COMPLIANCE_TEST_H_

#define RV_COMPLIANCE_RV32M

#define RV_COMPLIANCE_CODE_BEGIN 

#define RV_COMPLIANCE_CODE_END

#define MM_IO_EXIT 0x80000008

.macro RV_COMPLIANCE_HALT
.option push
.option norelax
_write_io_exit:
        li a0, MM_IO_EXIT
        sw zero, 0(a0)
        // Note we should never reach this next instruction (assuming the
        // processor is working correctly!)
_end_of_test:
        j _end_of_test
.option pop
.endm

#define RV_COMPLIANCE_DATA_BEGIN .section .testdata, "a"

#define RV_COMPLIANCE_DATA_END


#endif // _COMPLIANCE_TEST_H_
