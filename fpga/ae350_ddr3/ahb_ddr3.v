// SPDX-License-Identifier: GPL-3.0-only
`default_nettype none
`ifdef SYNTHESIS
`define XFIFO_NOCHECK
`endif

// The DDR3 back end for the AE350 RAM port: ahb_ram's 64-bit transfers on
// the bus clock in, ddr3_ctl's 256-bit requests on PCLK out.
//
// ahb_ram hands over two kinds of transfer:
//
//   A read raises req in its data phase, with addr steady, until ack; rdata
//   is valid while ack is high, and ahb_ram registers it into HRDATA at
//   that edge.  ack and rdata come from registers through logic, so a line
//   reaches HRDATA in the clock it arrives.  Nothing is posted while a read
//   is open.
//
//   A read that continues a burst in the line of the read before it is
//   answered in its address phase with no wait state: l_hit says the line
//   buffer holds the line of addr, the read before it, and l_data is the
//   doubleword l_dw of the buffer, registered into HRDATA at the edge the
//   read is accepted.  ahb_ram decides from HTRANS, HBURST, HSIZE and
//   HADDR[4:0] whether a read is in its predecessor's line, so no address
//   compare sits on the AE350's HADDR.
//
//   A write is posted: post pulses for one bus clock with addr, lanes and
//   wdata valid in that clock, and is never refused.  ahb_ram posts only
//   while post_ok is high, which promises room for that write and for one
//   more posted in the next clock (xfifo_w's LEAD).
//
// One DDR3 word is 32 bytes, one A25 cache line, byte k of the line at
// cmd_wdata[8k +: 8] and write-mask bit k (ddr3_ctl's beat k / 4, lane
// k % 4).  Every transfer that needs the DDR3, read or write, goes through
// one queue in program order, xfifo_w on the bus clock and xfifo_r on PCLK,
// and ddr3_arb, ctrl_glue and ddr3_ctl keep that order, so a read queued
// behind a write to the same word returns the written data.  A write goes
// to the DDR3 as one masked write of its own doubleword's lanes, every
// other byte of the line masked; up to 16 can be queued, so the A25 stores
// at the bus clock's pace while PCLK drains them.
//
// The last line read is held in a one-line buffer, so a cache-line fill's
// four doublewords cost one DDR3 read: the first misses and waits for the
// line, the other three are answered from the buffer with no wait state.
// A write is merged into the buffer as it leaves the queue's staging
// register, if it hits the buffered line, so the buffer never holds stale
// data: the A25 is the RAM port's only master.  A read in its data phase
// waits while the staging register holds anything, so it never sees the
// buffer before a write ahead of it is merged; a read answered in its
// address phase follows a read of its own burst, so no write is in the
// queue's staging register or in its data phase then (checked in
// simulation).
//
// The bus clock and PCLK come from different PLLs.  The queue is an
// asynchronous FIFO with Gray-coded pointers (xfifo_w, xfifo_r); its LUT
// RAM is written on the bus clock from registers and read asynchronously on
// PCLK, which reads an entry only after its write pointer has come through
// two flops.  A read's line comes back the old way: the PCLK side copies it
// into y_line and toggles y_tog, the bus side sees y_tog through two flops,
// and y_line then holds still until the next read is answered.
//
// The two halves are modules of their own, ahb_ddr3_bus and ahb_ddr3_pclk,
// so the AE350 image can place each beside its own side: the bus half near
// the AE350 macro, the PCLK half and the queue's RAM near ddr3_ctl, with
// only registers between them.  ahb_ddr3 joins them, for the bench.
//
// A reset of one side alone desynchronises the pointers; both sides are
// reset together at the hand-over and neither is reset after it.
//
// Simulation-only: MUT_MASK masks the lanes of the doubleword after the
// written one, MUT_NOMERGE leaves the buffer unmerged on a write hit,
// MUT_FULL lets xfifo_w promise room one entry late, and MUT_BYPASS lets
// xfifo_r hand a read out ahead of the write before it; the benches must
// fail each.  XFIFO_NOCHECK, and SYNTHESIS, leave out the queue's own
// checks, so tb_xfifo.v must catch its mutants by the data alone.
module ahb_ddr3 #(
    parameter integer AW = 25           // line address bits: 1 GiB
) (
    // the bus clock side, from ahb_ram
    input  wire          clk,
    input  wire          resetn,
    input  wire [1:0]    l_dw,
    output wire          l_hit,
    output wire [63:0]   l_data,
    input  wire          req,
    input  wire          post,
    output wire          post_ok,
    input  wire [AW+4:3] addr,
    input  wire [7:0]    lanes,
    input  wire [63:0]   wdata,
    output wire          ack,
    output wire [63:0]   rdata,

    // the PCLK side, to ddr3_ctl's request port
    input  wire          pclk,
    input  wire          prst,
    output wire          cmd_valid,
    input  wire          cmd_ready,
    output wire          cmd_we,
    output wire [AW-1:0] cmd_addr,
    output wire [255:0]  cmd_wdata,
    output wire [31:0]   cmd_wmask,
    input  wire          rdata_valid,
    input  wire [255:0]  rdata_line
);
    localparam integer W = AW + 75;
    wire          q_we, y_tog;
    wire [3:0]    q_waddr;
    wire [W-1:0]  q_wdata;
    wire [4:0]    q_wgray, q_rgray;
    wire [255:0]  y_line;
    ahb_ddr3_bus #(.AW(AW)) bus (
        .clk(clk), .resetn(resetn), .l_dw(l_dw), .l_hit(l_hit), .l_data(l_data),
        .req(req), .post(post), .post_ok(post_ok), .addr(addr),
        .lanes(lanes), .wdata(wdata), .ack(ack), .rdata(rdata),
        .q_we(q_we), .q_waddr(q_waddr), .q_wdata(q_wdata), .q_wgray(q_wgray),
        .q_rgray(q_rgray), .y_tog(y_tog), .y_line(y_line));
    ahb_ddr3_pclk #(.AW(AW)) pside (
        .bus_clk(clk), .pclk(pclk), .prst(prst),
        .q_we(q_we), .q_waddr(q_waddr), .q_wdata(q_wdata), .q_wgray(q_wgray),
        .q_rgray(q_rgray), .y_tog(y_tog), .y_line(y_line),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_we(cmd_we), .cmd_addr(cmd_addr),
        .cmd_wdata(cmd_wdata), .cmd_wmask(cmd_wmask), .rdata_valid(rdata_valid),
        .rdata_line(rdata_line));
