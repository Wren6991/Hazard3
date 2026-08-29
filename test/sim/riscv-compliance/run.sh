#!/bin/bash

set -e

COV_DIR=${PWD}/cov-work

CLEAN=0
COVERAGE=0
for arg in "$@"; do
	case ${arg} in
	--clean)
		CLEAN=1
		;;
	--coverage)
		COVERAGE=1
		;;
	*)
		echo "Unrecognised arg '${arg}'"
		exit 1
		;;
	esac
done

echo "Rebuilding simulators..."
make -C ../tb_verilator CONFIG=archtest COVERAGE=${COVERAGE} -j $(nproc)
make -C ../tb_verilator CONFIG=min      COVERAGE=${COVERAGE} -j $(nproc)

if [[ ${CLEAN} == 1 ]]; then
	echo "Cleaning..."
	make -C riscv-arch-test clean
	rm -rf ${COV_DIR}
	(find riscv-arch-test/work -name '*.cov' -print | xargs rm) || true
fi

echo "Starting..."
if [[ ${COVERAGE} == 1 ]]; then
	export HAZARD3_RVTEST_TB_SUFFIX=-cov
fi

# The suite may legitimately fail individual tests (e.g. known upstream
# bugs); still merge coverage and report, then propagate the failure.
set +e
make -C riscv-arch-test hazard3
RUN_STATUS=$?
set -e

if [[ ${COVERAGE} == 1 ]]; then
	echo "Merging coverage data..."
	mkdir -p "${COV_DIR}"
	COV_FILES=$(find riscv-arch-test/work -name '*.cov' -print)
	verilator_coverage --write "${COV_DIR}/merged.dat" ${COV_FILES}
	verilator_coverage --report summary "${COV_DIR}/merged.dat" | tee "${COV_DIR}/summary.txt"
	verilator_coverage --report hier    "${COV_DIR}/merged.dat" | tee "${COV_DIR}/hier.txt"
	verilator_coverage --write-info "${COV_DIR}/merged.info" "${COV_DIR}/merged.dat"
	genhtml "${COV_DIR}/merged.info" -o "${COV_DIR}/html"
	verilator_coverage --annotate-points --annotate "${COV_DIR}/annotated" "${COV_DIR}/merged.dat"
	echo "Coverage reports written to ${COV_DIR}:"
	echo "  html/index.html  line+branch HTML report"
	echo "  summary.txt      aggregate line/toggle/branch/expr/fsm"
	echo "  hier.txt         per-module hierarchy breakdown"
	echo "  annotated/       per-point source annotation"
fi

exit ${RUN_STATUS}
