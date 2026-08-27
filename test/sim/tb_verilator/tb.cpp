#include "Vtb.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#ifdef COVERAGE
#include "verilated_cov.h"
#endif

#include <iostream>
#include <cstdint>
#include <string>
#include <stdio.h>

#include "tb.h"
#include "tb_cli.h"
#include "tb_jtag.h"

class tb_verilator_top: public tb_top {
	VerilatedContext *contextp;
	Vtb *top;
	VerilatedVcdC *vcd = nullptr;

	// Loop-carried address-phase requests
	bus_request req_i;
	bus_request req_d;
	bool req_i_vld = false;
	bool req_d_vld = false;
	uint64_t cycle = 0;

public:
	tb_verilator_top(const tb_cli_args &parsed_args, int argc, char **argv);
	~tb_verilator_top() {if (vcd) {vcd->close(); delete vcd;} delete top; delete contextp;}

	void step(const tb_cli_args &args, mem_io_state &memio) override;

	void dump_coverage(const std::string &path) {
#ifdef COVERAGE
		if (!path.empty()) {
			contextp->coveragep()->write(path);
		}
#endif
	}

	void set_trst_n(bool trst_n)     override {top->trst_n = trst_n;}
	void set_tck(bool tck)           override {top->tck = tck;}
	void set_tdi(bool tdi)           override {top->tdi = tdi;}
	void set_tms(bool tms)           override {top->tms = tms;}
	bool get_tdo()                   override {return top->tdo;}
	void set_irq(uint32_t mask)      override {top->irq = mask;}
	void set_soft_irq(uint8_t mask)  override {top->soft_irq = mask;}
	void set_timer_irq(uint8_t mask) override {top->timer_irq = mask;}

};

tb_verilator_top::tb_verilator_top(const tb_cli_args &parsed_args, int argc, char **argv): tb_top {parsed_args} {
	contextp = new VerilatedContext;
	// Verilated context also gets a chance to parse the arguments. Any
	// argument prefixed with "+verilator+" is ignored by our tb arg parsing.
	contextp->commandArgs(argc, argv);
	top = new Vtb{contextp};

	if (parsed_args.dump_waves) {
		contextp->traceEverOn(true);
		vcd = new VerilatedVcdC;
		top->trace(vcd, 99);
		vcd->open(parsed_args.waves_path.c_str());
	}

	req_i_vld = false;
	req_d_vld = false;
	req_i.reservation_id = 0;
	req_d.reservation_id = 1;

	// Set bus interfaces to generate good IDLE responses at first
	top->i_hready = true;
	top->d_hready = true;

	// Reset + initial clock pulse
	top->eval();
	top->clk = true;
	top->tck = true;
	top->eval();
	top->clk = false;
	top->tck = false;
	top->trst_n = true;
	top->rst_n = true;
	top->eval();

#ifdef COVERAGE
	contextp->coveragep()->zero();
#endif
}

