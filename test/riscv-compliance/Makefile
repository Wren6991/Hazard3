TEST = I-ADD-01
TEST_ARCH = rv32i
BIN_ARCH = rv32i
SIM_EXEC = ../tb_cxxrtl/tb

CROSS_PREFIX = /opt/riscv/bin/riscv32-unknown-elf-

TEST_BIN_NAME := $(TEST_ARCH)-$(TEST)-on-$(BIN_ARCH)
TEST_SRC := riscv-compliance/riscv-test-suite/$(TEST_ARCH)/src/$(TEST).S
TEST_VEC := riscv-compliance/riscv-test-suite/$(TEST_ARCH)/references/$(TEST).reference_output

.PHONY: all
all:
	mkdir -p tmp
	$(CROSS_PREFIX)gcc -I include -T memmap.ld -nostartfiles -march=$(BIN_ARCH) $(TEST_SRC) -o tmp/$(TEST_BIN_NAME).elf
	$(CROSS_PREFIX)objdump -d tmp/$(TEST_BIN_NAME).elf > tmp/$(TEST_BIN_NAME).dis
	$(CROSS_PREFIX)objcopy -O binary tmp/$(TEST_BIN_NAME).elf tmp/$(TEST_BIN_NAME).bin
	$(SIM_EXEC) tmp/$(TEST_BIN_NAME).bin --dump 0x10000 0x10100 | tee tmp/$(TEST_BIN_NAME).log
	./compare_testvec tmp/$(TEST_BIN_NAME).log $(TEST_VEC)
