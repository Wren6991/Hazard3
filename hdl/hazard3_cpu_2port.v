/*****************************************************************************\
|                        Copyright (C) 2021 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Dual-ported top level file for Hazard3 CPU. This file instantiates the
// Hazard3 core, and interfaces its instruction fetch and load/store signals
// to a pair of AHB-Lite master ports.

`default_nettype none

module hazard3_cpu_2port #(
`include "hazard3_config.vh"
) (
	// Global signals
	input wire               clk,
	input wire               rst_n,

	`ifdef RISCV_FORMAL
	`RVFI_OUTPUTS ,
	`endif

	// Instruction fetch port
	output wire [W_ADDR-1:0] i_haddr,
	output wire              i_hwrite,
	output wire [1:0]        i_htrans,
	output wire [2:0]        i_hsize,
	output wire [2:0]        i_hburst,
	output wire [3:0]        i_hprot,
	output wire              i_hmastlock,
	input  wire              i_hready,
	input  wire              i_hresp,
	output wire [W_DATA-1:0] i_hwdata,
	input  wire [W_DATA-1:0] i_hrdata,

	// Load/store port
	output wire [W_ADDR-1:0] d_haddr,
	output wire              d_hwrite,
	output wire [1:0]        d_htrans,
	output wire [2:0]        d_hsize,
	output wire [2:0]        d_hburst,
	output wire [3:0]        d_hprot,
	output wire              d_hmastlock,
	output wire              d_hexcl,
	input  wire              d_hready,
	input  wire              d_hresp,
	input  wire              d_hexokay,
	output wire [W_DATA-1:0] d_hwdata,
	input  wire [W_DATA-1:0] d_hrdata,

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
wire              core_aph_panic_i; // unused as there's no arbitration
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
// Instruction port

localparam HTRANS_IDLE = 2'b00;
localparam HTRANS_NSEQ = 2'b10;

assign i_haddr = core_haddr_i;
assign i_htrans = core_aph_req_i ? HTRANS_NSEQ : HTRANS_IDLE;
assign i_hsize = core_hsize_i;

reg dphase_active_i;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		dphase_active_i <= 1'b0;
	else if (i_hready)
		dphase_active_i <= core_aph_req_i;

assign core_aph_ready_i = i_hready && core_aph_req_i;
assign core_dph_ready_i = i_hready && dphase_active_i;
assign core_dph_err_i   = i_hready && dphase_active_i && i_hresp;

assign core_rdata_i = i_hrdata;

assign i_hwrite = 1'b0;
assign i_hburst = 3'h0;
assign i_hmastlock = 1'b0;
assign i_hwdata = {W_DATA{1'b0}};

assign i_hprot = {
	2'b00,         // Noncacheable/nonbufferable
	core_priv_i,   // Privileged or Normal as per core state
	1'b0           // Instruction access
};

// ----------------------------------------------------------------------------
// Load/store port

assign d_haddr = core_haddr_d;
assign d_htrans = core_aph_req_d ? HTRANS_NSEQ : HTRANS_IDLE;
assign d_hwrite = core_hwrite_d;
assign d_hsize = core_hsize_d;
assign d_hexcl = core_aph_excl_d;

reg dphase_active_d;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		dphase_active_d <= 1'b0;
	else if (d_hready)
		dphase_active_d <= core_aph_req_d;

// D-side errors are reported even when not ready, so that the core can make
// use of the two-phase error response to cleanly squash a second load/store
// chasing the faulting one down the pipeline.
assign core_aph_ready_d = d_hready && core_aph_req_d;
assign core_dph_ready_d = d_hready && dphase_active_d;
assign core_dph_err_d = dphase_active_d && d_hresp;
assign core_dph_exokay_d = dphase_active_d && d_hexokay;

assign core_rdata_d = d_hrdata;
assign d_hwdata = core_wdata_d;

assign d_hburst = 3'h0;
assign d_hmastlock = 1'b0;

assign d_hprot = {
	2'b00,         // Noncacheable/nonbufferable
	core_priv_d,   // Privileged or Normal as per core state
	1'b1           // Data access
};

endmodule

`default_nettype wire
