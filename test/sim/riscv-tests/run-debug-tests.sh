set -e

make -C ../tb_cxxrtl/ tb
cd riscv-tests/debug

# Clean up old logs and test binaries
rm -rf logs
for fname in $(find -name "*" -maxdepth 1); do
	if file ${fname} | grep -q "ELF 32-bit"; then rm ${fname}; fi
done

# Only applicable tests are run
TESTS=""
TESTS="${TESTS} CheckMisa"
TESTS="${TESTS} CrashLoopOpcode"
TESTS="${TESTS} DebugBreakpoint"
TESTS="${TESTS} DebugChangeString"
TESTS="${TESTS} DebugCompareSections"
TESTS="${TESTS} DebugExit"
TESTS="${TESTS} DebugFunctionCall"
TESTS="${TESTS} DebugSymbols"
TESTS="${TESTS} DebugTurbostep"
TESTS="${TESTS} DisconnectTest"
TESTS="${TESTS} DownloadTest"
TESTS="${TESTS} EbreakTest"
TESTS="${TESTS} EtriggerTest"
TESTS="${TESTS} Hwbp1"
TESTS="${TESTS} Hwbp2"
TESTS="${TESTS} HwbpManual"
TESTS="${TESTS} InfoTest"
TESTS="${TESTS} InstantChangePc"
TESTS="${TESTS} InstantHaltTest"
TESTS="${TESTS} InterruptTest"
TESTS="${TESTS} ItriggerTest"
TESTS="${TESTS} JumpHbreak"
TESTS="${TESTS} MemorySampleMixed"
TESTS="${TESTS} MemorySampleSingle"
TESTS="${TESTS} MemTest16"
TESTS="${TESTS} MemTest32"
TESTS="${TESTS} MemTest64"
TESTS="${TESTS} MemTest8"
TESTS="${TESTS} MemTestBlock0"
TESTS="${TESTS} MemTestBlock1"
TESTS="${TESTS} MemTestBlock2"
TESTS="${TESTS} MemTestReadInvalid"
TESTS="${TESTS} PrivChange"
TESTS="${TESTS} PrivRw"
TESTS="${TESTS} ProgramSwWatchpoint"
TESTS="${TESTS} Registers"
TESTS="${TESTS} RepeatReadTest"
TESTS="${TESTS} Semihosting"
TESTS="${TESTS} SemihostingFileio"
TESTS="${TESTS} SimpleF18Test"
TESTS="${TESTS} SimpleNoExistTest"
TESTS="${TESTS} SimpleS0Test"
TESTS="${TESTS} SimpleS1Test"
TESTS="${TESTS} SimpleT0Test"
TESTS="${TESTS} SimpleT1Test"
TESTS="${TESTS} SimpleV13Test"
TESTS="${TESTS} StepTest"
TESTS="${TESTS} TooManyHwbp"
TESTS="${TESTS} TriggerExecuteInstant"
TESTS="${TESTS} UserInterrupt"
TESTS="${TESTS} WriteCsrs"
TESTS="${TESTS} WriteGprs"

# Run all tests with SBA enabled
./gdbserver.py \
	--sim_cmd "../../../tb_cxxrtl/tb --port 9824" \
	--server_cmd "riscv-openocd" \
	--gdb riscv32-unknown-elf-gdb \
	--gcc riscv32-unknown-elf-gcc \
	targets/luke/hazard3.py \
	${TESTS}

# Re-run without SBA -- covers some additional Debug Module logic like abstractauto
./gdbserver.py \
	--sim_cmd "../../../tb_cxxrtl/tb --port 9824" \
	--server_cmd "riscv-openocd" \
	--gdb riscv32-unknown-elf-gdb \
	--gcc riscv32-unknown-elf-gcc \
	targets/luke/hazard3_nosba.py \
	${TESTS}

# List of excluded tests, as seen by removing the test list from the above
# invocation and allowing all tests to run:
#
# "fail":
#  * IcountTest ......................... Relies on instruction count trigger, not implemented
#  * TriggerDmode ....................... Relies on load/store triggers, not implemented
# "exception":
#  * ProgramHwWatchpoint ................ Relies on load/store trigger, not implemented
#  * Sv32Test ........................... Relies on S-mode + vm, not implemented
#  * TriggerLoadAddressInstant .......... Relies on load address trigger, not implemented
#  * TriggerStoreAddressInstant ......... Relies on store address trigger, not implemented
# "not_applicable":
#  * CeaseStepiTest ..................... Relies on the `cease` instruction, not implemented
#  * CustomRegisterTest ................. Only applicable if target has custom debug registers like spike
#  * FreeRtosTest ....................... Requires freertos binary build, possibly should be ported in future
#  * MemTestBlockReadInvalid ............ Requires invalid_memory_returns_zero flag which is false for hazard3 tb
#  * MulticoreRegTest ................... SMP-only
#  * MulticoreRtosSwitchActiveHartTest .. SMP-only
#  * MulticoreRunAllHaltOne ............. SMP-only
#  * SmpSimultaneousRunHalt ............. SMP-only
#  * StepThread2Test .................... SMP-only
#  * Sv39Test ........................... (RV64 + S)-only
#  * Sv48Test ........................... (RV64 + S)-only
#  * UnavailableCycleTest ............... Requires unavailability control through DMCUSTOM, perhaps could be supported in future
#  * UnavailableHaltedTest .............. Requires unavailability control through DMCUSTOM, perhaps could be supported in future
#  * UnavailableMultiTest ............... Requires unavailability control through DMCUSTOM, perhaps could be supported in future
#  * UnavailableRunTest ................. Requires unavailability control through DMCUSTOM, perhaps could be supported in future
#  * VectorTest ......................... Relies on V extension, not implemented
#
# When this list was last updated, there were: 74 tests
