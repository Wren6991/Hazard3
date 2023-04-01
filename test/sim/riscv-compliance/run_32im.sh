#!/bin/bash
set -e

make -C riscv-arch-test RISCV_TARGET=hazard3 RISCV_DEVICE=M
