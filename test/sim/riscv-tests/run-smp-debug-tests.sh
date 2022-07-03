set -e

make -C ../tb_cxxrtl/ DOTF=tb_multicore.f tb
# make -C ../tb_cxxrtl/ DOTF=tb_multicore.f clean tb
cd riscv-tests/debug

# Clean up old logs and test binaries
rm -rf logs
for fname in $(find -name "*" -maxdepth 1); do
	if file ${fname} | grep -q "ELF 32-bit"; then rm ${fname}; fi
done

# Only applicable tests are included
./gdbserver.py \
	--sim_cmd "../../../tb_cxxrtl/tb --port 9824" \
	--server_cmd riscv-openocd \
	--gdb riscv32-unknown-elf-gdb \
	--gcc riscv32-unknown-elf-gcc \
	targets/luke/hazard3_smp.py
