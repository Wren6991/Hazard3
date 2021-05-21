#ifndef _MEM_H
#define _MEM_H

#include "rv_types.h"

struct MemBase32 {
	virtual uint8_t r8(ux_t addr) {return 0;}
	virtual void w8(ux_t addr, uint8_t data) {}
	virtual uint16_t r16(ux_t addr) {return 0;}
	virtual void w16(ux_t addr, uint16_t data) {}
	virtual uint32_t r32(ux_t addr) {return 0;}
	virtual void w32(ux_t addr, uint32_t data) {}
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

	virtual uint8_t r8(ux_t addr) {
		assert(addr < size);
		return mem[addr >> 2] >> 8 * (addr & 0x3) & 0xffu;
	}

	virtual void w8(ux_t addr, uint8_t data) {
		assert(addr < size);
		mem[addr >> 2] &= ~(0xffu << 8 * (addr & 0x3));
		mem[addr >> 2] |= (uint32_t)data << 8 * (addr & 0x3);
	}

	virtual uint16_t r16(ux_t addr) {
		assert(addr < size && addr + 1 < size); // careful of ~0u
		assert(addr % 2 == 0);
		return mem[addr >> 2] >> 8 * (addr & 0x2) & 0xffffu;
	}

	virtual void w16(ux_t addr, uint16_t data) {
		assert(addr < size && addr + 1 < size);
		assert(addr % 2 == 0);
		mem[addr >> 2] &= ~(0xffffu << 8 * (addr & 0x2));
		mem[addr >> 2] |= (uint32_t)data << 8 * (addr & 0x2);
	}

	virtual uint32_t r32(ux_t addr) {
		assert(addr < size && addr + 3 < size);
		assert(addr % 4 == 0);
		return mem[addr >> 2];
	}

	virtual void w32(ux_t addr, uint32_t data) {
		assert(addr < size && addr + 3 < size);
		assert(addr % 4 == 0);
		mem[addr >> 2] = data;
	}
};

struct TBExitException {
	ux_t exitcode;
	TBExitException(ux_t code): exitcode(code) {}
};

struct TBMemIO: MemBase32 {
	virtual void w32(ux_t addr, uint32_t data) {
		switch (addr) {
		case 0x0:
			printf("%c", (char)data);
			break;
		case 0x4:
			printf("%08x\n", data);
			break;
		case 0x8:
			throw TBExitException(data);
			break;
		}
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
		throw;
	}

	// perhaps some templatey-ness required
	virtual uint8_t r8(ux_t addr) {
		auto [offset, mem] = map_addr(addr);
		return mem->r8(offset);
	}

	virtual void w8(ux_t addr, uint8_t data) {
		auto [offset, mem] = map_addr(addr);
		mem->w8(offset, data);
	}

	virtual uint16_t r16(ux_t addr) {
		auto [offset, mem] = map_addr(addr);
		return mem->r16(offset);
	}

	virtual void w16(ux_t addr, uint16_t data) {
		auto [offset, mem] = map_addr(addr);
		mem->w16(offset, data);
	}

	virtual uint32_t r32(ux_t addr) {
		auto [offset, mem] = map_addr(addr);
		return mem->r32(offset);
	}

	virtual void w32(ux_t addr, uint32_t data) {
		auto [offset, mem] = map_addr(addr);
		mem->w32(offset, data);
	}
};

#endif
