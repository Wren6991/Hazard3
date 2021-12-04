Embench
=======

To run these benchmarks, first make sure the embench-iot submodule is checked out, then:

```bash
cd embench-iot
# Make sure testbench is up to date
make -C ../../tb_cxxrtl tb
./build_all.py --arch riscv32 --chip hazard3 --board hazard3tb
./benchmark_speed.py --target-module run_hazard3tb
```

The compiler specified in `config/riscv32/chips/hazard3/chip.cfg` is `/opt/riscv/unstable/bin/riscv32-unknown-elf-gcc`, which is where I have an unstable GCC 12 build installed on my machine. You need to have a recent upstream master build to support the Zba/Zbb/Zbc/Zbs instructions. If you don't care about these, you can use whatever `riscv32-unknown-elf` compiler you have, and also edit `cflags` in that `.cfg` file to not include the bitmanip extensions in `march`.
