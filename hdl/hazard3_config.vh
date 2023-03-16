/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Hazard3 CPU configuration parameters

// To configure Hazard3 you can either edit this file, or set parameters on
// your top-level instantiation, it's up to you. These parameters are all
// plumbed through Hazard3's internal hierarchy to the appropriate places.

// If you add a parameter here, you should add a matching line to
// hazard3_config_inst.vh to propagate the parameter through module
// instantiations.

// ----------------------------------------------------------------------------
// Reset state configuration

// RESET_VECTOR: Address of first instruction executed.
parameter RESET_VECTOR        = 32'h00000000,

// MTVEC_INIT: Initial value of trap vector base. Bits clear in MTVEC_WMASK
// will never change from this initial value. Bits set in MTVEC_WMASK can be
// written/set/cleared as normal.
//
// Note that mtvec bits 1:0 do not affect the trap base (as per RISC-V spec).
// Bit 1 is don't care, bit 0 selects the vectoring mode: unvectored if == 0
// (all traps go to mtvec), vectored if == 1 (exceptions go to mtvec, IRQs to
// mtvec + mcause * 4). This means MTVEC_INIT also sets the initial vectoring
// mode.
parameter MTVEC_INIT          = 32'h00000000,

// ----------------------------------------------------------------------------
// Standard RISC-V ISA support

// EXTENSION_A: Support for atomic read/modify/write instructions
parameter EXTENSION_A         = 1,

// EXTENSION_C: Support for compressed (variable-width) instructions
parameter EXTENSION_C         = 1,

// EXTENSION_M: Support for hardware multiply/divide/modulo instructions
parameter EXTENSION_M         = 1,

// EXTENSION_ZBA: Support for Zba address generation instructions
parameter EXTENSION_ZBA       = 0,

// EXTENSION_ZBB: Support for Zbb basic bit manipulation instructions
parameter EXTENSION_ZBB       = 0,

// EXTENSION_ZBC: Support for Zbc carry-less multiplication instructions
parameter EXTENSION_ZBC       = 0,

// EXTENSION_ZBS: Support for Zbs single-bit manipulation instructions
parameter EXTENSION_ZBS       = 0,

// EXTENSION_ZBKB: Support for Zbkb basic bit manipulation for cryptography
// Requires: Zbb. (This flag enables instructions in Zbkb which aren't in Zbb.)
parameter EXTENSION_ZBKB      = 0,

// EXTENSION_ZCB: Support for ZCB basic additional compressed instructions
// Requires: C. (Some Zcb instructions also require Zbb or M.)
// Note Zca is equivalent to C, as we do not support the F extension.
parameter EXTENSION_ZCB       = 0,

// EXTENSION_ZIFENCEI: Support for the fence.i instruction
// Optional, since a plain branch/jump will also flush the prefetch queue.
parameter EXTENSION_ZIFENCEI  = 0,

// ----------------------------------------------------------------------------
// Custom RISC-V extensions

// EXTENSION_XH3B: Custom bit-extract-multiple instructions for Hazard3
parameter EXTENSION_XH3BEXTM  = 0,

// EXTENSION_XH3IRQ: Custom preemptive, prioritised interrupt support. Can be
// disabled if an external interrupt controller (e.g. PLIC) is used. If
// disabled, and NUM_IRQS > 1, the external interrupts are simply OR'd into
// mip.meip.
parameter EXTENSION_XH3IRQ    = 0,

// EXTENSION_XH3PMPM: PMPCFGMx CSRs to enforce PMP regions in M-mode without
// locking. Unlike ePMP mseccfg.rlb, locked and unlocked regions can coexist
parameter EXTENSION_XH3PMPM   = 0,

// EXTENSION_XH3POWER: Custom power management controls for Hazard3
parameter EXTENSION_XH3POWER  = 0,

// ----------------------------------------------------------------------------
// Standard CSR support

// Note the Zicsr extension is implied by any of CSR_M_MANDATORY, CSR_M_TRAP,
// CSR_COUNTER.

// CSR_M_MANDATORY: Bare minimum CSR support e.g. misa. Spec says must = 1 if
// CSRs are present, but I won't tell anyone.
parameter CSR_M_MANDATORY     = 1,

// CSR_M_TRAP: Include M-mode trap-handling CSRs, and enable trap support.
parameter CSR_M_TRAP          = 1,

// CSR_COUNTER: Include performance counters and Zicntr CSRs
parameter CSR_COUNTER         = 0,

// U_MODE: Support the U (user) execution mode. In U mode, the core performs
// unprivileged bus accesses, and software's access to CSRs is restricted.
// Additionally, if the PMP is included, the core may restrict U-mode
// software's access to memory.
// Requires: CSR_M_TRAP.
parameter U_MODE              = 0,

// PMP_REGIONS: Number of physical memory protection regions, or 0 for no PMP.
// PMP is more useful if U mode is supported, but this is not a requirement.
parameter PMP_REGIONS         = 0,

// PMP_GRAIN: This is the "G" parameter in the privileged spec. Minimum PMP
// region size is 1 << (G + 2) bytes.  If G > 0, PMCFG.A can not be set to
// NA4 (will get set to OFF instead). If G > 1, the G - 1 LSBs of pmpaddr are
// read-only-0 when PMPCFG.A is OFF, and read-only-1 when PMPCFG.A is NAPOT.
parameter PMP_GRAIN           = 0,

