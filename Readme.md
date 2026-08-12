# Hazard3

Hazard3 is a 3-stage RISC-V processor, implementing the `RV32I` or `RV32E` instruction set and the following optional extensions:

* `M`: integer multiply/divide/modulo
* `A` : atomic memory operations, with AHB5 global exclusives
* `C`: compressed instructions
* `Zibi`: branch-with-immediate instructions (unratified)
* `Zicsr`: CSR access
* `Zilsd`: load/store pair instructions
* `Zba`: address generation
* `Zbb`: basic bit manipulation
* `Zbc`: carry-less multiplication
* `Zbs`: single-bit manipulation
* `Zbkb`: basic bit manipulation for scalar cryptography
* `Zbkx`: crossbar permutation instructions
* `Zcb`: basic additional compressed instructions
* `Zclsd`: compressed load/store pair instructions
* `Zcmp`: push/pop instructions
* Debug, Machine and User privilege/execution modes
* Privileged instructions `ecall`, `ebreak`, `mret` and `wfi`
* Physical memory protection (PMP) with up to 16 regions (configurable support for NAPOT and/or TOR matching)
* External debug support (JTAG or APB)
* Instruction address trigger unit (hardware breakpoints)

Download the Hazard3 reference manual [here (PDF)](https://github.com/Wren6991/Hazard3/releases/download/v1.1/hazard3.pdf). You can also [read the documentation online](https://wren.wtf/hazard3/doc).

This repository contains the source for the Hazard3 core and its associated debug components. The [example SoC integration](example_soc/soc/example_soc.v) shows how you can assemble these components to create a minimal system with a JTAG-enabled RISC-V processor, some RAM, a serial port and a platform timer.

Please read [Contributing.md](Contributing.md) before raising an issue or pull request.

# Cloning This Repository

For the purpose of using Hazard3 in your design, this repository is self-contained. However, you need the submodules for simulation scripts, tests and example SoC components. In the latter case you should do a recursive clone:

```bash
git clone --recursive https://github.com/Wren6991/Hazard3.git hazard3
```

To initialise submodules in an already-cloned repository:

```bash
git submodule update --init --recursive
```

The default branch for clones is [stable](https://github.com/Wren6991/Hazard3/tree/stable). I strongly recommend this branch for ASIC tapeouts. The head of stable is always the latest non-development release under [releases](https://github.com/Wren6991/Hazard3/releases).

See the [develop](https://github.com/Wren6991/Hazard3/tree/develop) branch to try the latest features and optimisations.

# Running Hello World

These instructions walk through:

* Setting up the tools for building the Hazard3 simulator from Verilog source
* Setting up the tools for building RISC-V binaries to run on the simulator
* Building a "Hello, world!" binary and running it on the simulator

These instructions are for Ubuntu 24.04. If you are running on Windows you may have some success with Ubuntu under WSL.

You will need:

* A recent Yosys build to process the Verilog (these instructions were last tested with `a0e94e506`)
* A `riscv32-unknown-elf-` toolchain to build software for the core
* A native `clang` to build the simulator

## Yosys

The [Yosys GitHub repo](https://github.com/YosysHQ/yosys) has instructions for building Yosys from source.

The following steps work for me on Ubuntu 24.04 using version `a0e94e506` mentioned above.

```bash
sudo apt install build-essential clang lld bison flex libreadline-dev gawk tcl-dev libffi-dev git graphviz xdot pkg-config python3 libboost-system-dev libboost-python-dev libboost-filesystem-dev zlib1g-dev

git clone https://github.com/YosysHQ/yosys.git
cd yosys
git submodule update --init
make -j$(nproc)
sudo make install
```

On MacOS the dependencies can be installed with:

```bash
brew install graphviz python3 boost zlib bison flex xdot pkg-config gawk lld
```

## RISC-V Toolchain

I recommend _building_ a toolchain to get libraries with the correct ISA support. Follow the below instructions to build a 32-bit version of the [RISC-V GNU toolchain](https://github.com/riscv/riscv-gnu-toolchain) with a multilib setup suitable for Hazard3 development.

```bash
# Prerequisites for Ubuntu 24.04
sudo apt install autoconf automake autotools-dev curl python3 python3-pip libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev ninja-build git cmake libglib2.0-dev libslirp-dev

cd /tmp
git clone https://github.com/riscv/riscv-gnu-toolchain
cd riscv-gnu-toolchain

./configure --prefix=/opt/riscv/gcc15 --with-arch=rv32ia_zicsr_zifencei --with-abi=ilp32 --with-multilib-generator="rv32i_zicsr_zifencei-ilp32--;rv32im_zicsr_zifencei-ilp32--;rv32ia_zicsr_zifencei-ilp32--;rv32ima_zicsr_zifencei-ilp32--;rv32ic_zicsr_zifencei-ilp32--;rv32imc_zicsr_zifencei-ilp32--;rv32iac_zicsr_zifencei-ilp32--;rv32imac_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbs_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbs_zicsr_zifencei-ilp32--;rv32imc_zba_zbb_zbs_zicsr_zifencei-ilp32--;rv32imac_zba_zbb_zbs_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbs_zbkb_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbs_zbkb_zicsr_zifencei-ilp32--;rv32imc_zba_zbb_zbs_zbkb_zicsr_zifencei-ilp32--;rv32imac_zba_zbb_zbs_zbkb_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbc_zbs_zbkb_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbc_zbs_zbkb_zicsr_zifencei-ilp32--;rv32imc_zba_zbb_zbc_zbs_zbkb_zicsr_zifencei-ilp32--;rv32imac_zba_zbb_zbc_zbs_zbkb_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbs_zbkb_zbkx_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbs_zbkb_zbkx_zicsr_zifencei-ilp32--;rv32imc_zba_zbb_zbs_zbkb_zbkx_zicsr_zifencei-ilp32--;rv32imac_zba_zbb_zbs_zbkb_zbkx_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbc_zbs_zbkb_zbkx_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbc_zbs_zbkb_zbkx_zicsr_zifencei-ilp32--;rv32imc_zba_zbb_zbc_zbs_zbkb_zbkx_zicsr_zifencei-ilp32--;rv32imac_zba_zbb_zbc_zbs_zbkb_zbkx_zicsr_zifencei-ilp32--;rv32i_zca_zicsr_zifencei-ilp32--;rv32im_zca_zicsr_zifencei-ilp32--;rv32ia_zca_zicsr_zifencei-ilp32--;rv32ima_zca_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbs_zca_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbs_zca_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbs_zbkb_zca_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbs_zbkb_zca_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbc_zbs_zbkb_zca_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbc_zbs_zbkb_zca_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbs_zbkb_zbkx_zca_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbs_zbkb_zbkx_zca_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbc_zbs_zbkb_zbkx_zca_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbc_zbs_zbkb_zbkx_zca_zicsr_zifencei-ilp32--;rv32i_zca_zcb_zicsr_zifencei-ilp32--;rv32im_zca_zcb_zicsr_zifencei-ilp32--;rv32ia_zca_zcb_zicsr_zifencei-ilp32--;rv32ima_zca_zcb_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbs_zca_zcb_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbs_zca_zcb_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbs_zbkb_zca_zcb_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbs_zbkb_zca_zcb_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbc_zbs_zbkb_zca_zcb_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbc_zbs_zbkb_zca_zcb_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbs_zbkb_zbkx_zca_zcb_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbs_zbkb_zbkx_zca_zcb_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbc_zbs_zbkb_zbkx_zca_zcb_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbc_zbs_zbkb_zbkx_zca_zcb_zicsr_zifencei-ilp32--;rv32i_zca_zcb_zcmp_zicsr_zifencei-ilp32--;rv32im_zca_zcb_zcmp_zicsr_zifencei-ilp32--;rv32ia_zca_zcb_zcmp_zicsr_zifencei-ilp32--;rv32ima_zca_zcb_zcmp_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbs_zca_zcb_zcmp_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbs_zca_zcb_zcmp_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbs_zbkb_zca_zcb_zcmp_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbs_zbkb_zca_zcb_zcmp_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbc_zbs_zbkb_zca_zcb_zcmp_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbc_zbs_zbkb_zca_zcb_zcmp_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbs_zbkb_zbkx_zca_zcb_zcmp_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbs_zbkb_zbkx_zca_zcb_zcmp_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbc_zbs_zbkb_zbkx_zca_zcb_zcmp_zicsr_zifencei-ilp32--;rv32ima_zba_zbb_zbc_zbs_zbkb_zbkx_zca_zcb_zcmp_zicsr_zifencei-ilp32--;rv32i_zmmul_zicsr_zifencei-ilp32--;rv32ia_zmmul_zicsr_zifencei-ilp32--;rv32ic_zmmul_zicsr_zifencei-ilp32--;rv32iac_zmmul_zicsr_zifencei-ilp32--;rv32i_zca_zmmul_zicsr_zifencei-ilp32--;rv32ia_zca_zmmul_zicsr_zifencei-ilp32--;rv32i_zca_zcb_zmmul_zicsr_zifencei-ilp32--;rv32ia_zca_zcb_zmmul_zicsr_zifencei-ilp32--;rv32i_zca_zcb_zcmp_zmmul_zicsr_zifencei-ilp32--;rv32ia_zca_zcb_zcmp_zmmul_zicsr_zifencei-ilp32--;rv32e_zicsr_zifencei-ilp32e--;rv32ema_zicsr_zifencei-ilp32e--;rv32emac_zicsr_zifencei-ilp32e--;rv32ema_zicsr_zifencei_zba_zbb_zbc_zbkb_zbkx_zbs_zca_zcb_zcmp-ilp32e--"
sudo mkdir -p /opt/riscv/gcc15
sudo chown $(whoami) /opt/riscv/gcc15
make -j $(nproc)
```

The `--with-multilib-generator=` flag builds multiple versions of the standard library, to match possible `-march` flags provided at link time. The multilib-generator command line above was generated using [multilib-gen-gen.py](test/sim/common/multilib-gen-gen.py)

Make sure this toolchain can be found on your `PATH` (as `riscv32-unknown-elf-*`):

```bash
export PATH="$PATH:/opt/riscv/gcc15/bin"
```

### Non-multilib (Smaller Install Size)

For a faster build and a smaller install size, use this `./configure` line instead:

```bash
./configure --prefix=/opt/riscv/gcc15 --with-arch=rv32imac_zicsr_zifencei_zba_zbb_zbkb_zbs --with-abi=ilp32
```

Adjust the `--with-arch` line as necessary for your Hazard3 configuration. You may need to adjust architectures used in software Makefiles in this repository to fit your chosen architecture variant.

### Building Toolchain on MacOS

These are my hacks to build the latest `riscv-gnu-toolchain` on MacOS Sequoia on M4 (Arm).

```bash
brew install python3 gawk gnu-sed make gmp mpfr libmpc isl zlib expat texinfo flock libslirp pkgconf
git clone https://github.com/riscv/riscv-gnu-toolchain
cd riscv-gnu-toolchain
git submodule update --init -- binutils gdb
# HACK for a macro definition which conflicts with a system header:
gsed -i 's,#        define fdopen,//#define fdopen,' binutils/zlib/zutil.h gdb/zlib/zutil.h

# pkgconf is required because gdb's configure script is unable to find these
# two libraries without help (a mystery).
export PATH="/opt/homebrew/bin:$PATH"
export LDFLAGS="-L/opt/homebrew/lib  $(pkgconf --libs-only-L gmp mpfr)"
export CPPFLAGS="-I/opt/homebrew/include $(pkgconf --cflags-only-I gmp mpfr)"
./configure --prefix=/opt/riscv/gcc15 --with-arch=rv32imac_zicsr_zifencei_zba_zbb_zbkb_zbs --with-abi=ilp32
gmake -j10
```

## Actually Running Hello World

Make sure you have done a _recursive_ clone of the Hazard3 repository. Build the CXXRTL-based simulator:

```bash
cd hazard3
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
riscv32-unknown-elf-gcc -march=rv32imac_zicsr_zifencei_zba_zbb_zbkb_zbs -Os -Wl,--no-warn-rwx-segments ../common/init.S main.c -T ../common/memmap.ld -I../common -o tmp/hellow.elf
riscv32-unknown-elf-objcopy -O binary tmp/hellow.elf tmp/hellow.bin
riscv32-unknown-elf-objdump -h tmp/hellow.elf > tmp/hellow.dis
riscv32-unknown-elf-objdump -d tmp/hellow.elf >> tmp/hellow.dis
../tb_cxxrtl/tb --bin tmp/hellow.bin --vcd tmp/hellow_run.vcd --cycles 100000
Hello world from Hazard3 + CXXRTL!
CPU requested halt. Exit code 123
Ran for 897 cycles
```

This will have created a waveform dump called `tmp/hellow_run.vcd` which you can view with GTKWave:

```bash
gtkwave tmp/hellow_run.vcd
```

Installing GTKWave on Ubuntu 24.04 is just `sudo apt install gtkwave`.

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

On Ubuntu:

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

On MacOS:

```bash
brew install autoconf automake libusb jimtcl
cd /tmp
git clone https://github.com/riscv/riscv-openocd.git
cd riscv-openocd
./bootstrap
# Workarounds:
# - System clang has a warning for the GCC constant VLA thing, and OpenOCD is -Werror by default
# - amtjtagaccel driver tries to pull in a Linux header
CFLAGS=-Wno-gnu-folding-constant ./configure --enable-remote-bitbang --enable-ftdi --enable-amtjtagaccel=no --program-prefix=riscv-
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
Info : Note: The adapter "remote_bitbang" doesn't support configurable speed
Info : JTAG tap: hazard3.cpu tap/device found: 0xdeadbeef (mfg: 0x777 (Fabric of Truth Inc), part: 0xeadb, ver: 0xd)
Info : [hazard3.cpu] datacount=1 progbufsize=2
Info : [hazard3.cpu] Examined RISC-V core
Info : [hazard3.cpu]  XLEN=32, misa=0x40901107
[hazard3.cpu] Target successfully examined.
Info : [hazard3.cpu] Examination succeed
Info : [hazard3.cpu] starting gdb server on 3333
Info : Listening on port 3333 for gdb connections
hazard3.cpu halted due to debug-request.
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

# Simulating with Verilator

There is a Verilator harness with the same features and interface as the CXXRTL harness. First build Verilator:

```
git clone https://github.com/verilator/verilator.git
cd verilator
mkdir build
cd build
cmake ..
make -j$(nproc)
sudo make install
```

Then go to the Hazard3 repository and build the simulator. You should be able to run the hello world binary you compiled earlier:

```bash
cd test/sim/tb_verilator
make tb
./tb --bin ../hellow/tmp/hellow.bin
```

# Building an Example SoC

There is a tiny [example SoC](example_soc/soc/example_soc.v) which builds on iCEBreaker, ULX3S and Arty A7-100T boards. The SoC contains:

- A Hazard3 processor, in a single-ported RV32IMA configuration, with debug support
- A Debug Transport Module and Debug Module to access Hazard3's debug interface
- 128 kB of RAM (fits in UP5k SPRAMs)
- A UART
- A standard RISC-V platform timer

Note there is no software tree for this SoC. For now you'll have to read the source and hack on the test software build. At least you can attach to the processor, poke registers/memory, and convince yourself you really are debugging a RISC-V core.

## Comparison of Supported Boards

On [iCEBreaker](https://1bitsquared.com/products/icebreaker) (a iCE40 UP5k development board), the processor can be debugged using the onboard FT2232H bridge, through a standard RISCV-V JTAG-DTM exposed on four IO pins. Connecting JTAG requires two solder jumpers to be bridged on the back to connect the JTAG -- see the comments in the [pin constraints file](example_soc/synth/fpga_icebreaker.pcf). FT2232H is a dual-channel FTDI device, so the UART and JTAG can be accessed simultaneously for a very civilised debug experience, with JTAG running at the full 30 MHz supported by the FTDI.

[ULX3S](https://radiona.org/ulx3s/) is based on a much larger ECP5 FPGA. Thanks to [this ECP5 JTAG adapter](hdl/debug/dtm/hazard3_ecp5_jtag_dtm.v), it is possible to attach the guts of a RISC-V JTAG-DTM to the custom DR hooks in ECP5's chip TAP. With the right config file you can then convince OpenOCD that the FPGA's own TAP *is* a JTAG-DTM. You can debug Hazard3 on ULX3S using the same micro USB cable you use to load the bitstream, no soldering required. The downside is that the FT231X device on the ULX3S is actually a UART bridge which supports JTAG by bitbanging the auxiliary UART signals, which is incredibly slow. The UART cannot be used simultaneously with JTAG access. The debugging experience is worse than iCEBreaker because of this.

Arty A7-100T uses an Artix-7 FPGA. This is the fastest and most capacious of the boards supported by this example SoC integration, but it's also the most expensive. The board has an FT2232H debug probe, similar to iCEBreaker. The probe is intended for programming the FPGA, or for Xilinx debug functionality like ILA. Using the probe, you can tunnel RISC-V debug traffic through the Artix-7 chip TAP [in a similar way](hdl/debug/dtm/hazard3_xilinx7_jtag_dtm.v) to ECP5, using the `BSCANE2` primitive. There is no performance cost to this tunnelling as the DTM registers are exposed directly as DRs on the FPGA chip TAP, so this is an excellent combination of a fast FPGA and a fast debug interface.

## Building for iCEBreaker

You must have `nextpnr-ice40`, `yosys`, and `iceprog` (from icestorm) on your PATH.

```bash
cd hazard3
cd example_soc/synth
make -f Icebreaker.mk prog
# Should be able to attach to the processor
riscv-openocd -f ../icebreaker-openocd.cfg
```

## Building for ULX3S

You must have `nextpnr-ecp5`, `yosys` and [ujprog](https://github.com/f32c/tools/blob/master/ujprog/README.md) on your PATH.

```bash
cd hazard3
cd example_soc/synth
make -f ULX3S.mk flash
# Should be able to attach to the processor
riscv-openocd -f ../ulx3s-openocd.cfg
```

## Building for Arty A7-100T

These scripts use Vivado to build and load the bitstream. You must have `vivado` on your `PATH`; I used version 2025.1. The free version of Vivado supports the A7-100T, so just type some swear words into AMD's export compliance form and away you go.

```bash
cd hazard3
cd example_soc/synth_vivado
make prog
# Should be able to attach to the processor
riscv-openocd -f ../arty7-openocd.cfg
```

Vivado and OpenOCD cannot simultaneously connect to the FTDI. If OpenOCD is connected then Vivado will fail to reprogram the FPGA.

# Performance

## RP2350

The RP2350 configuration of Hazard3 achieves 4.15 CoreMark/MHz.

```
2K performance run parameters for coremark.
CoreMark Size    : 666
Total ticks      : 14440822
Total time (secs): 14.440822
Iterations/Sec   : 4.154888
Iterations       : 60
Compiler version : GCC15.1.0
Compiler flags   : -O3 -g -march=rv32ima_zicsr_zifencei_zba_zbb_zbkb_zbs -mbranch-cost=1 -funroll-all-loops --param max-inline-insns-auto=200 -finline-limit=10000 -fno-code-hoisting -fno-if-conversion2 -DPERFORMANCE_RUN=1  
Memory location  : STACK
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0xa14c
Correct operation validated. See README.md for run and reporting rules.
CoreMark 1.0 : 4.154888 / GCC15.1.0 -O3 -g -march=rv32ima_zicsr_zifencei_zba_zbb_zbkb_zbs -mbranch-cost=1 -funroll-all-loops --param max-inline-insns-auto=200 -finline-limit=10000 -fno-code-hoisting -fno-if-conversion2 -DPERFORMANCE_RUN=1   / STACK
```

To reproduce this in the RTL simulator, use the top-level Makefile in [test/sim/coremark](test/sim/coremark) after you have followed all the steps to get set up for running a "Hello, world!" binary above. Expect the simulation to take a couple of minutes.

```bash
cd test/sim/coremark
make
```

The default flags are appropriate for the non-multilib toolchain build, and achieve 4.10 CoreMark/MHz. To achieve the full 4.15 CoreMark/MHz, change the ISA variant in `core_portme.mak` to `rv32ima_zicsr_zifencei_zba_zbb_zbkb_zbs`. See the comments in that file for an explanation of why this makes a difference.

See the RP2350 datasheet for details of the Hazard3 configuration used by that chip. The default `tb_cxxrtl` build uses the same configuration as RP2350, except that it also enables the Zbc extension (which is not emitted by GCC 14 as it is not useful for general-purpose code).

## Maximum

As of GCC 15, GCC can infer `clmul` and `clmulh` instructions in the CoreMark CRC function. The Zbc extension was dropped from the RP2350 configuration as compilers were not able to exploit it at the time. Enabling Zbc increases the score to 4.25 CoreMark/MHz.

```
CoreMark Size    : 666
Total ticks      : 14121622
Total time (secs): 14.121622
Iterations/Sec   : 4.248804
Iterations       : 60
Compiler version : GCC15.1.0
Compiler flags   : -O3 -g -march=rv32ima_zicsr_zifencei_zba_zbb_zbkb_zbs_zbc -mbranch-cost=1 -funroll-all-loops --param max-inline-insns-auto=200 -finline-limit=10000 -fno-code-hoisting -fno-if-conversion2 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -DPERFORMANCE_RUN=1  
Memory location  : STACK
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0xa14c
Correct operation validated. See README.md for run and reporting rules.
CoreMark 1.0 : 4.248804 / GCC15.1.0 -O3 -g -march=rv32ima_zicsr_zifencei_zba_zbb_zbkb_zbs_zbc -mbranch-cost=1 -funroll-all-loops --param max-inline-insns-auto=200 -finline-limit=10000 -fno-code-hoisting -fno-if-conversion2 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -DPERFORMANCE_RUN=1   / STACK
```

## RV32E

Reducing the number of GPRs from 31 to 15 carries around a 5% penalty, at 4.02 CoreMark/MHz.

```
2K performance run parameters for coremark.
CoreMark Size    : 666
Total ticks      : 14908801
Total time (secs): 14.908801
Iterations/Sec   : 4.024469
Iterations       : 60
Compiler version : GCC15.1.0
Compiler flags   : -O3 -g -march=rv32ema_zba_zbb_zbc_zbkb_zbkx_zbs_zicsr_zifencei -mabi=ilp32e -mbranch-cost=1 -funroll-all-loops --param max-inline-insns-auto=200 -finline-limit=10000 -fno-code-hoisting -fno-if-conversion2 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -DPERFORMANCE_RUN=1  
Memory location  : STACK
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0xa14c
Correct operation validated. See README.md for run and reporting rules.
CoreMark 1.0 : 4.024469 / GCC15.1.0 -O3 -g -march=rv32ema_zba_zbb_zbc_zbkb_zbkx_zbs_zicsr_zifencei -mabi=ilp32e -mbranch-cost=1 -funroll-all-loops --param max-inline-insns-auto=200 -finline-limit=10000 -fno-code-hoisting -fno-if-conversion2 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -DPERFORMANCE_RUN=1   / STACK
```
