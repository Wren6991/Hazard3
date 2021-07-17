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

// RISC-V Debug Module for Hazard3

`default_nettype none

module hazard3_dm #(
	// Where there are multiple harts per DM, the least-indexed hart is the
	// least-significant on each concatenated hart access bus.
	parameter N_HARTS = 1,
	// Where there are multiple DMs, the address of each DM should be a
	// multiple of 'h100, so that the lower 8 bits decode correctly.
	parameter NEXT_DM_ADDR = 32'h0000_0000,

	parameter XLEN = 32, // Do not modify
	parameter W_HARTSEL = N_HARTS > 1 ? $clog2(N_HARTS) : 1 // Do not modify
) (
	// DM is assumed to be in same clock domain as core; clock crossing
	// (if any) is inside DTM, or between DTM and DM.
	input  wire                      clk,
	input  wire                      rst_n,

	// APB access from Debug Transport Module
	input  wire                      dmi_psel,
	input  wire                      dmi_penable,
	input  wire                      dmi_pwrite,
	input  wire [7:0]                dmi_paddr,
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
	input  wire [N_HARTS-1:0]        hart_instr_caught_ebreak
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

localparam ADDR_DATA0        = 8'h04;
// Other data registers not present.
localparam ADDR_DMCONTROL    = 8'h10;
localparam ADDR_DMSTATUS     = 8'h11;
localparam ADDR_HARTINFO     = 8'h12;
localparam ADDR_HALTSUM1     = 8'h13;
localparam ADDR_HALTSUM0     = 8'h40;
// No HALTSUM2+ registers (we don't support >32 harts anyway)
// No array mask select registers
localparam ADDR_ABSTRACTCS   = 8'h16;
localparam ADDR_COMMAND      = 8'h17;
localparam ADDR_ABSTRACTAUTO = 8'h18;
localparam ADDR_CONFSTRPTR0  = 8'h19;
localparam ADDR_CONFSTRPTR1  = 8'h1a;
localparam ADDR_CONFSTRPTR2  = 8'h1b;
localparam ADDR_CONFSTRPTR3  = 8'h1c;
localparam ADDR_NEXTDM       = 8'h1d;
localparam ADDR_PROGBUF0     = 8'h20;
localparam ADDR_PROGBUF1     = 8'h21;
// No authentication, no system bus access

// ----------------------------------------------------------------------------
// Hart selection

reg dmactive;

// Some fiddliness to make sure we get a single-wide zero-valued signal when
// N_HARTS == 1 (so we can use this for indexing of per-hart signals)
reg  [W_HARTSEL-1:0] hartsel;
wire [W_HARTSEL-1:0] hartsel_next;

generate
if (N_HARTS > 1) begin: has_hartsel
	// only the lower 10 bits of hartsel are supported
	assign hartsel_next = dmi_write && dmi_paddr == ADDR_DMCONTROL ?
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

// ----------------------------------------------------------------------------
// Run/halt/reset control

// Normal read/write fields for dmcontrol (note some of these are per-hart
// fields that get rotated into dmcontrol based on the current/next hartsel).
reg [N_HARTS-1:0] dmcontrol_haltreq;
reg [N_HARTS-1:0] dmcontrol_hartreset;
reg [N_HARTS-1:0] dmcontrol_resethaltreq;
reg               dmcontrol_ndmreset;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		dmactive <= 1'b0;
		dmcontrol_ndmreset <= 1'b0;
		dmcontrol_haltreq <= {N_HARTS{1'b0}};
		dmcontrol_hartreset <= {N_HARTS{1'b0}};
		dmcontrol_resethaltreq <= {N_HARTS{1'b0}};
	end else if (!dmactive) begin
		// Only dmactive is writable when !dmactive
		if (dmi_write && dmi_paddr == ADDR_DMCONTROL)
			dmactive <= dmi_pwdata[0];
		dmcontrol_ndmreset <= 1'b0;
		dmcontrol_haltreq <= {N_HARTS{1'b0}};
		dmcontrol_hartreset <= {N_HARTS{1'b0}};
		dmcontrol_resethaltreq <= {N_HARTS{1'b0}};
	end else if (dmi_write && dmi_paddr == ADDR_DMCONTROL) begin
		dmactive <= dmi_pwdata[0];
		dmcontrol_ndmreset <= dmi_pwdata[1];
		dmcontrol_haltreq[hartsel_next] <= dmi_pwdata[31];
		dmcontrol_hartreset[hartsel_next] <= dmi_pwdata[29];
		// set/clear fields on this one for some reason
		dmcontrol_resethaltreq[hartsel_next] <= dmcontrol_resethaltreq[hartsel_next]
			&& !dmi_pwdata[2] || dmi_pwdata[3];
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

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		dmstatus_havereset <= {N_HARTS{1'b0}};
	end else if (!dmactive) begin
		dmstatus_havereset <= {N_HARTS{1'b0}};
	end else begin
		dmstatus_havereset <= dmstatus_havereset | (hart_reset_done & ~hart_reset_done_prev);
		// dmcontrol.ackhavereset:
		if (dmi_write && dmi_paddr == ADDR_DMCONTROL && dmi_pwdata[28])
			dmstatus_havereset[hartsel_next] <= 1'b0;
	end
end

reg [N_HARTS-1:0] dmstatus_resumeack;
reg [N_HARTS-1:0] dmcontrol_resumereq_sticky;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		dmstatus_resumeack <= {N_HARTS{1'b0}};
		dmcontrol_resumereq_sticky <= {N_HARTS{1'b0}};
	end else if (!dmactive) begin
		dmstatus_resumeack <= {N_HARTS{1'b0}};
		dmcontrol_resumereq_sticky <= {N_HARTS{1'b0}};
	end else begin
		dmstatus_resumeack <= dmstatus_resumeack | (dmcontrol_resumereq_sticky & hart_running & hart_available);
		dmcontrol_resumereq_sticky <= dmcontrol_resumereq_sticky & ~(hart_running & hart_available); // TODO this is because our "running" is actually just "not debug mode"
		// dmcontrol.resumereq:
		if (dmi_write && dmi_paddr == ADDR_DMCONTROL && dmi_pwdata[30]) begin
			dmcontrol_resumereq_sticky[hartsel_next] <= 1'b1;
			dmstatus_resumeack[hartsel_next] <= 1'b0;
		end
	end
end

assign hart_req_resume = dmcontrol_resumereq_sticky;

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
	end else if (dmi_write && dmi_paddr == ADDR_DATA0) begin
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
		if (dmi_paddr == ADDR_PROGBUF0)
			progbuf0 <= dmi_pwdata;
		if (dmi_paddr == ADDR_PROGBUF1)
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
	end else if (dmi_write && dmi_paddr == ADDR_ABSTRACTAUTO) begin
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
	(dmi_write && dmi_paddr == ADDR_COMMAND) ||
	((dmi_write || dmi_read) && abstractauto_autoexecdata && dmi_paddr == ADDR_DATA0) ||
	((dmi_write || dmi_read) && abstractauto_autoexecprogbuf[0] && dmi_paddr == ADDR_PROGBUF0) ||
	((dmi_write || dmi_read) && abstractauto_autoexecprogbuf[1] && dmi_paddr == ADDR_PROGBUF1)
);

wire dmi_access_illegal_when_busy =
	(dmi_write && (
		dmi_paddr == ADDR_ABSTRACTCS || dmi_paddr == ADDR_COMMAND || dmi_paddr == ADDR_ABSTRACTAUTO ||
		dmi_paddr == ADDR_DATA0 || dmi_paddr == ADDR_PROGBUF0 || dmi_paddr == ADDR_PROGBUF0)) ||
	(dmi_read && (
		dmi_paddr == ADDR_DATA0 || dmi_paddr == ADDR_PROGBUF0 || dmi_paddr == ADDR_PROGBUF0));

// Decode what acmd may be triggered on this cycle, and whether it is
// supported -- command source may be a registered version of most recent
// command (if abstractauto is used) or a fresh command off the bus. We don't
// register the entire write data; repeats of unsupported commands are
// detected by just registering that the last written command was
// unsupported.

wire       acmd_new = dmi_write && dmi_paddr == ADDR_COMMAND;

wire       acmd_new_postexec    = dmi_pwdata[18];
wire       acmd_new_transfer    = dmi_pwdata[17];
wire       acmd_new_write       = dmi_pwdata[16];
wire [4:0] acmd_new_regno       = dmi_pwdata[4:0];

wire       acmd_new_unsupported =
	dmi_pwdata[31:24] != 8'h00 || // Only Access Register command supported
	dmi_pwdata[22:20] != 3'h2  || // Must be 32 bits in size
	dmi_pwdata[19]             || // aarpostincrement not supported
	dmi_pwdata[15:12] != 4'h1  || // Only core register access supported
	dmi_pwdata[11:5]  != 7'h0;    // Only GPRs supported

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
		if (dmi_write && dmi_paddr == ADDR_ABSTRACTCS && !abstractcs_busy)
			abstractcs_cmderr <= abstractcs_cmderr & ~dmi_pwdata[10:8];
		if (abstractcs_cmderr == CMDERR_OK && abstractcs_busy && dmi_access_illegal_when_busy)
			abstractcs_cmderr <= CMDERR_BUSY;
		if (acmd_state != S_IDLE && hart_instr_caught_exception)
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
				if (hart_instr_caught_ebreak) begin
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
				if (hart_instr_caught_exception || hart_instr_caught_ebreak) begin
					acmd_state <= S_IDLE;
				end else if (hart_instr_data_rdy[hartsel]) begin
					acmd_state <= S_ISSUE_IMPEBREAK;
				end
			end
			S_ISSUE_IMPEBREAK: begin
				if (hart_instr_caught_exception || hart_instr_caught_ebreak) begin
					acmd_state <= S_IDLE;
				end else if (hart_instr_data_rdy[hartsel]) begin
					acmd_state <= S_WAIT_IMPEBREAK;
				end
			end
			S_WAIT_IMPEBREAK: begin
				if (hart_instr_caught_exception || hart_instr_caught_ebreak) begin
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
	acmd_state == S_ISSUE_REGWRITE  ? 32'h7b202073 | {20'd0, acmd_prev_regno,  7'd0} : // csrr xx, data0
	acmd_state == S_ISSUE_REGREAD   ? 32'h7b201073 | {12'd0, acmd_prev_regno, 15'd0} : // csrw data0, xx
	acmd_state == S_ISSUE_PROGBUF0  ? progbuf0                                    :
	acmd_state == S_ISSUE_PROGBUF1  ? progbuf1                                    :
	                                  32'h00100073                                  // ebreak
}};

// ----------------------------------------------------------------------------
// DMI read data mux

always @ (*) begin
	case (dmi_paddr)
	ADDR_DATA0:        dmi_prdata = abstract_data0;
	ADDR_DMCONTROL:    dmi_prdata = {
		dmcontrol_haltreq[hartsel],
		1'b0,                             // resumereq is a W1 field
		dmcontrol_hartreset[hartsel],
		1'b0,                             // ackhavereset is a W1 field
		1'b0,                             // reserved
		1'b0,                             // hasel hardwired 0 (no array mask)
		{{10-W_HARTSEL{1'b0}}, hartsel},  // hartsello
		10'h0,                            // hartselhi
		2'h0,                             // reserved
		2'h0,                             // set/clrresethaltreq are W1 fields
		dmcontrol_ndmreset,
		dmactive
	};
	ADDR_DMSTATUS:     dmi_prdata = {
		9'h0,                                                  // reserved
		1'b1,                                                  // impebreak = 1
		2'h0,                                                  // reserved
		{2{dmstatus_havereset[hartsel]}},                      // allhavereset, anyhavereset
		{2{dmstatus_resumeack[hartsel]}},                      // allresumeack, anyresumeack
		{2{hartsel >= N_HARTS}},                               // allnonexistent, anynonexistent
		{2{!hart_available[hartsel]}},                         // allunavail, anyunavail
		{2{hart_running[hartsel] && hart_available[hartsel]}}, // allrunning, anyrunning
		{2{hart_halted[hartsel] && hart_available[hartsel]}},  // allhalted, anyhalted
		1'b1,                                                  // authenticated
		1'b0,                                                  // authbusy
		1'b1,                                                  // hasresethaltreq = 1 (we do support it)
		1'b0,                                                  // confstrptrvalid
		4'd2                                                   // version = 2: RISC-V debug spec 0.13.2
	};
	ADDR_HARTINFO:     dmi_prdata = {
		8'h0,                             // reserved
		4'h0,                             // nscratch = 0
		3'h0,                             // reserved
		1'b0,                             // dataccess = 0, data0 is backed by a per-hart CSR
		4'h1,                             // datasize = 1, a single data CSR (data0) is available
		12'h7b2                           // dataaddr, same location where dscratch0 would be if implemented
	};
	ADDR_HALTSUM0:     dmi_prdata = {
		{XLEN - N_HARTS{1'b0}},
		hart_halted & hart_available
	};
	ADDR_HALTSUM1:     dmi_prdata = {
		{XLEN - 1{1'b0}},
		|(hart_halted & hart_available)
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
