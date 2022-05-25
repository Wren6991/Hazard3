#ifndef _PMP_H
#define _PMP_H

#include "hazard3_csr.h"

#define PMPCFG_L_LSB 7
#define PMPCFG_L_BITS 0x80
#define PMPCFG_A_LSB 3
#define PMPCFG_A_BITS 0x18
#define PMPCFG_R_BITS 0x04
#define PMPCFG_W_BITS 0x02
#define PMPCFG_X_BITS 0x01

#define PMPCFG_A_OFF 0x0
#define PMPCFG_A_TOR 0x1
#define PMPCFG_A_NA4 0x2
#define PMPCFG_A_NAPOT 0x3

// Note these aren't declared as inline -- presumably ok as our tests are single C files

void write_pmpaddr(unsigned int region, uintptr_t addr) {
	switch (region) {
	case 0:
		write_csr(pmpaddr0, addr);
		break;
	case 1:
		write_csr(pmpaddr1, addr);
		break;
	case 2:
		write_csr(pmpaddr2, addr);
		break;
	case 3:
		write_csr(pmpaddr3, addr);
		break;
	case 4:
		write_csr(pmpaddr4, addr);
		break;
	case 5:
		write_csr(pmpaddr5, addr);
		break;
	case 6:
		write_csr(pmpaddr6, addr);
		break;
	case 7:
		write_csr(pmpaddr7, addr);
		break;
	case 8:
		write_csr(pmpaddr8, addr);
		break;
	case 9:
		write_csr(pmpaddr9, addr);
		break;
	case 10:
		write_csr(pmpaddr10, addr);
		break;
	case 11:
		write_csr(pmpaddr11, addr);
		break;
	case 12:
		write_csr(pmpaddr12, addr);
		break;
	case 13:
		write_csr(pmpaddr13, addr);
		break;
	case 14:
		write_csr(pmpaddr14, addr);
		break;
	case 15:
		write_csr(pmpaddr15, addr);
		break;
	}
}

uintptr_t read_pmpaddr(unsigned int region) {
	switch (region) {
	case 0:
		return read_csr(pmpaddr0);
	case 1:
		return read_csr(pmpaddr1);
	case 2:
		return read_csr(pmpaddr2);
	case 3:
		return read_csr(pmpaddr3);
	case 4:
		return read_csr(pmpaddr4);
	case 5:
		return read_csr(pmpaddr5);
	case 6:
		return read_csr(pmpaddr6);
	case 7:
		return read_csr(pmpaddr7);
	case 8:
		return read_csr(pmpaddr8);
	case 9:
		return read_csr(pmpaddr9);
	case 10:
		return read_csr(pmpaddr10);
	case 11:
		return read_csr(pmpaddr11);
	case 12:
		return read_csr(pmpaddr12);
	case 13:
		return read_csr(pmpaddr13);
	case 14:
		return read_csr(pmpaddr14);
	case 15:
		return read_csr(pmpaddr15);
	default:
		return 0;
	}
}

void write_pmpcfg(unsigned int region, uint8_t cfg) {
	int regnum = region / 4;
	int lsb = (region % 4) * 8;
	uint32_t set_mask = (uint32_t)cfg << lsb;
	uint32_t clr_mask = ~(uint32_t)cfg & 0xffu << lsb;
	switch (regnum) {
	case 0:
		clear_csr(pmpcfg0, clr_mask);
		set_csr(pmpcfg0, set_mask);
		break;
	case 1:
		clear_csr(pmpcfg1, clr_mask);
		set_csr(pmpcfg1, set_mask);
		break;
	case 2:
		clear_csr(pmpcfg2, clr_mask);
		set_csr(pmpcfg2, set_mask);
		break;
	case 3:
		clear_csr(pmpcfg3, clr_mask);
		set_csr(pmpcfg3, set_mask);
		break;
	}
}

uint8_t read_pmpcfg(unsigned int region) {
	uint32_t cfgreg = 0;
	switch (region / 4) {
	case 0:
		cfgreg = read_csr(pmpcfg0);
		break;
	case 1:
		cfgreg = read_csr(pmpcfg1);
		break;
	case 2:
		cfgreg = read_csr(pmpcfg2);
		break;
	case 3:
		cfgreg = read_csr(pmpcfg3);
		break;
	}
	return (cfgreg >> (region % 4 * 8)) & 0xffu;
}

#endif