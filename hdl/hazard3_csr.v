/******************************************************************************
 *     DO WHAT THE FUCK YOU WANT TO AND DON'T BLAME US PUBLIC LICENSE         *
 *                        Version 3, April 2008                               *
 *                                                                            *
 *     Copyright (C) 2021 Luke Wren                                           *
 *                                                                            *
 *     Everyone is permitted to copy and distribute verbatim or modified      *
 *     copies of this license document and accompanying software, and         *
 *     changing either is allowed.                                            *
 *                                                                            *
 *       TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION      *
 *                                                                            *
 *     0. You just DO WHAT THE FUCK YOU WANT TO.                              *
 *     1. We're NOT RESPONSIBLE WHEN IT DOESN'T FUCKING WORK.                 *
 *                                                                            *
 *****************************************************************************/

`default_nettype none

// Control and Status Registers (CSRs)
// Also includes CSR-related logic like interrupt enable/masking,
// trap vector calculation.

module hazard3_csr #(
	parameter XLEN            = 32,   // Must be 32
	parameter W_COUNTER       = 64,   // This *should* be 64, but can be reduced to save gates.
	                                  // The full 64 bits is writeable, so high-word increment can
	                                  // be implemented in software, and a narrower hw counter used
`include "hazard3_config.vh"
,
`include "hazard3_width_const.vh"
) (
	input  wire               clk,
	input  wire               rst_n,

	// Debug signalling
	output reg                debug_mode,

	input  wire               dbg_req_halt,
	input  wire               dbg_req_halt_on_reset,
	input  wire               dbg_req_resume,

	output wire               dbg_instr_caught_exception,
	output wire               dbg_instr_caught_ebreak,

	input  wire [W_DATA-1:0]  dbg_data0_rdata,
	output wire [W_DATA-1:0]  dbg_data0_wdata,
	output wire               dbg_data0_wen,

	// Read port is combinatorial.
	// Write port is synchronous, and write effects will be observed on the next clock cycle.
	// The *_soon strobes are versions which the core does not gate with its stall signal.
	// These are needed because:
	// - Core stall is a function of bus stall
	// - Illegal CSR accesses produce trap entry
	// - Trap entry (not necessarily caused by CSR access) gates outgoing bus accesses
	// - Through-paths from e.g. hready to htrans are problematic for timing/implementation
	input  wire [11:0]        addr,
	input  wire [XLEN-1:0]    wdata,
	input  wire               wen,
	input  wire               wen_soon, // wen will be asserted once some stall condition clears
	input  wire [1:0]         wtype,
	output reg  [XLEN-1:0]    rdata,
	input  wire               ren,
	input  wire               ren_soon, // ren will be asserted once some stall condition clears
	output wire               illegal,

	// Trap signalling
	// *We* tell the core that we are taking a trap, and where to, based on:
	// - Synchronous exception inputs from the core
	// - External IRQ signals
	// - Masking etc based on the state of CSRs like mie
	//
	// We do this by raising trap_enter_vld, and keeping it raised until trap_enter_rdy
	// goes high. trap_addr has the absolute value of trap target address.
	// Once trap_enter_vld && _rdy, mepc_in is copied to mepc, and other trap state is set.
	//
	// Note that an exception input can go away, e.g. if the pipe gets flushed. In this
	// case we lower trap_enter_vld.
	output wire [XLEN-1:0]     trap_addr,
	output wire                trap_is_irq,
	output wire                trap_enter_vld,
	input  wire                trap_enter_rdy,
	input  wire [XLEN-1:0]     mepc_in,

	// Exceptions must *not* be a function of bus stall.
	input  wire [W_EXCEPT-1:0] except,

	// Level-sensitive interrupt sources
	input  wire                delay_irq_entry,
	input  wire [NUM_IRQ-1:0]  irq,
	input  wire                irq_software,
	input  wire                irq_timer,

	// Other CSR-specific signalling
	input  wire                instr_ret
);

// TODO block CSR access when entering trap?

`include "hazard3_ops.vh"

