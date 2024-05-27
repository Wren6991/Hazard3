# Set up root paths used by Makefiles (there is a lot of cross-referencing,
# e.g. tests referencing the HDL directory). This .mk file is
# (eventually) included by every Makefile in the project.

PROJ_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
HDL       := $(PROJ_ROOT)/hdl
SCRIPTS   := $(PROJ_ROOT)/scripts
