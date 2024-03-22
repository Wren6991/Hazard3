#pragma once

#include "rv_types.h"
#include <optional>
#include <tuple>
#include <cassert>
#include <vector>
#include <cstdio>

struct MemBase32 {
	virtual std::optional<uint8_t> r8(__attribute__((unused)) ux_t addr) {return std::nullopt;}
	virtual bool w8(__attribute__((unused)) ux_t addr, __attribute__((unused)) uint8_t data) {return false;}
	virtual std::optional<uint16_t> r16(__attribute__((unused)) ux_t addr) {return std::nullopt;}
	virtual bool w16(__attribute__((unused)) ux_t addr, __attribute__((unused)) uint16_t data) {return false;}
	virtual std::optional<uint32_t> r32(__attribute__((unused)) ux_t addr) {return std::nullopt;}
	virtual bool w32(__attribute__((unused)) ux_t addr, __attribute__((unused)) uint32_t data) {return false;}
};

struct FlatMem32: MemBase32 {
	uint32_t size;
	uint32_t *mem;

	FlatMem32(uint32_t size_) {
		assert(size_ % sizeof(uint32_t) == 0);
		size = size_;
		mem = new uint32_t[size >> 2];
		for (uint64_t i = 0; i < size >> 2; ++i)
			mem[i] = 0;
	}

	~FlatMem32() {
		delete mem;
	}

	virtual std::optional<uint8_t> r8(ux_t addr) {
		assert(addr < size);
		return mem[addr >> 2] >> 8 * (addr & 0x3) & 0xffu;
	}

	virtual bool w8(ux_t addr, uint8_t data) {
		assert(addr < size);
		mem[addr >> 2] &= ~(0xffu << 8 * (addr & 0x3));
		mem[addr >> 2] |= (uint32_t)data << 8 * (addr & 0x3);
		return true;
	}

	virtual std::optional<uint16_t> r16(ux_t addr) {
		assert(addr < size && addr + 1 < size); // careful of ~0u
		assert(addr % 2 == 0);
		return mem[addr >> 2] >> 8 * (addr & 0x2) & 0xffffu;
	}

	virtual bool w16(ux_t addr, uint16_t data) {
		assert(addr < size && addr + 1 < size);
		assert(addr % 2 == 0);
		mem[addr >> 2] &= ~(0xffffu << 8 * (addr & 0x2));
		mem[addr >> 2] |= (uint32_t)data << 8 * (addr & 0x2);
		return true;
	}

	virtual std::optional<uint32_t> r32(ux_t addr) {
		assert(addr < size && addr + 3 < size);
		assert(addr % 4 == 0);
		return mem[addr >> 2];
	}

	virtual bool w32(ux_t addr, uint32_t data) {
		assert(addr < size && addr + 3 < size);
		assert(addr % 4 == 0);
		mem[addr >> 2] = data;
		return true;
	}
};

struct TBExitException {
	ux_t exitcode;
	TBExitException(ux_t code): exitcode(code) {}
};

struct TBMemIO: MemBase32 {

	enum {
		IO_PRINT_CHAR  = 0x000,
		IO_PRINT_U32   = 0x004,
		IO_EXIT        = 0x008,
		IO_SET_SOFTIRQ = 0x010,
		IO_CLR_SOFTIRQ = 0x014,
		IO_GLOBMON_EN  = 0x018,
		IO_SET_IRQ     = 0x020,
		IO_CLR_IRQ     = 0x030,
		IO_MTIME       = 0x100,
		IO_MTIMEH      = 0x104,
		IO_MTIMECMP    = 0x108,
		IO_MTIMECMPH   = 0x10c,
	};

	uint64_t mtime;
	uint64_t mtimecmp;
	bool softirq;
	bool trace;

	TBMemIO(bool trace_) {
		mtime = 0;
		mtimecmp = 0; // -1 would be better, but match tb and tests
		softirq = false;
		trace = trace_;
	}

	virtual bool w32(ux_t addr, uint32_t data) {
		switch (addr) {
		case IO_PRINT_CHAR:
			if (trace)
				printf("IO_PRINT_CHAR: %c\n", (char)data);
			else
				printf("%c", (char)data);
			return true;
		case IO_PRINT_U32:
			if (trace)
				printf("IO_PRINT_U32: %08x\n", data);
			else
				printf("%08x\n", data);
			return true;
		case IO_EXIT:
			throw TBExitException(data);
			return true;
		case IO_SET_SOFTIRQ:
			softirq = softirq || (data & 0x1);
			return true;
		case IO_CLR_SOFTIRQ:
			softirq = softirq && !(data & 0x1);
			return true;
		case IO_MTIME:
			mtime = (mtime & 0xffffffff00000000ull) | data;
			return true;
		case IO_MTIMEH:
			mtime = (mtime & 0x00000000ffffffffull) | ((uint64_t)data << 32);
			return true;
		case IO_MTIMECMP:
			mtimecmp = (mtimecmp & 0xffffffff00000000ull) | data;
			return true;
		case IO_MTIMECMPH:
			mtimecmp = (mtimecmp & 0x00000000ffffffffull) | ((uint64_t)data << 32);
			return true;
		default:
			return false;
		}
	}

	virtual std::optional<uint32_t> r32(ux_t addr) {
		switch(addr) {
		case IO_MTIME:
			return mtime & 0xffffffffull;
		case IO_MTIMEH:
			return mtime >> 32;
		case IO_MTIMECMP:
			return mtimecmp & 0xffffffffull;
		case IO_MTIMECMPH:
			return mtimecmp >> 32;
		case IO_SET_SOFTIRQ:
		case IO_CLR_SOFTIRQ:
			return softirq;
		default:
			return {};
		}
	}

	void step() {
		mtime++;
	}

	bool timer_irq_pending() {
		return mtime >= mtimecmp;
	}

	bool soft_irq_pending() {
		return softirq;
	}

};

struct MemMap32: MemBase32 {
	std::vector<std::tuple<uint32_t, uint32_t, MemBase32*> > memmap;

	void add(uint32_t base, uint32_t size, MemBase32 *mem) {
		memmap.push_back(std::make_tuple(base, size, mem));
	}

	std::tuple <uint32_t, MemBase32*> map_addr(uint32_t addr) {
		for (auto&& [base, size, mem] : memmap) {
			if (addr >= base && addr < base + size)
				return std::make_tuple(addr - base, mem);
		}
		return std::make_tuple(addr, nullptr);
	}

	virtual std::optional<uint8_t> r8(ux_t addr) {
		auto [offset, mem] = map_addr(addr);
		if (mem)
			return mem->r8(offset);
		else
			return std::nullopt;
	}

	virtual bool w8(ux_t addr, uint8_t data) {
		auto [offset, mem] = map_addr(addr);
		if (mem)
			return mem->w8(offset, data);
		else
			return false;
	}

	virtual std::optional<uint16_t> r16(ux_t addr) {
		auto [offset, mem] = map_addr(addr);
		if (mem)
			return mem->r16(offset);
		else
			return std::nullopt;
	}

	virtual bool w16(ux_t addr, uint16_t data) {
		auto [offset, mem] = map_addr(addr);
		if (mem)
			return mem->w16(offset, data);
		else
			return false;
	}

	virtual std::optional<uint32_t> r32(ux_t addr) {
		auto [offset, mem] = map_addr(addr);
		if (mem)
			return mem->r32(offset);
		else
			return std::nullopt;
	}

	virtual bool w32(ux_t addr, uint32_t data) {
		auto [offset, mem] = map_addr(addr);
		if (mem)
			return mem->w32(offset, data);
		else
			return false;
	}
};
