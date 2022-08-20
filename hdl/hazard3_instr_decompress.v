/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module hazard3_instr_decompress #(
	parameter PASSTHROUGH = 0
) (
	input wire [31:0] instr_in,
	output reg instr_is_32bit,
	output reg [31:0] instr_out,
	output reg invalid
);

`include "rv_opcodes.vh"

localparam W_REGADDR = 5;

// Long-register formats: cr, ci, css
// Short-register formats: ciw, cl, cs, cb, cj
wire [W_REGADDR-1:0] rd_l  = instr_in[11:7];
wire [W_REGADDR-1:0] rs1_l = instr_in[11:7];
wire [W_REGADDR-1:0] rs2_l = instr_in[6:2];
wire [W_REGADDR-1:0] rd_s  = {2'b01, instr_in[4:2]};
wire [W_REGADDR-1:0] rs1_s = {2'b01, instr_in[9:7]};
wire [W_REGADDR-1:0] rs2_s = {2'b01, instr_in[4:2]};

// Mapping of cx -> x immediate formats (we are *expanding* instructions, not
// decoding them):

wire [31:0] imm_ci = {
	{7{instr_in[12]}},
	instr_in[6:2],
	20'h00000
};

wire [31:0] imm_cj = {
	instr_in[12],
	instr_in[8],
	instr_in[10:9],
	instr_in[6],
	instr_in[7],
	instr_in[2],
	instr_in[11],
	instr_in[5:3],
	{9{instr_in[12]}},
	12'h000
};

wire [31:0] imm_cb ={
	{4{instr_in[12]}},
	instr_in[6:5],
	instr_in[2],
	13'h0000,
	instr_in[11:10],
	instr_in[4:3],
	instr_in[12],
	7'h00
};

function [31:0] rfmt_rd;  input [4:0] rd;  begin rfmt_rd  = {20'h00000, rd, 7'h00};   end endfunction
function [31:0] rfmt_rs1; input [4:0] rs1; begin rfmt_rs1 = {12'h000, rs1, 15'h0000}; end endfunction
function [31:0] rfmt_rs2; input [4:0] rs2; begin rfmt_rs2 = {7'h00, rs2, 20'h00000};  end endfunction

generate
if (PASSTHROUGH) begin: instr_passthrough
	always @ (*) begin
		instr_is_32bit = 1'b1;
		instr_out = instr_in;
		invalid = 1'b0;
	end
end else begin: instr_decompress
	always @ (*) begin
		if (instr_in[1:0] == 2'b11) begin
			instr_is_32bit = 1'b1;
			instr_out = instr_in;
			invalid = 1'b0;
		end else begin
			instr_is_32bit = 1'b0;
			instr_out = 32'h0;
			invalid = 1'b0;
			casez (instr_in[15:0])
			16'h0:         invalid = 1'b1;
			RV_C_ADDI4SPN: instr_out = RV_NOZ_ADDI | rfmt_rd(rd_s) | rfmt_rs1(5'h2)
				| {2'h0, instr_in[10:7], instr_in[12:11], instr_in[5], instr_in[6], 2'b00, 20'h00000};
			RV_C_LW:       instr_out = RV_NOZ_LW | rfmt_rd(rd_s) | rfmt_rs1(rs1_s)
				| {6'h00, instr_in[5], instr_in[12:10], instr_in[6], 2'b00, 20'h00000};
			RV_C_SW:       instr_out = RV_NOZ_SW | rfmt_rs2(rs2_s) | rfmt_rs1(rs1_s)
				| {5'h00, instr_in[5], instr_in[12], 13'h000, instr_in[11:10], instr_in[6], 2'b00, 7'h00};
			RV_C_ADDI:     instr_out = RV_NOZ_ADDI | rfmt_rd(rd_l) | rfmt_rs1(rs1_l) | imm_ci;
			RV_C_JAL:      instr_out = RV_NOZ_JAL  | rfmt_rd(5'h1) | imm_cj;
			RV_C_J:        instr_out = RV_NOZ_JAL  | rfmt_rd(5'h0) | imm_cj;
			RV_C_LI:       instr_out = RV_NOZ_ADDI | rfmt_rd(rd_l) | imm_ci;
			RV_C_LUI: begin
				if (rd_l == 5'h2) begin
					// addi16sp
					instr_out = RV_NOZ_ADDI | rfmt_rd(5'h2) | rfmt_rs1(5'h2) |
						{{3{instr_in[12]}}, instr_in[4:3], instr_in[5], instr_in[2], instr_in[6], 24'h000000};
				end else begin
					instr_out = RV_NOZ_LUI | rfmt_rd(rd_l) | {{15{instr_in[12]}}, instr_in[6:2], 12'h000};
				end
				invalid = ~|{instr_in[12], instr_in[6:2]}; // RESERVED if imm == 0
			end
			RV_C_SLLI:     instr_out = RV_NOZ_SLLI | rfmt_rd(rs1_l) | rfmt_rs1(rs1_l) | imm_ci;
			RV_C_SRAI:     instr_out = RV_NOZ_SRAI | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | imm_ci;
			RV_C_SRLI:     instr_out = RV_NOZ_SRLI | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | imm_ci;
			RV_C_ANDI:     instr_out = RV_NOZ_ANDI | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | imm_ci;
			RV_C_AND:      instr_out = RV_NOZ_AND  | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | rfmt_rs2(rs2_s);
			RV_C_OR:       instr_out = RV_NOZ_OR   | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | rfmt_rs2(rs2_s);
			RV_C_XOR:      instr_out = RV_NOZ_XOR  | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | rfmt_rs2(rs2_s);
			RV_C_SUB:      instr_out = RV_NOZ_SUB  | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | rfmt_rs2(rs2_s);
			RV_C_ADD: begin
				if (|rs2_l) begin
					instr_out = RV_NOZ_ADD | rfmt_rd(rd_l) | rfmt_rs1(rs1_l) | rfmt_rs2(rs2_l);
				end else if (|rs1_l) begin // jalr
					instr_out = RV_NOZ_JALR | rfmt_rd(5'h1) | rfmt_rs1(rs1_l);
				end else begin // ebreak
					instr_out = RV_NOZ_EBREAK;
				end
			end
			RV_C_MV: begin
				if (|rs2_l) begin // mv
					instr_out = RV_NOZ_ADD | rfmt_rd(rd_l) | rfmt_rs2(rs2_l);
				end else begin // jr
					instr_out = RV_NOZ_JALR | rfmt_rs1(rs1_l);
					invalid = ~|rs1_l; // RESERVED
				end
			end
			RV_C_LWSP: begin
				instr_out = RV_NOZ_LW | rfmt_rd(rd_l) | rfmt_rs1(5'h2) |
					{4'h0, instr_in[3:2], instr_in[12], instr_in[6:4], 2'b00, 20'h00000};
				invalid = ~|rd_l; // RESERVED
			end
			RV_C_SWSP:    instr_out = RV_NOZ_SW | rfmt_rs2(rs2_l) | rfmt_rs1(5'h2)
				| {4'h0, instr_in[8:7], instr_in[12], 13'h0000, instr_in[11:9], 2'b00, 7'h00};
			RV_C_BEQZ:     instr_out = RV_NOZ_BEQ | rfmt_rs1(rs1_s) | imm_cb;
			RV_C_BNEZ:     instr_out = RV_NOZ_BNE | rfmt_rs1(rs1_s) | imm_cb;
			default: invalid = 1'b1;
			endcase
		end
	end
end
endgenerate

endmodule

`default_nettype wire
