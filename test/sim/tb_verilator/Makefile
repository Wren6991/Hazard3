include ../project_paths.mk

TOP       := tb
DOTF      := tb.f
CONFIG    := default
COVERAGE  ?= 0
TBEXEC    := $(patsubst %.f,%,$(DOTF))

ifneq ($(CONFIG),default)
  TBEXEC := $(TBEXEC)-$(CONFIG)
endif

ifeq ($(COVERAGE),1)
  VCOV_FLAGS := --coverage
  TBEXEC     := $(TBEXEC)-cov
endif

FILE_LIST := $(shell HDL=$(HDL) $(SCRIPTS)/listfiles ../tb_common/hdl/$(DOTF))
VINCDIR   := $(shell HDL=$(HDL) $(SCRIPTS)/listfiles -f flati ../tb_common/hdl/$(DOTF))
BUILD_DIR := build-$(patsubst %.f,%,$(DOTF))
ifeq ($(COVERAGE),1)
  BUILD_DIR := $(BUILD_DIR)-cov
  CDEFINES  += COVERAGE
endif
VOBJ_DIR  := $(BUILD_DIR)/obj_dir
VLIB      := $(VOBJ_DIR)/libV$(TOP).a

VERILATOR_ROOT := $(shell verilator --getenv VERILATOR_ROOT)
CXX       := g++
VERILATOR := verilator

TB_CFILES := tb.cpp $(wildcard ../tb_common/*.cpp)
CINCLUDE  := $(VOBJ_DIR) $(VERILATOR_ROOT)/include ../tb_common/include

.PHONY: clean all lint vcc vlib

all:  $(TBEXEC)
vcc:  $(BUILD_DIR)/vcc.touch
vlib: $(BUILD_DIR)/vlib.touch

$(BUILD_DIR)/vcc.touch: $(FILE_LIST) $(wildcard *.vh)
	mkdir -p $(VOBJ_DIR)
	$(VERILATOR) --Mdir $(VOBJ_DIR) --cc --trace $(VCOV_FLAGS) --top-module $(TOP) $(addprefix -I,$(VINCDIR))  -DCONFIG_HEADER="\"config_$(CONFIG).vh\"" $(FILE_LIST)
	touch $@

# CFG_GCH_IF_CLANG is set as a workaround for a verilator issue with newer GCC
# versions (see: https://github.com/verilator/verilator/issues/4730)
$(BUILD_DIR)/vlib.touch: $(BUILD_DIR)/vcc.touch
	$(MAKE) VERILATOR_ROOT=$(VERILATOR_ROOT) CFG_GCH_IF_CLANG=.gch -C $(VOBJ_DIR) -f V$(TOP).mk
	touch $@

clean::
	rm -rf $(BUILD_DIR) $(TBEXEC)

$(TBEXEC): $(BUILD_DIR)/vlib.touch $(TB_CFILES)
	$(CXX) -O3 -std=c++14 $(addprefix -D,$(CDEFINES) $(CDEFINES_$(DOTF))) \
	  $(addprefix -I ,$(CINCLUDE)) $(wildcard $(VOBJ_DIR)/*.o) $(TB_CFILES) -o $(TBEXEC)

lint:
	$(VERILATOR) --lint-only --top-module $(TOP) $(addprefix -I,$(VINCDIR)) -DCONFIG_HEADER="\"config_$(CONFIG).vh\"" $(FILE_LIST)
