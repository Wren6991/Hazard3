/*****************************************************************************\
|                        Copyright (C) 2021 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module fpga_orangecrab_25f (
	input  wire       clk_osc,
	output wire [7:0] dbg,

	output wire       uart_tx,
	input  wire       uart_rx,

	output rgb_led0_r,
	output rgb_led0_g,
	output rgb_led0_b,

	output rst_n,
	input usr_btn
);

wire clk_sys = clk_osc;
wire rst_n_sys;
wire trst_n;

fpga_reset #(
	.SHIFT (3)
) rstgen (
	.clk         (clk_sys),
	.force_rst_n (1'b1),
	.rst_n       (rst_n_sys)
);

example_soc #(
	.DTM_TYPE           ("ECP5"),
	.SRAM_DEPTH         (1 << 14),
	.CLK_MHZ            (48),

	.EXTENSION_M         (1),
	.EXTENSION_A         (1),
	.EXTENSION_C         (0),
	.EXTENSION_ZBA       (0),
	.EXTENSION_ZBB       (0),
	.EXTENSION_ZBC       (0),
	.EXTENSION_ZBS       (0),
	.EXTENSION_ZBKB      (0),
	.EXTENSION_ZIFENCEI  (1),
	.EXTENSION_XH3BEXTM  (0),
	.EXTENSION_XH3PMPM   (0),
	.EXTENSION_XH3POWER  (0),
	.CSR_COUNTER         (1),
	.MUL_FAST            (1),
	.MUL_FASTER          (0),
	.MULH_FAST           (0),
	.MULDIV_UNROLL       (1),
	.FAST_BRANCHCMP      (1),
	.BRANCH_PREDICTOR    (1)
) soc_u (
	.clk     (clk_sys),
	.rst_n   (rst_n_sys),

	// JTAG connections provided internally by ECP5 JTAGG primitive
	.tck     (1'b0),
	.trst_n  (1'b0),
	.tms     (1'b0),
	.tdi     (1'b0),
	.tdo     (/* unused */),

	.uart_tx (uart_tx),
	.uart_rx (uart_rx)
);

	// Create a 27 bit register
	reg [26:0] counter = 0;

	// Every positive edge increment register by 1
	always @(posedge clk_sys) begin
		counter <= counter + 1;
	end

	// Output inverted values of counter onto LEDs
	assign rgb_led0_r = ~counter[24];
	assign rgb_led0_g = ~counter[25];
	assign rgb_led0_b = 0;

	assign dbg = 8'hff;

	// Reset logic on button press.
	// this will enter the bootloader
	reg reset_sr = 1'b1;
	always @(posedge clk_sys) begin
		reset_sr <= {usr_btn};
	end
	assign rst_n = reset_sr;


endmodule