localparam X0 = {XLEN{1'b0}};

// ----------------------------------------------------------------------------
// List of M-mode CSRs (we implement a configurable subset of M-mode).
// ----------------------------------------------------------------------------
// The CSR block is the only piece of hardware which needs to know this mapping.

// Machine Information Registers (RO)
localparam MVENDORID      = 12'hf11; // Vendor ID.
localparam MARCHID        = 12'hf12; // Architecture ID.
localparam MIMPID         = 12'hf13; // Implementation ID.
localparam MHARTID        = 12'hf14; // Hardware thread ID.

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
localparam MIDCR          = 12'hbc0; // Implementation-defined control register (bag of bits)
localparam MEIE0          = 12'hbe0; // External interrupt enable register 0
localparam MEIP0          = 12'hfe0; // External interrupt pending register 0
localparam MLEI           = 12'hfe4; // Lowest external interrupt number

// ----------------------------------------------------------------------------
// Trigger Module

localparam TSELECT       = 12'h7a0;

// ----------------------------------------------------------------------------
// D-mode CSRs

localparam DCSR           = 12'h7b0;
localparam DPC            = 12'h7b1;
localparam DATA0          = 12'h7b2; // DSCRATCH0 would be here if implemented

// ----------------------------------------------------------------------------
// CSR state + update logic
// ----------------------------------------------------------------------------
// Names are (reg)_(field)

// Generic update logic for write/set/clear of an entire CSR:
function [XLEN-1:0] update;
	input [XLEN-1:0] prev;
begin
	update =
		wtype == CSR_WTYPE_C ? prev & ~wdata :
		wtype == CSR_WTYPE_S ? prev | wdata :
		wdata;
end
endfunction

function [XLEN-1:0] update_nonconst;
	input [XLEN-1:0] prev;
	input [XLEN-1:0] nonconst;
begin
	update_nonconst = ((
		wtype == CSR_WTYPE_C ? prev & ~wdata :
		wtype == CSR_WTYPE_S ? prev | wdata :
		wdata) & nonconst) | (prev & ~nonconst) ;
end
endfunction


wire enter_debug_mode;
wire exit_debug_mode;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		debug_mode <= 1'b0;
	end else if (DEBUG_SUPPORT) begin
		debug_mode <= (debug_mode && !exit_debug_mode) || enter_debug_mode;
	end
end

// ----------------------------------------------------------------------------
// Implementation-defined control register

localparam MIDCR_INIT = X0;
localparam MIDCR_WMASK = 32'h00000001;

reg [XLEN-1:0] midcr;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		midcr <= MIDCR_INIT;
	end else if (wen && addr == MIDCR) begin
		midcr <= update_nonconst(midcr, MIDCR_WMASK);
	end
end

// Modified external interrupt vectoring
wire midcr_eivect = midcr[0];

// ----------------------------------------------------------------------------
// Trap-handling CSRs

wire debug_suppresses_trap_update = DEBUG_SUPPORT && (debug_mode || enter_debug_mode);

// Two-level interrupt enable stack, shuffled on entry/exit:
reg mstatus_mpie;
reg mstatus_mie;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mstatus_mpie <= 1'b0;
		mstatus_mie <= 1'b0;
	end else if (CSR_M_TRAP) begin
		if (trap_enter_vld && trap_enter_rdy && !debug_suppresses_trap_update) begin
			if (except == EXCEPT_MRET) begin
				mstatus_mpie <= 1'b1;
				mstatus_mie <= mstatus_mpie;
			end else begin
				mstatus_mpie <= mstatus_mie;
				mstatus_mie <= 1'b0;
			end
		end else if (wen && addr == MSTATUS) begin
			{mstatus_mpie, mstatus_mie} <=
				wtype == CSR_WTYPE_C ? {mstatus_mpie, mstatus_mie} & ~{wdata[7], wdata[3]} :
				wtype == CSR_WTYPE_S ? {mstatus_mpie, mstatus_mie} |  {wdata[7], wdata[3]} :
				                                                      {wdata[7], wdata[3]} ;
		end
	end
end

reg [XLEN-1:0] mscratch;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mscratch <= X0;
	end else if (CSR_M_TRAP) begin
		if (wen && addr == MSCRATCH)
			mscratch <= update(mscratch);
	end
end

// Trap vector base
reg  [XLEN-1:0] mtvec_reg;
wire [XLEN-1:0] mtvec = mtvec_reg & ({XLEN{1'b1}} << 2);
wire            irq_vector_enable = mtvec_reg[0];

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mtvec_reg <= MTVEC_INIT;
	end else if (CSR_M_TRAP) begin
		if (wen && addr == MTVEC)
			mtvec_reg <= update_nonconst(mtvec_reg, MTVEC_WMASK);
	end
end

// Exception program counter
reg [XLEN-1:0] mepc;
// LSB is always 0
localparam MEPC_MASK = {{XLEN-1{1'b1}}, 1'b0};

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mepc <= X0;
	end else if (CSR_M_TRAP) begin
		if (trap_enter_vld && trap_enter_rdy && except != EXCEPT_MRET && !debug_suppresses_trap_update) begin
			mepc <= mepc_in & MEPC_MASK;
		end else if (wen && addr == MEPC) begin
			mepc <= update(mepc) & MEPC_MASK;
		end
	end
end

// Interrupt enable (reserved bits are tied to 0)
reg [XLEN-1:0] mie;
localparam MIE_WMASK = 32'h00000888; // meie, mtie, msie

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mie <= X0;
	end else if (CSR_M_TRAP) begin
		if (wen && addr == MIE)
			mie <= update_nonconst(mie, MIE_WMASK);
	end
end

wire mie_meie = mie[11];

// Interrupt status ("pending") register, handled later
wire [XLEN-1:0] mip;
// None of the bits we implement are directly writeable.
// MSIP is only writeable by a "platform-defined" mechanism, and we don't implement
// one!

// Trap cause registers. The non-constant bits can be written by software,
// and update automatically on trap entry. (bits 30:0 are WLRL, so we tie most off)
reg        mcause_irq;
reg  [5:0] mcause_code;
wire       mcause_irq_next;
wire [5:0] mcause_code_next;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mcause_irq <= 1'b0;
		mcause_code <= 6'h0;
	end else if (CSR_M_TRAP) begin
		if (trap_enter_vld && trap_enter_rdy && except != EXCEPT_MRET && !debug_suppresses_trap_update) begin
			mcause_irq <= mcause_irq_next;
			mcause_code <= mcause_code_next;
		end else if (wen && addr == MCAUSE) begin
			{mcause_irq, mcause_code} <=
				wtype == CSR_WTYPE_C ? {mcause_irq, mcause_code} & ~{wdata[31], wdata[5:0]} :
				wtype == CSR_WTYPE_S ? {mcause_irq, mcause_code} |  {wdata[31], wdata[5:0]} :
				                                                    {wdata[31], wdata[5:0]} ;
		end
	end
end

// Custom external interrupt enable register (would be at top of mie, but that
// only leaves room for 16 external interrupts)

localparam MEIE0_WMASK = ~({XLEN{1'b1}} << NUM_IRQ);

reg [XLEN-1:0] meie0;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		// All-ones for implemented IRQs
		meie0 <= X0;
	end else if (wen && addr == MEIE0) begin
		meie0 <= update_nonconst(meie0, MEIE0_WMASK);
	end
end

// Assigned later:
wire [XLEN-1:0] meip0;
wire [4:0] mlei;

// ----------------------------------------------------------------------------
// Counters

reg mcountinhibit_cy;
reg mcountinhibit_ir;

reg [XLEN-1:0] mcycleh;
reg [XLEN-1:0] mcycle;
reg [XLEN-1:0] minstreth;
reg [XLEN-1:0] minstret;

wire [XLEN-1:0] ctr_update = update(
	{addr[7], addr[1]} == 2'b00 ? mcycle   :
	{addr[7], addr[1]} == 2'b01 ? minstret :
	{addr[7], addr[1]} == 2'b10 ? mcycleh  :
	                              minstreth
);

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mcycleh <= X0;
		mcycle <= X0;
		minstreth <= X0;
		minstret <= X0;
		// Counters inhibited by default to save energy
		mcountinhibit_cy <= 1'b0;
		mcountinhibit_ir <= 1'b0;
	end else if (CSR_COUNTER) begin
		// Optionally hold the top (2 * XLEN - W_COUNTER) bits constant to
		// save gates (noncompliant if enabled)
		if (!(mcountinhibit_cy || debug_mode))
			{mcycleh, mcycle} <= (({mcycleh, mcycle} + 1'b1) & ~({2*XLEN{1'b1}} << W_COUNTER))
				| ({mcycleh, mcycle} & ({2*XLEN{1'b1}} << W_COUNTER));
		if (!(mcountinhibit_ir || debug_mode) && instr_ret)
			{minstreth, minstret} <= (({minstreth, minstret} + 1'b1) & ~({2*XLEN{1'b1}} << W_COUNTER))
				| ({minstreth, minstret} & ({2*XLEN{1'b1}} << W_COUNTER));
		if (wen) begin
			if (addr == MCYCLEH)
				mcycleh <= ctr_update;
			if (addr == MCYCLE)
				mcycle <= ctr_update;
			if (addr == MINSTRETH)
				minstreth <= ctr_update;
			if (addr == MINSTRET)
				minstret <= ctr_update;
			if (addr == MCOUNTINHIBIT) begin
				{mcountinhibit_ir, mcountinhibit_cy} <=
					wtype == CSR_WTYPE_C ? {mcountinhibit_ir, mcountinhibit_cy} & ~{wdata[2], wdata[0]} :
					wtype == CSR_WTYPE_S ? {mcountinhibit_ir, mcountinhibit_cy} |  {wdata[2], wdata[0]} :
					                                                               {wdata[2], wdata[0]} ;
			end
		end
	end
end

// ----------------------------------------------------------------------------
// Debug-mode CSRs

// The following DCSR bits are read/writable as normal:
// - ebreakm (bit 15)
// - step (bit 2)
// The following are read-only volatile:
// - cause (bits 8:6)
// All others are hardwired constants.

reg dcsr_ebreakm;
reg dcsr_step;
reg [2:0] dcsr_cause;
wire [2:0] dcause_next;

localparam DCSR_CAUSE_EBREAK  = 3'h1;
localparam DCSR_CAUSE_TRIGGER = 3'h2;
localparam DCSR_CAUSE_HALTREQ = 3'h3;
localparam DCSR_CAUSE_STEP    = 3'h4;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		dcsr_ebreakm <= 1'b0;
		dcsr_step <= 1'b0;
		dcsr_cause <= 3'h0;
	end else if (DEBUG_SUPPORT) begin
		if (debug_mode && wen && addr == DCSR) begin
			{dcsr_ebreakm, dcsr_step} <=
				wtype == CSR_WTYPE_C ? {dcsr_ebreakm, dcsr_step} & ~{wdata[15], wdata[2]} :
				wtype == CSR_WTYPE_S ? {dcsr_ebreakm, dcsr_step} |  {wdata[15], wdata[2]} :
				                                                    {wdata[15], wdata[2]} ;
		end
		if (enter_debug_mode) begin
			dcsr_cause <= dcause_next;
		end
	end
end

reg [XLEN-1:0] dpc;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		dpc <= X0;
	end else if (DEBUG_SUPPORT) begin
		if (enter_debug_mode)
			dpc <= mepc_in;
		else if (debug_mode && wen && addr == DPC)
			dpc <= update(dpc);
	end
end

assign dbg_data0_wdata = wdata;
assign dbg_data0_wen = wen && addr == DATA0;

// ----------------------------------------------------------------------------
// Read port + detect addressing of unmapped CSRs
// ----------------------------------------------------------------------------

reg decode_match;

always @ (*) begin
	decode_match = 1'b0;
	rdata = {XLEN{1'b0}};
	case (addr)

    // ------------------------------------------------------------------------
	// Mandatory CSRs

	MISA: if (CSR_M_MANDATORY) begin
		// WARL, so it is legal to be tied constant
		decode_match = 1'b1;
		rdata = {
			2'h1,              // MXL: 32-bit
			{XLEN-28{1'b0}},   // WLRL

			13'd0,             // Z...N, no
			|EXTENSION_M,
			3'd0,              // L...J, no
			1'b1,              // Integer ISA
			5'd0,              // H...D, no
			|EXTENSION_C,
			2'b0
		};
	end
	MVENDORID: if (CSR_M_MANDATORY) begin
		decode_match = !wen_soon; // MRO
		rdata = MVENDORID_VAL;
	end
	MARCHID: if (CSR_M_MANDATORY) begin
		decode_match = !wen_soon; // MRO
		rdata = MARCHID_VAL;
	end
	MIMPID: if (CSR_M_MANDATORY) begin
		decode_match = !wen_soon; // MRO
		rdata = MIMPID_VAL;
	end
	MHARTID: if (CSR_M_MANDATORY) begin
		decode_match = !wen_soon; // MRO
		rdata = MHARTID_VAL;
	end

	MSTATUS: if (CSR_M_MANDATORY || CSR_M_TRAP) begin
		decode_match = 1'b1;
		rdata = {
			1'b0,    // Never any dirty state besides GPRs
			8'd0,    // (WPRI)
			1'b0,    // TSR (Trap SRET), tied 0 if no S mode.
			1'b0,    // TW (Timeout Wait), tied 0 if only M mode.
			1'b0,    // TVM (trap virtual memory), tied 0 if no S mode.
			1'b0,    // MXR (Make eXecutable Readable), tied 0 if not S mode.
			1'b0,    // SUM, tied 0, we have no S or U mode
			1'b0,    // MPRV (modify privilege), tied 0 if no U mode
			4'd0,    // XS, FS always "off" (no extension state to clear!)
			2'b11,   // MPP (M-mode previous privilege), we are always M-mode
			2'd0,    // (WPRI)
			1'b0,    // SPP, tied 0 if S mode not supported
			mstatus_mpie,
			3'd0,    // No S, U
			mstatus_mie,
			3'd0     // No S, U
		};
	end

	// MSTATUSH is all zeroes (fields are MBE and SBE, which are zero because
	// we are pure little-endian.) Prior to priv-1.12 MSTATUSH could be left
	// unimplemented in this case, but now it must be decoded even if
	// hardwired to 0.
	MSTATUSH: if (CSR_M_MANDATORY || CSR_M_TRAP) begin
		decode_match = 1'b1;
	end

	// MEDELEG, MIDELEG should not exist for M-only implementations. Will raise
	// illegal instruction exception if accessed.

    // ------------------------------------------------------------------------
	// Trap-handling CSRs

	// TODO bit of a hack but this is a 32 bit synthesised register with
	// set/clear/write/read, don't turn it on unless we really have to
	MSCRATCH: if (CSR_M_TRAP && CSR_M_MANDATORY) begin
		decode_match = 1'b1;
		rdata = mscratch;
	end

	MEPC: if (CSR_M_TRAP) begin
		decode_match = 1'b1;
		rdata = mepc;
	end

	MCAUSE: if (CSR_M_TRAP) begin
		decode_match = 1'b1;
		rdata = {
			mcause_irq,      // Sign bit is 1 for IRQ, 0 for exception
			{26{1'b0}},      // Padding
			mcause_code[4:0] // Enough for 16 external IRQs, which is all we have room for in mip/mie
		};
	end

	MTVAL: if (CSR_M_TRAP) begin
		decode_match = 1'b1;
		// Hardwired to 0
	end

	MIE: if (CSR_M_TRAP) begin
		decode_match = 1'b1;
		rdata = mie;
	end

	MIP: if (CSR_M_TRAP) begin
		// Writes are permitted, but ignored.
		decode_match = 1'b1;
		rdata = mip;
	end

	MTVEC: if (CSR_M_TRAP) begin
		decode_match = 1'b1;
		rdata = {
			mtvec[XLEN-1:2],  // BASE
			1'b0,             // Reserved mode bit gets WARL'd to 0
			irq_vector_enable // MODE is vectored (2'h1) or direct (2'h0)
		};
	end

    // ------------------------------------------------------------------------
	// Counter CSRs

	// Get the tied WARLs out the way first
	MHPMCOUNTER3:   if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER4:   if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER5:   if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER6:   if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER7:   if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER8:   if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER9:   if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER10:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER11:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER12:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER13:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER14:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER15:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER16:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER17:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER18:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER19:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER20:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER21:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER22:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER23:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER24:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER25:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER26:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER27:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER28:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER29:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER30:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER31:  if (CSR_COUNTER) begin decode_match = 1'b1; end

	MHPMCOUNTER3H:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER4H:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER5H:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER6H:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER7H:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER8H:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER9H:  if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER10H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER11H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER12H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER13H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER14H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER15H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER16H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER17H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER18H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER19H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER20H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER21H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER22H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER23H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER24H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER25H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER26H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER27H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER28H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER29H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER30H: if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMCOUNTER31H: if (CSR_COUNTER) begin decode_match = 1'b1; end

	MHPMEVENT3:     if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT4:     if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT5:     if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT6:     if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT7:     if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT8:     if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT9:     if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT10:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT11:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT12:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT13:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT14:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT15:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT16:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT17:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT18:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT19:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT20:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT21:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT22:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT23:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT24:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT25:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT26:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT27:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT28:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT29:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT30:    if (CSR_COUNTER) begin decode_match = 1'b1; end
	MHPMEVENT31:    if (CSR_COUNTER) begin decode_match = 1'b1; end

	MCOUNTINHIBIT:  if (CSR_COUNTER) begin
		decode_match = 1'b1;
		rdata = {
			29'd0,
			mcountinhibit_ir,
			1'b0,
			mcountinhibit_cy
		};
	end

	MCYCLE: if (CSR_COUNTER) begin
		decode_match = 1'b1;
		rdata = mcycle;
	end
	MINSTRET: if (CSR_COUNTER) begin
		decode_match = 1'b1;
		rdata = minstret;
	end

	MCYCLEH: if (CSR_COUNTER) begin
		decode_match = 1'b1;
		rdata = mcycleh;
	end
	MINSTRETH: if (CSR_COUNTER) begin
		decode_match = 1'b1;
		rdata = minstreth;
	end

	// ------------------------------------------------------------------------
	// Trigger Module CSRs

	// If triggers aren't supported, OpenOCD expects the following:
	// - tselect must be present
	// - tselect must raise an exception when written to
	// Otherwise it returns an error instead of 0 count when enumerating triggers
	TSELECT: if (DEBUG_SUPPORT) begin
		decode_match = !wen_soon;
	end

	// ------------------------------------------------------------------------
	// Debug CSRs

	DCSR: if (DEBUG_SUPPORT && debug_mode) begin
		decode_match = 1'b1;
		rdata = {
			4'h4,         // xdebugver = 4, for 0.13.2 debug spec
			12'd0,        // reserved
			dcsr_ebreakm,
			3'h0,         // No other modes besides M to break from
			1'b0,         // stepie = 0, no interrupts in single-step mode
			1'b1,         // stopcount = 1, no counter increment in debug mode
			1'b1,         // stoptime = 0, no core-local timer increment in debug mode
			dcsr_cause,
			1'b0,         // reserved
			1'b0,         // mprven = 0, we don't have MPRV support
			1'b0,         // nmip = 0, we have no NMI
			dcsr_step,
			2'h3          // prv = 3, we only have M mode
		};
	end

	DPC: if (DEBUG_SUPPORT && debug_mode) begin
		decode_match = 1'b1;
		rdata = dpc;
	end

	DATA0: if (DEBUG_SUPPORT && debug_mode) begin
		decode_match = 1'b1;
		rdata = dbg_data0_rdata;
	end

    // ------------------------------------------------------------------------
	// Custom CSRs

	MIDCR: if (CSR_M_TRAP) begin
		decode_match = 1'b1;
		rdata = midcr;
	end

	MEIE0: if (CSR_M_TRAP) begin
		decode_match = 1'b1;
		rdata = meie0;
	end

	MEIP0: if (CSR_M_TRAP) begin
		decode_match = !wen_soon;
		rdata = meip0;
	end

	MLEI: if (CSR_M_TRAP) begin
		decode_match = !wen_soon;
		rdata = {{XLEN-5{1'b0}}, mlei};
	end

	default: begin end
	endcase
end

assign illegal = (wen_soon || ren_soon) && !decode_match;

// ----------------------------------------------------------------------------
// Debug run/halt

reg have_just_reset;
reg step_halt_req;
reg pending_dbg_resume_prev;

wire pending_dbg_resume = (pending_dbg_resume_prev || dbg_req_resume) && debug_mode;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		have_just_reset <= |DEBUG_SUPPORT;
		step_halt_req <= 1'b0;
		pending_dbg_resume_prev <= 1'b0;
	end else if (DEBUG_SUPPORT) begin
		if (instr_ret)
			have_just_reset <= 1'b0;

		if (debug_mode) begin
			step_halt_req <= 1'b0;
		end else if (dcsr_step && (instr_ret || (trap_enter_vld && trap_enter_rdy))) begin
			// Note exception entry is also considered a step -- in this case
			// we are supposed to take the trap and then break to debug mode
			// before executing the first trap instruction. *IRQ* entry does
			// not occur when step is 1 (because we hardwire dcsr.stepie to 0)
			step_halt_req <= 1'b1;
		end

		pending_dbg_resume_prev <= pending_dbg_resume;
	end
end

// We can enter the halted state in an IRQ-like manner (squeeze in between the
// instructions in stage 2 and stage 3) or in an exception-like manner
// (replace the instruction in stage 3).

// This would also include triggers, if/when those are implemented:
wire want_halt_except = DEBUG_SUPPORT && !debug_mode && (
	dcsr_ebreakm && except == EXCEPT_EBREAK
);

// Note all exception-like causes (trigger, ebreak) are higher priority than IRQ-like
wire want_halt_irq = DEBUG_SUPPORT && !debug_mode && !want_halt_except && (
	dbg_req_halt || (dbg_req_halt_on_reset && have_just_reset) || step_halt_req
);

assign dcause_next =
	// Trigger would be highest priority if implemented
	except == EXCEPT_EBREAK                                    ? 3'h1 : // ebreak (priority 3)
	dbg_req_halt || (dbg_req_halt_on_reset && have_just_reset) ? 3'h3 : // halt or reset-halt (priority 1, 2)
	                                                             3'h4;  // single-step (priority 0)

assign enter_debug_mode = !debug_mode && (want_halt_irq || want_halt_except) && trap_enter_rdy;

assign exit_debug_mode = debug_mode && pending_dbg_resume && trap_enter_rdy;

// Report back to DM instruction injector to tell it its instruction sequence
// has finished (ebreak) or crashed out
assign dbg_instr_caught_ebreak = debug_mode && except == EXCEPT_EBREAK && trap_enter_rdy;

// Note we exclude ebreak from here regardless of dcsr.ebreakm, since we are
// already in debug mode at this point
assign dbg_instr_caught_exception = debug_mode && except != EXCEPT_NONE && except != EXCEPT_EBREAK && trap_enter_rdy;

// ----------------------------------------------------------------------------
// Trap request generation

reg [NUM_IRQ-1:0] irq_r;
reg irq_software_r;
reg irq_timer_r;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		irq_r <= {NUM_IRQ{1'b0}};
		irq_software_r <= 1'b0;
		irq_timer_r <= 1'b0;
	end else begin
		irq_r <= irq;
		irq_software_r <= irq_software;
		irq_timer_r <= irq_timer;
	end
end

assign meip0 = {{XLEN-NUM_IRQ{1'b0}}, irq_r};
wire external_irq_pending = |(meie0 & meip0);

assign mip = {
	20'h0,                // Reserved
	external_irq_pending, // meip, Global pending bit for external IRQs
	3'h0,                 // Reserved
	irq_timer_r,          // mtip, interrupt from memory-mapped timer peripheral
	3'h0,                 // Reserved
	irq_software_r,       // msip, software interrupt from memory-mapped register
	3'h0                  // Reserved
};

// When eivect = 1, mip.meip is masked from the standard IRQs, so that the
// platform-specific causes and vectors are used instead.
wire [31:0] mip_no_global = mip & ~(32'h800 & ~{XLEN{midcr_eivect}});
wire standard_irq_active = |(mip_no_global & mie) && mstatus_mie && !dcsr_step;
wire external_irq_active = external_irq_pending && mstatus_mie && !dcsr_step && mie_meie;

wire [4:0] external_irq_num;
wire [3:0] standard_irq_num;
assign mlei = external_irq_num;

hazard3_priority_encode #(
	.W_REQ (32)
) mlei_priority_encode (
	.req (meie0 & meip0),
	.gnt (external_irq_num)
);

hazard3_priority_encode #(
	.W_REQ (16)
) irq_priority (
	.req (mip_no_global[15:0] & mie[15:0]),
	.gnt (standard_irq_num)
);

// ebreak may be treated as a halt-to-debugger or a regular M-mode exception,
// depending on dcsr.ebreakm.
wire exception_req_any = except != EXCEPT_NONE && !(except == EXCEPT_EBREAK && dcsr_ebreakm);

// Note when eivect=0 platform external interrupts also count as a standard
// external interrupt, so the standard mapping (collapsed into a single
// vector) always takes priority.
wire [5:0] mcause_irq_num =
	standard_irq_active ? {2'h0, standard_irq_num}         :
	external_irq_active ? {1'h0, external_irq_num} + 6'd16 : 6'd0;

wire [5:0] vector_sel =
	!exception_req_any && irq_vector_enable ? mcause_irq_num : 6'd0;

assign trap_addr =
	except == EXCEPT_MRET ? mepc :
	pending_dbg_resume    ? dpc  : mtvec | {24'h0, vector_sel, 2'h0};

// Check for exception-like or IRQ-like trap entry; any debug mode entry takes
// priority over any regular trap.
assign trap_is_irq = DEBUG_SUPPORT && (want_halt_except || want_halt_irq) ?
	!want_halt_except : !exception_req_any;

assign trap_enter_vld =
	CSR_M_TRAP && (exception_req_any ||
		!delay_irq_entry && !debug_mode && (standard_irq_active || external_irq_active)) ||
	DEBUG_SUPPORT && (want_halt_irq || want_halt_except || pending_dbg_resume);

assign mcause_irq_next = !exception_req_any;
assign mcause_code_next = exception_req_any ? {2'h0, except} : mcause_irq_num;

// ----------------------------------------------------------------------------

`ifdef RISCV_FORMAL

// Keep track of whether we are in a trap (only for formal property purposes)
reg in_trap;

always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		in_trap <= 1'b0;
	else
		in_trap <= (in_trap || (trap_enter_vld && trap_enter_rdy))
			&& !(trap_enter_vld && trap_enter_rdy && except == EXCEPT_MRET);

always @ (posedge clk) begin
	// Assume there are no nested exceptions, to stop riscv-formal from doing
	// annoying things like stopping instructions from retiring by repeatedly
	// feeding in invalid instructions

	if (in_trap)
		assume(except == EXCEPT_NONE);

	// Assume IRQs are not deasserted on cycles where exception entry does not
	// take place

	if (!trap_enter_rdy)
		assume(~|(irq_r & ~irq));

	// Make sure CSR accesses are flushed
	if (trap_enter_vld && trap_enter_rdy)
		assert(!(wen || ren));
	// Something is screwed up if this happens
	if ($past(trap_enter_vld && trap_enter_rdy))
		assert(!wen);
	// Should be impossible to get into the trap and exit it so quickly:
	if (in_trap && !$past(in_trap))
		assert(except != EXCEPT_MRET);
	// Should be impossible to get to another mret so soon after exiting:
	assert(!(except == EXCEPT_MRET && $past(except == EXCEPT_MRET)));

end

`endif

endmodule
