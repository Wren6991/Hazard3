/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// RISC-V Debug Module for Hazard3. Supports up to 32 cores (1 hart per core).

`default_nettype none

module hazard3_dm #(
	// Where there are multiple harts per DM, the least-indexed hart is the
	// least-significant on each concatenated hart access bus.
	parameter N_HARTS      = 1,
	// Where there are multiple DMs, the address of each DM should be a
	// multiple of 'h200, so that bits[8:2] decode correctly.
	parameter NEXT_DM_ADDR = 32'h0000_0000,
	// Implement support for system bus access:
	parameter HAVE_SBA     = 0,

	// Do not modify:
	parameter XLEN         = 32,                               // Do not modify
	parameter W_HARTSEL    = N_HARTS > 1 ? $clog2(N_HARTS) : 1 // Do not modify
) (
	// DM is assumed to be in same clock domain as core; clock crossing
	// (if any) is inside DTM, or between DTM and DM.
	input  wire                      clk,
	input  wire                      rst_n,

	// APB access from Debug Transport Module
	input  wire                      dmi_psel,
	input  wire                      dmi_penable,
	input  wire                      dmi_pwrite,
	input  wire [8:0]                dmi_paddr,
	input  wire [31:0]               dmi_pwdata,
	output reg  [31:0]               dmi_prdata,
	output wire                      dmi_pready,
	output wire                      dmi_pslverr,

	// Reset request/acknowledge. "req" is a pulse >= 1 cycle wide. "done" is
	// level-sensitive, goes high once component is out of reset.
	//
	// The "sys" reset (ndmreset) is conventionally everything apart from DM +
	// DTM, but, as per section 3.2 in 0.13.2 debug spec: "Exactly what is
	// affected by this reset is implementation dependent, as long as it is
	// possible to debug programs from the first instruction executed." So
	// this could simply be an all-hart reset.
	output wire                      sys_reset_req,
	input  wire                      sys_reset_done,
	output wire [N_HARTS-1:0]        hart_reset_req,
	input  wire [N_HARTS-1:0]        hart_reset_done,

	// Hart run/halt control
	output wire [N_HARTS-1:0]        hart_req_halt,
	output wire [N_HARTS-1:0]        hart_req_halt_on_reset,
	output wire [N_HARTS-1:0]        hart_req_resume,
	input  wire [N_HARTS-1:0]        hart_halted,
	input  wire [N_HARTS-1:0]        hart_running,

	// Hart access to data0 CSR (assumed to be core-internal but per-hart)
	output wire [N_HARTS*XLEN-1:0]   hart_data0_rdata,
	input  wire [N_HARTS*XLEN-1:0]   hart_data0_wdata,
	input  wire [N_HARTS-1:0]        hart_data0_wen,

	// Hart instruction injection
	output wire [N_HARTS*XLEN-1:0]   hart_instr_data,
	output wire [N_HARTS-1:0]        hart_instr_data_vld,
	input  wire [N_HARTS-1:0]        hart_instr_data_rdy,
	input  wire [N_HARTS-1:0]        hart_instr_caught_exception,
	input  wire [N_HARTS-1:0]        hart_instr_caught_ebreak,

	// System bus access (optional) -- can be hooked up to the standalone AHB
	// shim (hazard3_sbus_to_ahb.v) or the SBA input port on the processor
	// wrapper, which muxes SBA into the processor's load/store bus access
	// port. SBA does not increase debugger bus throughput, but supports
	// minimally intrusive debug bus access for e.g. Segger RTT.
	output wire [31:0]               sbus_addr,
	output wire                      sbus_write,
	output wire [1:0]                sbus_size,
	output wire                      sbus_vld,
	input  wire                      sbus_rdy,
	input  wire                      sbus_err,
	output wire [31:0]               sbus_wdata,
	input  wire [31:0]               sbus_rdata
);

wire dmi_write = dmi_psel && dmi_penable && dmi_pready && dmi_pwrite;
wire dmi_read = dmi_psel && dmi_penable && dmi_pready && !dmi_pwrite;
assign dmi_pready = 1'b1;
assign dmi_pslverr = 1'b0;

// Program buffer is fixed at 2 words plus impebreak. The main thing we care
// about is support for efficient memory block transfers using abstractauto;
// in this case 2 words + impebreak is sufficient for RV32I, and 1 word +
// impebreak is sufficient for RV32IC.
localparam PROGBUF_SIZE = 2;

// ----------------------------------------------------------------------------
// Address constants

localparam ADDR_DATA0        = 7'h04;
// Other data registers not present.
localparam ADDR_DMCONTROL    = 7'h10;
localparam ADDR_DMSTATUS     = 7'h11;
localparam ADDR_HARTINFO     = 7'h12;
localparam ADDR_HALTSUM1     = 7'h13;
localparam ADDR_HALTSUM0     = 7'h40;
// No HALTSUM2+ registers (we don't support >32 harts anyway)
localparam ADDR_HAWINDOWSEL  = 7'h14;
localparam ADDR_HAWINDOW     = 7'h15;
localparam ADDR_ABSTRACTCS   = 7'h16;
localparam ADDR_COMMAND      = 7'h17;
localparam ADDR_ABSTRACTAUTO = 7'h18;
localparam ADDR_CONFSTRPTR0  = 7'h19;
localparam ADDR_CONFSTRPTR1  = 7'h1a;
localparam ADDR_CONFSTRPTR2  = 7'h1b;
localparam ADDR_CONFSTRPTR3  = 7'h1c;
localparam ADDR_NEXTDM       = 7'h1d;
localparam ADDR_PROGBUF0     = 7'h20;
localparam ADDR_PROGBUF1     = 7'h21;
// No authentication
localparam ADDR_SBCS         = 7'h38;
localparam ADDR_SBADDRESS0   = 7'h39;
localparam ADDR_SBDATA0      = 7'h3c;

// APB is byte-addressed, DM registers are word-addressed.
wire [6:0] dmi_regaddr = dmi_paddr[8:2];

// ----------------------------------------------------------------------------
// Hart selection

reg dmactive;

// Some fiddliness to make sure we get a single-wide zero-valued signal when
// N_HARTS == 1 (so we can use this for indexing of per-hart signals)
reg  [W_HARTSEL-1:0] hartsel;
wire [W_HARTSEL-1:0] hartsel_next;

generate
if (N_HARTS > 1) begin: has_hartsel

	// Only the lower 10 bits of hartsel are supported
	assign hartsel_next = dmi_write && dmi_regaddr == ADDR_DMCONTROL ?
		dmi_pwdata[16 +: W_HARTSEL] : hartsel;

end else begin: has_no_hartsel

	assign hartsel_next = 1'b0;

end
endgenerate

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		hartsel <= {W_HARTSEL{1'b0}};
	end else if (!dmactive) begin
		hartsel <= {W_HARTSEL{1'b0}};
	end else begin
		hartsel <= hartsel_next;
	end
end

// Also implement the hart array mask if there is more than one hart.
reg  [N_HARTS-1:0] hart_array_mask;
reg                hasel;
wire [N_HARTS-1:0] hart_array_mask_next;
wire               hasel_next;

generate
if (N_HARTS > 1) begin: has_array_mask

	assign hart_array_mask_next = dmi_write && dmi_regaddr == ADDR_HAWINDOW ?
		dmi_pwdata[N_HARTS-1:0] : hart_array_mask;
	assign hasel_next = dmi_write && dmi_regaddr == ADDR_DMCONTROL ?
		dmi_pwdata[26] : hasel;

end else begin: has_no_array_mask

	assign hart_array_mask_next = 1'b0;
	assign hasel_next = 1'b0;

end
endgenerate

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		hart_array_mask <= {N_HARTS{1'b0}};
		hasel <= 1'b0;
	end else if (!dmactive) begin
		hart_array_mask <= {N_HARTS{1'b0}};
		hasel <= 1'b0;
	end else begin
		hart_array_mask <= hart_array_mask_next;
		hasel <= hasel_next;
	end
end

// ----------------------------------------------------------------------------
// Run/halt/reset control

// Normal read/write fields for dmcontrol (note some of these are per-hart
// fields that get rotated into dmcontrol based on the current/next hartsel).
reg  [N_HARTS-1:0] dmcontrol_haltreq;
reg  [N_HARTS-1:0] dmcontrol_hartreset;
reg  [N_HARTS-1:0] dmcontrol_resethaltreq;
reg                dmcontrol_ndmreset;

wire [N_HARTS-1:0] dmcontrol_op_mask;

generate
if (N_HARTS > 1) begin: dmcontrol_multiple_harts

	// Selection is the hart selected by hartsel, *plus* the hart array mask
	// if hasel is set. Note we don't need to use the "next" version of
	// hart_array_mask since it can't change simultaneously with dmcontrol.
	assign dmcontrol_op_mask =
		(hartsel_next >= N_HARTS ? {N_HARTS{1'b0}} : {{N_HARTS-1{1'b0}}, 1'b1} << hartsel_next)
		| ({N_HARTS{hasel_next}} & hart_array_mask);

end else begin: dmcontrol_single_hart

	assign dmcontrol_op_mask = 1'b1;

end
endgenerate

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		dmactive <= 1'b0;
		dmcontrol_ndmreset <= 1'b0;
		dmcontrol_haltreq <= {N_HARTS{1'b0}};
		dmcontrol_hartreset <= {N_HARTS{1'b0}};
		dmcontrol_resethaltreq <= {N_HARTS{1'b0}};
	end else if (!dmactive) begin
		// Only dmactive is writable when !dmactive
		if (dmi_write && dmi_regaddr == ADDR_DMCONTROL)
			dmactive <= dmi_pwdata[0];
		dmcontrol_ndmreset <= 1'b0;
		dmcontrol_haltreq <= {N_HARTS{1'b0}};
		dmcontrol_hartreset <= {N_HARTS{1'b0}};
		dmcontrol_resethaltreq <= {N_HARTS{1'b0}};
	end else if (dmi_write && dmi_regaddr == ADDR_DMCONTROL) begin
		dmactive <= dmi_pwdata[0];
		dmcontrol_ndmreset <= dmi_pwdata[1];

		dmcontrol_haltreq <= (dmcontrol_haltreq & ~dmcontrol_op_mask) |
			({N_HARTS{dmi_pwdata[31]}} & dmcontrol_op_mask);

		dmcontrol_hartreset <= (dmcontrol_hartreset & ~dmcontrol_op_mask) |
			({N_HARTS{dmi_pwdata[29]}} & dmcontrol_op_mask);

		dmcontrol_resethaltreq <= (dmcontrol_resethaltreq
			& ~({N_HARTS{dmi_pwdata[2]}} & dmcontrol_op_mask))
			|  ({N_HARTS{dmi_pwdata[3]}} & dmcontrol_op_mask);
	end
end

assign sys_reset_req = dmcontrol_ndmreset;
assign hart_reset_req = dmcontrol_hartreset;
assign hart_req_halt = dmcontrol_haltreq;
assign hart_req_halt_on_reset = dmcontrol_resethaltreq;

reg  [N_HARTS-1:0] hart_reset_done_prev;
reg  [N_HARTS-1:0] dmstatus_havereset;
wire [N_HARTS-1:0] hart_available = hart_reset_done & {N_HARTS{sys_reset_done}};

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		hart_reset_done_prev <= {N_HARTS{1'b0}};
	end else begin
		hart_reset_done_prev <= hart_reset_done;
	end
end

wire dmcontrol_ackhavereset = dmi_write && dmi_regaddr == ADDR_DMCONTROL && dmi_pwdata[28];

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		dmstatus_havereset <= {N_HARTS{1'b0}};
	end else if (!dmactive) begin
		dmstatus_havereset <= {N_HARTS{1'b0}};
	end else begin
		dmstatus_havereset <= (dmstatus_havereset | (hart_reset_done & ~hart_reset_done_prev))
			& ~({N_HARTS{dmcontrol_ackhavereset}} & dmcontrol_op_mask);
	end
end

reg [N_HARTS-1:0] dmstatus_resumeack;
reg [N_HARTS-1:0] dmcontrol_resumereq_sticky;

// Note: we are required to ignore resumereq when haltreq is also set, as per
// spec (odd since the host is forbidden from writing both at once anyway).
// The wording is odd, it refers only to `haltreq` which is specifically the
// write-only `dmcontrol` field, not the underlying halt request state bits.
wire dmcontrol_resumereq = dmi_write && dmi_regaddr == ADDR_DMCONTROL &&
	dmi_pwdata[30] && !dmi_pwdata[31];

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		dmstatus_resumeack <= {N_HARTS{1'b0}};
		dmcontrol_resumereq_sticky <= {N_HARTS{1'b0}};
	end else if (!dmactive) begin
		dmstatus_resumeack <= {N_HARTS{1'b0}};
		dmcontrol_resumereq_sticky <= {N_HARTS{1'b0}};
	end else begin
		dmstatus_resumeack <= (dmstatus_resumeack
			| (dmcontrol_resumereq_sticky & hart_running & hart_available))
			& ~({N_HARTS{dmcontrol_resumereq}} & dmcontrol_op_mask);

		dmcontrol_resumereq_sticky <= (dmcontrol_resumereq_sticky
			& ~(hart_running & hart_available))
			| ({N_HARTS{dmcontrol_resumereq}} & dmcontrol_op_mask);
	end
end

assign hart_req_resume = dmcontrol_resumereq_sticky;

// ----------------------------------------------------------------------------
// System bus access

reg [31:0] sbaddress;
reg [31:0] sbdata;

// Update logic for address/data registers:

reg        sbbusy;
reg        sbautoincrement;
reg [2:0]  sbaccess; // Size of the transfer

wire sbdata_write_blocked;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		sbaddress <= {32{1'b0}};
		sbdata <= {32{1'b0}};
	end else if (!dmactive) begin
		sbaddress <= {32{1'b0}};
		sbdata <= {32{1'b0}};
	end else if (HAVE_SBA) begin
		if (dmi_write && dmi_regaddr == ADDR_SBDATA0 && !sbdata_write_blocked) begin
			// Note sbbusyerror and sberror block writes to sbdata0, as the
			// write is required to have no side effects when they are set.
			sbdata <= dmi_pwdata;
		end else if (sbus_vld && sbus_rdy && !sbus_write && !sbus_err) begin
			// Make sure the lower byte lanes see appropriately shifted data as
			// long as the transfer is naturally aligned
			sbdata <= sbaddress[1:0] == 2'b01 ? {sbus_rdata[31:8],  sbus_rdata[15:8]}  :
			          sbaddress[1:0] == 2'b10 ? {sbus_rdata[31:16], sbus_rdata[31:16]} :
			          sbaddress[1:0] == 2'b11 ? {sbus_rdata[31:8],  sbus_rdata[31:24]} : sbus_rdata;
		end
		if (dmi_write && dmi_regaddr == ADDR_SBADDRESS0 && !sbbusy) begin
			// Note sbaddress can't be written when busy, but
			// sberror/sbbusyerror do not prevent writes.
			sbaddress <= dmi_pwdata;
		end else if (sbus_vld && sbus_rdy && !sbus_err && sbautoincrement) begin
			// Note: address increments only following a successful transfer.
			// Spec 0.13.2 weirdly implies address should increment following
			// a sbdata0 read with sbautoincrement=1 and sbreadondata=0, but
			// this seems to be a typo, fixed in later versions.
			sbaddress <= sbaddress + (
				sbaccess[1:0] == 2'b00 ? 3'h1 :
				sbaccess[1:0] == 2'b01 ? 3'h2 : 3'h4
			);
		end
	end
end

// Control logic:

reg        sbbusyerror;
reg        sbreadonaddr;
reg        sbreadondata;
reg [2:0]  sberror;
reg        sb_current_is_write;

localparam SBERROR_OK       = 3'h0;
localparam SBERROR_BADADDR  = 3'h2;
localparam SBERROR_BADALIGN = 3'h3;
localparam SBERROR_BADSIZE  = 3'h4;

assign sbdata_write_blocked = sbbusy || sbbusyerror || |sberror;

// Notes on behaviour of sbbusyerror: the sbbusyerror description says:
//
//  "Set when the debugger attempts to read data while a read is in progress,
//   or when the debugger initiates a new access while one is already in
//   progress (while sbbusy is set)."
//
// However, sbaddress0 description says:
//
//  "When the system bus master is busy, writes to this register will set
//   sbbusyerror and don’t do anything else."
//
// ...not conditioned on sbreadonaddr. Likewise the sbdata0 description says:
//
//   "If the bus master is busy then accesses set sbbusyerror, and don’t do
//    anything else."
//
// ...not conditioned on sbreadondata. We are going to take the union of all
// the cases where the spec says we should raise an error:

wire sb_access_illegal_when_busy =
	dmi_regaddr == ADDR_SBDATA0 && (dmi_read || dmi_write) ||
	dmi_regaddr == ADDR_SBADDRESS0 && dmi_write;

wire sb_want_start_write = dmi_write && dmi_regaddr == ADDR_SBDATA0;

wire sb_want_start_read =
	(sbreadonaddr && dmi_write && dmi_regaddr == ADDR_SBADDRESS0) ||
	(sbreadondata && dmi_read && dmi_regaddr == ADDR_SBDATA0);

wire [1:0] sb_next_align = sbreadonaddr && dmi_write && dmi_regaddr == ADDR_SBADDRESS0 ?
	dmi_pwdata[1:0] : sbaddress[1:0];

wire sb_badalign =
	(sbaccess == 3'h1 && sb_next_align[0]) ||
	(sbaccess == 3'h2 && |sb_next_align[1:0]);

wire sb_badsize = sbaccess > 3'h2;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		sbbusy              <= 1'b0;
		sbbusyerror         <= 1'b0;
		sbreadonaddr        <= 1'b0;
		sbreadondata        <= 1'b0;
		sbaccess            <= 3'h0;
		sbautoincrement     <= 1'b0;
		sberror             <= 3'h0;
		sb_current_is_write <= 1'b0;
	end else if (!dmactive) begin
		sbbusy              <= 1'b0;
		sbbusyerror         <= 1'b0;
		sbreadonaddr        <= 1'b0;
		sbreadondata        <= 1'b0;
		sbaccess            <= 3'h0;
		sbautoincrement     <= 1'b0;
		sberror             <= 3'h0;
		sb_current_is_write <= 1'b0;
	end else if (HAVE_SBA) begin
		if (dmi_write && dmi_regaddr == ADDR_SBCS) begin
			// Assume a transfer is not in progress when written (per spec)
			sbbusyerror     <= sbbusyerror && !dmi_pwdata[22];
			sbreadonaddr    <= dmi_pwdata[20];
			sbaccess        <= dmi_pwdata[19:17];
			sbautoincrement <= dmi_pwdata[16];
			sbreadondata    <= dmi_pwdata[15];
			sberror         <= sberror & ~dmi_pwdata[14:12];
		end
		if (sbbusy) begin
			if (sb_access_illegal_when_busy) begin
				sbbusyerror <= 1'b1;
			end
			if (sbus_vld && sbus_rdy) begin
				sbbusy <= 1'b0;
				if (sbus_err) begin
					sberror <= SBERROR_BADADDR;
				end
			end
		end else if (sb_want_start_read || sb_want_start_write && ~|sberror && !sbbusyerror) begin
			if (sb_badsize) begin
				sberror <= SBERROR_BADSIZE;
			end else if (sb_badalign) begin
				sberror <= SBERROR_BADALIGN;
			end else begin
				sbbusy <= 1'b1;
				sb_current_is_write <= sb_want_start_write;
			end
		end
	end
end

assign sbus_addr  = sbaddress;
assign sbus_write = sb_current_is_write;
assign sbus_size  = sbaccess[1:0];
assign sbus_vld   = sbbusy;

// Replicate byte lanes to handle naturally-aligned cases.
assign sbus_wdata = sbaccess[1:0] == 2'b00 ? {4{sbdata[7:0]}}  :
                    sbaccess[1:0] == 2'b01 ? {2{sbdata[15:0]}} : sbdata;

// ----------------------------------------------------------------------------
// Abstract command data registers

wire abstractcs_busy;

// The same data0 register is aliased as a CSR on all harts connected to this
// DM. Cores may read data0 as a CSR when in debug mode, and may write it when:
//
// - That core is in debug mode, and...
// - We are currently executing an abstract command on that core
//
// The DM can also read/write data0 at all times.

reg [XLEN-1:0] abstract_data0;

assign hart_data0_rdata = {N_HARTS{abstract_data0}};

always @ (posedge clk or negedge rst_n) begin: update_hart_data0
	integer i;
	if (!rst_n) begin
		abstract_data0 <= {XLEN{1'b0}};
	end else if (!dmactive) begin
		abstract_data0 <= {XLEN{1'b0}};
	end else if (dmi_write && dmi_regaddr == ADDR_DATA0) begin
		abstract_data0 <= dmi_pwdata;
	end else begin
		for (i = 0; i < N_HARTS; i = i + 1) begin
			if (hartsel == i && hart_data0_wen[i] && hart_halted[i] && abstractcs_busy)
				abstract_data0 <= hart_data0_wdata[i * XLEN +: XLEN];
		end
	end
end

reg [XLEN-1:0] progbuf0;
reg [XLEN-1:0] progbuf1;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		progbuf0 <= {XLEN{1'b0}};
		progbuf1 <= {XLEN{1'b0}};
	end else if (!dmactive) begin
		progbuf0 <= {XLEN{1'b0}};
		progbuf1 <= {XLEN{1'b0}};
	end else if (dmi_write && !abstractcs_busy) begin
		if (dmi_regaddr == ADDR_PROGBUF0)
			progbuf0 <= dmi_pwdata;
		if (dmi_regaddr == ADDR_PROGBUF1)
			progbuf1 <= dmi_pwdata;
	end
end

// We only support abstractauto on data0 update (use case is bulk memory read/write)
reg       abstractauto_autoexecdata;
reg [1:0] abstractauto_autoexecprogbuf;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		abstractauto_autoexecdata <= 1'b0;
		abstractauto_autoexecprogbuf <= 2'b00;
	end else if (!dmactive) begin
		abstractauto_autoexecdata <= 1'b0;
		abstractauto_autoexecprogbuf <= 2'b00;
	end else if (dmi_write && dmi_regaddr == ADDR_ABSTRACTAUTO) begin
		abstractauto_autoexecdata <= dmi_pwdata[0];
		abstractauto_autoexecprogbuf <= dmi_pwdata[17:16];
	end
end

// ----------------------------------------------------------------------------
// Abstract command state machine

localparam W_STATE = 4;
localparam S_IDLE            = 4'd0;

localparam S_ISSUE_REGREAD   = 4'd1;
localparam S_ISSUE_REGWRITE  = 4'd2;
localparam S_ISSUE_REGEBREAK = 4'd3;
localparam S_WAIT_REGEBREAK  = 4'd4;

localparam S_ISSUE_PROGBUF0  = 4'd5;
localparam S_ISSUE_PROGBUF1  = 4'd6;
localparam S_ISSUE_IMPEBREAK = 4'd7;
localparam S_WAIT_IMPEBREAK  = 4'd8;

localparam CMDERR_OK = 3'h0;
localparam CMDERR_BUSY = 3'h1;
localparam CMDERR_UNSUPPORTED = 3'h2;
localparam CMDERR_EXCEPTION = 3'h3;
localparam CMDERR_HALTRESUME = 3'h4;

reg [2:0]         abstractcs_cmderr;
reg [W_STATE-1:0] acmd_state;

assign abstractcs_busy = acmd_state != S_IDLE;

wire start_abstract_cmd = abstractcs_cmderr == CMDERR_OK && !abstractcs_busy && (
	(dmi_write && dmi_regaddr == ADDR_COMMAND) ||
	((dmi_write || dmi_read) && abstractauto_autoexecdata && dmi_regaddr == ADDR_DATA0) ||
	((dmi_write || dmi_read) && abstractauto_autoexecprogbuf[0] && dmi_regaddr == ADDR_PROGBUF0) ||
	((dmi_write || dmi_read) && abstractauto_autoexecprogbuf[1] && dmi_regaddr == ADDR_PROGBUF1)
);

wire dmi_access_illegal_when_busy =
	(dmi_write && (
		dmi_regaddr == ADDR_ABSTRACTCS || dmi_regaddr == ADDR_COMMAND || dmi_regaddr == ADDR_ABSTRACTAUTO ||
		dmi_regaddr == ADDR_DATA0 || dmi_regaddr == ADDR_PROGBUF0 || dmi_regaddr == ADDR_PROGBUF0)) ||
	(dmi_read && (
		dmi_regaddr == ADDR_DATA0 || dmi_regaddr == ADDR_PROGBUF0 || dmi_regaddr == ADDR_PROGBUF0));

// Decode what acmd may be triggered on this cycle, and whether it is
// supported -- command source may be a registered version of most recent
// command (if abstractauto is used) or a fresh command off the bus. We don't
// register the entire write data; repeats of unsupported commands are
// detected by just registering that the last written command was
// unsupported.

wire       acmd_new = dmi_write && dmi_regaddr == ADDR_COMMAND;

wire       acmd_new_postexec    = dmi_pwdata[18];
wire       acmd_new_transfer    = dmi_pwdata[17];
wire       acmd_new_write       = dmi_pwdata[16];
wire [4:0] acmd_new_regno       = dmi_pwdata[4:0];

// Note: regno and aarsize are permitted to have otherwise-invalid values if
// the transfer flag is not set.
wire       acmd_new_unsupported =
	(dmi_pwdata[31:24] != 8'h00                    ) || // Only Access Register command supported
	(dmi_pwdata[22:20] != 3'h2 && acmd_new_transfer) || // Must be 32 bits in size
	(dmi_pwdata[19]                                ) || // aarpostincrement not supported
	(dmi_pwdata[15:12] != 4'h1 && acmd_new_transfer) || // Only core register access supported
	(dmi_pwdata[11:5]  != 7'h0 && acmd_new_transfer);   // Only GPRs supported

reg        acmd_prev_postexec;
reg        acmd_prev_transfer;
reg        acmd_prev_write;
reg  [4:0] acmd_prev_regno;
reg        acmd_prev_unsupported;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		acmd_prev_postexec <= 1'b0;
		acmd_prev_transfer <= 1'b0;
		acmd_prev_write <= 1'b0;
		acmd_prev_regno <= 5'h0;
		acmd_prev_unsupported <= 1'b1;
	end else if (!dmactive) begin
		acmd_prev_postexec <= 1'b0;
		acmd_prev_transfer <= 1'b0;
		acmd_prev_write <= 1'b0;
		acmd_prev_regno <= 5'h0;
		acmd_prev_unsupported <= 1'b1;
	end else if (start_abstract_cmd && acmd_new) begin
		acmd_prev_postexec <= acmd_new_postexec;
		acmd_prev_transfer <= acmd_new_transfer;
		acmd_prev_write <= acmd_new_write;
		acmd_prev_regno <= acmd_new_regno;
		acmd_prev_unsupported <= acmd_new_unsupported;
	end
end

wire       acmd_postexec    = acmd_new ? acmd_new_postexec    : acmd_prev_postexec   ;
wire       acmd_transfer    = acmd_new ? acmd_new_transfer    : acmd_prev_transfer   ;
wire       acmd_write       = acmd_new ? acmd_new_write       : acmd_prev_write      ;
wire [4:0] acmd_regno       = acmd_new ? acmd_new_regno       : acmd_prev_regno      ;
wire       acmd_unsupported = acmd_new ? acmd_new_unsupported : acmd_prev_unsupported;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		abstractcs_cmderr <= CMDERR_OK;
		acmd_state <= S_IDLE;
	end else if (!dmactive) begin
		abstractcs_cmderr <= CMDERR_OK;
		acmd_state <= S_IDLE;
	end else begin
		if (dmi_write && dmi_regaddr == ADDR_ABSTRACTCS && !abstractcs_busy)
			abstractcs_cmderr <= abstractcs_cmderr & ~dmi_pwdata[10:8];
		if (abstractcs_cmderr == CMDERR_OK && abstractcs_busy && dmi_access_illegal_when_busy)
			abstractcs_cmderr <= CMDERR_BUSY;
		if (acmd_state != S_IDLE && hart_instr_caught_exception[hartsel])
			abstractcs_cmderr <= CMDERR_EXCEPTION;
		case (acmd_state)
			S_IDLE: begin
				if (start_abstract_cmd) begin
					if (!hart_halted[hartsel] || !hart_available[hartsel]) begin
						abstractcs_cmderr <= CMDERR_HALTRESUME;
					end else if (acmd_unsupported) begin
						abstractcs_cmderr <= CMDERR_UNSUPPORTED;
					end else begin
						if (acmd_transfer && acmd_write)
							acmd_state <= S_ISSUE_REGWRITE;
						else if (acmd_transfer && !acmd_write)
							acmd_state <= S_ISSUE_REGREAD;
						else if (acmd_postexec)
							acmd_state <= S_ISSUE_PROGBUF0;
						else
							acmd_state <= S_IDLE;
					end
				end
			end

			S_ISSUE_REGREAD: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_ISSUE_REGEBREAK;
			end
			S_ISSUE_REGWRITE: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_ISSUE_REGEBREAK;
			end
			S_ISSUE_REGEBREAK: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_WAIT_REGEBREAK;
			end
			S_WAIT_REGEBREAK: begin
				if (hart_instr_caught_ebreak[hartsel]) begin
					if (acmd_prev_postexec)
						acmd_state <= S_ISSUE_PROGBUF0;
					else
						acmd_state <= S_IDLE;
				end
			end

			S_ISSUE_PROGBUF0: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_ISSUE_PROGBUF1;
			end
			S_ISSUE_PROGBUF1: begin
				if (hart_instr_caught_exception[hartsel] || hart_instr_caught_ebreak[hartsel]) begin
					acmd_state <= S_IDLE;
				end else if (hart_instr_data_rdy[hartsel]) begin
					acmd_state <= S_ISSUE_IMPEBREAK;
				end
			end
			S_ISSUE_IMPEBREAK: begin
				if (hart_instr_caught_exception[hartsel] || hart_instr_caught_ebreak[hartsel]) begin
					acmd_state <= S_IDLE;
				end else if (hart_instr_data_rdy[hartsel]) begin
					acmd_state <= S_WAIT_IMPEBREAK;
				end
			end
			S_WAIT_IMPEBREAK: begin
				if (hart_instr_caught_exception[hartsel] || hart_instr_caught_ebreak[hartsel]) begin
					acmd_state <= S_IDLE;
				end
			end
		endcase
	end
end

assign hart_instr_data_vld = {{N_HARTS{1'b0}},
	acmd_state == S_ISSUE_REGREAD || acmd_state == S_ISSUE_REGWRITE || acmd_state == S_ISSUE_REGEBREAK ||
	acmd_state == S_ISSUE_PROGBUF0 || acmd_state == S_ISSUE_PROGBUF1 || acmd_state == S_ISSUE_IMPEBREAK
} << hartsel;

assign hart_instr_data = {N_HARTS{
	acmd_state == S_ISSUE_REGWRITE  ? 32'hbff02073 | {20'd0, acmd_prev_regno,  7'd0} : // csrr xx, dmdata0
	acmd_state == S_ISSUE_REGREAD   ? 32'hbff01073 | {12'd0, acmd_prev_regno, 15'd0} : // csrw dmdata0, xx
	acmd_state == S_ISSUE_PROGBUF0  ? progbuf0                                       :
	acmd_state == S_ISSUE_PROGBUF1  ? progbuf1                                       :
	                                  32'h00100073                                     // ebreak
}};

// ----------------------------------------------------------------------------
// Status helper functions

function status_any;
	input [N_HARTS-1:0] status_mask;
begin
	status_any = status_mask[hartsel] || (hasel && |(status_mask & hart_array_mask));
end
endfunction

function status_all;
	input [N_HARTS-1:0] status_mask;
begin
	status_all = status_mask[hartsel] && (!hasel || ~|(~status_mask & hart_array_mask));
end
endfunction

function [1:0] status_all_any;
	input [N_HARTS-1:0] status_mask;
begin
	status_all_any = {
		status_all(status_mask),
		status_any(status_mask)
	};
end
endfunction

// ----------------------------------------------------------------------------
// DMI read data mux

always @ (*) begin
	case (dmi_regaddr)
	ADDR_DATA0:        dmi_prdata = abstract_data0;
	ADDR_DMCONTROL:    dmi_prdata = {
		1'b0,                             // haltreq is a W-only field
		1'b0,                             // resumereq is a W1 field
		status_any(dmcontrol_hartreset),
		1'b0,                             // ackhavereset is a W1 field
		1'b0,                             // reserved
		hasel,
		{{10-W_HARTSEL{1'b0}}, hartsel},  // hartsello
		10'h0,                            // hartselhi
		2'h0,                             // reserved
		2'h0,                             // set/clrresethaltreq are W1 fields
		dmcontrol_ndmreset,
		dmactive
	};
	ADDR_DMSTATUS:     dmi_prdata = {
		9'h0,                                               // reserved
		1'b1,                                               // impebreak = 1
		2'h0,                                               // reserved
		status_all_any(dmstatus_havereset),                 // allhavereset, anyhavereset
		status_all_any(dmstatus_resumeack),                 // allresumeack, anyresumeack
		hartsel >= N_HARTS && !(hasel && |hart_array_mask), // allnonexistent
		hartsel >= N_HARTS,                                 // anynonexistent
		status_all_any(~hart_available),                    // allunavail, anyunavail
		status_all_any(hart_running & hart_available),      // allrunning, anyrunning
		status_all_any(hart_halted & hart_available),       // allhalted, anyhalted
		1'b1,                                               // authenticated
		1'b0,                                               // authbusy
		1'b1,                                               // hasresethaltreq = 1 (we do support it)
		1'b0,                                               // confstrptrvalid
		4'd2                                                // version = 2: RISC-V debug spec 0.13.2
	};
	ADDR_HARTINFO:     dmi_prdata = {
		8'h0,                             // reserved
		4'h0,                             // nscratch = 0
		3'h0,                             // reserved
		1'b0,                             // dataccess = 0, data0 is mapped to each hart's CSR space
		4'h1,                             // datasize = 1, a single data CSR (data0) is available
		12'hbff                           // dataaddr, placed at the top of the M-custom space since
		                                  // the spec doesn't reserve a location for it.
	};
	ADDR_HALTSUM0:     dmi_prdata = {
		{XLEN - N_HARTS{1'b0}},
		hart_halted & hart_available
	};
	ADDR_HALTSUM1:     dmi_prdata = {
		{XLEN - 1{1'b0}},
		|(hart_halted & hart_available)
	};
	ADDR_HAWINDOWSEL:  dmi_prdata = 32'h00000000;
	ADDR_HAWINDOW:     dmi_prdata = {
		{32-N_HARTS{1'b0}},
		hart_array_mask
	};
	ADDR_ABSTRACTCS:   dmi_prdata = {
		3'h0,                             // reserved
		5'd2,                             // progbufsize = 2
		11'h0,                            // reserved
		abstractcs_busy,
		1'b0,
		abstractcs_cmderr,
		4'h0,
		4'd1                              // datacount = 1
	};
	ADDR_ABSTRACTAUTO: dmi_prdata = {
		14'h0,
		abstractauto_autoexecprogbuf,     // only progbuf0,1 present
		15'h0,
		abstractauto_autoexecdata         // only data0 present
	};
	ADDR_SBCS:          dmi_prdata = {
		3'h1,                             // version = 1
		6'h00,
		sbbusyerror,
		sbbusy,
		sbreadonaddr,
		sbaccess,
		sbautoincrement,
		sbreadondata,
		sberror,
		7'h20,                            // sbasize = 32
		5'b00111                          // 8, 16, 32-bit transfers supported
	} & {32{|HAVE_SBA}};
	ADDR_SBDATA0:      dmi_prdata = sbdata & {32{|HAVE_SBA}};
	ADDR_SBADDRESS0:   dmi_prdata = sbaddress & {32{|HAVE_SBA}};
	ADDR_CONFSTRPTR0:  dmi_prdata = 32'h4c296328;
	ADDR_CONFSTRPTR1:  dmi_prdata = 32'h20656b75;
	ADDR_CONFSTRPTR2:  dmi_prdata = 32'h6e657257;
	ADDR_CONFSTRPTR3:  dmi_prdata = 32'h31322720;
	ADDR_NEXTDM:       dmi_prdata = NEXT_DM_ADDR;
	ADDR_PROGBUF0:     dmi_prdata = progbuf0;
	ADDR_PROGBUF1:     dmi_prdata = progbuf1;
	default:           dmi_prdata = {XLEN{1'b0}};
	endcase
end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
