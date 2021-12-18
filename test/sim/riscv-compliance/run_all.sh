#!/bin/bash
set -e

./run_32i.sh
./run_32im.sh
./run_32ic.sh
# These are TODO for sw reasons -- not sure why they don't bundle the handlers with the tests
# ./run_32privilege.sh
