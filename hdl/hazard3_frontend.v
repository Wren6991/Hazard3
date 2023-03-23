/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module hazard3_frontend #(
`include "hazard3_config.vh"
) (
	input  wire              clk,
	input  wire              rst_n,

	// Fetch interface
	// addr_vld may be asserted at any time, but after assertion,
	// neither addr nor addr_vld may change until the cycle after addr_rdy.
	// There is no backpressure on the data interface; the front end
	// must ensure it does not request data it cannot receive.
	// addr_rdy and dat_vld may be functions of hready, and
	// may not be used to compute combinational outputs.
	output wire              mem_size, // 1'b1 -> 32 bit access
	output wire [W_ADDR-1:0] mem_addr,
	output wire              mem_priv,
	output wire              mem_addr_vld,
	input  wire              mem_addr_rdy,
	input  wire [W_DATA-1:0] mem_data,
	input  wire              mem_data_err,
	input  wire              mem_data_vld,

	// Jump/flush interface
	// Processor may assert vld at any time. The request will not go through
	// unless rdy is high. Processor *may* alter request during this time.
	// Inputs must not be a function of hready.
	input  wire [W_ADDR-1:0] jump_target,
	input  wire              jump_priv,
	input  wire              jump_target_vld,
	output wire              jump_target_rdy,

	// Interface to the branch target buffer. `src_addr` is the address of the
	// last halfword of a taken backward branch. The frontend redirects fetch
	// such that `src_addr` appears to be sequentially followed by `target`.
	input  wire              btb_set,
	input  wire [W_ADDR-1:0] btb_set_src_addr,
	input  wire              btb_set_src_size,
	input  wire [W_ADDR-1:0] btb_set_target_addr,
	input  wire              btb_clear,
	output wire [W_ADDR-1:0] btb_target_addr_out,

	// Interface to Decode
	// Note reg/wire distinction
	// => decode is providing live feedback on the CIR it is decoding,
	//    which we fetched previously
	output reg  [31:0]       cir,
	output reg  [1:0]        cir_vld,        // number of valid halfwords in CIR
	input  wire [1:0]        cir_use,        // number of halfwords D intends to consume
	                                         // *may* be a function of hready
	output wire [1:0]        cir_err,        // Bus error on upper/lower halfword of CIR.
	output wire [1:0]        cir_predbranch, // Set for last halfword of a predicted-taken branch

	// "flush_behind": do not flush the oldest instruction when accepting a
	//  jump request (but still flush younger instructions). Sometimes a
	//  stalled instruction may assert a jump request, because e.g. the stall
	//  is dependent on a bus stall signal so can't gate the request.
	input  wire              cir_flush_behind,
	// Required for regnum predecode when Zcmp is enabled:
	input  wire [3:0]        df_uop_step_next,

	// Signal to power controller that power down is safe. (When going to
	// sleep, first the pipeline is stalled, and then the power controller
	// waits for the frontend to naturally come to a halt before releasing
	// its power request. This avoids manually halting the frontend.)
	output wire              pwrdown_ok,
	// Signal to delay the first instruction fetch following reset, because
	// powerup has not yet been negotiated.
	input  wire              delay_first_fetch,

	// Provide the rs1/rs2 register numbers which will be in CIR next cycle.
	// Coarse: valid if this instruction has a nonzero register operand.
	// (Suitable for regfile read)
	output reg  [4:0]        predecode_rs1_coarse,
	output reg  [4:0]        predecode_rs2_coarse,
	// Fine: like coarse, but accurate zeroing when the operand is implicit.
	// (Suitable for bypass. Still not precise enough for stall logic.)
	output reg  [4:0]        predecode_rs1_fine,
	output reg  [4:0]        predecode_rs2_fine,

	// Debugger instruction injection: instruction fetch is suppressed when in
	// debug halt state, and the DM can then inject instructions into the last
	// entry of the prefetch queue using the vld/rdy handshake.
	input  wire              debug_mode,
	input  wire [W_DATA-1:0] dbg_instr_data,
	input  wire              dbg_instr_data_vld,
	output wire              dbg_instr_data_rdy
);

`include "rv_opcodes.vh"

