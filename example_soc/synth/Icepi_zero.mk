include ../project_paths.mk

CHIPNAME=fpga_icepi_zero
TOP=fpga_icepi_zero
DOTF=../fpga/fpga_icepi_zero.f

SYNTH_OPT=-abc9
PNR_OPT=--timing-allow-fail

DEVICE=25k
PACKAGE=CABGA256
DEVICE_IDCODE=0x41111043

include $(SCRIPTS)/synth_ecp5.mk

# Get openFPGALoader from: git@github.com:trabucayre/openFPGALoader.git
prog: bit
	openFPGALoader -b icepi-zero $(CHIPNAME).bit

flash: bit
	openFPGALoader -b icepi-zero -f $(CHIPNAME).bit
