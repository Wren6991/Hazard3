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
parameter RESET_VECTOR    = 32'h0,

// MTVEC_INIT: Initial value of trap vector base. Bits clear in MTVEC_WMASK
// will never change from this initial value. Bits set in MTVEC_WMASK can be
// written/set/cleared as normal.
//
// Note that, if CSR_M_TRAP is set, MTVEC_INIT should probably have a
// different value from RESET_VECTOR.
//
// Note that mtvec bits 1:0 do not affect the trap base (as per RISC-V spec).
// Bit 1 is don't care, bit 0 selects the vectoring mode: unvectored if == 0
// (all traps go to mtvec), vectored if == 1 (exceptions go to mtvec, IRQs to
// mtvec + mcause * 4). This means MTVEC_INIT also sets the initial vectoring
// mode.
parameter MTVEC_INIT      = 32'h00000000,

// ----------------------------------------------------------------------------
// RISC-V ISA and CSR support

// EXTENSION_A: Support for atomic read/modify/write instructions
// (currently, only lr.w/sc.w are supported)
parameter EXTENSION_A     = 1,

// EXTENSION_C: Support for compressed (variable-width) instructions
parameter EXTENSION_C     = 1,

// EXTENSION_M: Support for hardware multiply/divide/modulo instructions
parameter EXTENSION_M     = 1,

// EXTENSION_ZBA: Support for Zba address generation instructions
parameter EXTENSION_ZBA   = 1,

// EXTENSION_ZBB: Support for Zbb basic bit manipulation instructions
parameter EXTENSION_ZBB   = 1,

// EXTENSION_ZBC: Support for Zbc carry-less multiplication instructions
parameter EXTENSION_ZBC   = 1,

// EXTENSION_ZBS: Support for Zbs single-bit manipulation instructions
parameter EXTENSION_ZBS   = 1,

// CSR_M_MANDATORY: Bare minimum CSR support e.g. misa. Spec says must = 1 if
// CSRs are present, but I won't tell anyone.
parameter CSR_M_MANDATORY = 1,

// CSR_M_TRAP: Include M-mode trap-handling CSRs, and enable trap support.
parameter CSR_M_TRAP      = 1,

// CSR_COUNTER: Include performance counters and relevant M-mode CSRs
parameter CSR_COUNTER     = 1,

// DEBUG_SUPPORT: Support for run/halt and instruction injection from an
// external Debug Module, support for Debug Mode, and Debug Mode CSRs.
// Requires: CSR_M_MANDATORY, CSR_M_TRAP.
parameter DEBUG_SUPPORT   = 0,

// NUM_IRQ: Number of external IRQs implemented in meie0 and meip0.
// Minimum 1 (if CSR_M_TRAP = 1), maximum 32.
parameter NUM_IRQ         = 32,

// ----------------------------------------------------------------------------
// ID registers

// JEDEC JEP106-compliant vendor ID, can be left at 0 if "not implemented or
// [...] this is a non-commercial implementation" (RISC-V spec).
// 31:7 is continuation code count, 6:0 is ID. Parity bit is not stored.
parameter MVENDORID_VAL   = 32'h0,

// Implementation ID for this specific version of Hazard3. Git hash is perfect.
parameter MIMPID_VAL      = 32'h0,

// Each core has a single hardware thread. Multiple cores should have unique IDs.
parameter MHARTID_VAL     = 32'h0,

// Pointer to configuration structure blob, or all-zeroes. Must be at least
// 4-byte-aligned.
parameter MCONFIGPTR_VAL  = 32'h0,

// ----------------------------------------------------------------------------
// Performance/size options

// REDUCED_BYPASS: Remove all forwarding paths except X->X (so back-to-back
// ALU ops can still run at 1 CPI), to save area.
parameter REDUCED_BYPASS  = 0,

// MULDIV_UNROLL: Bits per clock for multiply/divide circuit, if present. Must
// be a power of 2.
parameter MULDIV_UNROLL   = 1,

// MUL_FAST: Use single-cycle multiply circuit for MUL instructions, retiring
// to stage M. The sequential multiply/divide circuit is still used for MULH*
parameter MUL_FAST        = 0,

// MULH_FAST: extend the fast multiply circuit to also cover MULH*, and remove
// the multiply functionality from the sequential multiply/divide circuit.
// Requires; MUL_FAST
parameter MULH_FAST       = 0,

// MTVEC_WMASK: Mask of which bits in MTVEC are modifiable. Save gates by
// making trap vector base partly fixed (legal, as it's WARL).
//
// - The vectoring mode can be made fixed by clearing the LSB of MTVEC_WMASK
//
// - Note the entire vector table must always be aligned to its size, rounded
//   up to a power of two, so careful with the low-order bits.
parameter MTVEC_WMASK     = 32'hfffffffd,

// ----------------------------------------------------------------------------
// Port size parameters (do not modify)

parameter W_ADDR          = 32,   // Do not modify
parameter W_DATA          = 32    // Do not modify
