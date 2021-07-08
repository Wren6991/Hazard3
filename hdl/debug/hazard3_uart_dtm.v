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

// UART Debug Transport Module: connect an external two-wire 1 Mbaud UART
// interface to an APB Debug Module port.
//
// This is not suitable for production systems (it's a UART...) but is a
// simple way to get your FPGA board up and running.

module hazard3_uart_dtm #(
    // Expected to run at 1 Mbaud from some fixed reference frequency.
    parameter BAUD_CLKDIV = 12,
    parameter W_BAUDCTR = $clog2(BAUD_CLKDIV) // do not modify
) (
    input  wire        clk,
    input  wire        rst_n,

    // External UART interface
    input  wire        rx,
    output wire        tx,

    // APB port to Debug Module
    output wire        psel,
    output wire        penable,
    output wire        pwrite,
    output wire [7:0]  paddr,
    output wire [31:0] pwdata,
    input  wire [31:0] prdata,
    input  wire        pready,
    input  wire        pslverr
);

// ----------------------------------------------------------------------------
// Serial interface

wire [7:0] tx_wdata;
wire       tx_wvld;
wire       tx_wrdy;
wire [7:0] tx_rdata;
wire       tx_rvld;
wire       tx_rrdy = 1'b1;

wire [7:0] rx_wdata;
wire       rx_wvld;
wire       rx_wrdy;
wire [7:0] rx_rdata;
wire       rx_rvld;
wire       rx_rrdy;

hazard3_uart_dtm_fifo #(
    .WIDTH(8),
    .LOG_DEPTH(2)
) tx_fifo (
    .clk   (clk),
    .rst_n (rst_n),
    .wdata (tx_wdata),
    .wvld  (tx_wvld),
    .wrdy  (tx_wrdy),
    .rdata (tx_rdata),
    .rvld  (tx_rvld),
    .rrdy  (tx_rrdy)
);

hazard3_uart_dtm_fifo #(
    .WIDTH(8),
    .LOG_DEPTH(2)
) rx_fifo (
    .clk   (clk),
    .rst_n (rst_n),
    .wdata (rx_wdata),
    .wvld  (rx_wvld),
    .wrdy  (rx_wrdy),
    .rdata (rx_rdata),
    .rvld  (rx_rvld),
    .rrdy  (rx_rrdy)
);


reg [W_BAUDCTR-1:0] tx_baudctr;
reg [9:0] tx_shiftreg;
reg [3:0] tx_shiftctr;

assign tx_rrdy = ~|tx_shiftctr;
assign tx = tx_shiftreg[0];

