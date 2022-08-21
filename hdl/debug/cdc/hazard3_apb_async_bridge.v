/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// APB-to-APB asynchronous bridge for connecting DTM to DM, in case DTM is in
// a different clock domain (e.g. running directly from crystal to get a
// fixed baud reference)
//
// Note this module depends on the hazard3_sync_1bit module (a flop-chain
// synchroniser) which should be reimplemented for your FPGA/process.

`ifndef HAZARD3_REG_KEEP_ATTRIBUTE
`define HAZARD3_REG_KEEP_ATTRIBUTE (* keep = 1'b1 *)
`endif

`default_nettype none

module hazard3_apb_async_bridge #(
    parameter W_ADDR = 8,
    parameter W_DATA = 32,
    parameter N_SYNC_STAGES = 2
) (
    // Resets assumed to be synchronised externally
    input wire               clk_src,
    input wire               rst_n_src,

    input wire               clk_dst,
    input wire               rst_n_dst,

    // APB port from Transport Module
    input  wire              src_psel,
    input  wire              src_penable,
    input  wire              src_pwrite,
    input  wire [W_ADDR-1:0] src_paddr,
    input  wire [W_DATA-1:0] src_pwdata,
    output wire [W_DATA-1:0] src_prdata,
    output wire              src_pready,
    output wire              src_pslverr,

    // APB port to Debug Module
    output wire              dst_psel,
    output wire              dst_penable,
    output wire              dst_pwrite,
    output wire [W_ADDR-1:0] dst_paddr,
    output wire [W_DATA-1:0] dst_pwdata,
    input  wire [W_DATA-1:0] dst_prdata,
    input  wire              dst_pready,
    input  wire              dst_pslverr
);

// ----------------------------------------------------------------------------
// Clock-crossing registers

// We're using a modified req/ack handshake:
//
// - Initially both req and ack are low
// - src asserts req high
// - dst responds with ack high and begins transfer
// - src deasserts req once it sees ack high
// - dst deasserts ack once:
//     - transfer is complete *and*
//     - dst sees req deasserted
// - Once src sees ack low, a new transfer can begin.
//
// A NRZI toggle handshake might be more appropriate, but can cause spurious
// bus accesses when only one side of the link is reset.

`HAZARD3_REG_KEEP_ATTRIBUTE reg                            src_req;
wire                                                       dst_req;

`HAZARD3_REG_KEEP_ATTRIBUTE reg                            dst_ack;
wire                                                       src_ack;

// Note the launch registers are not resettable. We maintain setup/hold on
// launch-to-capture paths thanks to the req/ack handshake. A stray reset
// could violate this.
//
// The req/ack logic itself can be reset safely because the receiving domain
// is protected from metastability by a 2FF synchroniser.

`HAZARD3_REG_KEEP_ATTRIBUTE reg [W_ADDR + W_DATA + 1 -1:0] src_paddr_pwdata_pwrite; // launch
`HAZARD3_REG_KEEP_ATTRIBUTE reg [W_ADDR + W_DATA + 1 -1:0] dst_paddr_pwdata_pwrite; // capture

`HAZARD3_REG_KEEP_ATTRIBUTE reg [W_DATA + 1 -1:0]          dst_prdata_pslverr;      // launch
`HAZARD3_REG_KEEP_ATTRIBUTE reg [W_DATA + 1 -1:0]          src_prdata_pslverr;      // capture

hazard3_sync_1bit #(
    .N_STAGES (N_SYNC_STAGES)
) sync_req (
    .clk   (clk_dst),
    .rst_n (rst_n_dst),
    .i     (src_req),
    .o     (dst_req)
);

hazard3_sync_1bit #(
    .N_STAGES (N_SYNC_STAGES)
) sync_ack (
    .clk   (clk_src),
    .rst_n (rst_n_src),
    .i     (dst_ack),
    .o     (src_ack)
);

// ----------------------------------------------------------------------------
// src state machine

reg src_waiting_for_downstream;
reg src_pready_r;

always @ (posedge clk_src or negedge rst_n_src) begin
    if (!rst_n_src) begin
        src_req <= 1'b0;
        src_waiting_for_downstream <= 1'b0;
        src_prdata_pslverr <= {W_DATA + 1{1'b0}};
        src_pready_r <= 1'b1;
    end else if (src_waiting_for_downstream) begin
        if (src_req && src_ack) begin
            // Request was acknowledged, so deassert.
            src_req <= 1'b0;
        end else if (!(src_req || src_ack)) begin
            // Downstream transfer has finished, data is valid.
            src_pready_r <= 1'b1;
            src_waiting_for_downstream <= 1'b0;
            // Note this assignment is cross-domain (but data has been stable
            // for duration of ack synchronisation delay):
            src_prdata_pslverr <= dst_prdata_pslverr;
        end
    end else begin
        // paddr, pwdata and pwrite are all valid during the setup phase, and
        // APB defines the setup phase to always last one cycle and proceed
        // to access phase. So, we can ignore penable, and pready is ignored.
        if (src_psel) begin
            src_pready_r <= 1'b0;
            src_req <= 1'b1;
            src_waiting_for_downstream <= 1'b1;
        end
    end
end

// Bus request launch register is not resettable
always @ (posedge clk_src) begin
    if (src_psel && !src_waiting_for_downstream)
        src_paddr_pwdata_pwrite <= {src_paddr, src_pwdata, src_pwrite};
end

assign {src_prdata, src_pslverr} = src_prdata_pslverr;
assign src_pready = src_pready_r;

// ----------------------------------------------------------------------------
// dst state machine

wire dst_bus_finish = dst_penable && dst_pready;
reg dst_psel_r;
reg dst_penable_r;

always @ (posedge clk_dst or negedge rst_n_dst) begin
    if (!rst_n_dst) begin
        dst_ack <= 1'b0;
    end else if (dst_req) begin
        dst_ack <= 1'b1;
    end else if (!dst_req && dst_ack && !dst_psel_r) begin
        dst_ack <= 1'b0;
    end
end

always @ (posedge clk_dst or negedge rst_n_dst) begin
    if (!rst_n_dst) begin
        dst_psel_r <= 1'b0;
        dst_penable_r <= 1'b0;
    end else if (dst_req && !dst_ack) begin
        dst_psel_r <= 1'b1;
        // Note this assignment is cross-domain. The src register has been
        // stable for the duration of the req sync delay.
        dst_paddr_pwdata_pwrite <= src_paddr_pwdata_pwrite;
    end else if (dst_psel_r && !dst_penable_r) begin
        dst_penable_r <= 1'b1;
    end else if (dst_bus_finish) begin
        dst_psel_r <= 1'b0;
        dst_penable_r <= 1'b0;
    end
end

// Bus response launch register is not resettable
always @ (posedge clk_dst) begin
    if (dst_bus_finish)
        dst_prdata_pslverr <= {dst_prdata, dst_pslverr};
end

assign dst_psel = dst_psel_r;
assign dst_penable = dst_penable_r;
assign {dst_paddr, dst_pwdata, dst_pwrite} = dst_paddr_pwdata_pwrite;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
