#include "tb.h"

#include <fstream>
#include <iostream>

mem_io_state::mem_io_state(const tb_cli_args &args) {
	mtime = 0;
	mtimecmp[0] = 0;
	mtimecmp[1] = 0;
	exit_req = false;
	exit_code = 0;
	monitor_enabled = false;
	soft_irq_state = 0;
	irq_state = 0;
	for (int i = 0; i < N_RESERVATIONS; ++i) {
		reservation_valid[i] = false;
		reservation_addr[i] = 0;
	}
	poison_addr = -4u;
	mem = new uint8_t[MEM_SIZE];
	for (size_t i = 0; i < MEM_SIZE; ++i)
		mem[i] = 0;

	if (args.load_bin) {
		std::ifstream fd(args.bin_path, std::ios::binary | std::ios::ate);
		if (!fd){
			std::cerr << "Failed to open \"" << args.bin_path << "\"\n";
			exit(-1);
		}
		std::streamsize bin_size = fd.tellg();
		if (bin_size > MEM_SIZE) {
			std::cerr << "Binary file (" << bin_size << " bytes) is larger than memory (" << MEM_SIZE << " bytes)\n";
			exit(-1);
		}
		fd.seekg(0, std::ios::beg);
		fd.read((char*)mem, bin_size);
	}
}

