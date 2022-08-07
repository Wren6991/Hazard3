#ifndef _HAZARD3_IRQ_H
#define _HAZARD3_IRQ_H

#include "hazard3_csr.h"
#include "stdint.h"
#include "stdbool.h"

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

static inline bool h3irq_force_pending(unsigned int irq) {
	h3irq_array_set(hazard3_csr_meifa, irq >> 4, 1u << (irq & 0xfu));
}

#endif