endmodule

// The queue's write side, on its own clock: a staging register that writes
// the RAM (in xfifo_r) in the clock after push, and the write pointer, which
// moves in the clock the RAM is written, so the reader never sees an entry
// before it is there.  full and room are registered from the pointers after
// this clock's push and the read pointer as last seen through two flops, so
// they are never optimistic: full is high with DEPTH entries taken, and
// room high with at most DEPTH - LEAD, for a writer that decides to push
// up to LEAD - 1 clocks before it does.
module xfifo_w #(
    parameter integer W = 100,
    parameter integer LOG2 = 4,
    parameter integer LEAD = 2
) (
    input  wire            clk,
    input  wire            rst,
    input  wire            push,
    input  wire [W-1:0]    din,
    output reg             full = 1'b0,
    output reg             room = 1'b0,
    // to xfifo_r: the RAM's write port, and the pointer
    output reg             q_we = 1'b0,
    output reg  [LOG2-1:0] q_waddr = {LOG2{1'b0}},
    output reg  [W-1:0]    q_wdata = {W{1'b0}},
    output reg  [LOG2:0]   q_wgray = {(LOG2+1){1'b0}},
    input  wire [LOG2:0]   q_rgray
);
    localparam integer DEPTH = 1 << LOG2;
`ifdef MUT_FULL
    localparam integer SLACK = 1;
`else
    localparam integer SLACK = 0;
`endif
    reg  [LOG2:0] wbin = {(LOG2+1){1'b0}};      // entries pushed
    reg  [LOG2:0] rq1 = {(LOG2+1){1'b0}}, rq2 = {(LOG2+1){1'b0}};
    wire [LOG2:0] rbin_seen = gray2bin(rq2);
    wire [LOG2:0] used_now = wbin - rbin_seen;
    // the flags both ways, before push is known, so push only selects:
    // it comes late, from ahb_ddr3_bus's line buffer compare
    wire          full_hold = used_now >= DEPTH + SLACK;
    wire          full_push = used_now >= DEPTH + SLACK - 1;
    wire          room_hold = used_now <= DEPTH - LEAD + SLACK;
    wire          room_push = used_now <= DEPTH - LEAD + SLACK - 1;

    function [LOG2:0] gray2bin(input [LOG2:0] g);
        integer k;
        begin
            gray2bin[LOG2] = g[LOG2];
            for (k = LOG2 - 1; k >= 0; k = k - 1)
                gray2bin[k] = gray2bin[k+1] ^ g[k];
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            wbin <= {(LOG2+1){1'b0}};
            rq1 <= {(LOG2+1){1'b0}};
            rq2 <= {(LOG2+1){1'b0}};
            q_we <= 1'b0;
            q_wgray <= {(LOG2+1){1'b0}};
            full <= 1'b0;
            room <= 1'b0;
        end else begin
            rq1 <= q_rgray;
            rq2 <= rq1;
            q_we <= push;
            if (push) begin
                q_waddr <= wbin[LOG2-1:0];
                q_wdata <= din;
            end
            if (push) wbin <= wbin + 1'b1;
            q_wgray <= wbin ^ (wbin >> 1);      // the entry written now is wbin - 1
            full <= push ? full_push : full_hold;
            room <= push ? room_push : room_hold;
        end
    end

`ifndef XFIFO_NOCHECK
    always @(posedge clk)
        if (!rst && push && used_now >= DEPTH) begin
            $display("FAIL  xfifo: pushed into a full queue at t=%0t", $time);
            $finish;
        end
`endif
endmodule

// The queue's read side: the RAM, written on the writer's clock and read
// asynchronously, and the read pointer.  head is the oldest entry while
// empty is low; pop takes it.  The bus clock path into the RAM's write port
// is register to register (xfifo_w), so the RAM can sit beside the reader.
module xfifo_r #(
    parameter integer W = 100,
    parameter integer LOG2 = 4
) (
    input  wire            wclk,
    input  wire            q_we,
    input  wire [LOG2-1:0] q_waddr,
    input  wire [W-1:0]    q_wdata,
    input  wire [LOG2:0]   q_wgray,
    input  wire            clk,
    input  wire            rst,
    output wire            empty,
    output wire [W-1:0]    head,
    input  wire            pop,
    output reg  [LOG2:0]   q_rgray = {(LOG2+1){1'b0}}
);
    localparam integer DEPTH = 1 << LOG2;
    (* ram_style = "distributed" *) reg [W-1:0] mem [0:DEPTH-1];
    always @(posedge wclk)
        if (q_we)
            mem[q_waddr] <= q_wdata;

    reg  [LOG2:0] rbin = {(LOG2+1){1'b0}};
    reg  [LOG2:0] wq1 = {(LOG2+1){1'b0}}, wq2 = {(LOG2+1){1'b0}};
    wire [LOG2:0] rnext = rbin + 1'b1;
    assign empty = q_rgray == wq2;

`ifdef MUT_BYPASS
    // a read entry (top bit 0) behind a write is handed out first, then the
    // write, then the queue goes on after both
    reg skip = 1'b0;
    integer   k;
    reg [LOG2:0] wbin_seen;
    always @* begin
        wbin_seen[LOG2] = wq2[LOG2];
        for (k = LOG2 - 1; k >= 0; k = k - 1)
            wbin_seen[k] = wbin_seen[k+1] ^ wq2[k];
    end
    wire [W-1:0] h0 = mem[rbin[LOG2-1:0]], h1 = mem[rnext[LOG2-1:0]];
    wire [LOG2:0] avail = wbin_seen - rbin;
    wire swap = !skip && avail >= 2 && h0[W-1] && !h1[W-1];
    assign head = swap ? h1 : h0;
    wire [LOG2:0] radv = skip ? rbin + 2'd2 : rnext;
    always @(posedge clk)
        if (rst) skip <= 1'b0;
        else if (pop) skip <= swap;
`else
    assign head = mem[rbin[LOG2-1:0]];
`endif

    always @(posedge clk) begin
        if (rst) begin
            rbin <= {(LOG2+1){1'b0}};
            q_rgray <= {(LOG2+1){1'b0}};
            wq1 <= {(LOG2+1){1'b0}};
            wq2 <= {(LOG2+1){1'b0}};
        end else begin
            wq1 <= q_wgray;
            wq2 <= wq1;
`ifdef MUT_BYPASS
            if (pop && !swap) begin
                rbin <= radv;
                q_rgray <= radv ^ (radv >> 1);
            end
`else
            if (pop) begin
                rbin <= rnext;
                q_rgray <= rnext ^ (rnext >> 1);
            end
`endif
        end
    end

`ifndef XFIFO_NOCHECK
    always @(posedge clk)
        if (!rst && pop && empty) begin
            $display("FAIL  xfifo: popped an empty queue at t=%0t", $time);
            $finish;
        end
`endif
endmodule

// the bus clock half: the line buffer and the queue's write side
module ahb_ddr3_bus #(
    parameter integer AW = 25
) (
    input  wire          clk,
    input  wire          resetn,
    // a read in its address phase in the line of addr: its doubleword, and
    // whether the buffer holds that line
    input  wire [1:0]    l_dw,
    output wire          l_hit,
    output wire [63:0]   l_data,
    // its data phase
    input  wire          req,
    input  wire          post,
    output wire          post_ok,
    input  wire [AW+4:3] addr,
    input  wire [7:0]    lanes,
    input  wire [63:0]   wdata,
    output wire          ack,
    output wire [63:0]   rdata,
    // to the PCLK half, each a register on the bus clock
    output wire          q_we,
    output wire [3:0]    q_waddr,
    output wire [AW+74:0] q_wdata,
    output wire [4:0]    q_wgray,
    // from it, each a register on PCLK
    input  wire [4:0]    q_rgray,
    input  wire          y_tog,
    input  wire [255:0]  y_line,
    output wire [1:0]    dbg                // {b_read, lb_valid}, for ae350_sys's STALL report
);
    reg          lb_valid = 1'b0;           // the line buffer
    reg [AW-1:0] lb_tag = {AW{1'b0}};
    reg [255:0]  lb_data = 256'd0;

    reg          b_read = 1'b0;             // a read is queued, awaiting its line
    reg [2:0]    y_s = 3'd0;                // y_tog through two flops, and the last
    wire         y_edge = y_s[2] ^ y_s[1];

    wire [AW-1:0] line = addr[AW+4:5];
    wire          hit = lb_valid && lb_tag == line;

    // the staging register, as written to the RAM: {write, line, dw, lanes, data}
    wire          s_we = q_wdata[AW+74];
    wire [AW-1:0] s_line = q_wdata[AW+73:74];
    wire [1:0]    s_dw = q_wdata[73:72];
    wire [7:0]    s_lanes = q_wdata[71:64];
    wire [63:0]   s_wd = q_wdata[63:0];

    assign l_hit = hit;
    assign l_data = lb_data[64*l_dw +: 64];

    assign dbg = {b_read, lb_valid};
    wire full;
    wire rd_go = req && !b_read && !q_we;
    wire rd_push = rd_go && !hit && !full;
    wire push = post || rd_push;
    xfifo_w #(.W(AW + 75), .LOG2(4), .LEAD(2)) fw (
        .clk(clk), .rst(!resetn), .push(push),
        .din({post, line, addr[4:3], lanes, wdata}),
        .full(full), .room(post_ok),
        .q_we(q_we), .q_waddr(q_waddr), .q_wdata(q_wdata), .q_wgray(q_wgray),
        .q_rgray(q_rgray));

    // the data phase ends in the clock its line arrives, or its buffer hit
    // is seen; the staging register still holds the read, since nothing is
    // pushed while it is open
    assign ack = (b_read && y_edge) || (rd_go && hit);
    assign rdata = b_read ? y_line[64*s_dw +: 64] : lb_data[64*addr[4:3] +: 64];

    function [255:0] merge(input [255:0] old, input [1:0] dw, input [7:0] ln, input [63:0] wd);
        integer k;
        begin
            merge = old;
            for (k = 0; k < 8; k = k + 1)
`ifdef MUT_MASK
                if (ln[k]) merge[64*((dw + 2'd1) & 2'd3) + 8*k +: 8] = wd[8*k +: 8];
`else
                if (ln[k]) merge[64*dw + 8*k +: 8] = wd[8*k +: 8];
`endif
        end
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            lb_valid <= 1'b0;
            b_read <= 1'b0;
            y_s <= 3'd0;
        end else begin
            y_s <= {y_s[1:0], y_tog};
            if (b_read && y_edge) begin
                b_read <= 1'b0;
                lb_valid <= 1'b1;
                lb_tag <= s_line;
                lb_data <= y_line;
            end
            if (rd_push)
                b_read <= 1'b1;
`ifndef MUT_NOMERGE
            if (q_we && s_we && lb_valid && lb_tag == s_line)
                lb_data <= merge(lb_data, s_dw, s_lanes, s_wd);
`endif
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk)
        if (resetn && post && (req || b_read)) begin
            $display("FAIL  ahb_ddr3: a write posted while a read was open at t=%0t", $time);
            $finish;
        end
`endif
endmodule

// the PCLK half: the queue's read side, the request into ddr3_ctl, and the
// answer back
module ahb_ddr3_pclk #(
    parameter integer AW = 25
) (
    input  wire          bus_clk,           // the queue RAM's write port only
    input  wire          pclk,
    input  wire          prst,
    input  wire          q_we,
    input  wire [3:0]    q_waddr,
    input  wire [AW+74:0] q_wdata,
    input  wire [4:0]    q_wgray,
    output wire [4:0]    q_rgray,
    output reg           y_tog = 1'b0,
    output reg  [255:0]  y_line = 256'd0,   // still from y_tog's move until the next read
    output reg           cmd_valid = 1'b0,
    input  wire          cmd_ready,
    output reg           cmd_we = 1'b0,
    output reg  [AW-1:0] cmd_addr = {AW{1'b0}},
    output wire [255:0]  cmd_wdata,
    output reg  [31:0]   cmd_wmask = 32'd0,
    input  wire          rdata_valid,
    input  wire [255:0]  rdata_line
);
    wire          empty;
    wire [AW+74:0] head;
    wire          pop = !empty && (!cmd_valid || cmd_ready);
    xfifo_r #(.W(AW + 75), .LOG2(4)) fr (
        .wclk(bus_clk), .q_we(q_we), .q_waddr(q_waddr), .q_wdata(q_wdata), .q_wgray(q_wgray),
        .clk(pclk), .rst(prst), .empty(empty), .head(head), .pop(pop), .q_rgray(q_rgray));

    reg [63:0] cmd_wd = 64'd0;
    assign cmd_wdata = {4{cmd_wd}};
    reg        p_read = 1'b0;               // a read's line is due
    always @(posedge pclk) begin
        if (prst) begin
            y_tog <= 1'b0;
            p_read <= 1'b0;
            cmd_valid <= 1'b0;
        end else begin
            if (cmd_valid && cmd_ready) begin
                cmd_valid <= 1'b0;
                if (!cmd_we)
                    p_read <= 1'b1;
            end
            if (pop) begin
                cmd_valid <= 1'b1;
                cmd_we <= head[AW+74];
                cmd_addr <= head[AW+73:74];
                cmd_wd <= head[63:0];
                cmd_wmask <= ~({24'd0, head[71:64]} << (8 * head[73:72]));
            end
            if (p_read && rdata_valid) begin
                p_read <= 1'b0;
                y_line <= rdata_line;
                y_tog <= ~y_tog;
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge pclk)
        if (!prst && rdata_valid && !p_read)
            $fatal(1, "ahb_ddr3: read data arrived with no read open");
`endif
endmodule

`default_nettype wire
