#pragma once
#include <optional>
#include "rv_types.h"

class RVCSR {
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

public:

	enum {
		WRITE = 0,
		WRITE_SET = 1,
		WRITE_CLEAR = 2
	};

	RVCSR() {
		priv = 3;
		mcycle = 0;
		mcycleh = 0;
		minstret = 0;
		minstreth = 0;
		mcountinhibit = 0;
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

	// Update trap state (including change of privilege level), return trap target PC
	ux_t trap_enter(uint xcause, ux_t xepc);

	// Update trap state, return mepc:
	ux_t trap_mret();

	uint getpriv() {
		return priv;
	}
};
