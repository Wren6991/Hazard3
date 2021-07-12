TOP              := tb

all: tb

SYNTH_CMD += read_verilog -I ../../../hdl $(shell listfiles tb.f);
SYNTH_CMD += hierarchy -top $(TOP); proc; opt_clean; async2sync;
SYNTH_CMD += write_cxxrtl -g4 dut.cpp

dut.cpp:
	yosys -p "$(SYNTH_CMD)" 2>&1 > cxxrtl.log

clean::
	rm -f dut.cpp cxxrtl.log tb

tb: dut.cpp
	clang++ -O3 -std=c++14 $(addprefix -D,$(CDEFINES)) -I $(shell yosys-config --datdir)/include tb.cpp -o tb
