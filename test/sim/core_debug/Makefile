TOP              := hazard3_cpu_2port
CDEFINES         := DUAL_PORT

CPU_RESET_VECTOR := 32'hc0
EXTENSION_C      := 1
EXTENSION_M      := 1
DEBUG_SUPPORT    := 1
MULDIV_UNROLL    := 2
MUL_FAST         := 1
REDUCED_BYPASS   := 0

.PHONY: clean tb all run

all: run

run: tb
	./tb zero.bin waves.vcd

SYNTH_CMD += read_verilog -I ../../../hdl $(shell listfiles ../../../hdl/hazard3.f);
SYNTH_CMD += chparam -set EXTENSION_C $(EXTENSION_C) $(TOP);
SYNTH_CMD += chparam -set EXTENSION_M $(EXTENSION_M) $(TOP);
SYNTH_CMD += chparam -set DEBUG_SUPPORT $(DEBUG_SUPPORT) $(TOP);
SYNTH_CMD += chparam -set CSR_COUNTER 1 $(TOP);
SYNTH_CMD += chparam -set RESET_VECTOR $(CPU_RESET_VECTOR) $(TOP);
SYNTH_CMD += chparam -set REDUCED_BYPASS $(REDUCED_BYPASS) $(TOP);
SYNTH_CMD += chparam -set MULDIV_UNROLL $(MULDIV_UNROLL) $(TOP);
SYNTH_CMD += chparam -set MUL_FAST $(MUL_FAST) $(TOP);
SYNTH_CMD += prep -flatten -top $(TOP); async2sync;
SYNTH_CMD += write_cxxrtl dut.cpp

dut.cpp:
	yosys -p "$(SYNTH_CMD)" 2>&1 > cxxrtl.log

clean::
	rm -f dut.cpp cxxrtl.log tb

tb: dut.cpp
	clang++ -O3 -std=c++14 $(addprefix -D,$(CDEFINES)) -I $(shell yosys-config --datdir)/include tb.cpp -o tb
