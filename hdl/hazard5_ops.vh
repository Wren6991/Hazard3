
// ALU operation selectors

localparam ALUOP_ADD     = 4'h0; 
localparam ALUOP_SUB     = 4'h1; 
localparam ALUOP_LT      = 4'h2;
localparam ALUOP_LTU     = 4'h4;
localparam ALUOP_AND     = 4'h6;
localparam ALUOP_OR      = 4'h7;
localparam ALUOP_XOR     = 4'h8;
localparam ALUOP_SRL     = 4'h9;
localparam ALUOP_SRA     = 4'ha;
localparam ALUOP_SLL     = 4'hb;
localparam ALUOP_MULDIV  = 4'hc;

// Parameters to control ALU input muxes. Bypass mux paths are
// controlled by X, so D has no parameters to choose these.

localparam ALUSRCA_RS1 = 2'h0;
localparam ALUSRCA_PC  = 2'h1;

localparam ALUSRCB_RS2 = 2'h0;
localparam ALUSRCB_IMM = 2'h1;

localparam MEMOP_LW   = 4'h0;
localparam MEMOP_LH   = 4'h1;
localparam MEMOP_LB   = 4'h2;
localparam MEMOP_LHU  = 4'h3;
localparam MEMOP_LBU  = 4'h4;
localparam MEMOP_SW   = 4'h5;
localparam MEMOP_SH   = 4'h6;
localparam MEMOP_SB   = 4'h7;
localparam MEMOP_NONE = 4'h8;

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

localparam EXCEPT_NONE           = 3'h0;
localparam EXCEPT_ECALL          = 3'h1;
localparam EXCEPT_EBREAK         = 3'h2;
localparam EXCEPT_MRET           = 3'h3; // separate, but handled similarly
localparam EXCEPT_INSTR_ILLEGAL  = 3'h4;
localparam EXCEPT_INSTR_MISALIGN = 3'h5;
localparam EXCEPT_INSTR_FAULT    = 3'h6;

// Operations for M extension (these are just instr[14:12])

localparam M_OP_MUL    = 3'h0;
localparam M_OP_MULH   = 3'h1;
localparam M_OP_MULHSU = 3'h2;
localparam M_OP_MULHU  = 3'h3;
localparam M_OP_DIV    = 3'h4;
localparam M_OP_DIVU   = 3'h5;
localparam M_OP_REM    = 3'h6;
localparam M_OP_REMU   = 3'h7;
