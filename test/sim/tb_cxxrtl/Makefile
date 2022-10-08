TOP    := tb
DOTF   := tb.f
CONFIG := default

.PHONY: clean all

all: tb

SYNTH_CMD += read_verilog -I ../../../hdl -DCONFIG_HEADER="config_$(CONFIG).vh" $(shell listfiles $(DOTF));
SYNTH_CMD += hierarchy -top $(TOP);
SYNTH_CMD += write_cxxrtl dut.cpp

dut.cpp: $(shell listfiles $(DOTF))
	yosys -p '$(SYNTH_CMD)' 2>&1 > cxxrtl.log

clean::
	rm -f dut.cpp cxxrtl.log tb

tb: dut.cpp tb.cpp
	clang++ -O3 -std=c++14 $(addprefix -D,$(CDEFINES)) -I $(shell yosys-config --datdir)/include tb.cpp -o tb
