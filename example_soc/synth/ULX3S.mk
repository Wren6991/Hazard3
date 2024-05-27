include ../project_paths.mk

CHIPNAME=fpga_ulx3s
TOP=fpga_ulx3s
DOTF=../fpga/fpga_ulx3s.f

SYNTH_OPT=-abc9
PNR_OPT=--timing-allow-fail

DEVICE=um5g-85k
PACKAGE=CABGA381

include $(SCRIPTS)/synth_ecp5.mk

prog: bit
	ujprog $(CHIPNAME).bit

flash: bit
	ujprog -j flash $(CHIPNAME).bit
