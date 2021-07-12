/**********************************************************************
 * DO WHAT THE FUCK YOU WANT TO AND DON'T BLAME US PUBLIC LICENSE     *
 *                    Version 3, April 2008                           *
 *                                                                    *
 * Copyright (C) 2021 Luke Wren                                       *
 *                                                                    *
 * Everyone is permitted to copy and distribute verbatim or modified  *
 * copies of this license document and accompanying software, and     *
 * changing either is allowed.                                        *
 *                                                                    *
 *   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION  *
 *                                                                    *
 * 0. You just DO WHAT THE FUCK YOU WANT TO.                          *
 * 1. We're NOT RESPONSIBLE WHEN IT DOESN'T FUCKING WORK.             *
 *                                                                    *
 *********************************************************************/

// Implementation of standard RISC-V JTAG-DTM with an APB Debug Module
// Interface. The TAP itself is clocked directly by JTAG TCK; a clock
// crossing is instantiated internally between the TCK domain and the DMI bus
// clock domain.

`default_nettype none

module hazard3_jtag_dtm #(
	parameter IDCODE = 32'h0000_0001,
	parameter DTMCS_IDLE_HINT = 3'd4
) (
	// Standard JTAG signals -- the JTAG hardware is clocked directly by TCK.
	input  wire        tck,
	input  wire        trst_n,
	input  wire        tms,
	input  wire        tdi,
	output reg         tdo,

	// This is synchronous to TCK and asserted for one TCK cycle only
	output reg         dmihardreset_req,

	// Bus clock + reset for Debug Module Interface
	input  wire        clk_dmi,
	input  wire        rst_n_dmi,

	// Debug Module Interface (APB)
	output wire        dmi_psel,
	output wire        dmi_penable,
	output wire        dmi_pwrite,
	output wire [7:0]  dmi_paddr,
	output wire [31:0] dmi_pwdata,
	input  wire [31:0] dmi_prdata,
	input  wire        dmi_pready,
	input  wire        dmi_pslverr
);

// ----------------------------------------------------------------------------
// TAP state machine

reg [3:0] tap_state;
localparam S_RESET      = 4'd0;
localparam S_RUN_IDLE   = 4'd1;
localparam S_SELECT_DR  = 4'd2;
localparam S_CAPTURE_DR = 4'd3;
localparam S_SHIFT_DR   = 4'd4;
localparam S_EXIT1_DR   = 4'd5;
localparam S_PAUSE_DR   = 4'd6;
localparam S_EXIT2_DR   = 4'd7;
localparam S_UPDATE_DR  = 4'd8;
localparam S_SELECT_IR  = 4'd9;
localparam S_CAPTURE_IR = 4'd10;
localparam S_SHIFT_IR   = 4'd11;
localparam S_EXIT1_IR   = 4'd12;
localparam S_PAUSE_IR   = 4'd13;
localparam S_EXIT2_IR   = 4'd14;
localparam S_UPDATE_IR  = 4'd15;

always @ (posedge tck or negedge trst_n) begin
	if (!trst_n) begin
		tap_state <= S_RESET;
	end else case(tap_state)
		S_RESET      : tap_state <= tms ? S_RESET     : S_RUN_IDLE  ;
		S_RUN_IDLE   : tap_state <= tms ? S_SELECT_DR : S_RUN_IDLE  ;

		S_SELECT_DR  : tap_state <= tms ? S_SELECT_IR : S_CAPTURE_DR;
		S_CAPTURE_DR : tap_state <= tms ? S_EXIT1_DR  : S_SHIFT_DR  ;
		S_SHIFT_DR   : tap_state <= tms ? S_EXIT1_DR  : S_SHIFT_DR  ;
		S_EXIT1_DR   : tap_state <= tms ? S_UPDATE_DR : S_PAUSE_DR  ;
		S_PAUSE_DR   : tap_state <= tms ? S_EXIT2_DR  : S_PAUSE_DR  ;
		S_EXIT2_DR   : tap_state <= tms ? S_UPDATE_DR : S_SHIFT_DR  ;
		S_UPDATE_DR  : tap_state <= tms ? S_SELECT_DR : S_RUN_IDLE  ;

		S_SELECT_IR  : tap_state <= tms ? S_RESET     : S_CAPTURE_IR;
		S_CAPTURE_IR : tap_state <= tms ? S_EXIT1_IR  : S_SHIFT_IR  ;
		S_SHIFT_IR   : tap_state <= tms ? S_EXIT1_IR  : S_SHIFT_IR  ;
		S_EXIT1_IR   : tap_state <= tms ? S_UPDATE_IR : S_PAUSE_IR  ;
		S_PAUSE_IR   : tap_state <= tms ? S_EXIT2_IR  : S_PAUSE_IR  ;
		S_EXIT2_IR   : tap_state <= tms ? S_UPDATE_IR : S_SHIFT_IR  ;
		S_UPDATE_IR  : tap_state <= tms ? S_SELECT_DR : S_RUN_IDLE  ;
	endcase
end

// ----------------------------------------------------------------------------
// Instruction register

localparam W_IR = 5;
// All other encodings behave as BYPASS:
localparam IR_IDCODE = 5'h01;
localparam IR_DTMCS = 5'h10;
localparam IR_DMI = 5'h11;

reg [W_IR-1:0] ir_shift;
reg [W_IR-1:0] ir;

always @ (posedge tck or negedge trst_n) begin
	if (!trst_n) begin
		ir_shift <= {W_IR{1'b0}};
		ir <= IR_IDCODE;
	end else if (tap_state == S_RESET) begin
		ir_shift <= {W_IR{1'b0}};
		ir <= IR_IDCODE;
	end else if (tap_state == S_CAPTURE_IR) begin
		ir_shift <= ir;
	end else if (tap_state == S_SHIFT_IR) begin
		ir_shift <= {tdi, ir_shift} >> 1;
	end else if (tap_state == S_UPDATE_IR) begin
		ir <= ir_shift;
	end
end

// ----------------------------------------------------------------------------
// Data registers

// Shift register is sized to largest DR, which is DMI:
// {addr[7:0], data[31:0], op[1:0]}
localparam W_DR_SHIFT = 42;

reg [W_DR_SHIFT-1:0] dr_shift;
reg [1:0]            dmi_cmderr;

always @ (posedge tck or negedge trst_n) begin
	if (!trst_n) begin
		dr_shift <= {W_DR_SHIFT{1'b0}};
	end else if (tap_state == S_RESET) begin
		dr_shift <= {W_DR_SHIFT{1'b0}};
	end else if (tap_state == S_SHIFT_DR) begin
		dr_shift <= {tdi, dr_shift} >> 1;
		// Shorten DR shift chain according to IR
		if (ir == IR_DMI)
			dr_shift[41] <= tdi;
		else if (ir == IR_IDCODE || ir == IR_DTMCS)
			dr_shift[31] <= tdi;
		else // BYPASS
			dr_shift[0] <= tdi;
	end else if (tap_state == S_CAPTURE_DR) begin
		if (ir == IR_DMI)
			dr_shift <= {
				8'h0,
				dtm_prdata,
				dmi_busy && dmi_cmderr == 2'd0 ? 2'd3 : dmi_cmderr
			};
		else if (ir == IR_DTMCS)
			dr_shift <= {
				27'h0,
				DTMCS_IDLE_HINT,
				dmi_cmderr,
				6'd8,          // abits
				4'd1           // version
			};
		else if (ir == IR_IDCODE)
			dr_shift <= {10'h0, IDCODE};
		else // BYPASS
			dr_shift <= 42'h0;
	end
end

always @ (posedge tck or negedge trst_n) begin
	if (!trst_n) begin
		dmihardreset_req <= 1'b0;
	end else begin
		dmihardreset_req <= tap_state == S_UPDATE_DR && ir == IR_DTMCS && dr_shift[17];
	end
end

// ----------------------------------------------------------------------------
// DMI bus adapter

reg dmi_busy;

// DTM-domain bus, connected to a matching DM-domain bus via an APB crossing:
wire        dtm_psel;
wire        dtm_penable;
wire        dtm_pwrite;
wire [7:0]  dtm_paddr;
wire [31:0] dtm_pwdata;
wire [31:0] dtm_prdata;
wire        dtm_pready;
wire        dtm_pslverr;

// We are relying on some particular features of our APB clock crossing here
// to save some registers:
//
// - The transfer is launched immediately when psel is seen, no need to
//   actually assert an access phase (as the standard allows the CDC to
//   assume that access immediately follows setup) and no need to maintain
//   pwrite/paddr/pwdata valid after the setup phase
//
// - prdata/pslverr remain valid after the transfer completes, until the next
//   transfer completes
//
// These allow us to connect the upstream side of the CDC directly to our DR
// shifter without any sample/hold registers in between.

// psel is only pulsed for one cycle, penable is not asserted.
assign dtm_psel = tap_state == S_UPDATE_DR && ir == IR_DMI &&
	(dr_shift[1:0] == 2'd1 || dr_shift[1:0] == 2'd2) &&
	!(dmi_busy || dmi_cmderr != 2'd0) && dtm_pready;
assign dtm_penable = 1'b0;

// paddr/pwdata/pwrite are valid momentarily when psel is asserted.
assign dtm_paddr = dr_shift[34 +: 8];
assign dtm_pwrite = dr_shift[1];
assign dtm_pwdata = dr_shift[2 +: 32];

always @ (posedge tck or negedge trst_n) begin
	if (!trst_n) begin
		dmi_busy <= 1'b0;
		dmi_cmderr <= 2'd0;
	end else if (tap_state == S_CAPTURE_IR && ir == IR_DMI) begin
		// Reading while busy sets the busy sticky error. Note the capture
		// into shift register should also reflect this update on-the-fly
		if (dmi_busy && dmi_cmderr == 2'd0)
			dmi_cmderr <= 2'h3;
	end else if (tap_state == S_UPDATE_DR && ir == IR_DTMCS) begin
		// Writing dtmcs.dmireset = 1 clears a sticky error
		if (dr_shift[16])
			dmi_cmderr <= 2'd0;
	end else if (tap_state == S_UPDATE_DR && ir == IR_DMI) begin
		if (dtm_psel) begin
			dmi_busy <= 1'b1;
		end else if (dr_shift[1:0] != 2'd0) begin
			// DMI ignored operation, so set sticky busy
			if (dmi_cmderr == 2'd0)
				dmi_cmderr <= 2'd3;
		end
	end else if (dmi_busy && dtm_pready) begin
		dmi_busy <= 1'b0;
		if (dmi_cmderr == 2'd0 && dtm_pslverr)
			dmi_cmderr <= 2'd2;
	end
end

// DTM logic is in TCK domain, actual DMI + DM is in processor domain

hazard3_apb_async_bridge #(
	.W_ADDR        (8),
	.W_DATA        (32),
	.N_SYNC_STAGES (2)
) inst_hazard3_apb_async_bridge (
	.clk_src     (tck),
	.rst_n_src   (trst_n),

	.clk_dst     (clk_dmi),
	.rst_n_dst   (rst_n_dmi),

	.src_psel    (dtm_psel),
	.src_penable (dtm_penable),
	.src_pwrite  (dtm_pwrite),
	.src_paddr   (dtm_paddr),
	.src_pwdata  (dtm_pwdata),
	.src_prdata  (dtm_prdata),
	.src_pready  (dtm_pready),
	.src_pslverr (dtm_pslverr),

	.dst_psel    (dmi_psel),
	.dst_penable (dmi_penable),
	.dst_pwrite  (dmi_pwrite),
	.dst_paddr   (dmi_paddr),
	.dst_pwdata  (dmi_pwdata),
	.dst_prdata  (dmi_prdata),
	.dst_pready  (dmi_pready),
	.dst_pslverr (dmi_pslverr)
);

// ----------------------------------------------------------------------------
// TDO negedge register

always @ (negedge tck or negedge trst_n) begin
	if (!trst_n) begin
		tdo <= 1'b0;
	end else begin
		tdo <= tap_state == S_SHIFT_IR ? ir_shift[0] :
			   tap_state == S_SHIFT_DR ? dr_shift[0] : 1'b0;
	end
end

endmodule
