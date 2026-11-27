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
//   that edge.  Nothing is posted while a read is open.
//
//   A read that continues a burst in the line of the read before it is
//   answered in its address phase with no wait state: l_hit says the
//   current line register holds the line of addr, the read before it, and
//   l_data is its doubleword l_dw, registered into HRDATA at the edge the
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
// Reads land in four line ways, so up to four can be in flight.  Each way
// has a tag and is valid (its line is here), pending (its read is queued or
// in flight) or neither; a pending way may also be poisoned.  The ways'
// data lives on the PCLK side, one 256-bit slot each in a LUT RAM: reads
// are queued in way order (rr, round robin) and come back in queue order, so
// the PCLK side fills the slots in the same order (p_way) and toggles the
// way's r_tog, which the bus side sees through two flops.  A way is taken
// again only once its line is back, so a slot holds still from its toggle
// until its way is next queued.  The bus side reads the RAM asynchronously
// at r_way, its register d_way, so the way select is the RAM's own read
// mux rather than a 4:1 mux of 1024 flops.
//
// A read in its data phase is looked up in the clock after its req rises
// (or once no write is in the queue's staging register): if the current
// line register (cl) holds its line, it is answered then, as stage 1's
// line buffer did; if a way holds the line or has it pending, it waits on
// that way (WAIT), and is answered from the way's slot in the clock its
// line is there; otherwise it queues a read into way rr in the clock after
// (MISS), once that way's own read is back and the queue has room, and
// waits on it.  Answering from a way copies the line into cl, so the
// burst's further beats are answered with no wait state.
//
// Every lookup also starts a prefetch of the next pf_depth lines (0 to 3, a
// register in exts_perf): in clocks with no lookup, no demand read to queue
// and no post, while post_ok promises room, each next line not already in a
// way, valid or pending, is queued into way rr, one every two clocks, never
// into the way a read waits on.  post_ok's promise holds: a prefetch takes
// a slot only in a clock no write is posted, and post_ok is renewed from
// the pointers after it.
//
// A write leaves every way and cl right as it reaches the queue's staging
// register: cl, and any valid way with its line, become invalid; a pending
// way with its line is poisoned, since its read was queued ahead of the
// write and will bring the old data, and becomes invalid, not valid, when
// that line comes back.  No way is queued in a clock a write is in the
// staging register, and a lookup waits while one is, so a read never sees
// a line older than a write ahead of it.  The A25 is the RAM port's only
// master.
//
// The bus clock and PCLK come from different PLLs.  The queue is an
// asynchronous FIFO with Gray-coded pointers (xfifo_w, xfifo_r); its LUT
// RAM is written on the bus clock from registers and read asynchronously on
// PCLK, which reads an entry only after its write pointer has come through
// two flops.  A read's line comes back the old way, by toggle and steady
// data (r_tog and the slots, above).
//
// The two halves are modules of their own, ahb_ddr3_bus and ahb_ddr3_pclk,
// so the AE350 image can place each beside its own side: the bus half near
// the AE350 macro, the PCLK half and the queue's RAM near ddr3_ctl, with
// only registers between them.  ahb_ddr3 joins them, for the bench.
//
// A reset of one side alone desynchronises the pointers and the ways; both
// sides are reset together at the hand-over and neither is reset after it.
//
// Simulation-only: MUT_MASK masks the lanes of the doubleword after the
// written one, MUT_NOINVAL leaves a valid way valid on a write to its line,
// MUT_NOPOISON leaves a pending way unpoisoned, MUT_CLKEEP leaves cl valid
// on a write, MUT_FULL lets xfifo_w promise room one entry late, and
// MUT_BYPASS lets xfifo_r hand a read out ahead of the write before it; the
// benches must fail each.  XFIFO_NOCHECK, and SYNTHESIS, leave out the
// queue's own checks, so tb_xfifo.v must catch its mutants by the data
// alone.
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
    input  wire [1:0]    pf_depth,

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
    wire          q_we;
    wire [3:0]    q_waddr, r_tog;
    wire [W-1:0]  q_wdata;
    wire [4:0]    q_wgray, q_rgray;
    wire [1:0]    r_way;
    wire [255:0]  r_slot;
    ahb_ddr3_bus #(.AW(AW)) bus (
        .clk(clk), .resetn(resetn), .l_dw(l_dw), .l_hit(l_hit), .l_data(l_data),
        .req(req), .post(post), .post_ok(post_ok), .addr(addr),
        .lanes(lanes), .wdata(wdata), .ack(ack), .rdata(rdata), .pf_depth(pf_depth),
        .q_we(q_we), .q_waddr(q_waddr), .q_wdata(q_wdata), .q_wgray(q_wgray),
        .q_rgray(q_rgray), .r_tog(r_tog), .r_way(r_way), .r_slot(r_slot),
        .dbg(), .p_miss(), .p_wait(), .p_pf(), .p_pfhit());
    ahb_ddr3_pclk #(.AW(AW)) pside (
        .bus_clk(clk), .pclk(pclk), .prst(prst),
        .q_we(q_we), .q_waddr(q_waddr), .q_wdata(q_wdata), .q_wgray(q_wgray),
        .q_rgray(q_rgray), .r_tog(r_tog), .r_way(r_way), .r_slot(r_slot), .p_open(),
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
    // it comes late, from ahb_ddr3_bus's prefetch and room logic
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

