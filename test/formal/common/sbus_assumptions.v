/*****************************************************************************\
|                        Copyright (C) 2022 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Properties for driving the debug module system bus access patch-through
// core interface in the bus property checks

`default_nettype none

module sbus_assumptions #(
	parameter W_ADDR = 32,
	parameter W_DATA = 32
) (
	input wire              clk,
	input wire              rst_n,

	input wire [W_ADDR-1:0] dbg_sbus_addr,
	input wire              dbg_sbus_write,
	input wire [1:0]        dbg_sbus_size,
	input wire              dbg_sbus_vld,
	input wire              dbg_sbus_rdy,
	input wire              dbg_sbus_err,
	input wire [W_DATA-1:0] dbg_sbus_wdata,
	input wire [W_DATA-1:0] dbg_sbus_rdata
);

// Naturally aligned, no larger than bus
always assume(~|(dbg_sbus_addr & ~({32{1'b1}} << dbg_sbus_size)));
always assume(dbg_sbus_size < 2'h3);

// No transfers whilst core is in reset
always assume(!(!rst_n && dbg_sbus_vld));

// No change or retraction of active transfer
always @ (posedge clk) if (rst_n) begin
	if ($past(dbg_sbus_vld && !dbg_sbus_rdy)) begin
		assume($stable({
			dbg_sbus_vld,
			dbg_sbus_addr,
			dbg_sbus_size,
			dbg_sbus_write,
			dbg_sbus_wdata
		}));
	end
end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
