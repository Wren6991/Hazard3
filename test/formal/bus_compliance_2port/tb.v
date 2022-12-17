// Assume bus responses to both ports are well-formed, assert that bus
// requests are well-formed.

`default_nettype none

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

(* keep *) wire [31:0]       i_haddr;
(* keep *) wire              i_hwrite;
(* keep *) wire [1:0]        i_htrans;
(* keep *) wire [2:0]        i_hsize;
(* keep *) wire [2:0]        i_hburst;
(* keep *) wire [3:0]        i_hprot;
(* keep *) wire              i_hmastlock;
(* keep *) wire              i_hready;
(* keep *) wire              i_hresp;
(* keep *) wire [31:0]       i_hwdata;
(* keep *) wire [31:0]       i_hrdata;

(* keep *) wire [31:0]       d_haddr;
(* keep *) wire              d_hwrite;
(* keep *) wire [1:0]        d_htrans;
(* keep *) wire [2:0]        d_hsize;
(* keep *) wire [2:0]        d_hburst;
(* keep *) wire [3:0]        d_hprot;
(* keep *) wire              d_hmastlock;
(* keep *) wire              d_hexcl;
(* keep *) wire              d_hready;
(* keep *) wire              d_hresp;
(* keep *) wire              d_hexokay;
(* keep *) wire [31:0]       d_hwdata;
(* keep *) wire [31:0]       d_hrdata;

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

(* keep *) wire [31:0]       dbg_sbus_addr;
(* keep *) wire              dbg_sbus_write;
(* keep *) wire [1:0]        dbg_sbus_size;
(* keep *) wire              dbg_sbus_vld;
(* keep *) wire              dbg_sbus_rdy;
(* keep *) wire              dbg_sbus_err;
(* keep *) wire [31:0]       dbg_sbus_wdata;
(* keep *) wire [31:0]       dbg_sbus_rdata;

(* keep *) wire [31:0]       irq;
(* keep *) wire              soft_irq;
(* keep *) wire              timer_irq;

hazard3_cpu_2port dut (
	.clk                        (clk),
	.clk_always_on              (clk),
	.rst_n                      (rst_n),

	.pwrup_req                  (pwrup_req),
	.pwrup_ack                  (pwrup_ack),
	.clk_en                     (clk_en),
	.unblock_out                (unblock_out),
	.unblock_in                 (unblock_in),

	.i_haddr                    (i_haddr),
	.i_hwrite                   (i_hwrite),
	.i_htrans                   (i_htrans),
	.i_hsize                    (i_hsize),
	.i_hburst                   (i_hburst),
	.i_hprot                    (i_hprot),
	.i_hmastlock                (i_hmastlock),
	.i_hready                   (i_hready),
	.i_hresp                    (i_hresp),
	.i_hwdata                   (i_hwdata),
	.i_hrdata                   (i_hrdata),

	.d_haddr                    (d_haddr),
	.d_hwrite                   (d_hwrite),
	.d_htrans                   (d_htrans),
	.d_hsize                    (d_hsize),
	.d_hburst                   (d_hburst),
	.d_hprot                    (d_hprot),
	.d_hmastlock                (d_hmastlock),
	.d_hexcl                    (d_hexcl),
	.d_hready                   (d_hready),
	.d_hresp                    (d_hresp),
	.d_hexokay                  (d_hexokay),
	.d_hwdata                   (d_hwdata),
	.d_hrdata                   (d_hrdata),

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

	// Assert processor doesn't access the bus whilst asleep
	if (!(pwrup_req && pwrup_ack && clk_en)) begin
		assert(i_htrans == 2'h0);
		assert(d_htrans == 2'h0);
	end
end

// ----------------------------------------------------------------------------
// Bus properties

// -1 -> unconstrained, >=0 -> max length
localparam MAX_BUS_STALL = -1;

ahbl_slave_assumptions #(
	.MAX_BUS_STALL (MAX_BUS_STALL)
) i_assumptions (
	.clk             (clk),
	.rst_n           (rst_n),

	.dst_hready_resp (i_hready),
	.dst_hready      (i_hready),
	.dst_hresp       (i_hresp),
	.dst_hexokay     (1'b0),
	.dst_haddr       (i_haddr),
	.dst_hwrite      (i_hwrite),
	.dst_htrans      (i_htrans),
	.dst_hsize       (i_hsize),
	.dst_hburst      (i_hburst),
	.dst_hprot       (i_hprot),
	.dst_hmastlock   (i_hmastlock),
	.dst_hexcl       (1'b0),
	.dst_hwdata      (i_hwdata),
	.dst_hrdata      (i_hrdata)
);

ahbl_slave_assumptions #(
	.MAX_BUS_STALL (MAX_BUS_STALL)
) d_assumptions (
	.clk             (clk),
	.rst_n           (rst_n),

	.dst_hready_resp (d_hready),
	.dst_hready      (d_hready),
	.dst_hresp       (d_hresp),
	.dst_hexokay     (d_hexokay),
	.dst_haddr       (d_haddr),
	.dst_hwrite      (d_hwrite),
	.dst_htrans      (d_htrans),
	.dst_hsize       (d_hsize),
	.dst_hburst      (d_hburst),
	.dst_hprot       (d_hprot),
	.dst_hmastlock   (d_hmastlock),
	.dst_hexcl       (d_hexcl),
	.dst_hwdata      (d_hwdata),
	.dst_hrdata      (d_hrdata)
);

ahbl_master_assertions i_assertions (
	.clk             (clk),
	.rst_n           (rst_n),

	.src_hready      (i_hready),
	.src_hresp       (i_hresp),
	.src_hexokay     (1'b0),
	.src_haddr       (i_haddr),
	.src_hwrite      (i_hwrite),
	.src_htrans      (i_htrans),
	.src_hsize       (i_hsize),
	.src_hburst      (i_hburst),
	.src_hprot       (i_hprot),
	.src_hmastlock   (i_hmastlock),
	.src_hexcl       (1'b0),
	.src_hwdata      (i_hwdata),
	.src_hrdata      (i_hrdata)
);


ahbl_master_assertions d_assertions (
	.clk             (clk),
	.rst_n           (rst_n),

	.src_hready      (d_hready),
	.src_hresp       (d_hresp),
	.src_hexokay     (d_hexokay),
	.src_haddr       (d_haddr),
	.src_hwrite      (d_hwrite),
	.src_htrans      (d_htrans),
	.src_hsize       (d_hsize),
	.src_hburst      (d_hburst),
	.src_hprot       (d_hprot),
	.src_hmastlock   (d_hmastlock),
	.src_hexcl       (d_hexcl),
	.src_hwdata      (d_hwdata),
	.src_hrdata      (d_hrdata)
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
