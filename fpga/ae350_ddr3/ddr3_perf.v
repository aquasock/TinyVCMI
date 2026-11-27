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
//
// Words 4 and 5 time one read at a time: they are right only while no
// other client's reads are in flight, so with the video unit off, as
// firmware/apps/rd_lat runs.  A diagnostic, not used by the design.
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
    output reg  [255:0] snap = 256'd0,
    output reg          snap_tog = 1'b0
);
    reg [31:0] n_rd = 0, n_wr = 0, t_wait = 0, t_open = 0, t_issue = 0, t_data = 0, t_pclk = 0;
    reg [15:0] m_issue = 0, m_open = 0, c_issue = 0, c_open = 0;
    reg        open = 1'b0, issue = 1'b0, data = 1'b0;
    reg [SNAP_LOG2-1:0] snap_t = 0;

    wire c_rd = c_valid && c_ready && !c_we;
    wire x_rd = x_valid && x_ready && !x_we;

    always @(posedge pclk) begin
        t_pclk <= t_pclk + 1'b1;
        if (c_rd) n_rd <= n_rd + 1'b1;
        if (c_valid && c_ready && c_we) n_wr <= n_wr + 1'b1;
        if (c_valid && !c_we) t_wait <= t_wait + 1'b1;

        if (open) begin
            t_open <= t_open + 1'b1;
            if (~&c_open) c_open <= c_open + 1'b1;
        end
        if (c_rd) begin
            open <= 1'b1;
            c_open <= 16'd1;
        end else if (open && c_rvalid) begin
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
        end else if (issue && rd_load) begin
            issue <= 1'b0;
            if (c_issue > m_issue) m_issue <= c_issue;
        end

        if (data) t_data <= t_data + 1'b1;
        if (rd_load) data <= 1'b1;
        else if (x_rvalid) data <= 1'b0;

        snap_t <= snap_t + 1'b1;
        if (snap_t == 0) begin
            snap <= {t_pclk, m_open, m_issue, t_data, t_issue, t_open, t_wait, n_wr, n_rd};
            snap_tog <= ~snap_tog;
        end

        if (rst) begin
            {n_rd, n_wr, t_wait, t_open, t_issue, t_data, t_pclk} <= 0;
            {m_issue, m_open, c_issue, c_open} <= 0;
            {open, issue, data} <= 3'b000;
        end
    end
endmodule

`default_nettype wire
