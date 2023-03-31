// An integration of JTAG-DTM + DM + CPU for openocd to poke at over a remote
// bitbang socket

`default_nettype none

module tb #(
	parameter W_DATA = 32, // do not modify
	parameter W_ADDR = 32  // do not modify
) (
	// Global signals
	input wire                clk,
	input wire                rst_n,

	// JTAG port
    input  wire               tck,
    input  wire               trst_n,
    input  wire               tms,
    input  wire               tdi,
    output wire               tdo,

	// Instruction fetch port
	output wire [W_ADDR-1:0]  i_haddr,
	output wire               i_hwrite,
	output wire [1:0]         i_htrans,
	output wire               i_hexcl,
	output wire [2:0]         i_hsize,
	output wire [2:0]         i_hburst,
	output wire [3:0]         i_hprot,
	output wire               i_hmastlock,
	input  wire               i_hready,
	input  wire               i_hresp,
	input  wire               i_hexokay,
	output wire [W_DATA-1:0]  i_hwdata,
	input  wire [W_DATA-1:0]  i_hrdata,

	// Load/store port
	output wire [W_ADDR-1:0]  d_haddr,
	output wire               d_hwrite,
	output wire [1:0]         d_htrans,
	output wire               d_hexcl,
	output wire [2:0]         d_hsize,
	output wire [2:0]         d_hburst,
	output wire [3:0]         d_hprot,
	output wire               d_hmastlock,
	input  wire               d_hready,
	input  wire               d_hresp,
	input  wire               d_hexokay,
	output wire [W_DATA-1:0]  d_hwdata,
	input  wire [W_DATA-1:0]  d_hrdata,

	// Level-sensitive interrupt sources
	input wire [NUM_IRQS-1:0] irq,       // -> mip.meip
	input wire [1:0]          soft_irq,  // -> mip.msip
	input wire                timer_irq  // -> mip.mtip
);

// JTAG-DTM IDCODE, selected after TAP reset, would normally be a
// JEP106-compliant ID
localparam IDCODE = 32'hdeadbeef;

wire              dmi_psel;
wire              dmi_penable;
wire              dmi_pwrite;
wire [8:0]        dmi_paddr;
wire [31:0]       dmi_pwdata;
reg  [31:0]       dmi_prdata;
wire              dmi_pready;
wire              dmi_pslverr;

wire dmihardreset_req;
wire assert_dmi_reset = !rst_n || dmihardreset_req;
wire rst_n_dmi;

hazard3_reset_sync dmi_reset_sync_u (
	.clk       (clk),
	.rst_n_in  (!assert_dmi_reset),
	.rst_n_out (rst_n_dmi)
);

// Note the idle hint of 8 cycles was empirically found to be the correct
// value for a 1:2 TCK:clk_dmi ratio. OpenOCD doesn't particularly care
// because it will just increase idle cycles until it stops seeing BUSY.

hazard3_jtag_dtm #(
	.IDCODE          (IDCODE),
	.DTMCS_IDLE_HINT (8)
) inst_hazard3_jtag_dtm (
	.tck              (tck),
	.trst_n           (trst_n),
	.tms              (tms),
	.tdi              (tdi),
	.tdo              (tdo),

	.dmihardreset_req (dmihardreset_req),

	.clk_dmi          (clk),
	.rst_n_dmi        (rst_n_dmi),

	.dmi_psel         (dmi_psel),
	.dmi_penable      (dmi_penable),
	.dmi_pwrite       (dmi_pwrite),
	.dmi_paddr        (dmi_paddr),
	.dmi_pwdata       (dmi_pwdata),
	.dmi_prdata       (dmi_prdata),
	.dmi_pready       (dmi_pready),
	.dmi_pslverr      (dmi_pslverr)
);

localparam N_HARTS = 1;
localparam XLEN = 32;

wire                      sys_reset_req;
wire                      sys_reset_done;
wire [N_HARTS-1:0]        hart_reset_req;
wire [N_HARTS-1:0]        hart_reset_done;

wire [N_HARTS-1:0]        hart_req_halt;
wire [N_HARTS-1:0]        hart_req_halt_on_reset;
wire [N_HARTS-1:0]        hart_req_resume;
wire [N_HARTS-1:0]        hart_halted;
wire [N_HARTS-1:0]        hart_running;

wire [N_HARTS*XLEN-1:0]   hart_data0_rdata;
wire [N_HARTS*XLEN-1:0]   hart_data0_wdata;
wire [N_HARTS-1:0]        hart_data0_wen;

wire [N_HARTS*XLEN-1:0]   hart_instr_data;
wire [N_HARTS-1:0]        hart_instr_data_vld;
wire [N_HARTS-1:0]        hart_instr_data_rdy;
wire [N_HARTS-1:0]        hart_instr_caught_exception;
wire [N_HARTS-1:0]        hart_instr_caught_ebreak;

wire [31:0]               sbus_addr;
wire                      sbus_write;
wire [1:0]                sbus_size;
wire                      sbus_vld;
wire                      sbus_rdy;
wire                      sbus_err;
wire [31:0]               sbus_wdata;
wire [31:0]               sbus_rdata;

hazard3_dm #(
	.N_HARTS      (N_HARTS),
	.HAVE_SBA     (1),
	.NEXT_DM_ADDR (0)
) dm (
	.clk                         (clk),
	.rst_n                       (rst_n),

	.dmi_psel                    (dmi_psel),
	.dmi_penable                 (dmi_penable),
	.dmi_pwrite                  (dmi_pwrite),
	.dmi_paddr                   (dmi_paddr),
	.dmi_pwdata                  (dmi_pwdata),
	.dmi_prdata                  (dmi_prdata),
	.dmi_pready                  (dmi_pready),
	.dmi_pslverr                 (dmi_pslverr),

	.sys_reset_req               (sys_reset_req),
	.sys_reset_done              (sys_reset_done),
	.hart_reset_req              (hart_reset_req),
	.hart_reset_done             (hart_reset_done),

	.hart_req_halt               (hart_req_halt),
	.hart_req_halt_on_reset      (hart_req_halt_on_reset),
	.hart_req_resume             (hart_req_resume),
	.hart_halted                 (hart_halted),
	.hart_running                (hart_running),

	.hart_data0_rdata            (hart_data0_rdata),
	.hart_data0_wdata            (hart_data0_wdata),
	.hart_data0_wen              (hart_data0_wen),

	.hart_instr_data             (hart_instr_data),
	.hart_instr_data_vld         (hart_instr_data_vld),
	.hart_instr_data_rdy         (hart_instr_data_rdy),
	.hart_instr_caught_exception (hart_instr_caught_exception),
	.hart_instr_caught_ebreak    (hart_instr_caught_ebreak),

	.sbus_addr                   (sbus_addr),
	.sbus_write                  (sbus_write),
	.sbus_size                   (sbus_size),
	.sbus_vld                    (sbus_vld),
	.sbus_rdy                    (sbus_rdy),
	.sbus_err                    (sbus_err),
	.sbus_wdata                  (sbus_wdata),
	.sbus_rdata                  (sbus_rdata)
);


// Generate resynchronised reset for CPU based on upstream reset and
// on reset requests from DM.

wire assert_cpu_reset = !rst_n || sys_reset_req || hart_reset_req[0];
wire rst_n_cpu;

hazard3_reset_sync cpu_reset_sync (
	.clk       (clk),
	.rst_n_in  (!assert_cpu_reset),
	.rst_n_out (rst_n_cpu)
);

// Still some work to be done on the reset handshake -- this ought to be
// resynchronised to DM's reset domain here, and the DM should wait for a
// rising edge after it has asserted the reset pulse, to make sure the tail
// of the previous "done" is not passed on.
assign sys_reset_done = rst_n_cpu;
assign hart_reset_done = rst_n_cpu;


wire pwrup_req;
reg  pwrup_ack;
wire clk_en;
wire unblock_out;
wire unblock_in = unblock_out;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		pwrup_ack <= 1'b1;
	end else begin
		pwrup_ack <= pwrup_req;
	end
end

// Clock gate is disabled, as CXXRTL currently can't simulated gated clocks
// due to a limitation of the scheduler design

// // Latching clock gate. Does not insert an NBA delay on the gated clock, so
// // safe to exchange data between NBAs on the gated and non-gated clock. Does
// // not glitch as long as clk_en is driven from an NBA on the posedge of clk
// // (e.g. a normal RTL register). The clock stops *high*.

// reg clk_gated;

// always @ (*) begin
// 	if (clk_en)
// 		clk_gated = clk;
// end

`ifndef CONFIG_HEADER
`define CONFIG_HEADER "config_default.vh"
`endif
`include `CONFIG_HEADER

