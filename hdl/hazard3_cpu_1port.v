/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Single-ported top level file for Hazard3 CPU. This file instantiates the
// Hazard3 core, and arbitrates its instruction fetch and load/store signals
// down to a single AHB5 master port.

`default_nettype none

module hazard3_cpu_1port #(
`include "hazard3_config.vh"
) (
	// Global signals
	input wire                clk,
	input wire                clk_always_on,
	input wire                rst_n,

	`ifdef RISCV_FORMAL
	`RVFI_OUTPUTS ,
	`endif

	// Power control signals
	output wire               pwrup_req,
	input  wire               pwrup_ack,
	output wire               clk_en,
	output wire               unblock_out,
	input  wire               unblock_in,

	// AHB5 Master port
	output reg  [W_ADDR-1:0]  haddr,
	output reg                hwrite,
	output reg  [1:0]         htrans,
	output reg  [2:0]         hsize,
	output wire [2:0]         hburst,
	output reg  [3:0]         hprot,
	output wire               hmastlock,
	output reg  [7:0]         hmaster,
	output reg                hexcl,
	input  wire               hready,
	input  wire               hresp,
	input  wire               hexokay,
	output wire [W_DATA-1:0]  hwdata,
	input  wire [W_DATA-1:0]  hrdata,

	// Debugger run/halt control
	input  wire               dbg_req_halt,
	input  wire               dbg_req_halt_on_reset,
	input  wire               dbg_req_resume,
	output wire               dbg_halted,
	output wire               dbg_running,
	// Debugger access to data0 CSR
	input  wire [W_DATA-1:0]  dbg_data0_rdata,
	output wire [W_DATA-1:0]  dbg_data0_wdata,
	output wire               dbg_data0_wen,
	// Debugger instruction injection
	input  wire [W_DATA-1:0]  dbg_instr_data,
	input  wire               dbg_instr_data_vld,
	output wire               dbg_instr_data_rdy,
	output wire               dbg_instr_caught_exception,
	output wire               dbg_instr_caught_ebreak,

	// Optional debug system bus access patch-through
	input  wire [W_ADDR-1:0]  dbg_sbus_addr,
	input  wire               dbg_sbus_write,
	input  wire [1:0]         dbg_sbus_size,
	input  wire               dbg_sbus_vld,
	output wire               dbg_sbus_rdy,
	output wire               dbg_sbus_err,
	input  wire [W_DATA-1:0]  dbg_sbus_wdata,
	output wire [W_DATA-1:0]  dbg_sbus_rdata,

	// Level-sensitive interrupt sources
	input wire [NUM_IRQS-1:0] irq,       // -> mip.meip
	input wire                soft_irq,  // -> mip.msip
	input wire                timer_irq  // -> mip.mtip
);

// ----------------------------------------------------------------------------
// Processor core

// Instruction fetch signals
wire              core_aph_req_i;
wire              core_aph_panic_i;
wire              core_aph_ready_i;
wire              core_dph_ready_i;
wire              core_dph_err_i;

wire [W_ADDR-1:0] core_haddr_i;
wire [2:0]        core_hsize_i;
wire              core_priv_i;
wire [W_DATA-1:0] core_rdata_i;


// Load/store signals
wire              core_aph_req_d;
wire              core_aph_excl_d;
wire              core_aph_ready_d;
wire              core_dph_ready_d;
wire              core_dph_err_d;
wire              core_dph_exokay_d;

wire [W_ADDR-1:0] core_haddr_d;
wire [2:0]        core_hsize_d;
wire              core_priv_d;
wire              core_hwrite_d;
wire [W_DATA-1:0] core_wdata_d;
wire [W_DATA-1:0] core_rdata_d;


hazard3_core #(
`include "hazard3_config_inst.vh"
) core (
	.clk                        (clk),
	.clk_always_on              (clk_always_on),
	.rst_n                      (rst_n),

	.pwrup_req                  (pwrup_req),
	.pwrup_ack                  (pwrup_ack),
	.clk_en                     (clk_en),
	.unblock_out                (unblock_out),
	.unblock_in                 (unblock_in),

	`ifdef RISCV_FORMAL
	`RVFI_CONN ,
	`endif

	.bus_aph_req_i              (core_aph_req_i),
	.bus_aph_panic_i            (core_aph_panic_i),
	.bus_aph_ready_i            (core_aph_ready_i),
	.bus_dph_ready_i            (core_dph_ready_i),
	.bus_dph_err_i              (core_dph_err_i),
	.bus_haddr_i                (core_haddr_i),
	.bus_hsize_i                (core_hsize_i),
	.bus_priv_i                 (core_priv_i),
	.bus_rdata_i                (core_rdata_i),

	.bus_aph_req_d              (core_aph_req_d),
	.bus_aph_excl_d             (core_aph_excl_d),
	.bus_aph_ready_d            (core_aph_ready_d),
	.bus_dph_ready_d            (core_dph_ready_d),
	.bus_dph_err_d              (core_dph_err_d),
	.bus_dph_exokay_d           (core_dph_exokay_d),
	.bus_haddr_d                (core_haddr_d),
	.bus_hsize_d                (core_hsize_d),
	.bus_priv_d                 (core_priv_d),
	.bus_hwrite_d               (core_hwrite_d),
	.bus_wdata_d                (core_wdata_d),
	.bus_rdata_d                (core_rdata_d),

	.dbg_req_halt               (dbg_req_halt),
	.dbg_req_halt_on_reset      (dbg_req_halt_on_reset),
	.dbg_req_resume             (dbg_req_resume),
	.dbg_halted                 (dbg_halted),
	.dbg_running                (dbg_running),
	.dbg_data0_rdata            (dbg_data0_rdata),
	.dbg_data0_wdata            (dbg_data0_wdata),
	.dbg_data0_wen              (dbg_data0_wen),
	.dbg_instr_data             (dbg_instr_data),
	.dbg_instr_data_vld         (dbg_instr_data_vld),
	.dbg_instr_data_rdy         (dbg_instr_data_rdy),
	.dbg_instr_caught_exception (dbg_instr_caught_exception),
	.dbg_instr_caught_ebreak    (dbg_instr_caught_ebreak),



	.irq                        (irq),
	.soft_irq                   (soft_irq),
	.timer_irq                  (timer_irq)
);

// ----------------------------------------------------------------------------
// Arbitration state machine

wire      bus_gnt_i;
wire      bus_gnt_d;
wire      bus_gnt_s;

reg       bus_hold_aph;
reg [2:0] bus_gnt_ids_prev;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		bus_hold_aph <= 1'b0;
		bus_gnt_ids_prev <= 3'h0;
	end else begin
		bus_hold_aph <= htrans[1] && !hready && !hresp;
		bus_gnt_ids_prev <= {bus_gnt_i, bus_gnt_d, bus_gnt_s};
	end
end

// Debug SBA access is lower priority than load/store, but higher than
// instruction fetch. This isn't ideal, but in a tight loop the core may be
// performing an instruction fetch or load/store on every single cycle, and
// this is a simple way to guarantee eventual success of debugger accesses. A
// more complex way would be to add a "panic timer" to boost a stalled sbus
// access over an instruction fetch.

// Note that, often, the sbus will be disconnected: it doesn't provide any
// increase in debugger bus throughput compared with the program buffer and
// autoexec. It's useful for "minimally intrusive" debug bus access(i.e. less
// intrusive than halting the core and resuming it) e.g. for Segger RTT.

reg bus_active_dph_s;

assign {bus_gnt_i, bus_gnt_d, bus_gnt_s} =
	bus_hold_aph                      ? bus_gnt_ids_prev :
	core_aph_panic_i                  ? 3'b100 :
	core_aph_req_d                    ? 3'b010 :
	dbg_sbus_vld && !bus_active_dph_s ? 3'b001 :
	core_aph_req_i                    ? 3'b100 :
	                                    3'b000 ;
reg bus_active_dph_i;
reg bus_active_dph_d;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		bus_active_dph_i <= 1'b0;
		bus_active_dph_d <= 1'b0;
		bus_active_dph_s <= 1'b0;
	end else if (hready) begin
		bus_active_dph_i <= bus_gnt_i;
		bus_active_dph_d <= bus_gnt_d;
		bus_active_dph_s <= bus_gnt_s;
	end
end

// ----------------------------------------------------------------------------
// Address phase request muxing

localparam HTRANS_IDLE = 2'b00;
localparam HTRANS_NSEQ = 2'b10;

wire [3:0] hprot_data  = {
	2'b00,                  // Noncacheable/nonbufferable
	core_priv_d,            // Privileged or Normal as per core state
	1'b1                    // Data access
};

wire [3:0] hprot_instr = {
	2'b00,                  // Noncacheable/nonbufferable
	core_priv_i,            // Privileged or Normal as per core state
	1'b0                    // Instruction access
};

wire [3:0] hprot_sbus = {
	2'b00,         // Noncacheable/nonbufferable
	1'b1,          // Always privileged
	1'b1           // Data access
};

assign hburst = 3'b000;   // HBURST_SINGLE
assign hmastlock = 1'b0;

always @ (*) begin
	if (bus_gnt_s) begin
		htrans  = HTRANS_NSEQ;
		hexcl   = 1'b0;
		haddr   = dbg_sbus_addr;
		hsize   = {1'b0, dbg_sbus_size};
		hwrite  = dbg_sbus_write;
		hprot   = hprot_sbus;
		hmaster = 8'h01;
	end else if (bus_gnt_d) begin
		htrans  = HTRANS_NSEQ;
		hexcl   = core_aph_excl_d;
		haddr   = core_haddr_d;
		hsize   = core_hsize_d;
		hwrite  = core_hwrite_d;
		hprot   = hprot_data;
		hmaster = 8'h00;
	end else if (bus_gnt_i) begin
		htrans  = HTRANS_NSEQ;
		hexcl   = 1'b0;
		haddr   = core_haddr_i;
		hsize   = core_hsize_i;
		hwrite  = 1'b0;
		hprot   = hprot_instr;
		hmaster = 8'h00;
	end else begin
		htrans  = HTRANS_IDLE;
		hexcl   = 1'b0;
		haddr   = {W_ADDR{1'b0}};
		hsize   = 3'h0;
		hwrite  = 1'b0;
		hprot   = 4'h0;
		hmaster = 8'h00;
	end
end

assign hwdata = bus_active_dph_s ? dbg_sbus_wdata : core_wdata_d;

// ----------------------------------------------------------------------------
// Response routing

// Data buses directly connected
assign core_rdata_d   = hrdata;
assign core_rdata_i   = hrdata;
assign dbg_sbus_rdata = hrdata;

// Handhshake based on grant and bus stall
assign core_aph_ready_i = hready && bus_gnt_i;
assign core_dph_ready_i = bus_active_dph_i && hready;
assign core_dph_err_i   = bus_active_dph_i && hresp;

// D-side errors are reported even when not ready, so that the core can make
// use of the two-phase error response to cleanly squash a second load/store
// chasing the faulting one down the pipeline.
assign core_aph_ready_d  = hready && bus_gnt_d;
assign core_dph_ready_d  = bus_active_dph_d && hready;
assign core_dph_err_d    = bus_active_dph_d && hresp;
assign core_dph_exokay_d = bus_active_dph_d && hexokay;

assign dbg_sbus_err = bus_active_dph_s && hresp;
assign dbg_sbus_rdy = bus_active_dph_s && hready;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
