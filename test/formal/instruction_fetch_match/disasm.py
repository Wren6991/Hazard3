#!/usr/bin/env python3

from os import system

prog = []
for l in open("bmc.log"):
	if "Value for anyconst in tb.dut.core" in l:
		prog.append(l.split(" ")[-1])
with open("disasm.s", "w") as f:
	for instr in prog:
		f.write(f".word {instr}")

system("riscv32-unknown-elf-gcc -c disasm.s")
system("riscv32-unknown-elf-objdump -d -M numeric,no-aliases disasm.o")
