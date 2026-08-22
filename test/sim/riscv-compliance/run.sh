#!/bin/bash
set -e

echo "Rebuilding simulator..."
make -C ../tb_cxxrtl CONFIG=archtest
echo "Cleaning up previous run..."
cd riscv-arch-test/riscof-plugins/rv32
rm -rf riscof_work
echo "Starting..."
riscof run --config config.ini --suite ../../riscv-test-suite/ --env ../../riscv-test-suite/env
