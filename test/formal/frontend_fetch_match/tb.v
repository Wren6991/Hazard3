// Instantiate frontend. Generate bus responses where data is a known function
// of addresses. Attach a dummy program counter which either increments
// sequentially or follows jump requests asserted to the frontend.
//
// Assert that CIR is always equal to mem[PC].
//
// This is similar to the instruction_fetch_match testcase, but struggles less
// with depth because only the frontend is present. This testcase also places
// fewer constraints (i.e. ones implicit in the processor) on the frontend,
// so may chase out some latent bugs.

`default_nettype none

module tb #(
`include "hazard3_config.vh"
);

reg clk;
reg rst_n = 1'b0;
always @ (posedge clk)
	rst_n <= 1'b1;

// ----------------------------------------------------------------------------
// DUT

(*keep*) wire              mem_size;
(*keep*) wire [31:0]       mem_addr;
(*keep*) wire              mem_priv;
(*keep*) wire              mem_addr_vld;
(*keep*) wire              mem_addr_rdy;
(*keep*) wire [31:0]       mem_data;
(*keep*) wire              mem_data_err;
(*keep*) wire              mem_data_vld;

(*keep*) wire [31:0]       jump_target;
(*keep*) wire              jump_priv;
(*keep*) wire              jump_target_vld;
(*keep*) wire              jump_target_rdy;

(*keep*) wire [31:0]       cir;
(*keep*) wire [1:0]        cir_vld;
(*keep*) wire [1:0]        cir_use;
(*keep*) wire [1:0]        cir_err;
(*keep*) reg               cir_lock;

(*keep*) wire [4:0]        predecode_rs1_coarse;
(*keep*) wire [4:0]        predecode_rs2_coarse;
(*keep*) wire [4:0]        predecode_rs1_fine;
(*keep*) wire [4:0]        predecode_rs2_fine;

(*keep*) wire              debug_mode;
(*keep*) wire [31:0]       dbg_instr_data;
(*keep*) wire              dbg_instr_data_vld;
(*keep*) wire              dbg_instr_data_rdy;


hazard3_frontend #(
`include "hazard3_config_inst.vh"
) dut (
	.clk                  (clk),
	.rst_n                (rst_n),

	.mem_size             (mem_size),
	.mem_addr             (mem_addr),
	.mem_priv             (mem_priv),
	.mem_addr_vld         (mem_addr_vld),
	.mem_addr_rdy         (mem_addr_rdy),
	.mem_data             (mem_data),
	.mem_data_err         (mem_data_err),
	.mem_data_vld         (mem_data_vld),

	.jump_target          (jump_target),
	.jump_priv            (jump_priv),
	.jump_target_vld      (jump_target_vld),
	.jump_target_rdy      (jump_target_rdy),

	.cir                  (cir),
	.cir_vld              (cir_vld),
	.cir_use              (cir_use),
	.cir_err              (cir_err),
	.cir_lock             (cir_lock),

	.predecode_rs1_coarse (predecode_rs1_coarse),
	.predecode_rs2_coarse (predecode_rs2_coarse),
	.predecode_rs1_fine   (predecode_rs1_fine),
	.predecode_rs2_fine   (predecode_rs2_fine),

	.debug_mode           (debug_mode),
	.dbg_instr_data       (dbg_instr_data),
	.dbg_instr_data_vld   (dbg_instr_data_vld),
	.dbg_instr_data_rdy   (dbg_instr_data_rdy)
);

// ----------------------------------------------------------------------------
// Constraints

// TODO this only covers the possibilities of the 2-port processor:

(*keep*) wire        hready;
(*keep*) reg  [31:0] haddr_dphase;
(*keep*) reg         htrans_vld_dphase;

assign mem_addr_rdy = hready;
assign mem_data_vld = hready && htrans_vld_dphase;

assign mem_data = htrans_vld_dphase && hready ? {
	haddr_dphase[16:2], 1'b1,
	haddr_dphase[16:2], 1'b0
} : 32'h0;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		haddr_dphase <= 32'h0;
		htrans_vld_dphase <= 1'b0;
	end else if (hready) begin
		htrans_vld_dphase <= mem_addr_vld;
		if (mem_addr_vld) begin
			haddr_dphase <= mem_addr;
		end
	end
end

assign cir_lock = 1'b0; // TODO
assign debug_mode = 1'b0;
assign dbg_instr_data_vld = 1'b0;

always assume(cir_use <= cir_vld);

assign jump_target[0] = 1'b0;

// Jump should not be asserted on the first cycle after reset, as this *will*
// change the fetch address and screw things up. We don't check this in
// hardware (as it's assumed to be impossible in the real processor), just
// assert on it inside the frontend.
always @ (posedge clk) assume(!(jump_target_vld && !$past(rst_n)));


// ----------------------------------------------------------------------------
// Properties

reg [31:0] pc;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		pc <= RESET_VECTOR;
	end else if (jump_target_vld && jump_target_rdy) begin
		pc <= jump_target;
	end else begin
		pc <= pc + {cir_use, 1'b0};
	end
end

always @ (posedge clk) if (rst_n) begin
	// Sanity check
	assert(cir_vld < 2'd3);
	// Instruction data the frontend claims is valid must match the data in
	// memory at the corresponding address.
	if (cir_vld >= 2'd1) begin
		assert(cir[15:0] == pc[16:1]);
	end
	if (cir_vld >= 2'd2) begin
		assert(cir[31:16] == pc[16:1] + 16'd1);
	end
end

endmodule