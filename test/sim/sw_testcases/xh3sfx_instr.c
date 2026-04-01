#include "tb_cxxrtl_io.h"
#include "xh3sfx_intrinsics.h"

// Directed per-instruction tests for Xh3sfx

// ebreak is easier to find in waves.
#if 1
#define check_equal(a, b) tb_assert((a) == (b), "Line %d: " #a " == " #b "\nGot: %08x != %08x\n", __LINE__, (a), (b))
#else
#define check_equal(a, b) if ((a) != (b)) {asm ("ebreak");}
#endif

int main() {
	check_equal(__h3_funpackq3_s(0x00000000), 1 << 29);
	check_equal(__h3_funpackq3_s(0x7fffffff), (1 << 30) - (1 << 6));
	check_equal(__h3_funpackq3_s(0x007fffff), (1 << 30) - (1 << 6));
	check_equal(__h3_funpackq3_s(0x80000000), -1 << 29);
	check_equal(__h3_funpackq3_s(0xffffffff), -(1u << 30) + (1u << 6));
	check_equal(__h3_funpackq3_s(0x807fffff), -(1u << 30) + (1u << 6));

	check_equal(__h3_funpackq3_h(0x0000), 1 << 29);
	check_equal(__h3_funpackq3_h(0x7fff), (1 << 30) - (1 << 19));
	check_equal(__h3_funpackq3_h(0x03ff), (1 << 30) - (1 << 19));
	check_equal(__h3_funpackq3_h(0x8000), -1 << 29);
	check_equal(__h3_funpackq3_h(0xffff), -(1u << 30) + (1u << 19));
	check_equal(__h3_funpackq3_h(0x83ff), -(1u << 30) + (1u << 19));

	check_equal(__h3_funpacku3_s(0x00000000), 1 << 29);
	check_equal(__h3_funpacku3_s(0x7fffffff), (1 << 30) - (1 << 6));
	check_equal(__h3_funpacku3_s(0x007fffff), (1 << 30) - (1 << 6));
	check_equal(__h3_funpacku3_s(0x80000000), 1 << 29);
	check_equal(__h3_funpacku3_s(0xffffffff), (1u << 30) - (1u << 6));
	check_equal(__h3_funpacku3_s(0x807fffff), (1u << 30) - (1u << 6));

	check_equal(__h3_funpacku3_h(0x0000), 1 << 29);
	check_equal(__h3_funpacku3_h(0x7fff), (1 << 30) - (1 << 19));
	check_equal(__h3_funpacku3_h(0x03ff), (1 << 30) - (1 << 19));
	check_equal(__h3_funpacku3_h(0x8000), 1 << 29);
	check_equal(__h3_funpacku3_h(0xffff), (1u << 30) - (1u << 19));
	check_equal(__h3_funpacku3_h(0x83ff), (1u << 30) - (1u << 19));

	check_equal(__h3_fcheck2e_s(0x00, 0x00), 1);
	check_equal(__h3_fcheck2e_s(0x00, 0x01), 1);
	check_equal(__h3_fcheck2e_s(0x01, 0x00), 1);
	check_equal(__h3_fcheck2e_s(0x01, 0x01), 0);
	check_equal(__h3_fcheck2e_s(0xff, 0xff), 1);
	check_equal(__h3_fcheck2e_s(0xff, 0x01), 1);
	check_equal(__h3_fcheck2e_s(0x01, 0xff), 1);
	check_equal(__h3_fcheck2e_s(0x01, 0x01), 0);
	check_equal(__h3_fcheck2e_s(0x1f, 0x1f), 0);
	check_equal(__h3_fcheck2e_s(-1, -1),     1);

	check_equal(__h3_fcheck2e_h(0x00, 0x00), 1);
	check_equal(__h3_fcheck2e_h(0x00, 0x01), 1);
	check_equal(__h3_fcheck2e_h(0x01, 0x00), 1);
	check_equal(__h3_fcheck2e_h(0x01, 0x01), 0);
	check_equal(__h3_fcheck2e_h(0x1f, 0x1f), 1);
	check_equal(__h3_fcheck2e_h(0x1f, 0x01), 1);
	check_equal(__h3_fcheck2e_h(0x01, 0x1f), 1);
	check_equal(__h3_fcheck2e_h(0x01, 0x01), 0);
	check_equal(__h3_fcheck2e_h(0xff, 0xff), 1);
	check_equal(__h3_fcheck2e_h(-1, -1),     1);

	check_equal(__h3_feadjq3(0), -30);
	check_equal(__h3_feadjq3(0x80000000), 2);
	check_equal(__h3_feadjq3(1), -29);
	check_equal(__h3_feadjq3(-1), -29);
	check_equal(__h3_feadjq3(16), -25);
	check_equal(__h3_feadjq3(-16), -25);
	check_equal(__h3_feadjq3(1 << 29), 0);
	check_equal(__h3_feadjq3(-1 << 29), 0);

	check_equal(__h3_feadju3(0), -30);
	check_equal(__h3_feadju3(0x80000000), 2);
	check_equal(__h3_feadju3(1), -29);
	check_equal(__h3_feadju3(-1), 2);
	check_equal(__h3_feadju3(16), -25);
	check_equal(__h3_feadju3(-16), 2);
	check_equal(__h3_feadju3(1 << 29), 0);
	check_equal(__h3_feadju3(-1 << 29), 2);

	check_equal(__h3_ssrasticky(1, 0), 1);
	check_equal(__h3_ssrasticky(1, 1), 1);
	check_equal(__h3_ssrasticky(1, 31), 1);
	check_equal(__h3_ssrasticky(1, 255), 1);
	check_equal(__h3_ssrasticky(1, -1), 2);
	check_equal(__h3_ssrasticky(1, -31), 1 << 31);
	check_equal(__h3_ssrasticky(1, -255), 0);
	check_equal(__h3_ssrasticky(1, -256), 0);
	check_equal(__h3_ssrasticky(1u << 31, 30), -2);
	check_equal(__h3_ssrasticky(1u << 31, 31), -1);
	check_equal(__h3_ssrasticky(1u << 31, 32), -1);
	check_equal(__h3_ssrasticky(1u << 31, 255), -1);
	check_equal(__h3_ssrasticky((1u << 31) + (1u << 8), 16), (-1 << 15) + 1);
	check_equal(__h3_ssrasticky(1, 511), 1);
	check_equal(__h3_ssrasticky(1u << 31, 511), -1);
	check_equal(__h3_ssrasticky(1, -512), 0);
	check_equal(__h3_ssrasticky(1u << 31, -512), 0);

	check_equal(__h3_ssrlsticky(1, 0), 1);
	check_equal(__h3_ssrlsticky(1, 1), 1);
	check_equal(__h3_ssrlsticky(1, 31), 1);
	check_equal(__h3_ssrlsticky(1, 255), 1);
	check_equal(__h3_ssrlsticky(1, -1), 2);
	check_equal(__h3_ssrlsticky(1, -31), 1 << 31);
	check_equal(__h3_ssrlsticky(1, -255), 0);
	check_equal(__h3_ssrlsticky(1, -256), 0);
	check_equal(__h3_ssrlsticky(1 << 31, 30), 2);
	check_equal(__h3_ssrlsticky(1 << 31, 31), 1);
	check_equal(__h3_ssrlsticky(1 << 31, 32), 1);
	check_equal(__h3_ssrlsticky(1 << 31, 255), 1);
	check_equal(__h3_ssrlsticky(1, 511), 1);
	check_equal(__h3_ssrlsticky(1u << 31, 511), 1);
	check_equal(__h3_ssrlsticky(1, -512), 0);
	check_equal(__h3_ssrlsticky(1u << 31, -512), 0);

	check_equal(__h3_ssla(1, 0), 1);
	check_equal(__h3_ssla(1, 1), 2);
	check_equal(__h3_ssla(1, 31), 1 << 31);
	check_equal(__h3_ssla(1, 255), 0);
	check_equal(__h3_ssla(1, -1), 0);
	check_equal(__h3_ssla(1, -31), 0);
	check_equal(__h3_ssla(1, -255), 0);
	check_equal(__h3_ssla(1, -256), 0);
	check_equal(__h3_ssla(1u << 31, 30), 0);
	check_equal(__h3_ssla(1u << 31, 31), 0);
	check_equal(__h3_ssla(1u << 31, 32), 0);
	check_equal(__h3_ssla(1u << 31, 255), 0);
	check_equal(__h3_ssla(1u << 31, -30), -2);
	check_equal(__h3_ssla(1u << 31, -31), -1);
	check_equal(__h3_ssla(1u << 31, -32), -1);
	check_equal(__h3_ssla(1u << 31, -256), -1);
	check_equal(__h3_ssla(1, 511), 0);
	check_equal(__h3_ssla(1u << 31, 511), 0);
	check_equal(__h3_ssla(1, -512), 0);
	check_equal(__h3_ssla(1u << 31, -512), -1);

	check_equal(__h3_ssll(1, 0), 1);
	check_equal(__h3_ssll(1, 1), 2);
	check_equal(__h3_ssll(1, 31), 1 << 31);
	check_equal(__h3_ssll(1, 255), 0);
	check_equal(__h3_ssll(1, -1), 0);
	check_equal(__h3_ssll(1, -31), 0);
	check_equal(__h3_ssll(1, -255), 0);
	check_equal(__h3_ssll(1, -256), 0);
	check_equal(__h3_ssll(1u << 31, 30), 0);
	check_equal(__h3_ssll(1u << 31, 31), 0);
	check_equal(__h3_ssll(1u << 31, 32), 0);
	check_equal(__h3_ssll(1u << 31, 255), 0);
	check_equal(__h3_ssll(1u << 31, -30), 2);
	check_equal(__h3_ssll(1u << 31, -31), 1);
	check_equal(__h3_ssll(1u << 31, -32), 0);
	check_equal(__h3_ssll(1u << 31, -256), 0);
	check_equal(__h3_ssll(1, 511), 0);
	check_equal(__h3_ssll(1u << 31, 511), 0);
	check_equal(__h3_ssll(1, -512), 0);
	check_equal(__h3_ssll(1u << 31, -512), 0);

	check_equal(__h3_ssra(1, 0), 1);
	check_equal(__h3_ssra(1, -1), 2);
	check_equal(__h3_ssra(1, -31), 1 << 31);
	check_equal(__h3_ssra(1, -255), 0);
	check_equal(__h3_ssra(1, -256), 0);
	check_equal(__h3_ssra(1, 1), 0);
	check_equal(__h3_ssra(1, 31), 0);
	check_equal(__h3_ssra(1, 255), 0);
	check_equal(__h3_ssra(1u << 31, -30), 0);
	check_equal(__h3_ssra(1u << 31, -31), 0);
	check_equal(__h3_ssra(1u << 31, -32), 0);
	check_equal(__h3_ssra(1u << 31, -255), 0);
	check_equal(__h3_ssra(1u << 31, -256), 0);
	check_equal(__h3_ssra(1u << 31, 30), -2);
	check_equal(__h3_ssra(1u << 31, 31), -1);
	check_equal(__h3_ssra(1u << 31, 32), -1);
	check_equal(__h3_ssra(1, 511), 0);
	check_equal(__h3_ssra(1u << 31, 511), -1);
	check_equal(__h3_ssra(1, -512), 0);
	check_equal(__h3_ssra(1u << 31, -512), 0);

	check_equal(__h3_ssrl(1, 0), 1);
	check_equal(__h3_ssrl(1, -1), 2);
	check_equal(__h3_ssrl(1, -31), 1 << 31);
	check_equal(__h3_ssrl(1, -255), 0);
	check_equal(__h3_ssrl(1, -256), 0);
	check_equal(__h3_ssrl(1, 1), 0);
	check_equal(__h3_ssrl(1, 31), 0);
	check_equal(__h3_ssrl(1, 255), 0);
	check_equal(__h3_ssrl(1u << 31, -30), 0);
	check_equal(__h3_ssrl(1u << 31, -31), 0);
	check_equal(__h3_ssrl(1u << 31, -32), 0);
	check_equal(__h3_ssrl(1u << 31, -255), 0);
	check_equal(__h3_ssrl(1u << 31, -256), 0);
	check_equal(__h3_ssrl(1u << 31, 30), 2);
	check_equal(__h3_ssrl(1u << 31, 31), 1);
	check_equal(__h3_ssrl(1u << 31, 32), 0);
	check_equal(__h3_ssrl(1, 511), 0);
	check_equal(__h3_ssrl(1u << 31, 511), 0);
	check_equal(__h3_ssrl(1, -512), 0);
	check_equal(__h3_ssrl(1u << 31, -512), 0);

	check_equal(__h3_xorsign( 1,  1),  1);
	check_equal(__h3_xorsign( 1, -1), -1);
	check_equal(__h3_xorsign( -1, 1), -1);
	check_equal(__h3_xorsign( -1,-1),  1);
	check_equal(__h3_xorsign(0x80000000u, 0xdeadbeefu), -0xdeadbeefu);
	check_equal(__h3_xorsign(0, 0xdeadbeefu), 0xdeadbeefu);

	check_equal(__h3_fpackrq3_s(0, 0),                0x00000000); // Exact cancellation
	check_equal(__h3_fpackrq3_s(0, 255),              0x00000000); // Exact cancellation
	check_equal(__h3_fpackrq3_s(0, 510),              0x00000000); // Exact cancellation
	check_equal(__h3_fpackrq3_s(0, -512),             0x00000000); // Exact cancellation
	check_equal(__h3_fpackrq3_s(1 << 29, 0),          0x00000000); // Flush to +0
	check_equal(__h3_fpackrq3_s(1 << 29, 255),        0x7f800000); // Smallest +inf
	check_equal(__h3_fpackrq3_s((1 << 30) - 1, 255),  0x7f800000); // Exponent increase on round from +inf
	check_equal(__h3_fpackrq3_s((1 << 30) - 1, 254),  0x7f800000); // Exponent increase on round to +inf
	check_equal(__h3_fpackrq3_s(-1 << 29, 0),         0x80000000); // Flush to -0
	check_equal(__h3_fpackrq3_s(-1 << 29, 255),       0xff800000)  // Smallest -inf
	check_equal(__h3_fpackrq3_s((-1 << 30) + 1, 255), 0xff800000); // Exponent increase on round from -inf
	check_equal(__h3_fpackrq3_s((-1 << 30) + 1, 254), 0xff800000); // Exponent increase on round to -inf
	check_equal(__h3_fpackrq3_s(0x2000001f, 127),     0x3f800000); // Round down to even
	check_equal(__h3_fpackrq3_s(0x20000020, 127),     0x3f800000); // Tie-break down to even
	check_equal(__h3_fpackrq3_s(0x20000021, 127),     0x3f800001); // Round up to odd
	check_equal(__h3_fpackrq3_s(0x2000005f, 127),     0x3f800001); // Round down to odd
	check_equal(__h3_fpackrq3_s(0x20000060, 127),     0x3f800002); // Tie-break up to even
	check_equal(__h3_fpackrq3_s(0x20000061, 127),     0x3f800002); // Round up to even
	check_equal(__h3_fpackrq3_s(0x3fffffe0, 127),     0x40000000); // Exponent increase on round up
	check_equal(__h3_fpackrq3_s(0x3fffffff, 0),       0x00800000); // Round up to normality
	check_equal(__h3_fpackrq3_s(-0x2000001f, 127),    0xbf800000); // Round up to even
	check_equal(__h3_fpackrq3_s(-0x20000020, 127),    0xbf800000); // Tie-break up to even
	check_equal(__h3_fpackrq3_s(-0x20000021, 127),    0xbf800001); // Round down to odd
	check_equal(__h3_fpackrq3_s(-0x2000005f, 127),    0xbf800001); // Round up to odd
	check_equal(__h3_fpackrq3_s(-0x20000060, 127),    0xbf800002); // Tie-break down to even
	check_equal(__h3_fpackrq3_s(-0x20000061, 127),    0xbf800002); // Round down to even
	check_equal(__h3_fpackrq3_s(-0x3fffffe0, 127),    0xc0000000); // Exponent increase on round down
	check_equal(__h3_fpackrq3_s(-0x3fffffff, 0),      0x80800000); // Round down to normality

	check_equal(__h3_fpackrq3_h(0, 0),                    0x00000000); // Exact cancellation
	check_equal(__h3_fpackrq3_h(0, 31),                   0x00000000); // Exact cancellation
	check_equal(__h3_fpackrq3_h(0, 510),                  0x00000000); // Exact cancellation
	check_equal(__h3_fpackrq3_h(0, -512),                 0x00000000); // Exact cancellation
	check_equal(__h3_fpackrq3_h(1 << 29, 0),              0x00000000); // Flush to +0
	check_equal(__h3_fpackrq3_h(1 << 29, 31),             0x00007c00); // Smallest +inf
	check_equal(__h3_fpackrq3_h((1 << 30) - 1, 31),       0x00007c00); // Exponent increase on round from +inf
	check_equal(__h3_fpackrq3_h((1 << 30) - 1, 30),       0x00007c00); // Exponent increase on round to +inf
	check_equal(__h3_fpackrq3_h(-1 << 29, 0),             0xffff8000); // Flush to -0
	check_equal(__h3_fpackrq3_h(-1 << 29, 31),            0xfffffc00)  // Smallest -inf
	check_equal(__h3_fpackrq3_h((-1 << 30) + 1, 31),      0xfffffc00); // Exponent increase on round from -inf
	check_equal(__h3_fpackrq3_h((-1 << 30) + 1, 30),      0xfffffc00); // Exponent increase on round to -inf
	check_equal(__h3_fpackrq3_h(0x2003ffff, 15),          0x00003c00); // Round down to even
	check_equal(__h3_fpackrq3_h(0x20040000, 15),          0x00003c00); // Tie-break down to even
	check_equal(__h3_fpackrq3_h(0x20040001, 15),          0x00003c01); // Round up to odd
	check_equal(__h3_fpackrq3_h(0x200bffff, 15),          0x00003c01); // Round down to odd
	check_equal(__h3_fpackrq3_h(0x200c0000, 15),          0x00003c02); // Tie-break up to even
	check_equal(__h3_fpackrq3_h(0x200c0001, 15),          0x00003c02); // Round up to even
	check_equal(__h3_fpackrq3_h(0x3fffffe0, 15),          0x00004000); // Exponent increase on round up
	check_equal(__h3_fpackrq3_h(0x3fffffff, 0),           0x00000400); // Round up to normality
	check_equal(__h3_fpackrq3_h(-0x2003ffff, 15),         0xffffbc00); // Round up to even
	check_equal(__h3_fpackrq3_h(-0x20040000, 15),         0xffffbc00); // Tie-break up to even
	check_equal(__h3_fpackrq3_h(-0x20040001, 15),         0xffffbc01); // Round down to odd
	check_equal(__h3_fpackrq3_h(-0x200bffff, 15),         0xffffbc01); // Round up to odd
	check_equal(__h3_fpackrq3_h(-0x200c0000, 15),         0xffffbc02); // Tie-break down to even
	check_equal(__h3_fpackrq3_h(-0x200c0001, 15),         0xffffbc02); // Round down to even
	check_equal(__h3_fpackrq3_h(-0x3fffffe0, 15),         0xffffc000); // Exponent increase on round down
	check_equal(__h3_fpackrq3_h(-0x3fffffff, 0),          0xffff8400); // Round down to normality

	return 0;
}