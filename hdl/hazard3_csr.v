/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

// Control and Status Registers (CSRs)
// Also includes CSR-related logic like interrupt enable/masking,
// trap vector calculation.

module hazard3_csr #(
	parameter XLEN            = 32,   // Must be 32
`include "hazard3_config.vh"
,
`include "hazard3_width_const.vh"
) (
	input  wire               clk,
	input  wire               clk_always_on,
	input  wire               rst_n,

	// Debug signalling
	output reg                debug_mode,

	input  wire               dbg_req_halt,
	input  wire               dbg_req_halt_on_reset,
	input  wire               dbg_req_resume,

	output wire               dbg_instr_caught_exception,
	output wire               dbg_instr_caught_ebreak,

	input  wire [W_DATA-1:0]  dbg_data0_rdata,
	output wire [W_DATA-1:0]  dbg_data0_wdata,
	output wire               dbg_data0_wen,

	output wire [W_ADDR-1:0]  debug_dpc_wdata,
	output wire               debug_dpc_wen,
	input  wire [W_ADDR-1:0]  debug_dpc_rdata,

	// Read port is combinatorial.
	// Write port is synchronous, and write effects will be observed on the next clock cycle.
	// The *_soon strobes are versions which the core does not gate with its stall signal.
	// These are needed because:
	// - Core stall is a function of bus stall
	// - Illegal CSR accesses produce trap entry
	// - Trap entry (not necessarily caused by CSR access) gates outgoing bus accesses
	// - Through-paths from e.g. hready to htrans are problematic for timing/implementation
	input  wire [11:0]        addr,
	input  wire [XLEN-1:0]    wdata,
	input  wire               wen,
	input  wire               wen_soon, // wen will be asserted once some stall condition clears
	input  wire               wen_raw,  // raw, ungated instruction decode signal, for D-mode regs
	input  wire [1:0]         wtype,
	output reg  [XLEN-1:0]    rdata,
	input  wire               ren,
	input  wire               ren_soon, // ren will be asserted once some stall condition clears
	output wire               illegal,

	// Trap signalling
	// *We* tell the core that we are taking a trap, and where to, based on:
	// - Synchronous exception inputs from the core
	// - External IRQ signals
	// - Masking etc based on the state of CSRs like mie
	//
	// We do this by raising trap_enter_vld, and keeping it raised until trap_enter_rdy
	// goes high. trap_addr has the absolute value of trap target address.
	// Once trap_enter_vld && _rdy, mepc_in is copied to mepc, and other trap state is set.
	//
	// Note that an exception input can go away, e.g. if the pipe gets flushed. In this
	// case we lower trap_enter_vld.
	output wire [XLEN-1:0]     trap_addr,
	output wire                trap_is_irq,
	output wire                trap_is_debug_entry,
	output wire                trap_enter_vld,
	input  wire                trap_enter_rdy,
	// True when we are about to trap, but are waiting for an excepting or
	// potentially-excepting instruction to clear M first. The instruction in X
	// is suppressed, X PC does not increment but still tracks exception
	// addresses.
	output wire                trap_enter_soon,
	// We need to know about load/stores in data phase because their exception
	// status is still unknown, so fence them off before entering debug mode.
	input  wire                loadstore_dphase_pending,
	// Asserted when the instruction in stage 2 can't be squashed (e.g. to
	// keep an AHB address phase stable), or instruction fetch request can't
	// be issued (e.g. waiting for wake from wfi state).
	input  wire                delay_irq_entry,
	input  wire [XLEN-1:0]     mepc_in,

	// Power control signalling
	output wire                pwr_allow_clkgate,
	output wire                pwr_allow_power_down,
	output wire                pwr_allow_sleep_on_block,
	output wire                pwr_wfi_wakeup_req,

	// Each of these may be performed at a different privilege level from the others:
	output wire                m_mode_execution,
	output wire                m_mode_trap_entry,
	output wire                m_mode_loadstore,

	// Exceptions must *not* be a function of bus stall.
	input  wire [W_EXCEPT-1:0] except,
	input  wire                except_to_d_mode,

	// Level-sensitive interrupt sources
	input  wire [NUM_IRQS-1:0] irq,
	input  wire                irq_software,
	input  wire                irq_timer,

	// PMP config interface
	output wire [11:0]         pmp_cfg_addr,
	output reg                 pmp_cfg_wen,
	output wire [W_DATA-1:0]   pmp_cfg_wdata,
	input  wire [W_DATA-1:0]   pmp_cfg_rdata,

	// Trigger config interface
	output wire [11:0]         trig_cfg_addr,
	output reg                 trig_cfg_wen,
	output wire [W_DATA-1:0]   trig_cfg_wdata,
	input  wire [W_DATA-1:0]   trig_cfg_rdata,
	output wire                trig_m_en,

	// Other CSR-specific signalling
	output wire                trap_wfi,
	input  wire                instr_ret
);

`include "hazard3_ops.vh"
`include "hazard3_csr_addr.vh"

