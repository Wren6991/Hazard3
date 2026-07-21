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

localparam       N_REGS      = EXTENSION_E == 0 ? 32 : 16;
localparam [4:0] REGNUM_MASK = {~|EXTENSION_E, 4'hf};

wire [4:0] raddr1_masked = raddr1 & REGNUM_MASK;
wire [4:0] raddr2_masked = raddr2 & REGNUM_MASK;
wire [4:0] waddr_masked  = waddr  & REGNUM_MASK;

generate
if (RESET_REGFILE) begin: real_dualport_reset
	// This will presumably always be implemented with flops
	reg [W_DATA-1:0] mem [0:N_REGS-1];

	always @ (posedge clk or negedge rst_n) begin: reg_ports
		integer i;
		if (!rst_n) begin
			for (i = 0; i < N_REGS; i = i + 1) begin
				mem[i] <= {W_DATA{1'b0}};
			end
			rdata1 <= {W_DATA{1'b0}};
			rdata2 <= {W_DATA{1'b0}};
		end else begin
			if (wen) begin
				mem[waddr_masked] <= wdata;
			end
			rdata1 <= mem[raddr1_masked];
			rdata2 <= mem[raddr2_masked];
		end
	end
end else begin: real_dualport_noreset
	// This should be inference-compatible on FPGAs with dual-port (or 1R1W) BRAMs
	`ifdef YOSYS
	`ifdef FPGA_ICE40
	// We do not require write-to-read bypass logic on the BRAM
	(* no_rw_check *)
	`endif
	`endif
	// Optionally force use of distributed RAM on Xilinx for better timing
	`ifdef HAZARD3_REGFILE_RAM_STYLE_DISTRIBUTED
	(* ram_style = "distributed" *)
	`endif
	reg [W_DATA-1:0] mem [0:N_REGS-1];

	always @ (posedge clk) begin
		if (wen) begin
			mem[waddr_masked] <= wdata;
		end
		rdata1 <= mem[raddr1_masked];
		rdata2 <= mem[raddr2_masked];
	end
end
endgenerate

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
