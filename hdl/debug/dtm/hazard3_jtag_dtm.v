/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Implementation of standard RISC-V JTAG-DTM with an APB Debug Module
// Interface. The TAP itself is clocked directly by JTAG TCK; a clock
// crossing is instantiated internally between the TCK domain and the DMI bus
// clock domain.

`default_nettype none

module hazard3_jtag_dtm #(
	parameter IDCODE          = 32'h0000_0001,
	parameter DTMCS_IDLE_HINT = 3'd4,
	parameter W_PADDR         = 9,
	parameter ABITS           = W_PADDR - 2 // do not modify
) (
	// Standard JTAG signals -- the JTAG hardware is clocked directly by TCK.
	input  wire               tck,
	input  wire               trst_n,
	input  wire               tms,
	input  wire               tdi,
	output reg                tdo,

	// This is synchronous to TCK and asserted for one TCK cycle only
	output wire               dmihardreset_req,

	// Bus clock + reset for Debug Module Interface
	input  wire               clk_dmi,
	input  wire               rst_n_dmi,

	// Debug Module Interface (APB)
	output wire               dmi_psel,
	output wire               dmi_penable,
	output wire               dmi_pwrite,
	output wire [W_PADDR-1:0] dmi_paddr,
	output wire [31:0]        dmi_pwdata,
	input  wire [31:0]        dmi_prdata,
	input  wire               dmi_pready,
	input  wire               dmi_pslverr
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
localparam W_DR_SHIFT = ABITS + 32 + 2;

reg [W_DR_SHIFT-1:0] dr_shift;

// Signals to/from the DTM core, which implements the DTMCS and DMI registers
wire                  core_dr_wen;
wire                  core_dr_ren;
wire                  core_dr_sel_dmi_ndtmcs;
wire [W_DR_SHIFT-1:0] core_dr_wdata;
wire [W_DR_SHIFT-1:0] core_dr_rdata;

always @ (posedge tck or negedge trst_n) begin
	if (!trst_n) begin
		dr_shift <= {W_DR_SHIFT{1'b0}};
	end else if (tap_state == S_RESET) begin
		dr_shift <= {W_DR_SHIFT{1'b0}};
	end else if (tap_state == S_SHIFT_DR) begin
		dr_shift <= {tdi, dr_shift} >> 1;
		// Shorten DR shift chain according to IR
		if (ir == IR_DMI)
			dr_shift[W_DR_SHIFT - 1] <= tdi;
		else if (ir == IR_IDCODE || ir == IR_DTMCS)
			dr_shift[31] <= tdi;
		else // BYPASS
			dr_shift[0] <= tdi;
	end else if (tap_state == S_CAPTURE_DR) begin
		if (ir == IR_DMI || ir == IR_DTMCS)
			dr_shift <= core_dr_rdata;
		else if (ir == IR_IDCODE)
			dr_shift <= {10'h0, IDCODE};
		else // BYPASS
			dr_shift <= 42'h0;
	end
end

// Must retime shift data onto negedge before presenting on TDO

always @ (negedge tck or negedge trst_n) begin
	if (!trst_n) begin
		tdo <= 1'b0;
	end else begin
		tdo <= tap_state == S_SHIFT_IR ? ir_shift[0] :
			   tap_state == S_SHIFT_DR ? dr_shift[0] : 1'b0;
	end
end

// ----------------------------------------------------------------------------
// Core logic and bus interface

assign core_dr_sel_dmi_ndtmcs = ir == IR_DMI;
assign core_dr_wen = (ir == IR_DMI || ir == IR_DTMCS) && tap_state == S_UPDATE_DR;
assign core_dr_ren = (ir == IR_DMI || ir == IR_DTMCS) && tap_state == S_CAPTURE_DR;

assign core_dr_wdata = dr_shift;

hazard3_jtag_dtm_core #(
	.DTMCS_IDLE_HINT (DTMCS_IDLE_HINT),
	.W_ADDR          (ABITS)
) dtm_core (
	.tck               (tck),
	.trst_n            (trst_n),
	.clk_dmi           (clk_dmi),
	.rst_n_dmi         (rst_n_dmi),

	.dmihardreset_req  (dmihardreset_req),

	.dr_wen            (core_dr_wen),
	.dr_ren            (core_dr_ren),
	.dr_sel_dmi_ndtmcs (core_dr_sel_dmi_ndtmcs),
	.dr_wdata          (core_dr_wdata),
	.dr_rdata          (core_dr_rdata),

	.dmi_psel          (dmi_psel),
	.dmi_penable       (dmi_penable),
	.dmi_pwrite        (dmi_pwrite),
	.dmi_paddr         (dmi_paddr[W_PADDR-1:2]),
	.dmi_pwdata        (dmi_pwdata),
	.dmi_prdata        (dmi_prdata),
	.dmi_pready        (dmi_pready),
	.dmi_pslverr       (dmi_pslverr)
);

assign dmi_paddr[1:0] = 2'b00;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
