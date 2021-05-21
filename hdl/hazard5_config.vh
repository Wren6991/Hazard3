// Hazard5 CPU configuration parameters

// To configure Hazard5 you can either edit this file, or set parameters on
// your top-level instantiation, it's up to you. These parameters are all
// plumbed through Hazard5's internal hierarchy to the appropriate places.

// ----------------------------------------------------------------------------
// Reset state configuration

// RESET_VECTOR: Address of first instruction executed.
parameter RESET_VECTOR    = 32'h0,

// MTVEC_INIT: Initial value of trap vector base. Bits clear in MTVEC_WMASK
// will never change from this initial value. Bits set in MTVEC_WMASK can be
// written/set/cleared as normal. Note that, if CSR_M_TRAP is set, MTVEC_INIT
// should probably have a different value from RESET_VECTOR.
parameter MTVEC_INIT      = 32'h00000000,

// ----------------------------------------------------------------------------
// RISC-V ISA and CSR support

// EXTENSION_C: Support for compressed (variable-width) instructions
parameter EXTENSION_C     = 1,

// EXTENSION_M: Support for hardware multiply/divide/modulo instructions
parameter EXTENSION_M     = 1,

// CSR_M_MANDATORY: Bare minimum CSR support e.g. misa. Spec says must = 1 if
// CSRs are present, but I won't tell anyone.
parameter CSR_M_MANDATORY = 1,

// CSR_M_TRAP: Include M-mode trap-handling CSRs, and enable trap support.
parameter CSR_M_TRAP      = 1,

// CSR_COUNTER: Include performance counters and relevant M-mode CSRs
parameter CSR_COUNTER     = 0,

// ----------------------------------------------------------------------------
// Performance/size options

// REDUCED_BYPASS: Remove all forwarding paths except X->X (so back-to-back
// ALU ops can still run at 1 CPI), to save area.
parameter REDUCED_BYPASS  = 0,

// MULDIV_UNROLL: Bits per clock for multiply/divide circuit, if present. Must
// be a power of 2.
parameter MULDIV_UNROLL   = 1,

// MUL_FAST: Use single-cycle multiply circuit for MUL instructions, retiring
// to stage M. The sequential multiply/divide circuit is still used for
// MULH/MULHU/MULHSU.
parameter MUL_FAST        = 0,

// MTVEC_WMASK: Mask of which bits in MTVEC are modifiable. Save gates by
// making trap vector base partly fixed (legal, as it's WARL). Note the entire
// vector table must always be aligned to its size, rounded up to a power of
// two, so careful with the low-order bits.
parameter MTVEC_WMASK     = 32'hfffff000,

// ----------------------------------------------------------------------------
// Port size parameters (do not modify)

parameter W_ADDR          = 32,   // Do not modify
parameter W_DATA          = 32    // Do not modify