// the bus clock half: the ways' state, cl, prefetch and the queue's write side
module ahb_ddr3_bus #(
    parameter integer AW = 25
) (
    input  wire          clk,
    input  wire          resetn,
    // a read in its address phase in the line of addr: its doubleword, and
    // whether cl holds that line
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
    input  wire [1:0]    pf_depth,          // lines to prefetch past each lookup
    // to the PCLK half, each a register on the bus clock
    output wire          q_we,
    output wire [3:0]    q_waddr,
    output wire [AW+74:0] q_wdata,
    output wire [4:0]    q_wgray,
    output wire [1:0]    r_way,             // the slot to read: d_way
    // from it, each a register on PCLK but r_slot, its RAM read at r_way
    input  wire [4:0]    q_rgray,
    input  wire [3:0]    r_tog,
    input  wire [255:0]  r_slot,
    output wire [1:0]    dbg,               // {a read waits, a way is pending}, for the STALL report
    // one-clock pulses and levels for exts_perf, registered
    output reg           p_miss = 1'b0,     // a demand read queued
    output reg           p_wait = 1'b0,     // a read waits on a way (MISS or WAIT)
    output reg           p_pf = 1'b0,       // a prefetch queued
    output reg           p_pfhit = 1'b0     // a lookup found a prefetched line
);
    localparam [1:0] IDLE = 2'd0, MISS = 2'd1, WAIT = 2'd2;
    reg  [1:0]    st = IDLE;
    reg  [1:0]    d_way = 2'd0;             // the way a read waits on
    reg  [1:0]    rr = 2'd0;                // the way queued next

    reg  [3:0]    w_valid = 4'd0, w_pend = 4'd0, w_poison = 4'd0, w_pfb = 4'd0;
    reg  [4*AW-1:0] w_tag = {(4*AW){1'b0}};   // way k's at [AW*k +: AW]
    reg  [3:0]    r_s0 = 4'd0, r_s1 = 4'd0, r_s2 = 4'd0;   // r_tog through two flops, and the last
    wire [3:0]    ret = r_s2 ^ r_s1;        // a way's line is back

    reg           cl_valid = 1'b0;          // the current line
    reg  [AW-1:0] cl_tag = {AW{1'b0}};
    reg  [255:0]  cl_data = 256'd0;

    reg  [AW-1:0] pf_line = {AW{1'b0}};     // the next line to prefetch
    reg  [1:0]    pf_left = 2'd0;           // lines left to prefetch
    reg           pf_go = 1'b0;             // pf_line is in no way: queue it

    wire [AW-1:0] line = addr[AW+4:5];

    // the staging register, as written to the RAM: {write, line, dw, lanes, data}
    wire          s_we = q_wdata[AW+74];
    wire [AW-1:0] s_line = q_wdata[AW+73:74];
    wire          ws = q_we && s_we;

    integer k;
    wire [3:0] t_eq, pf_eq, s_eq;
    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : way
            assign t_eq[g] = w_tag[AW*g +: AW] == line;
            assign pf_eq[g] = w_tag[AW*g +: AW] == pf_line;
            assign s_eq[g] = w_tag[AW*g +: AW] == s_line;
        end
    endgenerate
    wire [3:0] have = w_valid | (w_pend & ~w_poison);   // the line is here or on its way
    wire [3:0] m_have = have & t_eq;
    wire [1:0] m_way = m_have[0] ? 2'd0 : m_have[1] ? 2'd1 : m_have[2] ? 2'd2 : 2'd3;
    wire       pf_have = |(have & pf_eq);

    wire cl_hit = cl_valid && cl_tag == line;
    assign l_hit = cl_hit;
    assign l_data = cl_data[64*l_dw +: 64];

    wire look = req && st == IDLE && !ws;
    wire w_ready = w_valid[d_way] || (ret[d_way] && !w_poison[d_way]);
    assign ack = (look && cl_hit) || (st == WAIT && w_ready);
    assign r_way = d_way;
    assign rdata = st == WAIT ? r_slot[64*addr[4:3] +: 64] : cl_data[64*addr[4:3] +: 64];

    // one push a clock: a post, else a demand read, else a prefetch
    wire full;
    wire dm_push = st == MISS && !w_pend[rr] && !full;
    wire pf_push = pf_go && !look && st != MISS && !ws && !post && post_ok && !w_pend[rr] &&
                   !(st == WAIT && rr == d_way);
    wire alloc = dm_push || pf_push;
    wire [AW-1:0] a_line = pf_push ? pf_line : line;
    wire push = post || alloc;
    xfifo_w #(.W(AW + 75), .LOG2(4), .LEAD(2)) fw (
        .clk(clk), .rst(!resetn), .push(push),
        .din({post, a_line, addr[4:3], lanes, wdata}),
        .full(full), .room(post_ok),
        .q_we(q_we), .q_waddr(q_waddr), .q_wdata(q_wdata), .q_wgray(q_wgray),
        .q_rgray(q_rgray));

    assign dbg = {st != IDLE, |w_pend};

    always @(posedge clk) begin
        if (!resetn) begin
            st <= IDLE;
            rr <= 2'd0;
            w_valid <= 4'd0;
            w_pend <= 4'd0;
            w_poison <= 4'd0;
            w_pfb <= 4'd0;
            r_s0 <= 4'd0;
            r_s1 <= 4'd0;
            r_s2 <= 4'd0;
            cl_valid <= 1'b0;
            pf_left <= 2'd0;
            pf_go <= 1'b0;
            {p_miss, p_wait, p_pf, p_pfhit} <= 4'd0;
        end else begin
            r_s0 <= r_tog;
            r_s1 <= r_s0;
            r_s2 <= r_s1;
            p_miss <= dm_push;
            p_wait <= st != IDLE;
            p_pf <= pf_push;
            p_pfhit <= 1'b0;

            // the ways: a line back, then a write in staging, then a way queued
            for (k = 0; k < 4; k = k + 1) begin
                if (ret[k]) begin
                    w_pend[k] <= 1'b0;
                    w_valid[k] <= !w_poison[k];
                    w_poison[k] <= 1'b0;
                end
                if (ws && s_eq[k]) begin
`ifndef MUT_NOINVAL
                    w_valid[k] <= 1'b0;
`endif
`ifndef MUT_NOPOISON
                    if (w_pend[k] && !ret[k])
                        w_poison[k] <= 1'b1;
`endif
                end
                if (alloc && rr == k) begin
                    w_valid[k] <= 1'b0;
                    w_pend[k] <= 1'b1;
                    w_poison[k] <= 1'b0;
                    w_pfb[k] <= pf_push;
                    w_tag[AW*k +: AW] <= a_line;
                end
            end
            if (alloc)
                rr <= rr + 1'b1;
`ifndef MUT_CLKEEP
            if (ws)
                cl_valid <= 1'b0;
`endif

            // the read in its data phase
            case (st)
                IDLE:
                    if (look && !cl_hit) begin
                        if (|m_have) begin
                            st <= WAIT;
                            d_way <= m_way;
                            if (w_pfb[m_way]) begin
                                p_pfhit <= 1'b1;
                                w_pfb[m_way] <= 1'b0;
                            end
                        end else
                            st <= MISS;
                    end
                MISS:
                    if (dm_push) begin
                        st <= WAIT;
                        d_way <= rr;
                    end
                default:
                    if (w_ready) begin
                        st <= IDLE;
                        cl_valid <= 1'b1;
                        cl_tag <= line;
                        cl_data <= r_slot;
                    end
            endcase

            // the prefetch: each lookup restarts it past its line
            if (look) begin
                pf_line <= line + 1'b1;
                pf_left <= pf_depth;
                pf_go <= 1'b0;
            end else if (pf_push) begin
                pf_line <= pf_line + 1'b1;
                pf_left <= pf_left - 1'b1;
                pf_go <= 1'b0;
            end else if (!pf_go && pf_left != 2'd0) begin
                if (pf_have) begin
                    pf_line <= pf_line + 1'b1;
                    pf_left <= pf_left - 1'b1;
                end else
                    pf_go <= 1'b1;
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk)
        if (resetn) begin
            if (post && (req || st != IDLE)) begin
                $display("FAIL  ahb_ddr3: a write posted while a read was open at t=%0t", $time);
                $finish;
            end
            if (|(ret & ~w_pend)) begin
                $display("FAIL  ahb_ddr3: a line came back to a way with no read open at t=%0t", $time);
                $finish;
            end
            if (st == WAIT && w_poison[d_way]) begin
                $display("FAIL  ahb_ddr3: a read waits on a poisoned way at t=%0t", $time);
                $finish;
            end
        end
`endif
endmodule

// the PCLK half: the queue's read side, the request into ddr3_ctl, and the
// lines back into the ways' slots
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
    output reg  [3:0]    r_tog = 4'd0,
    input  wire [1:0]    r_way,             // a bus clock register
    output wire [255:0]  r_slot,            // slot r_way, still from r_tog[r_way]'s move until that way is queued again
    output reg  [2:0]    p_open = 3'd0,     // reads taken and not back, for ddr3_perf's tap
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
`ifdef MUT_MASK
    wire [1:0] m_dw = head[73:72] + 2'd1;
`else
    wire [1:0] m_dw = head[73:72];
`endif
    reg  [1:0] p_way = 2'd0;                // the slot the next line goes to
    (* ram_style = "distributed" *) reg [255:0] slot [0:3];
    always @(posedge pclk)
        if (!prst && rdata_valid)
            slot[p_way] <= rdata_line;
    assign r_slot = slot[r_way];

    // p_open counts from registered strobes, a PCLK late, so this tap adds
    // nothing to cmd_ready's path
    wire       rd_take = cmd_valid && cmd_ready && !cmd_we;
    reg        o_take = 1'b0, o_back = 1'b0;
    integer k;
    always @(posedge pclk) begin
        o_take <= !prst && rd_take;
        o_back <= !prst && rdata_valid;
        if (prst) begin
            r_tog <= 4'd0;
            p_way <= 2'd0;
            p_open <= 3'd0;
            cmd_valid <= 1'b0;
        end else begin
            if (cmd_valid && cmd_ready)
                cmd_valid <= 1'b0;
            if (pop) begin
                cmd_valid <= 1'b1;
                cmd_we <= head[AW+74];
                cmd_addr <= head[AW+73:74];
                cmd_wd <= head[63:0];
                cmd_wmask <= ~({24'd0, head[71:64]} << (8 * m_dw));
            end
            p_open <= p_open + o_take - o_back;
            if (rdata_valid) begin
                for (k = 0; k < 4; k = k + 1)
                    if (p_way == k)
                        r_tog[k] <= ~r_tog[k];
                p_way <= p_way + 1'b1;
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge pclk)
        if (!prst && o_back && p_open == 3'd0)
            $fatal(1, "ahb_ddr3: read data arrived with no read open");
`endif
endmodule

`default_nettype wire
