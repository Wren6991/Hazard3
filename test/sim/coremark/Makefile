APP          := coremark
MAX_CYCLES   := 100000000

CROSS_PREFIX ?= riscv32-unknown-elf-
TBEXEC       ?= ../tb_cxxrtl/tb
TBDIR        := $(dir $(abspath $(TBEXEC)))


###############################################################################

.SUFFIXES:
.PHONY: all run waves view bin tb clean clean_tb

all: run

run: $(APP).bin
	$(TBEXEC) --bin $(APP).bin --cycles $(MAX_CYCLES)

waves: $(APP).bin
	$(TBEXEC) $(APP).bin $(APPNAME)_run.vcd --cycles $(MAX_CYCLES)

view: run
	gtkwave $(APP)_run.vcd

bin: $(APP).bin

tb:
	$(MAKE) -C $(TBDIR) tb

clean:
	rm -f $(APP).elf $(APP).bin $(APP).dis $(APP)_run.vcd
	rm -rf dist/build/

clean_tb: clean
	$(MAKE) -C $(TBDIR) clean

###############################################################################

$(APP).bin: $(APP).elf
	$(CROSS_PREFIX)objcopy -O binary $^ $@
	$(CROSS_PREFIX)objdump -h $(APP).elf > $(APP).dis
	$(CROSS_PREFIX)objdump -d $(APP).elf >> $(APP).dis

$(APP).elf:
	make -C dist
	cp dist/build/coremark.elf $(APP).elf
