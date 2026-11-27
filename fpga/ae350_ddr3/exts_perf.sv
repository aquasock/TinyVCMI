// SPDX-License-Identifier: GPL-3.0-only
// Read-latency counters in the AE350's EXTS window, on the bus clock, at
// 0xe8020000 (ae350_sys selects this slave for 0xe8020000 to 0xe803ffff), for
// firmware/apps/rd_lat, and the bridge's prefetch depth.  Every register is
// 32 bits; the counters count from reset and wrap:
//
//   0x00  ID, ID_VALUE
//   0x04  bus clocks
//   0x08  DDR3 read beats ahb_ram took (sd_req rising)
//   0x0c  bus clocks sd_req was high: from the clock after a beat was taken
//         to its sd_ack
//   0x10  demand reads the bridge queued (p_miss): beats neither its line
//         buffer nor a way could answer
//   0x14  bus clocks the bridge was answering a beat from DDR3 (p_wait):
//         from a miss or a pending way found to the line back
//   0x18  bus clocks the RAM port's HREADY was low, for any transfer
//   0x1c  snapshots of the PCLK words taken
//   0x20 to 0x3c  ddr3_perf's snapshot, words 0 to 7, on PCLK
//   0x40  PF_DEPTH, read and write: bits 1:0 the lines the bridge reads
//         ahead of a lookup, 0 to 3; 2 at reset
//   0x44  prefetches the bridge queued (p_pf)
//   0x48  lookups a prefetched way served (p_pfhit), first use only
//   0x4c  bus clocks the RAM port was idle: HREADY high, no transfer
//   0x50 to 0x5c  ddr3_perf's snapshot, words 8 to 11
//
// The snapshot (ddr3_perf.v) is copied here when its toggle arrives, about
// every 10 us, and holds still for that long, so a reader that wants words
// of one snapshot reads 0x1c before and after them and tries again if it
// moved.  A write anywhere but 0x40, or another offset, gets an AHB ERROR
// response.  Each transfer takes one wait state, as exts_video's do; a
// write's data is taken in it.  tap is snapshot word 11, for the board's
// stall dump.  A diagnostic but for pf_depth, which the bridge uses.
module exts_perf #(
    parameter [31:0] ID_VALUE = 32'h54565031          // "TVP1"
) (
    input  wire         clk,
    input  wire         resetn,
    input  wire [31:0]  haddr,
    input  wire [1:0]   htrans,
    input  wire         hsel,
    input  wire         hwrite,
    input  wire [31:0]  hwdata,
    input  wire         hready_in,
    output reg  [31:0]  hrdata = 32'd0,
    output reg          hready = 1'b1,
    output reg          hresp = 1'b0,

    input  wire         sd_req,
    input  wire         p_miss,
    input  wire         p_wait,
    input  wire         p_pf,
    input  wire         p_pfhit,
    input  wire         ram_ready,
    input  wire [1:0]   ram_trans,
    input  wire [383:0] snap,           // PCLK, still while snap_tog is
    input  wire         snap_tog,

    output reg  [1:0]   pf_depth = 2'd2,
    output wire [31:0]  tap
);
    reg [31:0] n_clk = 0, n_beat = 0, t_req = 0, n_miss = 0, t_miss = 0, t_ram = 0, n_snap = 0;
    reg [31:0] n_pf = 0, n_pfhit = 0, t_idle = 0;
    reg        req_d = 1'b0;
    reg [2:0]  snap_s = 3'd0;
    reg [383:0] snap_b = 384'd0;
    assign tap = snap_b[352 +: 32];

    reg [4:0]  index = 5'd0;
    reg        bad = 1'b0;
    reg        write = 1'b0;
    reg        pending = 1'b0;
    reg        error_second = 1'b0;

    always @(posedge clk) begin
        n_clk <= n_clk + 1'b1;
        req_d <= sd_req;
        if (sd_req && !req_d) n_beat <= n_beat + 1'b1;
        if (sd_req) t_req <= t_req + 1'b1;
        if (p_miss) n_miss <= n_miss + 1'b1;
        if (p_wait) t_miss <= t_miss + 1'b1;
        if (p_pf) n_pf <= n_pf + 1'b1;
        if (p_pfhit) n_pfhit <= n_pfhit + 1'b1;
        if (!ram_ready) t_ram <= t_ram + 1'b1;
        if (ram_ready && !ram_trans[1]) t_idle <= t_idle + 1'b1;
        snap_s <= {snap_s[1:0], snap_tog};
        if (snap_s[2] ^ snap_s[1]) begin
            snap_b <= snap;
            n_snap <= n_snap + 1'b1;
        end

        error_second <= 1'b0;
        if (hready) begin
            hresp <= 1'b0;
            if (hready_in && hsel && htrans[1]) begin
                index <= haddr[6:2];
                write <= hwrite;
                bad <= haddr[16:7] != 10'd0 || haddr[6:2] > 5'd23 || haddr[1:0] != 2'd0 ||
                       (hwrite && haddr[6:2] != 5'd16);
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
                if (write)
                    pf_depth <= hwdata[1:0];
                case (index)
                    5'd0: hrdata <= ID_VALUE;
                    5'd1: hrdata <= n_clk;
                    5'd2: hrdata <= n_beat;
                    5'd3: hrdata <= t_req;
                    5'd4: hrdata <= n_miss;
                    5'd5: hrdata <= t_miss;
                    5'd6: hrdata <= t_ram;
                    5'd7: hrdata <= n_snap;
                    5'd16: hrdata <= {30'd0, pf_depth};
                    5'd17: hrdata <= n_pf;
                    5'd18: hrdata <= n_pfhit;
                    5'd19: hrdata <= t_idle;
                    5'd20, 5'd21, 5'd22, 5'd23: hrdata <= snap_b[256 + 32*index[1:0] +: 32];
                    default: hrdata <= snap_b[32*index[2:0] +: 32];
                endcase
            end
        end
        if (error_second)
            hready <= 1'b1;

        if (!resetn) begin
            {n_clk, n_beat, t_req, n_miss, t_miss, t_ram, n_snap, n_pf, n_pfhit, t_idle} <= 0;
            req_d <= 1'b0;
            pf_depth <= 2'd2;
            write <= 1'b0;
            pending <= 1'b0;
            error_second <= 1'b0;
            hrdata <= 32'd0;
            hready <= 1'b1;
            hresp <= 1'b0;
        end
    end
endmodule
