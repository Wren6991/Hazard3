#!/bin/bash

set -ex

make -C ../tb_verilator -j$(nproc)
make -C micropython/ports/hazard3-tests submodules
make -C micropython/ports/hazard3-tests -j$(nproc)

cd micropython/tests
MICROPY_TEST_TIMEOUT=300 ./run-tests.py \
	-t "exec:../../../tb_verilator/tb --bin ../ports/hazard3-tests/build/firmware.bin" \
	-d basics -j$(nproc) \
	|| ./run-tests.py --print-failures

