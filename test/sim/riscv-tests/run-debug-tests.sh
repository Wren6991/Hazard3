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
