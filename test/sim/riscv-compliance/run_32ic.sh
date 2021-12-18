#!/bin/bash
set -e

make TEST_ARCH=C BIN_ARCH=rv32ic TESTLIST=" \
	cadd-01 \
	caddi16sp-01 \
	cand-01 \
	cbeqz-01 \
	cjal-01 \
	cjr-01 \
	clui-01 \
	clwsp-01 \
	cnop-01 \
	cslli-01 \
	csrli-01 \
	csw-01 \
	cxor-01 \
	caddi-01 \
	caddi4spn-01 \
	candi-01 \
	cbnez-01 \
	cj-01 \
	cjalr-01 \
	cli-01 \
	clw-01 \
	cmv-01 \
	cor-01 \
	csrai-01 \
	csub-01 \
	cswsp-01 \
	"
	#cebreak-01 \
