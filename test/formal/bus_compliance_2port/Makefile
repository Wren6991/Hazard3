include ../project_paths.mk

DOTF=tb.f
TOP=tb
YOSYS_SMT_SOLVER=z3
DEPTH=25

# Also check internal properties
DEFINES=HAZARD3_ASSERTIONS

all: bmc

include $(SCRIPTS)/formal.mk
