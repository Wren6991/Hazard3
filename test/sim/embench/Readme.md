Embench
=======

To run these benchmarks, first make sure the embench-iot submodule is checked out, then:

```bash
cd embench-iot
# Make sure testbench is up to date
make -C ../../tb_cxxrtl tb
./build_all.py --arch riscv32 --chip hazard3 --board hazard3tb --clean
# You might need a longer timeout -- some sims are tens of millions of cycles
./benchmark_speed.py --target-module run_hazard3tb --timeout 180 --sim-parallel
```

The compiler specified in `config/riscv32/chips/hazard3/chip.cfg` is `riscv32-unknown-elf-gcc` (no directory prefix -- just whichever is on PATH). On my machine this is currently GCC12, which is the first stable release to have support for the bitmanip instructions. These instructions seem to be worth about 6% performance overall -- you can disable them in the `chip.cfg` file if your local gcc12 doesn't support them.

If you want to play with the Zcb/Zcmp instructions, these currently (March 2023) require the CORE-V development toolchains, and you will have to edit the `chip.cfg` accordingly.

## Caution on stdlib/multilib

Some of the Embench benchmarks are essentially benchmarks of the soft float routines in `libm`, which respond well to the bitmanip instructions. I have a rather sprawling multilib setup which ensures I get Zb instructions in my stdlib when I link with Zb in my `-march`. However, depending on the default architecture your toolchain was configured with, you might find that it falls back to something incredibly conservative like RV32I-only if there is no exact multilib match.

To give you an idea, here the left hand side is the speed benchmark result for `-O2 -ffunction-sections` on GCC 12 with `-march=rv32im_zba_zbb_zbs` and an RV32I stdlib, and the right hand side is with the correct standard library:

```
RV32IMZbaZbbZbs with RV32I library:         With correct standard library:

Benchmark           Speed                    Benchmark           Speed
---------           -----                    ---------           -----
aha-mont64         0.8323                    aha-mont64         0.8318
crc32              0.9209                    crc32              0.9593
cubic              0.1346                    cubic              0.5378
edn                1.1087                    edn                1.1460
huffbench          1.5361                    huffbench          1.6016
matmult-int        1.2319                    matmult-int        1.2308
minver             0.2693                    minver             0.7535
nbody              0.1901                    nbody              0.8496
nettle-aes         0.8800                    nettle-aes         1.0828
nettle-sha256      0.9981                    nettle-sha256      1.3922
nsichneu           1.1674                    nsichneu           1.1674
picojpeg           0.9904                    picojpeg           1.0812
primecount         1.5352                    primecount         1.3765
qrduino            1.3538                    qrduino            1.3717
sglib-combined     1.2075                    sglib-combined     1.2749
slre               1.3740                    slre               1.4178
st                 0.2250                    st                 1.0011
statemate          2.2047                    statemate          2.1999
tarfind            2.2567                    tarfind            2.2568
ud                 0.9269                    ud                 1.0073
wikisort           0.7946                    wikisort           1.9289
---------           -----                    ---------           -----
Geometric mean     0.8488                    Geometric mean     1.1905
Geometric SD       2.1454                    Geometric SD       1.4039
Geometric range    1.4254                    Geometric range    0.8233
All benchmarks run successfully              All benchmarks run successfully
```

(Hazard3 configuration: all ISA options enabled, FAST_MUL=1, FASTER_MUL=1, FAST_MULH=1, BRANCH_PREDICTOR=1, MULDIV_UNROLL=2, REDUCED_BYPASS=0)

Also note I don't run the MD5 benchmark because it tries to do a hosted printf inside of the benchmarked section (which is a known issue with Embench).

I haven't yet compiled a full set of benchmark results for Hazard3, partly because it means coming up with a list of specimen configurations and then doing hardware characterisation on them. This is just a note in case you try to run Embench and wonder why the performance is through the floor.
