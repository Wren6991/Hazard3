#!/bin/bash

set -e

# Note c.ebreak is expected to fail due to not correctly handling mtval being
# (legally) hardwired to 0.

# Not clear yet whether this is a configuration issue or an issue with the
# reference vector generation/selection, but I've debugged the test, and the
# non-mtval-related parts of the signature are good.

make -C riscv-arch-test RISCV_TARGET=hazard3 RISCV_DEVICE=C || echo "
Note cebreak-01 is an expected failure: test does not correctly handle hardwired mtval.

If you see any other failures, that is a cause for concern."
