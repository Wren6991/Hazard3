/*****************************************************************************\
|                        Copyright (C) 2021 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// ALU operation selectors

localparam ALUOP_ADD         = 7'h00;
localparam ALUOP_SUB         = 7'h01;
localparam ALUOP_LT          = 7'h02;
localparam ALUOP_LTU         = 7'h04;
localparam ALUOP_AND         = 7'h06;
localparam ALUOP_OR          = 7'h07;
localparam ALUOP_XOR         = 7'h08;
localparam ALUOP_SRL         = 7'h09;
localparam ALUOP_SRA         = 7'h0a;
localparam ALUOP_SLL         = 7'h0b;
localparam ALUOP_MULDIV      = 7'h0c;
localparam ALUOP_RS2         = 7'h0d; // differs from AND/OR/XOR in [1:0]
// Bitmanip ALU operations (some also used by AMOs):
localparam ALUOP_SHXADD      = 7'h20;
localparam ALUOP_CLZ         = 7'h23;
localparam ALUOP_CPOP        = 7'h24;
localparam ALUOP_CTZ         = 7'h25;
localparam ALUOP_ANDN        = 7'h26; // Same LSBs as non-inverted
localparam ALUOP_ORN         = 7'h27; // Same LSBs as non-inverted
localparam ALUOP_XNOR        = 7'h28; // Same LSBs as non-inverted
localparam ALUOP_MAX         = 7'h29;
localparam ALUOP_MAXU        = 7'h2a;
localparam ALUOP_MIN         = 7'h2b;
localparam ALUOP_MINU        = 7'h2c;
localparam ALUOP_ORC_B       = 7'h2d;
localparam ALUOP_REV8        = 7'h2e;
localparam ALUOP_ROL         = 7'h2f;
localparam ALUOP_ROR         = 7'h30;
localparam ALUOP_SEXT_B      = 7'h31;
localparam ALUOP_SEXT_H      = 7'h32;
localparam ALUOP_ZEXT_H      = 7'h33;

// Zbc
localparam ALUOP_CLMUL       = 7'h34;

// Zbs
localparam ALUOP_BCLR        = 7'h35;
localparam ALUOP_BEXT        = 7'h36;
localparam ALUOP_BINV        = 7'h37;
localparam ALUOP_BSET        = 7'h38;

// Zbkb
localparam ALUOP_PACK        = 7'h39;
localparam ALUOP_PACKH       = 7'h3a;
localparam ALUOP_BREV8       = 7'h3b;
localparam ALUOP_ZIP         = 7'h3c;
localparam ALUOP_UNZIP       = 7'h3d;

// Xh3bextm
localparam ALUOP_BEXTM       = 7'h3e;

// Zbkx
localparam ALUOP_XPERM       = 7'h3f;

// Xh3sfx
localparam ALUOP_FUNPACKQ3_H = 7'h40;
localparam ALUOP_FUNPACKQ3_S = 7'h41;
localparam ALUOP_FCHECK2E_H  = 7'h42;
localparam ALUOP_FCHECK2E_S  = 7'h43;
localparam ALUOP_FPACKRQ3_H  = 7'h44;
localparam ALUOP_FPACKRQ3_S  = 7'h45;
localparam ALUOP_FEADJQ3     = 7'h48;
localparam ALUOP_FEADJU3     = 7'h49;
localparam ALUOP_XORSIGN     = 7'h4a;
localparam ALUOP_XNORSIGN    = 7'h4b;
localparam ALUOP_SSRASTICKY  = 7'h4c;
localparam ALUOP_SSRLSTICKY  = 7'h4d;
localparam ALUOP_SSLA        = 7'h4e;

// Parameters to control ALU input muxes. Bypass mux paths are
// controlled by X, so D has no parameters to choose these.

localparam ALUSRCA_RS1 = 1'h0;
localparam ALUSRCA_PC  = 1'h1;

localparam ALUSRCB_RS2 = 1'h0;
localparam ALUSRCB_IMM = 1'h1;

localparam MEMOP_LW   = 5'h00;
localparam MEMOP_LH   = 5'h01;
localparam MEMOP_LB   = 5'h02;
localparam MEMOP_LHU  = 5'h03;
localparam MEMOP_LBU  = 5'h04;
localparam MEMOP_SW   = 5'h05;
localparam MEMOP_SH   = 5'h06;
localparam MEMOP_SB   = 5'h07;

localparam MEMOP_LR_W = 5'h08;
localparam MEMOP_SC_W = 5'h09;
localparam MEMOP_AMO  = 5'h0a;
localparam MEMOP_NONE = 5'h10;

localparam BCOND_NEVER  = 2'h0;
localparam BCOND_ALWAYS = 2'h1;
localparam BCOND_ZERO   = 2'h2;
localparam BCOND_NZERO  = 2'h3;

// CSR access types

localparam CSR_WTYPE_W    = 2'h0;
localparam CSR_WTYPE_S    = 2'h1;
localparam CSR_WTYPE_C    = 2'h2;

// Exceptional condition signals which travel alongside (or instead of)
// instructions in the pipeline. These are speculative and can be flushed on
// e.g. branch mispredict. These mostly align with mcause values.

localparam EXCEPT_NONE           = 4'hf;

localparam EXCEPT_INSTR_MISALIGN = 4'h0;
localparam EXCEPT_INSTR_FAULT    = 4'h1;
localparam EXCEPT_INSTR_ILLEGAL  = 4'h2;
localparam EXCEPT_EBREAK         = 4'h3;
localparam EXCEPT_LOAD_ALIGN     = 4'h4;
localparam EXCEPT_LOAD_FAULT     = 4'h5;
localparam EXCEPT_STORE_ALIGN    = 4'h6;
localparam EXCEPT_STORE_FAULT    = 4'h7;
localparam EXCEPT_ECALL_U        = 4'h8;
// MRET, Return from M-mode: not really an exception, but handled like one
localparam EXCEPT_MRET           = 4'ha;
localparam EXCEPT_ECALL_M        = 4'hb;
// spare: c
// spare: d
// REFETCH: flush and refetch sequentially-following instructions, e.g. on
// executing fence.i. Jumps from stage 3 to get ordering against L/S dphase.
localparam EXCEPT_REFETCH        = 4'he;

// Operations for M extension (these are just instr[14:12])

localparam M_OP_MUL    = 3'h0;
localparam M_OP_MULH   = 3'h1;
localparam M_OP_MULHSU = 3'h2;
localparam M_OP_MULHU  = 3'h3;
localparam M_OP_DIV    = 3'h4;
localparam M_OP_DIVU   = 3'h5;
localparam M_OP_REM    = 3'h6;
localparam M_OP_REMU   = 3'h7;
