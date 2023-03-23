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

	// PC query
	input  wire [W_ADDR-1:0] pc,
	input  wire              m_mode,
	input  wire              d_mode,

	// Break request
	output wire              break_any,
	output wire              break_d_mode
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
	end else if (cfg_wen && tselect < BREAKPOINT_TRIGGERS && !(tdata1_dmode[tselect] && !d_mode)) begin
		// Handle writes to tselect-indexed registers (note writes to D-mode
		// triggers in non-D-mode are ignored rather than raising an exception)
		if (cfg_addr == TDATA1) begin
			if (d_mode) begin
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
		if (tselect >= BREAKPOINT_TRIGGERS) begin
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
		if (tselect >= BREAKPOINT_TRIGGERS) begin
			cfg_rdata = {W_DATA{1'b0}};
		end else begin
			cfg_rdata = tdata2[tselect];
		end
	end else if (cfg_addr == TINFO) begin
		if (tselect >= BREAKPOINT_TRIGGERS) begin
			cfg_rdata = 32'h00000001; // type = 0, no trigger
		end else begin
			cfg_rdata = 32'h00000004; // type = 2, address/data match
		end
	end
end

// ----------------------------------------------------------------------------
// Trigger match logic

reg [BREAKPOINT_TRIGGERS-1:0] want_d_mode_break;
reg [BREAKPOINT_TRIGGERS-1:0] want_m_mode_break;

always @ (*) begin: match_pc
	integer i;
	want_m_mode_break = {BREAKPOINT_TRIGGERS{1'b0}};
	want_d_mode_break = {BREAKPOINT_TRIGGERS{1'b0}};
	for (i = 0; i < BREAKPOINT_TRIGGERS; i = i + 1) begin
		if (mcontrol_execute[i] && tdata2[i] == pc && !d_mode && (m_mode ? mcontrol_m[i] : mcontrol_u[i])) begin
			want_d_mode_break[i] = mcontrol_action[i] && tdata1_dmode[i];
			want_m_mode_break[i] = !mcontrol_action[i] && trig_m_en;
		end
	end
end

assign break_any    = |want_m_mode_break || |want_d_mode_break;
assign break_d_mode = |want_d_mode_break;

end
endgenerate

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
