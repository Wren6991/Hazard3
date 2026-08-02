ifndef SRCS
$(error Must define list of test sources as SRCS)
endif

ifndef APP
$(error Must define application name as APP)
endif

CCFLAGS      ?=
LDSCRIPT     ?= ../common/memmap.ld
CROSS_PREFIX ?= riscv32-unknown-elf-
INCDIR       ?= ../common
TMP_PREFIX   ?= tmp/

# Useless:
override CCFLAGS += -g -Wl,--no-warn-rwx-segments

###############################################################################

.SUFFIXES:
.PHONY: all tb clean clean_tb

all: hex

hex: $(TMP_PREFIX)$(APP).hex

bin: $(TMP_PREFIX)$(APP).bin

clean:
	rm -rf $(TMP_PREFIX)

###############################################################################


$(TMP_PREFIX)$(APP).hex: $(TMP_PREFIX)$(APP).bin
	hexdump -v -e '1/4 "%08x\n"' $< > $@

$(TMP_PREFIX)$(APP).bin: $(TMP_PREFIX)$(APP).elf
	$(CROSS_PREFIX)objcopy -O binary $^ $@
	$(CROSS_PREFIX)objdump -h $^ > $(TMP_PREFIX)$(APP).dis
	$(CROSS_PREFIX)objdump -d $^ >> $(TMP_PREFIX)$(APP).dis

$(TMP_PREFIX)$(APP).elf: $(SRCS) $(wildcard %.h)
	mkdir -p $(TMP_PREFIX)
	$(CROSS_PREFIX)gcc $(CCFLAGS) $(SRCS) -T $(LDSCRIPT) $(addprefix -I,$(INCDIR)) -o $@
