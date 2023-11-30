#!/usr/bin/env python3

# Generate a multilib configure line for riscv-gnu-toolchain with all useful
# combinations of extensions supported by both Hazard3 and mainline GCC
# (currently GCC 13.2). Use as:
# ./configure ... --with-multilib-generator="$(path/to/multilib-gen-gen.py)"

base = "rv32i"
abi = "-ilp32--"
options = [
	"m",
	"a",
	"c",
	"zicsr",
	"zifencei",
	"zba",
	"zbb",
	"zbc",
	"zbs",
	"zbkb"
]

# The relationship here is: do not build for LHS except when *all of* RHS is
# also present. This cuts down on the number of configurations whilst
# hopefully preserving ones that are useful for Hazard3 development.
depends_on = {
	"zbb":      ["m"                ],
	"zba":      ["m"                ],
	"zbkb":     ["zbb"              ],
	"zbs":      ["zbb",             ],
	"zbc":      ["zba", "zbb", "zbs"],
	"zifencei": ["zicsr"            ],
}

l = []
for i in range(2 ** len(options)):
	isa = base
	violates_dependencies = False
	for j in (j for j in range(len(options)) if i & (1 << j)):
		opt = options[j]
		if opt in depends_on:
			for dep in depends_on[opt]:
				if not (i & (1 << options.index(dep))):
					violates_dependencies = True
					break
		if violates_dependencies:
			break
		if len(opt) > 1:
			isa += "_"
		isa += opt
	if not violates_dependencies:
		l.append(isa + abi)

assert((base + abi) in l)

print(";".join(l))
