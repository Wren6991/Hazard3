#!/bin/bash
make TEST_ARCH=M BIN_ARCH=rv32imc TESTLIST=" \
	div-01 \
	divu-01 \
	rem-01 \
	remu-01 \
	mul-01 \
	mulhu-01 \
	mulh-01 \
	mulhsu-01 \
	"
