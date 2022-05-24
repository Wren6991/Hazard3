# Hazard3

Hazard3 is a 3-stage RISC-V processor, implementing the `RV32I` instruction set and the following optional extensions:

* `M`: integer multiply/divide/modulo
* `C`: compressed instructions
* `A` : atomic memory operations, with AHB5 global exclusives
* `Zicsr`: CSR access
* `Zba`: address generation
* `Zbb`: basic bit manipulation
* `Zbc`: carry-less multiplication
* `Zbs`: single-bit manipulation
* `Zbkb`: basic bit manipulation for scalar cryptography
* M-mode privileged instructions `ECALL`, `EBREAK`, `MRET` and the `WFI` instruction
* The machine-mode (M-mode) privilege state, and standard M-mode CSRs
* The user-mode (U-mode) privilege state *(experimental)*
* Physical memory protection (PMP) with up to 16 naturally aligned regions *(experimental)*
* Debug support, compliant with RISC-V debug specification version 0.13.2

You can [read the documentation here](doc/hazard3.pdf). (PDF link)

This repository also contains a compliant RISC-V Debug Module for Hazard3, which can be accessed over an AMBA 3 APB port or using the optional JTAG Debug Transport Module.

There is an [example SoC integration](example_soc/soc/example_soc.v), showing how these components can be assembled to create a minimal system with a JTAG-enabled RISC-V processor, some RAM and a serial port.

The following are planned for future implementation:

* Debug trigger unit (breakpoint-only)

Hazard3 is still under development.

# Pipeline

- `F` fetch
	- Instruction fetch data phase
	- Instruction alignment
	- Decode of `rs1`/`rs2` register specifiers into register file read ports
- `X` execute
	- Expand compressed instructions
	- Expand immediates
	- Forward appropriate data and decoded operation to ALU or to load/store address phase
	- Resolve branch conditions
	- Instruction fetch address phase
	- Load/store address phase
- `M` memory
	- Load/store data phase
	- Some complex instructions, particularly multiply and divide
	- Exception handling

This is essentially Hazard5, with the `D` and `X` stages merged and the register file brought forward. Many components are reused directly from Hazard5. The particular focus here is on shortening the branch delay, which is one of the weak points in Hazard5's IPC.


# Cloning This Repository

For the purpose of using Hazard3 in your design, this repository is self-contained. You will need to pull in the submodules for simulation scripts, compliance tests and for components for the example SoC:

```bash
git clone --recursive https://github.com/Wren6991/Hazard3.git hazard3
```

# Running Hello World

These instructions are for Ubuntu 20.04. You will need:

- A recent Yosys build to process the Verilog. At least version `c2afcbe7`, which includes a workaround for a gtkwave string parsing issue. Latest master should be fine.
- A `riscv32-unknown-elf-` toolchain to build software for the core
- A native `clang` to build the simulator

## Yosys

