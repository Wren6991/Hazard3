/**********************************************************************
 * DO WHAT THE FUCK YOU WANT TO AND DON'T BLAME US PUBLIC LICENSE     *
 *                    Version 3, April 2008                           *
 *                                                                    *
 * Copyright (C) 2021 Luke Wren                                       *
 *                                                                    *
 * Everyone is permitted to copy and distribute verbatim or modified  *
 * copies of this license document and accompanying software, and     *
 * changing either is allowed.                                        *
 *                                                                    *
 *   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION  *
 *                                                                    *
 * 0. You just DO WHAT THE FUCK YOU WANT TO.                          *
 * 1. We're NOT RESPONSIBLE WHEN IT DOESN'T FUCKING WORK.             *
 *                                                                    *
 *********************************************************************/

// Nothing to see here, just a sync FIFO

module hazard3_uart_dtm_fifo #(
	parameter WIDTH = 8,
	parameter LOG_DEPTH = 2
) (
	input  wire             clk,
	input  wire             rst_n,

	input  wire [WIDTH-1:0] wdata,
	input  wire             wvld,
	output wire             wrdy,

	output wire [WIDTH-1:0] rdata,
	output wire             rvld,
	input  wire             rrdy
);

reg [WIDTH-1:0] fifo_mem [0:(1 << LOG_DEPTH) - 1];

reg [LOG_DEPTH:0] wptr;
reg [LOG_DEPTH:0] rptr;

assign wrdy = (rptr ^ {1'b1, {LOG_DEPTH{1'b0}}}) != wptr;
assign rvld = rptr != wptr;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		wptr <= {LOG_DEPTH+1{1'b0}};
		rptr <= {LOG_DEPTH+1{1'b0}};
	end else begin
		if (wvld && wrdy) begin
			fifo_mem[wptr[LOG_DEPTH-1:0]] <= wdata;
			wptr <= wptr + 1'b1;
		end
		if (rvld && rrdy) begin
			rptr <= rptr + 1'b1;
		end
	end
end

assign rdata = fifo_mem[rptr[LOG_DEPTH-1:0]];

endmodule
