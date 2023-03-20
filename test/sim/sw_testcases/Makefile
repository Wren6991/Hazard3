APP        := hellow
SRCS        = ../common/init.S $(APP).c $(EXTRA_SRCS_$(APP))
CCFLAGS    := -march=rv32imac_zicsr_zba_zbb_zbs_zcb -Os
MAX_CYCLES := 1000000
INCDIR     := include ../common

EXTRA_SRCS_irq_force              := ../common/irq_dispatch.S
EXTRA_SRCS_irq_top_bottom         := ../common/irq_dispatch.S
EXTRA_SRCS_irq_preempt_set_in_irq := ../common/irq_dispatch.S
EXTRA_SRCS_irq_set_all_with_pri   := ../common/irq_dispatch.S

include ../common/src_only_app.mk
