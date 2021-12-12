Software Testcases
==================

A smorgasbord of software testcases for various features and cases that aren't well-covered by upstream tests such as `riscv-arch-test`, the `riscv-test` end-to-end debug tests or `riscv-formal`. Each test consists of one C file.

Some tests have an expected text output associated with them -- the test passes if this text output matches, and `main()` exits with a zero return code. Other tests are completely self-checking, reporting pass/fail only with the return code from `main()`. This means there is _no point_ running these tests if the processor is in a fundamentally broken state (e.g. doesn't pass ISA compliance) and can't be trusted to check itself.

For example, `hellow.c`:

```c
#include "tb_cxxrtl_io.h"

/*EXPECTED-OUTPUT***************************************************************

Hello world from Hazard3 + CXXRTL!

*******************************************************************************/

int main() {
	tb_puts("Hello world from Hazard3 + CXXRTL!\n");
	return 0;
}
```

The contents of the `EXPECTED-OUTPUT` comment is simply compared with the logged text from `tb_puts`, `tb_printf` etc. Tests might log a range of output here, such as `mcause` values in exceptions. The contents of this comment may have inline `//` comments embedded within, and these are stripped by the test script before comparing with the output. This is useful if some of the test output requires some brief inline explanation in the test source. 

To run the tests:

```bash
./runtests
```

This will first rebuild the simulator (`../tb_cxxrtl/`) if needed, then build and run all the software testcases, then print out a summary of test pass/fail status. The `./run_tests` executable itself returns a successful exit code if and only if all tests passed. A printf log will be created for each test, with the same name as the test, at `tmp/test_name.log`.

VCD waveform dumping is not enabled by default, because tests run faster without waves, and dumping waves for all tests uses > 1 GB of disk space. To re-run a failing test and get wave output, run:

```bash
make APP=test_name
```

This creates a VCD file at `tmp/test_name_run.vcd`.

To clean up the junk:

```bash
./cleantests
```
