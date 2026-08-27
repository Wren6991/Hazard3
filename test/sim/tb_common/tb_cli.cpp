#include "tb_cli.h"
#include "tb_constants.h"
#include <iostream>

static const char *help_str =
"Usage: tb [--bin x.bin] [--port n] [--vcd x.vcd] [--dump start end] \\\n"
"          [--cycles n] [--cpuret] [--jtagdump x] [--jtagreplay x]\n"
"\n"
"    --bin x.bin      : Flat binary file loaded to address 0x0 in RAM\n"
"    --vcd x.vcd      : Path to dump waveforms to\n"
"    --dump start end : Print out memory contents from start to end (exclusive)\n"
"                       after execution finishes. Can be passed multiple times.\n"
"    --cycles n       : Maximum number of cycles to run before exiting.\n"
"                       Default is 0 (no maximum).\n"
"    --port n         : Port number to listen for openocd remote bitbang. Sim\n"
"                       runs in lockstep with JTAG bitbang, not free-running.\n"
"    --cpuret         : Testbench's return code is the return code written to\n"
"                       IO_EXIT by the CPU, or -1 if timed out.\n"
"    --jtagdump       : Dump OpenOCD JTAG bitbang commands to a file so they\n"
"                       can be replayed. (Lower perf impact than VCD dumping)\n"
"    --jtagreplay     : Play back some dumped OpenOCD JTAG bitbang commands\n"
"    --bus-stall-p    : Generate bus stalls with probability p (float 0..1)\n"
"    --logfile path   : File to write testbench stdout\n"
"    --sigfile path   : File to write only the data from --dump commands\n"
"                       (hex, 32 bits per line, same as riscv-arch-test)\n"
#ifdef COVERAGE
"    --coverage path  : File to write RTL coverage data to\n"
#endif
#ifdef CXXRTL_DEBUG_AGENT
"    --debug          : Run CXXRTL debugger\n"
#endif
;

static void exit_help(std::string errtext = "") {
	std::cerr << errtext << help_str;
	exit(-1);
}

void tb_parse_args(int argc, char **argv, tb_cli_args &args) {
	for (int i = 1; i < argc; ++i) {
		std::string s(argv[i]);
		if (s.substr(0, 11) == "+verilator+") {
			// Skip arguments passed directly to verilator context
			i += 1;
		} else if (s.rfind("--", 0) != 0) {
			std::cerr << "Unexpected positional argument " << s << "\n";
			exit_help("");
		} else if (s == "--bin") {
			if (argc - i < 2)
				exit_help("Option --bin requires an argument\n");
			args.load_bin = true;
			args.bin_path = argv[i + 1];
			i += 1;
		} else if (s == "--vcd") {
			if (argc - i < 2)
				exit_help("Option --vcd requires an argument\n");
			args.dump_waves = true;
			args.waves_path = argv[i + 1];
			i += 1;
		} else if (s == "--logfile") {
			if (argc - i < 2)
				exit_help("Option --logfile requires an argument\n");
			args.log_path = argv[i + 1];
			i += 1;
		} else if (s == "--sigfile") {
			if (argc - i < 2)
				exit_help("Option --sigfile requires an argument\n");
			args.sig_path = argv[i + 1];
			i += 1;
		} else if (s == "--coverage") {
			// Still parse this when COVERAGE is not defined, so it's
			// swallowed as a no-op.
			if (argc - i < 2)
				exit_help("Option --coverage requires an argument\n");
			args.coverage_path = argv[i + 1];
			i += 1;
		} else if (s == "--jtagdump") {
			if (argc - i < 2)
				exit_help("Option --jtagdump requires an argument\n");
			args.dump_jtag = true;
			args.jtag_dump_path = argv[i + 1];
			i += 1;
		} else if (s == "--jtagreplay") {
			if (argc - i < 2)
				exit_help("Option --jtagreplay requires an argument\n");
			args.replay_jtag = true;
			args.jtag_replay_path = argv[i + 1];
			i += 1;
		} else if (s == "--bus-stall-p") {
			if (argc - i < 2)
				exit_help("Option --bus-stall-p requires an argument\n");
			float p = atof(argv[i + 1]);
			if (p < 0.f || p > 1.f) {
				std::cerr << "--bus-stall-p requires a float between 0 and 1.\n";
				exit(-1);
			}
			args.bus_stall_p = (uint32_t)(p * (uint32_t)-1u);
			i += 1;
		} else if (s == "--dump") {
			if (argc - i < 3)
				exit_help("Option --dump requires 2 arguments\n");
			uint32_t first = std::stoul(argv[i + 1], 0, 0);
			uint32_t last = std::stoul(argv[i + 2], 0, 0);
			if (first < MEM_BASE || last > MEM_BASE + MEM_SIZE || first > last) {
				std::cerr << "Invalid memory range\n";
				exit(-1);
			}
			args.dump_ranges.push_back(std::pair<uint32_t, uint32_t>(
				first, last
			));
			i += 2;
		} else if (s == "--cycles") {
			if (argc - i < 2)
				exit_help("Option --cycles requires an argument\n");
			args.max_cycles = std::stol(argv[i + 1], 0, 0);
			i += 1;
		} else if (s == "--port") {
			if (argc - i < 2)
				exit_help("Option --port requires an argument\n");
			args.port = std::stol(argv[i + 1], 0, 0);
			i += 1;
		} else if (s == "--cpuret") {
			args.propagate_return_code = true;
#ifdef CXXRTL_DEBUG_AGENT
		} else if (s == "--debug") {
			args.run_agent = true;
#endif
		} else {
			std::cerr << "Unrecognised argument " << s << "\n";
			exit_help("");
		}
	}
	if (!(args.load_bin || args.port != 0 || args.replay_jtag))
		exit_help("At least one of --bin, --port or --jtagreplay must be specified.\n");
	if (args.dump_jtag && args.port == 0)
		exit_help("--jtagdump specified, but there is no JTAG socket to dump from.\n");
	if (args.replay_jtag && args.port != 0)
		exit_help("Can't specify both --port and --jtagreplay\n");
}
