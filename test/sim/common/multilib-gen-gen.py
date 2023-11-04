#!/usr/bin/env python3

# Generate a multilib configure line for riscv-gnu-toolchain with all
# combinations of extensions supported by both Hazard3 and mainline GCC
# (currently GCC 13.2). Use as:
# ./configure ... --with-multilib-generator="$(path/to/multilib-gen-gen.py)"

base = "rv32i"
abi = "-ilp32--"
options = [
	"m",
	"a",
	"c",
	"_zicsr",
	"_zifencei",
	"_zba",
	"_zbb",
	"_zbc",
	"_zbs",
	"_zbkb"
]

l = []
for i in range(2 ** len(options)):
	isa = base
	for j in range(len(options)):
		if i & (1 << j):
			isa += options[j]
	l.append(isa + abi)

print(";".join(l))
