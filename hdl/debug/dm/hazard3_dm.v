/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// RISC-V Debug Module for Hazard3. Supports up to 32 cores (1 hart per core).

`default_nettype none

module hazard3_dm #(
	// Where there are multiple harts per DM, the least-indexed hart is the
	// least-significant on each concatenated hart access bus.
	parameter N_HARTS       = 1,
	// Where there are multiple DMs, the address of each DM should be a
	// multiple of 'h200, so that bits[8:2] decode correctly.
	parameter NEXT_DM_ADDR  = 32'h0000_0000,
	// If 1, implement the abstract access memory command. AAM is not required
	// for full-speed memory transfers, but can perform minimally intrusive
	// memory access whilst the core is running (e.g. Segger RTT)
	parameter HAVE_AAM      = 1,

	parameter XLEN          = 32, // Do not modify
	parameter W_HARTSEL     = N_HARTS > 1 ? $clog2(N_HARTS) : 1 // Do not modify
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

// Second data register required for address for abstract access memory cmd
localparam HAVE_DATA1 = HAVE_AAM;

// ----------------------------------------------------------------------------
// Address constants

localparam ADDR_DATA0        = 7'h04;
localparam ADDR_DATA1        = 7'h05;
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
// No authentication, no system bus access

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

wire dmcontrol_resumereq = dmi_write && dmi_regaddr == ADDR_DMCONTROL && dmi_pwdata[30];

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
reg [XLEN-1:0] abstract_data1;

// If AAM is supported then we may expose either data0/data1 to the core CSR
// interface at different times, and this wire determines which:
reg core_adata_regsel;

assign hart_data0_rdata = {N_HARTS{
	core_adata_regsel ? abstract_data1 : abstract_data0
}};

always @ (posedge clk or negedge rst_n) begin: update_hart_data0
	integer i;
	if (!rst_n) begin
		abstract_data0 <= {XLEN{1'b0}};
		abstract_data1 <= {XLEN{1'b0}};
	end else if (!dmactive) begin
		abstract_data0 <= {XLEN{1'b0}};
		abstract_data1 <= {XLEN{1'b0}};
	end else if (dmi_write && dmi_regaddr == ADDR_DATA0) begin
		abstract_data0 <= dmi_pwdata;
	end else if (dmi_write && dmi_regaddr == ADDR_DATA1 && HAVE_DATA1) begin
		abstract_data1 <= dmi_pwdata;
	end else begin
		for (i = 0; i < N_HARTS; i = i + 1) begin
			if (hartsel == i && hart_data0_wen[i] && hart_halted[i] && abstractcs_busy) begin
				if (core_adata_regsel) begin
					abstract_data1 <= hart_data0_wdata[i * XLEN +: XLEN];
				end else begin
					abstract_data0 <= hart_data0_wdata[i * XLEN +: XLEN];
				end
			end
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

reg [HAVE_DATA1:0] abstractauto_autoexecdata;
reg [1:0]          abstractauto_autoexecprogbuf;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		abstractauto_autoexecdata <= {HAVE_DATA1+1{1'b0}};
		abstractauto_autoexecprogbuf <= 2'b00;
	end else if (!dmactive) begin
		abstractauto_autoexecdata <= {HAVE_DATA1+1{1'b0}};
		abstractauto_autoexecprogbuf <= 2'b00;
	end else if (dmi_write && dmi_regaddr == ADDR_ABSTRACTAUTO) begin
		abstractauto_autoexecdata <= dmi_pwdata[HAVE_DATA1:0];
		abstractauto_autoexecprogbuf <= dmi_pwdata[17:16];
	end
end

// ----------------------------------------------------------------------------
// Abstract command state machine

localparam W_STATE = 5;
localparam S_IDLE           = 5'd0;

// States for the Abstract Access Register command
localparam S_AAR_REGREAD    = 5'd1;
localparam S_AAR_REGWRITE   = 5'd2;
localparam S_AAR_REG_BREAK  = 5'd3;
localparam S_AAR_WAIT_REG   = 5'd4;

localparam S_AAR_PROGBUF0   = 5'd5;
localparam S_AAR_PROGBUF1   = 5'd6;
localparam S_AAR_IMPEBREAK  = 5'd7;

// States for the Abstract Access Register command
localparam S_AAM_PRESWAP0   = 5'd8;
localparam S_AAM_PRESWAP1   = 5'd9;
localparam S_AAM_LOADSTORE  = 5'd10;
localparam S_AAM_LS_BREAK   = 5'd11;
localparam S_AAM_WAIT_LS    = 5'd12;
localparam S_AAM_INCREMENT  = 5'd13;
localparam S_AAM_POSTSWAP0  = 5'd14;
localparam S_AAM_POSTSWAP1  = 5'd15;
localparam S_AAM_END_BREAK  = 5'd16;

// Shared state: wait for ebreak then return to idle
localparam S_WAIT_DONE      = 5'd17;

// Error codes for abstractcs.cmderr:
localparam CMDERR_OK          = 3'h0;
localparam CMDERR_BUSY        = 3'h1;
localparam CMDERR_UNSUPPORTED = 3'h2;
localparam CMDERR_EXCEPTION   = 3'h3;
localparam CMDERR_HALTRESUME  = 3'h4;

reg [2:0]         abstractcs_cmderr;
reg [W_STATE-1:0] acmd_state;

assign abstractcs_busy = acmd_state != S_IDLE;

wire start_abstract_cmd = abstractcs_cmderr == CMDERR_OK && !abstractcs_busy && (
	(dmi_write && dmi_regaddr == ADDR_COMMAND) ||
	((dmi_write || dmi_read) && dmi_regaddr == ADDR_DATA0    && abstractauto_autoexecdata[0]) ||
	((dmi_write || dmi_read) && dmi_regaddr == ADDR_DATA1    && abstractauto_autoexecdata[HAVE_DATA1] && HAVE_DATA1) ||
	((dmi_write || dmi_read) && dmi_regaddr == ADDR_PROGBUF0 && abstractauto_autoexecprogbuf[0]) ||
	((dmi_write || dmi_read) && dmi_regaddr == ADDR_PROGBUF1 && abstractauto_autoexecprogbuf[1])
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

// The fields line up nicely between AAR and AAM:
wire [7:0] acmd_new_command     = dmi_pwdata[31:24];
wire       acmd_new_increment   = dmi_pwdata[19];
wire       acmd_new_postexec    = dmi_pwdata[18];
wire [2:0] acmd_new_size        = dmi_pwdata[22:20];
wire       acmd_new_transfer    = dmi_pwdata[17];
wire       acmd_new_write       = dmi_pwdata[16];
wire [4:0] acmd_new_regno       = dmi_pwdata[4:0];

wire       acmd_new_unsupported =
	acmd_new_command == 8'h00 ? (             // Abstract Access Register
		acmd_new_size     != 3'h2  ||         // Must be 32 bits in size
		acmd_new_increment         ||         // aarpostincrement not supported
		dmi_pwdata[15:12] != 4'h1  ||         // Only core register access supported
		dmi_pwdata[11:5]  != 7'h0             // Only GPRs supported
	) :
	acmd_new_command == 8'h02 && HAVE_AAM ? ( // Abstract Access Memory
		acmd_new_size     >  3'h2             // 8/16/32-bit supported
	) :
		1'b1;                                 // No other commands supported


// Only bit 1 of the command field is stored (AAR vs AAM)
reg        acmd_prev_command;
reg        acmd_prev_increment;
reg        acmd_prev_postexec;
reg  [2:0] acmd_prev_size;
reg        acmd_prev_transfer;
reg        acmd_prev_write;
reg  [4:0] acmd_prev_regno;
reg        acmd_prev_unsupported;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		acmd_prev_command     <= 1'b0;
		acmd_prev_increment   <= 1'b0;
		acmd_prev_postexec    <= 1'b0;
		acmd_prev_size        <= 3'h0;
		acmd_prev_transfer    <= 1'b0;
		acmd_prev_write       <= 1'b0;
		acmd_prev_regno       <= 5'h0;
		acmd_prev_unsupported <= 1'b1;
	end else if (!dmactive) begin
		acmd_prev_command     <= 1'b0;
		acmd_prev_increment   <= 1'b0;
		acmd_prev_postexec    <= 1'b0;
		acmd_prev_size        <= 3'h0;
		acmd_prev_transfer    <= 1'b0;
		acmd_prev_write       <= 1'b0;
		acmd_prev_regno       <= 5'h0;
		acmd_prev_unsupported <= 1'b1;
	end else if (start_abstract_cmd && acmd_new) begin
		acmd_prev_command     <= acmd_new_command[1] && HAVE_AAM;
		acmd_prev_increment   <= acmd_new_increment && HAVE_AAM;
		acmd_prev_postexec    <= acmd_new_postexec;
		acmd_prev_size        <= HAVE_AAM ? acmd_new_size : 3'h0;
		acmd_prev_transfer    <= acmd_new_transfer;
		acmd_prev_write       <= acmd_new_write;
		acmd_prev_regno       <= acmd_new_regno;
		acmd_prev_unsupported <= acmd_new_unsupported;
	end
end

wire       acmd_command     = acmd_new ? acmd_new_command[1]  : acmd_prev_command    ;
wire       acmd_increment   = acmd_new ? acmd_new_increment   : acmd_prev_increment  ;
wire       acmd_postexec    = acmd_new ? acmd_new_postexec    : acmd_prev_postexec   ;
wire [2:0] acmd_size        = acmd_new ? acmd_new_size        : acmd_prev_size       ;
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
					end else if (!acmd_command) begin
						// Abstract Access Register
						if (acmd_transfer && acmd_write)
							acmd_state <= S_AAR_REGWRITE;
						else if (acmd_transfer && !acmd_write)
							acmd_state <= S_AAR_REGREAD;
						else if (acmd_postexec)
							acmd_state <= S_AAR_PROGBUF0;
						else
							acmd_state <= S_IDLE;
					end else if (acmd_command && HAVE_AAM) begin
						// Abstract Access Memory
						acmd_state <= S_AAM_PRESWAP0;
					end
				end
			end

			// Abstract Access Register transfer states:

			S_AAR_REGREAD: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_AAR_REG_BREAK;
			end
			S_AAR_REGWRITE: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_AAR_REG_BREAK;
			end
			S_AAR_REG_BREAK: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_AAR_WAIT_REG;
			end
			S_AAR_WAIT_REG: begin
				if (hart_instr_caught_ebreak[hartsel]) begin
					if (acmd_prev_postexec)
						acmd_state <= S_AAR_PROGBUF0;
					else
						acmd_state <= S_IDLE;
				end
			end

			// Abstract Access Register postexec states:

			S_AAR_PROGBUF0: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_AAR_PROGBUF1;
			end
			S_AAR_PROGBUF1: begin
				// Note frontend flush takes precedence over instruction injection, so we can go
				// straight to idle without worrying about the instruction injected from this state.
				if (hart_instr_caught_exception[hartsel] || hart_instr_caught_ebreak[hartsel]) begin
					acmd_state <= S_IDLE;
				end else if (hart_instr_data_rdy[hartsel]) begin
					acmd_state <= S_AAR_IMPEBREAK;
				end
			end
			S_AAR_IMPEBREAK: begin
				if (hart_instr_caught_exception[hartsel] || hart_instr_caught_ebreak[hartsel]) begin
					acmd_state <= S_IDLE;
				end else if (hart_instr_data_rdy[hartsel]) begin
					acmd_state <= S_WAIT_DONE;
				end
			end

			// Abstract Access Memory states:
			// TODO minimally intrusive quick halt

			S_AAM_PRESWAP0: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_AAM_PRESWAP1;
			end
			S_AAM_PRESWAP1: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_AAM_LOADSTORE;
			end
			S_AAM_LOADSTORE: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_AAM_LS_BREAK;
			end
			S_AAM_LS_BREAK: begin
				if (hart_instr_caught_exception[hartsel]) begin
					acmd_state <= S_AAM_INCREMENT;
				end else if (hart_instr_data_rdy[hartsel]) begin
					acmd_state <= S_AAM_WAIT_LS;
				end
			end
			S_AAM_WAIT_LS: begin
				// Fence off on the load/store having completed, by waiting for an ebreak directly
				// after it. Required because the cmderr exception flag must suppress increment
				// (but we must still run the rest of this microprogram to restore GPRs)
				if (hart_instr_caught_exception[hartsel] || hart_instr_caught_ebreak[hartsel])
					acmd_state <= S_AAM_INCREMENT;
			end

			S_AAM_INCREMENT: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_AAM_POSTSWAP0;
			end
			S_AAM_POSTSWAP0: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_AAM_POSTSWAP1;
			end
			S_AAM_POSTSWAP1: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_AAM_END_BREAK;
			end
			S_AAM_END_BREAK: begin
				if (hart_instr_data_rdy[hartsel])
					acmd_state <= S_WAIT_DONE;
			end

			// Fence off on the final ebreak before returning

			S_WAIT_DONE: begin
				if (hart_instr_caught_exception[hartsel] || hart_instr_caught_ebreak[hartsel]) begin
					acmd_state <= S_IDLE;
				end
			end

		endcase
	end
end

// Control whether DATA0/DATA1 is exposed to the hart, according to the state machine
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		core_adata_regsel <= 1'b0;
	end else if (!dmactive || acmd_state == S_IDLE) begin
		core_adata_regsel <= 1'b0;
	end else if (hart_data0_wen[hartsel] && hart_halted[hartsel] && abstractcs_busy) begin
		// AAM performs alternating accesses to DATA0/DATA1. AAR only accesses DATA0.
		core_adata_regsel <= core_adata_regsel ^ acmd_prev_command;
	end
end

assign hart_instr_data_vld = {{N_HARTS-1{1'b0}},
	acmd_state == S_AAR_REGREAD || acmd_state == S_AAR_REGWRITE || acmd_state == S_AAR_REG_BREAK ||
	acmd_state == S_AAR_PROGBUF0 || acmd_state == S_AAR_PROGBUF1 || acmd_state == S_AAR_IMPEBREAK ||
	HAVE_AAM && (
		acmd_state == S_AAM_PRESWAP0 || acmd_state == S_AAM_PRESWAP1 || acmd_state == S_AAM_LOADSTORE || acmd_state == S_AAM_LS_BREAK ||
		acmd_state == S_AAM_INCREMENT || acmd_state == S_AAM_POSTSWAP0 || acmd_state == S_AAM_POSTSWAP1 || acmd_state == S_AAM_END_BREAK
	)
} << hartsel;

assign hart_instr_data = {N_HARTS{
	acmd_state == S_AAR_REGWRITE              ? 32'hbff02073 | {20'd0, acmd_prev_regno,  7'd0} : // csrr xx, dmdata
	acmd_state == S_AAR_REGREAD               ? 32'hbff01073 | {12'd0, acmd_prev_regno, 15'd0} : // csrw dmdata, xx
	acmd_state == S_AAR_PROGBUF0              ? progbuf0                                       :
	acmd_state == S_AAR_PROGBUF1              ? progbuf1                                       :

	acmd_state == S_AAM_PRESWAP0  && HAVE_AAM ? 32'hbff51573                                   : // csrrw a0, dmdata, a0
	acmd_state == S_AAM_PRESWAP1  && HAVE_AAM ? 32'hbff595f3                                   : // csrrw a1, dmdata, a1

	acmd_state == S_AAM_LOADSTORE && HAVE_AAM ? (
	acmd_prev_write && acmd_prev_size == 3'h0 ? 32'h00a58023                                   : // sb  a0, (a1)
	                   acmd_prev_size == 3'h0 ? 32'h0005c503                                   : // lbu a0, (a1)
	acmd_prev_write && acmd_prev_size == 3'h1 ? 32'h00a59023                                   : // sh  a0, (a1)
	                   acmd_prev_size == 3'h1 ? 32'h0005d503                                   : // lhu a0, (a1)
	acmd_prev_write                           ? 32'h00a5a023                                   : // sw  a0, (a1)
	                                            32'h0005a503                                     // lw  a0, (a1)
	) :

	acmd_state == S_AAM_INCREMENT && HAVE_AAM ? 32'h00058593 | {                                 // addi a1, a1, 0x000
		!acmd_prev_increment                  ? 12'h000 :                                        // no increment because disabled
		abstractcs_cmderr == CMDERR_EXCEPTION ? 12'h000 :                                        // no increment because of load/store exception
		acmd_prev_size == 3'h0                ? 12'h001 :                                        // byte increment
		acmd_prev_size == 3'h1                ? 12'h002 : 12'h004,                               // halfword/word increment
		20'h00000
	} :

	acmd_state == S_AAM_POSTSWAP0 && HAVE_AAM ? 32'hbff51573                                   : // csrrw a0, dmdata, a0
	acmd_state == S_AAM_POSTSWAP1 && HAVE_AAM ? 32'hbff595f3                                   : // csrrw a1, dmdata, a1

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
	ADDR_DATA1:        dmi_prdata = abstract_data1;
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
		9'h0,                                           // reserved
		1'b1,                                           // impebreak = 1
		2'h0,                                           // reserved
		status_all_any(dmstatus_havereset),             // allhavereset, anyhavereset
		status_all_any(dmstatus_resumeack),             // allresumeack, anyresumeack
		{2{!hasel && hartsel >= N_HARTS}},              // allnonexistent, anynonexistent
		status_all_any(~hart_available),                // allunavail, anyunavail
		status_all_any(hart_running & hart_available),  // allrunning, anyrunning
		status_all_any(hart_halted & hart_available),   // allhalted, anyhalted
		1'b1,                                           // authenticated
		1'b0,                                           // authbusy
		1'b1,                                           // hasresethaltreq = 1 (we do support it)
		1'b0,                                           // confstrptrvalid
		4'd2                                            // version = 2: RISC-V debug spec 0.13.2
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
		HAVE_DATA1 ? 4'd2 : 4'd1          // datacount = 1 or 2, depending on AAM support
	};
	ADDR_ABSTRACTAUTO: dmi_prdata = {
		14'h0,
		abstractauto_autoexecprogbuf,     // only progbuf0,1 present
		{15-HAVE_DATA1{1'b0}},
		abstractauto_autoexecdata         // Either 1 or 2 bits wide
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

`ifndef YOSYS
`default_nettype wire
`endif
