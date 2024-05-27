# Source this file to add paths and tools to your shell environment. The stock
# Makefiles should work fine with just project_dir_paths.mk but it can be
# convenient to have everything available in your shell.

export PROJ_ROOT = $(git rev-parse --show-toplevel)
export HDL       = ${PROJ_ROOT}/hdl
export SCRIPTS   = ${PROJ_ROOT}/scripts

export PATH      = "${PATH}:${PROJ_ROOT}/scripts"
export PATH      = "${PATH}:/opt/riscv/bin"
