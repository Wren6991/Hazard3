/******************************************************************************
 *     DO WHAT THE FUCK YOU WANT TO AND DON'T BLAME US PUBLIC LICENSE         *
 *                        Version 3, April 2008                               *
 *                                                                            *
 *     Copyright (C) 2021 Luke Wren                                           *
 *                                                                            *
 *     Everyone is permitted to copy and distribute verbatim or modified      *
 *     copies of this license document and accompanying software, and         *
 *     changing either is allowed.                                            *
 *                                                                            *
 *       TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION      *
 *                                                                            *
 *     0. You just DO WHAT THE FUCK YOU WANT TO.                              *
 *     1. We're NOT RESPONSIBLE WHEN IT DOESN'T FUCKING WORK.                 *
 *                                                                            *
 *****************************************************************************/

// Assert that an AHB-Lite master is relatively well-behaved

module ahbl_master_assertions #(
	parameter W_ADDR = 32,
	parameter W_DATA = 32
) (
	input wire               clk,
	input wire               rst_n,

	input wire               src_hready,
	input wire               src_hresp,
	input wire               src_hexokay,
	input wire [W_ADDR-1:0]  src_haddr,
	input wire               src_hwrite,
	input wire [1:0]         src_htrans,
	input wire [2:0]         src_hsize,
	input wire [2:0]         src_hburst,
	input wire [3:0]         src_hprot,
	input wire               src_hmastlock,
	input wire               src_hexcl,
	input wire [W_DATA-1:0]  src_hwdata,
	input wire [W_DATA-1:0]  src_hrdata
);

// Data-phase monitoring 
reg              src_active_dph;
reg              src_write_dph;
reg [W_ADDR-1:0] src_addr_dph;
reg [2:0]        src_size_dph;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		src_active_dph <= 1'b0;
		src_write_dph <= 1'b0;
		src_addr_dph <= {W_ADDR{1'b0}};
		src_size_dph <= 3'h0;
	end else if (src_hready) begin
		src_active_dph <= src_htrans[1];
		src_write_dph <= src_hwrite;
		src_addr_dph <= src_haddr;
		src_size_dph <= src_hsize;
	end
end

// Assertions for all downstream requests
always @ (posedge clk) if (rst_n) begin: dst_ahbl_req_properties

	// Address phase properties (inactive when request is IDLE):
	if (src_htrans != 2'b00) begin
		// Transfer must be naturally aligned
		assert(!(src_haddr & ~({W_ADDR{1'b1}} << src_hsize)));
		// HSIZE appropriate for bus width
		assert(8 << src_hsize <= W_DATA);
		// No deassertion or change of active request
		if ($past(src_htrans[1] && !src_hready)) begin
			assert($stable({
				src_htrans,
				src_hwrite,
				src_haddr,
				src_hsize,
				src_hburst,
				src_hprot,
				src_hmastlock
			}));
		end
		// SEQ only issued following an NSEQ or SEQ, never an IDLE
		if (src_htrans == 2'b11)
			assert(src_active_dph);
		// SEQ transfer addresses must be sequential with previous transfer (note
		// this only supports INCRx bursts)
		if (src_htrans == 2'b11)
			assert(src_haddr == src_addr_dph + W_DATA / 8);
	end

	// Data phase properties:
	if (src_active_dph) begin
		// Write data stable during write data phase
		if (src_write_dph && !$past(src_hready))
			assert($stable(src_hwdata));
	end
end

endmodule
