#include "rv_csr.h"
#include "encoding/rv_csr.h"

#include <cassert>

// Inclusive msb:lsb style, like Verilog (and like the ISA manual)
#define BITS_UPTO(msb) (~((-1u << (msb)) << 1))
#define BITRANGE(msb, lsb) (BITS_UPTO((msb) - (lsb)) << (lsb))
#define GETBITS(x, msb, lsb) (((x) & BITRANGE(msb, lsb)) >> (lsb))
#define GETBIT(x, bit) (((x) >> (bit)) & 1u)


ux_t RVCSR::get_effective_xip() {
	return mip |
		(irq_s ? MIP_MSIP : 0) |
		(irq_t ? MIP_MTIP : 0) |
		(irq_e ? MIP_MEIP : 0);
}

void RVCSR::step() {
	uint64_t mcycle_64 = ((uint64_t)mcycleh << 32) | mcycle;
	uint64_t minstret_64 = ((uint64_t)minstreth << 32) | minstret;
	if (!(mcountinhibit & 0x1u)) {
		++mcycle_64;
	}
	if (!(mcountinhibit & 0x4u)) {
		++minstret_64;
	}
	if (!(pending_write_addr && *pending_write_addr == CSR_MCYCLEH)) {
		mcycleh = mcycle_64 >> 32;
	}
	if (!(pending_write_addr && *pending_write_addr == CSR_MCYCLE)) {
		mcycle = mcycle_64 & 0xffffffffu;
	}
	if (!(pending_write_addr && *pending_write_addr == CSR_MINSTRETH)) {
		minstreth = minstret_64 >> 32;
	}
	if (!(pending_write_addr && *pending_write_addr == CSR_MINSTRET)) {
		minstret = minstret_64 & 0xffffffffu;
	}
	if (pending_write_addr) {
		switch (*pending_write_addr) {
			case CSR_MSTATUS:       mstatus       = pending_write_data;               break;
			case CSR_MIE:           mie           = pending_write_data;               break;
			case CSR_MTVEC:         mtvec         = pending_write_data & 0xfffffffdu; break;
			case CSR_MSCRATCH:      mscratch      = pending_write_data;               break;
			case CSR_MEPC:          mepc          = pending_write_data & 0xfffffffeu; break;
			case CSR_MCAUSE:        mcause        = pending_write_data & 0x8000000fu; break;

			case CSR_MCYCLE:        mcycle        = pending_write_data;               break;
			case CSR_MCYCLEH:       mcycleh       = pending_write_data;               break;
			case CSR_MINSTRET:      minstret      = pending_write_data;               break;
			case CSR_MINSTRETH:     minstreth     = pending_write_data;               break;
			case CSR_MCOUNTINHIBIT: mcountinhibit = pending_write_data & 0x7u;        break;
			default:                                                                  break;
		}
		pending_write_addr = {};
	}
}


// Returns None on permission/decode fail
std::optional<ux_t> RVCSR::read(uint16_t addr, bool side_effect) {
	if (addr >= 1u << 12 || GETBITS(addr, 9, 8) > priv)
		return {};

	switch (addr) {
		case CSR_MISA:          return 0x40901105;  // RV32IMACX + U
		case CSR_MHARTID:       return 0;
		case CSR_MARCHID:       return 0x1b;        // Hazard3
		case CSR_MIMPID:        return 0x12345678u; // Match testbench value
		case CSR_MVENDORID:     return 0xdeadbeefu; // Match testbench value
		case CSR_MCONFIGPTR:    return 0x9abcdef0u; // Match testbench value

		case CSR_MSTATUS:       return mstatus;
		case CSR_MIE:           return mie;
		case CSR_MIP:           return get_effective_xip();
		case CSR_MTVEC:         return mtvec;
		case CSR_MSCRATCH:      return mscratch;
		case CSR_MEPC:          return mepc;
		case CSR_MCAUSE:        return mcause;
		case CSR_MTVAL:         return 0;

		case CSR_MCOUNTINHIBIT: return mcountinhibit;
		case CSR_MCYCLE:        return mcycle;
		case CSR_MCYCLEH:       return mcycleh;
		case CSR_MINSTRET:      return minstret;
		case CSR_MINSTRETH:     return minstreth;

		default:                return {};
	}
}

// Returns false on permission/decode fail
bool RVCSR::write(uint16_t addr, ux_t data, uint op) {
	if (addr >= 1u << 12 || GETBITS(addr, 9, 8) > priv)
		return false;
	if (op == WRITE_CLEAR || op == WRITE_SET) {
		std::optional<ux_t> rdata = read(addr, false);
		if (!rdata)
			return false;
		if (op == WRITE_CLEAR)
			data = *rdata & ~data;
		else
			data = *rdata | data;
	}
	pending_write_addr = addr;
	pending_write_data = data;
	// Actual write is applied at end of step() -- ordering is important
	// e.g. for mcycle updates. However we validate address for
	// writability immediately.
	switch (addr) {
		case CSR_MISA:          break;
		case CSR_MHARTID:       break;
		case CSR_MARCHID:       break;
		case CSR_MIMPID:        break;

		case CSR_MSTATUS:       break;
		case CSR_MIE:           break;
		case CSR_MIP:           break;
		case CSR_MTVEC:         break;
		case CSR_MSCRATCH:      break;
		case CSR_MEPC:          break;
		case CSR_MCAUSE:        break;
		case CSR_MTVAL:         break;

		case CSR_MCYCLE:        break;
		case CSR_MCYCLEH:       break;
		case CSR_MINSTRET:      break;
		case CSR_MINSTRETH:     break;
		case CSR_MCOUNTINHIBIT: break;
		default:                return false;
	}
	return true;
}

ux_t RVCSR::trap_enter_exception(uint xcause, ux_t xepc) {
	assert(xcause < 32);
	assert(!pending_write_addr);
	return trap_enter(xcause, xepc);
}

std::optional<ux_t> RVCSR::trap_check_enter_irq(ux_t xepc) {
	ux_t m_targeted_irqs = get_effective_xip() & mie;
	bool take_m_irq = m_targeted_irqs && ((mstatus & MSTATUS_MIE) || priv < PRV_M);
	if (take_m_irq) {
		ux_t cause = (1u << 31) | __builtin_ctz(m_targeted_irqs);
		return trap_enter(cause, xepc);
	} else {
		return std::nullopt;
	}
}

// Update trap state (including change of privilege level), return trap target PC
ux_t RVCSR::trap_enter(uint xcause, ux_t xepc) {
	mstatus = (mstatus & ~MSTATUS_MPP) | (priv << 11);
	priv = PRV_M;

	if (mstatus & MSTATUS_MIE)
		mstatus |= MSTATUS_MPIE;
	mstatus &= ~MSTATUS_MIE;

	mcause = xcause;
	mepc = xepc;
	if ((mtvec & 0x1) && (xcause & (1u << 31))) {
		return (mtvec & -2) + 4 * (xcause & ~(1u << 31));
	} else {
		return mtvec & -2;
	}
}

// Update trap state, return mepc:
ux_t RVCSR::trap_mret() {
	priv = GETBITS(mstatus, 12, 11);
	mstatus &= ~MSTATUS_MPP;
	if (priv != PRV_M)
		mstatus &= ~MSTATUS_MPRV;

	if (mstatus & MSTATUS_MPIE)
		mstatus |= MSTATUS_MIE;
	mstatus &= ~MSTATUS_MPIE;

	return mepc;
}
