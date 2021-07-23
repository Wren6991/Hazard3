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

// Example file integrating a Hazard3 processor, processor JTAG + debug
// components, some memory and a UART.

`default_nettype none

module example_soc #(
	parameter DTM_TYPE = "JTAG",    // can be "JTAG" or "ECP5"
	parameter SRAM_DEPTH = 1 << 15, // default 32 kwords -> 128 kB

	`include "hazard3_config.vh"
) (
	// System clock + reset
	input wire               clk,
	input wire               rst_n,

	// JTAG port to RISC-V JTAG-DTM
	input  wire              tck,
	input  wire              trst_n,
	input  wire              tms,
	input  wire              tdi,
	output wire              tdo,

	// IO
	output wire              uart_tx,
	input  wire              uart_rx
);

localparam W_ADDR = 32;
localparam W_DATA = 32;

// ----------------------------------------------------------------------------
// Processor debug

wire              dmi_psel;
wire              dmi_penable;
wire              dmi_pwrite;
wire [7:0]        dmi_paddr;
wire [31:0]       dmi_pwdata;
reg  [31:0]       dmi_prdata;
wire              dmi_pready;
wire              dmi_pslverr;


// TCK-domain DTM logic can force a hard reset of the
wire dmihardreset_req;
wire assert_dmi_reset = !rst_n || dmihardreset_req;
wire rst_n_dmi;

reset_sync dmi_reset_sync_u (
	.clk       (clk),
	.rst_n_in  (!assert_dmi_reset),
	.rst_n_out (rst_n_dmi)
);

