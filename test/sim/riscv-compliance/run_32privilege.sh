#!/bin/bash
make TEST_ARCH=privilege BIN_ARCH=rv32i TESTLIST=" \
	ebreak \
	ecall \
	misalign-lh-01 \
	misalign-lhu-01 \
	misalign-lw-01 \
	misalign-sh-01 \
	misalign-sw-01
	"
