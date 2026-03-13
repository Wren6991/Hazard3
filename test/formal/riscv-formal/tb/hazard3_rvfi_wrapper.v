/*****************************************************************************\
|                      Copyright (C) 2021-2025 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module rvfi_wrapper (
	input wire clock,
	input wire reset,
	`RVFI_OUTPUTS
	`RVFI_BUS_OUTPUTS
);

// ----------------------------------------------------------------------------
// Memory Interface
// ----------------------------------------------------------------------------

`ifndef SINGLE_PORTED_CORE
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
`endif

(* keep *) wire               [31:0]  d_haddr;
(* keep *) wire                       d_hwrite;
(* keep *) wire               [1:0]   d_htrans;
(* keep *) wire                       d_hexcl;
(* keep *) wire               [2:0]   d_hsize;
(* keep *) wire               [2:0]   d_hburst;
(* keep *) wire               [3:0]   d_hprot;
(* keep *) wire                       d_hmastlock;
(* keep *) wire               [7:0]   d_hmaster;
(* keep *) `rvformal_rand_reg         d_hready;
(* keep *) `rvformal_rand_reg         d_hresp;
(* keep *) `rvformal_rand_reg         d_hexokay;
(* keep *) wire               [31:0]  d_hwdata;
(* keep *) `rvformal_rand_reg [31:0]  d_hrdata;

(* keep *) wire                       fence_i_vld;
(* keep *) wire                       fence_d_vld;
(* keep *) wire                       fence_rdy;

(* keep *) `rvformal_rand_reg [31:0]  dbg_sbus_addr;
(* keep *) `rvformal_rand_reg         dbg_sbus_write;
(* keep *) `rvformal_rand_reg [1:0]   dbg_sbus_size;
(* keep *) `rvformal_rand_reg         dbg_sbus_vld;
(* keep *) wire                       dbg_sbus_rdy;
(* keep *) wire                       dbg_sbus_err;
(* keep *) `rvformal_rand_reg [31:0]  dbg_sbus_wdata;
(* keep *) wire               [31:0]  dbg_sbus_rdata;

`ifdef RISCV_FORMAL_FAIRNESS
`ifdef RISCV_FORMAL_FAIRNESS_MAX_STALL
localparam MAX_BUS_STALL = `RISCV_FORMAL_FAIRNESS_MAX_STALL;
`else
localparam MAX_BUS_STALL = 5;
`endif
`else
localparam MAX_BUS_STALL = -1;
`endif

`ifndef SINGLE_PORTED_CORE
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
`endif

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

sbus_assumptions #(
	.W_ADDR (32),
	.W_DATA (32)
) inst_sbus_assumptions (
	.clk            (clock),
	.rst_n          (!reset),
	.dbg_sbus_addr  (dbg_sbus_addr),
	.dbg_sbus_write (dbg_sbus_write),
	.dbg_sbus_size  (dbg_sbus_size),
	.dbg_sbus_vld   (dbg_sbus_vld),
	.dbg_sbus_rdy   (dbg_sbus_rdy),
	.dbg_sbus_err   (dbg_sbus_err),
	.dbg_sbus_wdata (dbg_sbus_wdata),
	.dbg_sbus_rdata (dbg_sbus_rdata)
);

`ifdef RISCV_FORMAL_FAIRNESS
// Limit the number of consecutive cycles the solver can stall the fence
// interface. This would be an uninteresting liveness failure.
reg [7:0] fence_stall_ctr;
always @ (posedge clock) begin
	if (reset) begin
		fence_stall_ctr <= 8'h00;
	end else if ((fence_i_vld || fence_d_vld) && !fence_rdy) begin
		fence_stall_ctr <= fence_stall_ctr + 8'h01;
		assume(fence_stall_ctr < MAX_BUS_STALL);
	end else begin
		fence_stall_ctr <= 8'h00;
	end
end
`endif

`ifdef RISCV_FORMAL_FAIRNESS
// Allow the solver to respond with HEXOKAY low only once (on cycles where
// exclusive data phases end, otherwise don't care). This is sufficient to
// cover most interesting paths and avoids the liveness check getting starved.
reg in_exclusive_dph;
reg seen_hexokay_low;
wire exclusive_dph_end = in_exclusive_dph && d_hready;
always @ (posedge clock) begin
	if (reset) begin
		seen_hexokay_low <= 1'b0;
		in_exclusive_dph <= 1'b0;
	end else begin
		seen_hexokay_low <= seen_hexokay_low || (exclusive_dph_end && !d_hexokay);
		if (d_hready) begin
			in_exclusive_dph <= d_htrans[1] && d_hexcl;
		end
	end
end

always @ (posedge clock) assume(d_hexokay || !exclusive_dph_end || !seen_hexokay_low);
`endif

`ifdef RISCV_FORMAL_FAIRNESS
// Disable bus faults for liveness check as the counterexamples aren't interesting
// TODO maybe the solver can have a couple of bus faults, as a treat
`ifndef SINGLE_PORTED_CORE
always assume(!i_hresp);
`endif
always assume(!d_hresp);
`endif

`ifdef RISCV_FORMAL_BUS
// Need to disable SBA accesses as they come out through the load/store port
// but cannot be cross-referenced with instruction execution
always assume(!dbg_sbus_vld);
`endif

`ifdef RISCV_FORMAL_FAIRNESS
`ifdef SINGLE_PORTED_CORE
// Disable SBUS access for single-ported liveness checks. These take priority
// over instruction fetch, and this is a known design limitation.
always assume(!dbg_sbus_vld);
`endif
`endif

// ----------------------------------------------------------------------------
// Device Under Test
// ----------------------------------------------------------------------------

(* keep *) `rvformal_rand_reg irq;
(* keep *) `rvformal_rand_reg soft_irq;
(* keep *) `rvformal_rand_reg timer_irq;

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

`ifdef NO_COMPRESSED_ISA
// Must be disabled for some checks combinations: e.g. riscv-formal doesn't
// currently support C + Zbb in the same test run (just a tooling issue)
localparam COMPRESSED = 0;
`else
localparam COMPRESSED = 1;
`endif

`ifdef ISA_ZCMP
// Disabled by default because riscv-formal doesn't understand instructions
// which perform multiple bus accesses or write multiple registers. We still
// run some checks, separately.
localparam EXTENSION_ZCMP = 1;
`else
localparam EXTENSION_ZCMP = 0;
`endif

`ifdef ISA_ZILSD_ZCLSD
// Disabled by default because riscv-formal doesn't understand instructions
// which perform multiple bus accesses or write multiple registers. We still
// run some checks, separately.
localparam EXTENSION_ZILSD = 1;
localparam EXTENSION_ZCLSD = 1;
`else
localparam EXTENSION_ZILSD = 0;
localparam EXTENSION_ZCLSD = 0;
`endif

`ifdef ISA_A
// riscv-formal doesn't model these instructions. It's possible to report AMOs
// as combined mem read + write, but not yet implemented.
localparam EXTENSION_A = 1;
`else
localparam EXTENSION_A = 0;
`endif

`ifdef SINGLE_PORTED_CORE
hazard3_cpu_1port #(
`else
hazard3_cpu_2port #(
`endif
	.RESET_VECTOR        (0),

	.EXTENSION_A         (EXTENSION_A),
	.EXTENSION_C         (COMPRESSED),
	.EXTENSION_E         (0),
	.EXTENSION_M         (1),

	.EXTENSION_ZBA       (1),
	.EXTENSION_ZBB       (1),
	.EXTENSION_ZBC       (1),
	.EXTENSION_ZBKB      (1),
	.EXTENSION_ZBKX      (1),
	.EXTENSION_ZBS       (1),
	.EXTENSION_ZCB       (COMPRESSED),
	.EXTENSION_ZCLSD     (EXTENSION_ZCLSD),
	.EXTENSION_ZIFENCEI  (1),
	.EXTENSION_ZILSD     (EXTENSION_ZILSD),
	.EXTENSION_ZCMP      (EXTENSION_ZCMP),
	.EXTENSION_XH3BEXTM  (1),
	.EXTENSION_XH3IRQ    (0), // Uninteresting: just a different way of driving mip.meip
	.EXTENSION_XH3PMPM   (0), // Uninteresting: just changes when PMP generates faults, and PMP is not modeled.
	.EXTENSION_XH3POWER  (0), // FIXME

	.CSR_M_MANDATORY     (1),
	.CSR_M_TRAP          (1),
	.CSR_COUNTER         (1),
	.DEBUG_SUPPORT       (0), // FIXME

	.NUM_IRQS            (1),

	.REDUCED_BYPASS      (0),
	.MUL_FAST            (1),
	.MULH_FAST           (1),
	.MULDIV_UNROLL       (4)  // Increased so more divide instructions fit in BMC depth
) dut (
	.clk                        (clock),
	.rst_n                      (!reset),

`ifdef SINGLE_PORTED_CORE
	.haddr                      (d_haddr),
	.hwrite                     (d_hwrite),
	.htrans                     (d_htrans),
	.hexcl                      (d_hexcl),
	.hsize                      (d_hsize),
	.hburst                     (d_hburst),
	.hprot                      (d_hprot),
	.hmastlock                  (d_hmastlock),
	.hready                     (d_hready),
	.hresp                      (d_hresp),
	.hexokay                    (d_hexcl),
	.hwdata                     (d_hwdata),
	.hrdata                     (d_hrdata),
`else
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
	.d_hexcl                    (d_hexcl),
	.d_hsize                    (d_hsize),
	.d_hburst                   (d_hburst),
	.d_hprot                    (d_hprot),
	.d_hmastlock                (d_hmastlock),
	.d_hready                   (d_hready),
	.d_hresp                    (d_hresp),
	.d_hexokay                  (d_hexokay),
	.d_hwdata                   (d_hwdata),
	.d_hrdata                   (d_hrdata),
`endif

	.fence_i_vld                (fence_i_vld),
	.fence_d_vld                (fence_d_vld),
	.fence_rdy                  (fence_rdy),

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

	.mhartid_val                (32'h0000_0000),
	.eco_version                (4'd0),

	.irq                        (irq),
	.soft_irq                   (soft_irq),
	.timer_irq                  (timer_irq),

	`RVFI_CONN
);

`ifdef RISCV_FORMAL_BUS
`ifndef SINGLE_PORTED_CORE
rvfi_bus_observer_ahb5 #(
	.XLEN   (32),
	.BUSLEN (32)
) observer_i (
	.clock          (clock),
	.reset          (reset),

	.ahb_haddr      (i_haddr),
	.ahb_hwrite     (i_hwrite),
	.ahb_htrans     (i_htrans),
	.ahb_hsize      (i_hsize),
	.ahb_hburst     (i_hburst),
	.ahb_hprot      ({3'h0, i_hprot}),
	.ahb_hmaster    (8'h00),
	.ahb_hexcl      (1'b0),
	.ahb_hready     (i_hready),
	.ahb_hresp      (i_hresp),
	.ahb_hexokay    (1'b0),
	.ahb_hwdata     (i_hwdata),
	.ahb_hrdata     (i_hrdata)

	`RVFI_BUS_CHANNEL_CONN(1)
);
`endif

rvfi_bus_observer_ahb5 #(
	.XLEN   (32),
	.BUSLEN (32)
) observer_d (
	.clock          (clock),
	.reset          (reset),

	.ahb_haddr      (d_haddr),
	.ahb_hwrite     (d_hwrite),
	.ahb_htrans     (d_htrans),
	.ahb_hsize      (d_hsize),
	.ahb_hburst     (d_hburst),
	.ahb_hprot      ({3'h0, d_hprot}),
	.ahb_hmaster    (d_hmaster),
	.ahb_hexcl      (d_hexcl),
	.ahb_hready     (d_hready),
	.ahb_hresp      (d_hresp),
	.ahb_hexokay    (d_hexokay),
	.ahb_hwdata     (d_hwdata),
	.ahb_hrdata     (d_hrdata)

	`RVFI_BUS_CHANNEL_CONN(0)
);
`endif

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
