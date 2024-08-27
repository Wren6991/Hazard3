/*****************************************************************************\
|                        Copyright (C) 2022 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

// The Hazard3 trigger unit always implements one trigger of each of the
// following types:
//
// * Instruction count trigger (type=3) with count=1 (can single-step U-mode
//   from M-mode, or step M-mode foreground from an M-mode exception handler)
//
// * Interrupt trigger (type=4): trigger on mask of mtip/msip/meip interrupts
//
// * Exception trigger (type=5): trigger on mask of exception causes
//
// The following are optionally supported:
//
// * Instruction address triggers (type=2 execute=1 select=0) aka breakpoints
//
// Breakpoints always use exact address matches, and the timing is always
// "early". The number of breakpoints is configured by BREAKPOINT_TRIGGERS,
// which can be 0.
//
// Interrupt/exception triggers break after the core transfers to its trap
// handler, but before the first trap handler instruction executes. Only
// action=1 is supported for these triggers, since trap-on-trap is useless
// when M is the only privileged mode.

module hazard3_triggers #(
`include "hazard3_config.vh"
) (
	input  wire              clk,
	input  wire              rst_n,

	// Config interface passed through CSR block
	input  wire [11:0]       cfg_addr,
	input  wire              cfg_wen,
	input  wire [W_DATA-1:0] cfg_wdata,
	output reg  [W_DATA-1:0] cfg_rdata,

	// Global trigger-to-M-mode enable (e.g. from tcontrol or mstatus.mie)
	input  wire              trig_m_en,

	// Fetch address query from stage F
	input  wire [W_ADDR-1:0] fetch_addr,
	input  wire              fetch_m_mode,
	input  wire              fetch_d_mode,

	// Trap trigger events from stage M
	input  wire              event_interrupt,
	input  wire              event_exception,
	input  wire [3:0]        event_trap_cause,

	// Break request (for each halfword of the word-sized word-aligned fetch)
	output wire [1:0]        break_any,
	output wire [1:0]        break_d_mode,

	// Stage-X debug mode flag, for CSR protection (may or may not be the same
	// as the query debug mode flag)
	input  wire              x_d_mode,
	// Stage-X M-mode flag, for enables on interrupt/exception triggers
	input  wire              x_m_mode
);

`include "hazard3_csr_addr.vh"

generate
if (DEBUG_SUPPORT == 0) begin: no_triggers

// The instantiation of this block should already be stubbed out in core.v if
// there are no triggers, but we still get warnings for elaborating this
// module with zero triggers, so add a generate block here too.

always @ (*) cfg_rdata = {W_DATA{1'b0}};
assign break_any = 1'b0;
assign break_d_mode = 1'b0;

end else begin: have_triggers

localparam TINDEX_ICOUNT    = BREAKPOINT_TRIGGERS + 0;
localparam TINDEX_INTERRUPT = BREAKPOINT_TRIGGERS + 1;
localparam TINDEX_EXCEPTION = BREAKPOINT_TRIGGERS + 2;
localparam N_TRIGGERS       = BREAKPOINT_TRIGGERS + 3;

// ----------------------------------------------------------------------------
// Configuration state

parameter W_TSELECT = $clog2(N_TRIGGERS);

reg [W_TSELECT-1:0] tselect;

// Note tdata1 and mcontrol are the same CSR. tdata1 refers to the universal
// fields (type/dmode) and mcontrol refers to those fields specific to
// type=2 (address/data match), the only trigger type we implement.

// State for instruction address match triggers (breakpoints)
reg              tdata1_dmode     [0:BREAKPOINT_TRIGGERS-1];
reg              mcontrol_action  [0:BREAKPOINT_TRIGGERS-1];
reg              mcontrol_m       [0:BREAKPOINT_TRIGGERS-1];
reg              mcontrol_u       [0:BREAKPOINT_TRIGGERS-1];
reg              mcontrol_execute [0:BREAKPOINT_TRIGGERS-1];
reg [W_DATA-1:0] tdata2           [0:BREAKPOINT_TRIGGERS-1];

// State for instruction count trigger
// (hardwired: count=1 dmode=0 action=0; Debug mode single step is already
// available via dcsr)
reg             icount_m;
reg             icount_u;

// State for interrupt trigger
// (hardwired: action=1; M-mode trap-on-trap is useless as you lose the
// original trap state)
reg             trigger_irq_m;
reg             trigger_irq_u;
reg             trigger_irq_dmode;
reg [15:0]      trigger_irq_cause;

localparam [15:0] IMPLEMENTED_IRQ_CAUSES = {
	4'h0, // reserved
	1'b1, // meip
	3'h0, // reserved or unimplemented
	1'b1, // mtip
	3'h0, // reserved or unimplemented
	1'b1, // msip
	3'h0  // reserved or unimplemented
};

// State for exception trigger
// (hardwired: action=1; M-mode trap-on-trap is useless as you lose the
// original trap state)
reg             trigger_exception_m;
reg             trigger_exception_u;
reg             trigger_exception_dmode;
reg [15:0]      trigger_exception_cause;

localparam [15:0] IMPLEMENTED_EXCEPTION_CAUSES = {
	4'h0,         // reserved
	1'b1,         // 11 -> ecall from M-mode
	2'h0,         // reserved or unimplemented
	|U_MODE,      // 8  -> ecall from U-mode
	1'b1,         // 7  -> store/AMO fault
	1'b1,         // 6  -> store/AMO align
	1'b1,         // 5  -> load fault
	1'b1,         // 4  -> load align
	1'b0,         // 3  -> breakpoint; seems useless and risky so disallow
	1'b1,         // 2  -> illegal opcode
	1'b1,         // 1  -> fetch fault
	~|EXTENSION_C // 0  -> fetch align (only when IALIGN is 32-bit)
};

// ----------------------------------------------------------------------------
// Configuration write port

localparam N_TRIGGERS_PADDED = 1 << $clog2(N_TRIGGERS);
wire [N_TRIGGERS_PADDED-1:0] tselect_match = {{N_TRIGGERS_PADDED-1{1'b0}}, 1'b1} << tselect;

always @ (posedge clk or negedge rst_n) begin: cfg_update
	integer i;
	if (!rst_n) begin

		tselect <= {W_TSELECT{1'b0}};

		for (i = 0; i < BREAKPOINT_TRIGGERS; i = i + 1) begin
			tdata1_dmode[i] <= 1'b0;
			mcontrol_action[i] <= 1'b0;
			mcontrol_m[i] <= 1'b0;
			mcontrol_u[i] <= 1'b0;
			mcontrol_execute[i] <= 1'b0;
			tdata2[i] <= {W_DATA{1'b0}};
		end

		icount_m <= 1'b0;
		icount_u <= 1'b0;

		trigger_irq_m <= 1'b0;
		trigger_irq_u <= 1'b0;
		trigger_irq_dmode <= 1'b0;
		trigger_irq_cause <= 16'h0;

		trigger_exception_m <= 1'b0;
		trigger_exception_u <= 1'b0;
		trigger_exception_dmode <= 1'b0;
		trigger_exception_cause <= 16'h0;

	end else if (cfg_wen && cfg_addr == TSELECT) begin

		tselect <= cfg_wdata[W_TSELECT-1:0];

	end else if (cfg_wen && cfg_addr == TDATA1) begin

		for (i = 0; i < BREAKPOINT_TRIGGERS; i = i + 1) begin
			if (tselect_match[i] && !(tdata1_dmode[i] && !x_d_mode)) begin
				if (x_d_mode) begin
					tdata1_dmode[i] <= cfg_wdata[27];
				end
				mcontrol_action[i] <= cfg_wdata[12];
				mcontrol_m[i] <= cfg_wdata[6];
				mcontrol_u[i] <= cfg_wdata[3] && |U_MODE;
				mcontrol_execute[i] <= cfg_wdata[2];
			end
		end
		if (tselect_match[TINDEX_ICOUNT]) begin
			// This trigger does not implement a dmode bit, as Debug-mode
			// break on single-step is already provided by dcsr.step
			icount_m <= cfg_wdata[9];
			icount_u <= cfg_wdata[6] && |U_MODE;
		end
		if (tselect_match[TINDEX_INTERRUPT] && !(trigger_irq_dmode && !x_d_mode)) begin
			trigger_irq_dmode <= cfg_wdata[27];
			trigger_irq_m <= cfg_wdata[9];
			trigger_irq_u <= cfg_wdata[6] && |U_MODE;
		end
		if (tselect_match[TINDEX_EXCEPTION] && !(trigger_exception_dmode && !x_d_mode)) begin
			trigger_exception_dmode <= cfg_wdata[27];
			trigger_exception_m <= cfg_wdata[9];
			trigger_exception_u <= cfg_wdata[6] && |U_MODE;
		end

	end else if (cfg_wen && cfg_addr == TDATA2) begin

		for (i = 0; i < BREAKPOINT_TRIGGERS; i = i + 1) begin
			if (tselect_match[i] && !(tdata1_dmode[i] && !x_d_mode)) begin
				tdata2[i] <= cfg_wdata & {{W_ADDR-2{1'b1}}, |EXTENSION_C, 1'b0};
			end
		end
		if (tselect_match[TINDEX_INTERRUPT] && !(trigger_irq_dmode && !x_d_mode)) begin
			trigger_irq_cause <= cfg_wdata[15:0] & IMPLEMENTED_IRQ_CAUSES;
		end
		if (tselect_match[TINDEX_EXCEPTION] && !(trigger_exception_dmode && !x_d_mode)) begin
			trigger_exception_cause <= cfg_wdata[15:0] & IMPLEMENTED_EXCEPTION_CAUSES;
		end

	end
end

// ----------------------------------------------------------------------------
// Configuration read port

reg [W_DATA-1:0] tdata1_rdata [0:N_TRIGGERS_PADDED-1];
reg [W_DATA-1:0] tdata2_rdata [0:N_TRIGGERS_PADDED-1];
reg [W_DATA-1:0] tinfo_rdata  [0:N_TRIGGERS_PADDED-1];

always @ (*) begin: generate_padded_rdata

	// Default for unimplemented triggers
	integer i;
	for (i = 0; i < N_TRIGGERS_PADDED; i = i + 1) begin
		tdata1_rdata[i] = {W_DATA{1'b0}};
		tdata2_rdata[i] = {W_DATA{1'b0}};
		tinfo_rdata[i]  = 32'd1 << 0; // type = 0, no trigger
	end

	// Breakpoints are the first n triggers
	for (i = 0; i < BREAKPOINT_TRIGGERS; i = i + 1) begin
		tdata1_rdata[i] = {
			4'h2,                              // type = address/data match
			tdata1_dmode[i],
			6'h00,                             // maskmax = 0, exact match only
			1'b0,                              // hit = 0, not implemented
			1'b0,                              // select = 0, address match only
			1'b0,                              // timing = 0, trigger before execution
			2'h0,                              // sizelo = 0, unsized
			{3'h0, mcontrol_action[i]},        // action = 0/1, break to M-mode/D-mode
			1'b0,                              // chain = 0, chaining is useless for exact matches
			4'h0,                              // match = 0, exact match only
			mcontrol_m[i],
			1'b0,
			1'b0,                              // s = 0, no S-mode
			mcontrol_u[i],
			mcontrol_execute[i],
			1'b0,                              // store = 0, this is not a watchpoint
			1'b0                               // load = 0, this is not a watchpoint
		};
		tdata2_rdata[i] = tdata2[i];
		tinfo_rdata[i] = 32'd1 << 2;           // type = 2, address/data match
	end

	// Instruction count trigger
	tdata1_rdata[TINDEX_ICOUNT] = {
		4'h3,                                  // type = instruction count
		1'b0,                                  // dmode = 0 (Debug mode already has dcsr.step)
		2'h0,                                  // reserved
		1'b0,                                  // hit = 0
		14'd1,                                 // count = 1, single-step only
		icount_m,
		1'b0,                                  // reserved
		1'b0,                                  // s = 0, no S-mode
		icount_u,
		6'h0                                   // action = 0, break to M-mode
	};
	tinfo_rdata[TINDEX_ICOUNT] = 32'd1 << 3;   // type = 3, instruction count

	// Interrupt trigger
	tdata1_rdata[TINDEX_INTERRUPT] = {
		4'h4,                                  // type = interrupt
		trigger_irq_dmode,
		1'b0,                                  // hit = 0
		16'h0,                                 // reserved
		trigger_irq_m,
		1'b0,                                  // reserved
		1'b0,                                  // s = 0, no S-mode
		trigger_irq_u,
		6'd1                                   // action = 1, break to Debug mode (if dmode=1)
	};
	tdata2_rdata[TINDEX_INTERRUPT] = {
		16'h0,
		trigger_irq_cause & IMPLEMENTED_IRQ_CAUSES
	};
	tinfo_rdata[TINDEX_INTERRUPT] = 32'd1 << 4;

	// Exception trigger
	tdata1_rdata[TINDEX_EXCEPTION] = {
		4'h5,                                  // type = exception
		trigger_exception_dmode,
		1'b0,                                  // hit = 0
		16'h0,                                 // reserved
		trigger_exception_m,
		1'b0,                                  // reserved
		1'b0,                                  // s = 0, no S-mode
		trigger_exception_u,
		6'd1                                   // action = 1, break to Debug mode (if dmode=1)
	};
	tdata2_rdata[TINDEX_EXCEPTION] = {
		16'h0,
		trigger_exception_cause & IMPLEMENTED_EXCEPTION_CAUSES
	};
	tinfo_rdata[TINDEX_EXCEPTION] = 32'd1 << 5;

end

always @ (*) begin
	cfg_rdata = {W_DATA{1'b0}};
	if (cfg_addr == TSELECT) begin
		cfg_rdata = {{W_DATA-W_TSELECT{1'b0}}, tselect};
	end else if (cfg_addr == TDATA1) begin
		cfg_rdata = tdata1_rdata[tselect];
	end else if (cfg_addr == TDATA2) begin
		cfg_rdata = tdata2_rdata[tselect];
	end else if (cfg_addr == TINFO) begin
		cfg_rdata = tinfo_rdata[tselect];
	end
end

// ----------------------------------------------------------------------------
// Interrupt/exception trigger logic

// Ignore tcontrol.mte as these triggers never target M-mode.
wire exception_trigger_match =
	!x_d_mode && trigger_exception_dmode &&
	(x_m_mode ? trigger_exception_m : trigger_exception_u) &&
	event_exception &&
	trigger_exception_cause[event_trap_cause] &&
	IMPLEMENTED_EXCEPTION_CAUSES[event_trap_cause];

wire interrupt_trigger_match =
	!x_d_mode && trigger_irq_dmode &&
	(x_m_mode ? trigger_irq_m : trigger_irq_u) &&
	trigger_irq_cause[event_trap_cause] &&
	IMPLEMENTED_IRQ_CAUSES[event_trap_cause];

// Asserted no later than the end of the aphase for the instruction fetch at
// mtvec. Tags the dphase of trap handler instruction fetches as containing
// breakpoints.
reg break_ie;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		break_ie <= 1'b0;
	end else begin
		break_ie <= !x_d_mode && (break_ie || (
			exception_trigger_match || interrupt_trigger_match
		));
	end
end

// ----------------------------------------------------------------------------
// Breakpoint trigger logic

// To reduce the fanin of jump and load/store gating in stage X, the address
// lookup is in stage F (fetch data phase). We check *fetch addresses*, not
// program counter values. Fetches are always word-sized and word-aligned.
//
// To ensure it is safe to do this, non-debug-mode writes to the TDATA1 and
// TDATA2 CSRs cause a prefetch flush, to maintain write-to-fetch ordering.
//
// It's possible for different breakpoints to match different halfwords of the
// fetch word. The trigger unit must report both matches separately, because
// it is not known at this point where the instruction boundaries are (we
// don't have the instruction data yet).

reg [BREAKPOINT_TRIGGERS-1:0] breakpoint_enabled;
reg [BREAKPOINT_TRIGGERS-1:0] breakpoint_match;
reg [BREAKPOINT_TRIGGERS-1:0] want_d_mode_break;
reg [BREAKPOINT_TRIGGERS-1:0] want_m_mode_break;
reg [BREAKPOINT_TRIGGERS-1:0] want_d_mode_break_hw0;
reg [BREAKPOINT_TRIGGERS-1:0] want_d_mode_break_hw1;
reg [BREAKPOINT_TRIGGERS-1:0] want_m_mode_break_hw0;
reg [BREAKPOINT_TRIGGERS-1:0] want_m_mode_break_hw1;

always @ (*) begin: match_pc
	integer i;
	for (i = 0; i < BREAKPOINT_TRIGGERS; i = i + 1) begin
		// Detect tripped breakpoints
		breakpoint_enabled[i] = mcontrol_execute[i] && !fetch_d_mode && (
			fetch_m_mode ? mcontrol_m[i] : mcontrol_u[i]
		);
		breakpoint_match[i] = breakpoint_enabled[i] && fetch_addr == {tdata2[i][W_DATA-1:2], 2'b00};
		// Decide the type of break implied by the trip
		want_d_mode_break[i] = breakpoint_match[i] &&  mcontrol_action[i] && tdata1_dmode[i];
		want_m_mode_break[i] = breakpoint_match[i] && !mcontrol_action[i] && trig_m_en;
		// Report separately for each halfword, so the frontend can pass this
		// through the prefetch buffer. A breakpoint exception is taken when
		// the first halfword of an instruction (of any size) is flagged with
		// a breakpoint, implying an exact match.
		want_d_mode_break_hw0[i] = want_d_mode_break[i] && !tdata2[i][1];
		want_d_mode_break_hw1[i] = want_d_mode_break[i] &&  tdata2[i][1];
		want_m_mode_break_hw0[i] = want_m_mode_break[i] && !tdata2[i][1];
		want_m_mode_break_hw1[i] = want_m_mode_break[i] &&  tdata2[i][1];
	end
end

// Break flags to frontend (tag the current fetch dphase as containing a breakpoint):

assign break_any    = {
	|want_m_mode_break_hw1 || |want_d_mode_break_hw1 || break_ie,
	|want_m_mode_break_hw0 || |want_d_mode_break_hw0 || break_ie
};

assign break_d_mode = {
	|want_d_mode_break_hw1 || break_ie,
	|want_d_mode_break_hw0 || break_ie
};

end
endgenerate

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