localparam W_BUNDLE = 16;
// This is the minimum for full throughput (enough to avoid dropping data when
// decode stalls) and there is no significant advantage to going larger.
localparam FIFO_DEPTH = 2;

// ----------------------------------------------------------------------------
// Fetch queue

wire jump_now = jump_target_vld && jump_target_rdy;
reg [1:0] mem_data_hwvld;

// Mark data as containing a predicted-taken branch instruction so that
// mispredicts can be recovered -- need to track both halfwords so that we
// can mark the entire instruction, and nothing but the instruction:
reg [1:0] mem_data_predbranch;

// Bus errors travel alongside data. They cause an exception if the core tries
// to decode the instruction, but until then can be flushed harmlessly.

reg  [W_DATA-1:0]    fifo_mem        [0:FIFO_DEPTH];
reg                  fifo_err        [0:FIFO_DEPTH];
reg  [1:0]           fifo_predbranch [0:FIFO_DEPTH];
reg  [1:0]           fifo_valid_hw   [0:FIFO_DEPTH];
reg                  fifo_valid      [0:FIFO_DEPTH];

wire [W_DATA-1:0] fifo_rdata       = fifo_mem[0];
wire              fifo_full        = fifo_valid[FIFO_DEPTH - 1];
wire              fifo_empty       = !fifo_valid[0];
wire              fifo_almost_full = fifo_valid[FIFO_DEPTH - 2];

wire              fifo_push;
wire              fifo_pop;
wire              fifo_dbg_inject = DEBUG_SUPPORT && dbg_instr_data_vld && dbg_instr_data_rdy;

always @ (*) begin: boundary_conditions
	integer i;
	fifo_mem[FIFO_DEPTH] = mem_data;
	fifo_predbranch[FIFO_DEPTH] = 2'b00;
	fifo_err[FIFO_DEPTH] = 1'b0;
	fifo_valid_hw[FIFO_DEPTH] = 2'b00;
	fifo_valid[FIFO_DEPTH] = 1'b0;
	for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
		fifo_valid[i] = |EXTENSION_C ? |fifo_valid_hw[i] : fifo_valid_hw[i][0];
	end
end

always @ (posedge clk or negedge rst_n) begin: fifo_update
	integer i;
	if (!rst_n) begin
		for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
			fifo_valid_hw[i] <= 2'b00;
			fifo_mem[i] <= 32'h0;
			fifo_err[i] <= 1'b0;
			fifo_predbranch[i] <= 2'b00;
		end
	end else begin
		for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
			if (fifo_pop || (fifo_push && !fifo_valid[i])) begin
				fifo_mem[i]        <= fifo_valid[i + 1] ? fifo_mem[i + 1]        : mem_data;
				fifo_err[i]        <= fifo_valid[i + 1] ? fifo_err[i + 1]        : mem_data_err;
				fifo_predbranch[i] <= fifo_valid[i + 1] ? fifo_predbranch[i + 1] : mem_data_predbranch;
			end
			fifo_valid_hw[i] <=
				jump_now                                                 ? 2'h0                            :
				fifo_valid[i + 1] && fifo_pop                            ? fifo_valid_hw[i + 1]            :
				fifo_valid[i]     && fifo_pop                            ? mem_data_hwvld & {2{fifo_push}} :
				fifo_valid[i]                                            ? fifo_valid_hw[i]                :
				fifo_push && !fifo_pop && (i == 0 || fifo_valid[i - |i]) ? mem_data_hwvld                  : 2'h0;
		end
		// Allow DM to inject instructions directly into the lowest-numbered
		// queue entry. This mux should not extend critical path since it is
		// balanced with the instruction-assembly muxes on the queue bypass
		// path. Note that flush takes precedence over debug injection
		// (and the debug module design must account for this)
		if (fifo_dbg_inject) begin
			fifo_mem[0] <= dbg_instr_data;
			fifo_err[0] <= 1'b0;
			fifo_predbranch[0] <= 2'b00;
			fifo_valid_hw[0] <= jump_now ? 2'b00 : 2'b11;
		end
`ifdef HAZARD3_ASSERTIONS
		// FIFO validity must be compact, so we can always consume from the end
		if (!fifo_valid[0]) begin
			assert(!fifo_valid[1]);
		end
`endif
	end