always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_baudctr <= {W_BAUDCTR{1'b0}};
        tx_shiftreg <= 10'h3ff;
        tx_shiftctr <= 4'd0;
    end else if (tx_rvld && tx_rrdy) begin
        tx_baudctr <= BAUD_CLKDIV - 1;
        tx_shiftreg <= {1'b1, tx_rdata, 1'b0};
        tx_shiftctr <= 4'd10;
    end else if (|tx_baudctr) begin
        tx_baudctr <= tx_baudctr - 1'b1;
    end else if (|tx_shiftctr) begin
        tx_baudctr <= BAUD_CLKDIV - 1;
        tx_shiftreg <= {1'b1, tx_shiftreg[9:1]};
        tx_shiftctr <= tx_shiftctr - 1'b1;
    end
end

wire rx_sync;
hazard3_sync_1bit #(
    .N_STAGES (2)
) sync_req (
    .clk   (clk),
    .rst_n (rst_n),
    .i     (rx),
    .o     (rx_sync)
);

reg [W_BAUDCTR-1:0] rx_baudctr;
reg [7:0] rx_shiftreg;
reg [3:0] rx_shiftctr;

// Only push if the frame ends with a valid stop bit:
assign rx_wvld = ~|rx_baudctr && rx_shiftctr == 4'd1 && rx_sync;
assign rx_wdata = rx_shiftreg;

always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_baudctr <= {W_BAUDCTR{1'b0}};
        rx_shiftreg <= 8'h00;
        rx_shiftctr <= 4'd0;
    end else if (~|rx_shiftctr && ~|rx_baudctr && !rx_sync) begin
        rx_shiftctr <= 4'd10;
        // Start with half-period to get sampling alignment
        rx_baudctr <= (BAUD_CLKDIV - 1) / 2;
    end else if (|rx_baudctr) begin
        rx_baudctr <= rx_baudctr - 1'b1;
    end else if (|rx_shiftctr) begin
        rx_baudctr <= BAUD_CLKDIV - 1;
        rx_shiftctr <= rx_shiftctr - 1'b1;
         if (rx_shiftctr != 4'd1 && rx_shiftctr != 4'd10)
             rx_shiftreg <= {rx_sync, rx_shiftreg[7:1]};
    end
end

// ----------------------------------------------------------------------------
// Command state machine

localparam W_STATE = 5;

localparam [W_STATE-1:0] S_IDLE0   = 5'd0;
localparam [W_STATE-1:0] S_IDLE1   = 5'd1;
localparam [W_STATE-1:0] S_IDLE2   = 5'd2;
localparam [W_STATE-1:0] S_IDLE3   = 5'd3;

localparam [W_STATE-1:0] S_CMD     = 5'd4;

localparam [W_STATE-1:0] S_WADDR   = 5'd5;
localparam [W_STATE-1:0] S_WDATA0  = 5'd6;
localparam [W_STATE-1:0] S_WDATA1  = 5'd7;
localparam [W_STATE-1:0] S_WDATA2  = 5'd8;
localparam [W_STATE-1:0] S_WDATA3  = 5'd9;
localparam [W_STATE-1:0] S_WSETUP  = 5'd10;
localparam [W_STATE-1:0] S_WACCESS = 5'd11;

localparam [W_STATE-1:0] S_RADDR   = 5'd12;
localparam [W_STATE-1:0] S_RSETUP  = 5'd13;
localparam [W_STATE-1:0] S_RACCESS = 5'd14;
localparam [W_STATE-1:0] S_RDATA0  = 5'd15;
localparam [W_STATE-1:0] S_RDATA1  = 5'd16;
localparam [W_STATE-1:0] S_RDATA2  = 5'd17;
localparam [W_STATE-1:0] S_RDATA3  = 5'd18;

localparam CMD_NOP = 8'h00;
localparam CMD_READ = 8'h01;
localparam CMD_WRITE = 8'h02;
localparam CMD_RETURN_TO_IDLE = 8'ha5;

reg [W_STATE-1:0] state;
reg [7:0]         dm_addr;
reg [31:0]        dm_data;



always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE0;
        dm_addr <= 8'h0;
        dm_data <= 32'h0;
    end else case (state)
        S_IDLE0:  if (rx_rvld) state <= rx_rdata == "S" ? S_IDLE1 : S_IDLE0;
        S_IDLE1:  if (rx_rvld) state <= rx_rdata == "U" ? S_IDLE2 : S_IDLE0;
        S_IDLE2:  if (rx_rvld) state <= rx_rdata == "P" ? S_IDLE3 : S_IDLE0;
        S_IDLE3:  if (rx_rvld) state <= rx_rdata == "?" ? S_CMD   : S_IDLE0;
        S_CMD:    if (rx_rvld) begin
            if (rx_rdata == CMD_READ)
                state <= S_RADDR;
            else if (rx_rdata == CMD_WRITE)
                state <= S_WADDR;
            else if (rx_rdata == CMD_RETURN_TO_IDLE)
                state <= S_IDLE0;
            // NOP or invalid leave DTM in command state.
        end

        S_WADDR:  if (rx_rvld) begin
            state <= S_WDATA0;
            dm_addr <= rx_rdata;
        end
        S_WDATA0: if (rx_rvld) begin
            state <= S_WDATA1;
            dm_data <= {rx_rdata, dm_data[31:8]};
        end
        S_WDATA1: if (rx_rvld) begin
            state <= S_WDATA2;
            dm_data <= {rx_rdata, dm_data[31:8]};
        end
        S_WDATA2: if (rx_rvld) begin
            state <= S_WDATA3;
            dm_data <= {rx_rdata, dm_data[31:8]};
        end
        S_WDATA3: if (rx_rvld) begin
            state <= S_WSETUP;
            dm_data <= {rx_rdata, dm_data[31:8]};
        end
        S_WSETUP: state <= S_WACCESS;
        S_WACCESS: if (pready) state <= S_CMD;

        S_RADDR:  if (rx_rvld) begin
            state <= S_RSETUP;
            dm_addr <= rx_rdata;
        end
        S_RSETUP: state <= S_RACCESS;
        S_RACCESS: if (pready) begin
            dm_data <= prdata;
            state <= S_RDATA0;
        end
        S_RDATA0: if (tx_wrdy) begin
            dm_data <= {rx_rdata, dm_data[31:8]};
            state <= S_RDATA1;
        end
        S_RDATA1: if (tx_wrdy) begin
            dm_data <= {rx_rdata, dm_data[31:8]};
            state <= S_RDATA2;
        end
        S_RDATA2: if (tx_wrdy) begin
            dm_data <= {rx_rdata, dm_data[31:8]};
            state <= S_RDATA3;
        end
        S_RDATA3: if (tx_wrdy) begin
            dm_data <= {rx_rdata, dm_data[31:8]};
            state <= S_CMD;
        end

    endcase
end

// ----------------------------------------------------------------------------
// Bus & FIFO hookup

wire state_is_idle =
    state == S_IDLE0 ||
    state == S_IDLE1 ||
    state == S_IDLE2 ||
    state == S_IDLE3;

wire state_is_wdata =
    state == S_WDATA0 ||
    state == S_WDATA1 ||
    state == S_WDATA2 ||
    state == S_WDATA3;

wire state_is_rdata =
    state == S_RDATA0 ||
    state == S_RDATA1 ||
    state == S_RDATA2 ||
    state == S_RDATA3;

// Note we don't consume the read padding bytes during the read data phase --
// these are actually interpreted as NOPs preceding the next command.
// (They are still important for bus pacing though.)
assign rx_rrdy =
    state_is_idle ||
    state == S_CMD ||
    state == S_WADDR ||
    state == S_RADDR ||
    state_is_wdata;

assign tx_wdata = state_is_wdata ? rx_rdata : dm_data[7:0];
assign tx_wvld = (state_is_wdata && state_is_wdata) || state_is_rdata;

assign psel =
    state == S_WSETUP ||
    state == S_WACCESS ||
    state == S_RSETUP ||
    state == S_RACCESS;

assign penable =
    state == S_WACCESS ||
    state == S_RACCESS;

assign pwrite =
    state == S_WSETUP ||
    state == S_WACCESS;

assign paddr = dm_addr;
assign pwdata = dm_data;

endmodule
