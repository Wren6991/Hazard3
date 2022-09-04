TOP                 := tb
DOTF                := tb.f

CPU_RESET_VECTOR    := 32'h40

MVENDORID_VAL       := 32'hdeadbeef
MIMPID_VAL          := 32'h12345678
MCONFIGPTR_VAL      := 32'h9abcdef0

.PHONY: clean all

all: tb

SYNTH_CMD += read_verilog -I ../../../hdl $(shell listfiles $(DOTF));
SYNTH_CMD += chparam -set RESET_VECTOR $(CPU_RESET_VECTOR) $(TOP);
SYNTH_CMD += chparam -set MVENDORID_VAL $(MVENDORID_VAL) $(TOP);
SYNTH_CMD += chparam -set MIMPID_VAL $(MIMPID_VAL) $(TOP);
SYNTH_CMD += chparam -set MCONFIGPTR_VAL $(MCONFIGPTR_VAL) $(TOP);
SYNTH_CMD += hierarchy -top $(TOP);
SYNTH_CMD += write_cxxrtl dut.cpp

dut.cpp: $(shell listfiles $(DOTF))
	yosys -p "$(SYNTH_CMD)" 2>&1 > cxxrtl.log

clean::
	rm -f dut.cpp cxxrtl.log tb

tb: dut.cpp tb.cpp
	clang++ -O3 -std=c++14 $(addprefix -D,$(CDEFINES)) -I $(shell yosys-config --datdir)/include tb.cpp -o tb
