#include "tb_cxxrtl_io.h"


#include <stdint.h>

#define read_csr(csrname) ({ \
  uint32_t __csr_tmp_u32; \
  __asm__ ("csrr %0, " #csrname : "=r" (__csr_tmp_u32)); \
  __csr_tmp_u32; \
})

#define write_csr(csrname, val) __asm__ ("csrw " #csrname ", %0" : : "r" (val))

void __attribute__((interrupt)) handle_exception() {
	uint32_t call_num;
	asm volatile ("mv %0, a7" : "=r" (call_num));
	tb_puts("Handling ecall. Call number:\n");
	tb_put_u32(call_num);
	write_csr(mepc, read_csr(mepc) + 4);
}

static inline void make_ecall(uint32_t call) {
	asm volatile ("mv a7, %0 \n ecall" : : "r" (call));
}

const uint32_t call_nums[] = {
	0x123,
	0x456,
	0xdeadbeef
};

void main() {
	tb_puts("mcause initial value:\n");
	tb_put_u32(read_csr(mcause));
	for (int i = 0; i < sizeof(call_nums) / sizeof(*call_nums); ++i)
		make_ecall(call_nums[i]);
	tb_puts("Finished making calls.\n");
	tb_puts("mcause final value:\n");
	tb_put_u32(read_csr(mcause));
	tb_exit(0);
}
