/*****************************************************************************\
|                        Copyright (C) 2022 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Standalone bus shim for connecting the DM's System Bus Access to AHB

`default_nettype none

module hazard3_sbus_to_ahb #(
	parameter W_ADDR = 32,
	parameter W_DATA = 32
) (
	input wire               clk,
	input wire               rst_n,

	input  wire [W_ADDR-1:0] sbus_addr,
	input  wire              sbus_write,
	input  wire [1:0]        sbus_size,
	input  wire              sbus_vld,
	output wire              sbus_rdy,
	output wire              sbus_err,
	input  wire [W_DATA-1:0] sbus_wdata,
	output wire [W_DATA-1:0] sbus_rdata,

	output wire [W_ADDR-1:0] ahblm_haddr,
	output wire              ahblm_hwrite,
	output wire [1:0]        ahblm_htrans,
	output wire [2:0]        ahblm_hsize,
	output wire [2:0]        ahblm_hburst,
	output wire [3:0]        ahblm_hprot,
	output wire              ahblm_hmastlock,
	input  wire              ahblm_hready,
	input  wire              ahblm_hresp,
	output wire [W_DATA-1:0] ahblm_hwdata,
	input  wire [W_DATA-1:0] ahblm_hrdata
);

// Most signals are simple tie-throughs

assign ahblm_haddr     = sbus_addr;
assign ahblm_hwrite    = sbus_write;
assign ahblm_hsize     = {1'b0, sbus_size};
assign ahblm_hwdata    = sbus_wdata;

// HPROT = noncacheable nonbufferable privileged data access:
assign ahblm_hprot     = 4'b0011;
assign ahblm_hmastlock = 1'b0;
assign ahblm_hburst    = 3'h0;

assign sbus_err        = ahblm_hresp;
assign sbus_rdata      = ahblm_hrdata;

// Handshaking

reg dph_active;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		dph_active <= 1'b0;
	end else if (ahblm_hready) begin
		dph_active <= ahblm_htrans[1];
	end
end

assign ahblm_htrans = sbus_vld && !dph_active ? 2'b10 : 2'b00;

assign sbus_rdy = ahblm_hready && dph_active;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
