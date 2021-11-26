Random Bitmanip Test Vectors
============================

At time of writing there are no upstream compliance tests for the new bitmanip extensions.

So, generate some constrained-random input vectors, and run them against the [reference simulator](https://github.com/riscv-software-src/riscv-isa-sim) to get golden output vectors. Not perfect, but enough to give me some confidence in my implementation until the official tests come out.

People on the mailing lists seem to defer to spike over the pseudocode in the spec anyway, so that is probably a better verification target than trying to write my own vectors based on my own interpretation of the spec.