// PMPADDR_HARDWIRED: If a bit is 1, the corresponding region's pmpaddr and
// pmpcfg registers are read-only. PMP_GRAIN is ignored on hardwired regions.
// It's recommended to make hardwired regions the highest-numbered, so they
// can be overridden by lower-numbered regions.
parameter PMP_HARDWIRED       = PMP_REGIONS > 0 ? {PMP_REGIONS{1'b0}} : 1'b0,

// PMPADDR_HARDWIRED_ADDR: Values of pmpaddr registers whose PMP_HARDWIRED
// bits are set to 1. Non-hardwired regions reset to all-zeroes.
parameter PMP_HARDWIRED_ADDR  = PMP_REGIONS > 0 ? {PMP_REGIONS{32'h0}} : 1'b0,

// PMPCFG_RESET_VAL: Values of pmpcfg registers whose PMP_HARDWIRED bits are
// set to 1. Non-hardwired regions reset to all zeroes.
parameter PMP_HARDWIRED_CFG   = PMP_REGIONS > 0 ? {PMP_REGIONS{8'h00}} : 1'b0,

// DEBUG_SUPPORT: Support for run/halt and instruction injection from an
// external Debug Module, support for Debug Mode, and Debug Mode CSRs.
// Requires: CSR_M_MANDATORY, CSR_M_TRAP.
parameter DEBUG_SUPPORT       = 0,

// BREAKPOINT_TRIGGERS: Number of triggers which support type=2 execute=1
// (but not store/load=1, i.e. not a watchpoint). Requires: DEBUG_SUPPORT
parameter BREAKPOINT_TRIGGERS = 0,

// ----------------------------------------------------------------------------
// External interrupt support

// NUM_IRQS: Number of external IRQs. Minimum 1, maximum 512. Note that if
// EXTENSION_XH3IRQ (Hazard3 interrupt controller) is disabled then multiple
// external interrupts are simply OR'd into mip.meip.
parameter NUM_IRQS            = 1,

// IRQ_PRIORITY_BITS: Number of priority bits implemented for each interrupt
// in meipra, if EXTENSION_XH3IRQ is enabled. The number of distinct levels
// is (1 << IRQ_PRIORITY_BITS). Minimum 0, max 4. Note that multiple priority
// levels with a large number of IRQs will have a severe effect on timing.
parameter IRQ_PRIORITY_BITS   = 0,

// IRQ_INPUT_BYPASS: disable the input registers on the external interrupts,
// to reduce latency by one cycle. Can be applied on an IRQ-by-IRQ basis.
// Ignored if EXTENSION_XH3IRQ is disabled.
parameter IRQ_INPUT_BYPASS    = {NUM_IRQS{1'b0}},

// ----------------------------------------------------------------------------
// ID registers

// JEDEC JEP106-compliant vendor ID, can be left at 0 if "not implemented or
// [...] this is a non-commercial implementation" (RISC-V spec).
// 31:7 is continuation code count, 6:0 is ID. Parity bit is not stored.
parameter MVENDORID_VAL       = 32'h0,

// Implementation ID for this specific version of Hazard3. Git hash is perfect.
parameter MIMPID_VAL          = 32'h0,

// Each core has a single hardware thread. Multiple cores should have unique IDs.
parameter MHARTID_VAL         = 32'h0,

// Pointer to configuration structure blob, or all-zeroes. Must be at least
// 4-byte-aligned.
parameter MCONFIGPTR_VAL      = 32'h0,

// ----------------------------------------------------------------------------
// Performance/size options

// REDUCED_BYPASS: Remove all forwarding paths except X->X (so back-to-back
// ALU ops can still run at 1 CPI), to save area.
parameter REDUCED_BYPASS      = 0,

// MULDIV_UNROLL: Bits per clock for multiply/divide circuit, if present. Must
// be a power of 2.
parameter MULDIV_UNROLL       = 1,

// MUL_FAST: Use single-cycle multiply circuit for MUL instructions, retiring
// to stage 3. The sequential multiply/divide circuit is still used for MULH*
parameter MUL_FAST            = 0,

// MUL_FASTER: Retire fast multiply results to stage 2 instead of stage 3.
// Throughput is the same, but latency is reduced from 2 cycles to 1 cycle.
// Requires: MUL_FAST.
parameter MUL_FASTER          = 0,

// MULH_FAST: extend the fast multiply circuit to also cover MULH*, and remove
// the multiply functionality from the sequential multiply/divide circuit.
// Requires: MUL_FAST
parameter MULH_FAST           = 0,

// FAST_BRANCHCMP: Instantiate a separate comparator (eq/lt/ltu) for branch
// comparisons, rather than using the ALU. Improves fetch address delay,
// especially if Zba extension is enabled. Disabling may save area.
parameter FAST_BRANCHCMP      = 1,

// RESET_REGFILE: whether to support reset of the general purpose registers.
// There are around 1k bits in the register file, so the reset can be
// disabled e.g. to permit block-RAM inference on FPGA.
parameter RESET_REGFILE       = 0,

// BRANCH_PREDICTOR: enable branch prediction. The branch predictor consists
// of a single BTB entry which is allocated on a taken backward branch, and
// cleared on a mispredicted nontaken branch, a fence.i or a trap. Successful
// prediction eliminates the 1-cyle fetch bubble on a taken branch, usually
// making tight loops faster.
parameter BRANCH_PREDICTOR    = 0,

// MTVEC_WMASK: Mask of which bits in mtvec are writable. Full writability is
// recommended, because a common idiom in setup code is to set mtvec just
// past code that may trap, as a hardware "try {...} catch" block.
//
// - The vectoring mode can be made fixed by clearing the LSB of MTVEC_WMASK
//
// - In vectored mode, the vector table must be aligned to its size, rounded
//   up to a power of two.
parameter MTVEC_WMASK         = 32'hfffffffd,

// ----------------------------------------------------------------------------
// Port size parameters (do not modify)

parameter W_ADDR              = 32,   // Do not modify
parameter W_DATA              = 32    // Do not modify
