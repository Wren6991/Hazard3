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


// I don't even O_O

wire [31:0] imm_ci = {{7{instr_in[12]}}, instr_in[6:2], {20{1'b0}}};

wire [31:0] imm_cj = {instr_in[12], instr_in[8], instr_in[10:9], instr_in[6], instr_in[7],
	instr_in[2], instr_in[11], instr_in[5:3], {9{instr_in[12]}}, {12{1'b0}}};

wire [31:0] imm_cb =
	{{20{1'b0}}, instr_in[11:10], instr_in[4:3], instr_in[12], {7{1'b0}}} |
	{{4{instr_in[12]}}, instr_in[6:5], instr_in[2], {25{1'b0}}};

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
			RV_C_ADDI4SPN: instr_out = RV_NOZ_ADDI | ({27'h0, rd_s} << RV_RD_LSB) | (5'h2 << RV_RS1_LSB)
				| ({instr_in[10:7], instr_in[12:11], instr_in[5], instr_in[6], 2'b00} << 20);
			RV_C_LW:       instr_out = RV_NOZ_LW | ({27'h0, rd_s} << RV_RD_LSB) | (rs1_s << RV_RS1_LSB)
				| ({instr_in[5], instr_in[12:10], instr_in[6], 2'b00} << 20);
			RV_C_SW:       instr_out = RV_NOZ_SW | (rs2_s << RV_RS2_LSB) | (rs1_s << RV_RS1_LSB)
				| ({instr_in[11:10], instr_in[6], 2'b00} << 7) | ({instr_in[5], instr_in[12]} << 25);
			RV_C_ADDI:     instr_out = RV_NOZ_ADDI | (rd_l << RV_RD_LSB) | (rs1_l << RV_RS1_LSB) | imm_ci;
			RV_C_JAL:      instr_out = RV_NOZ_JAL | (5'h1 << RV_RD_LSB) | imm_cj;
			RV_C_J:        instr_out = RV_NOZ_JAL | (5'h0 << RV_RD_LSB) | imm_cj;
			RV_C_LI:       instr_out = RV_NOZ_ADDI | (rd_l << RV_RD_LSB) | imm_ci;
			RV_C_LUI: begin
				if (rd_l == 5'h2) begin
					// addi6sp
					instr_out = RV_NOZ_ADDI | (5'h2 << RV_RD_LSB) | (5'h2 << RV_RS1_LSB) |
						({{3{instr_in[12]}}, instr_in[4:3], instr_in[5], instr_in[2], instr_in[6]} << 24);
				end else begin
					instr_out = RV_NOZ_LUI | (rd_l << RV_RD_LSB) | ({{15{instr_in[12]}}, instr_in[6:2]} << 12);
				end
				invalid = ~|{instr_in[12], instr_in[6:2]}; // RESERVED if imm == 0
			end
			RV_C_SLLI:     instr_out = RV_NOZ_SLLI | (rs1_l << RV_RD_LSB) | (rs1_l << RV_RS1_LSB) | imm_ci;
			RV_C_SRAI:     instr_out = RV_NOZ_SRAI | (rs1_s << RV_RD_LSB) | (rs1_s << RV_RS1_LSB) | imm_ci;
			RV_C_SRLI:     instr_out = RV_NOZ_SRLI | (rs1_s << RV_RD_LSB) | (rs1_s << RV_RS1_LSB) | imm_ci;
			RV_C_ANDI:     instr_out = RV_NOZ_ANDI | (rs1_s << RV_RD_LSB) | (rs1_s << RV_RS1_LSB) | imm_ci;
			RV_C_AND:      instr_out = RV_NOZ_AND  | (rs1_s << RV_RD_LSB) | (rs1_s << RV_RS1_LSB) | (rs2_s << RV_RS2_LSB);
			RV_C_OR:       instr_out = RV_NOZ_OR   | (rs1_s << RV_RD_LSB) | (rs1_s << RV_RS1_LSB) | (rs2_s << RV_RS2_LSB);
			RV_C_XOR:      instr_out = RV_NOZ_XOR  | (rs1_s << RV_RD_LSB) | (rs1_s << RV_RS1_LSB) | (rs2_s << RV_RS2_LSB);
			RV_C_SUB:      instr_out = RV_NOZ_SUB  | (rs1_s << RV_RD_LSB) | (rs1_s << RV_RS1_LSB) | (rs2_s << RV_RS2_LSB);
			RV_C_ADD: begin
				if (|rs2_l) begin
					instr_out = RV_NOZ_ADD | (rd_l << RV_RD_LSB) | (rs1_l << RV_RS1_LSB) | (rs2_l << RV_RS2_LSB);
				end else if (|rs1_l) begin // jalr
					instr_out = RV_NOZ_JALR | (5'h1 << RV_RD_LSB) | (rs1_l << RV_RS1_LSB);
				end else begin // ebreak
					instr_out = RV_NOZ_EBREAK;
				end
			end
			RV_C_MV: begin
				if (|rs2_l) begin // mv
					instr_out = RV_NOZ_ADD | (rd_l << RV_RD_LSB) | (rs2_l << RV_RS2_LSB);
				end else begin // jr
					instr_out = RV_NOZ_JALR | (rs1_l << RV_RS1_LSB);
					invalid = ~|rs1_l; // RESERVED
				end
			end
			RV_C_LWSP: begin
				instr_out = RV_NOZ_LW | (rd_l << RV_RD_LSB) | (5'h2 << RV_RS1_LSB)
				| ({instr_in[3:2], instr_in[12], instr_in[6:4], 2'b00} << 20);
				invalid = ~|rd_l; // RESERVED
			end
			RV_C_SWSP:    instr_out = RV_NOZ_SW | (rs2_l << RV_RS2_LSB) | (5'h2 << RV_RS1_LSB)
				| ({instr_in[11:9], 2'b00} << 7) | ({instr_in[8:7], instr_in[12]} << 25);
			RV_C_BEQZ:     instr_out = RV_NOZ_BEQ | (rs1_s << RV_RS1_LSB) | imm_cb;
			RV_C_BNEZ:     instr_out = RV_NOZ_BNE | (rs1_s << RV_RS1_LSB) | imm_cb;
			default: invalid = 1'b1;
			endcase
		end
	end
end
endgenerate

endmodule

`default_nettype wire