bus_response tb_mem_access(tb_top &tb, mem_io_state &memio, bus_request req) {
	bus_response resp;

	// Global monitor. When monitor is not enabled, HEXOKAY is tied high
	if (memio.monitor_enabled) {
		if (req.excl) {
			// Always set reservation on read. Always clear reservation on
			// write. On successful write, clear others' matching reservations.
			if (req.write) {
				resp.exokay = memio.reservation_valid[req.reservation_id] &&
					memio.reservation_addr[req.reservation_id] == (req.addr & RESERVATION_ADDR_MASK);
				memio.reservation_valid[req.reservation_id] = false;
				if (resp.exokay) {
					for (int i = 0; i < N_RESERVATIONS; ++i) {
						if (i == req.reservation_id)
							continue;
						if (memio.reservation_addr[i] == (req.addr & RESERVATION_ADDR_MASK))
							memio.reservation_valid[i] = false;
					}
				}
			} else {
				resp.exokay = true;
				memio.reservation_valid[req.reservation_id] = true;
				memio.reservation_addr[req.reservation_id] = req.addr & RESERVATION_ADDR_MASK;
			}
		} else {
			resp.exokay = false;
			// Non-exclusive write still clears others' reservations
			if (req.write) {
				for (int i = 0; i < N_RESERVATIONS; ++i) {
					if (i == req.reservation_id)
						continue;
					if (memio.reservation_addr[i] == (req.addr & RESERVATION_ADDR_MASK))
						memio.reservation_valid[i] = false;
				}
			}
		}
	}


	if (req.write) {
		if (memio.monitor_enabled && req.excl && !resp.exokay) {
			// Failed exclusive write; do nothing
		} else if ((req.addr & -4u) == memio.poison_addr) {
			resp.err = true;
		} else if (req.addr >= MEM_BASE && req.addr <= MEM_BASE + MEM_SIZE - (1u << (int)req.size)) {
			unsigned int n_bytes = 1u << (int)req.size;
			// Note we are relying on hazard3's byte lane replication
			for (unsigned int i = 0; i < n_bytes; ++i) {
				memio.mem[req.addr + i - MEM_BASE] = req.wdata >> (8 * i) & 0xffu;
			}
		} else if (req.addr == IO_BASE + IO_PRINT_CHAR) {
			fprintf(tb.logfile, "%c", (char)(req.wdata & 0xff));
		} else if (req.addr == IO_BASE + IO_PRINT_U32) {
			fprintf(tb.logfile, "%08x\n", req.wdata);
		} else if (req.addr == IO_BASE + IO_EXIT) {
			if (!memio.exit_req) {
				memio.exit_req = true;
				memio.exit_code = req.wdata;
			}
		} else if (req.addr == IO_BASE + IO_SET_SOFTIRQ) {
			memio.soft_irq_state |= req.wdata;
			tb.set_soft_irq(memio.soft_irq_state);
		} else if (req.addr == IO_BASE + IO_CLR_SOFTIRQ) {
			memio.soft_irq_state &= ~req.wdata;
			tb.set_soft_irq(memio.soft_irq_state);
		} else if (req.addr == IO_BASE + IO_GLOBMON_EN) {
			memio.monitor_enabled = req.wdata;
		} else if (req.addr == IO_BASE + IO_POISON_ADDR) {
			memio.poison_addr = req.wdata & -4u;
		} else if (req.addr == IO_BASE + IO_SET_IRQ) {
			memio.irq_state |= req.wdata;
			tb.set_irq(memio.irq_state);
		} else if (req.addr == IO_BASE + IO_CLR_IRQ) {
			memio.irq_state &= ~req.wdata;
			tb.set_irq(memio.irq_state);
		} else if (req.addr == IO_BASE + IO_MTIME) {
			memio.mtime = (memio.mtime & 0xffffffff00000000u) | req.wdata;
		} else if (req.addr == IO_BASE + IO_MTIMEH) {
			memio.mtime = (memio.mtime & 0x00000000ffffffffu) | ((uint64_t)req.wdata << 32);
		} else if (req.addr == IO_BASE + IO_MTIMECMP0) {
			memio.mtimecmp[0] = (memio.mtimecmp[0] & 0xffffffff00000000u) | req.wdata;
		} else if (req.addr == IO_BASE + IO_MTIMECMP0H) {
			memio.mtimecmp[0] = (memio.mtimecmp[0] & 0x00000000ffffffffu) | ((uint64_t)req.wdata << 32);
		} else if (req.addr == IO_BASE + IO_MTIMECMP1) {
			memio.mtimecmp[1] = (memio.mtimecmp[1] & 0xffffffff00000000u) | req.wdata;
		} else if (req.addr == IO_BASE + IO_MTIMECMP1H) {
			memio.mtimecmp[1] = (memio.mtimecmp[1] & 0x00000000ffffffffu) | ((uint64_t)req.wdata << 32);
		} else {
			resp.err = true;
		}
	} else {
		if ((req.addr & -4u) == memio.poison_addr) {
			resp.err = true;
		} else if (req.addr >= MEM_BASE && req.addr <= MEM_BASE + MEM_SIZE - (1u << (int)req.size)) {
			req.addr &= ~0x3u;
			req.addr -= MEM_BASE;
			resp.rdata =
				(uint32_t)memio.mem[req.addr] |
				memio.mem[req.addr + 1] << 8 |
				memio.mem[req.addr + 2] << 16 |
				memio.mem[req.addr + 3] << 24;
		} else if (req.addr == IO_BASE + IO_PRINT_CHAR) {
			uint8_t c;
			ssize_t n;
			do {
				n = read(STDIN_FILENO, &c, 1);
			} while (n < 0 && errno == EINTR);
			resp.rdata = n == 1 ? c : 0xffffffffu;
		} else if (req.addr == IO_BASE + IO_SET_SOFTIRQ || req.addr == IO_BASE + IO_CLR_SOFTIRQ) {
			resp.rdata = memio.soft_irq_state;
		} else if (req.addr == IO_BASE + IO_SET_IRQ || req.addr == IO_BASE + IO_CLR_IRQ) {
			resp.rdata = memio.irq_state;
		} else if (req.addr == IO_BASE + IO_MTIME) {
			resp.rdata = memio.mtime;
		} else if (req.addr == IO_BASE + IO_MTIMEH) {
			resp.rdata = memio.mtime >> 32;
		} else if (req.addr == IO_BASE + IO_MTIMECMP0) {
			resp.rdata = memio.mtimecmp[0];
		} else if (req.addr == IO_BASE + IO_MTIMECMP0H) {
			resp.rdata = memio.mtimecmp[0] >> 32;
		} else if (req.addr == IO_BASE + IO_MTIMECMP1) {
			resp.rdata = memio.mtimecmp[1];
		} else if (req.addr == IO_BASE + IO_MTIMECMP1H) {
			resp.rdata = memio.mtimecmp[1] >> 32;
		} else {
			resp.err = true;
		}
	}
	if (resp.err) {
		resp.exokay = false;
	}
	return resp;
}

void mem_io_state::step(tb_top &tb) {
	// Default update logic for mtime, mtimecmp
	++mtime;
	tb.set_timer_irq((uint8_t)((mtime >= mtimecmp[0]) | (mtime >= mtimecmp[1]) << 1));
}
