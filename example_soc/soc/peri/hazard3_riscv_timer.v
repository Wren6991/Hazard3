/*****************************************************************************\
|                        Copyright (C) 2022 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

// Basic implementation of standard 64-bit RISC-V timer with 32-bit APB.

// TICK_IS_NRZ = 1: tick is an NRZ signal that is asynchronous to clk.
// TICK_IS_NRZ = 0: tick is a level-sensitive signal that is synchronous to clk.

module hazard3_riscv_timer #(
	parameter TICK_IS_NRZ = 0
) (
	input  wire               clk,
	input  wire               rst_n,

	input  wire [15:0]        paddr,
	input  wire               psel,
	input  wire               penable,
	input  wire               pwrite,
	input  wire [31:0]        pwdata,
	output reg  [31:0]        prdata,
	output wire               pready,
	output wire               pslverr,

	input  wire               dbg_halt,
	input  wire               tick,

	output reg                timer_irq
);

localparam ADDR_CTRL      = 16'h0000;
localparam ADDR_MTIME     = 16'h0008;
localparam ADDR_MTIMEH    = 16'h000c;
localparam ADDR_MTIMECMP  = 16'h0010;
localparam ADDR_MTIMECMPH = 16'h0014;

// ----------------------------------------------------------------------------
// Timer tick logic

wire tick_event;

generate
if (TICK_IS_NRZ) begin: edge_detect

	wire tick_nrz_sync;

	hazard3_sync_1bit tick_sync_u (
		.clk    (clk),
		.rst_n  (rst_n),
		.i      (tick_nrz),
		.o      (tick_nrz_sync)
	);

	reg tick_nrz_prev;
	always @ (posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			tick_nrz_prev <= 1'b0;
		end else begin
			tick_nrz_prev <= tick_nrz_sync;
		end
	end

	assign tick_event = tick_nrz_sync ^ tick_nrz_sync_prev;

end else begin: no_edge_detect

	assign tick_event = tick;

end
endgenerate

reg ctrl_en;
wire tick_now = tick_event && ctrl_en && !dbg_halt;

// ----------------------------------------------------------------------------
// Counter registers

wire bus_write = pwrite && psel && penable;
wire bus_read = !pwrite && psel && penable;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		ctrl_en <= 1'b1;
	end else if (bus_write && paddr == ADDR_CTRL) begin
		ctrl_en <= pwdata[0];
	end
end

reg [63:0] mtime;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mtime <= 64'h0;
	end else begin
		if (tick_now)
			mtime <= mtime + 1'b1;
		if (bus_write && paddr == ADDR_MTIME)
			mtime[31:0] <= pwdata;
		if (bus_write && paddr == ADDR_MTIMEH)
			mtime[63:32] <= pwdata;
	end
end

// mtimecmp is stored inverted for minor LUT savings on iCE40
reg  [63:0] mtimecmp;
wire [64:0] cmp_diff = {1'b0, mtime} + {1'b0, mtimecmp} + 65'd1;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mtimecmp <= 64'h0;
		timer_irq <= 1'b0;
	end else begin
		if (bus_write && paddr == ADDR_MTIMECMP)
			mtimecmp[31:0] <= ~pwdata;
		if (bus_write && paddr == ADDR_MTIMECMPH)
			mtimecmp[63:32] <= ~pwdata;
		timer_irq <= cmp_diff[64];
	end
end

always @ (*) begin
	case (paddr)
	ADDR_CTRL:      prdata = {31'h0, ctrl_en};
	ADDR_MTIME:     prdata = mtime[31:0];
	ADDR_MTIMEH:    prdata = mtime[63:32];
	ADDR_MTIMECMP:  prdata = ~mtimecmp[31:0];
	ADDR_MTIMECMPH: prdata = ~mtimecmp[63:32];
	default:        prdata = 32'h0;
	endcase
end

assign pready = 1'b1;
assign pslverr = 1'b0;

endmodule

`ifndef YOSYS
`default_nettype none
`endif
