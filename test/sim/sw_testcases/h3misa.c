#include "tb_cxxrtl_io.h"

/*EXPECTED-OUTPUT***************************************************************

Detected extensions:
A
B
C
I
M
Zba
Zbb
Zbc
Zbkb
Zbkc
Zbkx
Zbs
Zkt
Zca
Zcb
Zilsd
Zclsd
Zcmp
Zifencei
Zmmul
Zibi

*******************************************************************************/

const struct {const char *name; int groupid; int bit;} c_api_bitmap[] = {
	{"A",           0, 0 },
	{"B",           0, 1 },
	{"C",           0, 2 },
	{"D",           0, 3 },
	{"E",           0, 4 },
	{"F",           0, 5 },
	{"H",           0, 7 },
	{"I",           0, 8 },
	{"M",           0, 12},
	{"Q",           0, 16},
	{"V",           0, 21},
	{"Zacas",       0, 26},
	{"Zba",         0, 27},
	{"Zbb",         0, 28},
	{"Zbc",         0, 29},
	{"Zbkb",        0, 30},
	{"Zbkc",        0, 31},
	{"Zbkx",        0, 32},
	{"Zbs",         0, 33},
	{"Zfa",         0, 34},
	{"Zfh",         0, 35},
	{"Zfhmin",      0, 36},
	{"Zicboz",      0, 37},
	{"Zicond",      0, 38},
	{"Zihintntl",   0, 39},
	{"Zihintpause", 0, 40},
	{"Zknd",        0, 41},
	{"Zkne",        0, 42},
	{"Zknh",        0, 43},
	{"Zksed",       0, 44},
	{"Zksh",        0, 45},
	{"Zkt",         0, 46},
	{"Ztso",        0, 47},
	{"Zvbb",        0, 48},
	{"Zvbc",        0, 49},
	{"Zvfh",        0, 50},
	{"Zvfhmin",     0, 51},
	{"Zvkb",        0, 52},
	{"Zvkg",        0, 53},
	{"Zvkned",      0, 54},
	{"Zvknha",      0, 55},
	{"Zvknhb",      0, 56},
	{"Zvksed",      0, 57},
	{"Zvksh",       0, 58},
	{"Zvkt",        0, 59},
	{"Zve32x",      0, 60},
	{"Zve32f",      0, 61},
	{"Zve64x",      0, 62},
	{"Zve64f",      0, 63},
	{"Zve64d",      1, 0 },
	{"Zimop",       1, 1 },
	{"Zca",         1, 2 },
	{"Zcb",         1, 3 },
	{"Zcd",         1, 4 },
	{"Zcf",         1, 5 },
	{"Zcmop",       1, 6 },
	{"Zawrs",       1, 7 },
	{"Zilsd",       1, 8 },
	{"Zclsd",       1, 9 },
	{"Zcmp",        1, 10},
	{"Zifencei",    1, 11},
	{"Zmmul",       1, 12},
	{"Zibi",        1, 13},
};

static inline uint32_t h3_misa_read(uint32_t index) {
	uint32_t ret;
	asm ("csrrw %0, 0xbf1, %1" : "=r" (ret) : "r" (index));
	return ret;
}

bool h3_misa_extension_supported(unsigned int groupid, unsigned int bit_position) {
	unsigned int index = groupid * 64u + bit_position;
	if (index >= h3_misa_read(0x400u)) {
		return false;
	}
	return h3_misa_read(index >> 5) & (1u << (index & 0x1f));
}

int main() {
	tb_printf("Detected extensions:\n");
	for (int i = 0; i < sizeof(c_api_bitmap) / sizeof(c_api_bitmap[0]); ++i) {
		if (h3_misa_extension_supported(c_api_bitmap[i].groupid, c_api_bitmap[i].bit)) {
			tb_printf("%s\n", c_api_bitmap[i].name);
		}
	}
	return 0;
}