localparam X0 = {XLEN{1'b0}};

// ----------------------------------------------------------------------------
// CSR state + update logic
// ----------------------------------------------------------------------------
// Names are (reg)_(field)

// Generic update logic for write/set/clear of an entire CSR:
wire [XLEN-1:0] wdata_update =
		wtype == CSR_WTYPE_C ? rdata & ~wdata :
		wtype == CSR_WTYPE_S ? rdata |  wdata : wdata;

function [XLEN-1:0] update_nonconst;
	input [XLEN-1:0] prev;
	input [XLEN-1:0] nonconst;
begin
		update_nonconst = (wdata_update & nonconst) | (prev & ~nonconst) ;
end
endfunction

wire enter_debug_mode;
wire exit_debug_mode;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		debug_mode <= 1'b0;
	end else if (DEBUG_SUPPORT) begin
		debug_mode <= (debug_mode && !exit_debug_mode) || enter_debug_mode;
	end
end

// Core execution state, 1 -> M-mode, 0 -> U-mode (if implemented)
reg  m_mode;
wire wen_m_mode = wen && (m_mode || debug_mode);
wire ren_m_mode = ren && (m_mode || debug_mode);

// ----------------------------------------------------------------------------
// Standard trap-handling CSRs

wire debug_suppresses_trap_update = DEBUG_SUPPORT && (debug_mode || enter_debug_mode);

wire trapreg_update = trap_enter_vld && trap_enter_rdy && !debug_suppresses_trap_update;
wire trapreg_update_enter = trapreg_update && except != EXCEPT_MRET;
wire trapreg_update_exit = trapreg_update && except == EXCEPT_MRET;

reg mstatus_mpie;
reg mstatus_mie;
reg mstatus_mpp; // only MSB is implemented
reg mstatus_mprv;
reg mstatus_tw;

// Spec text from priv-1.12:
// "An MRET or SRET instruction is used to return from a trap in M-mode or
//  S-mode respectively. When executing an xRET instruction, supposing xPP
//  holds the value y, xIE is set to xPIE; the privilege mode is changed to
//  y; xPIE is set to 1; and xPP is set to the least-privileged supported
//  mode (U if U-mode is implemented, else M). If xPP=M, xRET also sets
//  MPRV=0."

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		m_mode <= 1'b1;
		mstatus_mpie <= 1'b0;
		mstatus_mie <= 1'b0;
		mstatus_mpp <= 1'b1;
		mstatus_mprv <= 1'b0;
		mstatus_tw <= 1'b0;
	end else if (CSR_M_TRAP) begin
		if (trapreg_update_exit) begin
			mstatus_mpie <= 1'b1;
			mstatus_mie <= mstatus_mpie;
			if (U_MODE) begin
				m_mode <= mstatus_mpp;
				mstatus_mpp <= 1'b0;
				if (!mstatus_mpp) begin
					mstatus_mprv <= 1'b0;
				end
			end
		end else if (trapreg_update_enter) begin
			mstatus_mpie <= mstatus_mie;
			mstatus_mie <= 1'b0;
			if (U_MODE) begin
				m_mode <= 1'b1;
				mstatus_mpp <= m_mode;
			end
		end else if (wen_m_mode && addr == MSTATUS) begin
			mstatus_mpie <= wdata_update[7];
			mstatus_mie  <= wdata_update[3];
			mstatus_mprv <= wdata_update[17];
			// Note only the MSB of MPP is implemented. It reads back as 11 or 00.
			mstatus_mpp  <= wdata_update[12] || !U_MODE;
			mstatus_tw   <= wdata_update[21] && U_MODE;
		end else if (wen_raw && debug_mode && addr == DCSR && U_MODE && DEBUG_SUPPORT) begin
			// Debugger can change/observe core state directly through
			// dcsr.prv (this doesn't affect debugger operation, as all
			// operations have an effective level of M-mode whilst the core
			// is halted for debug.)
			m_mode <= wdata_update[1];
		end
	end
end

// Trap all U-mode WFIs if timeout bit is set. Note that the debug spec
// says "The `wfi` instruction acts as a `nop`" during program buffer
// execution, and nops do not trap, so in debug mode we allow WFIs but
// immediately wake them.
assign trap_wfi = mstatus_tw && !(debug_mode || m_mode);

reg [XLEN-1:0] mscratch;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mscratch <= X0;
	end else if (CSR_M_TRAP) begin
		if (wen_m_mode && addr == MSCRATCH)
			mscratch <= wdata_update;
	end
end

// Trap vector base
reg  [XLEN-1:0] mtvec_reg;
wire [XLEN-1:0] mtvec = mtvec_reg & ({XLEN{1'b1}} << 2);
wire            irq_vector_enable = mtvec_reg[0];

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mtvec_reg <= MTVEC_INIT;
	end else if (CSR_M_TRAP) begin
		if (wen_m_mode && addr == MTVEC)
			mtvec_reg <= update_nonconst(mtvec_reg, MTVEC_WMASK);
	end
end

// Exception program counter
reg [XLEN-1:0] mepc;
// mepc only holds values aligned to instruction alignment
localparam MEPC_MASK = {{XLEN-2{1'b1}}, |EXTENSION_C, 1'b0};

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mepc <= X0;
	end else if (CSR_M_TRAP) begin
		if (trapreg_update_enter) begin
			mepc <= mepc_in & MEPC_MASK;
		end else if (wen_m_mode && addr == MEPC) begin
			mepc <= wdata_update & MEPC_MASK;
		end
	end
end

// Interrupt enable (reserved bits are tied to 0)
reg [XLEN-1:0] mie;
localparam MIE_WMASK = 32'h00000888; // meie, mtie, msie

wire meicontext_clearts;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mie <= X0;
	end else if (CSR_M_TRAP) begin
		if (wen_m_mode && addr == MIE) begin
			mie <= update_nonconst(mie, MIE_WMASK);
		end else if (wen_m_mode && addr == MEICONTEXT) begin
			// meicontext.clearts/mtiesave/msiesave can be used to clear and
			// save standard timer and soft IRQ enables, simultaneously with
			// saving external interrupt context.
			mie[7] <= (mie[7] || wdata_update[3]) && !meicontext_clearts;
			mie[3] <= (mie[3] || wdata_update[2]) && !meicontext_clearts;
		end
	end
end

// Interrupt pending register (assigned later). In our implementation this
// register is entirely read-only.
wire [XLEN-1:0] mip;

// Trap cause registers. The non-constant bits can be written by software, and
// update automatically on trap entry. The `code` field need only be large
// enough to support causes that will be set by hardware, in our case 4 bits.
// (Note this is different to scause which always has a hard minimum of 5
// bits.)
reg        mcause_irq;
reg  [3:0] mcause_code;
wire       mcause_irq_next;
wire [3:0] mcause_code_next;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mcause_irq <= 1'b0;
		mcause_code <= 4'h0;
	end else if (CSR_M_TRAP) begin
		if (trapreg_update_enter) begin
			mcause_irq <= mcause_irq_next;
			mcause_code <= mcause_code_next;
		end else if (wen_m_mode && addr == MCAUSE) begin
			{mcause_irq, mcause_code} <= {wdata_update[31], wdata_update[3:0]};
		end
	end
end

// ----------------------------------------------------------------------------
// Custom external IRQ controller

wire [XLEN-1:0] irq_ctrl_rdata;
wire            external_irq_pending;

generate
if (|EXTENSION_XH3IRQ) begin: have_irq_ctrl

	hazard3_irq_ctrl #(
	`include "hazard3_config_inst.vh"
	) irq_ctrl (
		.clk                  (clk),
		.clk_always_on        (clk_always_on),
		.rst_n                (rst_n),

		.addr                 (addr),
		.wtype                (wtype),
		.wen_m_mode           (wen_m_mode),
		.ren_m_mode           (ren_m_mode),
		.wdata_raw            (wdata),
		.wdata                (wdata_update),
		.rdata                (irq_ctrl_rdata),

		.trapreg_update_enter (trapreg_update_enter),
		.trapreg_update_exit  (trapreg_update_exit),
		.trap_entry_is_eirq   (mcause_irq_next && mcause_code_next == 4'hb),

		.meicontext_clearts   (meicontext_clearts),
		.mie_mtie             (mie[7]),
		.mie_msie             (mie[3]),

		.irq                  (irq),
		.external_irq_pending (external_irq_pending)
	);

end else begin: no_irq_ctrl

	reg external_irq_pending_r;

	always @ (posedge clk_always_on or negedge rst_n) begin
		if (!rst_n) begin
			external_irq_pending_r <= 1'b0;
		end else begin
			external_irq_pending_r <= |irq;
		end
	end

	assign irq_ctrl_rdata = {W_DATA{1'b0}};
	assign meicontext_clearts = 1'b0;
	assign external_irq_pending = external_irq_pending_r;

end
endgenerate

// ----------------------------------------------------------------------------
// Custom sleep/power control CSRs

reg msleep_sleeponblock;
reg msleep_powerdown;
reg msleep_deepsleep;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		msleep_sleeponblock <= 1'b0;
		msleep_powerdown    <= 1'b0;
		msleep_deepsleep    <= 1'b0;
	end else if (wen_m_mode && addr == MSLEEP) begin
		msleep_sleeponblock <= wdata_update[2] && |EXTENSION_XH3POWER;
		msleep_powerdown    <= wdata_update[1] && |EXTENSION_XH3POWER;
		msleep_deepsleep    <= wdata_update[0] && |EXTENSION_XH3POWER;
	end
end

assign pwr_allow_sleep_on_block = msleep_sleeponblock;
assign pwr_allow_power_down = msleep_powerdown;
assign pwr_allow_clkgate = msleep_deepsleep;

// ----------------------------------------------------------------------------
// Counters

reg mcountinhibit_cy;
reg mcountinhibit_ir;

reg [XLEN-1:0] mcycleh;
reg [XLEN-1:0] mcycle;
reg [XLEN-1:0] minstreth;
reg [XLEN-1:0] minstret;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mcycleh <= X0;
		mcycle <= X0;
		minstreth <= X0;
		minstret <= X0;
		// Counters inhibited by default to save energy
		mcountinhibit_cy <= 1'b1;
		mcountinhibit_ir <= 1'b1;
	end else begin
		if (!(mcountinhibit_cy || debug_mode))
			{mcycleh, mcycle} <= ({mcycleh, mcycle} + 1'b1) & {2*XLEN{|CSR_COUNTER}};
		if (!(mcountinhibit_ir || debug_mode) && instr_ret)
			{minstreth, minstret} <= ({minstreth, minstret} + 1'b1) & {2*XLEN{|CSR_COUNTER}};
		if (wen_m_mode) begin
			if (addr == MCYCLEH)
				mcycleh <= wdata_update & {XLEN{|CSR_COUNTER}};
			if (addr == MCYCLE)
				mcycle <= wdata_update & {XLEN{|CSR_COUNTER}};
			if (addr == MINSTRETH)
				minstreth <= wdata_update & {XLEN{|CSR_COUNTER}};
			if (addr == MINSTRET)
				minstret <= wdata_update & {XLEN{|CSR_COUNTER}};
			if (addr == MCOUNTINHIBIT) begin
				{mcountinhibit_ir, mcountinhibit_cy} <= {wdata_update[2], wdata_update[0]} | {2{~|CSR_COUNTER}};
			end
		end
	end
end

// Note we still implement tm, even though the time/timeh CSRs are
// unimplemented. The tm bit provides a standard way to configure whether
// M-mode software permits the trapped access to reach the timer registers.
// (This is in fact required by the RVM-CSI platform spec.)
reg mcounteren_cy;
reg mcounteren_tm;
reg mcounteren_ir;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mcounteren_cy <= 1'b0;
		mcounteren_tm <= 1'b0;
		mcounteren_ir <= 1'b0;
	end else if (wen_m_mode && addr == MCOUNTEREN) begin
		mcounteren_cy <= wdata_update[0] && |CSR_COUNTER && |U_MODE;
		mcounteren_tm <= wdata_update[1] && |CSR_COUNTER && |U_MODE;
		mcounteren_ir <= wdata_update[2] && |CSR_COUNTER && |U_MODE;
	end
end

// ----------------------------------------------------------------------------
// Debug-mode CSRs

// The following DCSR bits are read/writable as normal:
// - ebreakm (bit 15)
// - ebreaku (bit 12) if U-mode is supported
// - step (bit 2)
// The following are read-only volatile:
// - cause (bits 8:6)
// All others are hardwired constants.

reg dcsr_ebreakm;
reg dcsr_ebreaku;
reg dcsr_step;
reg [2:0] dcsr_cause;
wire [2:0] dcause_next;

localparam DCSR_CAUSE_EBREAK  = 3'h1;
localparam DCSR_CAUSE_TRIGGER = 3'h2;
localparam DCSR_CAUSE_HALTREQ = 3'h3;
localparam DCSR_CAUSE_STEP    = 3'h4;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		dcsr_ebreakm <= 1'b0;
		dcsr_ebreaku <= 1'b0;
		dcsr_step <= 1'b0;
		dcsr_cause <= 3'h0;
	end else begin
		// Note we can use the ungated write enable in debug mode since a CSR
		// write to a valid D-mode CSR address is guaranteed not to generate
		// an exception (of any kind, including PMP) in D-mode.
		if (debug_mode && wen_raw && addr == DCSR) begin
			{dcsr_ebreakm, dcsr_ebreaku, dcsr_step} <= {
				wdata_update[15],
				wdata_update[12] && U_MODE,
				wdata_update[2]
			} & {3{|DEBUG_SUPPORT}};
		end
		if (enter_debug_mode) begin
			dcsr_cause <= dcause_next & {3{|DEBUG_SUPPORT}};
		end
	end
end

// DPC is mapped to the real PC in the decode module. We set it to the
// exception return address when entering Debug Mode, and whilst in Debug
// Mode we can write to it as though it were a CSR. Note only IALIGN'd values
// can be written to dpc.
assign debug_dpc_wdata = (debug_mode ? wdata_update           : mepc_in) & (~X0 << 2 - EXTENSION_C);
assign debug_dpc_wen   =  debug_mode ? wen_raw && addr == DPC : enter_debug_mode;

// Debug Module's data0 register is mapped into the core's CSR space:
assign dbg_data0_wdata = wdata;
assign dbg_data0_wen = debug_mode && wen_raw && addr == DMDATA0;

reg tcontrol_mte;
reg tcontrol_mpte;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		tcontrol_mpte <= 1'b0;
		tcontrol_mte <= 1'b0;
	end else if (wen_m_mode && addr == TCONTROL) begin
		tcontrol_mpte <= wdata_update[7] && DEBUG_SUPPORT;
		tcontrol_mte <= wdata_update[3] && DEBUG_SUPPORT;
	end else if (DEBUG_SUPPORT && trapreg_update_enter) begin
		tcontrol_mte <= 1'b0;
		tcontrol_mpte <= tcontrol_mte;
	end else if (DEBUG_SUPPORT && trapreg_update_exit) begin
		tcontrol_mte <= tcontrol_mpte;
		// Unlike mstatus.mie/mpie, tcontrol.mpte is unchanged by trap exit.
	end
end

// ----------------------------------------------------------------------------
// Read port + detect addressing of unmapped CSRs
// ----------------------------------------------------------------------------

reg decode_match;

// Address match conditions -- certain CSRs are inaccessible if their
// conditions are not met:
wire match_drw = DEBUG_SUPPORT && debug_mode;
wire match_mrw = m_mode || debug_mode;
wire match_mro = (m_mode || debug_mode) && !wen_soon;
wire match_urw = U_MODE && 1'b1;
wire match_uro = U_MODE && !wen_soon;

always @ (*) begin
	decode_match = 1'b0;
	rdata = {XLEN{1'b0}};
	pmp_cfg_wen = 1'b0;
	trig_cfg_wen = 1'b0;
	case (addr)

	// ------------------------------------------------------------------------
	// Mandatory CSRs

	MISA: if (CSR_M_MANDATORY) begin
		// WARL, so it is legal to be tied constant
		decode_match = match_mrw;
		rdata = {
			2'h1,              // MXL: 32-bit
			{XLEN-28{1'b0}},   // WLRL

			2'd0,              // Z, Y, no
			|{                 // X is set for any custom extensions
				|EXTENSION_XH3BEXTM,
				|EXTENSION_XH3IRQ,
				|EXTENSION_XH3PMPM,
				|EXTENSION_XH3POWER
			},
			2'd0,              // V, W, no
			|U_MODE,
			7'd0,              // T...N, no
			|EXTENSION_M,
			3'd0,              // L...J, no
			1'b1,              // Integer ISA
			5'd0,              // H...D, no
			|EXTENSION_C,
			1'b0,
			|EXTENSION_A
		};
	end
	MVENDORID: if (CSR_M_MANDATORY) begin
		decode_match = match_mro;
		rdata = MVENDORID_VAL;
	end
	MARCHID: if (CSR_M_MANDATORY) begin
		decode_match = match_mro;
		// Hazard3's open source architecture ID
		rdata = 32'd27;
	end
	MIMPID: if (CSR_M_MANDATORY) begin
		decode_match = match_mro;
		rdata = MIMPID_VAL;
	end
	MHARTID: if (CSR_M_MANDATORY) begin
		decode_match = match_mro;
		rdata = MHARTID_VAL;
	end

	MCONFIGPTR: if (CSR_M_MANDATORY) begin
		decode_match = match_mro;
		rdata = MCONFIGPTR_VAL;
	end

	MSTATUS: if (CSR_M_MANDATORY || CSR_M_TRAP) begin
		decode_match = match_mrw;
		rdata = {
			1'b0,             // Never any dirty state besides GPRs
			8'd0,             // (WPRI)
			1'b0,             // TSR (Trap SRET), tied 0 if no S mode.
			mstatus_tw,       // TW (Timeout Wait)
			1'b0,             // TVM (trap virtual memory), tied 0 if no S mode.
			1'b0,             // MXR (Make eXecutable Readable), tied 0 if no S mode.
			1'b0,             // SUM, tied 0 if no S mode
			mstatus_mprv,     // MPRV (modify privilege)
			4'd0,             // XS, FS always "off" (no extension state to clear!)
			{2{mstatus_mpp}}, // MPP (M-mode previous privilege), only M and U supported
			2'd0,             // (WPRI)
			1'b0,             // SPP, tied 0 if S mode not supported
			mstatus_mpie,     // Previous interrupt enable
			3'd0,             // No S, U
			mstatus_mie,      // Interrupt enable
			3'd0              // No S, U
		};
	end

	// MSTATUSH is all zeroes (fields are MBE and SBE, which are zero because
	// we are pure little-endian.) Prior to priv-1.12 MSTATUSH could be left
	// unimplemented in this case, but now it must be decoded even if
	// hardwired to 0.
	MSTATUSH: if (CSR_M_MANDATORY || CSR_M_TRAP) begin
		decode_match = match_mrw;
	end

	// MEDELEG, MIDELEG should not exist for no-S-mode implementations. Will
	// raise illegal instruction exception if accessed.

	// MENVCFG is seemingly mandatory as of M-mode v1.12, if U-mode is
	// implemented. All of its fields are tied to 0 in our implementation.
	MENVCFGH: if (U_MODE) begin
		decode_match = match_mrw;
	end
	MENVCFG: if (U_MODE) begin
		decode_match = match_mrw;
	end

	// ------------------------------------------------------------------------
	// Trap-handling CSRs

	// This is a 32 bit synthesised register with set/clear/write/read, don't
	// turn it on unless we really have to
	MSCRATCH: if (CSR_M_TRAP && CSR_M_MANDATORY) begin
		decode_match = match_mrw;
		rdata = mscratch;
	end

	MEPC: if (CSR_M_TRAP) begin
		decode_match = match_mrw;
		rdata = mepc;
	end

	MCAUSE: if (CSR_M_TRAP) begin
		decode_match = match_mrw;
		rdata = {
			mcause_irq,      // Sign bit is 1 for IRQ, 0 for exception
			{27{1'b0}},      // Padding
			mcause_code[3:0] // Enough for 16 external IRQs, which is all we have room for in mip/mie
		};
	end

	MTVAL: if (CSR_M_TRAP) begin
		decode_match = match_mrw;
		// Hardwired to 0
	end

	MIE: if (CSR_M_TRAP) begin
		decode_match = match_mrw;
		rdata = mie;
	end

	MIP: if (CSR_M_TRAP) begin
		// Writes are permitted, but ignored.
		decode_match = match_mrw;
		rdata = mip;
	end

	MTVEC: if (CSR_M_TRAP) begin
		decode_match = match_mrw;
		rdata = {
			mtvec[XLEN-1:2],  // BASE
			1'b0,             // Reserved mode bit gets WARL'd to 0
			irq_vector_enable // MODE is vectored (2'h1) or direct (2'h0)
		};
	end

	// ------------------------------------------------------------------------
	// Counter CSRs

	// Get the tied WARLs out the way first
	MHPMCOUNTER3:   if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER4:   if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER5:   if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER6:   if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER7:   if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER8:   if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER9:   if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER10:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER11:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER12:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER13:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER14:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER15:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER16:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER17:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER18:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER19:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER20:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER21:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER22:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER23:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER24:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER25:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER26:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER27:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER28:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER29:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER30:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER31:  if (CSR_COUNTER) begin decode_match = match_mrw; end

	MHPMCOUNTER3H:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER4H:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER5H:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER6H:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER7H:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER8H:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER9H:  if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER10H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER11H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER12H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER13H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER14H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER15H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER16H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER17H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER18H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER19H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER20H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER21H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER22H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER23H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER24H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER25H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER26H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER27H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER28H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER29H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER30H: if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMCOUNTER31H: if (CSR_COUNTER) begin decode_match = match_mrw; end

	MHPMEVENT3:     if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT4:     if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT5:     if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT6:     if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT7:     if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT8:     if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT9:     if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT10:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT11:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT12:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT13:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT14:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT15:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT16:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT17:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT18:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT19:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT20:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT21:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT22:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT23:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT24:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT25:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT26:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT27:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT28:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT29:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT30:    if (CSR_COUNTER) begin decode_match = match_mrw; end
	MHPMEVENT31:    if (CSR_COUNTER) begin decode_match = match_mrw; end

	MCOUNTINHIBIT:  if (CSR_COUNTER) begin
		decode_match = match_mrw;
		rdata = {
			29'd0,
			mcountinhibit_ir,
			1'b0,
			mcountinhibit_cy
		};
	end

	MCYCLE: if (CSR_COUNTER) begin
		decode_match = match_mrw;
		rdata = mcycle;
	end
	MINSTRET: if (CSR_COUNTER) begin
		decode_match = match_mrw;
		rdata = minstret;
	end

	MCYCLEH: if (CSR_COUNTER) begin
		decode_match = match_mrw;
		rdata = mcycleh;
	end
	MINSTRETH: if (CSR_COUNTER) begin
		decode_match = match_mrw;
		rdata = minstreth;
	end

	MCOUNTEREN: if (CSR_COUNTER && U_MODE) begin
		decode_match = match_mrw;
		rdata = {
			29'd0,
			mcounteren_ir,
			mcounteren_tm,
			mcounteren_cy
		};
	end

	// ------------------------------------------------------------------------
	// PMP CSRs (bridge to PMP config interface)

	// If PMP is present, all 16 registers are present, but some may be WARL'd
	// to 0 depending on how many regions are actually implemented.
	PMPCFG0:   if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPCFG1:   if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPCFG2:   if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPCFG3:   if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR0:  if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR1:  if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR2:  if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR3:  if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR4:  if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR5:  if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR6:  if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR7:  if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR8:  if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR9:  if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR10: if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR11: if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR12: if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR13: if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR14: if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end
	PMPADDR15: if (PMP_REGIONS > 0) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end

	// MSECCFG is strictly optional, and we don't implement any of its
	// features (ePMP etc) so we don't decode it.

	// ------------------------------------------------------------------------
	// U-mode CSRs

	// The read-only counters are always visible to M mode, and are visible to
	// U mode if the corresponding mcounteren bit is set.
	CYCLE: if (CSR_COUNTER) begin
		decode_match = mcounteren_cy ? match_uro : match_mro;
		rdata = mcycle;
	end
	CYCLEH: if (CSR_COUNTER) begin
		decode_match = mcounteren_cy ? match_uro : match_mro;
		rdata = mcycleh;
	end

	INSTRET: if (CSR_COUNTER) begin
		decode_match = mcounteren_ir ? match_uro : match_mro;
		rdata = minstret;
	end
	INSTRETH: if (CSR_COUNTER) begin
		decode_match = mcounteren_ir ? match_uro : match_mro;
		rdata = minstreth;
	end

	// ------------------------------------------------------------------------
	// Trigger Module CSRs

	// If triggers aren't supported, we implement tselect as hardwired 0,
	// tinfo as hardwired 1 (meaning type=0 always) and tdata as hardwired 0
	// (meaning type=0). The debugger will see the first trigger as
	// unimplemented, and immediately halt discovery.
	TSELECT: if (DEBUG_SUPPORT) begin
		decode_match = match_mrw;
		if (BREAKPOINT_TRIGGERS > 0) begin
			trig_cfg_wen = match_mrw && wen;
			rdata = trig_cfg_rdata;
		end else begin
			rdata = 32'h00000000;
		end
	end

	TDATA1: if (DEBUG_SUPPORT) begin
		decode_match = match_mrw;
		if (BREAKPOINT_TRIGGERS > 0) begin
			trig_cfg_wen = match_mrw && wen;
			rdata = trig_cfg_rdata;
		end else begin
			rdata = 32'h00000000;
		end
	end

	TDATA2: if (DEBUG_SUPPORT) begin
		decode_match = match_mrw;
		if (BREAKPOINT_TRIGGERS > 0) begin
			trig_cfg_wen = match_mrw && wen;
			rdata = trig_cfg_rdata;
		end else begin
			rdata = 32'h00000000;
		end
	end

	TINFO: if (DEBUG_SUPPORT) begin
		// Note tinfo is a read-write CSR (writes don't trap) even though it
		// is entirely read-only.
		decode_match = match_mrw;
		if (BREAKPOINT_TRIGGERS > 0) begin
			trig_cfg_wen = match_mrw && wen;
			rdata = trig_cfg_rdata;
		end else begin
			rdata = 32'h00000001;
		end
	end

	TCONTROL: if (DEBUG_SUPPORT && BREAKPOINT_TRIGGERS > 0) begin
		decode_match = match_mrw;
		rdata = {
			24'h0,
			tcontrol_mpte,
			3'h0,
			tcontrol_mte,
			3'h0
		};
	end

	// ------------------------------------------------------------------------
	// Debug CSRs

	DCSR: if (DEBUG_SUPPORT) begin
		decode_match = match_drw;
		rdata = {
			4'h4,         // xdebugver = 4, for 0.13.2 debug spec
			12'd0,        // reserved
			dcsr_ebreakm,
			2'h0,         // No mode 2/1
			dcsr_ebreaku,
			1'b0,         // stepie = 0, no interrupts in single-step mode
			1'b1,         // stopcount = 1, no counter increment in debug mode
			1'b1,         // stoptime = 0, no core-local timer increment in debug mode
			dcsr_cause,
			1'b0,         // reserved
			1'b0,         // mprven = 0, debugger always acts as M-mode
			1'b0,         // nmip = 0, we have no NMI
			dcsr_step,
			{2{m_mode}}   // priv = M or U, report the core state directly
		};
	end

	DPC: if (DEBUG_SUPPORT) begin
		decode_match = match_drw;
		rdata = debug_dpc_rdata;
	end

	DMDATA0: if (DEBUG_SUPPORT) begin
		decode_match = match_drw;
		rdata = dbg_data0_rdata;
	end

	// ------------------------------------------------------------------------
	// Custom CSRs

	PMPCFGM0: if (PMP_REGIONS > 0 && EXTENSION_XH3PMPM) begin
		decode_match = match_mrw;
		pmp_cfg_wen = match_mrw && wen;
		rdata = pmp_cfg_rdata;
	end

	MEIEA: if (CSR_M_TRAP && EXTENSION_XH3IRQ) begin
		decode_match = match_mrw;
		rdata = irq_ctrl_rdata;
	end

	MEIPA: if (CSR_M_TRAP && EXTENSION_XH3IRQ) begin
		decode_match = match_mrw;
		rdata = irq_ctrl_rdata;
	end

	MEIFA: if (CSR_M_TRAP && EXTENSION_XH3IRQ) begin
		decode_match = match_mrw;
		rdata = irq_ctrl_rdata;
	end

	MEIPRA: if (CSR_M_TRAP && EXTENSION_XH3IRQ) begin
		decode_match = match_mrw;
		rdata = irq_ctrl_rdata;
	end

	MEINEXT: if (CSR_M_TRAP && EXTENSION_XH3IRQ) begin
		decode_match = match_mrw;
		rdata = irq_ctrl_rdata;
	end

	MEICONTEXT: if (CSR_M_TRAP && EXTENSION_XH3IRQ) begin
		decode_match = match_mrw;
		rdata = irq_ctrl_rdata;
	end

	MSLEEP: if (EXTENSION_XH3POWER) begin
		decode_match = match_mrw;
		rdata = {
			29'h0,
			msleep_sleeponblock,
			msleep_powerdown,
			msleep_deepsleep
		};
	end

	default: begin end
	endcase
end

assign illegal = (wen_soon || ren_soon) && !decode_match;

// ----------------------------------------------------------------------------
// Debug run/halt

// req_resume_prev is to cut an in->out path from request to trap addr.
reg have_just_reset;
reg step_halt_req;
reg dbg_req_resume_prev;
reg dbg_req_halt_prev;
reg dbg_req_halt_on_reset_sticky;
reg pending_dbg_resume_prev;

wire pending_dbg_resume = (pending_dbg_resume_prev || dbg_req_resume_prev) && debug_mode;

// Halt request input register needs to always be clocked, because a WFI needs
// to fall through if the debugger requests halt of a sleeping core.
always @ (posedge clk_always_on or negedge rst_n) begin
	if (!rst_n) begin
		dbg_req_halt_prev <= 1'b0;
	end else begin
		// Just a delayed version of the request from outside of the core.
		// Delay is fine because the DM awaits ack before deasserting.
		dbg_req_halt_prev <= dbg_req_halt && DEBUG_SUPPORT != 0;
	end
end

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		have_just_reset <= |DEBUG_SUPPORT;
		dbg_req_halt_on_reset_sticky <= 1'b0;
		step_halt_req <= 1'b0;
		dbg_req_resume_prev <= 1'b0;
		pending_dbg_resume_prev <= 1'b0;
	end else if (DEBUG_SUPPORT) begin
		have_just_reset <= 1'b0;

		// One-cycle delay on assertion of reset halt req is harmless because
		// of a matching delay on the first instruction fetch (reset_holdoff).
		if (have_just_reset && dbg_req_halt_on_reset) begin
			dbg_req_halt_on_reset_sticky <= 1'b1;
		end else if (enter_debug_mode) begin
			dbg_req_halt_on_reset_sticky <= 1'b0;
		end

		dbg_req_resume_prev <= dbg_req_resume;

		if (debug_mode) begin
			step_halt_req <= 1'b0;
		end else if (dcsr_step && (instr_ret || (trap_enter_vld && trap_enter_rdy))) begin
			// Note exception entry is also considered a step -- in this case
			// we are supposed to take the trap and then break to debug mode
			// before executing the first trap instruction. *IRQ* entry does
			// not occur when step is 1 (because we hardwire dcsr.stepie to 0)
			step_halt_req <= 1'b1;
		end

		pending_dbg_resume_prev <= pending_dbg_resume;
	end
end

// We can enter the halted state in an IRQ-like manner (squeeze in between the
// instructions in stage 2 and stage 3) or in an exception-like manner
// (replace the instruction in stage 3).
//
// Halt request and step-break are IRQ-like. We need to be careful when a halt
// request lines up with an instruction in M which either has generated an
// exception (e.g. an ecall) or may yet generate an exception (a load). In
// this case the correct thing to do is to:
//
// - Squash whatever instruction may be in X, and inhibit X PC increment
// - Wait until after the exception entry is taken (or the load/store
//   completes successfully)
// - Immediately trigger an IRQ-like debug entry.
//
// This ensures the debugger sees mcause/mepc set correctly, with dpc pointing
// to the handler entry point, if the instruction excepts.

wire exception_req_any;
wire halt_delayed_by_exception = exception_req_any || loadstore_dphase_pending;

wire want_halt_except = DEBUG_SUPPORT && !debug_mode && (
	dcsr_ebreakm &&  m_mode && except == EXCEPT_EBREAK ||
	dcsr_ebreaku && !m_mode && except == EXCEPT_EBREAK ||
	except_to_d_mode        && except == EXCEPT_EBREAK
);

// Note exception-like causes (trigger, ebreak) are higher priority than
// IRQ-like.
//
// We must mask halt_req with delay_irq_entry (true on cycle 2 and beyond of
// load/store address phase) because at that point we can't suppress the bus
// access. Others are fine because they are never mid-instruction in stage 2.
wire want_halt_irq_if_no_exception = DEBUG_SUPPORT && !debug_mode && !want_halt_except && (
	(dbg_req_halt_prev && !delay_irq_entry) ||
	dbg_req_halt_on_reset_sticky ||
	step_halt_req
);

// Exception (or potential exception due to load/store) in M delays halt
// entry. The halt intention still blocks X, so we can't get blocked forever
// by a string of load/stores. This is just here to get sequencing between an
// exception (or potential exception) in M, and debug mode entry.
wire want_halt_irq = want_halt_irq_if_no_exception && !halt_delayed_by_exception;

assign dcause_next =
	except == EXCEPT_EBREAK && except_to_d_mode ? 3'h2 : // trigger (priority 4)
	except == EXCEPT_EBREAK                     ? 3'h1 : // ebreak (priority 3)
	dbg_req_halt_prev || dbg_req_halt_on_reset  ? 3'h3 : // halt or reset-halt (priority 1, 2)
	                                              3'h4;  // single-step (priority 0)

assign trap_is_debug_entry = |DEBUG_SUPPORT && !debug_mode && (want_halt_irq || want_halt_except);
assign enter_debug_mode = trap_is_debug_entry && trap_enter_rdy;

assign exit_debug_mode = debug_mode && pending_dbg_resume && trap_enter_rdy;

// Report back to DM instruction injector to tell it its instruction sequence
// has finished (ebreak) or crashed out
assign dbg_instr_caught_ebreak = debug_mode && except == EXCEPT_EBREAK && trap_enter_rdy;

// Note we exclude ebreak from here regardless of dcsr.ebreakm, since we are
// already in debug mode at this point
assign dbg_instr_caught_exception = debug_mode && except != EXCEPT_NONE &&
	except != EXCEPT_EBREAK && trap_enter_rdy;

// ----------------------------------------------------------------------------
// Trap request generation

reg irq_software_r;
reg irq_timer_r;

// Always clocked, as it's used to generate a wakeup.
always @ (posedge clk_always_on or negedge rst_n) begin
	if (!rst_n) begin
		irq_software_r <= 1'b0;
		irq_timer_r <= 1'b0;
	end else begin
		irq_software_r <= irq_software;
		irq_timer_r <= irq_timer;
	end
end

assign mip = {
	20'h0,                // Reserved
	external_irq_pending, // meip, Global pending bit for external IRQs
	3'h0,                 // Reserved
	irq_timer_r,          // mtip, interrupt from memory-mapped timer peripheral
	3'h0,                 // Reserved
	irq_software_r,       // msip, software interrupt from memory-mapped register
	3'h0                  // Reserved
};

wire irq_active = |(mip & mie) && mstatus_mie && !dcsr_step;

// WFI clear respects individual interrupt enables but ignores mstatus.mie.
// Additionally, wfi is treated as a nop during single-stepping and D-mode.
// Note that the IRQs and debug halt request input registers are clocked by
// clk_always_on, so that a wakeup can be generated when asleep. Note also
// that want_halt_irq_if_no_exception can be masked while asleep, so also
// feed in the raw halt request as a wakeup source.
assign pwr_wfi_wakeup_req = |(mip & mie) || dcsr_step || debug_mode ||
	want_halt_irq_if_no_exception || dbg_req_halt_prev;

// Priority order from priv spec: external > software > timer
wire [3:0] standard_irq_num =
	mip[11] && mie[11] ? 4'd11 :
	mip[3]  && mie[3]  ? 4'd3  :
	mip[7]  && mie[7]  ? 4'd7  : 4'd0;

// ebreak may be treated as a halt-to-debugger or a regular M-mode exception,
// depending on dcsr.ebreakm.
assign exception_req_any = except != EXCEPT_NONE && !(
	except == EXCEPT_EBREAK && (m_mode ? dcsr_ebreakm : dcsr_ebreaku)
);

wire [3:0] mcause_irq_num =	irq_active ? standard_irq_num : 4'd0;

wire [3:0] vector_sel =	!exception_req_any && irq_vector_enable ? mcause_irq_num : 4'd0;

assign trap_addr =
	except == EXCEPT_MRET ? mepc             :
	pending_dbg_resume    ? debug_dpc_rdata  : mtvec | {26'h0, vector_sel, 2'h0};

// Check for exception-like or IRQ-like trap entry; any debug mode entry takes
// priority over any regular trap.
assign trap_is_irq = DEBUG_SUPPORT && (want_halt_except || want_halt_irq) ?
	!want_halt_except : !exception_req_any;

// When there is a loadstore dphase pending, we block off the IRQ trap
// request, but still assert the trap_enter_soon flag. This blocks issue of
// further load/stores which have not yet been locked into aphase, so the IRQ
// can eventually go through. It's not safe to enter an IRQ when a dphase is
// in progress, because that dphase could subsequently except, and sample the
// IRQ vector PC instead of the load/store instruction PC.

assign trap_enter_vld =
	CSR_M_TRAP && (exception_req_any ||
		!delay_irq_entry && !debug_mode && irq_active && !loadstore_dphase_pending) ||
	DEBUG_SUPPORT && (
		(!delay_irq_entry && want_halt_irq) || want_halt_except || pending_dbg_resume);

assign trap_enter_soon = trap_enter_vld || (
	|DEBUG_SUPPORT && want_halt_irq_if_no_exception ||
	!delay_irq_entry && !debug_mode && irq_active && loadstore_dphase_pending
);

assign mcause_irq_next = !exception_req_any;
assign mcause_code_next = exception_req_any ? except : mcause_irq_num;

// ----------------------------------------------------------------------------
// Privilege state outputs

assign pmp_cfg_addr = addr;
assign pmp_cfg_wdata = wdata_update;

assign trig_cfg_addr = addr;
assign trig_cfg_wdata = wdata_update;
assign trig_m_en = tcontrol_mte;

// Effective privilege for execution. Used for:
// - Privilege level of branch target fetches (frontend keeps fetch privilege
//   constant during sequential fetch)
// - Checking PC against PMP execute permission

assign m_mode_execution = !U_MODE || debug_mode || m_mode;

// Effective privilege for trap entry. Used for:
// - Privilege level of trap target fetches (frontend keeps fetch privilege
//   constant during sequential fetch)

assign m_mode_trap_entry = !U_MODE || (
	except == EXCEPT_MRET ? mstatus_mpp : 1'b1
);

// Effective privilege for load/stores. Used for:
// - Privilege level of load/stores on the bus
// - Checking load/stores against PMP read/write permission

assign m_mode_loadstore = !U_MODE || debug_mode || (
	mstatus_mprv ? mstatus_mpp : m_mode
);

// ----------------------------------------------------------------------------
// Properties

`ifdef HAZARD3_ASSERTIONS

// Keep track of whether we are in a trap (only for formal property purposes)
reg in_trap;

always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		in_trap <= 1'b0;
	else
		in_trap <= (in_trap || (trap_enter_vld && trap_enter_rdy))
			&& !(trap_enter_vld && trap_enter_rdy && except == EXCEPT_MRET);

always @ (posedge clk) begin
`ifdef RISCV_FORMAL
	// Assume there are no nested exceptions, to stop riscv-formal from doing
	// annoying things like stopping instructions from retiring by repeatedly
	// feeding in invalid instructions
	if (in_trap)
		assume(except == EXCEPT_NONE || except == EXCEPT_MRET);

	// Note the actual IRQ registers have been moved into hazard3_irq_ctrl
	// (and are now optional) so repeat them here for the property
	reg [NUM_IRQS-1:0] irq_r;
	always @ (posedge clk_always_on or negedge rst_n) begin
		if (!rst_n) begin
			irq_r <= {NUM_IRQS{1'b0}};
		end else begin
			irq_r <= irq;
		end
	end

	// Assume IRQs are not deasserted on cycles where exception entry does not
	// take place
	if (!trap_enter_rdy)
		assume(~|(irq_r & ~irq));
`endif

	// Make sure CSR accesses are flushed
	if (trap_enter_vld && trap_enter_rdy)
		assert(!(wen || ren));

	// Writing to CSR on cycle after trap entry -- should be impossible, a CSR
	// access instruction should have been flushed or moved down to stage 3, and
	// no fetch could have arrived by now
	if ($past(trap_enter_vld && trap_enter_rdy))
		assert(!wen);

	// Should be impossible to get into the trap and exit immediately:
	if (in_trap && !$past(in_trap))
		assert(except != EXCEPT_MRET);

	// Should be impossible to get to another mret so soon after exiting:
	if ($past(except == EXCEPT_MRET && trap_enter_vld && trap_enter_rdy))
		assert(except != EXCEPT_MRET);

	// Must be impossible to enter two traps on consecutive cycles. Most importantly:
	//
	// - IRQ -> Except: no new instruction could have been fetched by this point,
	//   and an exception by e.g. a left-behind store data phase would sample the
	//   wrong PC.
	//
	// - Except -> IRQ: would need to re-set mstatus.mie first, shouldn't happen
	//
	// Sole exclusion is mret. We can return from an interrupt/exception and take
	// a new interrupt on the next cycle.

	if ($past(trap_enter_vld && trap_enter_rdy && except != EXCEPT_MRET))
		assert(!(trap_enter_vld && trap_enter_rdy));

	// Just to stress that this is the the only case:
	if (trap_enter_vld && trap_enter_rdy && $past(trap_enter_vld && trap_enter_rdy))
		assert($past(except == EXCEPT_MRET));

	if (rst_n && $past(trap_enter_vld && !trap_enter_rdy && !trap_is_irq)) begin
		// Exception which didn't go through should not disappear
		assert(trap_enter_vld);
		// Exception should not be replaced by IRQ
		assert(!trap_is_irq);
	end

	// This must be a breakpoint exception (presumably from the trigger unit).
	if (except_to_d_mode) begin
		assert(except == EXCEPT_EBREAK);
	end

	// Exceptions should squash load/stores before they reach dphase.
	if (except != EXCEPT_NONE && !(except == EXCEPT_LOAD_FAULT || except == EXCEPT_STORE_FAULT)) begin
		assert(!loadstore_dphase_pending);
	end

	// Debug entries are trap entries! (we should also assert in core.v that
	// trap entries are never coincident with active load/store address
	// phases, which gives some confidence that debug entry does not gobble
	// load/stores.)
	if (enter_debug_mode) begin
		assert(trap_enter_vld);
	end
end

`endif

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
