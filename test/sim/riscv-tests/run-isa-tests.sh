set -e

make -C ../tb_cxxrtl tb
cd riscv-tests/isa
make XLEN=32 clean

# Note SKIP_V is something I added to their Makefile. We have no need for the
# virtual memory test machine configuration.
make -j$(nproc) XLEN=32 SKIP_V=1 rv32ui rv32uc rv32um rv32ua rv32mi

for test in $(find -name "*-p-*.bin"); do echo $test; ../../../tb_cxxrtl/tb --bin $test --cycles 10000 --vcd $test.vcd --cpuret; done