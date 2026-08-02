#ifndef _HAZARD3_IRQ_H
#define _HAZARD3_IRQ_H

#include "hazard3_csr.h"
#include "stdint.h"
#include "stdbool.h"

// Should match processor configuration in testbench:
#define NUM_IRQS 32
#define MAX_PRIORITY 15

// Declarations for irq_dispatch.S
extern uintptr_t _external_irq_table[NUM_IRQS];
extern uint32_t _external_irq_entry_count;

#define h3irq_array_read(csr, index) (read_set_csr(csr, (index)) >> 16)

#define h3irq_array_write(csr, index, data) (write_csr(csr, (index) | ((uint32_t)(data) << 16)))
#define h3irq_array_set(csr, index, data) (set_csr(csr, (index) | ((uint32_t)(data) << 16)))
#define h3irq_array_clear(csr, index, data) (clear_csr(csr, (index) | ((uint32_t)(data) << 16)))

static inline void h3irq_enable(unsigned int irq, bool enable) {
	if (enable) {
		h3irq_array_set(hazard3_csr_meiea, irq >> 4, 1u << (irq & 0xfu));
	}
	else {
		h3irq_array_clear(hazard3_csr_meiea, irq >> 4, 1u << (irq & 0xfu));
	}
}

static inline bool h3irq_pending(unsigned int irq) {
	return h3irq_array_read(hazard3_csr_meipa, irq >> 4) & (1u << (irq & 0xfu));
}

static inline void h3irq_force_pending(unsigned int irq, bool force) {
	if (force) {
		h3irq_array_set(hazard3_csr_meifa, irq >> 4, 1u << (irq & 0xfu));
	}
	else {
		h3irq_array_clear(hazard3_csr_meifa, irq >> 4, 1u << (irq & 0xfu));
	}
}

static inline bool h3irq_is_forced(unsigned int irq) {
	return h3irq_array_read(hazard3_csr_meifa, irq >> 4) & (1u << (irq & 0xfu));
}

// -1 for no IRQ
static inline int h3irq_get_current_irq() {
	uint32_t meicontext = read_csr(hazard3_csr_meicontext);
	return meicontext & 0x8000u ? -1 : (meicontext >> 4) & 0x1ffu;
}

static inline void h3irq_set_priority(unsigned int irq, uint32_t priority) {
	// Don't want read-modify-write, but no instruction for atomically writing
	// a bitfield. So, first drop priority to minimum, then set to the target
	// value. It should be safe to drop an IRQ's priority below its current
	// even from within that IRQ (but it is never safe to boost an IRQ when
	// it may already be in an older stack frame)
	h3irq_array_clear(hazard3_csr_meipra, irq >> 2, 0xfu << (4 * (irq & 0x3)));
	h3irq_array_set(hazard3_csr_meipra, irq >> 2, (priority & 0xfu) << (4 * (irq & 0x3)));
}

static inline void h3irq_set_handler(unsigned int irq, void (*handler)(void)) {
	_external_irq_table[irq] = (uintptr_t)handler;
}

static inline void global_irq_enable(bool en) {
	// mstatus.mie
	if (en) {
		set_csr(mstatus, 0x8);
	}
	else {
		clear_csr(mstatus, 0x8);
	}
}

static inline void external_irq_enable(bool en) {
	// mie.meie
	if (en) {
		set_csr(mie, 0x800);
	}
	else {
		clear_csr(mie, 0x800);
	}
}

static inline void timer_irq_enable(bool en) {
	// mie.mtie
	if (en) {
		set_csr(mie, 0x080);
	}
	else {
		clear_csr(mie, 0x080);
	}
}

#endif
