TOP    := tb
DOTF   := tb.f
CONFIG := default
TBEXEC := $(patsubst %.f,%,$(DOTF))

.PHONY: clean all

all: $(TBEXEC)

SYNTH_CMD += read_verilog -I ../../../hdl -DCONFIG_HEADER="config_$(CONFIG).vh" $(shell listfiles $(DOTF));
SYNTH_CMD += hierarchy -top $(TOP);
SYNTH_CMD += write_cxxrtl build-$(DOTF)/dut.cpp

build-$(DOTF)/dut.cpp: $(shell listfiles $(DOTF))
	mkdir -p build-$(DOTF)
	yosys -p '$(SYNTH_CMD)' 2>&1 > build-$(DOTF)/cxxrtl.log

clean::
	rm -f build-$(DOTF) $(TBEXEC)

$(TBEXEC): build-$(DOTF)/dut.cpp tb.cpp
	clang++ -O3 -std=c++14 $(addprefix -D,$(CDEFINES)) -I $(shell yosys-config --datdir)/include -I build-$(DOTF) tb.cpp -o $(TBEXEC)
