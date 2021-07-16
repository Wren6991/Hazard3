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

// FPGA toplevel for ../soc/example_soc.v on an iCEBreaker dev board

`default_nettype none

module fpga_icebreaker (
	input wire        clk_osc,

	// No external trst_n as iCEBreaker can't easily drive it from FTDI, so we
	// generate a pulse internally from FPGA PoR.
    input  wire       tck,
    input  wire       tms,
    input  wire       tdi,
    output wire       tdo,

    output wire       mirror_tck,
    output wire       mirror_tms,
    output wire       mirror_tdi,
    output wire       mirror_tdo,

	output wire       uart_tx,
	input  wire       uart_rx
);

assign mirror_tck = tck;
assign mirror_tms = tms;
assign mirror_tdi = tdi;
assign mirror_tdo = tdo;

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

reset_sync trst_sync_u (
	.clk       (tck),
	.rst_n_in  (rst_n_sys),
	.rst_n_out (trst_n)
);

example_soc soc_u (
	.clk     (clk_sys),
	.rst_n   (rst_n_sys),

	.tck     (tck),
	.trst_n  (rst_n_sys), //fixme!
	.tms     (tms),
	.tdi     (tdi),
	.tdo     (tdo),

	.uart_tx (uart_tx),
	.uart_rx (uart_rx)
);

endmodule
