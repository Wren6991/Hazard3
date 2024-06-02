#pragma once
#include <optional>
#include "rv_types.h"

class RVCSR {

	static const int PMP_REGIONS = 16;
	static const int IMPLEMENTED_PMP_REGIONS = 4;

	// Latched IRQ signals into core
	bool irq_t;
	bool irq_s;
	bool irq_e;

	// Current core privilege level (M/S/U)
	uint priv;

	ux_t mcycle;
	ux_t mcycleh;
	ux_t minstret;
	ux_t minstreth;
	ux_t mcountinhibit;
	ux_t mstatus;
	ux_t mie;
	ux_t mip;
	ux_t mtvec;
	ux_t mscratch;
	ux_t mepc;
	ux_t mcause;
	ux_t hazard3_msleep;

	ux_t pmpaddr[PMP_REGIONS];
	ux_t pmpcfg[PMP_REGIONS / 4];

	std::optional<ux_t> pending_write_addr;
	ux_t pending_write_data;

	ux_t get_effective_xip();

	// Internal interface for updating trap state. Returns trap target pc.
	ux_t trap_enter(uint xcause, ux_t xepc);

	ux_t pmpcfg_a(int i) {
		uint8_t cfg_bits = pmpcfg[i / 4] >> 8 * (i % 4);
		return (cfg_bits >> 3) & 0x3u;
	}

	ux_t pmpcfg_xwr(int i) {
		uint8_t cfg_bits = pmpcfg[i / 4] >> 8 * (i % 4);
		return cfg_bits & 0x7u;
	}

	ux_t pmpcfg_l(int i) {
		uint8_t cfg_bits = pmpcfg[i / 4] >> 8 * (i % 4);
		return (cfg_bits >> 7) & 0x1u;
	}

public:

	enum {
		WRITE = 0,
		WRITE_SET = 1,
		WRITE_CLEAR = 2
	};

	RVCSR() {
		irq_t = false;
		irq_s = false;
		irq_e = false;
		priv = 3;
		mcycle = 0;
		mcycleh = 0;
		minstret = 0;
		minstreth = 0;
		mcountinhibit = 0x5;
		mstatus = 0;
		mie = 0;
		mip = 0;
		mtvec = 0;
		mscratch = 0;
		mepc = 0;
		mcause = 0;
		hazard3_msleep = 0;
		pending_write_addr = {};
		for (int i = 0; i < PMP_REGIONS; ++i) {
			pmpaddr[i] = 0;
		}
		for (int i = 0; i < PMP_REGIONS / 4; ++i) {
			pmpcfg[i] = 0;
		}
	}

	void step();

	// Returns None on permission/decode fail
	std::optional<ux_t> read(uint16_t addr, bool side_effect=true);

	// Returns false on permission/decode fail
	bool write(uint16_t addr, ux_t data, uint op=WRITE);

	// Determine target privilege level of an exception, update trap state
	// (including change of privilege level), return trap target PC
	ux_t trap_enter_exception(uint xcause, ux_t xepc);

	// If there is currently a pending IRQ that must be entered, then
	// determine its target privilege level, update trap state, and return
	// trap target PC. Otherwise return None.
	std::optional<ux_t> trap_check_enter_irq(ux_t xepc);

	// Update trap state, return mepc:
	ux_t trap_mret();

	uint get_true_priv() {
		return priv;
	}

	uint get_effective_priv();

	bool get_mstatus_tw() {
		return mstatus & 0x00200000u;
	}

	void set_irq_t(bool irq) {
		irq_t = irq;
	}

	void set_irq_s(bool irq) {
		irq_s = irq;
	}

	void set_irq_e(bool irq) {
		irq_e = irq;
	}

	ux_t get_xcause() {
		return mcause;
	}

	// Return region, or -1 for no match
	int get_pmp_match(ux_t addr);

	uint get_pmp_xwr(ux_t addr);
};
