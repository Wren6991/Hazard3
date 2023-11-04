#ifndef _XOROSHIRO256_H
#define _XOROSHIRO256_H

// xoroshiro256++ pseudorandom number generator.
// Adapted from: https://prng.di.unimi.it/xoshiro256plusplus.c
// Original copyright notice:

/*  Written in 2019 by David Blackman and Sebastiano Vigna (vigna@acm.org)

To the extent possible under law, the author has dedicated all copyright
and related and neighboring rights to this software to the public domain
worldwide. This software is distributed without any warranty.

See <http://creativecommons.org/publicdomain/zero/1.0/>. */

#include <stdint.h>

/* This is xoshiro256++ 1.0, one of our all-purpose, rock-solid generators.
   It has excellent (sub-ns) speed, a state (256 bits) that is large
   enough for any parallel application, and it passes all tests we are
   aware of.

   For generating just floating-point numbers, xoshiro256+ is even faster.

   The state must be seeded so that it is not everywhere zero. If you have
   a 64-bit seed, we suggest to seed a splitmix64 generator and use its
   output to fill s. */

static inline uint64_t xr256_rotl(const uint64_t x, int k) {
	return (x << k) | (x >> (64 - k));
}

uint64_t xr256_next(uint64_t s[4]) {
	const uint64_t result = xr256_rotl(s[0] + s[3], 23) + s[0];

	const uint64_t t = s[1] << 17;

	s[2] ^= s[0];
	s[3] ^= s[1];
	s[1] ^= s[2];
	s[0] ^= s[3];

	s[2] ^= t;

	s[3] = xr256_rotl(s[3], 45);

	return result;
}

#endif
