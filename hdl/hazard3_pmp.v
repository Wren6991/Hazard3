/*****************************************************************************\
|                        Copyright (C) 2022 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

// Physical memory protection unit

module hazard3_pmp #(
`include "hazard3_config.vh"
) (
	input  wire              clk,
	input  wire              rst_n,

	// Config interface passed through CSR block
	input  wire [11:0]       cfg_addr,
	input  wire              cfg_wen,
	input  wire [W_DATA-1:0] cfg_wdata,
	output reg  [W_DATA-1:0] cfg_rdata,

	// Fetch address query
	input  wire [W_ADDR-1:0] i_addr,
	input  wire              i_m_mode,
	output wire              i_kill,

	// Load/store address query
	input  wire [W_ADDR-1:0] d_addr,
	// Broken out separately for carry-save:
	input  wire [W_ADDR-1:0] d_addr_addend_rs1,
	input  wire [W_ADDR-1:0] d_addr_addend_imm,
	input  wire [W_ADDR-1:0] d_addr_addend_lspair_offs,
	input  wire              d_m_mode,
	input  wire              d_write,
	output wire              d_kill
);

localparam PMP_A_NAPOT = 2'b11;
localparam PMP_A_NA4   = 2'b10;
localparam PMP_A_TOR   = 2'b01;
localparam PMP_A_OFF   = 2'b00;

// Which values are supported in A field (unsupported are mapped to OFF):
localparam [3:0] PMP_A_SUPPORTED = {
	|PMP_MATCH_NAPOT,
	|PMP_MATCH_NAPOT && PMP_GRAIN == 0,
	|PMP_MATCH_TOR,
	1'b1
};

`include "hazard3_csr_addr.vh"

generate
if (PMP_REGIONS == 0) begin: no_pmp

// This should already be stubbed out in core.v, but use a generate here too
// so that we don't get a warning for elaborating this module with a region
// count of 0.

always @ (*) cfg_rdata = {W_DATA{1'b0}};
assign i_kill = 1'b0;
assign d_kill = 1'b0;

end else begin: have_pmp

// ----------------------------------------------------------------------------
// Config registers and read/write interface

// Whether a region's configuration is writable; this is non-trivial when TOR
// is supported because locking region i + 1 can also lock region i.
wire [PMP_REGIONS-1:0] region_locked;

reg  [PMP_REGIONS-1:0] pmpcfg_l;
reg  [1:0]             pmpcfg_a [0:PMP_REGIONS-1];
reg  [PMP_REGIONS-1:0] pmpcfg_x;
reg  [PMP_REGIONS-1:0] pmpcfg_w;
reg  [PMP_REGIONS-1:0] pmpcfg_r;

// Address register contains bits 33:2 of the address (to support 16 GiB
// physical address space). We don't implement bits 33 or 32.
reg  [W_ADDR-3:0]      pmpaddr  [0:PMP_REGIONS-1];

// Hazard3 extension for applying PMP regions to M-mode without locking.
// Different from ePMP mseccfg.rlb: low-numbered regions may be locked for
// security reasons, but higher-numbered regions should still be available for
// other purposes e.g. stack guarding, peripheral emulation
reg  [PMP_REGIONS-1:0] pmpcfg_m;

always @ (posedge clk or negedge rst_n) begin: cfg_update
	reg signed [31:0] i;
	if (!rst_n) begin
		for (i = 0; i < PMP_REGIONS; i = i + 1) begin
			pmpcfg_l[i] <= PMP_HARDWIRED[i] ? PMP_HARDWIRED_CFG[8 * i + 7]      : 1'b0;
			pmpcfg_a[i] <= PMP_HARDWIRED[i] ? PMP_HARDWIRED_CFG[8 * i + 3 +: 2] : 2'h0;
			pmpcfg_x[i] <= PMP_HARDWIRED[i] ? PMP_HARDWIRED_CFG[8 * i + 2]      : 1'b0;
			pmpcfg_w[i] <= PMP_HARDWIRED[i] ? PMP_HARDWIRED_CFG[8 * i + 1]      : 1'b0;
			pmpcfg_r[i] <= PMP_HARDWIRED[i] ? PMP_HARDWIRED_CFG[8 * i + 0]      : 1'b0;

			pmpaddr[i]  <= PMP_HARDWIRED[i] ? PMP_HARDWIRED_ADDR[32 * i +: 30]  :
			               PMP_GRAIN > 1    ? ~(~30'h0 << (PMP_GRAIN - 1))      : 30'h0;
		end
		pmpcfg_m <= {PMP_REGIONS{1'b0}};
	end else if (cfg_wen) begin
		for (i = 0; i < PMP_REGIONS; i = i + 1) begin
			if (cfg_addr == PMPCFG0 + i[13:2] && !region_locked[i]) begin
				if (PMP_HARDWIRED[i]) begin
					// Keep tied to hardwired value (but still make the "register" sensitive to clk)
					pmpcfg_l[i] <= PMP_HARDWIRED_CFG[8 * i + 7];
					pmpcfg_a[i] <= PMP_HARDWIRED_CFG[8 * i + 3 +: 2];
					pmpcfg_x[i] <= PMP_HARDWIRED_CFG[8 * i + 2];
					pmpcfg_w[i] <= PMP_HARDWIRED_CFG[8 * i + 1];
					pmpcfg_r[i] <= PMP_HARDWIRED_CFG[8 * i + 0];
					pmpaddr[i]  <= PMP_HARDWIRED_ADDR[32 * i +: 30];
				end else begin
					pmpcfg_l[i] <= cfg_wdata[i % 4 * 8 + 7];
					pmpcfg_x[i] <= cfg_wdata[i % 4 * 8 + 2];
					pmpcfg_w[i] <= cfg_wdata[i % 4 * 8 + 1];
					pmpcfg_r[i] <= cfg_wdata[i % 4 * 8 + 0];
					// Unsupported A values are mapped to OFF (it's a WARL field).
					pmpcfg_a[i] <= PMP_A_SUPPORTED[cfg_wdata[i % 4 * 8 + 3 +: 2]] ?
						cfg_wdata[i % 4 * 8 + 3 +: 2] : PMP_A_OFF;
				end
			end
			if (cfg_addr == PMPADDR0 + i[11:0] && !region_locked[i]) begin
				// This implements one bit too many when G > 0 and only
				// PMP_MATCH_TOR is enabled, however that bit is ignored for
				// both rdata and address matching, so should be trimmed.
				if (PMP_GRAIN > 1) begin
					pmpaddr[i] <= cfg_wdata[W_ADDR-3:0] | ~(~30'h0 << (PMP_GRAIN - 1));
				end else begin
					pmpaddr[i] <= cfg_wdata[W_ADDR-3:0];
				end
			end
		end
		if (cfg_addr == PMPCFGM0) begin
			pmpcfg_m <= cfg_wdata[PMP_REGIONS-1:0] & ~PMP_HARDWIRED & {PMP_REGIONS{|EXTENSION_XH3PMPM}};
		end
	end
end


always @ (*) begin: cfg_read
	reg signed [31:0] i;
	cfg_rdata = {W_DATA{1'b0}};
	for (i = 0; i < PMP_REGIONS; i = i + 1) begin
		if (cfg_addr == PMPCFG0 + i[13:2]) begin
			cfg_rdata[i % 4 * 8 +: 8] = {
				pmpcfg_l[i],
				2'b00,
				pmpcfg_a[i],
				pmpcfg_x[i],
				pmpcfg_w[i],
				pmpcfg_r[i]
			};
		end else if (cfg_addr == PMPADDR0 + i[11:0]) begin
			if (PMP_GRAIN >= 2 && pmpcfg_a[i][1]) begin
				// Bits G-2:0 read back as all-ones when A is NA4 or NAPOT.
				cfg_rdata[W_ADDR-3:0] = pmpaddr[i] | ~({W_ADDR-2{1'b1}} << (PMP_GRAIN - 1));
			end else if (PMP_GRAIN >= 1 && !pmpcfg_a[i][1]) begin
				// Bits G-1:0 read back as all-zeroes when A is OFF or TOR.
				cfg_rdata[W_ADDR-3:0] = pmpaddr[i] & ({W_ADDR-2{1'b1}} << PMP_GRAIN);
			end else begin
				cfg_rdata[W_ADDR-3:0] = pmpaddr[i];
			end
		end
	end
	if (cfg_addr == PMPCFGM0) begin
		cfg_rdata = {{32-PMP_REGIONS{1'b0}}, pmpcfg_m} & {32{|EXTENSION_XH3PMPM}};
	end
end

// ----------------------------------------------------------------------------
// Region locking rules

reg [PMP_REGIONS-1:0] pmp_region_is_tor;
always @ (*) begin: check_region_is_tor
	integer i;
	for (i = 0; i < PMP_REGIONS; i = i + 1) begin
		pmp_region_is_tor[i] = PMP_MATCH_TOR && pmpcfg_a[i] == PMP_A_TOR;
	end
end

assign region_locked = pmpcfg_l | ((pmpcfg_l & pmp_region_is_tor) >> 1);

// ----------------------------------------------------------------------------
// Match addresses against regions

wire [PMP_REGIONS-1:0] d_match_napot;
wire [PMP_REGIONS-1:0] i_match_napot;
wire [PMP_REGIONS-1:0] d_match_tor;
wire [PMP_REGIONS-1:0] i_match_tor;

if (PMP_MATCH_NAPOT != 0) begin: have_napot

	reg [PMP_REGIONS-1:0] d_match_napot_r;
	reg [PMP_REGIONS-1:0] i_match_napot_r;

	assign d_match_napot = d_match_napot_r;
	assign i_match_napot = i_match_napot_r;

	// Decode PMPCFGx.A and PMPADDRx into a 32-bit address mask and address
	reg [W_ADDR-1:0] match_mask [0:PMP_REGIONS-1];
	reg [W_ADDR-1:0] match_addr [0:PMP_REGIONS-1];

	// Encoding: (noting ADDR is a 4-byte address, not a word address):
	// CFG.A |  ADDR    | Region size
	// ------+----------+------------
	// NA4   | y..yyyyy | 4 bytes
	// NAPOT | y..yyyy0 | 8 bytes
	// NAPOT | y..yyy01 | 16 bytes
	// NAPOT | y..yy011 | 32 bytes
	// NAPOT | y..y0111 | 64 bytes
	// etc.
	//
	// So, with the exception of NA4, the rule is to check all bits more
	// significant than the least-significant 0 bit.

	always @ (*) begin: decode_match_mask_addr
		integer i, j;
		for (i = 0; i < PMP_REGIONS; i = i + 1) begin
			if (!pmpcfg_a[i][0]) begin
				match_mask[i] = {{W_ADDR-2{1'b1}}, 2'b00};
			end else begin
				// Bits 1:0 are always 0. Bit 2 is 0 because NAPOT is at least 8 bytes.
				match_mask[i] = {W_ADDR{1'b0}};
				for (j = 3; j < W_ADDR; j = j + 1) begin
					match_mask[i][j] = match_mask[i][j - 1] || !pmpaddr[i][j - 3];
				end
			end
			match_addr[i] = {pmpaddr[i], 2'b00} & match_mask[i];
		end
	end

	// We check only the least-addressed byte of each access. See later
	// comments for an argument as to why this is sufficient.

	always @ (*) begin: check_d_match
		integer i;
		for (i = PMP_REGIONS - 1; i >= 0; i = i - 1) begin
			d_match_napot_r[i] = pmpcfg_a[i][1] &&
				(d_addr & match_mask[i]) == match_addr[i];
			i_match_napot_r[i] = pmpcfg_a[i][1] &&
				(i_addr & match_mask[i]) == match_addr[i];
		end
	end

end else begin: no_napot

	assign d_match_napot = {PMP_REGIONS{1'b0}};
	assign i_match_napot = {PMP_REGIONS{1'b0}};

end

if (PMP_MATCH_TOR != 0) begin: have_tor

	reg [PMP_REGIONS-1:0] d_match_tor_r;
	reg [PMP_REGIONS-1:0] i_match_tor_r;
	reg [W_ADDR-1:0]      watermark [0:PMP_REGIONS-1];
	reg [PMP_REGIONS-1:0] d_lt;
	reg [PMP_REGIONS-1:0] i_lt;

	assign d_match_tor = d_match_tor_r;
	assign i_match_tor = i_match_tor_r;

	always @ (*) begin: compare
		integer i;
		for (i = 0; i < PMP_REGIONS; i = i + 1) begin
			watermark[i] = {
				pmpaddr[i][W_ADDR-3:0] & (~30'h0 << PMP_GRAIN),
				2'b00
			};
			// Bring terms in separately to try to encourage adder merging
			d_lt[i] = (
				d_addr_addend_rs1 + d_addr_addend_imm + d_addr_addend_lspair_offs
			) < watermark[i];
			i_lt[i] = i_addr < watermark[i];
		end
	end

	wire [PMP_REGIONS-1:0] d_prev_ge = ~(d_lt << 1);
	wire [PMP_REGIONS-1:0] i_prev_ge = ~(i_lt << 1);

	always @ (*) begin: match
		integer i;
		for (i = 0; i < PMP_REGIONS; i = i + 1) begin
			d_match_tor_r[i] = d_lt[i] && d_prev_ge[i] && pmpcfg_a[i] == PMP_A_TOR;
			i_match_tor_r[i] = i_lt[i] && i_prev_ge[i] && pmpcfg_a[i] == PMP_A_TOR;
		end
	end

end else begin: no_tor

	assign d_match_tor = {PMP_REGIONS{1'b0}};
	assign i_match_tor = {PMP_REGIONS{1'b0}};

end

// ----------------------------------------------------------------------------
// Decode permissions from matches

// For load/stores we assume any non-naturally-aligned transfers trigger a
// misaligned load/store/AMO exception, so we only need to decode the PMP
// attribute for the first byte of the access. Note the spec gives us freedom
// to report *either* a load/store/AMO access fault (mcause = 5, 7) or a
// load/store/AMO alignment fault (mcause = 4, 6), in the case that both
// happen, and we choose alignment fault in this case.

reg d_m; // Hazard3 extension (M-mode without locking)
reg d_l;
reg d_r;
reg d_w;

always @ (*) begin: check_d_match
	integer i;
	d_m = 1'b0;
	d_l = 1'b0;
	d_r = 1'b0;
	d_w = 1'b0;
	// Lowest-numbered match wins, so work down from the top. This should be
	// inferred as a priority mux structure (cascade mux).
	for (i = PMP_REGIONS - 1; i >= 0; i = i - 1) begin
		if (d_match_napot[i] || d_match_tor[i]) begin
			d_m = pmpcfg_m[i];
			d_l = pmpcfg_l[i];
			d_r = pmpcfg_r[i];
			d_w = pmpcfg_w[i];
		end
	end
end

// Instructions work similarly because we check *fetches*, not instructions.
// Fetch is always word-sized word-aligned. The spec permits this:
//
// "On some implementations, misaligned loads, stores, and instruction fetches
//  may also be decomposed into multiple accesses, some of which may succeed
//  before an access-fault exception occurs."
//
// Hazard3 separately checks the naturally-aligned fetches that occur in the
// course of fetching a non-naturally-aligned instruction. This means
// instruction fetch spanning two different regions which both grant X
// permission *is* permitted, unlike the RP2350 version of Hazard3.

reg i_m; // Hazard3 extension (M-mode without locking)
reg i_l;
reg i_x;

always @ (*) begin: check_i_match
	integer i;
	i_m = 1'b0;
	i_l = 1'b0;
	i_x = 1'b0;
	for (i = PMP_REGIONS - 1; i >= 0; i = i - 1) begin
		if (i_match_napot[i] || i_match_tor[i]) begin
			i_m = pmpcfg_m[i];
			i_l = pmpcfg_l[i];
			i_x = pmpcfg_x[i];
		end
	end
end

// ----------------------------------------------------------------------------
// Access rules

// M-mode gets to ignore protections, unless the lock or M-mode bit is set.

assign d_kill = (!d_m_mode || d_l || d_m) && (
	(!d_write && !d_r) ||
	( d_write && !d_w)
);

assign i_kill =	(!i_m_mode || i_l || i_m) && !i_x;

end
endgenerate

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
