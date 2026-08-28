# riscv-arch-test

To run tests:

```bash
./run.sh
```

The test framework has a baffling number of dependencies. I eliminated a lot of them (Ruby + broken vendored Z3 binary) by inlining required UDB functionality into the Python test framework. You still need to install `uv`, and get the correct binary release of the SAIL ISA sim.
 
## SAIL ISA sim

Download prebuilt 0.13.1 from [here](https://github.com/riscv/sail-riscv/releases/tag/0.13.1)

I extracted the tarball contents as: `/opt/riscv/sail/*`, so e.g. the sail binary is `/opt/riscv/sail/bin/sail_riscv_sim`. The upstream test suite has some hardcoded paths that assume you splat `share`, `bin` etc directly under `/opt`, but I don't do this for hygiene reasons, so the paths are modified.

You still need `/opt/riscv/sail/bin` on your `$PATH`.

## Other Prerequisites

Just install `uv`. E.g. on MacOS:

```bash
brew install uv
```

You don't need `mise`, Ruby etc. Ignore the instructions in the `riscv-arch-test` repository.