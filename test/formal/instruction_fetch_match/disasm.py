#!/usr/bin/env python3

from os import system

prog = []
for l in open("bmc.log"):
	if "Value for anyconst in tb.dut.core" in l:
		prog.append(l.split(" ")[-1])
with open("disasm.s", "w") as f:
	for instr in prog:
		f.write(f".word {instr}")

system("riscv32-unknown-elf-gcc -march=rv32imac_zicsr_zifencei_zba_zbb_zbkb_zbs -c disasm.s")
# -d fails to disassemble compressed instructions (sometimes?) so use -D -j .text instead
system("riscv32-unknown-elf-objdump -D -j .text -M numeric,no-aliases disasm.o")

