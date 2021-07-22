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

// The ECP5 JTAGG primitive (yes that is the correct spelling) allows you to
// add two custom DRs to the FPGA's chip TAP, selected using the 8-bit ER1
// (0x32) and ER2 (0x38) instructions.
//
// Brian Swetland pointed out on Twitter that the standard RISC-V JTAG-DTM
// only uses two DRs (DTMCS and DMI), besides the standard IDCODE and BYPASS
// whic. This file instantiates the guts of Hazard3's standard JTAG-DTM and
// connects the DTMCS and DMI registers to the JTAGG primitive's ER1/ER2 DRs.
//
// The exciting part is that upstream OpenOCD already allows you to set the IR
// length *and* set custom DTMCS/DMI IR values for RISC-V JTAG DTMs. This
// means with the right config file, you can access a debug module hung from
// the ECP5 TAP in this fashion using only upstream OpenOCD and gdb.

`default_nettype none

module hazard3_ecp5_jtag_dtm #(
    parameter DTMCS_IDLE_HINT = 3'd4,
    parameter W_ADDR = 8
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
    output wire [W_ADDR-1:0]  dmi_paddr,
    output wire [31:0]        dmi_pwdata,
    input  wire [31:0]        dmi_prdata,
    input  wire               dmi_pready,
    input  wire               dmi_pslverr
);

// Signals to/from the ECP5 TAP

wire jtdo2;
wire jtdo1;
wire jtdi;
wire jtck;
wire jrti2;
wire jrti1;
wire jshift;
wire jupdate;
wire jrst_n;
wire jce2;
wire jce1;

JTAGG jtag_u (
    .JTDO2   (jtdo2),
    .JTDO1   (jtdo1),
    .JTDI    (jtdi),
    .JTCK    (jtck),
    .JRTI2   (jrti2),
    .JRTI1   (jrti1),
    .JSHIFT  (jshift),
    .JUPDATE (jupdate),
    .JRSTN   (jrst_n),
    .JCE2    (jce2),
    .JCE1    (jce1)
);

localparam W_DR_SHIFT = W_ADDR + 32 + 2;

wire                  core_dr_wen;
wire                  core_dr_ren;
wire                  core_dr_sel_dmi_ndtmcs;
wire [W_DR_SHIFT-1:0] core_dr_wdata;
wire [W_DR_SHIFT-1:0] core_dr_rdata;

// We would like to know at all times which DR is selected. Unfortunately
// JTAGG does not tell us this. Instead:
//
// - During run test/idle, jrti1/jrti2 is asserted if IR matches ER1/ER2
//
// - During CAPTURE OR SHIFT, jce1/jce2 is asserted if IR matches ER1/ER2
//
// There is no signal that is valid during UPDATE. So we make our own:

reg dr_sel_prev;
assign core_dr_sel_dmi_ndtmcs = jce1 ? 1'b0 : jce2 ? 1'b1 : dr_sel_prev;

always @ (posedge jtck or negedge jrst_n) begin
    if (!jrst_n) begin
        dr_sel_prev <= 1'b0;
    end else begin
        dr_sel_prev <= core_dr_sel_dmi_ndtmcs;
    end
end

// This is equivalent to "in capture DR state and IR is ER1 or ER2"
assign core_dr_ren = (jce1 || jce2) && !jshift;

assign core_dr_wen = jupdate;

// Our DR shifter is made much more complex by the flop inserted by JTAGG
// between TDI and JTDI, which we have no control of. Say we have a total DR
// shift length of 42 (8 addr 32 data 2 op, in DMI) and first consider just
// SHIFT -> UPDATE:
//
// - After 42 SHIFT clocks, the 42nd data bit will be in the JTDI register
//
// - When we UPDATE, the write data must be the concatenation of the JTDI
//   register and a 41 bit shift register which follows JTDI
//
// As we shift, JTDI plus 41 other flops form our 42 bit shift register. So
// far, mostly normal. The problem is that when we CAPTURE, we can't put the
// 42nd data bit into the JTDI register, because we have no control of it. We
// can't have a chain of 42 FPGA flops, because then our total scan length
// appears from the outside to be 43 bits. So the trick is:
//
// - The frontmost flop in the 42-bit scan is usually JTDI, but we have an
//   additional shadow flop that is used on the first SHIFT cycle after
//   CAPTURE
//
// - CAPTURE loads rdata into the shadow flop and the 41 regular shift flops
//
// - The first SHIFT clock drops the shifter LSB (which was previously on
//   TDO), clocks the shadow flop down into the 41st position (which would
//   normally take data from JTDI), and JTDI is swapped back in place of the
//   shadow flop for UPDATE purposes
//
// - We are now in steady-state SHIFT.
//
// So before/after the first SHIFT clock the notional 42-bit register is
// {capture[41:0]} -> {JTDI reg, capture[41:1]} Where capture[41] is
// initially stored in the shadow flop, and then passes on to flop 40 of the
// main shift register. (we don't support zero-bit SHIFT, who cares!)
//
// Ok maybe that was a longwinded explanation but this really confused the
// shit out of me, so this is a gift for future Luke or other readers


reg                  dr_shift_head;
reg [W_DR_SHIFT-2:0] dr_shift_tail;
reg                  use_shift_head;

assign core_dr_wdata = core_dr_sel_dmi_ndtmcs ? {jtdi, dr_shift_tail} :
    {{W_DR_SHIFT-32{1'b0}}, jtdi, dr_shift_tail[30:0]};

always @ (posedge jtck or negedge jrst_n) begin
    if (!jrst_n) begin
        dr_shift_head <= 1'b0;
        dr_shift_tail <= {W_DR_SHIFT-1{1'b0}};
        use_shift_head <= 1'b0;
    end else if (core_dr_ren) begin
        use_shift_head <= 1'b1;
        {dr_shift_head, dr_shift_tail} <= core_dr_rdata;
    end else begin
        use_shift_head <= 1'b0;
        dr_shift_tail <= {
            use_shift_head ? dr_shift_head : jtdi,
            dr_shift_tail
        } >> 1;
        if (!core_dr_sel_dmi_ndtmcs)
            dr_shift_tail[30] <= jtdi;
    end
end

// We have only a single shifter for the ER1 and ER2 chains, so these are tied
// together:

reg shift_tail_neg;

always @ (negedge jtck or negedge jrst_n) begin
    if (!jrst_n) begin
        shift_tail_neg <= 1'b0;
    end else begin
        shift_tail_neg <= dr_shift_tail[0];
    end
end

assign jtdo1 = shift_tail_neg;
assign jtdo2 = shift_tail_neg;

// The actual DTM is in here:

// hazard3_jtag_dtm_core #(
//     .DTMCS_IDLE_HINT(DTMCS_IDLE_HINT),
//     .W_ADDR(W_ADDR),
//     .W_DR_SHIFT(W_DR_SHIFT)
// ) inst_hazard3_jtag_dtm_core (
//     .tck               (tck),
//     .trst_n            (trst_n),
//     .clk_dmi           (clk_dmi),
//     .rst_n_dmi         (rst_n_dmi),

//     .dr_wen            (core_dr_wen),
//     .dr_ren            (core_dr_ren),
//     .dr_sel_dmi_ndtmcs (core_dr_sel_dmi_ndtmcs),
//     .dr_wdata          (core_dr_wdata),
//     .dr_rdata          (core_dr_rdata),

//     .dmihardreset_req  (dmihardreset_req),

//     .dmi_psel          (dmi_psel),
//     .dmi_penable       (dmi_penable),
//     .dmi_pwrite        (dmi_pwrite),
//     .dmi_paddr         (dmi_paddr),
//     .dmi_pwdata        (dmi_pwdata),
//     .dmi_prdata        (dmi_prdata),
//     .dmi_pready        (dmi_pready),
//     .dmi_pslverr       (dmi_pslverr)
// );

assign core_dr_rdata = 42'h555555550;

endmodule
