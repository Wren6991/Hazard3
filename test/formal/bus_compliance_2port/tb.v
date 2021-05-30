// Assume bus responses to both ports are well-formed, assert that bus
// requests are well-formed.

module tb;

reg clk;
reg rst_n = 1'b0;
always @ (posedge clk)
	rst_n <= 1'b1;

// ----------------------------------------------------------------------------
// DUT

(* keep *) wire [31:0]  i_haddr;
(* keep *) wire         i_hwrite;
(* keep *) wire [1:0]   i_htrans;
(* keep *) wire [2:0]   i_hsize;
(* keep *) wire [2:0]   i_hburst;
(* keep *) wire [3:0]   i_hprot;
(* keep *) wire         i_hmastlock;
(* keep *) wire         i_hready;
(* keep *) wire         i_hresp;
(* keep *) wire [31:0]  i_hwdata;
(* keep *) wire [31:0]  i_hrdata;

(* keep *) wire [31:0]  d_haddr;
(* keep *) wire         d_hwrite;
(* keep *) wire [1:0]   d_htrans;
(* keep *) wire [2:0]   d_hsize;
(* keep *) wire [2:0]   d_hburst;
(* keep *) wire [3:0]   d_hprot;
(* keep *) wire         d_hmastlock;
(* keep *) wire         d_hready;
(* keep *) wire         d_hresp;
(* keep *) wire [31:0]  d_hwdata;
(* keep *) wire [31:0]  d_hrdata;

(* keep *) reg  [15:0]  irq;

hazard3_cpu_2port dut (
	.clk          (clk),
	.rst_n        (rst_n),

	.i_haddr      (i_haddr),
	.i_hwrite     (i_hwrite),
	.i_htrans     (i_htrans),
	.i_hsize      (i_hsize),
	.i_hburst     (i_hburst),
	.i_hprot      (i_hprot),
	.i_hmastlock  (i_hmastlock),
	.i_hready     (i_hready),
	.i_hresp      (i_hresp),
	.i_hwdata     (i_hwdata),
	.i_hrdata     (i_hrdata),

	.d_haddr      (d_haddr),
	.d_hwrite     (d_hwrite),
	.d_htrans     (d_htrans),
	.d_hsize      (d_hsize),
	.d_hburst     (d_hburst),
	.d_hprot      (d_hprot),
	.d_hmastlock  (d_hmastlock),
	.d_hready     (d_hready),
	.d_hresp      (d_hresp),
	.d_hwdata     (d_hwdata),
	.d_hrdata     (d_hrdata),

	.irq          (irq)
);

// ----------------------------------------------------------------------------
// Bus properties

// -1 -> unconstrained, >=0 -> max length
localparam MAX_BUS_STALL = -1;

ahbl_slave_assumptions #(
	.MAX_BUS_STALL (MAX_BUS_STALL)
) i_assumptions (
	.clk             (clk),
	.rst_n           (rst_n),

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
) d_assumptions (
	.clk             (clk),
	.rst_n           (rst_n),

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

ahbl_master_assertions i_assertions (
	.clk             (clk),
	.rst_n           (rst_n),

	.src_hready      (i_hready),
	.src_hresp       (i_hresp),
	.src_haddr       (i_haddr),
	.src_hwrite      (i_hwrite),
	.src_htrans      (i_htrans),
	.src_hsize       (i_hsize),
	.src_hburst      (i_hburst),
	.src_hprot       (i_hprot),
	.src_hmastlock   (i_hmastlock),
	.src_hwdata      (i_hwdata),
	.src_hrdata      (i_hrdata)
);


ahbl_master_assertions d_assertions (
	.clk             (clk),
	.rst_n           (rst_n),

	.src_hready      (d_hready),
	.src_hresp       (d_hresp),
	.src_haddr       (d_haddr),
	.src_hwrite      (d_hwrite),
	.src_htrans      (d_htrans),
	.src_hsize       (d_hsize),
	.src_hburst      (d_hburst),
	.src_hprot       (d_hprot),
	.src_hmastlock   (d_hmastlock),
	.src_hwdata      (d_hwdata),
	.src_hrdata      (d_hrdata)
);

endmodule