generate
if (DTM_TYPE == "JTAG") begin

	// Standard RISC-V JTAG-DTM connected to external IOs.
	// JTAG-DTM IDCODE should be a JEP106-compliant ID:
	localparam IDCODE = 32'hdeadbeef;

	hazard3_jtag_dtm #(
		.IDCODE (IDCODE)
	) dtm_u (
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

end else if (DTM_TYPE == "ECP5") begin

	// Attach RISC-V DTM's DTMCS/DMI registers to ECP5 ER1/ER2 registers. This
	// allows the processor to be debugged through the ECP5 chip TAP, using
	// regular upstream OpenOCD.

	// Connects to ECP5 TAP internally by instantiating a JTAGG primitive.
	assign tdo = 1'b0;

	hazard3_ecp5_jtag_dtm dtm_u (
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

end
endgenerate


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

hazard3_dm #(
	.N_HARTS      (N_HARTS),
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
	.hart_instr_caught_ebreak    (hart_instr_caught_ebreak)
);


// Generate resynchronised reset for CPU based on upstream system reset and on
// system/hart reset requests from DM.

wire assert_cpu_reset = !rst_n || sys_reset_req || hart_reset_req[0];
wire rst_n_cpu;

reset_sync cpu_reset_sync (
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

// ----------------------------------------------------------------------------
// Processor

wire [W_ADDR-1:0] proc_haddr;
wire              proc_hwrite;
wire [1:0]        proc_htrans;
wire [2:0]        proc_hsize;
wire [2:0]        proc_hburst;
wire [3:0]        proc_hprot;
wire              proc_hmastlock;
wire              proc_hready;
wire              proc_hresp;
wire [W_DATA-1:0] proc_hwdata;
wire [W_DATA-1:0] proc_hrdata;

wire uart_irq;

hazard3_cpu_1port #(
	// These must have the values given here for you to end up with a useful SoC:
	.RESET_VECTOR    (32'h0000_00c0),
	.MTVEC_INIT      (32'h0000_0000),
	.CSR_M_MANDATORY (1),
	.CSR_M_TRAP      (1),
	.DEBUG_SUPPORT   (1),
	.NUM_IRQ         (1),
	// Can be overridden from the defaults in hazard3_config.vh during
	// instantiation of example_soc():
	.EXTENSION_C     (EXTENSION_C),
	.EXTENSION_M     (EXTENSION_M),
	.CSR_COUNTER     (CSR_COUNTER),
	.MVENDORID_VAL   (MVENDORID_VAL),
	.MARCHID_VAL     (MARCHID_VAL),
	.MIMPID_VAL      (MIMPID_VAL),
	.MHARTID_VAL     (MHARTID_VAL),
	.REDUCED_BYPASS  (REDUCED_BYPASS),
	.MULDIV_UNROLL   (MULDIV_UNROLL),
	.MUL_FAST        (MUL_FAST),
	.MTVEC_WMASK     (MTVEC_WMASK)
) cpu (
	.clk                        (clk),
	.rst_n                      (rst_n_cpu),

	.ahblm_haddr                (proc_haddr),
	.ahblm_hwrite               (proc_hwrite),
	.ahblm_htrans               (proc_htrans),
	.ahblm_hsize                (proc_hsize),
	.ahblm_hburst               (proc_hburst),
	.ahblm_hprot                (proc_hprot),
	.ahblm_hmastlock            (proc_hmastlock),
	.ahblm_hready               (proc_hready),
	.ahblm_hresp                (proc_hresp),
	.ahblm_hwdata               (proc_hwdata),
	.ahblm_hrdata               (proc_hrdata),

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

	.irq                        (uart_irq),

	// Should provide timer and software-controllable IRQ at system level --
	// not implemented in this basic SoC.
	.soft_irq                   (1'b0),
	.timer_irq                  (1'b0)
);


// ----------------------------------------------------------------------------
// Bus fabric

// - 128 kB SRAM (using SPRAMs) at 0x0000_0000
// - UART at 0x4000_0000

// AHBL layer

wire               sram0_hready_resp;
wire               sram0_hready;
wire               sram0_hresp;
wire [W_ADDR-1:0]  sram0_haddr;
wire               sram0_hwrite;
wire [1:0]         sram0_htrans;
wire [2:0]         sram0_hsize;
wire [2:0]         sram0_hburst;
wire [3:0]         sram0_hprot;
wire               sram0_hmastlock;
wire [W_DATA-1:0]  sram0_hwdata;
wire [W_DATA-1:0]  sram0_hrdata;

wire               bridge_hready_resp;
wire               bridge_hready;
wire               bridge_hresp;
wire [W_ADDR-1:0]  bridge_haddr;
wire               bridge_hwrite;
wire [1:0]         bridge_htrans;
wire [2:0]         bridge_hsize;
wire [2:0]         bridge_hburst;
wire [3:0]         bridge_hprot;
wire               bridge_hmastlock;
wire [W_DATA-1:0]  bridge_hwdata;
wire [W_DATA-1:0]  bridge_hrdata;


ahbl_splitter #(
	.N_PORTS     (2),
	.ADDR_MAP    (64'h40000000_20000000),
	.ADDR_MASK   (64'he0000000_e0000000)
) splitter_u (
	.clk (clk),
	.rst_n (rst_n),

	.src_hready_resp (proc_hready   ),
	.src_hready      (proc_hready   ),
	.src_hresp       (proc_hresp    ),
	.src_haddr       (proc_haddr    ),
	.src_hwrite      (proc_hwrite   ),
	.src_htrans      (proc_htrans   ),
	.src_hsize       (proc_hsize    ),
	.src_hburst      (proc_hburst   ),
	.src_hprot       (proc_hprot    ),
	.src_hmastlock   (proc_hmastlock),
	.src_hwdata      (proc_hwdata   ),
	.src_hrdata      (proc_hrdata   ),

	.dst_hready_resp ({bridge_hready_resp , sram0_hready_resp}),
	.dst_hready      ({bridge_hready      , sram0_hready     }),
	.dst_hresp       ({bridge_hresp       , sram0_hresp      }),
	.dst_haddr       ({bridge_haddr       , sram0_haddr      }),
	.dst_hwrite      ({bridge_hwrite      , sram0_hwrite     }),
	.dst_htrans      ({bridge_htrans      , sram0_htrans     }),
	.dst_hsize       ({bridge_hsize       , sram0_hsize      }),
	.dst_hburst      ({bridge_hburst      , sram0_hburst     }),
	.dst_hprot       ({bridge_hprot       , sram0_hprot      }),
	.dst_hmastlock   ({bridge_hmastlock   , sram0_hmastlock  }),
	.dst_hwdata      ({bridge_hwdata      , sram0_hwdata     }),
	.dst_hrdata      ({bridge_hrdata      , sram0_hrdata     })
);

// APB layer

wire        uart_psel;
wire        uart_penable;
wire        uart_pwrite;
wire [15:0] uart_paddr;
wire [31:0] uart_pwdata;
wire [31:0] uart_prdata;
wire        uart_pready;
wire        uart_pslverr;

ahbl_to_apb apb_bridge_u (
	.clk               (clk),
	.rst_n             (rst_n),

	.ahbls_hready      (bridge_hready),
	.ahbls_hready_resp (bridge_hready_resp),
	.ahbls_hresp       (bridge_hresp),
	.ahbls_haddr       (bridge_haddr),
	.ahbls_hwrite      (bridge_hwrite),
	.ahbls_htrans      (bridge_htrans),
	.ahbls_hsize       (bridge_hsize),
	.ahbls_hburst      (bridge_hburst),
	.ahbls_hprot       (bridge_hprot),
	.ahbls_hmastlock   (bridge_hmastlock),
	.ahbls_hwdata      (bridge_hwdata),
	.ahbls_hrdata      (bridge_hrdata),

	.apbm_paddr        (uart_paddr),
	.apbm_psel         (uart_psel),
	.apbm_penable      (uart_penable),
	.apbm_pwrite       (uart_pwrite),
	.apbm_pwdata       (uart_pwdata),
	.apbm_pready       (uart_pready),
	.apbm_prdata       (uart_prdata),
	.apbm_pslverr      (uart_pslverr)
);

// ----------------------------------------------------------------------------
// Memory and peripherals

// No preloaded bootloader -- just use the debugger! (the processor will
// actually enter an infinite crash loop after reset if memory is
// zero-initialised so don't leave the little guy hanging too long)

ahb_sync_sram #(
	.DEPTH (SRAM_DEPTH)
) sram0 (
	.clk               (clk),
	.rst_n             (rst_n),

	.ahbls_hready_resp (sram0_hready_resp),
	.ahbls_hready      (sram0_hready),
	.ahbls_hresp       (sram0_hresp),
	.ahbls_haddr       (sram0_haddr),
	.ahbls_hwrite      (sram0_hwrite),
	.ahbls_htrans      (sram0_htrans),
	.ahbls_hsize       (sram0_hsize),
	.ahbls_hburst      (sram0_hburst),
	.ahbls_hprot       (sram0_hprot),
	.ahbls_hmastlock   (sram0_hmastlock),
	.ahbls_hwdata      (sram0_hwdata),
	.ahbls_hrdata      (sram0_hrdata)
);

uart_mini uart_u (
	.clk          (clk),
	.rst_n        (rst_n),

	.apbs_psel    (uart_psel),
	.apbs_penable (uart_penable),
	.apbs_pwrite  (uart_pwrite),
	.apbs_paddr   (uart_paddr),
	.apbs_pwdata  (uart_pwdata),
	.apbs_prdata  (uart_prdata),
	.apbs_pready  (uart_pready),
	.apbs_pslverr (uart_pslverr),

	.rx           (uart_rx),
	.tx           (uart_tx),
	.cts          (1'b0),
	.rts          (/* unused */),
	.irq          (uart_irq),
	.dreq         (/* unused */)
);

endmodule
