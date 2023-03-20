APP          := coremark
MAX_CYCLES   := 100000000

CROSS_PREFIX ?= /opt/riscv/gcc-riscv32-corev/bin/riscv32-corev-elf-
TBDIR        ?= ../tb_cxxrtl


###############################################################################

.SUFFIXES:
.PHONY: all run waves view bin tb clean clean_tb

all: run

run: $(APP).bin
	$(TBDIR)/tb --bin $(APP).bin --cycles $(MAX_CYCLES)

waves: $(APP).bin
	$(TBDIR)/tb $(APP).bin $(APPNAME)_run.vcd --cycles $(MAX_CYCLES)

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