The [Yosys GitHub repo](https://github.com/YosysHQ/yosys) has instructions for building Yosys from source. I don't recommend right now (July '21) to use the version from your package manager.

## RISC-V Toolchain

The instructions below are for building a version of the 32-bit [RISC-V GNU toolchain](https://github.com/riscv/riscv-gnu-toolchain) with multilib support for the various combinations of RV32I/M/C ISAs:

```bash
# Prerequisites for Ubuntu 20.04
sudo apt install -y autoconf automake autotools-dev curl python3 libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev
cd /tmp
git clone --recursive https://github.com/riscv/riscv-gnu-toolchain
cd riscv-gnu-toolchain
# The ./configure arguments are the most important difference
./configure --prefix=/opt/riscv --with-arch=rv32imc --with-abi=ilp32 --with-multilib-generator="rv32i-ilp32--;rv32ic-ilp32--;rv32im-ilp32--;rv32imc-ilp32--"
sudo mkdir /opt/riscv
sudo chown $(whoami) /opt/riscv
make -j $(nproc)
```

The multilib build is strongly recommended -- getting a RV32IMC standard library on a RV32I processor variant will ruin your day, and running soft float that does not use the multiply instructions is not much fun either.

This build will also install an appropriate gdb as `riscv32-unknown-elf-gdb`.

## Actually Running Hello World

Make sure you have done a _recursive_ clone of the Hazard3 repository. Build the CXXRTL-based simulator:

```bash
cd hazard3
# Set up some paths, add RISC-V toolchain to PATH
. sourceme

cd test/sim/tb_cxxrtl
make
```

Build and run the hello world binary:

```bash
cd ../hellow
make
```

All going well you should see something like:

```
$ make
mkdir -p tmp/
riscv32-unknown-elf-gcc -march=rv32imc -Os ../common/init.S main.c -T ../common/memmap.ld -I../common -o tmp/hellow.elf
riscv32-unknown-elf-objcopy -O binary tmp/hellow.elf tmp/hellow.bin
riscv32-unknown-elf-objdump -h tmp/hellow.elf > tmp/hellow.dis
riscv32-unknown-elf-objdump -d tmp/hellow.elf >> tmp/hellow.dis
../tb_cxxrtl/tb --bin tmp/hellow.bin --vcd tmp/hellow_run.vcd --cycles 100000
Hello world from Hazard3 + CXXRTL!
CPU requested halt. Exit code 123
Ran for 601 cycles
```

This will have created a waveform dump called `tmp/hellow_run.vcd` which you can view with GTKWave:

```bash
gtkwave tmp/hellow_run.vcd
```

# Loading Hello World with the Debugger

Invoking the simulator built in the previous step, with no arguments, shows the following usage message:

```
$ ./tb 
At least one of --bin or --port must be specified.
Usage: tb [--bin x.bin] [--vcd x.vcd] [--dump start end] [--cycles n] [--port n]
    --bin x.bin      : Flat binary file loaded to address 0x0 in RAM
    --vcd x.vcd      : Path to dump waveforms to
    --dump start end : Print out memory contents from start to end (exclusive)
                       after execution finishes. Can be passed multiple times.
    --cycles n       : Maximum number of cycles to run before exiting.
                       Default is 0 (no maximum).
    --port n         : Port number to listen for openocd remote bitbang. Sim
                       runs in lockstep with JTAG bitbang, not free-running.
```

This simulator contains:

- Hardware:
	- The processor
	- A Debug Module (DM)
	- A JTAG Debug Transport Module (DTM)
- Software:
	- RAM model
	- Routines for loading binary files, dumping VCDs
	- Routines for bitbanging the JTAG DTM through a TCP socket

Running hello world in the previous section used the `--bin` argument to load the linked hello world executable directly into the testbench's RAM. If we invoke the simulator with the `--port` argument, it will instead wait for a connection on that port, and then accept JTAG bitbang commands in OpenOCD's `remote-bitbang` format. The simulation runs in lockstep with the JTAG bitbanging, for more predictable results.

We need to build a copy of `riscv-openocd` before going any further. OpenOCD's role is to translate the abstract debug commands issued by gdb, e.g. "set the program counter to address `x`", to more concrete operations, e.g. "shift this JTAG DR".

## Building riscv-openocd

We need a recent build of [riscv-openocd](https://github.com/riscv/riscv-openocd) with the `remote-bitbang` protocol enabled.

```bash
cd /tmp
git clone https://github.com/riscv/riscv-openocd.git
cd riscv-openocd
./bootstrap
# Prefix is optional
./configure --enable-remote-bitbang --enable-ftdi --program-prefix=riscv-
make -j $(nproc)
sudo make install
```

## Loading and Running

You're going to want three terminal tabs in the `tb_cxxrtl` directory.

```bash
cd hazard3/test/sim/tb_cxxrtl
```

In the first of them type:

```bash
./tb --port 9824
```

You should see something like

```
Waiting for connection on port 9824
```

The simulation will start once OpenOCD connects. In your second terminal in the same directory, start riscv-openocd:

```bash
riscv-openocd -f openocd.cfg
```

If you see something like:

```
Info : Initializing remote_bitbang driver
Info : Connecting to localhost:9824
Info : remote_bitbang driver initialized
Info : This adapter doesn't support configurable speed
Info : JTAG tap: hazard3.cpu tap/device found: 0xdeadbeef (mfg: 0x777 (<unknown>), part: 0xeadb, ver: 0xd)
Info : datacount=1 progbufsize=2
Info : Disabling abstract command reads from CSRs.
Info : Examined RISC-V core; found 1 harts
Info :  hart 0: XLEN=32, misa=0x40801105
Info : starting gdb server for hazard3.cpu on 3333
Info : Listening on port 3333 for gdb connections
Info : Listening on port 6666 for tcl connections
Info : Listening on port 4444 for telnet connections
```

Then openocd is successfully connected to the processor's debug hardware. We're going to use riscv-gdb to load and run the hello world executable, which is what the third terminal is for:

```bash
riscv32-unknown-elf-gdb
# Remaining commands are typed into the gdb prompt. This one tells gdb to shut up:
set confirm off
# Connect to openocd on its default port:
target extended-remote localhost:3333
# Load hello world, and check that it loaded correctly
file ../hellow/tmp/hellow.elf
load
compare-sections
# The processor will quit the simulation when after returning from main(), by
# writing to a magic MMIO register. openocd will be quite unhappy that the
# other end of its socket disappeared, so to avoid the resulting error
# messages, add a breakpoint before _exit.
break _exit
run
# Should break at _exit. Check the terminal with the simulator, you should see
# the hello world message. The exit code is in register a0, it should be 123:
info reg a0
```

# Building an Example SoC

There is a tiny [example SoC](example_soc/soc/example_soc.v) which builds on both iCEBreaker and ULX3S. The SoC contains:

- A Hazard3 processor, in a single-ported RV32IM configuration, with debug support
- A Debug Transport Module and Debug Module to access Hazard3's debug interface
- 128 kB of RAM (fits in UP5k SPRAMs)
- A UART

On iCEBreaker (a iCE40 UP5k development board), the processor can be debugged using the onboard FT2232H bridge, through a standard RISCV-V JTAG-DTM exposed on four IO pins. Connecting JTAG requires two solder jumpers to be bridged on the back to connect the JTAG -- see the comments in the [pin constraints file](example_soc/synth/fpga_icebreaker.pcf). FT2232H is a dual-channel FTDI device, so the UART and JTAG can be accessed simultaneously for a very civilised debug experience, with JTAG running at the full 30 MHz supported by the FTDI.

ULX3S is based on a much larger ECP5 FPGA. Thanks to [this ECP5 JTAG adapter](hdl/debug/dtm/hazard3_ecp5_jtag_dtm.v), it is possible to attach the guts of a RISC-V JTAG-DTM to the custom DR hooks in ECP5's chip TAP. With the right config file you can then convince OpenOCD that the FPGA's own TAP *is* a JTAG-DTM. You can debug Hazard3 on ULX3S using the same micro USB cable you use to load the bitstream, no soldering required. The downside is that the FT231X device on the ULX3S is actually a UART bridge which supports JTAG by bitbanging the auxiliary UART signals, which is incredibly slow. The UART can not be used simultaneously with JTAG access. 

For these reasons -- much faster JTAG, and simultaneous UART access -- iCEBreaker is currently a more pleasant platform to debug if you don't have any external JTAG probe.

Note there is no software tree for this SoC. For now you'll have to read the source and hack on the test software build. All very much WIP. At least you can attach to the processor, poke registers/memory, and convince yourself you really are debugging a RISC-V core.

## Building for iCEBreaker

```bash
cd hazard3
. sourceme
cd example_soc/synth
make -f Icebreaker.mk prog
# Should be able to attach to the processor
riscv-openocd -f ../icebreaker-openocd.cfg
```

## Building for ULX3S

```bash
cd hazard3
. sourceme
cd example_soc/synth
make -f ULX3S.mk flash
# Should be able to attach to the processor
riscv-openocd -f ../ulx3s-openocd.cfg
```
