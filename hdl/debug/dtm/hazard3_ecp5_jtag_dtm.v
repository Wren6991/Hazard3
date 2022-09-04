/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// The ECP5 JTAGG primitive (yes that is the correct spelling) allows you to
// add two custom DRs to the FPGA's chip TAP, selected using the 8-bit ER1
// (0x32) and ER2 (0x38) instructions.
//
// Brian Swetland pointed out on Twitter that the standard RISC-V JTAG-DTM
// only uses two DRs (DTMCS and DMI), besides the standard IDCODE and BYPASS
// which are provided already by the ECP5 TAP. This file instantiates the
// guts of Hazard3's standard JTAG-DTM and connects the DTMCS and DMI
// registers to the JTAGG primitive's ER1/ER2 DRs.
//
// The exciting part is that upstream OpenOCD already allows you to set the IR
// length *and* set custom DTMCS/DMI IR values for RISC-V JTAG DTMs. This
// means with the right config file, you can access a debug module hung from
// the ECP5 TAP in this fashion using only upstream OpenOCD and gdb.

`default_nettype none

module hazard3_ecp5_jtag_dtm #(
    parameter DTMCS_IDLE_HINT = 3'd4,
    parameter W_PADDR         = 9,
    parameter ABITS           = W_PADDR - 2 // do not modify
) (
    // This is synchronous to TCK and asserted for one TCK cycle only
    output wire               dmihardreset_req,

    // Bus clock + reset for Debug Module Interface
    input  wire               clk_dmi,
    input  wire               rst_n_dmi,

    // Debug Module Interface (APB)
    output wire               dmi_psel,
    output wire               dmi_penable,
    output wire               dmi_pwrite,
    output wire [W_PADDR-1:0] dmi_paddr,
    output wire [31:0]        dmi_pwdata,
    input  wire [31:0]        dmi_prdata,
    input  wire               dmi_pready,
    input  wire               dmi_pslverr
);

// Signals to/from the ECP5 TAP

wire jtdo2;
wire jtdo1;
wire jtdi;
wire jtck_posedge_dont_use;
wire jshift;
wire jupdate;
wire jrst_n;
wire jce2;
wire jce1;

JTAGG jtag_u (
    .JTDO2   (jtdo2),
    .JTDO1   (jtdo1),
    .JTDI    (jtdi),
    .JTCK    (jtck_posedge_dont_use),
    .JRTI2   (/* unused */),
    .JRTI1   (/* unused */),
    .JSHIFT  (jshift),
    .JUPDATE (jupdate),
    .JRSTN   (jrst_n),
    .JCE2    (jce2),
    .JCE1    (jce1)
);

// JTAGG primitive asserts its signals synchronously to JTCK's posedge, but
// you get weird and inconsistent results if you try to consume them
// synchronously on JTCK's posedge, possibly due to a lack of hold
// constraints in nextpnr.
//
// A quick hack is to move the sampling onto the negedge of the clock. This
// then creates more problems because we would be running our shift logic on
// a different edge from the control + CDC logic in the DTM core.
//
// So, even worse hack, move all our JTAG-domain logic onto the negedge
// (or near enough) by inverting the clock.

wire jtck = !jtck_posedge_dont_use;

localparam W_DR_SHIFT = ABITS + 32 + 2;

reg                   core_dr_wen;
reg                   core_dr_ren;
reg                   core_dr_sel_dmi_ndtmcs;
reg                   dr_shift_en;
wire [W_DR_SHIFT-1:0] core_dr_wdata;
wire [W_DR_SHIFT-1:0] core_dr_rdata;

// Decode our shift controls from the interesting ECP5 ones, and re-register
// onto JTCK negedge (our posedge). Note without re-registering we observe
// them a half-cycle (effectively one cycle) too early. This is another
// consequence of the stupid JTDI thing

always @ (posedge jtck or negedge jrst_n) begin
    if (!jrst_n) begin
        core_dr_sel_dmi_ndtmcs <= 1'b0;
        core_dr_wen <= 1'b0;
        core_dr_ren <= 1'b0;
        dr_shift_en <= 1'b0;
    end else begin
        if (jce1 || jce2)
            core_dr_sel_dmi_ndtmcs <= jce2;
        core_dr_ren <= (jce1 || jce2) && !jshift;
        core_dr_wen <= jupdate;
        dr_shift_en <= jshift;
    end
end

reg [W_DR_SHIFT-1:0] dr_shift;
assign core_dr_wdata = dr_shift;

always @ (posedge jtck or negedge jrst_n) begin
    if (!jrst_n) begin
        dr_shift <= {W_DR_SHIFT{1'b0}};
    end else if (core_dr_ren) begin
        dr_shift <= core_dr_rdata;
    end else if (dr_shift_en) begin
        dr_shift <= {jtdi, dr_shift} >> 1'b1;
        if (!core_dr_sel_dmi_ndtmcs)
            dr_shift[31] <= jtdi;
    end
end

// Not documented on ECP5: as well as the posedge flop on JTDI, the ECP5 puts
// a negedge flop on JTDO1, JTDO2. (Conjecture based on dicking around with a
// logic analyser.) To get JTDOx to appear with the same timing as our shifter
// LSB (which we update on every JTCK negedge) we:
//
// - Register the LSB of the *next* value of dr_shift on the JTCK posedge, so
//   half a cycle earlier than the actual dr_shift update
//
// - This then gets re-registered with the pointless JTDO negedge flops, so
//   that it appears with the same timing as our DR shifter update.

reg dr_shift_next_halfcycle;
always @ (negedge jtck or negedge jrst_n) begin
    if (!jrst_n) begin
        dr_shift_next_halfcycle <= 1'b0;
    end else  begin
        dr_shift_next_halfcycle <=
            core_dr_ren ? core_dr_rdata[0] :
            dr_shift_en ? dr_shift[1]      : dr_shift[0];
    end
end

// We have only a single shifter for the ER1 and ER2 chains, so these are tied
// together:

assign jtdo1 = dr_shift_next_halfcycle;
assign jtdo2 = dr_shift_next_halfcycle;

// The actual DTM is in here:

hazard3_jtag_dtm_core #(
    .DTMCS_IDLE_HINT (DTMCS_IDLE_HINT),
    .W_ADDR          (ABITS)
) inst_hazard3_jtag_dtm_core (
    .tck               (jtck),
    .trst_n            (jrst_n),

    .clk_dmi           (clk_dmi),
    .rst_n_dmi         (rst_n_dmi),

    .dr_wen            (core_dr_wen),
    .dr_ren            (core_dr_ren),
    .dr_sel_dmi_ndtmcs (core_dr_sel_dmi_ndtmcs),
    .dr_wdata          (core_dr_wdata),
    .dr_rdata          (core_dr_rdata),

    .dmihardreset_req  (dmihardreset_req),

    .dmi_psel          (dmi_psel),
    .dmi_penable       (dmi_penable),
    .dmi_pwrite        (dmi_pwrite),
    .dmi_paddr         (dmi_paddr[W_PADDR-1:2]),
    .dmi_pwdata        (dmi_pwdata),
    .dmi_prdata        (dmi_prdata),
    .dmi_pready        (dmi_pready),
    .dmi_pslverr       (dmi_pslverr)
);

assign dmi_paddr[1:0] = 2'b00;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
