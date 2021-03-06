/*****************************************************************************\
|                        Copyright (C) 2021 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module fpga_ulx3s (
	input  wire       clk_osc,
	output wire [7:0] dbg,

	output wire       uart_tx,
	input  wire       uart_rx
);

wire clk_sys;
wire pll_sys_locked;
wire rst_n_sys;

pll_25_40 pll_sys (
	.clkin   (clk_osc),
	.clkout0 (clk_sys),
	.locked  (pll_sys_locked)
);

fpga_reset #(
	.SHIFT (3)
) rstgen (
	.clk         (clk_sys),
	.force_rst_n (pll_sys_locked),
	.rst_n       (rst_n_sys)
);

example_soc #(
	.DTM_TYPE      ("ECP5"),
	.SRAM_DEPTH    (1 << 15),

	.EXTENSION_M   (1),
	.EXTENSION_A   (1),
	.EXTENSION_C   (0),
	.EXTENSION_ZBA (0),
	.EXTENSION_ZBB (0),
	.EXTENSION_ZBC (0),
	.EXTENSION_ZBS (0),
	.CSR_COUNTER   (0),
	.MUL_FAST      (1),
	.MULDIV_UNROLL (1)
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

endmodule
