module rvfi_wrapper (
	input wire clock,
	input wire reset,
	`RVFI_OUTPUTS
);

// ----------------------------------------------------------------------------
// Memory Interface
// ----------------------------------------------------------------------------

(* keep *) wire               [31:0]  i_haddr;
(* keep *) wire                       i_hwrite;
(* keep *) wire               [1:0]   i_htrans;
(* keep *) wire               [2:0]   i_hsize;
(* keep *) wire               [2:0]   i_hburst;
(* keep *) wire               [3:0]   i_hprot;
(* keep *) wire                       i_hmastlock;
(* keep *) `rvformal_rand_reg         i_hready;
(* keep *) `rvformal_rand_reg         i_hresp;
(* keep *) wire               [31:0]  i_hwdata;
(* keep *) `rvformal_rand_reg [31:0]  i_hrdata;

(* keep *) wire               [31:0]  d_haddr;
(* keep *) wire                       d_hwrite;
(* keep *) wire               [1:0]   d_htrans;
(* keep *) wire               [2:0]   d_hsize;
(* keep *) wire               [2:0]   d_hburst;
(* keep *) wire               [3:0]   d_hprot;
(* keep *) wire                       d_hmastlock;
(* keep *) `rvformal_rand_reg         d_hready;
(* keep *) `rvformal_rand_reg         d_hresp;
(* keep *) wire               [31:0]  d_hwdata;
(* keep *) `rvformal_rand_reg [31:0]  d_hrdata;

`ifdef RISCV_FORMAL_FAIRNESS
localparam MAX_BUS_STALL = 8;
`else
localparam MAX_BUS_STALL = -1;
`endif

ahbl_slave_assumptions #(
	.MAX_BUS_STALL (MAX_BUS_STALL)
) i_slave_assumptions (
	.clk             (clock),
	.rst_n           (!reset),

	.dst_hready_resp (i_hready),
	.dst_hready      (i_hready),
	.dst_hresp       (i_hresp),
	.dst_haddr       (i_haddr),
	.dst_hwrite      (i_hwrite),
	.dst_htrans      (i_htrans),
	.dst_hsize       (i_hsize),
	.dst_hburst      (i_hburst),
	.dst_hprot       (i_hprot),
	.dst_hmastlock   (i_hmastlock),
	.dst_hwdata      (i_hwdata),
	.dst_hrdata      (i_hrdata)
);


ahbl_slave_assumptions #(
	.MAX_BUS_STALL (MAX_BUS_STALL)
) d_slave_assumptions (
	.clk             (clock),
	.rst_n           (!reset),

	.dst_hready_resp (d_hready),
	.dst_hready      (d_hready),
	.dst_hresp       (d_hresp),
	.dst_haddr       (d_haddr),
	.dst_hwrite      (d_hwrite),
	.dst_htrans      (d_htrans),
	.dst_hsize       (d_hsize),
	.dst_hburst      (d_hburst),
	.dst_hprot       (d_hprot),
	.dst_hmastlock   (d_hmastlock),
	.dst_hwdata      (d_hwdata),
	.dst_hrdata      (d_hrdata)
);


// ----------------------------------------------------------------------------
// Device Under Test
// ----------------------------------------------------------------------------

// FIXME IRQs are tied off because riscv-formal doesn't accept the
// nonsequential pc_wdata when an instruction is followed by an interrupt
// (and the rvfi_intr signal doesn't do anything)

wire [31:0] irq = 0;
wire        soft_irq = 0;
wire        timer_irq = 0;
// (* keep *) `rvformal_rand_reg [15:0] irq;

localparam W_DATA = 32;

(* keep *) wire              dbg_req_halt;
(* keep *) wire              dbg_req_halt_on_reset;
(* keep *) wire              dbg_req_resume;
(* keep *) wire              dbg_halted;
(* keep *) wire              dbg_running;
(* keep *) wire [W_DATA-1:0] dbg_data0_rdata;
(* keep *) wire [W_DATA-1:0] dbg_data0_wdata;
(* keep *) wire              dbg_data0_wen;
(* keep *) wire [W_DATA-1:0] dbg_instr_data;
(* keep *) wire              dbg_instr_data_vld;
(* keep *) wire              dbg_instr_data_rdy;
(* keep *) wire              dbg_instr_caught_exception;
(* keep *) wire              dbg_instr_caught_ebreak;

hazard3_cpu_2port #(
	.RESET_VECTOR       (0),

	.EXTENSION_M        (1),
	.EXTENSION_A        (0), // FIXME
	.EXTENSION_C        (1),

	.EXTENSION_ZBA      (0),
	.EXTENSION_ZBB      (0),
	.EXTENSION_ZBC      (0),
	.EXTENSION_ZBS      (0),

	.CSR_M_MANDATORY    (1),
	.CSR_M_TRAP         (1),
	.CSR_COUNTER        (1),
	.DEBUG_SUPPORT      (0), // FIXME

	.NUM_IRQ            (32),

	.EXTENSION_ZIFENCEI (1),

	.REDUCED_BYPASS     (0),
	.FAST_BRANCHCMP     (1),
	.MUL_FAST           (1),
	.MULH_FAST          (1),
	.MULDIV_UNROLL      (2)
) dut (
	.clk                        (clock),
	.rst_n                      (!reset),

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
	.d_hwrite                   (d_hwrite),
	.d_htrans                   (d_htrans),
	.d_hexcl                    (/* FIXME */),
	.d_hsize                    (d_hsize),
	.d_hburst                   (d_hburst),
	.d_hprot                    (d_hprot),
	.d_hmastlock                (d_hmastlock),
	.d_hready                   (d_hready),
	.d_hresp                    (d_hresp),
	.d_hexokay                  (1'b1), // FIXME
	.d_hwdata                   (d_hwdata),
	.d_hrdata                   (d_hrdata),

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
	.timer_irq                  (timer_irq),

	`RVFI_CONN
);

endmodule
