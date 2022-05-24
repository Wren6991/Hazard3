/*****************************************************************************\
|                        Copyright (C) 2021 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Single-ported top level file for Hazard3 CPU. This file instantiates the
// Hazard3 core, and arbitrates its instruction fetch and load/store signals
// down to a single AHB-Lite master port.

`default_nettype none

module hazard3_cpu_1port #(
`include "hazard3_config.vh"
) (
	// Global signals
	input wire               clk,
	input wire               rst_n,

	`ifdef RISCV_FORMAL
	`RVFI_OUTPUTS ,
	`endif

	// AHB-lite Master port
	output reg  [W_ADDR-1:0] ahblm_haddr,
	output reg               ahblm_hwrite,
	output reg  [1:0]        ahblm_htrans,
	output reg  [2:0]        ahblm_hsize,
	output wire [2:0]        ahblm_hburst,
	output reg  [3:0]        ahblm_hprot,
	output wire              ahblm_hmastlock,
	output reg               ahblm_hexcl,
	input  wire              ahblm_hready,
	input  wire              ahblm_hresp,
	input  wire              ahblm_hexokay,
	output wire [W_DATA-1:0] ahblm_hwdata,
	input  wire [W_DATA-1:0] ahblm_hrdata,

	// Debugger run/halt control
	input  wire              dbg_req_halt,
	input  wire              dbg_req_halt_on_reset,
	input  wire              dbg_req_resume,
	output wire              dbg_halted,
	output wire              dbg_running,
	// Debugger access to data0 CSR
	input  wire [W_DATA-1:0] dbg_data0_rdata,
	output wire [W_DATA-1:0] dbg_data0_wdata,
	output wire              dbg_data0_wen,
	// Debugger instruction injection
	input  wire [W_DATA-1:0] dbg_instr_data,
	input  wire              dbg_instr_data_vld,
	output wire              dbg_instr_data_rdy,
	output wire              dbg_instr_caught_exception,
	output wire              dbg_instr_caught_ebreak,

	// Level-sensitive interrupt sources
	input wire [NUM_IRQ-1:0] irq,       // -> mip.meip
	input wire               soft_irq,  // -> mip.msip
	input wire               timer_irq  // -> mip.mtip
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
	.rst_n                      (rst_n),

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

reg       bus_hold_aph;
reg [1:0] bus_gnt_id_prev;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		bus_hold_aph <= 1'b0;
		bus_gnt_id_prev <= 2'h0;
	end else begin
		bus_hold_aph <= ahblm_htrans[1] && !ahblm_hready && !ahblm_hresp;
		bus_gnt_id_prev <= {bus_gnt_i, bus_gnt_d};
	end
end

assign {bus_gnt_i, bus_gnt_d} =
	bus_hold_aph     ? bus_gnt_id_prev :
	core_aph_panic_i ? 2'b10 :
	core_aph_req_d   ? 2'b01 :
	core_aph_req_i   ? 2'b10 :
	                   2'b00 ;

// Keep track of whether instr/data access is active in AHB dataphase.
reg bus_active_dph_i;
reg bus_active_dph_d;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		bus_active_dph_i <= 1'b0;
		bus_active_dph_d <= 1'b0;
	end else if (ahblm_hready) begin
		bus_active_dph_i <= bus_gnt_i;
		bus_active_dph_d <= bus_gnt_d;
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

assign ahblm_hburst = 3'b000;   // HBURST_SINGLE
assign ahblm_hmastlock = 1'b0;

always @ (*) begin
	if (bus_gnt_d) begin
		ahblm_htrans = HTRANS_NSEQ;
		ahblm_hexcl  = core_aph_excl_d;
		ahblm_haddr  = core_haddr_d;
		ahblm_hsize  = core_hsize_d;
		ahblm_hwrite = core_hwrite_d;
		ahblm_hprot  = hprot_data;
	end else if (bus_gnt_i) begin
		ahblm_htrans = HTRANS_NSEQ;
		ahblm_hexcl  = 1'b0;
		ahblm_haddr  = core_haddr_i;
		ahblm_hsize  = core_hsize_i;
		ahblm_hwrite = 1'b0;
		ahblm_hprot  = hprot_instr;
	end else begin
		ahblm_htrans = HTRANS_IDLE;
		ahblm_hexcl  = 1'b0;
		ahblm_haddr  = {W_ADDR{1'b0}};
		ahblm_hsize  = 3'h0;
		ahblm_hwrite = 1'b0;
		ahblm_hprot  = 4'h0;
	end
end

// ----------------------------------------------------------------------------
// Response routing

// Data buses directly connected
assign core_rdata_d = ahblm_hrdata;
assign core_rdata_i = ahblm_hrdata;
assign ahblm_hwdata = core_wdata_d;

// Handhshake based on grant and bus stall
assign core_aph_ready_i = ahblm_hready && bus_gnt_i;
assign core_dph_ready_i = ahblm_hready && bus_active_dph_i;
assign core_dph_err_i   = bus_active_dph_i && ahblm_hresp;

// D-side errors are reported even when not ready, so that the core can make
// use of the two-phase error response to cleanly squash a second load/store
// chasing the faulting one down the pipeline.
assign core_aph_ready_d = ahblm_hready && bus_gnt_d;
assign core_dph_ready_d = ahblm_hready && bus_active_dph_d;
assign core_dph_err_d = bus_active_dph_d && ahblm_hresp;
assign core_dph_exokay_d = bus_active_dph_d && ahblm_hexokay;

endmodule

`default_nettype wire
