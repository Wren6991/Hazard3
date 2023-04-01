#!/bin/bash
set -e

make -C riscv-arch-test RISCV_TARGET=hazard3 RISCV_DEVICE=I clean
make -C riscv-arch-test RISCV_TARGET=hazard3 RISCV_DEVICE=M clean
make -C riscv-arch-test RISCV_TARGET=hazard3 RISCV_DEVICE=C clean
