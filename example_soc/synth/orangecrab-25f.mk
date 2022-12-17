CHIPNAME=fpga_orangecrab_25f
TOP=fpga_orangecrab_25f
DOTF=../fpga/fpga_orangecrab_25f.f

SYNTH_OPT=-abc9
PNR_OPT=--timing-allow-fail

DEVICE=25k
PACKAGE=CSFBGA285

DEVICE_IDCODE=0x41111043

include $(SCRIPTS)/synth_ecp5.mk

$(CHIPNAME).dfu: bit
	cp $(CHIPNAME).bit $@
	dfu-suffix -v 1209 -p 5af0 -a $@

prog: bit
	ujprog $(CHIPNAME).bit

flash: $(CHIPNAME).dfu
	dfu-util -d 1209:5af0 -D $<
