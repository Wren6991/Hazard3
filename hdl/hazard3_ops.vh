/*****************************************************************************\
|                        Copyright (C) 2021 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// ALU operation selectors

localparam ALUOP_ADD     = 6'h00; 
localparam ALUOP_SUB     = 6'h01; 
localparam ALUOP_LT      = 6'h02;
localparam ALUOP_LTU     = 6'h04;
localparam ALUOP_AND     = 6'h06;
localparam ALUOP_OR      = 6'h07;
localparam ALUOP_XOR     = 6'h08;
localparam ALUOP_SRL     = 6'h09;
localparam ALUOP_SRA     = 6'h0a;
localparam ALUOP_SLL     = 6'h0b;
localparam ALUOP_MULDIV  = 6'h0c;
localparam ALUOP_RS2     = 6'h0d; // differs from AND/OR/XOR in [1:0]
// Bitmanip ALU operations (some also used by AMOs):
localparam ALUOP_SH1ADD  = 6'h20;
localparam ALUOP_SH2ADD  = 6'h21;
localparam ALUOP_SH3ADD  = 6'h22;
localparam ALUOP_CLZ     = 6'h23;
localparam ALUOP_CPOP    = 6'h24;
localparam ALUOP_CTZ     = 6'h25;
localparam ALUOP_ANDN    = 6'h26; // Same LSBs as non-inverted
localparam ALUOP_ORN     = 6'h27; // Same LSBs as non-inverted
localparam ALUOP_XNOR    = 6'h28; // Same LSBs as non-inverted
localparam ALUOP_MAX     = 6'h29;
localparam ALUOP_MAXU    = 6'h2a;
localparam ALUOP_MIN     = 6'h2b;
localparam ALUOP_MINU    = 6'h2c;
localparam ALUOP_ORC_B   = 6'h2d;
localparam ALUOP_REV8    = 6'h2e;
localparam ALUOP_ROL     = 6'h2f;
localparam ALUOP_ROR     = 6'h30;
localparam ALUOP_SEXT_B  = 6'h31;
localparam ALUOP_SEXT_H  = 6'h32;
localparam ALUOP_ZEXT_H  = 6'h33;

localparam ALUOP_CLMUL   = 6'h34;
localparam ALUOP_CLMULH  = 6'h35;
localparam ALUOP_CLMULR  = 6'h36;

localparam ALUOP_BCLR    = 6'h37;
localparam ALUOP_BEXT    = 6'h38;
localparam ALUOP_BINV    = 6'h39;
localparam ALUOP_BSET    = 6'h3a;

localparam ALUOP_PACK    = 6'h3b;
localparam ALUOP_PACKH   = 6'h3c;
localparam ALUOP_BREV8   = 6'h3d;
localparam ALUOP_ZIP     = 6'h3e;
localparam ALUOP_UNZIP   = 6'h3f;

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
// instructions in the pipeline. These are speculative and can be flushed
// on e.g. branch mispredict
// These mostly align with mcause values.

localparam EXCEPT_NONE           = 4'hf;

localparam EXCEPT_INSTR_MISALIGN = 4'h0;
localparam EXCEPT_INSTR_FAULT    = 4'h1;
localparam EXCEPT_INSTR_ILLEGAL  = 4'h2;
localparam EXCEPT_EBREAK         = 4'h3;
localparam EXCEPT_LOAD_ALIGN     = 4'h4;
localparam EXCEPT_LOAD_FAULT     = 4'h5;
localparam EXCEPT_STORE_ALIGN    = 4'h6;
localparam EXCEPT_STORE_FAULT    = 4'h7;
localparam EXCEPT_MRET           = 4'ha; // Not really an exception, but handled like one
localparam EXCEPT_ECALL          = 4'hb;

// Operations for M extension (these are just instr[14:12])

localparam M_OP_MUL    = 3'h0;
localparam M_OP_MULH   = 3'h1;
localparam M_OP_MULHSU = 3'h2;
localparam M_OP_MULHU  = 3'h3;
localparam M_OP_DIV    = 3'h4;
localparam M_OP_DIVU   = 3'h5;
localparam M_OP_REM    = 3'h6;
localparam M_OP_REMU   = 3'h7;
