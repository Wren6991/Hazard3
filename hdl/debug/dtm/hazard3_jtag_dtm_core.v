/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// DTMCS + DMI control logic, bus interface and bus clock domain crossing for
// a standard RISC-V APB JTAG-DTM. Essentially everything apart from the
// actual TAP controller, IR and shift registers. Instantiated by
// hazard3_jtag_dtm.v.
//
// This core logic can be reused and connected to some other serial transport
// or, for example, the ECP5 JTAGG primitive (see hazard5_ecp5_jtag_dtm.v)

`default_nettype none

module hazard3_jtag_dtm_core #(
	parameter DTMCS_IDLE_HINT = 3'd4,
	parameter W_ADDR = 8,
	parameter W_DR_SHIFT = W_ADDR + 32 + 2 // do not modify
) (
	input  wire                  tck,
	input  wire                  trst_n,

	input  wire                  clk_dmi,
	input  wire                  rst_n_dmi,

	// DR capture/update (read/write) signals
	input  wire                  dr_wen,
	input  wire                  dr_ren,
	input  wire                  dr_sel_dmi_ndtmcs,
	input  wire [W_DR_SHIFT-1:0] dr_wdata,
	output wire [W_DR_SHIFT-1:0] dr_rdata,

	// This is synchronous to TCK and asserted for one TCK cycle only
	output reg                   dmihardreset_req,

	// Debug Module Interface (APB)
	output wire                  dmi_psel,
	output wire                  dmi_penable,
	output wire                  dmi_pwrite,
	output wire [W_ADDR-1:0]     dmi_paddr,
	output wire [31:0]           dmi_pwdata,
	input  wire [31:0]           dmi_prdata,
	input  wire                  dmi_pready,
	input  wire                  dmi_pslverr
);

wire write_dmi   = dr_wen &&  dr_sel_dmi_ndtmcs;
wire write_dtmcs = dr_wen && !dr_sel_dmi_ndtmcs;
wire read_dmi    = dr_ren &&  dr_sel_dmi_ndtmcs;
wire read_dtmcs  = dr_ren && !dr_sel_dmi_ndtmcs;

// ----------------------------------------------------------------------------
// DMI bus adapter

reg [1:0]   dmi_cmderr;
reg         dmi_busy;

// DTM-domain bus, connected to a matching DM-domain bus via an APB crossing:
wire              dtm_psel;
wire              dtm_penable;
wire              dtm_pwrite;
wire [W_ADDR-1:0] dtm_paddr;
wire [31:0]       dtm_pwdata;
wire [31:0]       dtm_prdata;
wire              dtm_pready;
wire              dtm_pslverr;

// We are relying on some particular features of our APB clock crossing here
// to save some registers:
//
// - The transfer is launched immediately when psel is seen, no need to
//   actually assert an access phase (as the standard allows the CDC to
//   assume that access immediately follows setup) and no need to maintain
//   pwrite/paddr/pwdata valid after the setup phase
//
// - prdata/pslverr remain valid after the transfer completes, until the next
//   transfer completes
//
// These allow us to connect the upstream side of the CDC directly to our DR
// shifter without any sample/hold registers in between.

// psel is only pulsed for one cycle, penable is not asserted.
assign dtm_psel = write_dmi &&
	(dr_wdata[1:0] == 2'd1 || dr_wdata[1:0] == 2'd2) &&
	!(dmi_busy || dmi_cmderr != 2'd0) && dtm_pready;
assign dtm_penable = 1'b0;

// paddr/pwdata/pwrite are valid momentarily when psel is asserted.
assign dtm_paddr = dr_wdata[34 +: W_ADDR];
assign dtm_pwrite = dr_wdata[1];
assign dtm_pwdata = dr_wdata[2 +: 32];

always @ (posedge tck or negedge trst_n) begin
	if (!trst_n) begin
		dmi_busy <= 1'b0;
		dmi_cmderr <= 2'd0;
	end else if (read_dmi) begin
		// Reading while busy sets the busy sticky error. Note the capture
		// into shift register should also reflect this update on-the-fly
		if (dmi_busy && dmi_cmderr == 2'd0)
			dmi_cmderr <= 2'h3;
	end else if (write_dtmcs) begin
		// Writing dtmcs.dmireset = 1 clears a sticky error
		if (dr_wdata[16])
			dmi_cmderr <= 2'd0;
	end else if (write_dmi) begin
		if (dtm_psel) begin
			dmi_busy <= 1'b1;
		end else if (dr_wdata[1:0] != 2'd0) begin
			// DMI ignored operation, so set sticky busy
			if (dmi_cmderr == 2'd0)
				dmi_cmderr <= 2'd3;
		end
	end else if (dmi_busy && dtm_pready) begin
		dmi_busy <= 1'b0;
		if (dmi_cmderr == 2'd0 && dtm_pslverr)
			dmi_cmderr <= 2'd2;
	end
end

// DTM logic is in TCK domain, actual DMI + DM is in processor domain

hazard3_apb_async_bridge #(
	.W_ADDR        (W_ADDR),
	.W_DATA        (32),
	.N_SYNC_STAGES (2)
) inst_hazard3_apb_async_bridge (
	.clk_src     (tck),
	.rst_n_src   (trst_n),

	.clk_dst     (clk_dmi),
	.rst_n_dst   (rst_n_dmi),

	.src_psel    (dtm_psel),
	.src_penable (dtm_penable),
	.src_pwrite  (dtm_pwrite),
	.src_paddr   (dtm_paddr),
	.src_pwdata  (dtm_pwdata),
	.src_prdata  (dtm_prdata),
	.src_pready  (dtm_pready),
	.src_pslverr (dtm_pslverr),

	.dst_psel    (dmi_psel),
	.dst_penable (dmi_penable),
	.dst_pwrite  (dmi_pwrite),
	.dst_paddr   (dmi_paddr),
	.dst_pwdata  (dmi_pwdata),
	.dst_prdata  (dmi_prdata),
	.dst_pready  (dmi_pready),
	.dst_pslverr (dmi_pslverr)
);

// ----------------------------------------------------------------------------
// DR read/write

wire [W_DR_SHIFT-1:0] dtmcs_rdata = {
	{W_ADDR{1'b0}},
	19'h0,
	DTMCS_IDLE_HINT[2:0],
	dmi_cmderr,
	W_ADDR[5:0],   // abits
	4'd1           // version
};

wire [W_DR_SHIFT-1:0] dmi_rdata = {
	{W_ADDR{1'b0}},
	dtm_prdata,
	dmi_busy && dmi_cmderr == 2'd0 ? 2'd3 : dmi_cmderr
};

assign dr_rdata = dr_sel_dmi_ndtmcs ? dmi_rdata : dtmcs_rdata;

always @ (posedge tck or negedge trst_n) begin
	if (!trst_n) begin
		dmihardreset_req <= 1'b0;
	end else begin
		dmihardreset_req <= write_dtmcs && dr_wdata[17];
	end
end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
