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
localparam W_RNUM = $clog2(N_REGS);

`ifdef GF180MCU

// Process-specific cells

wire [31:0] reg_q [0:N_REGS-1];

wire [N_REGS-1:0] wen_mask = {{N_REGS{1'b0}}, 1'b1} << waddr[W_RNUM-1:0];

assign reg_q[0] = 32'd0;
genvar g;
generate
for (g = 1; g < N_REGS; g = g + 1) begin: loop_g
	wire [31:0] reg_q_;
	// Use scan flop to replace missing DFFE. Constraints should disable false
	// hold check on Q->D path (Q is stable when D is selected).
	gf180mcu_fd_sc_mcu9t5v0__sdffq_1 reg_u [31:0] (
		.CLK (clk),
		.D   (reg_q_),
		.Q   (reg_q_),
		.SI  (wdata),
		.SE  (wen_mask[g])
	);
	assign reg_q[g] = wen_mask[g] ? wdata : reg_q_;
end
endgenerate

// Combinatorial mux of register outputs
wire [31:0] rdata1_nxt_l = reg_q[{1'b0, raddr1[W_RNUM-2:0]}];
wire [31:0] rdata1_nxt_h = reg_q[{1'b1, raddr1[W_RNUM-2:0]}];

wire [31:0] rdata2_nxt_l = reg_q[{1'b0, raddr2[W_RNUM-2:0]}];
wire [31:0] rdata2_nxt_h = reg_q[{1'b1, raddr2[W_RNUM-2:0]}];

// Use scan flop for final mux level and to present data to next stage

wire [31:0] rdata1_q;
wire [31:0] rdata2_q;

gf180mcu_fd_sc_mcu9t5v0__sdffq_4 flop_rdata1_u [31:0] (
	.CLK (clk),
	.D   (rdata1_nxt_l),
	.SI  (rdata1_nxt_h),
	.SE  (raddr1[W_RNUM-1]),
	.Q   (rdata1_q)
);

gf180mcu_fd_sc_mcu9t5v0__sdffq_4 flop_rdata2_u [31:0] (
	.CLK (clk),
	.D   (rdata2_nxt_l),
	.SI  (rdata2_nxt_h),
	.SE  (raddr2[W_RNUM-1]),
	.Q   (rdata2_q)
);

always @ (*) begin
	rdata1 = rdata1_q;
	rdata2 = rdata2_q;
end

`else

// Behavioural model (synthesisable) for transparent-write register file

reg [31:0] reg_q [0:N_REGS-1];

always @ (posedge clk) begin
	if (wen) begin
		reg_q[waddr[W_RNUM-1:0]] <= wdata;
	end
	reg_q[0] <= 32'd0;
	if (wen && |waddr && waddr[W_RNUM-1:0] == raddr1[W_RNUM-1:0]) begin
		rdata1 <= wdata;
	end else begin
		rdata1 <= reg_q[raddr1[W_RNUM-1:0]];
	end
	if (wen && |waddr && waddr[W_RNUM-1:0] == raddr2[W_RNUM-1:0]) begin
		rdata2 <= wdata;
	end else begin
		rdata2 <= reg_q[raddr2[W_RNUM-1:0]];
	end
end

`endif

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
