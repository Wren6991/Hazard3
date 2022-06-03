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
	input  wire              mstatus_mxr, // make executable readable

	// Config interface passed through CSR block
	input  wire [11:0]       cfg_addr,
	input  wire              cfg_wen,
	input  wire [W_DATA-1:0] cfg_wdata,
	output reg  [W_DATA-1:0] cfg_rdata,

	// Fetch address query
	input  wire [W_ADDR-1:0] i_addr,
	input  wire              i_instr_is_32bit,
	input  wire              i_m_mode,
	output wire              i_kill,

	// Load/store address query
	input  wire [W_ADDR-1:0] d_addr,
	input  wire              d_m_mode,
	input  wire              d_write,
	output wire              d_kill
);

localparam PMP_A_OFF   = 2'b00;
localparam PMP_A_TOR   = 2'b01; // we don't implement
localparam PMP_A_NA4   = 2'b10;
localparam PMP_A_NAPOT = 2'b11;

`include "hazard3_csr_addr.vh"

// ----------------------------------------------------------------------------
// Config registers and read/write interface

reg              pmpcfg_l [0:PMP_REGIONS-1];
reg [1:0]        pmpcfg_a [0:PMP_REGIONS-1];
reg              pmpcfg_r [0:PMP_REGIONS-1];
reg              pmpcfg_w [0:PMP_REGIONS-1];
reg              pmpcfg_x [0:PMP_REGIONS-1];

// Address register contains bits 33:2 of the address (to support 16 GiB
// physical address space). We don't implement bits 33 or 32.
reg [W_ADDR-3:0] pmpaddr  [0:PMP_REGIONS-1];

always @ (posedge clk or negedge rst_n) begin: cfg_update
	integer i;
	if (!rst_n) begin
		for (i = 0; i < PMP_REGIONS; i = i + 1) begin
			pmpcfg_l[i] <= PMP_HARDWIRED[i] ? PMP_HARDWIRED_CFG[8 * i + 7]      : 1'b0;
			pmpcfg_a[i] <= PMP_HARDWIRED[i] ? PMP_HARDWIRED_CFG[8 * i + 3 +: 2] : 2'h0;
			pmpcfg_r[i] <= PMP_HARDWIRED[i] ? PMP_HARDWIRED_CFG[8 * i + 2]      : 1'b0;
			pmpcfg_w[i] <= PMP_HARDWIRED[i] ? PMP_HARDWIRED_CFG[8 * i + 1]      : 1'b0;
			pmpcfg_x[i] <= PMP_HARDWIRED[i] ? PMP_HARDWIRED_CFG[8 * i + 0]      : 1'b0;

			pmpaddr[i]  <= PMP_HARDWIRED[i] ? PMP_HARDWIRED_ADDR[32 * i +: 30]  :
			               PMP_GRAIN > 1    ? ~(~30'h0 << (PMP_GRAIN - 1))      : 30'h0;
		end
	end else if (cfg_wen) begin
		for (i = 0; i < PMP_REGIONS; i = i + 1) begin
			if (!PMP_HARDWIRED[i]) begin
				if (cfg_addr == PMPCFG0 + i / 4 && !pmpcfg_l[i]) begin
					pmpcfg_l[i] <= cfg_wdata[i % 4 * 8 + 7];
					pmpcfg_r[i] <= cfg_wdata[i % 4 * 8 + 2];
					pmpcfg_w[i] <= cfg_wdata[i % 4 * 8 + 1];
					pmpcfg_x[i] <= cfg_wdata[i % 4 * 8 + 0];
					// Unsupported A values are mapped to OFF (it's a WARL field).
					pmpcfg_a[i] <=
						cfg_wdata[i % 4 * 8 + 3 +: 2] == PMP_A_TOR ? PMP_A_OFF :
						cfg_wdata[i % 4 * 8 + 3 +: 2] == PMP_A_NA4 && PMP_GRAIN > 0 ? PMP_A_OFF :
						cfg_wdata[i % 4 * 8 + 3 +: 2];
				end
				if (cfg_addr == PMPADDR0 + i && !pmpcfg_l[i]) begin
					if (PMP_GRAIN > 1) begin
						pmpaddr[i] <= cfg_wdata[W_ADDR-3:0] | ~(~30'h0 << (PMP_GRAIN - 1));
					end else begin
						pmpaddr[i] <= cfg_wdata[W_ADDR-3:0];
					end
				end

			end
		end
	end
end

always @ (*) begin: cfg_read
	integer i;
	cfg_rdata = {W_DATA{1'b0}};
	for (i = 0; i < PMP_REGIONS; i = i + 1) begin
		if (cfg_addr == PMPCFG0 + i / 4) begin
			cfg_rdata[i % 4 * 8 +: 8] = {
				pmpcfg_l[i],
				2'b00,
				pmpcfg_a[i],
				pmpcfg_r[i],
				pmpcfg_w[i],
				pmpcfg_x[i]
			};
		end else if (cfg_addr == PMPADDR0 + i) begin
			// If G > 1, the G-1 LSBs of pmpaddr_i are read-only-zero when
			// region is OFF, and read-only-one when region is NAPOT.
			if (PMP_GRAIN > 1 && !PMP_HARDWIRED[i]) begin
				cfg_rdata[W_ADDR-3:0] = pmpaddr[i] & ~(
					{30{pmpcfg_a[i] != PMP_A_OFF}} & ~(~30'h0 << (PMP_GRAIN - 1))
				);
			end else begin
				cfg_rdata[W_ADDR-3:0] = pmpaddr[i];
			end
		end
	end
end

// ----------------------------------------------------------------------------
// Address query lookup

// Decode PMPCFGx.A and PMPADDRx into a 32-bit address mask and address value
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
		if (pmpcfg_a[i] == PMP_A_NA4) begin
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

// For load/stores we assume any non-naturally-aligned transfers trigger a
// misaligned load/store/AMO exception, so we only need to decode the PMP
// attribute for the first byte of the access. Note the spec gives us freedom
// to report *either* a load/store/AMO access fault (mcause = 5, 7) or a
// load/store/AMO alignment fault (mcause = 4, 6), in the case that both
// happen, and we choose alignment fault in this case.

reg d_match;
reg d_l;
reg d_r;
reg d_w;
reg d_x; // needed because of MXR

always @ (*) begin: check_d_match
	integer i;
	d_match = 1'b0;
	d_l = 1'b0;
	d_r = 1'b0;
	d_w = 1'b0;
	d_x = 1'b0;
	// Lowest-numbered match wins, so work down from the top. This should be
	// inferred as a priority mux structure (cascade mux).
	for (i = PMP_REGIONS - 1; i >= 0; i = i - 1) begin
		if (|pmpcfg_a[i] && (d_addr & match_mask[i]) == match_addr[i]) begin
			d_match = 1'b1;
			d_l = pmpcfg_l[i];
			d_r = pmpcfg_r[i];
			d_w = pmpcfg_w[i];
			d_x = pmpcfg_x[i];
		end
	end
end

// Instruction fetches are more complex. For IALIGN=4 (i.e. non-RVC)
// implementations, we can assume that instruction fetches are naturally
// aligned, because any control flow transfer which would cause a
// non-naturally-aligned fetch will have trapped. Therefore we never have to
// worry about priority of instruction alignment fault vs instruction access
// fault exceptions. However, when IALIGN=2, there are some cases to
// consider:
//
// - An instruction which straddles a protection boundary must fail the PMP
//   check as it has a partial match
//
// - A jump to an illegal instruction starting at the last halfword of a PMP
//   region: in this case the size of the instruction is unknown, so it is
//   ambiguous whether this should be an access fault (if we treat the
//   illegal instruction as 32-bit) or an illegal instruction fault (if we
//   treat the instruction as 16-bit). To disambiguate, we decode the two
//   LSBs of the instruction to determine its size, as though it were valid.
//
// To detect partial matches of instruction fetches, we take the simple but
// possibly suboptimal choice of querying both PC and PC + 2. On the topic of
// partial matches, note the spec wording, as it's tricky:
//
// "The lowest-numbered PMP entry that matches any byte of an access
//  determines whether that access succeeds or fails. The matching PMP entry
//  must match all bytes of an access, or the access fails, irrespective of
//  the L, R, W, and X bits."
//
// This means that a partial match *is* permitted, if and only if you also
// completely match a lower-numbered region. We don't accumulate the partial
// match across all regions.

reg i_match;
reg i_partial_match;
reg i_l;
reg i_x;

wire [W_ADDR-1:0] i_addr_hw1 = i_addr + 2'h2;

always @ (*) begin: check_i_match
	integer i;
	reg match_hw0, match_hw1;
	i_match = 1'b0;
	i_partial_match = 1'b0;
	i_l = 1'b0;
	i_x = 1'b0;
	for (i = PMP_REGIONS - 1; i >= 0; i = i - 1) begin
		match_hw0 = |pmpcfg_a[i] && (i_addr     & match_mask[i]) == match_addr[i];
		match_hw1 = |pmpcfg_a[i] && (i_addr_hw1 & match_mask[i]) == match_addr[i];
		if (match_hw0 || match_hw1) begin
			i_match = 1'b1;
			i_partial_match = (match_hw0 ^ match_hw1) && i_instr_is_32bit;
			i_l = pmpcfg_l[i];
			i_x = pmpcfg_x[i];
		end
	end
end

// ----------------------------------------------------------------------------
// Access rules

// M-mode gets to ignore protections, unless the lock bit is set.

assign d_kill = !(d_m_mode && !d_l) && (
	(!d_write && !(d_r || (d_x && mstatus_mxr))) ||
	( d_write && !d_w)
);

// Straddling a protection boundary is always an error.

assign i_kill = i_partial_match || (
	!(i_m_mode && !i_l) && !i_x
);

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
