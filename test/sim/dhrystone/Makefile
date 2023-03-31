SRCS       := ../common/init.S src/dhrystone_main.c src/dhrystone.c src/util.c
APP        := dhrystone
CCFLAGS    := -O3 -fno-inline -march=rv32im_zicsr_zba_zbb_zbs
MAX_CYCLES := 1000000

include ../common/src_only_app.mk
