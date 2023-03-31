#!/bin/bash
set -ex

make -C riscv-arch-test RISCV_TARGET=hazard3 RISCV_DEVICE=I
