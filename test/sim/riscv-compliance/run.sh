#!/bin/bash

set -e

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

echo "Rebuilding simulator..."
make -C ../tb_cxxrtl CONFIG=archtest
if [[ ${CLEAN} == 1 ]]; then
	echo "Cleaning..."
	make -C riscv-arch-test clean
fi
echo "Starting..."
make -C riscv-arch-test hazard3
