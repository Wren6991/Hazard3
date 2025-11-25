/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Register file
// Single write port, dual read port

`default_nettype none

module hazard3_regfile_1w2r #(
`include "hazard3_config.vh"
) (
	input wire clk,
	input wire rst_n,

	input wire [4:0]        raddr1,
	output reg [W_DATA-1:0] rdata1,

	input wire [4:0]        raddr2,
	output reg [W_DATA-1:0] rdata2,

	input wire [4:0]        waddr,
	input wire [W_DATA-1:0] wdata,
	input wire              wen
);

localparam N_REGS = EXTENSION_E == 0 ? 32 : 16;

wire [31:0] reg_q [0:N_REGS-1];

wire [N_REGS-1:0] wen_mask = {{N_REGS{1'b0}}, 1'b1} << waddr[$clog2(N_REGS)-1:0];

// Active-low enable in second half of clock cycle (note half-cycle path
// through wen_mask into E; not suitable for systems where HREADY is late)
wire [N_REGS-1:0] latch_enable_n;
gf180mcu_fd_sc_mcu9t5v0__icgtn_4 clkgate_u [N_REGS-1:0] (
	.TE   (1'b0),
	.E    (wen_mask),
	.CLKN (clk),
	.Q    (latch_enable_n)
);

// Write data passes transparently through latches to be registered in output
// flops at the end of the cycle
assign reg_q[0] = 32'd0;
genvar g;
generate
for (g = 1; g < N_REGS; g = g + 1) begin: loop_g
	wire [31:0] latch_q;
	gf180mcu_fd_sc_mcu9t5v0__latq_1 reg_u [31:0] (
		.D (wdata),
		.E (!latch_enable_n[g]),
		.Q (latch_q)
	);
	assign reg_q[g] = latch_q;
end
endgenerate

// Combinatorial mux of latch outputs
wire [31:0] rdata1_nxt = reg_q[raddr1[$clog2(N_REGS)-1:0]];
wire [31:0] rdata2_nxt = reg_q[raddr2[$clog2(N_REGS)-1:0]];

// Present read data to next stage
always @ (posedge clk) begin
	rdata1 <= rdata1_nxt;
	rdata2 <= rdata2_nxt;
end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
