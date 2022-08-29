// Assume bus responses are well-formed, assert that bus requests are
// well-formed.

module tb;

reg clk;
reg rst_n = 1'b0;
always @ (posedge clk)
	rst_n <= 1'b1;

// ----------------------------------------------------------------------------
// DUT

(* keep *) wire              pwrup_req;
(* keep *) wire              pwrup_ack;
(* keep *) wire              clk_en;
(* keep *) wire              unblock_out;
(* keep *) wire              unblock_in;

(* keep *) wire [31:0]       haddr;
(* keep *) wire              hwrite;
(* keep *) wire              hexcl;
(* keep *) wire [1:0]        htrans;
(* keep *) wire [2:0]        hsize;
(* keep *) wire [2:0]        hburst;
(* keep *) wire [3:0]        hprot;
(* keep *) wire              hmastlock;
(* keep *) wire              hready;
(* keep *) wire              hexokay;
(* keep *) wire              hresp;
(* keep *) wire [31:0]       hwdata;
(* keep *) wire [31:0]       hrdata;

localparam W_DATA = 32;

(* keep *) wire              dbg_req_halt;
(* keep *) wire              dbg_req_halt_on_reset;
(* keep *) wire              dbg_req_resume;
(* keep *) wire              dbg_halted;
(* keep *) wire              dbg_running;
(* keep *) wire [W_DATA-1:0] dbg_data0_rdata;
(* keep *) wire [W_DATA-1:0] dbg_data0_wdata;
(* keep *) wire              dbg_data0_wen;
(* keep *) wire [W_DATA-1:0] dbg_instr_data;
(* keep *) wire              dbg_instr_data_vld;
(* keep *) wire              dbg_instr_data_rdy;
(* keep *) wire              dbg_instr_caught_exception;
(* keep *) wire              dbg_instr_caught_ebreak;

(*keep*) wire [31:0]         dbg_sbus_addr;
(*keep*) wire                dbg_sbus_write;
(*keep*) wire [1:0]          dbg_sbus_size;
(*keep*) wire                dbg_sbus_vld;
(*keep*) wire                dbg_sbus_rdy;
(*keep*) wire                dbg_sbus_err;
(*keep*) wire [31:0]         dbg_sbus_wdata;
(*keep*) wire [31:0]         dbg_sbus_rdata;

(* keep *) wire [31:0]       irq;
(* keep *) wire              soft_irq;
(* keep *) wire              timer_irq;

hazard3_cpu_1port dut (
	.clk                        (clk),
	.clk_always_on              (clk),
	.rst_n                      (rst_n),

	.pwrup_req                  (pwrup_req),
	.pwrup_ack                  (pwrup_ack),
	.clk_en                     (clk_en),
	.unblock_out                (unblock_out),
	.unblock_in                 (unblock_in),

	.haddr                      (haddr),
	.hwrite                     (hwrite),
	.hexcl                      (hexcl),
	.htrans                     (htrans),
	.hsize                      (hsize),
	.hburst                     (hburst),
	.hprot                      (hprot),
	.hmastlock                  (hmastlock),
	.hready                     (hready),
	.hexokay                    (hexokay),
	.hresp                      (hresp),
	.hwdata                     (hwdata),
	.hrdata                     (hrdata),

	.dbg_req_halt               (dbg_req_halt),
	.dbg_req_halt_on_reset      (dbg_req_halt_on_reset),
	.dbg_req_resume             (dbg_req_resume),
	.dbg_halted                 (dbg_halted),
	.dbg_running                (dbg_running),
	.dbg_data0_rdata            (dbg_data0_rdata),
	.dbg_data0_wdata            (dbg_data0_wdata),
	.dbg_data0_wen              (dbg_data0_wen),
	.dbg_instr_data             (dbg_instr_data),
	.dbg_instr_data_vld         (dbg_instr_data_vld),
	.dbg_instr_data_rdy         (dbg_instr_data_rdy),
	.dbg_instr_caught_exception (dbg_instr_caught_exception),
	.dbg_instr_caught_ebreak    (dbg_instr_caught_ebreak),

	.dbg_sbus_addr              (dbg_sbus_addr),
	.dbg_sbus_write             (dbg_sbus_write),
	.dbg_sbus_size              (dbg_sbus_size),
	.dbg_sbus_vld               (dbg_sbus_vld),
	.dbg_sbus_rdy               (dbg_sbus_rdy),
	.dbg_sbus_err               (dbg_sbus_err),
	.dbg_sbus_wdata             (dbg_sbus_wdata),
	.dbg_sbus_rdata             (dbg_sbus_rdata),

	.irq                        (irq),
	.soft_irq                   (soft_irq),
	.timer_irq                  (timer_irq)
);

