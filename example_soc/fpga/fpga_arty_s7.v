/*****************************************************************************\
|                        Copyright (C) 2021 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module fpga (
	input wire        clk_osc,

	output wire [3:0] led,

	output wire       uart_tx,
	input  wire       uart_rx
);

wire clk_sys;
wire locked;
wire clkfbout;
wire clkfbout_buf;
BUFG bufg_clkfbout (
	.I (clkfbout),
	.O (clkfbout_buf)
);

// Configured for 12 -> 80 MHz
MMCME2_ADV #(
	.BANDWIDTH            ("OPTIMIZED"),
	.CLKOUT4_CASCADE      ("FALSE"),
	.COMPENSATION         ("ZHOLD"),
	.STARTUP_WAIT         ("FALSE"),
	.DIVCLK_DIVIDE        (1),
	.CLKFBOUT_MULT_F      (60.000),
	.CLKFBOUT_PHASE       (0.000),
	.CLKFBOUT_USE_FINE_PS ("FALSE"),
	.CLKOUT0_DIVIDE_F     (9.000),
	.CLKOUT0_PHASE        (0.000),
	.CLKOUT0_DUTY_CYCLE   (0.500),
	.CLKOUT0_USE_FINE_PS  ("FALSE"),
	.CLKIN1_PERIOD        (83.333)
) mmcm_adv_inst (
	.CLKFBOUT            (clkfbout),
	.CLKFBOUTB           (/* unused */),
	.CLKOUT0             (clk_sys),
	.CLKOUT0B            (/* unused */),
	.CLKOUT1             (/* unused */),
	.CLKOUT1B            (/* unused */),
	.CLKOUT2             (/* unused */),
	.CLKOUT2B            (/* unused */),
	.CLKOUT3             (/* unused */),
	.CLKOUT3B            (/* unused */),
	.CLKOUT4             (/* unused */),
	.CLKOUT5             (/* unused */),
	.CLKOUT6             (/* unused */),
	// Input clock control
	.CLKFBIN             (clkfbout_buf),
	.CLKIN1              (clk_osc),
	.CLKIN2              (1'b0),
	// Tied to always select the primary input clock
	.CLKINSEL            (1'b1),
	// Ports for dynamic reconfiguration
	.DADDR               (7'h0),
	.DCLK                (1'b0),
	.DEN                 (1'b0),
	.DI                  (16'h0),
	.DO                  (/* unused */),
	.DRDY                (/* unused */),
	.DWE                 (1'b0),
	// Ports for dynamic phase shift
	.PSCLK               (1'b0),
	.PSEN                (1'b0),
	.PSINCDEC            (1'b0),
	.PSDONE              (/* unused */),
	// Other control and status signals
	.LOCKED              (locked),
	.CLKINSTOPPED        (/* unused */),
	.CLKFBSTOPPED        (/* unused */),
	.PWRDWN              (1'b0),
	.RST                 (1'b0) // TODO???
);

blinky #(
	.CLK_HZ (12_000_000),
	.BLINK_HZ (1)
) blinky_clk_osc (
	.clk (clk_osc),
	.blink (led[0])
);

blinky #(
	.CLK_HZ (80_000_000),
	.BLINK_HZ (2)
) blinky_clk_sys (
	.clk (clk_sys),
	.blink (led[1])
);

wire rst_n_sys;

fpga_reset #(
	.SHIFT (3)
) rstgen (
	.clk         (clk_sys),
	.force_rst_n (1'b1),
	.rst_n       (rst_n_sys)
);

example_soc #(
	.DTM_TYPE            ("XILINX7"),

	.SRAM_DEPTH          (1 << 15),

	.CLK_MHZ             (60),

	.EXTENSION_A         (1),
	.EXTENSION_C         (0),
	.EXTENSION_M         (1),
	.EXTENSION_ZBA       (0),
	.EXTENSION_ZBB       (0),
	.EXTENSION_ZBC       (0),
	.EXTENSION_ZBS       (0),
	.EXTENSION_ZBKB      (0),
	.EXTENSION_ZCMP      (0),
	.EXTENSION_ZCLSD     (0),
	.EXTENSION_ZCB       (0),
	.EXTENSION_ZILSD     (0),
	.EXTENSION_ZIFENCEI  (0),
	.EXTENSION_XH3BEXTM  (0),
	.EXTENSION_XH3PMPM   (0),
	.EXTENSION_XH3POWER  (0),

	.CSR_COUNTER         (0),
	.U_MODE              (0),
	.PMP_REGIONS         (0),
	.BREAKPOINT_TRIGGERS (0),
	.IRQ_PRIORITY_BITS   (0),
	.REDUCED_BYPASS      (0),
	.MULDIV_UNROLL       (1),
	.MUL_FAST            (0),
	.MUL_FASTER          (0),
	.MULH_FAST           (0),
	.FAST_BRANCHCMP      (1),
	.BRANCH_PREDICTOR    (0)
) soc_u (
	.clk            (clk_sys),
	.rst_n          (rst_n_sys),

	.tck            (1'b0),
	.trst_n         (1'b0),
	.tms            (1'b0),
	.tdi            (1'b0),
	.tdo            (/* unused */),

	.uart_tx        (uart_tx),
	.uart_rx        (uart_rx)
);

endmodule
