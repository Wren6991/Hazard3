// Assume bus responses are well-formed, assert that bus requests are
// well-formed.

module tb;

reg clk;
reg rst_n = 1'b0;
always @ (posedge clk)
	rst_n <= 1'b1;

// ----------------------------------------------------------------------------
// DUT

(* keep *) wire [31:0]       ahblm_haddr;
(* keep *) wire              ahblm_hwrite;
(* keep *) wire              ahblm_hexcl;
(* keep *) wire [1:0]        ahblm_htrans;
(* keep *) wire [2:0]        ahblm_hsize;
(* keep *) wire [2:0]        ahblm_hburst;
(* keep *) wire [3:0]        ahblm_hprot;
(* keep *) wire              ahblm_hmastlock;
(* keep *) wire              ahblm_hready;
(* keep *) wire              ahblm_hexokay;
(* keep *) wire              ahblm_hresp;
(* keep *) wire [31:0]       ahblm_hwdata;
(* keep *) wire [31:0]       ahblm_hrdata;

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

(*keep*) wire [31:0]         dbg_sbus_addr;
(*keep*) wire                dbg_sbus_write;
(*keep*) wire [1:0]          dbg_sbus_size;
(*keep*) wire                dbg_sbus_vld;
(*keep*) wire                dbg_sbus_rdy;
(*keep*) wire                dbg_sbus_err;
(*keep*) wire [31:0]         dbg_sbus_wdata;
(*keep*) wire [31:0]         dbg_sbus_rdata;

(* keep *) wire [31:0]       irq;
(* keep *) wire              soft_irq;
(* keep *) wire              timer_irq;

hazard3_cpu_1port dut (
	.clk                        (clk),
	.rst_n                      (rst_n),

	.ahblm_haddr                (ahblm_haddr),
	.ahblm_hwrite               (ahblm_hwrite),
	.ahblm_hexcl                (ahblm_hexcl),
	.ahblm_htrans               (ahblm_htrans),
	.ahblm_hsize                (ahblm_hsize),
	.ahblm_hburst               (ahblm_hburst),
	.ahblm_hprot                (ahblm_hprot),
	.ahblm_hmastlock            (ahblm_hmastlock),
	.ahblm_hready               (ahblm_hready),
	.ahblm_hexokay              (ahblm_hexokay),
	.ahblm_hresp                (ahblm_hresp),
	.ahblm_hwdata               (ahblm_hwdata),
	.ahblm_hrdata               (ahblm_hrdata),

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

	.dbg_sbus_addr              (dbg_sbus_addr),
	.dbg_sbus_write             (dbg_sbus_write),
	.dbg_sbus_size              (dbg_sbus_size),
	.dbg_sbus_vld               (dbg_sbus_vld),
	.dbg_sbus_rdy               (dbg_sbus_rdy),
	.dbg_sbus_err               (dbg_sbus_err),
	.dbg_sbus_wdata             (dbg_sbus_wdata),
	.dbg_sbus_rdata             (dbg_sbus_rdata),

	.irq                        (irq),
	.soft_irq                   (soft_irq),
	.timer_irq                  (timer_irq)
);

// ----------------------------------------------------------------------------
// Bus properties

// -1 -> unconstrained, >=0 -> max length
localparam MAX_BUS_STALL = -1;

ahbl_slave_assumptions #(
	.MAX_BUS_STALL (MAX_BUS_STALL)
) d_assumptions (
	.clk             (clk),
	.rst_n           (rst_n),

	.dst_hready_resp (ahblm_hready),
	.dst_hready      (ahblm_hready),
	.dst_hresp       (ahblm_hresp),
	.dst_hexokay     (ahblm_hexokay),
	.dst_haddr       (ahblm_haddr),
	.dst_hwrite      (ahblm_hwrite),
	.dst_htrans      (ahblm_htrans),
	.dst_hsize       (ahblm_hsize),
	.dst_hburst      (ahblm_hburst),
	.dst_hprot       (ahblm_hprot),
	.dst_hmastlock   (ahblm_hmastlock),
	.dst_hexcl       (ahblm_hexcl),
	.dst_hwdata      (ahblm_hwdata),
	.dst_hrdata      (ahblm_hrdata)
);

ahbl_master_assertions d_assertions (
	.clk             (clk),
	.rst_n           (rst_n),

	.src_hready      (ahblm_hready),
	.src_hresp       (ahblm_hresp),
	.src_hexokay     (ahblm_hexokay),
	.src_haddr       (ahblm_haddr),
	.src_hwrite      (ahblm_hwrite),
	.src_htrans      (ahblm_htrans),
	.src_hsize       (ahblm_hsize),
	.src_hburst      (ahblm_hburst),
	.src_hprot       (ahblm_hprot),
	.src_hmastlock   (ahblm_hmastlock),
	.src_hexcl       (ahblm_hexcl),
	.src_hwdata      (ahblm_hwdata),
	.src_hrdata      (ahblm_hrdata)
);

sbus_assumptions sbus_assumptions (
	.clk            (clk),
	.rst_n          (rst_n),

	.dbg_sbus_addr  (dbg_sbus_addr),
	.dbg_sbus_write (dbg_sbus_write),
	.dbg_sbus_size  (dbg_sbus_size),
	.dbg_sbus_vld   (dbg_sbus_vld),
	.dbg_sbus_rdy   (dbg_sbus_rdy),
	.dbg_sbus_err   (dbg_sbus_err),
	.dbg_sbus_wdata (dbg_sbus_wdata),
	.dbg_sbus_rdata (dbg_sbus_rdata)
);

endmodule
