// This file is included at the bottom of hazard3_core.v to provide internal
// assertions. Here we are:
//
// - Attaching a memory with arbitrary constant contents to the instruction
//   fetch port
// - Asserting that, when CIR is valid, CIR contents matches the memory value
//   at PC

localparam MEM_SIZE_BYTES = 64;

reg [31:0] instr_mem [0:MEM_SIZE_BYTES-1];
reg [31:0] garbage;

always @ (*) begin: constrain_mem_const
	integer i;
	for (i = 0; i < MEM_SIZE_BYTES / 4; i = i + 1)
		assume(instr_mem[i] == $anyconst);
end

reg        dph_i_active;
reg [2:0]  dph_i_size;
reg [31:0] dph_i_addr;
reg [31:0] dph_rdata_unmasked;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		dph_i_active <= 1'b0;
		dph_i_size <= 3'd0;
		dph_i_addr <= 32'h0;
		dph_rdata_unmasked <= 32'h0;
	end else if (bus_aph_ready_i) begin
		dph_i_active <= bus_aph_req_i;
		dph_i_size <= bus_hsize_i;
		dph_i_addr <= bus_haddr_i;
		if (bus_haddr_i < MEM_SIZE_BYTES)
			dph_rdata_unmasked <= instr_mem[bus_haddr_i / 4];
		else
			dph_rdata_unmasked <= garbage;
	end
end

always @ (*) begin: connect_rdata
	integer i;
	for (i = 0; i < 4; i = i + 1) begin
		if (bus_dph_ready_i && i >= (dph_i_addr & 32'h3) && i < (dph_i_addr & 32'h3) + (32'd1 << dph_i_size))
			assume(bus_rdata_i[i * 8 +: 8] == dph_rdata_unmasked[i * 8 +: 8]);
		else
			assume(bus_rdata_i == 8'h0);
	end
end

always assume(d_pc < MEM_SIZE_BYTES);


wire [31:0] expect_cir;
assign expect_cir[15:0 ] = instr_mem[ d_pc      / 4] >> (d_pc[1] ? 16 : 0 );
assign expect_cir[31:16] = instr_mem[(d_pc + 2) / 4] >> (d_pc[1] ? 0  : 16);

// Note we can get a mismatch in the upper halfword during a CIR lock of a
// jump in the lower halfword -- the fetch will tumble into the top and this
// is fine as long as we correctly update the PC when the lock clears.
wire allow_upper_half_mismatch = fd_cir[15:0] == expect_cir[15:0] && fd_cir[1:0] != 2'b11;

always @ (posedge clk) if (rst_n) begin
	if (fd_cir_vld >= 2'd1)
		assert(fd_cir[15:0] == expect_cir[15:0]);
	if (fd_cir_vld >= 2'd2 && d_pc <= MEM_SIZE_BYTES - 4 && !allow_upper_half_mismatch)
		assert(fd_cir[31:16] == expect_cir[31:16]);
end


