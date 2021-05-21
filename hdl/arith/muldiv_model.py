#!/usr/bin/env python3

# Quick reference model for sequential unsigned multiply/divide/modulo

def div_step(w, accum, divisor):
	sub_tmp = accum - (divisor << (w - 1))
	underflow = sub_tmp < 0
	if not underflow:
		accum = sub_tmp
	accum = (accum << 1) | (not underflow)
	return accum

def divmod(w, dividend, divisor, debug=True):
	accum = dividend
	for i in range(w):
		accum_prev = accum
		accum = div_step(w, accum, divisor)
		if debug:
			print("Step {:02d}: accum {:0{}x} -> {:0{}x}".format(
				i, accum_prev, int(w / 2), accum, int(w / 2)))
	return (accum >> w, accum & ((1 << w) - 1))

def mul_step(w, accum, multiplicand):
	add_en = accum & 1
	accum = accum >> 1
	if add_en:
		accum += (multiplicand << (w - 1))
	return accum

def mul(w, multiplicand, multiplier, debug=True):
	accum = multiplier
	for i in range(w):
		accum_prev = accum
		accum = mul_step(w, accum, multiplicand)
		if debug:
			print("Step {:02d}: accum {:0{}x} -> {:0{}x}".format(
				i, accum_prev, int(w / 2), accum, int(w / 2)))
	return (accum >> w, accum & ((1 << w) - 1))

def divtest(w=4):
	for i in range(2 ** w):
		for j in range(1, 2 ** w):
			gatemod, gatediv = divmod(w, i, j, debug=False)
			goldmod, golddiv = (i % j, i // j)
			print("{:02d} % {:02d} = {:02d} (gold {:02d}); ./. = {:02d} (gold {:02d})"
				.format(i, j, gatemod, goldmod, gatediv, golddiv))
			assert(gatemod == goldmod)
			assert(gatediv == golddiv)

def multest(w=4):
	for i in range(2 ** w):
		for j in range(2 ** w):
			gateh, gatel = mul(w, i, j, debug=False)
			gold = i * j
			goldl, goldh = (gold & ((1 << w) - 1), gold >> w)
			print("{:02d} * {:02d} = ({:02d} (gold {:02d}), {:02d} (gold {:02d})"
				.format(i, j, gateh, goldh, gatel, goldl))
			assert(gatel == goldl)
			assert(gateh == goldh)

if __name__ == "__main__":
	print("Test division:")
	divtest()
	print("Test multiplication:")
	multest()
