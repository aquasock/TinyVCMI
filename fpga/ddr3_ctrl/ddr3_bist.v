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
    parameter integer R_LOG2 = 20       // random READs per pass
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
    output reg  [3:0]    n_log = 4'd0,
    // the test's two independent variables, from command 0x3C 0x5m:
    // m[0] folds the address with XOR and shifts only, as this test did
    // before the adder, and m[1] writes each word once instead of twice.
    // Each isolates one of the two changes that arrived together with the
    // doubled write, so the board can say which of them the read failures
    // belong to.  Latched at a pass boundary, so a change cannot land
    // between a word's write and its check.
    input  wire [1:0]    tm_mode,
    // idle PCLK between a word's two writes, command 0x3C 0x60 + lo and
    // 0x3C 0x70 + hi: zero keeps them back to back as they always were, and a
    // spacing wide enough for the device's write-to-write turnaround separates
    // a second write to the same address from the mask byte's own path.
    input  wire [7:0]    tm_gap
);
    // the log entry on its way to elog, one PCLK behind the check
    reg         log_v = 1'b0;
    reg  [2:0]  log_idx = 3'd0;
    reg  [63:0] log_d = 64'd0;

    function [255:0] gen(input [AW-1:0] a, input [31:0] s, input [31:0] add);
        integer gk;
        reg [2:0] g3;
        reg [31:0] x;
        begin
            for (gk = 0; gk < 8; gk = gk + 1) begin
                g3 = gk;
                x = {a, g3} ^ s ^ (32'h9e3779b9 * (gk + 1));
                // the address again, through the adder's carries.  XOR and
                // shifts are linear, so a one-bit address step came out a few
                // bits apart and the test could not tell one address's word
                // from its neighbour's; a carry spreads it through the word.
                // `add` is the address through the adder's carries, or zero
                // for the old fold that the experiment switches back to.  It is
                // selected outside, once per word, so the mode costs one 32-bit
                // mux on the address rather than one per beat on the data.
                x = x + add;
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
                     S_RR = 4'd5, S_RRW = 4'd6, S_WG = 4'd7;
    localparam integer DEPTH = 64;
    localparam [AW-1:0] LAST = (1 << N_LOG2) - 1;
    localparam [31:0] RLAST = (1 << R_LOG2) - 1;

    reg [1:0]    pmode = 2'd0;        // tm_mode, latched at a pass boundary
    reg [7:0]    gap_cnt = 8'd0;      // the idle PCLK before a word's second write
    reg [31:0]   seed = 32'h2545f491;
    reg [31:0]   seed_b = 32'h5bf03635;  // the second write of a word
    reg          w2nd = 1'b0;           // the masked write of the current word
    reg [31:0]   rcnt = 32'd0;
    reg [31:0]   lfsr = 32'h1;

    // the words owed, as {re-read, address}
    reg [AW:0]   rq [0:DEPTH-1];
    reg [5:0]    rq_w = 6'd0, rq_r = 6'd0;
    reg [6:0]    rq_n = 7'd0;
    wire         take = cmd_valid && cmd_ready;
    wire         rpop = rdata_valid && (rq_n != 7'd0);

    // A word is written twice: its pattern whole, then a second pattern
    // through a mask, so the read must see the two merged.  The mask never
    // lets the test forget what a masked byte is meant to keep: some
    // addresses write every byte, and some suppress every byte, whose word
    // must stay exactly as the first write left it.
    function [31:0] mgen(input [AW-1:0] a, input [31:0] s);
        reg [31:0] x;
        begin
            if (a[4:0] == 5'd0)
                mgen = 32'h00000000;        // write every byte
            else if (a[4:0] == 5'd1)
                mgen = 32'hffffffff;        // suppress every byte
            else begin
                x = 32'd1 << (a[4:0] - 5'd2);   // one bit: 0 .. 29
                mgen = x;
            end
        end
    endfunction

    // what a masked write leaves: the masked bytes of a, the rest of b
    function [255:0] merge(input [255:0] a, input [255:0] b, input [31:0] m);
        integer mk, mb;
        begin
            for (mb = 0; mb < 8; mb = mb + 1)
                for (mk = 0; mk < 4; mk = mk + 1)
                    merge[32*mb + 8*mk +: 8] = m[4*mb + mk] ? a[32*mb + 8*mk +: 8]
                                                           : b[32*mb + 8*mk +: 8];
        end
    endfunction

    wire [31:0] add_w = pmode[0] ? 32'd0 : {7'd0, cmd_addr};
    wire [31:0] add_r = pmode[0] ? 32'd0 : {7'd0, rq[rq_r][AW-1:0]};
    assign cmd_wdata = w2nd ? gen(cmd_addr, seed_b, add_w)
                            : gen(cmd_addr, seed, add_w);
    assign cmd_wmask = w2nd ? mgen(cmd_addr, seed) : 32'h0;

    // the check, a PCLK behind the word
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
    wire rroom = (rq_n + (take && !cmd_we ? 7'd1 : 7'd0)) < DEPTH - 2;

    // the re-read: one at a time, of the newest logged word
    reg          cmd_retry = 1'b0;      // the READ offered is a re-read
    reg          retry_pend = 1'b0, retry_fly = 1'b0;
    reg [2:0]    retry_idx = 3'd0;
    reg [AW-1:0] retry_addr = {AW{1'b0}}, resume = {AW{1'b0}};
    reg [255:0]  retry_got = 256'd0;
    reg  [31:0]  pin_bad;
    reg  [31:0]  lb_bad;                // lane l, beat b at 8l + b
    reg  [7:0]   beat_bad;
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

    integer ql;
    always @(posedge pclk) begin
        // the FIFO
        if (take && !cmd_we) begin
            rq[rq_w] <= {cmd_retry, cmd_addr};
            rq_w <= rq_w + 6'd1;
        end
        if (rpop)
            rq_r <= rq_r + 6'd1;
        rq_n <= rq_n + ((take && !cmd_we) ? 7'd1 : 7'd0) - (rpop ? 7'd1 : 7'd0);

        // the check
        ck_v <= rpop;
        ck_retry <= rq[rq_r][AW];
        ck_a <= rq[rq_r][AW-1:0];
        ck_got <= rdata_data;
        ck_exp <= merge(gen(rq[rq_r][AW-1:0], seed, add_r),
                        gen(rq[rq_r][AW-1:0], seed_b, add_r),
                        pmode[1] ? 32'hffffffff : mgen(rq[rq_r][AW-1:0], seed));
        if (take && cmd_we && n_written != 32'hffffffff)
            n_written <= n_written + 32'd1;
        if (ck_v && ck_retry) begin
            elog[64*retry_idx + 38] <= 1'b1;
            elog[64*retry_idx + 39] <= (diff == 256'd0);
            elog[64*retry_idx + 40] <= (ck_got == retry_got);
            retry_fly <= 1'b0;
        end
        // The log entry is captured here and written a PCLK later.  Written in
        // place, its data cone ran from the comparator through eight LUT4s into
        // the register -- 4.62 ns of logic and 6.04 ns of routing in one
        // placement, and the critical path of the whole image at 93.81 MHz --
        // because lane_bad and beat_bad are wide reductions of the XOR and the
        // entry lands in a n_log-indexed slice.  Registering the entry first
        // leaves the write a register-to-register copy.
        log_v <= !rst && ck_v && !ck_retry && (|lane_bad) && (n_log != 4'd8);
        log_idx <= n_log[2:0];
        log_d <= {8'd0, passes[13:0], state == S_RR, 4'd0, beat_bad, lane_bad, ck_a};
        if (log_v)
            elog[64*log_idx +: 64] <= log_d;

        if (ck_v && !ck_retry) begin
            for (ql = 0; ql < 32; ql = ql + 1) begin
                if (pin_bad[ql]) pin_err[16*ql +: 16] <= inc16(pin_err[16*ql +: 16]);
                if (lb_bad[ql]) beat_err[16*ql +: 16] <= inc16(beat_err[16*ql +: 16]);
            end
            if (|lane_bad && n_log != 4'd8) begin
                n_log <= n_log + 4'd1;
                if (!retry_pend && !retry_fly && (state == S_RD || state == S_RR)) begin
                    retry_pend <= 1'b1;
                    retry_idx <= n_log[2:0];
                    retry_addr <= ck_a;
                    retry_got <= ck_got;
                end
            end
        end
        if (ck_v && !ck_retry) begin
            if (n_checked != 32'hffffffff)
                n_checked <= n_checked + 32'd1;
            for (ql = 0; ql < 4; ql = ql + 1)
                if (lane_bad[ql] && lane_err[32*ql +: 32] != 32'hffffffff)
                    lane_err[32*ql +: 32] <= lane_err[32*ql +: 32] + 32'd1;
            if (|lane_bad && !err_seen) begin
                err_seen <= 1'b1;
                err_addr <= ck_a;
                err_diff <= diff;
            end
        end
        if (clr) begin
            passes <= 16'd0;
            n_written <= 32'd0;
            n_checked <= 32'd0;
            lane_err <= 128'd0;
            err_seen <= 1'b0;
            pin_err <= 512'd0;
            beat_err <= 512'd0;
            elog <= 512'd0;
            n_log <= 4'd0;
            log_v <= 1'b0;
            retry_pend <= 1'b0;
        end

        // the passes
        case (state)
            S_IDLE: begin
                pmode <= tm_mode;
                cmd_we <= 1'b1;
                cmd_addr <= {AW{1'b0}};
                cmd_valid <= 1'b1;
                state <= S_WR;
            end
            S_WR: if (take) begin
                if (!pmode[1] && !w2nd) begin
                    w2nd <= 1'b1;               // the word's masked write next
                    if (tm_gap != 8'd0) begin
                        cmd_valid <= 1'b0;      // and idle PCLK before it
                        gap_cnt <= tm_gap;
                        state <= S_WG;
                    end
                end else begin
                    w2nd <= 1'b0;
                    if (cmd_addr == LAST) begin
                        cmd_valid <= 1'b0;
                        state <= S_WRW;
                    end else
                        cmd_addr <= cmd_addr + 1'b1;
                end
            end
            // the idle PCLK between a word's two writes
            S_WG: begin
                if (gap_cnt == 8'd0) begin
                    cmd_valid <= 1'b1;
                    state <= S_WR;
                end else
                    gap_cnt <= gap_cnt - 8'd1;
            end
            S_WRW: begin
                cmd_we <= 1'b0;
                cmd_addr <= {AW{1'b0}};
                cmd_valid <= 1'b1;
                state <= S_RD;
            end
            S_RD: if (take) begin
                if (cmd_retry) begin            // back to where the re-read cut in
                    cmd_retry <= 1'b0;
                    cmd_addr <= resume;
                    cmd_valid <= rroom;
                end else if (cmd_addr == LAST) begin
                    cmd_valid <= 1'b0;
                    retry_pend <= 1'b0;
                    state <= S_RDW;
                end else if (retry_pend) begin  // the re-read next
                    resume <= cmd_addr + 1'b1;
                    cmd_addr <= retry_addr;
                    cmd_retry <= 1'b1;
                    retry_pend <= 1'b0;
                    retry_fly <= 1'b1;
                    elog[64*retry_idx + 37] <= 1'b1;
                    cmd_valid <= rroom;
                end else begin
                    cmd_addr <= cmd_addr + 1'b1;
                    cmd_valid <= rroom;
                end
            end else if (!cmd_valid && rroom)
                cmd_valid <= 1'b1;
            S_RDW: if (rq_n == 7'd0 && !ck_v) begin
                rcnt <= 32'd0;
                cmd_addr <= lfsr[AW-1:0] & LAST;
                cmd_valid <= 1'b1;
                state <= S_RR;
            end
            S_RR: if (take) begin
                if (cmd_retry) begin
                    cmd_retry <= 1'b0;
                    cmd_addr <= resume;
                    cmd_valid <= rroom;
                end else begin
                    lfsr <= xs_next(lfsr);      // the next random address
                    if (rcnt == RLAST) begin
                        cmd_valid <= 1'b0;
                        retry_pend <= 1'b0;
                        state <= S_RRW;
                    end else begin
                        rcnt <= rcnt + 32'd1;
                        if (retry_pend) begin
                            resume <= xs_next(lfsr) & LAST;
                            cmd_addr <= retry_addr;
                            cmd_retry <= 1'b1;
                            retry_pend <= 1'b0;
                            retry_fly <= 1'b1;
                            elog[64*retry_idx + 37] <= 1'b1;
                        end else
                            cmd_addr <= xs_next(lfsr) & LAST;
                        cmd_valid <= rroom;
                    end
                end
            end else if (!cmd_valid && rroom)
                cmd_valid <= 1'b1;
            S_RRW: if (rq_n == 7'd0 && !ck_v) begin
                pmode <= tm_mode;               // a mode change lands between passes
                if (passes != 16'hffff)
                    passes <= passes + 16'd1;
                seed <= seed + 32'h9e3779b9;
                seed_b <= seed_b + 32'h7f4a7c15;
                cmd_we <= 1'b1;
                cmd_addr <= {AW{1'b0}};
                cmd_valid <= 1'b1;
                state <= S_WR;
            end
            default: state <= S_IDLE;
        endcase
        if (rst) begin
            state <= S_IDLE;
            cmd_valid <= 1'b0;
            w2nd <= 1'b0;
            rq_w <= 6'd0; rq_r <= 6'd0; rq_n <= 7'd0;
            ck_v <= 1'b0;
            cmd_retry <= 1'b0;
            retry_pend <= 1'b0;
            retry_fly <= 1'b0;
        end
    end
endmodule

`default_nettype wire
