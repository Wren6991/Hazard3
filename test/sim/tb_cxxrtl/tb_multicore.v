// An integration of JTAG-DTM + DM + 2 single-ported CPUs for openocd to poke
// at over a remote bitbang socket

`default_nettype none

module tb #(
	parameter W_ADDR = 32, // do not modify
	parameter W_DATA = 32  // do not modify
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

	// Core 0 bus (named I for consistency with 1-core 2-port tb)
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

	// Core 1 bus (named D for consistency with 1-core 2-port tb)
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
	input wire [1:0]          timer_irq  // -> mip.mtip
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

localparam N_HARTS = 2;
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

wire assert_cpu_reset0 = !rst_n || sys_reset_req || hart_reset_req[0];
wire assert_cpu_reset1 = !rst_n || sys_reset_req || hart_reset_req[1];
wire rst_n_cpu0;
wire rst_n_cpu1;

hazard3_reset_sync cpu0_reset_sync (
	.clk       (clk),
	.rst_n_in  (!assert_cpu_reset0),
	.rst_n_out (rst_n_cpu0)
);

hazard3_reset_sync cpu1_reset_sync (
	.clk       (clk),
	.rst_n_in  (!assert_cpu_reset1),
	.rst_n_out (rst_n_cpu1)
);

// Still some work to be done on the reset handshake -- this ought to be
// resynchronised to DM's reset domain here, and the DM should wait for a
// rising edge after it has asserted the reset pulse, to make sure the tail
// of the previous "done" is not passed on.
assign sys_reset_done = rst_n_cpu0 && rst_n_cpu1;
assign hart_reset_done = {rst_n_cpu1, rst_n_cpu0};

`ifndef CONFIG_HEADER
`define CONFIG_HEADER "config_default.vh"
`endif
`include `CONFIG_HEADER

wire pwrup_req_cpu0;
wire pwrup_req_cpu1;
wire unblock_out_cpu0;
wire unblock_out_cpu1;

hazard3_cpu_1port #(
	.MHARTID_VAL (32'h0000_0000),
`define HAZARD3_CONFIG_INST_NO_MHARTID
`include "hazard3_config_inst.vh"
) cpu0 (
	.clk                        (clk),
	.clk_always_on              (clk),
	.rst_n                      (rst_n_cpu0),

	.pwrup_req                  (pwrup_req_cpu0),
	.pwrup_ack                  (pwrup_req_cpu0),
	.clk_en                     (),
	.unblock_out                (unblock_out_cpu0),
	.unblock_in                 (unblock_out_cpu1),

	.haddr                      (i_haddr),
	.hexcl                      (i_hexcl),
	.hwrite                     (i_hwrite),
	.htrans                     (i_htrans),
	.hsize                      (i_hsize),
	.hburst                     (i_hburst),
	.hprot                      (i_hprot),
	.hmastlock                  (i_hmastlock),
	.hready                     (i_hready),
	.hresp                      (i_hresp),
	.hexokay                    (i_hexokay),
	.hwdata                     (i_hwdata),
	.hrdata                     (i_hrdata),

	.dbg_req_halt               (hart_req_halt              [0]),
	.dbg_req_halt_on_reset      (hart_req_halt_on_reset     [0]),
	.dbg_req_resume             (hart_req_resume            [0]),
	.dbg_halted                 (hart_halted                [0]),
	.dbg_running                (hart_running               [0]),

	.dbg_data0_rdata            (hart_data0_rdata           [0 * XLEN +: XLEN]),
	.dbg_data0_wdata            (hart_data0_wdata           [0 * XLEN +: XLEN]),
	.dbg_data0_wen              (hart_data0_wen             [0]),

	.dbg_instr_data             (hart_instr_data            [0 * XLEN +: XLEN]),
	.dbg_instr_data_vld         (hart_instr_data_vld        [0]),
	.dbg_instr_data_rdy         (hart_instr_data_rdy        [0]),
	.dbg_instr_caught_exception (hart_instr_caught_exception[0]),
	.dbg_instr_caught_ebreak    (hart_instr_caught_ebreak   [0]),

	// SBA is routed through core 1, so tie off on core 0
	.dbg_sbus_addr              (32'h0),
	.dbg_sbus_write             (1'b0),
	.dbg_sbus_size              (2'h0),
	.dbg_sbus_vld               (1'b0),
	.dbg_sbus_rdy               (),
	.dbg_sbus_err               (),
	.dbg_sbus_wdata             (32'h0),
	.dbg_sbus_rdata             (),

	.irq                        (irq),
	.soft_irq                   (soft_irq[0]),
	.timer_irq                  (timer_irq[0])
);

hazard3_cpu_1port #(
	.MHARTID_VAL (32'h0000_0001),
`define HAZARD3_CONFIG_INST_NO_MHARTID
`include "hazard3_config_inst.vh"
) cpu1 (
	.clk                        (clk),
	.clk_always_on              (clk),
	.rst_n                      (rst_n_cpu1),

	.pwrup_req                  (pwrup_req_cpu1),
	.pwrup_ack                  (pwrup_req_cpu1),
	.clk_en                     (),
	.unblock_out                (unblock_out_cpu1),
	.unblock_in                 (unblock_out_cpu0),

	.haddr                      (d_haddr),
	.hexcl                      (d_hexcl),
	.hwrite                     (d_hwrite),
	.htrans                     (d_htrans),
	.hsize                      (d_hsize),
	.hburst                     (d_hburst),
	.hprot                      (d_hprot),
	.hmastlock                  (d_hmastlock),
	.hready                     (d_hready),
	.hresp                      (d_hresp),
	.hexokay                    (d_hexokay),
	.hwdata                     (d_hwdata),
	.hrdata                     (d_hrdata),

	.dbg_req_halt               (hart_req_halt              [1]),
	.dbg_req_halt_on_reset      (hart_req_halt_on_reset     [1]),
	.dbg_req_resume             (hart_req_resume            [1]),
	.dbg_halted                 (hart_halted                [1]),
	.dbg_running                (hart_running               [1]),

	.dbg_data0_rdata            (hart_data0_rdata           [1 * XLEN +: XLEN]),
	.dbg_data0_wdata            (hart_data0_wdata           [1 * XLEN +: XLEN]),
	.dbg_data0_wen              (hart_data0_wen             [1]),

	.dbg_instr_data             (hart_instr_data            [1 * XLEN +: XLEN]),
	.dbg_instr_data_vld         (hart_instr_data_vld        [1]),
	.dbg_instr_data_rdy         (hart_instr_data_rdy        [1]),
	.dbg_instr_caught_exception (hart_instr_caught_exception[1]),
	.dbg_instr_caught_ebreak    (hart_instr_caught_ebreak   [1]),

	.dbg_sbus_addr              (sbus_addr),
	.dbg_sbus_write             (sbus_write),
	.dbg_sbus_size              (sbus_size),
	.dbg_sbus_vld               (sbus_vld),
	.dbg_sbus_rdy               (sbus_rdy),
	.dbg_sbus_err               (sbus_err),
	.dbg_sbus_wdata             (sbus_wdata),
	.dbg_sbus_rdata             (sbus_rdata),

	.irq                        (irq),
	.soft_irq                   (soft_irq[1]),
	.timer_irq                  (timer_irq[1])
);


endmodule
