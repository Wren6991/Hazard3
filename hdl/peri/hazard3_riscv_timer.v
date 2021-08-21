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
// accessed over 32-bit data bus.
//
// This is written for minimal area on FPGA -- in particular, it uses 64-bit
// serial increment and compare -- so is not the best solution for less
// resource-constrained platforms, because it can't count faster than once
// per 64 cycles, and bus accesses can be delayed for up to 63 timer ticks
// whilst the serial counter rotates to the correct bus alignment. The serial
// operations are also quite energy-intensive.
//
// Tie tick high for a 64-cycle timebase. tick must be free-running, i.e. must
// not be held low indefinitely, because this would also halt the serial
// mtimecmp comparison. To pause the timer due to an external event, assert
// dbg_halt high. To pause from software, write 0 to CTRL.EN.

module hazard3_riscv_timer (
	input  wire               clk,
	input  wire               rst_n,

	input  wire               psel,
	input  wire               penable,
	input  wire               pwrite,
	input  wire [7:0]         paddr,
	input  wire [31:0]        pwdata,
	output reg  [31:0]        prdata,
	output reg                pready,
	output wire               pslverr,

	input  wire               dbg_halt,

	input  wire               tick,

	output reg                timer_irq
);

localparam W_ADDR = 8;
localparam W_DATA = 32;

localparam ADDR_CTRL      = 8'h00;
localparam ADDR_MTIME     = 8'h08;
localparam ADDR_MTIMEH    = 8'h0c;
localparam ADDR_MTIMECMP  = 8'h10;
localparam ADDR_MTIMECMPH = 8'h14;


reg ctrl_en;
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		ctrl_en <= 1'b1;
	end else if (bus_write && paddr == ADDR_CTRL) begin
		ctrl_en <= pwdata[0];
	end
end

wire bus_write = pwrite && psel && penable && pready;
wire tick_and_increment = ctrl_en && !dbg_halt && tick;

// ----------------------------------------------------------------------------
// mtime and serial increment

// Increment takes place over the course of 64 ticks. The mtime register is
// constantly rotating to bring a new serial bit into position 0.

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

// ----------------------------------------------------------------------------
// mtimecmp and serial comparison

// The timer IRQ is only updated every 64 ticks, when we finish a new
// comparison. This is permitted by the RISC-V privileged spec: before
// returning, the IRQ handler should poll mtip until it sees the IRQ
// deassert.

reg [63:0] mtimecmp;
reg        mtimecmp_borrow;

wire mtimecmp_borrow_next =
	(!mtime[0] && (mtimecmp[0] || mtimecmp_borrow))
	||            (mtimecmp[0] && mtimecmp_borrow);

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mtimecmp <= 64'h0;
		mtimecmp_borrow <= 1'b0;
		timer_irq <= 1'b0;
	end else begin
		// Serially subtract mtimecmp from mtime. If there is no borrow from
		// bit 63 (i.e. if mtime was greater or equal) then assert IRQ.
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

// ----------------------------------------------------------------------------
// Bus read mux

// Only the lower half of each 64-bit counter register is exposed to the bus,
// using the serial counter to make sure the correct bits are aligned with
// the bus window at the point the bus access finishes. Note pready is only
// valid during the access phase (& is ignored during setup phase).

always @ (*) case (paddr)
	ADDR_CTRL:      begin prdata = {{W_DATA-1{1'b0}}, ctrl_en}; pready = 1'b1;                end
	ADDR_MTIME:     begin prdata = mtime[31:0];                 pready = serial_ctr == 6'h00; end
	ADDR_MTIMEH:    begin prdata = mtime[31:0];                 pready = serial_ctr == 6'h20; end
	ADDR_MTIMECMP:  begin prdata = mtimecmp[31:0];              pready = serial_ctr == 6'h00; end
	ADDR_MTIMECMPH: begin prdata = mtimecmp[31:0];              pready = serial_ctr == 6'h20; end
	default:        begin prdata = {W_DATA{1'b0}};              pready = 1'b1;                end
endcase

endmodule
