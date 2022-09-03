TEST_ARCH = I
BIN_ARCH = rv64i
SIM_EXEC = ../tb_cxxrtl/tb

CROSS_PREFIX = riscv64-unknown-elf-

TESTLIST= \
  add-01 \
  addi-01 \
  and-01 \
  andi-01 \
  auipc-01 \
  beq-01 \
  bge-01 \
  bgeu-01 \
  blt-01 \
  bltu-01 \
  bne-01 \
  fence-01 \
  jal-01 \
  jalr-01 \
  lb-align-01 \
  lbu-align-01 \
  lh-align-01 \
  lhu-align-01 \
  lui-01 \
  lw-align-01 \
  or-01 \
  ori-01 \
  sb-align-01 \
  sh-align-01 \
  sll-01 \
  slli-01 \
  slt-01 \
  slti-01 \
  sltiu-01 \
  sltu-01 \
  sra-01 \
  srai-01 \
  srl-01 \
  srli-01 \
  sub-01 \
  sw-align-01 \
  xor-01 \
  xori-01

.PHONY: all testlist clean $(addprefix test-,$(TESTLIST))
all: testlist

define make-test-target
  # Turns out variable expansions inside functions don't work like I thought they did. Oh well this will do
  test-$1:
	mkdir -p tmp
	$(CROSS_PREFIX)gcc -I include -T memmap.ld -nostartfiles -march=$(BIN_ARCH) riscv-arch-test/riscv-test-suite/rv64i_m/$(TEST_ARCH)/src/$1.S -DXLEN=64 -o tmp/$(TEST_ARCH)-$1-on-$(BIN_ARCH).elf
	$(CROSS_PREFIX)objdump -h tmp/$(TEST_ARCH)-$1-on-$(BIN_ARCH).elf > tmp/$(TEST_ARCH)-$1-on-$(BIN_ARCH).dis
	$(CROSS_PREFIX)objdump -d tmp/$(TEST_ARCH)-$1-on-$(BIN_ARCH).elf >> tmp/$(TEST_ARCH)-$1-on-$(BIN_ARCH).dis
	$(CROSS_PREFIX)objcopy -O binary tmp/$(TEST_ARCH)-$1-on-$(BIN_ARCH).elf tmp/$(TEST_ARCH)-$1-on-$(BIN_ARCH).bin
	$(SIM_EXEC) --bin tmp/$(TEST_ARCH)-$1-on-$(BIN_ARCH).bin --vcd tmp/$(TEST_ARCH)-$1-on-$(BIN_ARCH).vcd --dump 0x400000 0x404000 --cycles 1000000 > tmp/$(TEST_ARCH)-$1-on-$(BIN_ARCH).log
	./compare_testvec tmp/$(TEST_ARCH)-$1-on-$(BIN_ARCH).log riscv-arch-test/riscv-test-suite/rv64i_m/$(TEST_ARCH)/references/$1.reference_output
endef

$(foreach test,$(TESTLIST),$(eval $(call make-test-target,$(test))))

testlist: $(addprefix test-,$(TESTLIST))

clean:
	rm -rf tmp/
