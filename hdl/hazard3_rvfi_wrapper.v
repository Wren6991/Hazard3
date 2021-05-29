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


// AHB-lite requires: data phase of IDLE has no wait states
always @ (posedge clock) begin
	if ($past(i_htrans) == 2'b00 && $past(i_hready))
		assume(i_hready);
	if ($past(d_htrans) == 2'b00 && $past(d_hready))
		assume(d_hready);
end

`ifdef RISCV_FORMAL_FAIRNESS

reg [7:0] i_bus_fairness_ctr;
reg [7:0] d_bus_fairness_ctr;
localparam MAX_STALL_LENGTH = 8;

always @ (posedge clock) begin
	if (reset) begin
		i_bus_fairness_ctr <= 8'h0;
		d_bus_fairness_ctr <= 8'h0;
	end else begin
		i_bus_fairness_ctr <= i_bus_fairness_ctr + ~&i_bus_fairness_ctr;
		d_bus_fairness_ctr <= d_bus_fairness_ctr + ~&d_bus_fairness_ctr;
		if (i_hready)
			i_bus_fairness_ctr <= 8'h0;
		if (d_hready)
			d_bus_fairness_ctr <= 8'h0;
	end
	assume(i_bus_fairness_ctr <= MAX_STALL_LENGTH);
	assume(d_bus_fairness_ctr <= MAX_STALL_LENGTH);
end

`endif

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
