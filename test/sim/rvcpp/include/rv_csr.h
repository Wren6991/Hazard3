#pragma once
#include <optional>
#include "rv_types.h"

class RVCSR {

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

	std::optional<ux_t> pending_write_addr;
	ux_t pending_write_data;

	ux_t get_effective_xip();

	// Internal interface for updating trap state. Returns trap target pc.
	ux_t trap_enter(uint xcause, ux_t xepc);

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
		pending_write_addr = {};
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

};