// ----------------------------------------------------------------------------
// Power signal properties

(* keep *) wire pwrup_ack_nxt;
always @ (posedge clk or negedge rst_n) begin
	 if (!rst_n) begin
	 	pwrup_ack <= 1'b1;
	 end else begin
	 	pwrup_ack <= 1'b1;
	 end
end

always @ (posedge clk) if (rst_n) begin

	// Assume the testbench gives fair acks to the processor's reqs
	if (pwrup_req && pwrup_ack) begin
		assume(pwrup_ack_nxt);
	end	
	if (!pwrup_req && !pwrup_ack) begin
		assume(!pwrup_ack_nxt);
	end

	// Assume there is no sbus access when powered down
	if (!(pwrup_req && pwrup_ack && clk_en)) begin
		assume(!dbg_sbus_vld);
	end

	// Assert only one of pwrup_req and pwrup_ack changes on one cycle
	// (processor upholds its side of the 4-phase handshake)
	assert((pwrup_ack != $past(pwrup_ack)) + {1'b0, (pwrup_req != $past(pwrup_req))} < 2'd2);

	// Assert rocessor doesn't access the bus whilst asleep
	if (!(pwrup_req && pwrup_ack && clk_en)) begin
		assert(htrans == 2'h0);
	end
end

// ----------------------------------------------------------------------------
// Bus properties

// -1 -> unconstrained, >=0 -> max length
localparam MAX_BUS_STALL = -1;

ahbl_slave_assumptions #(
	.MAX_BUS_STALL (MAX_BUS_STALL)
) d_assumptions (
	.clk             (clk),
	.rst_n           (rst_n),

	.dst_hready_resp (hready),
	.dst_hready      (hready),
	.dst_hresp       (hresp),
	.dst_hexokay     (hexokay),
	.dst_haddr       (haddr),
	.dst_hwrite      (hwrite),
	.dst_htrans      (htrans),
	.dst_hsize       (hsize),
	.dst_hburst      (hburst),
	.dst_hprot       (hprot),
	.dst_hmastlock   (hmastlock),
	.dst_hexcl       (hexcl),
	.dst_hwdata      (hwdata),
	.dst_hrdata      (hrdata)
);

ahbl_master_assertions d_assertions (
	.clk             (clk),
	.rst_n           (rst_n),

	.src_hready      (hready),
	.src_hresp       (hresp),
	.src_hexokay     (hexokay),
	.src_haddr       (haddr),
	.src_hwrite      (hwrite),
	.src_htrans      (htrans),
	.src_hsize       (hsize),
	.src_hburst      (hburst),
	.src_hprot       (hprot),
	.src_hmastlock   (hmastlock),
	.src_hexcl       (hexcl),
	.src_hwdata      (hwdata),
	.src_hrdata      (hrdata)
);

sbus_assumptions sbus_assumptions (
	.clk            (clk),
	.rst_n          (rst_n),

	.dbg_sbus_addr  (dbg_sbus_addr),
	.dbg_sbus_write (dbg_sbus_write),
	.dbg_sbus_size  (dbg_sbus_size),
	.dbg_sbus_vld   (dbg_sbus_vld),
	.dbg_sbus_rdy   (dbg_sbus_rdy),
	.dbg_sbus_err   (dbg_sbus_err),
	.dbg_sbus_wdata (dbg_sbus_wdata),
	.dbg_sbus_rdata (dbg_sbus_rdata)
);

endmodule
