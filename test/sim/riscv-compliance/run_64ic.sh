#!/bin/bash
set -e

make TEST_ARCH=C BIN_ARCH=rv64ic TESTLIST=" \
	cadd-01 \
	caddi-01 \
	caddi16sp-01 \
	caddi4spn-01 \
	caddiw-01 \
	caddw-01 \
	cand-01 \
	candi-01 \
	cbeqz-01 \
	cbnez-01 \
	cebreak-01 \
	cj-01 \
	cjalr-01 \
	cjr-01 \
	cld-01 \
	cldsp-01 \
	cli-01 \
	clui-01 \
	clw-01 \
	clwsp-01 \
	cmv-01 \
	cnop-01 \
	cor-01 \
	csd-01 \
	csdsp-01 \
	cslli-01 \
	csrai-01 \
	csrli-01 \
	csub-01 \
	csubw-01 \
	csw-01 \
	cswsp-01 \
	cxor-01 \
	"
	#cebreak-01 \


