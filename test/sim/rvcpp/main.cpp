#include <cassert>
#include <cstdio>
#include <iostream>
#include <fstream>
#include <tuple>
#include <vector>

#include "rv_types.h"
#include "rv_csr.h"
#include "rv_core.h"
#include "rv_mem.h"

// Minimal RISC-V interpreter, supporting:
// - RV32I
// - M
// - A
// - C (also called Zca)
// - Zba
// - Zbb
// - Zbc
// - Zbs
// - Zbkb
// - Zcmp
// - M-mode traps

#define RAM_SIZE_DEFAULT (16u * (1u << 20))
#define RAM_BASE         0u
#define IO_BASE          0x80000000u
#define TBIO_BASE        (IO_BASE + 0x0000)

const char *help_str =
"Usage: tb [--bin x.bin] [--dump start end] [--vcd x.vcd] [--cycles n]\n"
"    --bin x.bin      : Flat binary file loaded to address 0x0 in RAM\n"
"    --vcd x.vcd      : Dummy option for compatibility with CXXRTL tb\n"
"    --dump start end : Print out memory contents between start and end (exclusive)\n"
"                       after execution finishes. Can be passed multiple times.\n"
"    --cycles n       : Maximum number of cycles to run before exiting.\n"
"    --cpuret         : Testbench's return code is the return code written to\n"
"                       IO_EXIT by the CPU, or -1 if timed out.\n"
"    --memsize n      : Memory size in units of 1024 bytes, default is 16 MiB\n"
"    --trace          : Print out execution tracing info\n"
;

void exit_help(std::string errtext = "") {
	std::cerr << errtext << help_str;
	exit(-1);
}

int main(int argc, char **argv) {
	if (argc < 2)
		exit_help();

	std::vector<std::tuple<uint32_t, uint32_t>> dump_ranges;
	int64_t max_cycles = 100000;
	uint32_t ram_size = RAM_SIZE_DEFAULT;
	bool load_bin = false;
	std::string bin_path;
	bool trace_execution = false;
	bool propagate_return_code = false;

	for (int i = 1; i < argc; ++i) {
		std::string s(argv[i]);
		if (s == "--bin") {
			if (argc - i < 2)
				exit_help("Option --bin requires an argument\n");
			load_bin = true;
			bin_path = argv[i + 1];
			i += 1;
		}
		else if (s == "--vcd") {
			if (argc - i < 2)
				exit_help("Option --vcd requires an argument\n");
			// (We ignore this argument, it's supported for
			i += 1;
		}
		else if (s == "--dump") {
			if (argc - i < 3)
				exit_help("Option --dump requires 2 arguments\n");
			dump_ranges.push_back(std::make_tuple(
				std::stoul(argv[i + 1], 0, 0),
				std::stoul(argv[i + 2], 0, 0)
			));
			i += 2;
		}
		else if (s == "--cycles") {
			if (argc - i < 2)
				exit_help("Option --cycles requires an argument\n");
			max_cycles = std::stol(argv[i + 1], 0, 0);
			i += 1;
		}
		else if (s == "--memsize") {
			if (argc - i < 2)
				exit_help("Option --memsize requires an argument\n");
			ram_size = 1024 * std::stol(argv[i + 1], 0, 0);
			i += 1;
		}
		else if (s == "--trace") {
			trace_execution = true;
		}
		else if (s == "--cpuret") {
			propagate_return_code = true;
		}
		else {
			std::cerr << "Unrecognised argument " << s << "\n";
			exit_help("");
		}
	}

	TBMemIO io;
	MemMap32 mem;
	mem.add(0x80000000u, 12, &io);

	RVCore core(mem, RAM_BASE + 0x40, RAM_BASE, ram_size);

	if (load_bin) {
		std::ifstream fd(bin_path, std::ios::binary | std::ios::ate);
		std::streamsize bin_size = fd.tellg();
		if (bin_size > ram_size) {
			std::cerr << "Binary file (" << bin_size << " bytes) is larger than memory (" << ram_size << " bytes)\n";
			return -1;
		}
		fd.seekg(0, std::ios::beg);
		fd.read((char*)core.ram, bin_size);
	}

	int64_t cyc;
	int rc = 0;
	try {
		for (cyc = 0; cyc < max_cycles; ++cyc)
			core.step(trace_execution);
		if (propagate_return_code)
			rc = -1;
	}
	catch (TBExitException e) {
		printf("CPU requested halt. Exit code %d\n", e.exitcode);
		printf("Ran for %ld cycles\n", cyc + 1);
		if (propagate_return_code)
			rc = e.exitcode;
	}

	for (auto [start, end] : dump_ranges) {
		printf("Dumping memory from %08x to %08x:\n", start, end);
		for (uint32_t i = 0; i < end - start; ++i)
			printf("%02x%c", *core.r8(start + i), i % 16 == 15 ? '\n' : ' ');
		printf("\n");
	}

	return rc;
}
