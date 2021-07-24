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

pll_25_50 pll_sys (
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

	.EXTENSION_C   (0),
	.EXTENSION_M   (1),
	.CSR_COUNTER   (1),
	.MUL_FAST      (1),
	.MULDIV_UNROLL (2)
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
