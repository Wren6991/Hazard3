# Copyright 2018 Embedded Microprocessor Benchmark Consortium (EEMBC)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 
# Original Author: Shay Gal-on

#File : core_portme.mak

#	Use this flag to define how to to get an executable (e.g -o)
OUTFLAG= -o

# Note removing C (compressed) support tends to slightly improve performance
# by eliminating alignment nops. This is really a toolchain issue because
# most 2-byte alignment nops could also be eliminated by selectively
# expanding 16-bit instructions to 32-bit.
MARCH        = rv32imac_zicsr_zifencei_zba_zbb_zbkb_zbs
CROSS_PREFIX = riscv32-unknown-elf-

CC           =  $(CROSS_PREFIX)gcc
LD           =  $(CROSS_PREFIX)gcc
AS           =  $(CROSS_PREFIX)gcc

# Slightly shorter alternative when compressed instructions are not used:
# PORT_CFLAGS = -O3 -g -march=$(MARCH) -mbranch-cost=1 -funroll-all-loops --param max-inline-insns-auto=200 -finline-limit=10000 -fno-code-hoisting -fno-if-conversion2
PORT_CFLAGS = -O3 -g -march=$(MARCH) -mbranch-cost=1 -funroll-all-loops --param max-inline-insns-auto=200 -finline-limit=10000 -fno-code-hoisting -fno-if-conversion2 -falign-functions=4 -falign-jumps=4 -falign-loops=4

FLAGS_STR = "$(PORT_CFLAGS) $(XCFLAGS) $(XLFLAGS) $(LFLAGS_END)"
CFLAGS = $(PORT_CFLAGS) -I$(PORT_DIR) -I. -DFLAGS_STR=\"$(FLAGS_STR)\" 

#Flag : LFLAGS_END
#	Define any libraries needed for linking or other flags that should come at the end of the link line (e.g. linker scripts). 

SEPARATE_COMPILE=1
# Flag : SEPARATE_COMPILE
# You must also define below how to create an object file, and how to link.

OBJOUT 	= -o
LFLAGS 	= -T ../../common/memmap.ld -Wl,--noinhibit-exec -march=$(MARCH)
ASFLAGS = -c -march=$(MARCH)
OFLAG 	= -o
COUT 	= -c

LFLAGS_END = 
# Flag : PORT_SRCS
# 	Port specific source files can be added here
#	You may also need cvt.c if the fcvt functions are not provided as intrinsics by your compiler!
PORT_SRCS = $(PORT_DIR)/core_portme.c $(PORT_DIR)/ee_printf.c $(PORT_DIR)/init.S
PORT_OBJS = $(addsuffix $(OEXT),$(patsubst %.c,%,$(patsubst %.S,%,$(PORT_SRCS))))
vpath %.c $(PORT_DIR)
vpath %.s $(PORT_DIR)
vpath %.S $(PORT_DIR)

# Flag : LOAD
#	For a simple port, we assume self hosted compile and run, no load needed.

# Flag : RUN
#	For a simple port, we assume self hosted compile and run, simple invocation of the executable

LOAD = echo "Please set LOAD to the process of loading the executable to the flash"
RUN = echo "Please set LOAD to the process of running the executable (e.g. via jtag, or board reset)"

OEXT = .o
EXE = .elf

$(OPATH)$(PORT_DIR)/%$(OEXT) : %.c
	$(CC) $(CFLAGS) $(XCFLAGS) $(COUT) $< $(OBJOUT) $@

$(OPATH)%$(OEXT) : %.c
	$(CC) $(CFLAGS) $(XCFLAGS) $(COUT) $< $(OBJOUT) $@

$(OPATH)$(PORT_DIR)/%$(OEXT) : %.s
	$(AS) $(ASFLAGS) $< $(OBJOUT) $@

$(OPATH)$(PORT_DIR)/%$(OEXT) : %.S
	$(AS) $(ASFLAGS) $< $(OBJOUT) $@

# Target : port_pre% and port_post%
# For the purpose of this simple port, no pre or post steps needed.

.PHONY : port_prebuild port_postbuild port_prerun port_postrun port_preload port_postload
port_pre% port_post% : 

MKDIR = mkdir -p

