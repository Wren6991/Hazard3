#!/usr/bin/env python3

import argparse
import re
import sys

# Script for annotating rvcpp trace output with the contents of an objdump
# disassembly file. Multiple disassembly files can be passed, in which case
# they will be merged. (Usually these files would be for non-overlapping
# address ranges: if the files overlap, the later file in command line order
# takes precedence for the overlapping address.)

parser = argparse.ArgumentParser()
parser.add_argument("logfile", help="Raw log file to be annotated, output from rvcpp --trace")
parser.add_argument("out", help="Output path for annotated log file (pass - for stdout)")
parser.add_argument("-d", "--dis", action="append", help="Specify a disassembly file (output of objdump -d) with which to annotate the log")
args = parser.parse_args()

if args.dis is None:
	sys.exit("At least one disassembly file must be specified")

label_dict = {}
instr_dict = {}
for dispath in args.dis:
	for l in open(dispath).readlines():
		if re.match(r"^\s*[0-9a-f]+:", l):
			instruction_addr = int(l.split(":")[0], 16)
			instruction_text = " ".join(l.strip().split()[2:])
			instr_dict[instruction_addr] = instruction_text
		elif re.match("^[0-9a-f]+ <", l):
			label_addr = int(l.split()[0], 16)
			label_text = l.split("<")[-1].strip("\n>:")
			label_dict[label_addr] = label_text

ifile = open(args.logfile)
if args.out == "-":
	ofile = sys.stdout
else:
	ofile = open(args.out, "w")

for l in ifile.readlines():
	# Not an addressed line, so just pass it through unmodified.
	if not re.match("^[0-9a-f]{8}:", l):
		ofile.write(l)
		continue
	addr = int(l[:8], 16)
	# If there is a label, there ought also be an instruction to be labelled.
	# assert(not (addr in label_dict and addr not in instr_dict))
	# Not an address we know about, so pass it through unmodified.
	if addr not in label_dict and addr not in instr_dict:
		ofile.write(l)
		continue
	# Removed label lines for now as the label is usually present on the jump instruction
	# if addr in label_dict:
	# 	ofile.write(" " * 42 + label_dict[addr] + ":\n")
	if addr in instr_dict:
		ofile.write(l.strip() + " " * 2 + instr_dict[addr] + "\n")


