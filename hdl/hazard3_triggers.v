/*****************************************************************************\
|                        Copyright (C) 2022 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

// Trigger unit. Currently only breakpoint (type=2 execute=1 select=0)
// triggers are supported. Only exact address matches are supported, and the
// timing is always "early".

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

	// Fetch address query
	input  wire [W_ADDR-1:0] fetch_addr,
	input  wire              fetch_m_mode,
	input  wire              fetch_d_mode,

	// Break request (for each halfword of the word-sized word-aligned fetch)
	output wire [1:0]        break_any,
	output wire [1:0]        break_d_mode,

	// Stage-X debug mode flag, for CSR protection (may or may not be the same
	// as the query debug mode flag)
	input  wire              x_d_mode
);

`include "hazard3_csr_addr.vh"

generate
if (BREAKPOINT_TRIGGERS == 0) begin: no_triggers

// The instantiation of this block should already be stubbed out in core.v if
// there are no triggers, but we still get warnings for elaborating this
// module with zero triggers, so add a generate block here too.

always @ (*) cfg_rdata = {W_DATA{1'b0}};
assign break_any = 1'b0;
assign break_d_mode = 1'b0;

end else begin: have_triggers

// ----------------------------------------------------------------------------
// Configuration state

parameter W_TSELECT = $clog2(BREAKPOINT_TRIGGERS);

reg [W_TSELECT-1:0] tselect;
wire tselect_in_range = {{32-W_TSELECT{1'sb0}}, $signed(tselect)} < BREAKPOINT_TRIGGERS;

// Note tdata1 and mcontrol are the same CSR. tdata1 refers to the universal
// fields (type/dmode) and mcontrol refers to those fields specific to
// type=2 (address/data match), the only trigger type we implement.

reg              tdata1_dmode     [0:BREAKPOINT_TRIGGERS-1];
reg              mcontrol_action  [0:BREAKPOINT_TRIGGERS-1];
reg              mcontrol_m       [0:BREAKPOINT_TRIGGERS-1];
reg              mcontrol_u       [0:BREAKPOINT_TRIGGERS-1];
reg              mcontrol_execute [0:BREAKPOINT_TRIGGERS-1];
reg [W_DATA-1:0] tdata2           [0:BREAKPOINT_TRIGGERS-1];

// ----------------------------------------------------------------------------
// Configuration write port

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
	end else if (cfg_wen && cfg_addr == TSELECT) begin
		tselect <= cfg_wdata[W_TSELECT-1:0];
	end else if (cfg_wen && tselect_in_range && !(tdata1_dmode[tselect] && !x_d_mode)) begin
		// Handle writes to tselect-indexed registers (note writes to D-mode
		// triggers in non-D-mode are ignored rather than raising an exception)
		if (cfg_addr == TDATA1) begin
			if (x_d_mode) begin
				tdata1_dmode[tselect] <= cfg_wdata[27];
			end
			mcontrol_action[tselect] <= cfg_wdata[12];
			mcontrol_m[tselect] <= cfg_wdata[6];
			mcontrol_u[tselect] <= cfg_wdata[3];
			mcontrol_execute[tselect] <= cfg_wdata[2];
		end else if (cfg_addr == TDATA2) begin
			tdata2[tselect] <= cfg_wdata;
		end
	end
end

// ----------------------------------------------------------------------------
// Configuration read port

always @ (*) begin
	cfg_rdata = {W_DATA{1'b0}};
	if (cfg_addr == TSELECT) begin
		cfg_rdata = {{W_DATA-W_TSELECT{1'b0}}, tselect};
	end else if (cfg_addr == TDATA1) begin
		if (!tselect_in_range) begin
			// Nonexistent -> type=0
			cfg_rdata = {W_DATA{1'b0}};
		end else begin
			cfg_rdata = {
				4'h2,                              // type = address/data match
				tdata1_dmode[tselect],
				6'h00,                             // maskmax = 0, exact match only
				1'b0,                              // hit = 0, not implemented
				1'b0,                              // select = 0, address match only
				1'b0,                              // timing = 0, trigger before execution
				2'h0,                              // sizelo = 0, unsized
				{3'h0, mcontrol_action[tselect]},  // action = 0/1, break to M-mode/D-mode
				1'b0,                              // chain = 0, chaining is useless for exact matches
				4'h0,                              // match = 0, exact match only
				mcontrol_m[tselect],
				1'b0,
				1'b0,                              // s = 0, no S-mode
				mcontrol_u[tselect],
				mcontrol_execute[tselect],
				1'b0,                              // store = 0, this is not a watchpoint
				1'b0                               // load = 0, this is not a watchpoint
			};
		end
	end else if (cfg_addr == TDATA2) begin
		if (!tselect_in_range) begin
			cfg_rdata = {W_DATA{1'b0}};
		end else begin
			cfg_rdata = tdata2[tselect];
		end
	end else if (cfg_addr == TINFO) begin
		if (!tselect_in_range) begin
			cfg_rdata = 32'h00000001; // type = 0, no trigger
		end else begin
			cfg_rdata = 32'h00000004; // type = 2, address/data match
		end
	end
end

// ----------------------------------------------------------------------------
// Trigger match logic

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

reg [BREAKPOINT_TRIGGERS-1:0] trigger_enabled;
reg [BREAKPOINT_TRIGGERS-1:0] trigger_match;
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
		trigger_enabled[i] = mcontrol_execute[i] && !fetch_d_mode && (
			fetch_m_mode ? mcontrol_m[i] : mcontrol_u[i]
		);
		trigger_match[i] = fetch_addr == {tdata2[i][W_DATA-1:2], 2'b00};
		// Decide the type of break implied by the trip
		want_d_mode_break[i] = trigger_match[i] &&  mcontrol_action[i] && tdata1_dmode[i];
		want_m_mode_break[i] = trigger_match[i] && !mcontrol_action[i] && trig_m_en;
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

assign break_any    = {
	|want_m_mode_break_hw1 || |want_d_mode_break_hw1,
	|want_m_mode_break_hw0 || |want_d_mode_break_hw0
};

assign break_d_mode = {
	|want_d_mode_break_hw1,
	|want_d_mode_break_hw0
};

end
endgenerate

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
