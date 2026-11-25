`default_nettype none

// The controller's first user: a memory test on ddr3_ctl's request port.
//
// Each pass writes words 0 .. 2^N_LOG2 - 1 in order, reads them back in
// order with a READ offered every PCLK, then reads 2^R_LOG2 words at
// pseudo-random addresses in that range, and checks every word read against
// what its address was written with.  Words are 256 bits, one BL8 burst of
// the x32 array, so N_LOG2 = 25 covers the whole 1 GiB.
//
// The data is each address's own and changes every pass: beat k, 32 bits,
// is one xorshift32 round (XOR only, no carry chain) of the address, k and
// the pass's seed, so every DQ pin carries its own sequence and no two
// words, beats or passes are alike.
//
// With MASKPASS, each pass writes every word a second time, before reading
// any, with the inverse of its data under a write mask: bit 4b + l of the
// mask, set, suppresses beat b's byte on lane l, and the mask is one more
// xorshift of the address, so about half of every word's 32 bytes are
// suppressed and which ones change from word to word and pass to pass.  The
// inverse needs no logic of its own: gen() is linear, and with its seed XORed
// with KINV it returns the complement of every beat.  Every word read is then
// owed its first data with the bytes the mask let through inverted, so a byte
// written when it should have been suppressed, or the reverse, fails in all
// eight of its bits.
//
// A write carries its data, made from its address as the port takes it.
// ddr3_ctl returns read data in request order, so each word read is checked
// against the oldest read address, kept in a FIFO; a READ is offered only
// with room in it, and every request is held until the port takes it.
//
// Errors are counted per lane, a word whose lane l (DQ 8l..8l+7, any beat)
// differs counting once for that lane, and the first failing word's address
// and the XOR of what came back with what was owed are kept.  For finding
// why words fail, the test also counts, per DQ pin, the words in which that
// pin differed in any beat, and per lane and beat the words in which that
// lane's byte of that beat differed; and it logs the first eight failing
// words and reads each again at once, before the pass writes anything, so a
// word that comes back right was read wrong and one that comes back wrong
// the same way was written wrong.  Entry e of the log, at [64e +: 64]:
//
//   [24:0]   the word's address        [28:25]  its lanes that differed
//   [36:29]  its beats that differed   [37]     its re-read was issued
//   [38]     the re-read was checked   [39]     the re-read was right
//   [40]     the re-read was what the first read was
//   [41]     in the random READs       [55:42]  the pass, its low 14 bits
module ddr3_bist #(
    parameter integer AW = 25,          // native port address, 256-bit words
    parameter integer N_LOG2 = 25,      // words written and read per pass
    parameter integer R_LOG2 = 20,      // random READs per pass
    parameter integer MASKPASS = 1      // the masked inverse write pass (0: the test of 0d3bce3)
) (
    input  wire          pclk,
    input  wire          rst,           // also stops the test
    input  wire          clr,           // clear the counts and the first error

    output reg           cmd_valid = 1'b0,
    input  wire          cmd_ready,
    output reg           cmd_we = 1'b0,
    output reg  [AW-1:0] cmd_addr = {AW{1'b0}},
    output wire [255:0]  cmd_wdata,
    output wire [31:0]   cmd_wmask,     // 1 suppresses beat b, lane l at 4b + l
    input  wire          rdata_valid,
    input  wire [255:0]  rdata_data,

    output reg  [3:0]    state = 4'd0,
    output reg  [15:0]   passes = 16'd0,
    output reg  [31:0]   n_written = 32'd0,
    output reg  [31:0]   n_checked = 32'd0,
    output reg  [127:0]  lane_err = 128'd0,     // lane l at [32l +: 32]
    output reg           err_seen = 1'b0,
    output reg  [AW-1:0] err_addr = {AW{1'b0}},
    output reg  [255:0]  err_diff = 256'd0,
    output reg  [511:0]  pin_err = 512'd0,      // DQ q at [16q +: 16]
    output reg  [511:0]  beat_err = 512'd0,     // lane l, beat b at [16(8l + b) +: 16]
    output reg  [511:0]  elog = 512'd0,         // entry e at [64e +: 64]
    output reg  [3:0]    n_log = 4'd0
);

    function [255:0] gen(input [AW-1:0] a, input [31:0] s);
        integer gk;
        reg [2:0] g3;
        reg [31:0] x;
        begin
            for (gk = 0; gk < 8; gk = gk + 1) begin
                g3 = gk;
                x = {a, g3} ^ s ^ (32'h9e3779b9 * (gk + 1));
                x = x ^ (x << 13);
                x = x ^ (x >> 17);
                x = x ^ (x << 5);
                gen[32*gk +: 32] = x;
            end
        end
    endfunction

    function [31:0] xs_next(input [31:0] x);
        reg [31:0] y;
        begin
            y = x ^ (x << 13);
            y = y ^ (y >> 17);
            xs_next = y ^ (y << 5);
        end
    endfunction

    localparam [3:0] S_IDLE = 4'd0, S_WR = 4'd1, S_WRW = 4'd2, S_RD = 4'd3, S_RDW = 4'd4,
                     S_RR = 4'd5, S_RRW = 4'd6, S_MW = 4'd7, S_MWW = 4'd8;
    // gen(a, s ^ KINV) is ~gen(a, s) in every beat (xorshift32(KINV) is all ones),
    // and the mask of address a is beat 0 of gen(a, s ^ KM)
    localparam [31:0] KINV = 32'h5e6cfce7;
    localparam [31:0] KM = 32'h7f4a7c15;
    localparam integer DEPTH = 64;
    localparam [AW-1:0] LAST = (1 << N_LOG2) - 1;
    localparam [31:0] RLAST = (1 << R_LOG2) - 1;

    reg [31:0]   seed = 32'h2545f491;
    // counts the pass's random READs, 0 to RLAST: R_LOG2 bits, not 32, so its
    // carry chain is short (as 32 bits it was 1.1 ns over 100 MHz fully timed)
    reg [R_LOG2-1:0] rcnt = {R_LOG2{1'b0}};
    reg [31:0]   lfsr = 32'h1;

    // the words owed, as {re-read, address}
    // in LUT RAM, read asynchronously into c0_a: inferred as block RAM, the
    // read register moved into it and its 2.82 ns clock-to-output led the
    // address into gen() 0.09 ns over 100 MHz, the design's worst path
    (* ram_style = "distributed" *) reg [AW:0]   rq [0:DEPTH-1];
    reg [5:0]    rq_w = 6'd0, rq_r = 6'd0;
    reg [6:0]    rq_n = 7'd0;
    wire         take = cmd_valid && cmd_ready;
    wire         rpop = rdata_valid && (rq_n != 7'd0);
    // (registered at set_addr instead, gen sat behind the address and seed
    // adders and put the word 4.7 ns over 100 MHz fully timed, against 1.6 ns
    // into the controller's FIFO as it is here)
    // the writes' seed: the pass's, or the pass's with KINV in the masked pass
    reg  [31:0]  wseed = 32'h2545f491;
    reg          mpass = 1'b0;          // in the masked pass
    function [31:0] mfun(input [AW-1:0] a, input [31:0] s);
        reg [255:0] g;
        begin
            g = gen(a, s ^ KM);
            mfun = g[31:0];
        end
    endfunction
    // a word's 32 mask bits to its 256 data bits: byte (beat b, lane l) at
    // 32b + 8l from bit 4b + l
    function [255:0] mexp(input [31:0] m);
        integer eb, el;
        begin
            for (eb = 0; eb < 8; eb = eb + 1)
                for (el = 0; el < 4; el = el + 1)
                    mexp[32*eb + 8*el +: 8] = {8{m[4*eb + el]}};
        end
    endfunction
    assign cmd_wdata = gen(cmd_addr, wseed);
    assign cmd_wmask = mpass ? mfun(cmd_addr, seed) : 32'd0;

    // the check, three PCLK behind the word, each step registered for 100 MHz:
    // c0 the word and the address it is owed (the FIFO's head), ck the word
    // owed made from it, d the difference and its per-lane, -beat and -pin
    // flags; the counts and the log take d's.
    reg          c0_v = 1'b0, c0_retry = 1'b0;
    reg [AW-1:0] c0_a = {AW{1'b0}};
    reg [255:0]  c0_got = 256'd0;
    reg          ck_v = 1'b0, ck_retry = 1'b0;
    reg [AW-1:0] ck_a = {AW{1'b0}};
    reg [255:0]  ck_got = 256'd0, ck_exp = 256'd0;
    wire [255:0] diff = ck_got ^ ck_exp;
    reg  [3:0]   lane_bad;
    integer cl, cb;
    always @(*)
        for (cl = 0; cl < 4; cl = cl + 1) begin
            lane_bad[cl] = 1'b0;
            for (cb = 0; cb < 8; cb = cb + 1)
                if (diff[32*cb + 8*cl +: 8] != 8'd0)
                    lane_bad[cl] = 1'b1;
        end

    // room for one more READ after the one being taken
    // (rq_n + 1 < DEPTH - 2 as rq_n < DEPTH - 3: both compares of a register
    // run beside `take` instead of an adder behind it, which put cmd_valid
    // 4 ns over 100 MHz fully timed)
    wire rroom = (take && !cmd_we) ? (rq_n < DEPTH - 3) : (rq_n < DEPTH - 2);

    // the re-read: one at a time, of the newest logged word
    reg          cmd_retry = 1'b0;      // the READ offered is a re-read
    reg          retry_pend = 1'b0, retry_fly = 1'b0;
    reg [2:0]    retry_idx = 3'd0;
    reg [7:0]    retry_oh = 8'd1;       // retry_idx, one-hot
    reg          mark_v = 1'b0;         // a re-read was issued last PCLK
    reg [7:0]    mark_oh = 8'd1;        // its entry
    reg [AW-1:0] retry_addr = {AW{1'b0}}, resume = {AW{1'b0}};
    // the logged word's difference: a re-read of the same address in the
    // same pass is owed the same word, so it came back as the first read did
    // exactly when its difference is the same
    reg [255:0]  retry_diff = 256'd0;
    reg  [31:0]  pin_bad;
    reg  [31:0]  lb_bad;                // lane l, beat b at 8l + b
    reg  [7:0]   beat_bad;
    // the d stage
    reg          d_v = 1'b0, d_retry = 1'b0;
    // per byte: the difference is retry_diff's.  Only their AND is used, and
    // 64-bit compares put it 1.7 ns over 100 MHz fully timed (TOOL-065); a
    // copy of the word for the compare alone, 256 more flops beside the
    // other 256-bit stages, left the placer unable to legalise 3 seeds of 5
    reg  [31:0]  d_same = 32'd0;
    // the log's entry is written a PCLK after the word is judged
    reg          l_v = 1'b0;
    reg  [2:0]   l_idx = 3'd0;
    // the log's entry selects, one-hot beside their indices: decoding an
    // index in front of 512 bits of log put it 1.6 ns over 100 MHz fully
    // timed (TOOL-065)
    reg  [7:0]   l_oh = 8'd1;
    integer      le;
    reg  [63:0]  l_data = 64'd0;
    reg [AW-1:0] d_a = {AW{1'b0}};
    reg [255:0]  d_diff = 256'd0;
    reg  [3:0]   d_lane = 4'd0;
    reg  [7:0]   d_beat = 8'd0;
    reg  [31:0]  d_pin = 32'd0, d_lb = 32'd0;
    integer cq, cv;
    always @(*) begin
        for (cq = 0; cq < 32; cq = cq + 1) begin
            pin_bad[cq] = 1'b0;
            for (cv = 0; cv < 8; cv = cv + 1)
                if (diff[32*cv + cq]) pin_bad[cq] = 1'b1;
        end
        for (cv = 0; cv < 8; cv = cv + 1) begin
            beat_bad[cv] = (diff[32*cv +: 32] != 32'd0);
            for (cq = 0; cq < 4; cq = cq + 1)
                lb_bad[8*cq + cv] = (diff[32*cv + 8*cq +: 8] != 8'd0);
        end
    end
    function [15:0] inc16(input [15:0] a);
        inc16 = (a == 16'hffff) ? a : a + 16'd1;
    endfunction

    // cmd_addr == LAST and rcnt == RLAST, registered with the values they
    // describe: compared where the passes branch on them they put the re-read
    // and the log 4.8 ns over 100 MHz fully timed (TOOL-065)
    reg          a_last = (LAST == 0), r_last = (RLAST == 0);
    task set_addr(input [AW-1:0] v);
        begin
            cmd_addr <= v;
            a_last <= (v == LAST);
        end
    endtask
    // the next address: compared as cmd_addr == LAST - 1, not as the sum,
    // so no adder sits in front of the compare (as for rcnt below)
    task inc_addr;
        begin
            cmd_addr <= cmd_addr + 1'b1;
            a_last <= (cmd_addr == LAST - 1);
        end
    endtask
    task set_rcnt(input [R_LOG2-1:0] v);
        begin
            rcnt <= v;
            r_last <= (v == RLAST[R_LOG2-1:0]);
        end
    endtask
    task inc_rcnt;
        begin
            rcnt <= rcnt + 1'b1;
            r_last <= (rcnt == RLAST[R_LOG2-1:0] - 1'b1);
        end
    endtask

    integer ql, qs;
    always @(posedge pclk) begin
        // the log entry judged last PCLK; first, so that a re-read's flags
        // set at the same edge below take precedence over its zeros
        l_v <= 1'b0;
        if (l_v)
            for (le = 0; le < 8; le = le + 1)
                if (l_oh[le]) elog[64*le +: 64] <= l_data;

        // the FIFO
        if (take && !cmd_we) begin
            rq[rq_w] <= {cmd_retry, cmd_addr};
            rq_w <= rq_w + 6'd1;
        end
        if (rpop)
            rq_r <= rq_r + 6'd1;
        rq_n <= rq_n + ((take && !cmd_we) ? 7'd1 : 7'd0) - (rpop ? 7'd1 : 7'd0);

        // the check: c0, then ck, then d
        c0_v <= rpop;
        c0_retry <= rq[rq_r][AW];
        c0_a <= rq[rq_r][AW-1:0];
        c0_got <= rdata_data;
        ck_v <= c0_v;
        ck_retry <= c0_retry;
        ck_a <= c0_a;
        ck_got <= c0_got;
        // with the masked pass, the bytes its mask let through were inverted
        ck_exp <= (MASKPASS != 0) ? gen(c0_a, seed) ^ mexp(~mfun(c0_a, seed)) : gen(c0_a, seed);
        d_v <= ck_v;
        d_retry <= ck_retry;
        d_a <= ck_a;
        d_diff <= diff;
        d_lane <= lane_bad;
        d_beat <= beat_bad;
        d_pin <= pin_bad;
        d_lb <= lb_bad;
        for (qs = 0; qs < 32; qs = qs + 1)
            d_same[qs] <= (diff[8*qs +: 8] == retry_diff[8*qs +: 8]);
        if (take && cmd_we && n_written != 32'hffffffff)
            n_written <= n_written + 32'd1;
        if (d_v && d_retry) begin
            for (le = 0; le < 8; le = le + 1)
                if (retry_oh[le]) begin
                    elog[64*le + 38] <= 1'b1;
                    elog[64*le + 39] <= (d_lane == 4'd0);
                    elog[64*le + 40] <= &d_same;
                end
            retry_fly <= 1'b0;
        end
        if (d_v && !d_retry) begin
            for (ql = 0; ql < 32; ql = ql + 1) begin
                if (d_pin[ql]) pin_err[16*ql +: 16] <= inc16(pin_err[16*ql +: 16]);
                if (d_lb[ql]) beat_err[16*ql +: 16] <= inc16(beat_err[16*ql +: 16]);
            end
            if (|d_lane && n_log != 4'd8) begin
                l_v <= 1'b1;
                l_idx <= n_log[2:0];
                l_oh <= 8'd1 << n_log[2:0];
                l_data <= {8'd0, passes[13:0], state == S_RR, 4'd0, d_beat, d_lane, d_a};
                n_log <= n_log + 4'd1;
                if (!retry_pend && !retry_fly && (state == S_RD || state == S_RR)) begin
                    retry_pend <= 1'b1;
                    retry_idx <= n_log[2:0];
                    retry_oh <= 8'd1 << n_log[2:0];
                    retry_addr <= d_a;
                    retry_diff <= d_diff;
                end
            end
        end
        if (d_v && !d_retry) begin
            if (n_checked != 32'hffffffff)
                n_checked <= n_checked + 32'd1;
            for (ql = 0; ql < 4; ql = ql + 1)
                if (d_lane[ql] && lane_err[32*ql +: 32] != 32'hffffffff)
                    lane_err[32*ql +: 32] <= lane_err[32*ql +: 32] + 32'd1;
            if (|d_lane && !err_seen) begin
                err_seen <= 1'b1;
                err_addr <= d_a;
                err_diff <= d_diff;
            end
        end
        if (mark_v)
            for (le = 0; le < 8; le = le + 1)
                if (mark_oh[le]) elog[64*le + 37] <= 1'b1;
        if (clr) begin
            passes <= 16'd0;
            n_written <= 32'd0;
            n_checked <= 32'd0;
            lane_err <= 128'd0;
            err_seen <= 1'b0;
            pin_err <= 512'd0;
            beat_err <= 512'd0;
            elog <= 512'd0;
            l_v <= 1'b0;
            n_log <= 4'd0;
            retry_pend <= 1'b0;
        end

        // the passes
        case (state)
            S_IDLE: begin
                cmd_we <= 1'b1;
                set_addr({AW{1'b0}});
                cmd_valid <= 1'b1;
                state <= S_WR;
            end
            S_WR: if (take) begin
                if (a_last) begin
                    cmd_valid <= 1'b0;
                    state <= S_WRW;
                end else
                    inc_addr;
            end
            S_WRW: begin
                set_addr({AW{1'b0}});
                cmd_valid <= 1'b1;
                if (MASKPASS != 0) begin        // every word again, inverted, masked
                    mpass <= 1'b1;
                    wseed <= seed ^ KINV;
                    state <= S_MW;
                end else begin
                    cmd_we <= 1'b0;
                    state <= S_RD;
                end
            end
            S_MW: if (take) begin
                if (a_last) begin
                    cmd_valid <= 1'b0;
                    state <= S_MWW;
                end else
                    inc_addr;
            end
            S_MWW: begin
                mpass <= 1'b0;
                wseed <= seed;
                cmd_we <= 1'b0;
                set_addr({AW{1'b0}});
                cmd_valid <= 1'b1;
                state <= S_RD;
            end
            S_RD: if (take) begin
                if (cmd_retry) begin            // back to where the re-read cut in
                    cmd_retry <= 1'b0;
                    set_addr(resume);
                    cmd_valid <= rroom;
                end else if (a_last) begin
                    cmd_valid <= 1'b0;
                    retry_pend <= 1'b0;
                    state <= S_RDW;
                end else if (retry_pend) begin  // the re-read next
                    resume <= cmd_addr + 1'b1;
                    set_addr(retry_addr);
                    cmd_retry <= 1'b1;
                    retry_pend <= 1'b0;
                    retry_fly <= 1'b1;
                    cmd_valid <= rroom;
                end else begin
                    inc_addr;
                    cmd_valid <= rroom;
                end
            end else if (!cmd_valid && rroom)
                cmd_valid <= 1'b1;
            S_RDW: if (rq_n == 7'd0 && !c0_v && !ck_v && !d_v) begin
                set_rcnt({R_LOG2{1'b0}});
                set_addr(lfsr[AW-1:0] & LAST);
                cmd_valid <= 1'b1;
                state <= S_RR;
            end
            S_RR: if (take) begin
                if (cmd_retry) begin
                    cmd_retry <= 1'b0;
                    set_addr(resume);
                    cmd_valid <= rroom;
                end else begin
                    lfsr <= xs_next(lfsr);      // the next random address
                    if (r_last) begin
                        cmd_valid <= 1'b0;
                        retry_pend <= 1'b0;
                        state <= S_RRW;
                    end else begin
                        inc_rcnt;
                        if (retry_pend) begin
                            resume <= xs_next(lfsr) & LAST;
                            set_addr(retry_addr);
                            cmd_retry <= 1'b1;
                            retry_pend <= 1'b0;
                            retry_fly <= 1'b1;
                        end else
                            set_addr(xs_next(lfsr) & LAST);
                        cmd_valid <= rroom;
                    end
                end
            end else if (!cmd_valid && rroom)
                cmd_valid <= 1'b1;
            S_RRW: if (rq_n == 7'd0 && !c0_v && !ck_v && !d_v) begin
                if (passes != 16'hffff)
                    passes <= passes + 16'd1;
                seed <= seed + 32'h9e3779b9;
                wseed <= seed + 32'h9e3779b9;
                cmd_we <= 1'b1;
                set_addr({AW{1'b0}});
                cmd_valid <= 1'b1;
                state <= S_WR;
            end
            default: state <= S_IDLE;
        endcase
        // the re-read's issue, marked in bit 37 of its entry a PCLK later
        // (above, before clr): marked at the issue, behind take and the read
        // states' branches and in front of 512 bits of log, it was 1.1 to
        // 3.3 ns over 100 MHz fully timed (TOOL-065).  Nothing here reads the
        // log, and the entry cannot change in between, as the re-read is in
        // flight.
        mark_v <= take && !cmd_retry && retry_pend &&
                  ((state == S_RD && !a_last) || (state == S_RR && !r_last));
        mark_oh <= retry_oh;
        if (rst) begin
            state <= S_IDLE;
            cmd_valid <= 1'b0;
            rq_w <= 6'd0; rq_r <= 6'd0; rq_n <= 7'd0;
            c0_v <= 1'b0; ck_v <= 1'b0; d_v <= 1'b0;
            cmd_retry <= 1'b0;
            retry_pend <= 1'b0;
            retry_fly <= 1'b0;
            mpass <= 1'b0;
            wseed <= seed;
        end
    end
`ifndef SYNTHESIS
    // the flags must equal the compares they stand for at every edge
    always @(posedge pclk) begin
        if (wseed != (mpass ? seed ^ KINV : seed))
            $fatal(1, "FAIL  ddr3_bist: the write seed is not the pass's");
        if (a_last != (cmd_addr == LAST) || r_last != (rcnt == RLAST[R_LOG2-1:0]))
            $fatal(1, "FAIL  ddr3_bist: a_last or r_last disagrees with its compare");
    end
`endif
endmodule

`default_nettype wire
