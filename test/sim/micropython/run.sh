#!/bin/bash

set -ex

CLEAN=0
for arg in "$@"; do
	case ${arg} in
	--clean)
		CLEAN=1
		;;
	*)
		echo "Unrecognised arg '${arg}'"
		exit 1
		;;
	esac
done

make -C ../tb_verilator -j$(nproc)
make -C micropython/ports/hazard3-tests submodules
if [[ ${CLEAN} == 1 ]]; then
	make -C micropython/ports/hazard3-tests clean
fi
make -C micropython/ports/hazard3-tests -j$(nproc)

cd micropython/tests
MICROPY_TEST_TIMEOUT=300 ./run-tests.py \
	-t "exec:../../../tb_verilator/tb --cpuret --bin ../ports/hazard3-tests/build/firmware.bin" \
	-j$(nproc) \
	|| ./run-tests.py --print-failures

