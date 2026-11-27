// SPDX-License-Identifier: GPL-3.0-only
// Read-latency counters in the AE350's EXTS window, on the bus clock, at
// 0xe8020000 (ae350_sys selects this slave for 0xe8020000 to 0xe803ffff), for
// firmware/apps/rd_lat.  Every register is read-only and 32 bits, counting
// from reset and wrapping:
//
//   0x00  ID, ID_VALUE
//   0x04  bus clocks
//   0x08  DDR3 read beats ahb_ram took (sd_req rising)
//   0x0c  bus clocks sd_req was high: from the clock after a beat was taken
//         to its sd_ack
//   0x10  line misses: beats the bridge's line buffer could not answer
//         (b_read rising)
//   0x14  bus clocks b_read was high: from a miss queued to its line back
//   0x18  bus clocks the RAM port's HREADY was low, for any transfer
//   0x1c  snapshots of 0x20 to 0x3c taken
//   0x20 to 0x3c  ddr3_perf's snapshot, words 0 to 7, on PCLK
//
// The snapshot (ddr3_perf.v) is copied here when its toggle arrives, about
// every 10 us, and holds still for that long, so a reader that wants words
// of one snapshot reads 0x1c before and after them and tries again if it
// moved.  Any write, or another offset, gets an AHB ERROR response.  Each
// transfer takes one wait state, as exts_video's do.  A diagnostic, not used
// by the design.
module exts_perf #(
    parameter [31:0] ID_VALUE = 32'h54565031          // "TVP1"
) (
    input  wire         clk,
    input  wire         resetn,
    input  wire [31:0]  haddr,
    input  wire [1:0]   htrans,
    input  wire         hsel,
    input  wire         hwrite,
    input  wire         hready_in,
    output reg  [31:0]  hrdata = 32'd0,
    output reg          hready = 1'b1,
    output reg          hresp = 1'b0,

    input  wire         sd_req,
    input  wire         b_read,
    input  wire         ram_ready,
    input  wire [255:0] snap,           // PCLK, still while snap_tog is
    input  wire         snap_tog
);
    reg [31:0] n_clk = 0, n_beat = 0, t_req = 0, n_miss = 0, t_miss = 0, t_ram = 0, n_snap = 0;
    reg        req_d = 1'b0, read_d = 1'b0;
    reg [2:0]  snap_s = 3'd0;
    reg [255:0] snap_b = 256'd0;

    reg [3:0]  index = 4'd0;
    reg        bad = 1'b0;
    reg        pending = 1'b0;
    reg        error_second = 1'b0;

    always @(posedge clk) begin
        n_clk <= n_clk + 1'b1;
        req_d <= sd_req;
        read_d <= b_read;
        if (sd_req && !req_d) n_beat <= n_beat + 1'b1;
        if (sd_req) t_req <= t_req + 1'b1;
        if (b_read && !read_d) n_miss <= n_miss + 1'b1;
        if (b_read) t_miss <= t_miss + 1'b1;
        if (!ram_ready) t_ram <= t_ram + 1'b1;
        snap_s <= {snap_s[1:0], snap_tog};
        if (snap_s[2] ^ snap_s[1]) begin
            snap_b <= snap;
            n_snap <= n_snap + 1'b1;
        end

        error_second <= 1'b0;
        if (hready) begin
            hresp <= 1'b0;
            if (hready_in && hsel && htrans[1]) begin
                index <= haddr[5:2];
                bad <= hwrite || haddr[16:6] != 11'd0 || haddr[1:0] != 2'd0;
                pending <= 1'b1;
                hready <= 1'b0;
            end
        end
        if (pending) begin
            pending <= 1'b0;
            if (bad) begin
                hresp <= 1'b1;
                error_second <= 1'b1;
            end else begin
                hready <= 1'b1;
                case (index)
                    4'd0: hrdata <= ID_VALUE;
                    4'd1: hrdata <= n_clk;
                    4'd2: hrdata <= n_beat;
                    4'd3: hrdata <= t_req;
                    4'd4: hrdata <= n_miss;
                    4'd5: hrdata <= t_miss;
                    4'd6: hrdata <= t_ram;
                    4'd7: hrdata <= n_snap;
                    default: hrdata <= snap_b[32*index[2:0] +: 32];
                endcase
            end
        end
        if (error_second)
            hready <= 1'b1;

        if (!resetn) begin
            {n_clk, n_beat, t_req, n_miss, t_miss, t_ram, n_snap} <= 0;
            {req_d, read_d} <= 2'b00;
            pending <= 1'b0;
            error_second <= 1'b0;
            hrdata <= 32'd0;
            hready <= 1'b1;
            hresp <= 1'b0;
        end
    end
endmodule
