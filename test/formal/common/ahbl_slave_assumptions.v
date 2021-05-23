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

// Assumptions to constrain an AHB-Lite slave to be relatively well-behaved

module ahbl_slave_assumptions #(
	parameter W_ADDR = 32,
	parameter W_DATA = 32,
	parameter MAX_BUS_STALL = -1 // set >= 0 to constrain max stall length
) (
	input wire                clk,
	input wire                rst_n,

	// Downstream AHB-Lite master port
	input  wire               dst_hready_resp,
	output wire               dst_hready,
	input  wire               dst_hresp,
	output wire [W_ADDR-1:0]  dst_haddr,
	output wire               dst_hwrite,
	output wire [1:0]         dst_htrans,
	output wire [2:0]         dst_hsize,
	output wire [2:0]         dst_hburst,
	output wire [3:0]         dst_hprot,
	output wire               dst_hmastlock,
	output wire [W_DATA-1:0]  dst_hwdata,
	input  wire [W_DATA-1:0]  dst_hrdata
);

reg              dst_active_dph;
reg              dst_write_dph;
reg [W_ADDR-1:0] dst_addr_dph;
reg [2:0]        dst_size_dph;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		dst_active_dph <= 1'b0;
		dst_write_dph <= 1'b0;
		dst_addr_dph <= {W_ADDR{1'b0}};
		dst_size_dph <= 3'h0;
	end else if (dst_hready) begin
		dst_active_dph <= dst_htrans[1];
		dst_write_dph <= dst_hwrite;
		dst_addr_dph <= dst_haddr;
		dst_size_dph <= dst_hsize;
	end
end

// Assumptions for all downstream responses
always @ (posedge clk) if (rst_n) begin: dst_ahbl_resp_properties
	// IDLE->OKAY
	if (!dst_active_dph) begin
		assume(dst_hready_resp);
		assume(!dst_hresp);
	end
	// Correct two-phase error response.
	if (dst_hresp && dst_hready)
		assume($past(dst_hresp && !dst_hready));
	if (dst_hresp && !dst_hready)
		assume($past(!(dst_hresp && !dst_hready)));
	if ($past(dst_hresp && !dst_hready))
		assume(dst_hresp);
end


generate
if (MAX_BUS_STALL >= 0) begin: constrain_max_bus_stall

reg [7:0] bus_stall_ctr;
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		bus_stall_ctr <= 8'h0;
	end else begin
		if (dst_hready)
			bus_stall_ctr <= 8'h0;
		else
			bus_stall_ctr <= bus_stall_ctr + ~&bus_stall_ctr;
		assume(bus_stall_ctr <= MAX_BUS_STALL);
	end
end

end
endgenerate

endmodule
