# Contributing

There are two main ways you can contribute to Hazard3: _pull requests_ and _issues_.

## Pull Requests

I am grateful for any of the following pull requests:

* New documentation, or fixes for existing documentation
* New tests, or syncing new versions of upstream tests
	* For upstream tests with downstream patches, please first raise a PR on the submodule for those upstream tests (just merging down is fine)
* Improvements and expansion to the example SoC
* Bug fixes for the example SoC
* Porting the example SoC to new FPGA platforms
	* Preferably ones supported by Yosys + nextpnr, with an inexpensive commercially-available development board that I can order for testing
* Improvements to automation and scripting
* Improvements to RTL in project dependencies like `example_soc/libfpga/`
* General project maintenance (such as fixing accidental use of SSH URLs for submodules)

Please do not raise pull requests for the following:

* Changes to RTL sources in the top-level `hdl/` directory
* Cosmetic changes (except for comment-only changes)

### Changes to Core RTL

I do not merge pull requests which modify hardware sources in the `hdl/` directory. I close these pull requests without reading the patch.

The contents of the `hdl/` directory have a single author. I will not expose people taping out Hazard3 to the possibility of your employer chasing you for your contribution by harassing them legally. A contribution agreement does not solve this, because you may sign it without the legal capability to do so, and **what is taped out cannot be taped back in.**

If you are reading this as a software engineer, please understand that the ASIC industry is more hostile to open-source projects than the software industry is, and I am trying my hardest to build a core that other people can safely use.

(I am not trying to be obstructive; if a community fork of Hazard3 gets traction I am happy to contribute and help out with issues and questions. However, the core RTL in this repository will remain single-author.)

Do not raise issues with suggested code changes to core RTL. This is the same thing as a pull request, and I will close the issue without reading the patch. Please clearly identify the issue and I will fix it.

## Issues

There are three main categories of issues which are helpful to the project: _bug reports_, _feature requests_ and _questions_.

### Bug Reports

If you find a bug in the Hazard3 repository, please report it. This includes:

1. A functional bug in Hazard3 such as mis-execution, or ISA non-compliance
2. A compatibility issue with your tools
	* Please do not raise cosmetic lint issues: the intersection of clean Verilog across all lint tools is the empty set. Hazard3 is lint-clean with Verilator lint.
	* A lint issue relating to simulation/synthesis mismatch is important though, and falls under point **1** above.
3. An incorrect or incomplete statement in documentation
4. A test which fails when it should pass, or vice versa

#### Reproducibility

Before I fix a bug I must reproduce it on my own machine. I cannot fix issues on faith as this is unlikely to result in a reliable or complete fix. Please include the following in a bug report to ensure I can reproduce the issue:

* A description of expected behaviour
* A description of actual, observed behaviour (which differs from expected)
* A description of the platform where you observed the issue
	* Preferred platforms are the CXXRTL simulator, and the iCEBreaker and ULX3S FPGA SoCs
	* You can attach a patch for a preferred platform if it is necessary to reproduce the issue
* All files necessary to reproduce the issue
	* For software the minimum is an ELF and disassembly file for your binary
	* Do not strip symbols from ELF files
	* Please attach source code if possible (but the ELF is more important as I may not be able to reproduce your build exactly)
* A sequence of bash commands which can be invoked on the above files to reproduce the faulty behaviour

I develop Hazard3 on the latest Ubuntu LTS release (currently 24.04) and testing your reproduction on this platform is much appreciated.

### Feature Requests

I am happy to field feature requests. Please be aware the answer may be "no" for any of the following reasons:

* Future maintenance burden which I feel is excessive
* Impact on performance or functionality of existing features
* I don't like the feature, for reasons of aesthetics or toolchain compatibility
* I don't expect to have time to implement the feature in a reasonable timeframe

Please describe **why** the requested feature is useful. This helps me prioritise the request, and I might realise I also want this feature!

I am overwhelmingly more likely to implement requests for standard RISC-V ISA features than custom ones. As a rule, I don't implement standard RISC-V features that are not at least in the Frozen state. Please also consider the availability of toolchain support and upstream tests.

### Questions

The following questions are relevant to this repository and I am happy to answer them:

* Questions about Hazard3's implementation-defined behaviour in relation to the RISC-V standards
* Questions about tools used to build the Hazard3 simulator or tests (which are not covered by [Readme.md](Readme.md))

The following questions are not relevant and I am likely to either ignore or close them:

* Questions about Verilog
	* The IEEE 1364-2005 PDF can be found online
	* The best way to learn is to just do it ([instructional video](https://www.youtube.com/watch?v=ZXsQAXx_ao0))
	* Get an FPGA board like an iCEBreaker and get hacking
	* Yosys and nextpnr are great if you are already familiar with software tooling
	* Start with blinking an LED, then PWM the LED, then implement UART TX, then UART RX
* Questions about the RISC-V ISA
	* Get the latest ISA manual [here](https://github.com/riscv/riscv-isa-manual/releases/latest) (you want the _unprivileged_ manual first -- I find the HTML version more readable these days)
	* There are some excellent books on the topic. I recommend the RISC-V edition of _Computer Organization and Design_ by Patterson & Hennessy for a gentle introduction to computer architecture as well as the RISC-V ISA.
* Questions which are not questions, i.e. telling me how clever you are
	* I have ChatGPT for this purpose