hazard3_cpu_2port #(
`include "hazard3_config_inst.vh"
) cpu (
	.clk                        (clk),
	.clk_always_on              (clk),
	.rst_n                      (rst_n_cpu),

	.pwrup_req                  (pwrup_req),
	.pwrup_ack                  (pwrup_ack),
	.clk_en                     (clk_en),
	.unblock_out                (unblock_out),
	.unblock_in                 (unblock_in),

	.i_haddr                    (i_haddr),
	.i_hwrite                   (i_hwrite),
	.i_htrans                   (i_htrans),
	.i_hsize                    (i_hsize),
	.i_hburst                   (i_hburst),
	.i_hprot                    (i_hprot),
	.i_hmastlock                (i_hmastlock),
	.i_hready                   (i_hready),
	.i_hresp                    (i_hresp),
	.i_hwdata                   (i_hwdata),
	.i_hrdata                   (i_hrdata),

	.d_haddr                    (d_haddr),
	.d_hexcl                    (d_hexcl),
	.d_hwrite                   (d_hwrite),
	.d_htrans                   (d_htrans),
	.d_hsize                    (d_hsize),
	.d_hburst                   (d_hburst),
	.d_hprot                    (d_hprot),
	.d_hmastlock                (d_hmastlock),
	.d_hready                   (d_hready),
	.d_hresp                    (d_hresp),
	.d_hexokay                  (d_hexokay),
	.d_hwdata                   (d_hwdata),
	.d_hrdata                   (d_hrdata),

	.dbg_req_halt               (hart_req_halt),
	.dbg_req_halt_on_reset      (hart_req_halt_on_reset),
	.dbg_req_resume             (hart_req_resume),
	.dbg_halted                 (hart_halted),
	.dbg_running                (hart_running),

	.dbg_data0_rdata            (hart_data0_rdata),
	.dbg_data0_wdata            (hart_data0_wdata),
	.dbg_data0_wen              (hart_data0_wen),

	.dbg_instr_data             (hart_instr_data),
	.dbg_instr_data_vld         (hart_instr_data_vld),
	.dbg_instr_data_rdy         (hart_instr_data_rdy),
	.dbg_instr_caught_exception (hart_instr_caught_exception),
	.dbg_instr_caught_ebreak    (hart_instr_caught_ebreak),

	.dbg_sbus_addr              (sbus_addr),
	.dbg_sbus_write             (sbus_write),
	.dbg_sbus_size              (sbus_size),
	.dbg_sbus_vld               (sbus_vld),
	.dbg_sbus_rdy               (sbus_rdy),
	.dbg_sbus_err               (sbus_err),
	.dbg_sbus_wdata             (sbus_wdata),
	.dbg_sbus_rdata             (sbus_rdata),

	.irq                        (irq),
	.soft_irq                   (soft_irq[0]),
	.timer_irq                  (timer_irq[0])
);

assign i_hexcl = 1'b0;

endmodule
