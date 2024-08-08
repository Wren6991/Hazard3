SRCS := ../common/init.S main.c
APP  := hello_multicore
CCFLAGS = -march=rv32imac_zicsr_zifencei_zba_zbb_zbkb_zbs -Os

DOTF := tb_multicore.f
TBEXEC := ../tb_cxxrtl/tb_multicore

include ../common/src_only_app.mk
