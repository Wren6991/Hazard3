set -e

make -C ../tb_cxxrtl/ tb
cd riscv-tests/debug

# Clean up old logs and test binaries
rm -rf logs
for fname in $(find -name "*" -maxdepth 1); do
	if file ${fname} | grep -q "ELF 32-bit"; then rm ${fname}; fi
done

# Only applicable tests are included
./gdbserver.py \
	--sim_cmd "../../../tb_cxxrtl/tb --port 9824" \
	--server_cmd "riscv-openocd" \
	--gdb riscv32-unknown-elf-gdb \
	--gcc riscv32-unknown-elf-gcc \
	targets/luke/hazard3.py \
CheckMisa \
CrashLoopOpcode \
DebugBreakpoint \
DebugChangeString \
DebugCompareSections \
DebugExit \
DebugFunctionCall \
DebugSymbols \
DebugTurbostep \
DisconnectTest \
DownloadTest \
EbreakTest \
Hwbp1 \
Hwbp2 \
HwbpManual \
InfoTest \
InstantChangePc \
InstantHaltTest \
InterruptTest \
JumpHbreak \
MemorySampleMixed \
MemorySampleSingle \
MemTest16 \
MemTest32 \
MemTest64 \
MemTest8 \
MemTestBlock0 \
MemTestBlock1 \
MemTestBlock2 \
MemTestReadInvalid \
PrivChange \
PrivRw \
ProgramSwWatchpoint \
Registers \
RepeatReadTest \
Semihosting \
SemihostingFileio \
SimpleF18Test \
SimpleNoExistTest \
SimpleS0Test \
SimpleS1Test \
SimpleT0Test \
SimpleT1Test \
SimpleV13Test \
StepTest \
TooManyHwbp \
TriggerExecuteInstant \
UserInterrupt \
WriteCsrs \
WriteGprs

# List of excluded tests, as seen by removing the test list from the above
# invocation and allowing all tests to run:
#
# "fail":
#  * EtriggerTest ....................... Relies on exception trigger, not implemented
#  * IcountTest ......................... Relies on interrupt count trigger, not implemented
#  * TriggerDmode ....................... Relies on load/store triggers, not implemented
# "exception":
#  * ItriggerTest ....................... Relies on interrupt trigger, not implemented
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
