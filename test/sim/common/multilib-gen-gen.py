#!/usr/bin/env python3

# Generate a multilib configure line for riscv-gnu-toolchain with useful
# combinations of extensions supported by both Hazard3 and mainline GCC
# (currently GCC 14). Use as:
# ./configure ... --with-multilib-generator="$(path/to/multilib-gen-gen.py)"

base = "rv32i"
abi = "-ilp32--"
options = [
	# GCC13+:
	"m",
	"a",
	"c",
	"zicsr",
	"zifencei",
	"zba",
	"zbb",
	"zbc",
	"zbs",
	"zbkb",
	# GCC14 only:
	"zca",
	"zcb",
	# "zcmp" (waiting on binutils 2.43)
]

# Do not build for LHS except when *all of* RHS is also present. This cuts
# down on the number of configurations. A leading "!" means antidependency,
# i.e. an incompatibility.
depends_on = {
	"zbb":      ["m", "zba", "zbs"          ],
	"zba":      ["m", "zbb", "zbs"          ],
	"zbs":      ["m", "zba", "zbb"          ],
	"zbkb":     ["zbb"                      ],
	"zbc":      ["zba", "zbb", "zbs", "zbkb"],
	"zifencei": ["zicsr"                    ],
	"c":        ["!zca"                     ],
	"zca":      ["!c"                       ],
	"zcb":      ["zca"                      ],
	# "zcmp":     ["zca", "zcb",              ],
}

l = []
for i in range(2 ** len(options)):
	isa = base
	violates_dependencies = False
	for j in (j for j in range(len(options)) if i & (1 << j)):
		opt = options[j]
		if opt in depends_on:
			for dep in depends_on[opt]:
				inverted_dep = dep.startswith("!")
				if inverted_dep: dep = dep[1:]
				if inverted_dep == bool(i & (1 << options.index(dep))):
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

print(len(l))
