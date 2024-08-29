# Hazard3

Hazard3 is a 3-stage RISC-V processor, implementing the `RV32I` instruction set and the following optional extensions:

* `M`: integer multiply/divide/modulo
* `A` : atomic memory operations, with AHB5 global exclusives
* `C`: compressed instructions
* `Zicsr`: CSR access
* `Zba`: address generation
* `Zbb`: basic bit manipulation
* `Zbc`: carry-less multiplication
* `Zbs`: single-bit manipulation
* `Zbkb`: basic bit manipulation for scalar cryptography
* `Zcb`: basic additional compressed instructions
* `Zcmp`: push/pop instructions
* Debug, Machine and User privilege/execution modes
* Privileged instructions `ecall`, `ebreak`, `mret` and `wfi`
* Physical memory protection (PMP) with up to 16 naturally aligned regions (NA4 / NAPOT address matching, TOR not supported)

You can [read the documentation here](https://github.com/Wren6991/Hazard3/releases/download/v1.0/hazard3.pdf). (PDF link)

This repository also contains a compliant RISC-V Debug Module for Hazard3, which can be accessed over an AMBA 3 APB port or using the optional JTAG Debug Transport Module.

The [example SoC integration](example_soc/soc/example_soc.v) shows how these components can be assembled to create a minimal system with a JTAG-enabled RISC-V processor, some RAM and a serial port.

Please read [Contributing.md](Contributing.md) before raising an issue or pull request.

For the latest stable release, check out the [stable](https://github.com/Wren6991/Hazard3/tree/stable) branch. For the latest work-in-progress code including new experimental features, check out the [develop](https://github.com/Wren6991/Hazard3/tree/develop) branch.

# Links to Specifications

These are links to the ratified versions of the extensions.

| Extension  | Specification |
|----------- |---------------|
| `RV32I` v2.1 | [Unprivileged ISA 20191213](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf) |
| `M` v2.0 | [Unprivileged ISA 20191213](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf) |
| `A` v2.1 | [Unprivileged ISA 20191213](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf) |
| `C` v2.0 | [Unprivileged ISA 20191213](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf) |
| `Zicsr` v2.0 | [Unprivileged ISA 20191213](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf) |
| `Zifencei` v2.0 | [Unprivileged ISA 20191213](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf) |
| `Zba` v1.0.0 | [Bit Manipulation ISA extensions 20210628](https://github.com/riscv/riscv-bitmanip/releases/download/1.0.0/bitmanip-1.0.0-38-g865e7a7.pdf) |
| `Zbb` v1.0.0 | [Bit Manipulation ISA extensions 20210628](https://github.com/riscv/riscv-bitmanip/releases/download/1.0.0/bitmanip-1.0.0-38-g865e7a7.pdf) |
| `Zbc` v1.0.0 | [Bit Manipulation ISA extensions 20210628](https://github.com/riscv/riscv-bitmanip/releases/download/1.0.0/bitmanip-1.0.0-38-g865e7a7.pdf) |
| `Zbs` v1.0.0 | [Bit Manipulation ISA extensions 20210628](https://github.com/riscv/riscv-bitmanip/releases/download/1.0.0/bitmanip-1.0.0-38-g865e7a7.pdf) |
| `Zbkb` v1.0.1 | [Scalar Cryptography ISA extensions 20220218](https://github.com/riscv/riscv-crypto/releases/download/v1.0.1-scalar/riscv-crypto-spec-scalar-v1.0.1.pdf) |
| `Zcb` v1.0.3-1 | [Code Size Reduction extensions frozen v1.0.3-1](https://github.com/riscv/riscv-code-size-reduction/releases/download/v1.0.3-1/Zc-v1.0.3-1.pdf) |
| `Zcmp` v1.0.3-1 | [Code Size Reduction extensions frozen v1.0.3-1](https://github.com/riscv/riscv-code-size-reduction/releases/download/v1.0.3-1/Zc-v1.0.3-1.pdf) |
| Machine ISA v1.12 | [Privileged Architecture 20211203](https://github.com/riscv/riscv-isa-manual/releases/download/Priv-v1.12/riscv-privileged-20211203.pdf) |
| Debug v0.13.2 | [RISC-V External Debug Support 20190322](https://riscv.org/wp-content/uploads/2019/03/riscv-debug-release.pdf) |

These specifications are abstract descriptions of the architectural features that Hazard3 implements. The [Hazard3 documentation](doc/hazard3.pdf) is a concrete description of how it implements them, especially in regard to the privileged ISA and debug support.

# Cloning This Repository

For the purpose of using Hazard3 in your design, this repository is self-contained. You need the submodules for simulation scripts, compliance tests and example SoC components:

```bash
git clone --recursive https://github.com/Wren6991/Hazard3.git hazard3
```

To initialise submodules in an already-cloned repository:

```bash
git submodule update --init --recursive
```

# Running Hello World

These instructions walk through:

* Setting up the tools for building the Hazard3 simulator from Verilog source
* Setting up the tools for building RISC-V binaries to run on the simulator
* Building a "Hello, world!" binary and running it on the simulator

These instructions are for Ubuntu 24.04. If you are running on Windows you may have some success with Ubuntu under WSL.

You will need:

* A recent Yosys build to process the Verilog (these instructions were last tested with `b1569de5`)
* A `riscv32-unknown-elf-` toolchain to build software for the core
* A native `clang-16` to build the simulator

`clang-17` is also known to work fine. `clang-18` does work, but has a serious compile time regression with CXXRTL output, which is why the `tb_cxxrtl` Makefile explicitly selects `clang-16`.

## Yosys

The [Yosys GitHub repo](https://github.com/YosysHQ/yosys) has instructions for building Yosys from source.

The following steps work for me on Ubuntu 24.04 using version `b1569de5` mentioned above.

```bash
sudo apt install build-essential clang lld bison flex libreadline-dev gawk tcl-dev libffi-dev git graphviz xdot pkg-config python3 libboost-system-dev libboost-python-dev libboost-filesystem-dev zlib1g-dev

git clone https://github.com/YosysHQ/yosys.git
cd yosys
git submodule update --init
make -j$(nproc)
sudo make install
```

## RISC-V Toolchain

I recommend building a toolchain to get libraries with the correct ISA support. Follow the below instructions to build a 32-bit GCC 14 version of the [RISC-V GNU toolchain](https://github.com/riscv/riscv-gnu-toolchain) with a multilib setup suitable for Hazard3 development.

```bash
# Prerequisites for Ubuntu 24.04
sudo apt install autoconf automake autotools-dev curl python3 python3-pip libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev ninja-build git cmake libglib2.0-dev libslirp-dev

cd /tmp
git clone https://github.com/riscv/riscv-gnu-toolchain
cd riscv-gnu-toolchain
git clone --depth=1 https://github.com/gcc-mirror/gcc gcc-14 -b releases/gcc-14
./configure --with-gcc-src=$(pwd)/gcc-14 --prefix=/opt/riscv/gcc14-no-zcmp --with-arch=rv32ia_zicsr --with-abi=ilp32 --with-multilib-generator="rv32i-ilp32--;rv32im-ilp32--;rv32ia-ilp32--;rv32ima-ilp32--;rv32ic-ilp32--;rv32imc-ilp32--;rv32iac-ilp32--;rv32imac-ilp32--;rv32i_zicsr-ilp32--;rv32im_zicsr-ilp32--;rv32ia_zicsr-ilp32--;rv32ima_zicsr-ilp32--;rv32ic_zicsr-ilp32--;rv32imc_zicsr-ilp32--;rv32iac_zicsr-ilp32--;rv32imac_zicsr-ilp32--;rv32i_zicsr_zifencei-ilp32--;rv32im_zicsr_zifencei-ilp32--;rv32ia_zicsr_zifencei-ilp32--;rv32ima_zicsr_zifencei-ilp32--;rv32ic_zicsr_zifencei-ilp32--;rv32imc_zicsr_zifencei-ilp32--;rv32iac_zicsr_zifencei-ilp32--;rv32imac_zicsr_zifencei-ilp32--;rv32im_zba_zbb_zbs-ilp32--;rv32ima_zba_zbb_zbs-ilp32--;rv32imc_zba_zbb_zbs-ilp32--;rv32imac_zba_zbb_zbs-ilp32--;rv32im_zicsr_zba_zbb_zbs-ilp32--;rv32ima_zicsr_zba_zbb_zbs-ilp32--;rv32imc_zicsr_zba_zbb_zbs-ilp32--;rv32imac_zicsr_zba_zbb_zbs-ilp32--;rv32im_zicsr_zifencei_zba_zbb_zbs-ilp32--;rv32ima_zicsr_zifencei_zba_zbb_zbs-ilp32--;rv32imc_zicsr_zifencei_zba_zbb_zbs-ilp32--;rv32imac_zicsr_zifencei_zba_zbb_zbs-ilp32--;rv32im_zba_zbb_zbs_zbkb-ilp32--;rv32ima_zba_zbb_zbs_zbkb-ilp32--;rv32imc_zba_zbb_zbs_zbkb-ilp32--;rv32imac_zba_zbb_zbs_zbkb-ilp32--;rv32im_zicsr_zba_zbb_zbs_zbkb-ilp32--;rv32ima_zicsr_zba_zbb_zbs_zbkb-ilp32--;rv32imc_zicsr_zba_zbb_zbs_zbkb-ilp32--;rv32imac_zicsr_zba_zbb_zbs_zbkb-ilp32--;rv32im_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--;rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--;rv32imc_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--;rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--;rv32im_zba_zbb_zbc_zbs_zbkb-ilp32--;rv32ima_zba_zbb_zbc_zbs_zbkb-ilp32--;rv32imc_zba_zbb_zbc_zbs_zbkb-ilp32--;rv32imac_zba_zbb_zbc_zbs_zbkb-ilp32--;rv32im_zicsr_zba_zbb_zbc_zbs_zbkb-ilp32--;rv32ima_zicsr_zba_zbb_zbc_zbs_zbkb-ilp32--;rv32imc_zicsr_zba_zbb_zbc_zbs_zbkb-ilp32--;rv32imac_zicsr_zba_zbb_zbc_zbs_zbkb-ilp32--;rv32im_zicsr_zifencei_zba_zbb_zbc_zbs_zbkb-ilp32--;rv32ima_zicsr_zifencei_zba_zbb_zbc_zbs_zbkb-ilp32--;rv32imc_zicsr_zifencei_zba_zbb_zbc_zbs_zbkb-ilp32--;rv32imac_zicsr_zifencei_zba_zbb_zbc_zbs_zbkb-ilp32--;rv32i_zca-ilp32--;rv32im_zca-ilp32--;rv32ia_zca-ilp32--;rv32ima_zca-ilp32--;rv32i_zicsr_zca-ilp32--;rv32im_zicsr_zca-ilp32--;rv32ia_zicsr_zca-ilp32--;rv32ima_zicsr_zca-ilp32--;rv32i_zicsr_zifencei_zca-ilp32--;rv32im_zicsr_zifencei_zca-ilp32--;rv32ia_zicsr_zifencei_zca-ilp32--;rv32ima_zicsr_zifencei_zca-ilp32--;rv32im_zba_zbb_zbs_zca-ilp32--;rv32ima_zba_zbb_zbs_zca-ilp32--;rv32im_zicsr_zba_zbb_zbs_zca-ilp32--;rv32ima_zicsr_zba_zbb_zbs_zca-ilp32--;rv32im_zicsr_zifencei_zba_zbb_zbs_zca-ilp32--;rv32ima_zicsr_zifencei_zba_zbb_zbs_zca-ilp32--;rv32im_zba_zbb_zbs_zbkb_zca-ilp32--;rv32ima_zba_zbb_zbs_zbkb_zca-ilp32--;rv32im_zicsr_zba_zbb_zbs_zbkb_zca-ilp32--;rv32ima_zicsr_zba_zbb_zbs_zbkb_zca-ilp32--;rv32im_zicsr_zifencei_zba_zbb_zbs_zbkb_zca-ilp32--;rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca-ilp32--;rv32im_zba_zbb_zbc_zbs_zbkb_zca-ilp32--;rv32ima_zba_zbb_zbc_zbs_zbkb_zca-ilp32--;rv32im_zicsr_zba_zbb_zbc_zbs_zbkb_zca-ilp32--;rv32ima_zicsr_zba_zbb_zbc_zbs_zbkb_zca-ilp32--;rv32im_zicsr_zifencei_zba_zbb_zbc_zbs_zbkb_zca-ilp32--;rv32ima_zicsr_zifencei_zba_zbb_zbc_zbs_zbkb_zca-ilp32--;rv32i_zca_zcb-ilp32--;rv32im_zca_zcb-ilp32--;rv32ia_zca_zcb-ilp32--;rv32ima_zca_zcb-ilp32--;rv32i_zicsr_zca_zcb-ilp32--;rv32im_zicsr_zca_zcb-ilp32--;rv32ia_zicsr_zca_zcb-ilp32--;rv32ima_zicsr_zca_zcb-ilp32--;rv32i_zicsr_zifencei_zca_zcb-ilp32--;rv32im_zicsr_zifencei_zca_zcb-ilp32--;rv32ia_zicsr_zifencei_zca_zcb-ilp32--;rv32ima_zicsr_zifencei_zca_zcb-ilp32--;rv32im_zba_zbb_zbs_zca_zcb-ilp32--;rv32ima_zba_zbb_zbs_zca_zcb-ilp32--;rv32im_zicsr_zba_zbb_zbs_zca_zcb-ilp32--;rv32ima_zicsr_zba_zbb_zbs_zca_zcb-ilp32--;rv32im_zicsr_zifencei_zba_zbb_zbs_zca_zcb-ilp32--;rv32ima_zicsr_zifencei_zba_zbb_zbs_zca_zcb-ilp32--;rv32im_zba_zbb_zbs_zbkb_zca_zcb-ilp32--;rv32ima_zba_zbb_zbs_zbkb_zca_zcb-ilp32--;rv32im_zicsr_zba_zbb_zbs_zbkb_zca_zcb-ilp32--;rv32ima_zicsr_zba_zbb_zbs_zbkb_zca_zcb-ilp32--;rv32im_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb-ilp32--;rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb-ilp32--;rv32im_zba_zbb_zbc_zbs_zbkb_zca_zcb-ilp32--;rv32ima_zba_zbb_zbc_zbs_zbkb_zca_zcb-ilp32--;rv32im_zicsr_zba_zbb_zbc_zbs_zbkb_zca_zcb-ilp32--;rv32ima_zicsr_zba_zbb_zbc_zbs_zbkb_zca_zcb-ilp32--;rv32im_zicsr_zifencei_zba_zbb_zbc_zbs_zbkb_zca_zcb-ilp32--;rv32ima_zicsr_zifencei_zba_zbb_zbc_zbs_zbkb_zca_zcb-ilp32--"
sudo mkdir -p /opt/riscv/gcc14-no-zcmp
sudo chown $(whoami) /opt/riscv/gcc14-no-zcmp
make -j $(nproc)
```

The `--with-multilib-generator=` flag builds multiple versions of the standard library, to match possible `-march` flags provided at link time. Recent versions of GCC seem to remove the fallback to the `--with-arch` architecture when there is no exact match, so if you are developing for multiple ISA variants then you need a fairly expansive multilib setup. The multilib-generator command line above was generated using [multilib-gen-gen.py](test/sim/common/multilib-gen-gen.py)

As of writing (August 2024) there are issues with Zcmp support on `riscv-gnu-toolchain`. The above multilib command line excludes Zcmp from the library setup for this reason.

Make sure this toolchain can be found on your `PATH` (as `riscv32-unknown-elf-*`):

```bash
export PATH="$PATH:/opt/riscv/gcc14-no-zcmp/bin"
```

### Non-multilib (Smaller Install Size)

For a faster build and a smaller install size, use this `./configure` line instead:

```bash
./configure --with-gcc-src=$(pwd)/gcc-14 --prefix=/opt/riscv/gcc14-no-zcmp --with-arch=rv32imac_zicsr_zifencei_zba_zbb_zbkb_zbs --with-abi=ilp32
```

Adjust the `--with-arch` line as necessary for your Hazard3 configuration. You may need to adjust architectures used in software Makefiles in this repository to fit your chosen architecture variant.

You can also remove the `--with-gcc-src` flag if you would prefer to use the GCC version pinned by the toolchain repository.

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
Info : Note: The adapter "remote_bitbang" doesn't support configurable speed
Info : JTAG tap: hazard3.cpu tap/device found: 0xdeadbeef (mfg: 0x777 (Fabric of Truth Inc), part: 0xeadb, ver: 0xd)
Info : [hazard3.cpu] datacount=1 progbufsize=2
Info : [hazard3.cpu] Disabling abstract command reads from CSRs.
Info : [hazard3.cpu] Disabling abstract command writes to CSRs.
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

# Building an Example SoC

There is a tiny [example SoC](example_soc/soc/example_soc.v) which builds on both iCEBreaker and ULX3S. The SoC contains:

- A Hazard3 processor, in a single-ported RV32IMA configuration, with debug support
- A Debug Transport Module and Debug Module to access Hazard3's debug interface
- 128 kB of RAM (fits in UP5k SPRAMs)
- A UART

On iCEBreaker (a iCE40 UP5k development board), the processor can be debugged using the onboard FT2232H bridge, through a standard RISCV-V JTAG-DTM exposed on four IO pins. Connecting JTAG requires two solder jumpers to be bridged on the back to connect the JTAG -- see the comments in the [pin constraints file](example_soc/synth/fpga_icebreaker.pcf). FT2232H is a dual-channel FTDI device, so the UART and JTAG can be accessed simultaneously for a very civilised debug experience, with JTAG running at the full 30 MHz supported by the FTDI.

ULX3S is based on a much larger ECP5 FPGA. Thanks to [this ECP5 JTAG adapter](hdl/debug/dtm/hazard3_ecp5_jtag_dtm.v), it is possible to attach the guts of a RISC-V JTAG-DTM to the custom DR hooks in ECP5's chip TAP. With the right config file you can then convince OpenOCD that the FPGA's own TAP *is* a JTAG-DTM. You can debug Hazard3 on ULX3S using the same micro USB cable you use to load the bitstream, no soldering required. The downside is that the FT231X device on the ULX3S is actually a UART bridge which supports JTAG by bitbanging the auxiliary UART signals, which is incredibly slow. The UART cannot be used simultaneously with JTAG access. 

For these reasons -- much faster JTAG, and simultaneous UART access -- iCEBreaker is currently a more pleasant platform to debug if you don't have any external JTAG probe.

Note there is no software tree for this SoC. For now you'll have to read the source and hack on the test software build. All very much WIP. At least you can attach to the processor, poke registers/memory, and convince yourself you really are debugging a RISC-V core.

## Building for iCEBreaker

```bash
cd hazard3
cd example_soc/synth
make -f Icebreaker.mk prog
# Should be able to attach to the processor
riscv-openocd -f ../icebreaker-openocd.cfg
```

## Building for ULX3S

```bash
cd hazard3
cd example_soc/synth
make -f ULX3S.mk flash
# Should be able to attach to the processor
riscv-openocd -f ../ulx3s-openocd.cfg
```

# Performance

The RP2350 configuration of Hazard3 achieves 3.81 CoreMark/MHz.

```
2K performance run parameters for coremark.
CoreMark Size    : 666
Total ticks      : 15758494
Total time (secs): 15.758494
Iterations/Sec   : 3.807470
Iterations       : 60
Compiler version : GCC14.2.1 20240807
Compiler flags   : -O3 -g -march=rv32ima_zicsr_zifencei_zba_zbb_zbkb_zbs -mbranch-cost=1 -funroll-all-loops --param max-inline-insns-auto=200 -finline-limit=10000 -fno-code-hoisting -fno-if-conversion2 -DPERFORMANCE_RUN=1  
Memory location  : STACK
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0xa14c
Correct operation validated. See README.md for run and reporting rules.
CoreMark 1.0 : 3.807470 / GCC14.2.1 20240807 -O3 -g -march=rv32ima_zicsr_zifencei_zba_zbb_zbkb_zbs -mbranch-cost=1 -funroll-all-loops --param max-inline-insns-auto=200 -finline-limit=10000 -fno-code-hoisting -fno-if-conversion2 -DPERFORMANCE_RUN=1   / STACK
```

To reproduce this in the RTL simulator, use the top-level Makefile in [test/sim/coremark](test/sim/coremark) after you have followed all the steps to get set up for running a "Hello, world!" binary above.

The default flags are appropriate for the non-multilib toolchain build, and achieve 3.74 CoreMark/MHz. To achieve the full 3.81 CoreMark/MHz, change the ISA variant in `core_portme.mak` to `rv32ima_zicsr_zifencei_zba_zbb_zbkb_zbs`. See the comments in that file for an explanation of why this makes a difference.

See the RP2350 datasheet for details of the Hazard3 configuration used by that chip. The default `tb_cxxrtl` build uses the same configuration as RP2350, except that it also enables the Zbc extension (which is not emitted by GCC 14 as it is not useful for general-purpose code).
