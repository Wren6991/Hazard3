# Hazard3

Hazard3 is a 3-stage RV32IMC processor based on Hazard5. The stages are:

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

Merging the decode and execute stages shouldn't have too much effect on overall cycle time, which on Hazard5 is dominated by branch target decode in `D` being presented to the bus. On Hazard3, the branch target decode is much the same, except branch direction is now resolved in parallel with the branch target decode (as the ALU will be physically alongside the branch address adder) and all jumps/branches will be presented in stage 2 of the pipeline. The branch timings on Hazard5, with its static branch prediction, were:

- `JAL`: 2 cycles
- `JALR`: 4 cycles (this includes `RET`!)
- Backward branch taken: 2 cycles
- Backward branch nontaken (mispredict): 4 cycles
- Forward branch taken (mispredict): 4 cycles
- Forward branch nontaken: 1 cycle

On Hazard3 the expectation is for all jumps and taken branches to take 2 cycles, and nontaken branches to take 1 cycle.

## Other Architectural Expansion

- A extension (at least `ll`/`sc`, AMOs would be nice but are easy to emulate)
- Don't half-ass exceptions -- particularly things like instruction fetch memory fault
- Debug
- Don't half-ass CSRs
- WFI instruction


# Exceptions

Exceptions have a number of sources:

- Instruction fetch (hresp captured and piped through to decode, flushed if fetch speculation was incorrect)
- Instruction decode (invalid instructions, or exception-causing instructions like ecall)
- CSR address decode
- Load/store address alignment (address phase)
- Load/store bus error (data phase)
- External interrupts
- Internal interrupts (timers etc)
- Debugger breakpoints
- Debugger single-step

Out of these the most troublesome is probably load/store bus error, as it *must* be associated with stage 3 of the pipeline, not with stage 2.

Therefore it may be best to take the exception branch from stage 3, kind of like a branch mispredict. This flush signal would inhibit side-effecting instructions in stage 2. In particular, the case of a load/store in stage 2 with a faulting load/store in stage 3. The sequence of events there is probably:

- Cycles m through n (maybe): data phase stall of instruction in stage 3
- Cycle n + 1: first cycle of error response. Error is registered locally.
- Cycle n + 2: Second cycle of error response. Exception branch is generated, and load/store in stage 2 is suppressed based on the registered flag.

