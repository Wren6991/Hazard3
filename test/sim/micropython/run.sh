#!/bin/bash

set -ex

make -C ../tb_verilator -j$(nproc)
make -C micropython/ports/hazard3-tests -j$(nproc)
cd micropython/tests
./run-tests.py -t "exec:../../../tb_verilator/tb --bin ../ports/hazard3-tests/build/firmware.bin"         
