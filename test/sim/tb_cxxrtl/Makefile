TOP              := tb
DOTF             := tb.f

CPU_RESET_VECTOR := 32'h40

EXTENSION_C      := 1
EXTENSION_M      := 1
EXTENSION_ZBA    := 1
EXTENSION_ZBB    := 1
EXTENSION_ZBC    := 1
EXTENSION_ZBS    := 1
DEBUG_SUPPORT    := 1

MULDIV_UNROLL    := 2
MUL_FAST         := 1
MULH_FAST        := 1
REDUCED_BYPASS   := 0

MVENDORID_VAL    := 32'hdeadbeef
MIMPID_VAL       := 32'h12345678
MCONFIGPTR_VAL   := 32'h9abcdef0

.PHONY: clean all

all: tb

SYNTH_CMD += read_verilog -I ../../../hdl $(shell listfiles $(DOTF));
SYNTH_CMD += chparam -set EXTENSION_C $(EXTENSION_C) $(TOP);
SYNTH_CMD += chparam -set EXTENSION_M $(EXTENSION_M) $(TOP);
SYNTH_CMD += chparam -set EXTENSION_ZBA $(EXTENSION_ZBA) $(TOP);
SYNTH_CMD += chparam -set EXTENSION_ZBB $(EXTENSION_ZBB) $(TOP);
SYNTH_CMD += chparam -set EXTENSION_ZBC $(EXTENSION_ZBC) $(TOP);
SYNTH_CMD += chparam -set EXTENSION_ZBS $(EXTENSION_ZBS) $(TOP);
SYNTH_CMD += chparam -set DEBUG_SUPPORT $(DEBUG_SUPPORT) $(TOP);
SYNTH_CMD += chparam -set CSR_COUNTER 1 $(TOP);
SYNTH_CMD += chparam -set RESET_VECTOR $(CPU_RESET_VECTOR) $(TOP);
SYNTH_CMD += chparam -set REDUCED_BYPASS $(REDUCED_BYPASS) $(TOP);
SYNTH_CMD += chparam -set MULDIV_UNROLL $(MULDIV_UNROLL) $(TOP);
SYNTH_CMD += chparam -set MUL_FAST $(MUL_FAST) $(TOP);
SYNTH_CMD += chparam -set MULH_FAST $(MULH_FAST) $(TOP);
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
