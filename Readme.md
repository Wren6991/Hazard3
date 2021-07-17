# Hazard3

Hazard3 is a 3-stage RISC-V processor, providing the following architectural support:

* `RV32I`: 32-bit base instruction set
* `M` extension: integer multiply/divide/modulo
* `C` extension: compressed instructions
* `Zicsr` extension: CSR access
* M-mode privileged instructions `ECALL`, `EBREAK`, `MRET`
* The machine-mode (M-mode) privilege state, and standard M-mode CSRs
* Debug support, compliant with RISC-V debug specification version 0.13.2

You can [read the documentation here](doc/hazard3.pdf). (PDF link)

This repository also contains a compliant RISC-V Debug Module for Hazard3, which can be accessed over an AMBA 3 APB port or using the optional JTAG Debug Transport Module.

There is an [example SoC integration](example_soc/soc/example_soc.v), showing how these components can be assembled to create a minimal system with a JTAG-enabled RISC-V processor, some RAM and a serial port.

The following are planned for future implementation:

* Support for `WFI` instruction
* `A` extension: atomic memory access

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

This is essentially Hazard5, with the `D` and `X` stages merged and the register file brought forward. Many components are reused directly from Hazard5. The particular focus here is on shortening the branch delay, which is one of the weak points in Hazard5's IPC.
