/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Dual-ported top level file for Hazard3 CPU. This file instantiates the
// Hazard3 core, and interfaces its instruction fetch and load/store signals
// to a pair of AHB5 master ports.

`default_nettype none

module hazard3_cpu_2port #(
`include "hazard3_config.vh"
) (
	// Global signals
	input wire                clk,
	input wire                clk_always_on,
	input wire                rst_n,

	// Power control signals
	output wire               pwrup_req,
	input  wire               pwrup_ack,
	output wire               clk_en,
	output wire               unblock_out,
	input  wire               unblock_in,

	`ifdef RISCV_FORMAL
	`RVFI_OUTPUTS ,
	`endif

	// Instruction fetch port
	output wire [W_ADDR-1:0]  i_haddr,
	output wire               i_hwrite,
	output wire [1:0]         i_htrans,
	output wire [2:0]         i_hsize,
	output wire [2:0]         i_hburst,
	output wire [3:0]         i_hprot,
	output wire               i_hmastlock,
	output wire [7:0]         i_hmaster,
	input  wire               i_hready,
	input  wire               i_hresp,
	output wire [W_DATA-1:0]  i_hwdata,
	input  wire [W_DATA-1:0]  i_hrdata,

	// Load/store port
	output wire [W_ADDR-1:0]  d_haddr,
	output wire               d_hwrite,
	output wire [1:0]         d_htrans,
	output wire [2:0]         d_hsize,
	output wire [2:0]         d_hburst,
	output wire [3:0]         d_hprot,
	output wire               d_hmastlock,
	output wire [7:0]         d_hmaster,
	output wire               d_hexcl,
	input  wire               d_hready,
	input  wire               d_hresp,
	input  wire               d_hexokay,
	output wire [W_DATA-1:0]  d_hwdata,
	input  wire [W_DATA-1:0]  d_hrdata,

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
	.bus_aph_panic_i            (/* unused for 2port */),
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
assign i_hmaster = 8'h00;
assign i_hwdata = {W_DATA{1'b0}};

assign i_hprot = {
	2'b00,         // Noncacheable/nonbufferable
	core_priv_i,   // Privileged or Normal as per core state
	1'b0           // Instruction access
};

// ----------------------------------------------------------------------------
// Load/store port

// The debug module has optional System Bus Access support, which can be muxed
// into the processor's D port here (or connected to a standalone AHB shim).
// This confers absolutely no advantage for debugger bus throughput, but
// allows the debugger to access the bus with minimal disturbance to the
// processor.

wire      bus_gnt_d;
wire      bus_gnt_s;

reg       bus_hold_aph;
reg [1:0] bus_gnt_ds_prev;
reg       bus_active_dph_d;
reg       bus_active_dph_s;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		bus_hold_aph <= 1'b0;
		bus_gnt_ds_prev <= 2'h0;
	end else begin
		bus_hold_aph <= d_htrans[1] && !d_hready && !d_hresp;
		bus_gnt_ds_prev <= {bus_gnt_d, bus_gnt_s};
	end
end

assign {bus_gnt_d, bus_gnt_s} =
	bus_hold_aph                      ? bus_gnt_ds_prev :
	core_aph_req_d                    ? 2'b10 :
	dbg_sbus_vld && !bus_active_dph_s ? 2'b01 :
	                                    2'b00 ;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		bus_active_dph_d <= 1'b0;
		bus_active_dph_s <= 1'b0;
	end else if (d_hready) begin
		bus_active_dph_d <= bus_gnt_d;
		bus_active_dph_s <= bus_gnt_s;
	end
end

assign d_htrans = bus_gnt_d || bus_gnt_s ? HTRANS_NSEQ : HTRANS_IDLE;

assign d_haddr  = bus_gnt_s ? dbg_sbus_addr         : core_haddr_d;
assign d_hwrite = bus_gnt_s ? dbg_sbus_write        : core_hwrite_d;
assign d_hsize  = bus_gnt_s ? {1'b0, dbg_sbus_size} : core_hsize_d;
assign d_hexcl  = bus_gnt_s ? 1'b0                  : core_aph_excl_d;

assign d_hprot = {
	2'b00,                    // Noncacheable/nonbufferable
	bus_gnt_s || core_priv_d, // Privileged or Normal as per core state
	1'b1                      // Data access
};

assign d_hwdata = bus_active_dph_s ? dbg_sbus_wdata : core_wdata_d;

// D-side errors are reported even when not ready, so that the core can make
// use of the two-phase error response to cleanly squash a second load/store
// chasing the faulting one down the pipeline.
assign core_aph_ready_d  = d_hready && bus_gnt_d;
assign core_dph_ready_d  = bus_active_dph_d && d_hready;
assign core_dph_err_d    = bus_active_dph_d && d_hresp;
assign core_dph_exokay_d = bus_active_dph_d && d_hexokay;
assign core_rdata_d = d_hrdata;

assign dbg_sbus_err = bus_active_dph_s && d_hresp;
assign dbg_sbus_rdy = bus_active_dph_s && d_hready;
assign dbg_sbus_rdata = d_hrdata;

assign d_hburst = 3'h0;
assign d_hmastlock = 1'b0;
assign d_hmaster = bus_gnt_s ? 8'h01 : 8'h00;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
