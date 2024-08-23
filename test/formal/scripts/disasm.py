#!/usr/bin/env python3

# Scrape instruction values from a formal counterexample trace, and
# disassemble the result

# pip3 install verilog_vcd (or use venv if you're a nerd)
from Verilog_VCD.Verilog_VCD import parse_vcd

from os import system
from sys import argv

fd_cir = None
df_cir_use = None

for netinfo in parse_vcd(argv[1]).values():
    for net in netinfo['nets']:
        # print(net["hier"], net["name"])
        if net["name"] == "fd_cir":
            fd_cir = netinfo['tv']
        if net["name"] == "df_cir_use":
            df_cir_use = netinfo['tv']

assert len(fd_cir) == len(df_cir_use)

with open("disasm.s", "w") as f:
    for instr, size in zip(fd_cir, df_cir_use):
        instr = int(instr[1], 2)
        size = int(size[1], 2)
        # print(f"cir={instr:08x} (used: {size} hwords)")
        if size == 1:
            f.write(f".hword 0x{instr & 0xffff:04x}\n")
        elif size == 2:
            f.write(f".word 0x{instr:08x}\n")
    # Also jam in the last CIR value as it tends to still be relevant even
    # when it doesn't complete
    f.write(f".word 0x{int(fd_cir[-1][1], 2):08x}\n")

system("riscv32-unknown-elf-gcc -c disasm.s")
system("riscv32-unknown-elf-objdump -D -j .text -M numeric,no-aliases disasm.o")


