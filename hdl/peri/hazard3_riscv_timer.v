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

// Implementation of standard RISC-V timer (mtime/mtimeh mtimecmp/mtimecmph)
// accessed over 32-bit data bus. Ticks on both edges of tick_nrz, which is
// provided by some external timebase, and is assumed to be asynchronous to
// clk. Nothing fancy, just a simple implementation of the spec.

module hazard3_riscv_timer (
	input  wire               clk,
	input  wire               rst_n,

	input  wire               psel,
	input  wire               penable,
	input  wire               pwrite,
	input  wire [7:0]         paddr,
	input  wire [31:0]        pwdata,
	output reg  [31:0]        prdata,
	output wire               pready,
	output wire               pslverr,

	input  wire               dbg_halt,
	input  wire               tick_nrz,

	output reg                timer_irq
);

wire bus_write = pwrite && psel && penable;
wire bus_read = !pwrite && psel && penable;

localparam W_ADDR = 8;
localparam W_DATA = 32;

localparam ADDR_CTRL      = 8'h00;
localparam ADDR_MTIME     = 8'h08;
localparam ADDR_MTIMEH    = 8'h0c;
localparam ADDR_MTIMECMP  = 8'h10;
localparam ADDR_MTIMECMPH = 8'h14;

wire tick_nrz_sync;

hazard3_sync_1bit tick_sync_u (
	.clk    (clk),
	.rst_n  (rst_n),
	.i      (tick_nrz),
	.o      (tick_nrz_sync)
);

reg tick_nrz_prev;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		tick_nrz_prev <= 1'b0;
	else
		tick_nrz_prev <= tick_nrz_sync;

reg ctrl_en;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		ctrl_en <= 1'b1;
	else if (bus_write && paddr == ADDR_CTRL)
		ctrl_en <= pwdata[0];

wire tick = ctrl_en && !dbg_halt && tick_nrz_prev != tick_nrz_sync;

reg [63:0] mtime;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mtime <= 64'h0;
	end else begin
		if (tick)
			mtime <= mtime + 1'b1;
		if (bus_write && paddr == ADDR_MTIME)
			mtime[31:0] <= pwdata;
		if (bus_write && paddr == ADDR_MTIMEH)
			mtime[63:32] <= pwdata;
	end
end

reg [63:0] mtimecmp;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mtimecmp <= 64'h0;
		timer_irq <= 1'b0;
	end else begin
		if (bus_write && paddr == ADDR_MTIMECMP)
			mtimecmp[31:0] <= pwdata;
		if (bus_write && paddr == ADDR_MTIMECMPH)
			mtimecmp[63:32] <= pwdata;
		timer_irq <= mtime >= mtimecmp; // oof
	end
end

always @ (*) begin
	case (paddr)
	ADDR_CTRL:      prdata = {{W_DATA-1{1'b0}}, ctrl_en};
	ADDR_MTIME:     prdata = mtime[31:0];
	ADDR_MTIMEH:    prdata = mtime[63:32];
	ADDR_MTIMECMP:  prdata = mtimecmp[31:0];
	ADDR_MTIMECMPH: prdata = mtimecmp[63:32];
	default:        prdata = {W_DATA{1'b0}};
	endcase
end

endmodule