void tb_verilator_top::step(const tb_cli_args &args, mem_io_state &memio) {
	top->clk = false;
	top->eval();
	if (vcd) {
		vcd->dump(2ull * cycle);
	}

	// Progress address phase to data phase on posedge when HREADY asserted:
	if (top->d_hready) {
		req_d_vld = top->d_htrans >> 1;
		req_d.write = top->d_hwrite;
		req_d.size = (bus_size_t)top->d_hsize;
		req_d.addr = top->d_haddr;
		req_d.excl = top->d_hexcl;
	}
	if (top->i_hready) {
		req_i_vld = top->i_htrans >> 1;
		req_i.write = top->i_hwrite;
		req_i.size = (bus_size_t)top->i_hsize;
		req_i.addr = top->i_haddr;
		req_i.excl = top->i_hexcl;
	}

	top->clk = true;
	top->eval();

	// I and D ports are handled identically, to support dual-core single-port tb

	if (top->d_hresp && !top->d_hready) {
		// ERROR ph0 -> ph1
		top->d_hready = true;
	} else if (!req_d_vld) {
		// IDLE -> OKAY
		top->d_hready = true;
		top->d_hresp = false;
	} else {
		top->d_hresp = false;
		bool stall = rand() < args.bus_stall_p;
		top->d_hready = !stall;
		if (stall) {
			top->d_hrdata = rand();
		} else {
			req_d.wdata = top->d_hwdata;
			bus_response resp = {};
			if (req_d_vld) {
				resp = mem_callback_d(*this, memio, req_d);
			} else {
				resp.exokay = !memio.monitor_enabled;
			}
			if (resp.err) {
				top->d_hready = false;
				top->d_hresp = true;
			}
			if (req_d_vld && !req_d.write) {
				top->d_hrdata = resp.rdata;
			} else {
				top->d_hrdata = rand();
			}
			top->d_hexokay = resp.exokay;
		}
	}

	if (top->i_hresp && !top->i_hready) {
		// ERROR ph0 -> ph1
		top->i_hready = true;
	} else if (!req_i_vld) {
		// IDLE -> OKAY
		top->i_hready = true;
		top->i_hresp = false;
	} else {
		top->i_hresp = false;
		bool stall = rand() < args.bus_stall_p;
		top->i_hready = !stall;
		if (stall) {
			top->i_hrdata = rand();
		} else {
			req_i.wdata = top->i_hwdata;
			bus_response resp = {};
			if (req_i_vld) {
				resp = mem_callback_d(*this, memio, req_i);
			} else {
				resp.exokay = !memio.monitor_enabled;
			}
			if (resp.err) {
				top->i_hready = false;
				top->i_hresp = true;
			}
			if (req_i_vld && !req_i.write) {
				top->i_hrdata = resp.rdata;
			} else {
				top->i_hrdata = rand();
			}
			top->i_hexokay = resp.exokay;
		}
	}

	if (vcd) {
		vcd->dump(2ull * cycle + 1ull);
	}
	++cycle;
}

int main(int argc, char **argv) {
	tb_cli_args args;
	tb_parse_args(argc, argv, args);

	tb_jtag_state jtag(args);
	mem_io_state memio(args);
	tb_verilator_top tb(args, argc, argv);

	bool timed_out = false;
	for (int64_t cycle = 0; cycle < args.max_cycles || args.max_cycles == 0; ++cycle) {
		bool jtag_exit_cmd = jtag.step(tb);
		memio.step(tb);
		tb.step(args, memio);

		if (memio.exit_req) {
			fprintf(tb.logfile, "CPU requested halt. Exit code %d\n", memio.exit_code);
			fprintf(tb.logfile, "Ran for " I64_FMT " cycles\n", cycle + 1);
			break;
		}
		if (cycle + 1 == args.max_cycles) {
			fprintf(tb.logfile, "Max cycles reached\n");
			timed_out = true;
		}
		if (jtag_exit_cmd)
			break;
	}

	jtag.close();

	for (auto r : args.dump_ranges) {
		fprintf(tb.logfile, "Dumping memory from %08x to %08x:\n", r.first, r.second);
		for (int i = 0; i < r.second - r.first; ++i)
			fprintf(tb.logfile, "%02x%c", memio.mem[r.first + i - MEM_BASE], i % 16 == 15 ? '\n' : ' ');
		fprintf(tb.logfile, "\n");
	}

	if (args.sig_path != "") {
		FILE *sigfile = fopen(args.sig_path.c_str(), "wb");
		for (auto r : args.dump_ranges) {
			for (uint32_t i = 0; i < r.second - r.first; i += 4) {
				fprintf(
					sigfile,
					"%02x%02x%02x%02x\n",
					memio.mem[r.first + i + 3 - MEM_BASE],
					memio.mem[r.first + i + 2 - MEM_BASE],
					memio.mem[r.first + i + 1 - MEM_BASE],
					memio.mem[r.first + i + 0 - MEM_BASE]
				);
			}
		}
		fclose(sigfile);
	}

	tb.dump_coverage(args.coverage_path);

	if (args.propagate_return_code && timed_out) {
		return -1;
	} else if (args.propagate_return_code && memio.exit_req) {
		return memio.exit_code;
	} else {
		return 0;
	}
}

// Needed on MacOS, haven't looked into why
double sc_time_stamp() {
	return 0.0;
}
