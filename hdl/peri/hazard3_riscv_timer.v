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

// Implementation of standard RISC-V timer (mtime/mtimeh mtimecmp/mtimecmph)
// accessed over 32-bit data bus. Ticks on both edges of tick_nrz, which is
// provided by some external timebase, and is assumed to be asynchronous to
// clk. Nothing fancy, just a simple implementation of the spec.

module hazard3_riscv_timer (
	input  wire               clk,
	input  wire               rst_n,

	input  wire               psel,
	input  wire               penable,
	input  wire               pwrite,
	input  wire [7:0]         paddr,
	input  wire [31:0]        pwdata,
	output reg  [31:0]        prdata,
	output wire               pready,
	output wire               pslverr,

	input  wire               dbg_halt,
	input  wire               tick_nrz,

	output reg                timer_irq
);

wire bus_write = pwrite && psel && penable && pready;

localparam W_ADDR = 8;
localparam W_DATA = 32;

localparam ADDR_CTRL      = 8'h00;
localparam ADDR_MTIME     = 8'h08;
localparam ADDR_MTIMEH    = 8'h0c;
localparam ADDR_MTIMECMP  = 8'h10;
localparam ADDR_MTIMECMPH = 8'h14;

wire tick_nrz_sync;

hazard3_sync_1bit tick_sync_u (
	.clk    (clk),
	.rst_n  (rst_n),
	.i      (tick_nrz),
	.o      (tick_nrz_sync)
);

reg tick_nrz_prev;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		tick_nrz_prev <= 1'b0;
	else
		tick_nrz_prev <= tick_nrz_sync;

reg ctrl_en;
always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		ctrl_en <= 1'b1;
	else if (bus_write && paddr == ADDR_CTRL)
		ctrl_en <= pwdata[0];

wire tick = tick_nrz_prev != tick_nrz_sync;
wire tick_and_increment = ctrl_en && !dbg_halt && tick;

// The 64-bit TIME and TIMECMP registers are processed serially, over the
// course of 64 cycles.

reg [5:0] serial_ctr;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		serial_ctr <= 6'h00;
	end else if (tick) begin
		serial_ctr <= serial_ctr + 1'b1;
	end
end

reg [63:0] mtime;
reg        mtime_carry;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mtime <= 64'h0;
		mtime_carry <= 1'b1;
	end else begin
		if (tick) begin
			if (tick_and_increment) begin
				// Serially increment mtime
				{mtime_carry, mtime[63]} <= mtime_carry + mtime[0];
				mtime[62:0] <= mtime[63:1];
			end else begin
				// Still keep rotating the register, so writes can take place,
				// and so we can continuously compare with mtimecmp.
				mtime <= {mtime[0], mtime[63:1]};
			end
			// Preload carry for increment
			if (serial_ctr == 6'h3f)
				mtime_carry <= 1'b1;
		end
		// Only the lower half is written; pready is driven so that the write
		// occurs at the correct time and hence bit-alignment.
		if (bus_write && (paddr == ADDR_MTIME || paddr == ADDR_MTIMEH))
			mtime[31:0] <= pwdata;
	end
end

reg [63:0] mtimecmp;
reg        mtimecmp_borrow;

wire mtimecmp_borrow_next = (!mtimecmp[0] && (mtime[0] || mtimecmp_borrow)) || (mtime[0] && mtimecmp_borrow);

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mtimecmp <= 64'h0;
		mtimecmp_borrow <= 1'b0;
		timer_irq <= 1'b0;
	end else begin
		// Serially subtract mtime from mtimecmp. If there is no borrow from
		// bit 63 (i.e. if mtimecmp was greater or equal) then assert IRQ.
		if (tick) begin
			mtimecmp_borrow <= mtimecmp_borrow_next;
			mtimecmp <= {mtimecmp[0], mtimecmp[63:1]};
			if (serial_ctr == 6'h3f) begin
				mtimecmp_borrow <= 1'b0;
				timer_irq <= !mtimecmp_borrow_next;
			end
		end
		if (bus_write && (paddr == ADDR_MTIMECMP || paddr == ADDR_MTIMECMPH))
			mtimecmp[31:0] <= pwdata;
	end
end

always @ (*) begin
	case (paddr)
	ADDR_CTRL:      begin  prdata = {{W_DATA-1{1'b0}}, ctrl_en}; pready = 1'b1;                end
	ADDR_MTIME:     begin  prdata = mtime[31:0];                 pready = serial_ctr == 6'h00; end
	ADDR_MTIMEH:    begin  prdata = mtime[31:0];                 pready = serial_ctr == 6'h20; end
	ADDR_MTIMECMP:  begin  prdata = mtimecmp[31:0];              pready = serial_ctr == 6'h00; end
	ADDR_MTIMECMPH: begin  prdata = mtimecmp[63:32];             pready = serial_ctr == 6'h20; end
	default:        begin  prdata = {W_DATA{1'b0}};              pready = 1'b1;                end
	endcase
end

endmodule
