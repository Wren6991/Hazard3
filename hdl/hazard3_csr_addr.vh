/*****************************************************************************\
|                        Copyright (C) 2022 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// List of addresses for CSRs implemented by Hazard3, including custom CSRs.

// ----------------------------------------------------------------------------
// M-mode CSRs

// Machine Information Registers (RO)
localparam MVENDORID      = 12'hf11; // Vendor ID.
localparam MARCHID        = 12'hf12; // Architecture ID.
localparam MIMPID         = 12'hf13; // Implementation ID.
localparam MHARTID        = 12'hf14; // Hardware thread ID.
localparam MCONFIGPTR     = 12'hf15; // Pointer to configuration data structure.

// Machine Trap Setup (RW)
localparam MSTATUS        = 12'h300; // Machine status register.
localparam MSTATUSH       = 12'h310; // As of priv-1.12 this must be present even if tied 0.
localparam MISA           = 12'h301; // ISA and extensions
localparam MEDELEG        = 12'h302; // Machine exception delegation register.
localparam MIDELEG        = 12'h303; // Machine interrupt delegation register.
localparam MIE            = 12'h304; // Machine interrupt-enable register.
localparam MTVEC          = 12'h305; // Machine trap-handler base address.
localparam MCOUNTEREN     = 12'h306; // Machine counter enable.

// Machine Trap Handling (RW)
localparam MSCRATCH       = 12'h340; // Scratch register for machine trap handlers.
localparam MEPC           = 12'h341; // Machine exception program counter.
localparam MCAUSE         = 12'h342; // Machine trap cause.
localparam MTVAL          = 12'h343; // Machine bad address or instruction.
localparam MIP            = 12'h344; // Machine interrupt pending.

// Machine Memory Protection (RW)
localparam PMPCFG0        = 12'h3a0; // Physical memory protection configuration.
localparam PMPCFG1        = 12'h3a1; // Physical memory protection configuration, RV32 only.
localparam PMPCFG2        = 12'h3a2; // Physical memory protection configuration.
localparam PMPCFG3        = 12'h3a3; // Physical memory protection configuration, RV32 only.
localparam PMPADDR0       = 12'h3b0; // Physical memory protection address register.
localparam PMPADDR1       = 12'h3b1; // Physical memory protection address register.

// Performance counters (RW)
localparam MCYCLE         = 12'hb00; // Raw cycles since start of day
localparam MINSTRET       = 12'hb02; // Instruction retire count since start of day
localparam MHPMCOUNTER3   = 12'hb03; // WARL (we tie to 0)
localparam MHPMCOUNTER4   = 12'hb04; // WARL (we tie to 0)
localparam MHPMCOUNTER5   = 12'hb05; // WARL (we tie to 0)
localparam MHPMCOUNTER6   = 12'hb06; // WARL (we tie to 0)
localparam MHPMCOUNTER7   = 12'hb07; // WARL (we tie to 0)
localparam MHPMCOUNTER8   = 12'hb08; // WARL (we tie to 0)
localparam MHPMCOUNTER9   = 12'hb09; // WARL (we tie to 0)
localparam MHPMCOUNTER10  = 12'hb0a; // WARL (we tie to 0)
localparam MHPMCOUNTER11  = 12'hb0b; // WARL (we tie to 0)
localparam MHPMCOUNTER12  = 12'hb0c; // WARL (we tie to 0)
localparam MHPMCOUNTER13  = 12'hb0d; // WARL (we tie to 0)
localparam MHPMCOUNTER14  = 12'hb0e; // WARL (we tie to 0)
localparam MHPMCOUNTER15  = 12'hb0f; // WARL (we tie to 0)
localparam MHPMCOUNTER16  = 12'hb10; // WARL (we tie to 0)
localparam MHPMCOUNTER17  = 12'hb11; // WARL (we tie to 0)
localparam MHPMCOUNTER18  = 12'hb12; // WARL (we tie to 0)
localparam MHPMCOUNTER19  = 12'hb13; // WARL (we tie to 0)
localparam MHPMCOUNTER20  = 12'hb14; // WARL (we tie to 0)
localparam MHPMCOUNTER21  = 12'hb15; // WARL (we tie to 0)
localparam MHPMCOUNTER22  = 12'hb16; // WARL (we tie to 0)
localparam MHPMCOUNTER23  = 12'hb17; // WARL (we tie to 0)
localparam MHPMCOUNTER24  = 12'hb18; // WARL (we tie to 0)
localparam MHPMCOUNTER25  = 12'hb19; // WARL (we tie to 0)
localparam MHPMCOUNTER26  = 12'hb1a; // WARL (we tie to 0)
localparam MHPMCOUNTER27  = 12'hb1b; // WARL (we tie to 0)
localparam MHPMCOUNTER28  = 12'hb1c; // WARL (we tie to 0)
localparam MHPMCOUNTER29  = 12'hb1d; // WARL (we tie to 0)
localparam MHPMCOUNTER30  = 12'hb1e; // WARL (we tie to 0)
localparam MHPMCOUNTER31  = 12'hb1f; // WARL (we tie to 0)

localparam MCYCLEH        = 12'hb80; // High halves of each counter
localparam MINSTRETH      = 12'hb82;
localparam MHPMCOUNTER3H  = 12'hb83;
localparam MHPMCOUNTER4H  = 12'hb84;
localparam MHPMCOUNTER5H  = 12'hb85;
localparam MHPMCOUNTER6H  = 12'hb86;
localparam MHPMCOUNTER7H  = 12'hb87;
localparam MHPMCOUNTER8H  = 12'hb88;
localparam MHPMCOUNTER9H  = 12'hb89;
localparam MHPMCOUNTER10H = 12'hb8a;
localparam MHPMCOUNTER11H = 12'hb8b;
localparam MHPMCOUNTER12H = 12'hb8c;
localparam MHPMCOUNTER13H = 12'hb8d;
localparam MHPMCOUNTER14H = 12'hb8e;
localparam MHPMCOUNTER15H = 12'hb8f;
localparam MHPMCOUNTER16H = 12'hb90;
localparam MHPMCOUNTER17H = 12'hb91;
localparam MHPMCOUNTER18H = 12'hb92;
localparam MHPMCOUNTER19H = 12'hb93;
localparam MHPMCOUNTER20H = 12'hb94;
localparam MHPMCOUNTER21H = 12'hb95;
localparam MHPMCOUNTER22H = 12'hb96;
localparam MHPMCOUNTER23H = 12'hb97;
localparam MHPMCOUNTER24H = 12'hb98;
localparam MHPMCOUNTER25H = 12'hb99;
localparam MHPMCOUNTER26H = 12'hb9a;
localparam MHPMCOUNTER27H = 12'hb9b;
localparam MHPMCOUNTER28H = 12'hb9c;
localparam MHPMCOUNTER29H = 12'hb9d;
localparam MHPMCOUNTER30H = 12'hb9e;
localparam MHPMCOUNTER31H = 12'hb9f;

localparam MCOUNTINHIBIT  = 12'h320; // Count inhibit register for mcycle/minstret
localparam MHPMEVENT3     = 12'h323; // WARL (we tie to 0)
localparam MHPMEVENT4     = 12'h324; // WARL (we tie to 0)
localparam MHPMEVENT5     = 12'h325; // WARL (we tie to 0)
localparam MHPMEVENT6     = 12'h326; // WARL (we tie to 0)
localparam MHPMEVENT7     = 12'h327; // WARL (we tie to 0)
localparam MHPMEVENT8     = 12'h328; // WARL (we tie to 0)
localparam MHPMEVENT9     = 12'h329; // WARL (we tie to 0)
localparam MHPMEVENT10    = 12'h32a; // WARL (we tie to 0)
localparam MHPMEVENT11    = 12'h32b; // WARL (we tie to 0)
localparam MHPMEVENT12    = 12'h32c; // WARL (we tie to 0)
localparam MHPMEVENT13    = 12'h32d; // WARL (we tie to 0)
localparam MHPMEVENT14    = 12'h32e; // WARL (we tie to 0)
localparam MHPMEVENT15    = 12'h32f; // WARL (we tie to 0)
localparam MHPMEVENT16    = 12'h330; // WARL (we tie to 0)
localparam MHPMEVENT17    = 12'h331; // WARL (we tie to 0)
localparam MHPMEVENT18    = 12'h332; // WARL (we tie to 0)
localparam MHPMEVENT19    = 12'h333; // WARL (we tie to 0)
localparam MHPMEVENT20    = 12'h334; // WARL (we tie to 0)
localparam MHPMEVENT21    = 12'h335; // WARL (we tie to 0)
localparam MHPMEVENT22    = 12'h336; // WARL (we tie to 0)
localparam MHPMEVENT23    = 12'h337; // WARL (we tie to 0)
localparam MHPMEVENT24    = 12'h338; // WARL (we tie to 0)
localparam MHPMEVENT25    = 12'h339; // WARL (we tie to 0)
localparam MHPMEVENT26    = 12'h33a; // WARL (we tie to 0)
localparam MHPMEVENT27    = 12'h33b; // WARL (we tie to 0)
localparam MHPMEVENT28    = 12'h33c; // WARL (we tie to 0)
localparam MHPMEVENT29    = 12'h33d; // WARL (we tie to 0)
localparam MHPMEVENT30    = 12'h33e; // WARL (we tie to 0)
localparam MHPMEVENT31    = 12'h33f; // WARL (we tie to 0)

// Custom M-mode CSRs:
localparam MEIE0          = 12'hbe0; // External interrupt enable register 0
localparam MEIE1          = 12'hbe1; // External interrupt enable register 1
localparam MEIE2          = 12'hbe2; // External interrupt enable register 2
localparam MEIE3          = 12'hbe3; // External interrupt enable register 3
localparam MEIP0          = 12'hfe0; // External interrupt pending register 0
localparam MEIP1          = 12'hfe1; // External interrupt pending register 1
localparam MEIP2          = 12'hfe2; // External interrupt pending register 2
localparam MEIP3          = 12'hfe3; // External interrupt pending register 3
localparam MLEI           = 12'hfe4; // Lowest external interrupt number

// ----------------------------------------------------------------------------
// Trigger Module

localparam TSELECT       = 12'h7a0;

// ----------------------------------------------------------------------------
// D-mode CSRs

localparam DCSR           = 12'h7b0;
localparam DPC            = 12'h7b1;
localparam DMDATA0        = 12'hbff; // Custom read/write
