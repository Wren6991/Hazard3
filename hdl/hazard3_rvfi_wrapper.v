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

(* keep *) `rvformal_rand_reg [15:0] irq;

hazard3_cpu_2port #(
	.RESET_VECTOR  (0),
	.EXTENSION_C   (1),
	.EXTENSION_M   (1),
	.MUL_FAST      (1),
	.MULDIV_UNROLL (2)
) dut (
	.clk         (clock),
	.rst_n       (!reset),

	.i_haddr     (i_haddr),
	.i_hwrite    (i_hwrite),
	.i_htrans    (i_htrans),
	.i_hsize     (i_hsize),
	.i_hburst    (i_hburst),
	.i_hprot     (i_hprot),
	.i_hmastlock (i_hmastlock),
	.i_hready    (i_hready),
	.i_hresp     (i_hresp),
	.i_hwdata    (i_hwdata),
	.i_hrdata    (i_hrdata),

	.d_haddr     (d_haddr),
	.d_hwrite    (d_hwrite),
	.d_htrans    (d_htrans),
	.d_hsize     (d_hsize),
	.d_hburst    (d_hburst),
	.d_hprot     (d_hprot),
	.d_hmastlock (d_hmastlock),
	.d_hready    (d_hready),
	.d_hresp     (d_hresp),
	.d_hwdata    (d_hwdata),
	.d_hrdata    (d_hrdata),

	.irq         (irq),

	`RVFI_CONN
);

endmodule
