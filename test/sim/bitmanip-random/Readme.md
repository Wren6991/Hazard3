Random Bitmanip Test Vectors
============================

At time of writing there are no upstream compliance tests for the new bitmanip extensions.

So, generate some constrained-random input vectors, and run them against the [reference simulator](https://github.com/riscv-software-src/riscv-isa-sim) to get golden output vectors. Not perfect, but enough to give me some confidence in my implementation until the official tests come out.

People on the mailing lists seem to defer to spike over the pseudocode in the spec anyway, so that is probably a better verification target than trying to write my own vectors based on my own interpretation of the spec.

The Python script `vector-gen` creates two directories:

- `test/` -- this contains assembly programs suitable for running on the Hazard3 CXXRTL testbench.
	- There is one test for each of the instructions in `Zba`/`Zbb`/`Zbc`/`Zbs`
	- The tests put a series of test values through that instruction, and write the results out to a test signature data section
	- The testbench is told to dump the signature section for comparison with the reference vectors
- `refgen/` this contains C programs suitable for running on the `spike` ISA simulator against the RISC-V proxy kernel `pk`
	- These put the same inputs through the same instructions (using inline asm), and then `printf` the results
	- The resulting reference vectors can be found here in the `reference/` directory. They're checked in so that you don't have to install spike/pk to run these tests.

To run all the tests and compare the results against the reference vectors, run

```bash
./vector-gen
make testall
```

To regenerate the reference vectors using the ISA simulator, run

```bash
./vector-gen
make makerefs
```
