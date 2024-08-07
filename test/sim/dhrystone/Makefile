SRCS       := ../common/init.S src/dhrystone_main.c src/dhrystone.c src/util.c
APP        := dhrystone
CCFLAGS    := -O3 -fno-inline -march=rv32imac_zicsr_zifencei_zba_zbb_zbkb_zbs -Wno-implicit-function-declaration -Wno-implicit-int
MAX_CYCLES := 1000000

include ../common/src_only_app.mk
