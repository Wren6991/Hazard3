#pragma once

#include <array>
#include <optional>

#include "rv_csr.h"
#include "rv_types.h"
#include "rv_mem.h"

struct RVCore {
	std::array<ux_t, 32> regs;
	ux_t pc;
	RVCSR csr;
	bool load_reserved;
	MemBase32 &mem;
	bool stalled_on_wfi;

	// A single flat RAM is handled as a special case, in addition to whatever
	// is in `mem`, because this avoids virtual calls for the majority of
	// memory accesses. This RAM takes precedence over whatever is mapped at
	// the same address in `mem`. (Note the size of this RAM may be zero, and
	// RAM can also be added to the `mem` object.)
	ux_t *ram;
	ux_t ram_base;
	ux_t ram_top;

	RVCore(MemBase32 &_mem, ux_t reset_vector, ux_t ram_base_, ux_t ram_size_) : mem(_mem) {
		std::fill(std::begin(regs), std::end(regs), 0);
		pc = reset_vector;
		load_reserved = false;
		stalled_on_wfi = false;
		ram_base = ram_base_;
		ram_top = ram_base_ + ram_size_;
		ram = new ux_t[ram_size_ / sizeof(ux_t)];
		assert(ram);
		assert(!(ram_base_ & 0x3));
		assert(!(ram_size_ & 0x3));
		assert(ram_base_ + ram_size_ >= ram_base_);
		for (ux_t i = 0; i < ram_size_ / sizeof(ux_t); ++i)
			ram[i] = 0;
	}

	~RVCore() {
		delete ram;
	}

	enum {
		OPC_LOAD     = 0b00'000,
		OPC_MISC_MEM = 0b00'011,
		OPC_OP_IMM   = 0b00'100,
		OPC_AUIPC    = 0b00'101,
		OPC_STORE    = 0b01'000,
		OPC_AMO      = 0b01'011,
		OPC_OP       = 0b01'100,
		OPC_LUI      = 0b01'101,
		OPC_BRANCH   = 0b11'000,
		OPC_JALR     = 0b11'001,
		OPC_JAL      = 0b11'011,
		OPC_SYSTEM   = 0b11'100,
		OPC_CUSTOM0  = 0b00'010
	};

	// Functions to read/write memory from this hart's point of view
	std::optional<uint8_t> r8(ux_t addr, uint permissions=0x1u) {
		if (!(csr.get_pmp_xwr(addr) & permissions)) {
			return {};
		} else if (addr >= ram_base && addr < ram_top) {
			return ram[(addr - ram_base) >> 2] >> 8 * (addr & 0x3) & 0xffu;
		} else {
			return mem.r8(addr);
		}
	}

	bool w8(ux_t addr, uint8_t data) {
		if (!(csr.get_pmp_xwr(addr) & 0x2u)) {
			return false;
		} else if (addr >= ram_base && addr < ram_top) {
			ram[(addr - ram_base) >> 2] &= ~(0xffu << 8 * (addr & 0x3));
			ram[(addr - ram_base) >> 2] |= (uint32_t)data << 8 * (addr & 0x3);
			return true;
		} else {
			return mem.w8(addr, data);
		}
	}

	std::optional<uint16_t> r16(ux_t addr, uint permissions=0x1u) {
		if (!(csr.get_pmp_xwr(addr) & permissions)) {
			return {};
		} else if (addr >= ram_base && addr < ram_top) {
			return ram[(addr - ram_base) >> 2] >> 8 * (addr & 0x2) & 0xffffu;
		} else {
			return mem.r16(addr);
		}
	}

	bool w16(ux_t addr, uint16_t data) {
		if (!(csr.get_pmp_xwr(addr) & 0x2u)) {
			return false;
		} else if (addr >= ram_base && addr < ram_top) {
			ram[(addr - ram_base) >> 2] &= ~(0xffffu << 8 * (addr & 0x2));
			ram[(addr - ram_base) >> 2] |= (uint32_t)data << 8 * (addr & 0x2);
			return true;
		} else {
			return mem.w16(addr, data);
		}
	}

	std::optional<uint32_t> r32(ux_t addr, uint permissions=0x1u) {
		if (!(csr.get_pmp_xwr(addr) & permissions)) {
			return {};
		} else if (addr >= ram_base && addr < ram_top) {
			return ram[(addr - ram_base) >> 2];
		} else {
			return mem.r32(addr);
		}
	}

	bool w32(ux_t addr, uint32_t data) {
		if (!(csr.get_pmp_xwr(addr) & 0x2u)) {
			return false;
		} else if (addr >= ram_base && addr < ram_top) {
			ram[(addr - ram_base) >> 2] = data;
			return true;
		} else {
			return mem.w32(addr, data);
		}
	}

	// Fetch and execute one instruction from memory.
	void step(bool trace=false);
};
