#ifndef _COMPLIANCE_IO_H_
#define _COMPLIANCE_IO_H_

#define RVTEST_IO_INIT
#define RVTEST_IO_WRITE_STR(_SP, _STR)
#define RVTEST_IO_CHECK()


// Put this info into a label name so that it can be seen in the disassembly (holy hack batman)
#define LABEL_ASSERT_(reg, val, line) assert_ ## reg ## _ ## val ## _l ## line:
#define LABEL_ASSERT(reg, val, line) LABEL_ASSERT_(reg, val, line)

#define RVTEST_IO_ASSERT_GPR_EQ(_SP, _R, _I) LABEL_ASSERT(_R, xxx, __LINE__) nop
#define RVTEST_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVTEST_IO_ASSERT_DFPR_EQ(_D, _R, _I)

#endif // _COMPLIANCE_IO_H_