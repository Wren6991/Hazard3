module rvfi_wrapper (
	input wire clock,
	input wire reset,
	`RVFI_OUTPUTS
);

// ----------------------------------------------------------------------------
// Memory Interface
// ----------------------------------------------------------------------------

(* keep *) wire               [31:0]  haddr;
(* keep *) wire                       hwrite;
(* keep *) wire               [1:0]   htrans;
(* keep *) wire               [2:0]   hsize;
(* keep *) wire               [2:0]   hburst;
(* keep *) wire               [3:0]   hprot;
(* keep *) wire                       hmastlock;
(* keep *) `rvformal_rand_reg         hready;
(* keep *) wire                       hresp;
(* keep *) wire               [31:0]  hwdata;
(* keep *) `rvformal_rand_reg [31:0]  hrdata;

// AHB-lite requires: data phase of IDLE has no wait states
always @ (posedge clock)
	if ($past(htrans) == 2'b00 && $past(hready))
		assume(hready);

// Handling of bus faults is not tested
// always assume(!hresp);

`ifdef RISCV_FORMAL_FAIRNESS

reg [7:0] bus_fairness_ctr;
localparam MAX_STALL_LENGTH = 8;

always @ (posedge clock) begin
	if (reset)
		bus_fairness_ctr <= 8'h0;
	else if (hready)
		bus_fairness_ctr <= 8'h0;
	else
		bus_fairness_ctr <= bus_fairness_ctr + ~&bus_fairness_ctr;

	assume(bus_fairness_ctr <= MAX_STALL_LENGTH);
end

`endif

// ----------------------------------------------------------------------------
// Device Under Test
// ----------------------------------------------------------------------------

hazard5_cpu #(
	.RESET_VECTOR (0),
	.EXTENSION_C  (1),
	.EXTENSION_M  (1)
) dut (
	.clk             (clock),
	.rst_n           (!reset),
	.ahblm_haddr     (haddr),
	.ahblm_hwrite    (hwrite),
	.ahblm_htrans    (htrans),
	.ahblm_hsize     (hsize),
	.ahblm_hburst    (hburst),
	.ahblm_hprot     (hprot),
	.ahblm_hmastlock (hmastlock),
	.ahblm_hready    (hready),
	.ahblm_hresp     (hresp),
	.ahblm_hwdata    (hwdata),
	.ahblm_hrdata    (hrdata),
	`RVFI_CONN
);

endmodule
