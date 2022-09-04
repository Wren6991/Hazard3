#include "tb_cxxrtl_io.h"

int main() {
	volatile uint64_t p = 7006652, q = 5678;
	tb_put_u32(p / q); // = 1234
}
