# To build single-core dual-port tb: make
# To build dual-core single-port tb: make DOTF=tb_multicore.f
# To build with debug agent support: make CDEFINES=CXXRTL_DEBUG_AGENT

include ../project_paths.mk

TOP       := tb
DOTF      := tb.f
CONFIG    := default
TBEXEC    := $(patsubst %.f,%,$(DOTF))

ifneq ($(CONFIG),default)
  TBEXEC := $(TBEXEC)-$(CONFIG)
endif

FILE_LIST := $(shell HDL=$(HDL) $(SCRIPTS)/listfiles ../tb_common/hdl/$(DOTF))
VINCDIR   := $(shell HDL=$(HDL) $(SCRIPTS)/listfiles -f flati ../tb_common/hdl/$(DOTF))
BUILD_DIR := build-$(TBEXEC)

CPPFILES  := tb.cpp $(wildcard ../tb_common/*.cpp)
CPPINCDIR =
CPPINCDIR += $(shell yosys-config --datdir)/include/backends/cxxrtl/runtime
CPPINCDIR += $(BUILD_DIR)
CPPINCDIR += ../tb_common/include

CLANGXX   := clang++

.PHONY: clean all lint

all: $(TBEXEC)

SYNTH_CMD += read_verilog $(addprefix -I ,$(VINCDIR)) -DCONFIG_HEADER="config_$(CONFIG).vh" $(FILE_LIST);
SYNTH_CMD += hierarchy -top $(TOP);
SYNTH_CMD += write_cxxrtl $(BUILD_DIR)/dut.cpp

$(BUILD_DIR)/dut.cpp: $(FILE_LIST) $(wildcard *.vh) $(VINCDIR)
	mkdir -p $(BUILD_DIR)
	yosys -p '$(SYNTH_CMD)' 2>&1 > $(BUILD_DIR)/cxxrtl.log

clean::
	rm -rf $(BUILD_DIR) $(TBEXEC)

$(TBEXEC): $(BUILD_DIR)/dut.cpp $(CPPFILES)
	$(CLANGXX) -Oz -std=c++14 $(addprefix -D,$(CDEFINES) $(CDEFINES_$(DOTF))) $(addprefix -I ,$(CPPINCDIR)) $(CPPFILES) -o $(TBEXEC)

lint:
	verilator --lint-only --top-module $(TOP) $(addprefix -I,$(VINCDIR)) -DCONFIG_HEADER="\"config_$(CONFIG).vh\"" $(FILE_LIST)
