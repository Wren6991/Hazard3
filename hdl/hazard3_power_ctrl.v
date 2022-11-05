/*****************************************************************************\
|                        Copyright (C) 2022 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

// Wake/sleep (power) state machine for Hazard3

module hazard3_power_ctrl #(
`include "hazard3_config.vh"
) (
	input  wire              clk_always_on,
	input  wire              rst_n,

	// 4-phase (Gray code) req/ack handshake for requesting and releasing
	// power+clock enable on non-processor hardware, e.g. the bus fabric. This
	// can also be used for an external controller to gate the processor's clk
	// input, rather than the clk_en signal below.
	output reg               pwrup_req,
	input  wire              pwrup_ack,

	// Top-level clock enable for an optional clock gate on the processor's clk
	// input (but not clk_always_on, which clocks this module and the IRQ input
	// flops). This allows the processor to clock-gate when sleeping. It's
	// acceptable for the clock gate cell to have one cycle of delay when
	// clk_en changes.
	output reg               clk_en,

	// Power state controls from CSRs
	input  wire              allow_clkgate,
	input  wire              allow_power_down,
	input  wire              allow_sleep_on_block,

	// Signal from frontend that it has stalled against the WFI pipeline
	// stall, and we are now clear to enter a deep sleep state
	input  wire              frontend_pwrdown_ok,

	input  wire              sleeping_on_wfi,
	input  wire              wfi_wakeup_req,
	input  wire              sleeping_on_block,
	input  wire              block_wakeup_req_pulse,
	output reg               stall_release
);

// ----------------------------------------------------------------------------
// Wake/sleep state machine

localparam W_STATE              = 2;
localparam S_AWAKE              = 2'h0;
localparam S_ENTER_ASLEEP       = 2'h1;
localparam S_ASLEEP             = 2'h2;
localparam S_ENTER_AWAKE        = 2'h3;

reg [W_STATE-1:0] state;
reg               block_wakeup_req;

wire active_wake_req =
	(sleeping_on_block && (block_wakeup_req || wfi_wakeup_req)) ||
	(sleeping_on_wfi && wfi_wakeup_req);

// Note: we assert our power up request during reset, and *assume* that the
// power up acknowledge is also high at reset. If this is a problem, extend
// the core reset.

always @ (posedge clk_always_on or negedge rst_n) begin
	if (!rst_n) begin
		state <= S_AWAKE;
		pwrup_req <= 1'b1;
		clk_en <= 1'b1;
		stall_release <= 1'b0;
	end else begin
		stall_release <= 1'b0;
		case (state)
		S_AWAKE: if (sleeping_on_wfi || sleeping_on_block) begin
			if (stall_release) begin
				// The last cycle of an ongoing which we have just released. Sit
				// tight, this instruction will move down the pipeline at the
				// end of this cycle. (There is an assertion that this doesn't
				// happen twice.)
				state <= S_AWAKE;
			end else if (active_wake_req) begin
				// Skip deep sleep if it would immediately fall through.
				stall_release <= 1'b1;
			end else if ((allow_power_down || allow_clkgate) && (sleeping_on_wfi || allow_sleep_on_block)) begin
				if (frontend_pwrdown_ok) begin
					pwrup_req <= !allow_power_down;
					clk_en <= !allow_clkgate;
					state <= allow_power_down ? S_ENTER_ASLEEP : S_ASLEEP;
				end else begin
					// Stay awake until it is safe to power down (i.e. until our
					// instruction fetch goes quiet).
					state <= S_AWAKE;
				end					
			end else begin
				// No power state change. Just sit with the pipeline stalled.
				state <= S_AWAKE;
			end
		end
		S_ENTER_ASLEEP: if (!pwrup_ack) begin
			state <= S_ASLEEP;
		end
		S_ASLEEP: if (active_wake_req) begin
			pwrup_req <= 1'b1;
			clk_en <= 1'b1;
			// Still go through the enter state for non-power-down wakeup, in
			// case the clock gate cell has a 1 cycle delay.
			state <= S_ENTER_AWAKE;
		end
		S_ENTER_AWAKE: if (pwrup_ack || !allow_power_down) begin
			state <= S_AWAKE;
			stall_release <= 1'b1;
		end
		default: begin
			state <= S_AWAKE;
		end
		endcase
	end
end

`ifdef HAZARD3_ASSERTIONS
// Regs are a workaround for the non-constant reset value issue with
// $past() in yosys-smtbmc.
reg past_sleeping;
reg past_stall_release;
always @ (posedge clk_always_on or negedge rst_n) begin
	if (!rst_n) begin
		past_sleeping <= 1'b0;
		past_stall_release <= 1'b0;
	end else begin
		past_sleeping <= sleeping_on_wfi || sleeping_on_block;
		past_stall_release <= stall_release;
		// These must always be mutually exclusive.
		assert(!(sleeping_on_wfi && sleeping_on_block));
		if (stall_release) begin
			// Presumably there was a stall which we just released
			assert(past_sleeping);
			// Presumably we are still in that stall
			assert(sleeping_on_wfi|| sleeping_on_block);
			// It takes one cycle to do a release and enter a new sleep state, so a
			// double release should be impossible.
			assert(!past_stall_release);
		end
		if (state == S_ASLEEP) begin
			assert(allow_power_down || allow_clkgate);
		end
	end
end
`endif

// ----------------------------------------------------------------------------
// Pulse->level for block wakeup

// Unblock signal is sticky: a prior unblock with no block since will cause
// the next block to immediately fall through.

always @ (posedge clk_always_on or negedge rst_n) begin
	if (!rst_n) begin
		block_wakeup_req <= 1'b0;
	end else begin
		// Note the OR takes precedence over the AND, so we don't miss a second
		// unblock that arrives at the instant we wake up.
		block_wakeup_req <= (block_wakeup_req && !(
			sleeping_on_block && stall_release
		)) || block_wakeup_req_pulse;
	end
end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