end

assign pwrdown_ok = fifo_full && !jump_target_vld;

// ----------------------------------------------------------------------------
// Branch target buffer

reg [W_ADDR-1:0] btb_src_addr;
reg              btb_src_size;
reg [W_ADDR-1:0] btb_target_addr;
reg              btb_valid;

generate
if (BRANCH_PREDICTOR) begin: have_btb
	always @ (posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			btb_src_addr <= {W_ADDR{1'b0}};
			btb_src_size <= 1'b0;
			btb_target_addr <= {W_ADDR{1'b0}};
			btb_valid <= 1'b0;
		end else if (btb_clear) begin
			// Clear takes precedences over set. E.g. if a taken branch is in
			// stage 2 and an exception is in stage 3, we must clear the BTB.
			btb_valid <= 1'b0;
		end else if (btb_set) begin
			btb_src_addr <= btb_set_src_addr;
			btb_src_size <= btb_set_src_size;
			btb_target_addr <= btb_set_target_addr;
			btb_valid <= 1'b1;
		end
	end
end else begin: no_btb
	always @ (*) begin
		btb_src_addr = {W_ADDR{1'b0}};
		btb_target_addr = {W_ADDR{1'b0}};
		btb_valid = 1'b0;
	end
end
endgenerate

// Decode uses the target address to set the PC to the correct branch target
// value following a predicted-taken branch (as normally it would update PC
// by following an X jump request, and in this case there is none).
//
// Note this assumes the BTB target has not changed by the time the predicted
// branch arrives at decode! This is always true because the only way for the
// target address to change is when an older branch is taken, which would
// flush the younger predicted-taken branch before it reaches decode. 

assign btb_target_addr_out = btb_target_addr;

// ----------------------------------------------------------------------------
// Fetch request generation

// Fetch addr runs ahead of the PC, in word increments.
reg [W_ADDR-1:0] fetch_addr;
reg              fetch_priv;
reg              btb_prev_start_of_overhanging;
reg [1:0]        mem_aph_hwvld;
reg              mem_addr_hold;

wire btb_match_word = |BRANCH_PREDICTOR && btb_valid && (
	fetch_addr[W_ADDR-1:2] == btb_src_addr[W_ADDR-1:2]
);

// Catch case where predicted-taken branch instruction extends into next word:
wire btb_src_overhanging    = btb_src_size && btb_src_addr[1];

// Suppress case where we have jumped immediately after a word-aligned halfword-sized
// branch, and the jump target went into fetch_addr due to an address-phase hold:
wire btb_jumped_beyond      = !btb_src_size && !btb_src_addr[1] && !mem_aph_hwvld[0];

wire btb_match_current_addr = btb_match_word && !btb_src_overhanging && !btb_jumped_beyond;
wire btb_match_next_addr    = btb_match_word && btb_src_overhanging;

wire btb_match_now = btb_match_current_addr || btb_prev_start_of_overhanging;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		fetch_addr <= RESET_VECTOR;
		// M-mode at reset:
		fetch_priv <= 1'b1;
		btb_prev_start_of_overhanging <= 1'b0;
	end else begin
		if (jump_now) begin
			// Post-increment if jump request is going straight through
			fetch_addr <= {jump_target[W_ADDR-1:2] + (mem_addr_rdy && !mem_addr_hold), 2'b00};
			fetch_priv <= jump_priv || !U_MODE;
			btb_prev_start_of_overhanging <= 1'b0;
		end else if (mem_addr_vld && mem_addr_rdy) begin
			if (btb_match_now && |BRANCH_PREDICTOR) begin
				fetch_addr <= {btb_target_addr[W_ADDR-1:2], 2'b00};
			end else begin
				fetch_addr <= fetch_addr + 32'h4;
			end
			btb_prev_start_of_overhanging <= btb_match_next_addr;
		end
	end
end

// Combinatorially generate the address-phase request

reg reset_holdoff;
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		reset_holdoff <= 1'b1;
	end else begin
		reset_holdoff <= (|EXTENSION_XH3POWER && delay_first_fetch) ? reset_holdoff : 1'b0;
		// This should be impossible, but assert to be sure, because it *will*
		// change the fetch address (and we shouldn't check it in hardware if
		// we can prove it doesn't happen)
`ifdef HAZARD3_ASSERTIONS
		assert(!(jump_target_vld && reset_holdoff));
`endif
	end
end

reg [W_ADDR-1:0] mem_addr_r;
reg              mem_priv_r;
reg              mem_addr_vld_r;

// Downstream accesses are always word-sized word-aligned.
assign mem_addr = mem_addr_r;
assign mem_priv = mem_priv_r;
assign mem_addr_vld = mem_addr_vld_r && !reset_holdoff;
assign mem_size = 1'b1;

wire fetch_stall;

always @ (*) begin
	mem_addr_r = fetch_addr;
	mem_priv_r = fetch_priv;
	mem_addr_vld_r = 1'b1;
	case (1'b1)
		mem_addr_hold                    : begin mem_addr_r = fetch_addr; end
		jump_target_vld || reset_holdoff : begin
		                                         mem_addr_r = {jump_target[W_ADDR-1:2], 2'b00};
		                                         mem_priv_r = jump_priv || !U_MODE;
		end
		DEBUG_SUPPORT && debug_mode      : begin mem_addr_vld_r = 1'b0; end
		!fetch_stall                     : begin mem_addr_r = fetch_addr; end
		default                          : begin mem_addr_vld_r = 1'b0; end
	endcase
end

assign jump_target_rdy = !mem_addr_hold;

// ----------------------------------------------------------------------------
// Bus Pipeline Tracking

// Keep track of some useful state of the memory interface

reg  [1:0] pending_fetches;
reg  [1:0] ctr_flush_pending;

wire [1:0] pending_fetches_next = pending_fetches + (mem_addr_vld && !mem_addr_hold) - mem_data_vld;

// Using the non-registered version of pending_fetches would improve FIFO
// utilisation, but create a combinatorial path from hready to address phase!
// This means at least a 2-word FIFO is required for full fetch throughput.
assign fetch_stall = fifo_full
	|| fifo_almost_full && |pending_fetches
	|| pending_fetches > 2'h1;

// Debugger only injects instructions when the frontend is at rest and empty.
assign dbg_instr_data_rdy = DEBUG_SUPPORT && !fifo_valid[0] && ~|ctr_flush_pending;

wire cir_room_for_fetch;
// If fetch data is forwarded past the FIFO, ensure it is not also written to it.
assign fifo_push = mem_data_vld && ~|ctr_flush_pending && !(cir_room_for_fetch && fifo_empty)
	&& !(DEBUG_SUPPORT && debug_mode);

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mem_addr_hold <= 1'b0;
		pending_fetches <= 2'h0;
		ctr_flush_pending <= 2'h0;
	end else begin
`ifdef HAZARD3_ASSERTIONS
		assert(ctr_flush_pending <= pending_fetches);
		assert(pending_fetches < 2'd3);
		assert(!(mem_data_vld && !pending_fetches));
`endif
		mem_addr_hold <= mem_addr_vld && !mem_addr_rdy;
		pending_fetches <= pending_fetches_next;
		if (jump_now) begin
			ctr_flush_pending <= pending_fetches - mem_data_vld;
		end else if (|ctr_flush_pending && mem_data_vld) begin
			ctr_flush_pending <= ctr_flush_pending - 1'b1;
		end
	end
end

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mem_data_hwvld <= 2'b11;
		mem_aph_hwvld <= 2'b11;
		mem_data_predbranch <= 2'b00;
	end else begin
		if (jump_now) begin
			if (|EXTENSION_C) begin
				if (mem_addr_rdy) begin
					mem_aph_hwvld <= 2'b11;
					mem_data_hwvld <= {1'b1, !jump_target[1]};
				end else begin
					mem_aph_hwvld <= {1'b1, !jump_target[1]};
				end
			end
			mem_data_predbranch <= 2'b00;
		end else if (mem_addr_vld && mem_addr_rdy) begin
			if (|EXTENSION_C) begin
				// If a predicted-taken branch instruction only spans the first
				// half of a word, need to flag the second half as invalid. 
				mem_data_hwvld <= mem_aph_hwvld & {
					!(|BRANCH_PREDICTOR && btb_match_now && (btb_src_addr[1] == btb_src_size)),
					1'b1
				};
				// Also need to take the alignment of the destination into account.
				mem_aph_hwvld <= {
					1'b1,
					!(|BRANCH_PREDICTOR && btb_match_now && btb_target_addr[1])
				};
			end
			mem_data_predbranch <=
				|BRANCH_PREDICTOR && btb_match_word ? (
					btb_src_addr[1] ? 2'b10 :
					btb_src_size    ? 2'b11 : 2'b01
				) :
				|BRANCH_PREDICTOR && btb_prev_start_of_overhanging ? (
					2'b01
				) : 2'b00;
		end
	end
end

// ----------------------------------------------------------------------------
// Instruction assembly yard

// buf_level is the number of valid halfwords in {hwbuf, cir}.
reg [1:0] buf_level;
reg [W_BUNDLE-1:0] hwbuf;

wire [W_DATA-1:0] fetch_data = fifo_empty ? mem_data : fifo_rdata;
wire [1:0] fetch_data_hwvld = fifo_empty ? mem_data_hwvld : fifo_valid_hw[0];
wire fetch_data_vld = !fifo_empty || (mem_data_vld && ~|ctr_flush_pending && !debug_mode);

wire [2*W_BUNDLE-1:0] fetch_data_aligned = {
	fetch_data[W_BUNDLE +: W_BUNDLE],
	fetch_data_hwvld[0] || ~|EXTENSION_C ?
		fetch_data[0 +: W_BUNDLE] : fetch_data[W_BUNDLE +: W_BUNDLE]
};

// Shift any recycled instruction data down to backfill D's consumption
// We don't care about anything which is invalid or will be overlaid with fresh data,
// so choose these values in a way that minimises muxes
wire [3*W_BUNDLE-1:0] instr_data_shifted =
	cir_use[1]                ? {hwbuf, cir[W_BUNDLE +: W_BUNDLE], hwbuf} :
	cir_use[0] && EXTENSION_C ? {hwbuf, hwbuf, cir[W_BUNDLE +: W_BUNDLE]} :
	                            {hwbuf, cir};

wire [1:0] level_next_no_fetch = buf_level - cir_use;

// Overlay fresh fetch data onto the shifted/recycled instruction data
// Again, if something won't be looked at, generate cheapest possible garbage.
assign cir_room_for_fetch = level_next_no_fetch <= (|EXTENSION_C && ~&fetch_data_hwvld ? 2'h2 : 2'h1);
assign fifo_pop = cir_room_for_fetch && !fifo_empty;

wire [3*W_BUNDLE-1:0] instr_data_plus_fetch =
	!cir_room_for_fetch                    ? instr_data_shifted :
	level_next_no_fetch[1] && |EXTENSION_C ? {fetch_data_aligned[0 +: W_BUNDLE], instr_data_shifted[0 +: 2 * W_BUNDLE]} :
	level_next_no_fetch[0] && |EXTENSION_C ? {fetch_data_aligned, instr_data_shifted[0 +: W_BUNDLE]} :
	                                         {instr_data_shifted[2 * W_BUNDLE +: W_BUNDLE], fetch_data_aligned};

// Also keep track of bus errors associated with CIR contents, shifted in the
// same way as instruction data. Errors may come straight from the bus, or
// may be buffered in the prefetch queue.

wire fetch_bus_err = fifo_empty ? mem_data_err : fifo_err[0];

reg  [2:0] cir_bus_err;
wire [2:0] cir_bus_err_shifted =
	cir_use[1]                ? cir_bus_err >> 2 :
	cir_use[0] && EXTENSION_C ? cir_bus_err >> 1 : cir_bus_err;

wire [2:0] cir_bus_err_plus_fetch =
	!cir_room_for_fetch                    ? cir_bus_err_shifted :
	level_next_no_fetch[1] && |EXTENSION_C ? {fetch_bus_err, cir_bus_err_shifted[1:0]} :
	level_next_no_fetch[0] && |EXTENSION_C ? {{2{fetch_bus_err}}, cir_bus_err_shifted[0]} :
	                                         {cir_bus_err_shifted[2], {2{fetch_bus_err}}};

// And the same thing again for whether CIR contains a predicted-taken branch.
// One day I should clean up this copy/paste.

wire [1:0] fetch_predbranch = fifo_empty ? mem_data_predbranch : fifo_predbranch[0];
wire [1:0] fetch_predbranch_aligned = {
	fetch_predbranch[1],
	fetch_data_hwvld[0] || ~|EXTENSION_C ? fetch_predbranch[0] : fetch_predbranch[1]
};


reg  [2:0] cir_predbranch_reg;
wire [2:0] cir_predbranch_shifted =
	cir_use[1]                ? cir_predbranch_reg >> 2 :
	cir_use[0] && EXTENSION_C ? cir_predbranch_reg >> 1 : cir_predbranch_reg;

wire [2:0] cir_predbranch_plus_fetch =
	!cir_room_for_fetch                    ? cir_predbranch_shifted :
	level_next_no_fetch[1] && |EXTENSION_C ? {fetch_predbranch_aligned[0], cir_predbranch_shifted[1:0]} :
	level_next_no_fetch[0] && |EXTENSION_C ? {fetch_predbranch_aligned, cir_predbranch_shifted[0]} :
	                                         {cir_predbranch_shifted[2], fetch_predbranch_aligned};

wire [1:0] fetch_fill_amount = cir_room_for_fetch && fetch_data_vld ? (
	&fetch_data_hwvld ? 2'h2 : 2'h1
) : 2'h0;

wire [1:0] buf_level_next =
	jump_now && cir_flush_behind   ? (cir[1:0] == 2'b11 || ~|EXTENSION_C ? 2'h2 : 2'h1) :
	jump_now                       ? 2'h0 : level_next_no_fetch + fetch_fill_amount;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		buf_level <= 2'h0;
		cir_vld <= 2'h0;
		hwbuf <= 16'h0;
		cir <= 16'h0;
		cir_bus_err <= 3'h0;
		cir_predbranch_reg <= 3'h0;
	end else begin
`ifdef HAZARD3_ASSERTIONS
		assert(cir_vld <= 2);
 		assert(cir_use <= cir_vld);
 		if (!jump_now)
	 		assert(buf_level_next >= level_next_no_fetch);
`endif
		buf_level <= buf_level_next;
		cir_vld <= buf_level_next & ~(buf_level_next >> 1'b1);
		cir_bus_err <= cir_bus_err_plus_fetch;
		cir_predbranch_reg <= cir_predbranch_plus_fetch;
		{hwbuf, cir} <= instr_data_plus_fetch;
	end
end

`ifdef HAZARD3_ASSERTIONS
reg [1:0] property_past_buf_level; // Workaround for weird non-constant $past reset issue
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		property_past_buf_level <= 2'h0;
	end else begin
		property_past_buf_level <= buf_level;
		// We fetch 32 bits per cycle, max. If this happens it's due to negative overflow.
		if (property_past_buf_level == 2'h0)
			assert(buf_level != 2'h3);
	end
end
`endif

assign cir_err = cir_bus_err[1:0];
assign cir_predbranch = cir_predbranch_reg[1:0];

// ----------------------------------------------------------------------------
// Register number predecode

wire [31:0] next_instr = instr_data_plus_fetch[31:0];
wire next_instr_is_32bit = next_instr[1:0] == 2'b11 || ~|EXTENSION_C;


wire [3:0] uop_ctr = df_uop_step_next & {4{|EXTENSION_ZCMP}};

wire [4:0] zcmp_pushpop_rs2 =
	uop_ctr == 4'h0 ? 5'd01                   : // ra
	uop_ctr == 4'h1 ? 5'd08                   : // s0
	uop_ctr == 4'h2 ? 5'd09                   : // s1
	                  5'd15 + {1'b0, uop_ctr} ; // s2-s11

wire [4:0] zcmp_pushpop_rs1 =
	uop_ctr <  4'hd ? 5'd02 :                   // sp   (addr base reg)
	uop_ctr == 4'hd ? 5'd00 :                   // zero (clear a0)
	uop_ctr == 4'he ? 5'd01 :                   // ra   (ret)
	                  5'd02 ;                   // sp   (stack adj)

wire [4:0] zcmp_sa01_r1s  = {|next_instr[9:8], ~|next_instr[9:8], next_instr[9:7]};
wire [4:0] zcmp_sa01_r2s  = {|next_instr[4:3], ~|next_instr[4:3], next_instr[4:2]};

wire [4:0] zcmp_mvsa01_rs1 = {4'h5, uop_ctr[0]};
wire [4:0] zcmp_mva01s_rs1 = uop_ctr[0] ? zcmp_sa01_r2s : zcmp_sa01_r1s;

always @ (*) begin

	casez ({next_instr_is_32bit, |EXTENSION_ZCMP, next_instr[15:0]})
	{1'b1, 1'bz, 16'bzzzzzzzzzzzzzzzz}: predecode_rs1_coarse = next_instr[19:15]; // 32-bit R, S, B formats
	{1'b0, 1'bz, 16'b00zzzzzzzzzzzz00}: predecode_rs1_coarse = 5'd2;              // c.addi4spn + don't care
	{1'b0, 1'bz, 16'b0zzzzzzzzzzzzz01}: predecode_rs1_coarse = next_instr[11:7];  // c.addi, c.addi16sp + don't care (jal, li)
	{1'b0, 1'bz, 16'b100zzzzzzzzzzz10}: predecode_rs1_coarse = next_instr[11:7];  // c.add
	{1'b0, 1'bz, 16'bz10zzzzzzzzzzz10}: predecode_rs1_coarse = 5'd2;              // c.lwsp, c.swsp
	{1'b0, 1'bz, 16'bz00zzzzzzzzzzz10}: predecode_rs1_coarse = next_instr[11:7];  // c.slli, c.mv, c.add
	{1'b0, 1'b1, 16'b1z11zzzzzzzzzz10}: predecode_rs1_coarse = zcmp_pushpop_rs1;  // cm.push, cm.pop*
	{1'b0, 1'b1, 16'b1z10zzzzz0zzzz10}: predecode_rs1_coarse = zcmp_mvsa01_rs1;   // cm.mvsa01
	{1'b0, 1'b1, 16'b1z10zzzzz1zzzz10}: predecode_rs1_coarse = zcmp_mva01s_rs1;   // cm.mva01s
	default:                            predecode_rs1_coarse = {2'b01, next_instr[9:7]};
	endcase

	casez ({next_instr_is_32bit, next_instr[1:0], next_instr[13]})
	{1'b1, 2'bzz, 1'bz}: predecode_rs2_coarse = next_instr[24:20];
	{1'b0, 2'b10, 1'b0}: predecode_rs2_coarse = next_instr[6:2];    // c.add, c.swsp
	{1'b0, 2'b10, 1'b1}: predecode_rs2_coarse = zcmp_pushpop_rs2;   // cm.push
	default:             predecode_rs2_coarse = {2'b01, next_instr[4:2]};
	endcase

	// The "fine" predecode targets those instructions which either:
	// - Have an implicit zero-register operand in their expanded form (e.g. c.beqz)
	// - Do not have a register operand on that port, but rely on the port being 0
	// We don't care about instructions which ignore the reg ports, e.g. ebreak

	casez ({|EXTENSION_C, next_instr})
	// -> addi rd, x0, imm:
	{1'b1, 16'hzzzz, `RVOPC_C_LI}: predecode_rs1_fine = 5'd0;
	{1'b1, 16'hzzzz, `RVOPC_C_MV}: begin
		if (next_instr[6:2] == 5'd0) begin
			// c.jr has rs1 as normal
			predecode_rs1_fine = predecode_rs1_coarse;
		end else begin
			// -> add rd, x0, rs2:
			predecode_rs1_fine = 5'd0;
		end
	end
	default: predecode_rs1_fine = predecode_rs1_coarse;
	endcase

	casez ({|EXTENSION_C, next_instr})
	{1'b1, 16'hzzzz, `RVOPC_C_BEQZ}: predecode_rs2_fine = 5'd0;    // -> beq rs1, x0, label
	{1'b1, 16'hzzzz, `RVOPC_C_BNEZ}: predecode_rs2_fine = 5'd0;    // -> bne rs1, x0, label
	default:                         predecode_rs2_fine = predecode_rs2_coarse;
	endcase


end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
