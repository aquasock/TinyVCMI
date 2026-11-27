// SPDX-License-Identifier: GPL-3.0-only
`default_nettype none

// Where a CPU read's time goes on PCLK: counters on ddr3_arb's two sides
// and the PHY's READ, copied whole into snap every 2^SNAP_LOG2 PCLK and
// announced by snap_tog, as ctrl_glue's status is, so exts_perf can take
// the copy on the bus clock while it holds still.  Words of snap, 32 bits
// each, low word first:
//
//   0  CPU reads ddr3_arb took (c_valid, c_ready, not c_we)
//   1  CPU writes it took
//   2  PCLK a CPU read was offered and not yet taken, the taking one
//      included: the arbiter's wait
//   3  PCLK from a CPU read taken to its word handed back (c_rvalid): the
//      whole of the PCLK side after the queue
//   4  PCLK from a read taken by ddr3_ctl (x_) to its READ in the PHY's
//      command registers (rd_load): the controller's queueing, ACTIVATEs,
//      PRECHAREs and refreshes
//   5  PCLK from that READ to its word back from ddr3_ctl (x_rvalid): the
//      PHY's and the controller's fixed read latency
//   6  the longest of word 4 for one read, in bits 15:0, and of word 3 in
//      bits 31:16, each saturating
//   7  PCLK since the hand-over, so a reader can tell PCLK from bus clocks
//   8  video reads ddr3_arb took (v_valid, v_ready)
//   9  video words it handed back (v_rvalid)
//  10  CPU words it handed back (c_rvalid)
//  11  live, not counted: {arb_dbg[27:0], p_open[2:0], 0}, ddr3_arb's dbg
//      and the bridge's reads in flight (ahb_ddr3_pclk), as of the copy
//
// Words 3 to 5 time one read at a time: they are right only while no other
// read is in flight, so with the video unit off and the bridge's prefetch
// depth 0, as firmware/apps/rd_lat runs them.  Every input is registered
// once before it is counted.  A diagnostic, not used by the design.
module ddr3_perf #(
    parameter integer SNAP_LOG2 = 10
) (
    input  wire         pclk,
    input  wire         rst,
    input  wire         c_valid,
    input  wire         c_ready,
    input  wire         c_we,
    input  wire         c_rvalid,
    input  wire         x_valid,
    input  wire         x_ready,
    input  wire         x_we,
    input  wire         x_rvalid,
    input  wire         rd_load,
    input  wire         v_valid,
    input  wire         v_ready,
    input  wire         v_rvalid,
    input  wire [27:0]  arb_dbg,
    input  wire [2:0]   p_open,
    output reg  [383:0] snap = 384'd0,
    output reg          snap_tog = 1'b0
);
    // every input through a register first, so the counters add nothing to
    // the handshakes' own paths; each count and span is the same, a PCLK late
    reg q_c_valid = 1'b0, q_c_ready = 1'b0, q_c_we = 1'b0, q_c_rvalid = 1'b0;
    reg q_x_valid = 1'b0, q_x_ready = 1'b0, q_x_we = 1'b0, q_x_rvalid = 1'b0;
    reg q_rd_load = 1'b0, q_v_valid = 1'b0, q_v_ready = 1'b0, q_v_rvalid = 1'b0;
    reg [27:0] q_arb_dbg = 28'd0;
    reg [2:0]  q_p_open = 3'd0;
    always @(posedge pclk)
        {q_c_valid, q_c_ready, q_c_we, q_c_rvalid, q_x_valid, q_x_ready, q_x_we, q_x_rvalid,
         q_rd_load, q_v_valid, q_v_ready, q_v_rvalid, q_arb_dbg, q_p_open} <=
        {c_valid, c_ready, c_we, c_rvalid, x_valid, x_ready, x_we, x_rvalid,
         rd_load, v_valid, v_ready, v_rvalid, arb_dbg, p_open};

    reg [31:0] n_rd = 0, n_wr = 0, t_wait = 0, t_open = 0, t_issue = 0, t_data = 0, t_pclk = 0;
    reg [31:0] n_vrd = 0, n_vret = 0, n_cret = 0;
    reg [15:0] m_issue = 0, m_open = 0, c_issue = 0, c_open = 0;
    reg        open = 1'b0, issue = 1'b0, data = 1'b0;
    reg [SNAP_LOG2-1:0] snap_t = 0;

    wire c_rd = q_c_valid && q_c_ready && !q_c_we;
    wire x_rd = q_x_valid && q_x_ready && !q_x_we;

    always @(posedge pclk) begin
        t_pclk <= t_pclk + 1'b1;
        if (c_rd) n_rd <= n_rd + 1'b1;
        if (q_c_valid && q_c_ready && q_c_we) n_wr <= n_wr + 1'b1;
        if (q_c_valid && !q_c_we) t_wait <= t_wait + 1'b1;
        if (q_v_valid && q_v_ready) n_vrd <= n_vrd + 1'b1;
        if (q_v_rvalid) n_vret <= n_vret + 1'b1;
        if (q_c_rvalid) n_cret <= n_cret + 1'b1;

        if (open) begin
            t_open <= t_open + 1'b1;
            if (~&c_open) c_open <= c_open + 1'b1;
        end
        if (c_rd) begin
            open <= 1'b1;
            c_open <= 16'd1;
        end else if (open && q_c_rvalid) begin
            open <= 1'b0;
            if (c_open > m_open) m_open <= c_open;
        end

        if (issue) begin
            t_issue <= t_issue + 1'b1;
            if (~&c_issue) c_issue <= c_issue + 1'b1;
        end
        if (x_rd) begin
            issue <= 1'b1;
            c_issue <= 16'd1;
        end else if (issue && q_rd_load) begin
            issue <= 1'b0;
            if (c_issue > m_issue) m_issue <= c_issue;
        end

        if (data) t_data <= t_data + 1'b1;
        if (q_rd_load) data <= 1'b1;
        else if (q_x_rvalid) data <= 1'b0;

        snap_t <= snap_t + 1'b1;
        if (snap_t == 0) begin
            snap <= {q_arb_dbg, q_p_open, 1'b0, n_cret, n_vret, n_vrd,
                     t_pclk, m_open, m_issue, t_data, t_issue, t_open, t_wait, n_wr, n_rd};
            snap_tog <= ~snap_tog;
        end

        if (rst) begin
            {n_rd, n_wr, t_wait, t_open, t_issue, t_data, t_pclk, n_vrd, n_vret, n_cret} <= 0;
            {m_issue, m_open, c_issue, c_open} <= 0;
            {open, issue, data} <= 3'b000;
        end
    end
endmodule

`default_nettype wire
