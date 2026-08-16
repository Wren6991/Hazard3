# Usually provided by passing --march=xxx to ./runtests
MARCH      ?= rv32imac_zicsr_zifencei_zba_zbb_zbkb_zbs

ifeq (,$(findstring rv32e,$(MARCH)))
    MABI := ilp32
else
    MABI := ilp32e
endif

# Avoid shadowing libgcc implementations of float functions (e.g. if we want
# to test Xh3sfx versions against the upstream default soft float lib):
DEFINES    := XH3SFX_LIB_PREFIX=__h3_

APP        := hellow
SRCS        = ../common/init.S $(APP).c $(EXTRA_SRCS_$(APP))
CCFLAGS    := -march=$(MARCH) -mabi=$(MABI) -Os $(addprefix -D,$(DEFINES))
MAX_CYCLES := 1000000
INCDIR     := include ../common

EXTRA_SRCS_irq_force              := ../common/irq_dispatch.S
EXTRA_SRCS_irq_preempt_set_in_irq := ../common/irq_dispatch.S
EXTRA_SRCS_irq_set_all_with_pri   := ../common/irq_dispatch.S
EXTRA_SRCS_irq_top_bottom         := ../common/irq_dispatch.S
EXTRA_SRCS_xh3sfx_addhf           := ../common/xh3sfx_float_lib.S
EXTRA_SRCS_xh3sfx_addsf           := ../common/xh3sfx_float_lib.S
EXTRA_SRCS_xh3sfx_convert_h       := ../common/xh3sfx_float_lib.S
EXTRA_SRCS_xh3sfx_convert_s       := ../common/xh3sfx_float_lib.S
EXTRA_SRCS_xh3sfx_mulhf           := ../common/xh3sfx_float_lib.S
EXTRA_SRCS_xh3sfx_mulsf           := ../common/xh3sfx_float_lib.S

include ../common/src_only_app.mk
