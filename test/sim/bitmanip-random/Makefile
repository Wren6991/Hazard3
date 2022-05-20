BIN_ARCH     = rv32imc_zba_zbb_zbc_zbs_zicsr
SIM_EXEC     = ../tb_cxxrtl/tb

CROSS_PREFIX = /opt/riscv/bin/riscv32-unknown-elf-
SPIKE        = spike
PK           = $(RISCV)/riscv32-unknown-elf/bin/pk

TESTLIST=$(patsubst %.S,%,$(patsubst test/%,%,$(wildcard test/*.S)))

.PHONY: all testall makerefs clean cleanrefs $(addprefix test-,$(TESTLIST)) $(addprefix ref-,$(TESTLIST))
all: testall

define make-test-target
  test-$1:
	mkdir -p tmp
	$(CROSS_PREFIX)gcc -I include -T memmap.ld -nostartfiles -march=$(BIN_ARCH) test/$1.S -o tmp/$1.elf
	$(CROSS_PREFIX)objdump -h tmp/$1.elf > tmp/$1.dis
	$(CROSS_PREFIX)objdump -d tmp/$1.elf >> tmp/$1.dis
	$(CROSS_PREFIX)objdump -j .testdata -d tmp/$1.elf >> tmp/$1.dis
	$(CROSS_PREFIX)objcopy -O binary tmp/$1.elf tmp/$1.bin
	$(SIM_EXEC) --bin tmp/$1.bin --vcd tmp/$1.vcd --dump 0x400000 0x410000 > tmp/$1.log
	../riscv-compliance/compare_testvec tmp/$1.log reference/$1.reference_output
endef

# Creating reference vectors requires a recent `spike` to be installed on your PATH.
define make-reference-target
  ref-$1:
	mkdir -p reference
	@echo "Reference for $1"
	$(CROSS_PREFIX)gcc -march=$(BIN_ARCH) -o tmp/spike-$1 refgen/$1.c
	$(SPIKE) --isa=$(BIN_ARCH) $(PK) tmp/spike-$1 | tail -n +2 > reference/$1.reference_output
endef


$(foreach test,$(TESTLIST),$(eval $(call make-test-target,$(test))))
$(foreach test,$(TESTLIST),$(eval $(call make-reference-target,$(test))))

testall: $(addprefix test-,$(TESTLIST))
makerefs: $(addprefix ref-,$(TESTLIST))

clean:
	rm -rf tmp/

cleanrefs:
	rm -rf reference/
