`default_nettype none

// Controller-facing read-data aligner: the trained read-valid boundary.
//
// The PHY's IDES8_MEM words do not arrive in a fixed order.  Each DQ pin's
// 8-bit word holds eight consecutive beats of the written pattern P, but the
// window starts at an arbitrary beat, so the word is one of P's eight
// rotations, and which rotation it is varies with the lane and with the read
// epoch (TOOL-022).  This module trains that phase per lane, derotates every
// captured word so beat 0 is P's bit 0, transposes each lane's eight pins
// into eight beat bytes, and presents one 256-bit burst -- eight beats of
// 32 bits, lane 3 in the top byte -- with a per-cycle valid.
//
// The write side drives P on even DQ and ~P on odd DQ, so a correct burst
// byte is 0x55 where P's bit is set and 0xAA where it is clear; `ok` marks a
// burst whose 32 bytes all match.  A pattern is identifiable only if its
// eight rotations are distinct: P = 0x00 or 0xff cannot be trained and
// `pat_ok` stays low, so training refuses rather than locking to the first
// of several equal matches.
//
// Training counts only cycles the caller marks `stream`, which the core
// grants after the read path has run sixteen unbroken cycles.  A lane locks
// after LOCK_CYCLES such cycles agree on exactly one rotation and all eight
// pins hold it: even pins the word itself, odd pins its inverse, as the write
// serializers drive them.  A mis-framed pin therefore blocks the lock instead
// of being averaged away.  The count is of agreeing observations, not of
// consecutive clocks: the core gates its reads into groups, so the stream is
// live for only part of each group, and a gap neither confirms nor
// contradicts a rotation.  A lock is held until the next `arm`; it is never
// moved silently, and a lane whose live rotation disagrees with its lock sets
// `drift` so the host sees the change rather than only a data error.
//
// This is the data path only.  Which burst answers which READ command, and
// the read latency, remain the controller's to establish.
module rd_align #(
    parameter integer LOCK_CYCLES = 32,
    parameter integer RELOCK_CYCLES = 8,
    parameter integer DRIFT_CYCLES = 32,
    // PRE = 1: the measurement's compares are made a PCLK early, from dq_pre,
    // the word dq_q will hold at the next PCLK, against the rotations
    // rot_pat_r will hold then, and registered, so they describe dq_q in the
    // same cycle the compares made from dq_q itself would.  Made from dq_q,
    // compares and reductions in one PCLK put meas_ok_r 1.9 ns over 100 MHz
    // fully timed (TOOL-065).  The unit bench drives dq_q alone and keeps 0.
    parameter integer PRE = 0
) (
    input  wire         pclk,
    input  wire         rst,        // hold in reset while the PHY is not ready
    input  wire         stream,     // the read path is live this cycle
    input  wire [255:0] dq_q,       // lane l, pin p, beat b at 64l + 8p + b
    input  wire [255:0] dq_pre,     // with PRE: the word dq_q holds a PCLK later
    input  wire [3:0]   rvalid,     // each lane's FIFO holds a whole word
    input  wire [7:0]   pat,        // the pattern the write side drove
    input  wire         arm,        // discard the locks and retrain
    output wire [3:0]   trained,    // per lane: a rotation is locked
    output wire [11:0]  rot,        // per lane: the locked rotation, 3 bits
    output wire [255:0] data,       // aligned burst: beat b, lane l at 32b + 8l
    output wire         valid,      // data holds a burst from a live stream
    output wire         ok,         // every byte of that burst matched
    output wire [3:0]   err,        // sticky: a lane's byte did not match
    output wire [3:0]   drift,      // sticky: the live rotation moved
    output wire         pat_ok,     // the pattern's rotations are distinct
    output wire [11:0]  phase,      // the live measured rotation, 3 bits a lane
    output wire [3:0]   phase_ok,   // that lane's word identifies one rotation
    output wire [15:0]  relocks     // uniform slips followed since the last arm
);
    // The eight rotations, in the convention the write side and
    // tools/ddr3_write_probe.py use: rot_pat[r] = (P << r) | (P >> (8-r)),
    // whose bit j is P[(j - r) mod 8].  Derotating is therefore
    // (w >> r) | (w << (8 - r)), which puts P's bit j back at bit j.
    function [7:0] rot_at(input [7:0] p, input integer r);
        rot_at = (p << r) | (p >> (8 - r));
    endfunction

    wire [63:0] rot_pat = {rot_at(pat, 7), rot_at(pat, 6), rot_at(pat, 5),
                           rot_at(pat, 4), rot_at(pat, 3), rot_at(pat, 2),
                           rot_at(pat, 1), rot_at(pat, 0)};

    // A rotation is identifiable only when the pattern has eight distinct
    // ones; otherwise the measured index is one of several.
    function integer distinct(input [7:0] p);
        integer ia, ib;
        begin
            distinct = 1;
            for (ia = 0; ia < 8; ia = ia + 1)
                for (ib = 0; ib < 8; ib = ib + 1)
                    if (ia != ib && rot_at(p, ia) == rot_at(p, ib))
                        distinct = 0;
        end
    endfunction

    // Registered like the measurement: the pattern changes only on command,
    // and its twenty-eight comparisons must not sit in the lock decision's
    // clock.
    reg pat_ok_r;
    always @(posedge pclk)
        pat_ok_r <= distinct(pat) != 0;

    // The rotations, registered beside the comparisons that use them; the
    // pattern only changes on command.
    // wr_core registers the same eight rotations for its own check; merged,
    // the one register would feed both from wherever it lands, which put
    // the Gowin control 1.1 ns short of PCLK, so this copy stays
    (* syn_preserve = 1, keep = 1 *) reg [63:0] rot_pat_r;
    always @(posedge pclk)
        rot_pat_r <= rot_pat;

    // Measure each lane's rotation: pin 0's word must be exactly one
    // rotation of P, and every other pin must hold that word or its
    // inverse, odd pins inverted as the write serializers drive them.
    // "Exactly one" is "any, of a pattern whose rotations are distinct":
    // a periodic pattern's rotations match in twos or more, so pat_ok_r
    // stands in for counting the matches.
    reg  [3:0]  meas_any;           // w0 is one of the pattern's rotations
    reg  [3:0]  meas_pins;          // its other pins hold w0 or its inverse
    reg  [11:0] meas_rot;
    reg  [7:0]  match;              // per rotation: w0 equals it
    reg  [6:0]  pin_bad;            // per pin: it does not hold w0 or ~w0
    reg  [7:0]  w0;
    integer     ml, mr, mp;
    // the early compares, with PRE
    reg  [31:0] pre_match = 32'd0;      // lane l, rotation r at 8l + r
    reg  [27:0] pre_bad = 28'd0;        // lane l, pin p at 7l + p - 1
    reg  [7:0]  pw0;
    integer     pl, pr, pp;
    always @(posedge pclk)
        if (PRE != 0)
            for (pl = 0; pl < 4; pl = pl + 1) begin
                pw0 = dq_pre[64*pl +: 8];
                for (pr = 0; pr < 8; pr = pr + 1)
                    pre_match[8*pl + pr] <= (pw0 == rot_pat[8*pr +: 8]);
                for (pp = 1; pp < 8; pp = pp + 1)
                    pre_bad[7*pl + pp - 1] <= (dq_pre[64*pl + 8*pp +: 8] !=
                                               ((pp % 2) ? ~pw0 : pw0));
            end
    always @(*) begin
        meas_any = 4'b0000;
        meas_pins = 4'b0000;
        meas_rot = 12'd0;
        for (ml = 0; ml < 4; ml = ml + 1) begin
            w0 = dq_q[64*ml +: 8];
            // The eight compares are written as a vector and reduced
            // afterwards.  Written as an if-chain over the index, the tool
            // serializes them through the priority mux that picks the
            // rotation, which put nine levels of LUT on pclk; as a vector
            // they sit side by side and only the encode is a chain.
            for (mr = 0; mr < 8; mr = mr + 1)
                match[mr] = (PRE != 0) ? pre_match[8*ml + mr] : (w0 == rot_pat_r[8*mr +: 8]);
            meas_any[ml] = |match;
            // encoded by OR, not by priority: the measurement is used only
            // when the pattern's rotations are distinct (pat_ok_r), and then
            // at most one compare matches.  The priority chain put meas_ok_r
            // and d0 to d3 0.7 ns over 100 MHz fully timed (TOOL-065).
            meas_rot[3*ml]     = match[1] | match[3] | match[5] | match[7];
            meas_rot[3*ml + 1] = match[2] | match[3] | match[6] | match[7];
            meas_rot[3*ml + 2] = match[4] | match[5] | match[6] | match[7];
            for (mp = 1; mp < 8; mp = mp + 1)
                pin_bad[mp-1] = (PRE != 0) ? pre_bad[7*ml + mp - 1] :
                                (dq_q[64*ml + 8*mp +: 8] != ((mp % 2) ? ~w0 : w0));
            meas_pins[ml] = ~|pin_bad;
        end
    end

    // The measurement is registered before the lock logic uses it: the
    // pattern's rotations, eight comparisons and a count per lane in one
    // clock, followed by the counter, does not close at 100 MHz otherwise.
    // meas_ok_r and meas_rot_r describe the same measurement cycle, which
    // the lock logic relies on, and that latency is one cycle, as the
    // hardware-proven image has it.
    //
    // meas_ok_r carries no reset.  Its only consumers are inside the lock
    // block's `rst || arm` branch, which clears every register it feeds, so a
    // stale value during reset is unobservable there, and meas_rot_r, which
    // is registered beside it and read by the same consumers, has never been
    // cleared either.  The register and its reset mux were the last path the
    // Gowin control missed pclk by.
    reg [3:0]  meas_ok_r;
    reg [11:0] meas_rot_r;
    always @(posedge pclk) begin
        meas_ok_r <= meas_any & meas_pins & {4{pat_ok_r}};
        meas_rot_r <= meas_rot;
    end

    reg [11:0] rlock;               // per lane, 3 bits
    reg [31:0] tcnt;                // per lane, 8 bits
    // per lane, tcnt != 0 and tcnt >= LOCK_CYCLES - 1, kept with tcnt
    reg [3:0]  tc_nz, tc_ge;
    reg [11:0] tcand;               // per lane, 3 bits
    reg [3:0]  trained_r, err_r, drift_r;
    reg [15:0] relocks_r;
    reg [3:0]  rcnt;                // stability of a uniform move
    // rcnt >= RELOCK_CYCLES - 1, registered with rcnt: compared in front of
    // the relock it put rlock 0.95 ns over 100 MHz fully timed (TOOL-065)
    reg        rc_ge;
    reg [31:0] dcnt;                // per lane, 8 bits: time off its lock
    integer    tl;

    // The read capture does not hold one frame: it re-frames by a fixed step
    // every time the read stream is interrupted, uniformly in all four lanes
    // and with their offsets preserved (TOOL-023).  So a lock is a starting
    // point, not a permanent fact.  A move that all four lanes make together
    // and that holds RELOCK_CYCLES is followed -- the locks move with it, and
    // the burst stays in pattern order.  A lane that leaves its lock while
    // the others do not, or a move that never settles, is not followed:
    // DRIFT_CYCLES off the lock sets that lane's drift.
    // one 3-bit subtraction per lane: a 12-bit subtract would carry a borrow
    // from one lane's field into the next.  The offsets are registered with
    // the measurement they belong to, so the slip decision starts from
    // flops; for the one cycle after a relock they still hold the old lock's
    // offsets, which the settle window and the relock count already cover.
    reg [2:0] d0 = 3'd0, d1 = 3'd0, d2 = 3'd0, d3 = 3'd0;
    // uniform and moved are registered with d0..d3 and meas_ok_r from the
    // values those take, so they equal the compares of the registers they
    // once were; compared after them, they led the relock 1.4 ns over 100 MHz
    // fully timed (TOOL-065)
    reg uniform_r = 1'b0, moved_r = 1'b0;
    wire [2:0] dn0 = meas_rot[2:0]  - rlock[2:0];
    wire [2:0] dn1 = meas_rot[5:3]  - rlock[5:3];
    wire [2:0] dn2 = meas_rot[8:6]  - rlock[8:6];
    wire [2:0] dn3 = meas_rot[11:9] - rlock[11:9];
    wire uniform_n = (&(meas_any & meas_pins & {4{pat_ok_r}})) &&
                     (dn0 == dn1) && (dn0 == dn2) && (dn0 == dn3);
    always @(posedge pclk) begin
        d0 <= dn0;
        d1 <= dn1;
        d2 <= dn2;
        d3 <= dn3;
        uniform_r <= uniform_n;
        moved_r <= uniform_n && (dn0 != 3'd0);
    end
    wire uniform = uniform_r;
    wire moved = moved_r;
    wire relock_now = stream && moved && rc_ge;

    always @(posedge pclk) begin
        if (rst || arm) begin
            trained_r <= 4'b0000;
            drift_r <= 4'b0000;
            tcnt <= 32'd0;
            tc_nz <= 4'b0000;
            tc_ge <= {4{LOCK_CYCLES <= 1}};
            tcand <= 12'd0;
            rlock <= 12'd0;
            relocks_r <= 16'd0;
            rcnt <= 4'd0;
            rc_ge <= (RELOCK_CYCLES <= 1);
            dcnt <= 32'd0;
        end else begin
            for (tl = 0; tl < 4; tl = tl + 1) begin
                if (trained_r[tl]) begin
                    // a lane that sits off its lock while the move is not a
                    // uniform one is the fault case, not a slip.  The count is
                    // of live cycles, so a gated gap neither adds to it nor
                    // clears it.
                    if (stream) begin
                        if (!moved && meas_ok_r[tl] &&
                            (meas_rot_r[3*tl +: 3] != rlock[3*tl +: 3])) begin
                            if (dcnt[8*tl +: 8] != 8'hff)
                                dcnt[8*tl +: 8] <= dcnt[8*tl +: 8] + 8'd1;
                            if (dcnt[8*tl +: 8] >= DRIFT_CYCLES - 1)
                                drift_r[tl] <= 1'b1;
                        end else if (!moved) begin
                            dcnt[8*tl +: 8] <= 8'd0;
                        end
                    end
                end else if (stream && meas_ok_r[tl] && pat_ok_r) begin
                    if (tc_nz[tl] &&
                        (meas_rot_r[3*tl +: 3] != tcand[3*tl +: 3])) begin
                        tcnt[8*tl +: 8] <= 8'd1;
                        tc_nz[tl] <= 1'b1;
                        tc_ge[tl] <= (LOCK_CYCLES <= 2);
                        tcand[3*tl +: 3] <= meas_rot_r[3*tl +: 3];
                    end else if (tc_ge[tl]) begin
                        tcnt[8*tl +: 8] <= 8'd0;
                        tc_nz[tl] <= 1'b0;
                        tc_ge[tl] <= (LOCK_CYCLES <= 1);
                        trained_r[tl] <= 1'b1;
                        rlock[3*tl +: 3] <= meas_rot_r[3*tl +: 3];
                    end else begin
                        tcnt[8*tl +: 8] <= tcnt[8*tl +: 8] + 8'd1;
                        tc_nz[tl] <= (tcnt[8*tl +: 8] != 8'hff);
                        tc_ge[tl] <= (tcnt[8*tl +: 8] >= LOCK_CYCLES - 2);
                        tcand[3*tl +: 3] <= meas_rot_r[3*tl +: 3];
                    end
                end else if (stream) begin
                    // live, but not identifying one rotation: a pin is out of
                    // frame or the pattern is unusable, so the count restarts
                    tcnt[8*tl +: 8] <= 8'd0;
                    tc_nz[tl] <= 1'b0;
                    tc_ge[tl] <= (LOCK_CYCLES <= 1);
                end
            end

            // follow a move all four lanes make together, once it holds
            if (stream && moved) begin
                if (relock_now) begin
                    rlock <= meas_rot_r;
                    relocks_r <= relocks_r + 16'd1;
                    rcnt <= 4'd0;
                    rc_ge <= (RELOCK_CYCLES <= 1);
                end else begin
                    rcnt <= rcnt + 4'd1;
                    rc_ge <= (rcnt >= RELOCK_CYCLES - 2);
                end
            end else if (stream) begin
                rcnt <= 4'd0;
                rc_ge <= (RELOCK_CYCLES <= 1);
            end
        end
    end

    // Transpose, then rotate whole bytes.  Transposing is pure wiring: byte
    // b of lane l, bit p, is bit b of pin p's word, so the byte's bit 0 is
    // DQ0 of that lane.  A lane's rotation is then a byte rotation of its
    // 64-bit burst, which costs three 2:1 mux stages per bit instead of an
    // eight-way mux on every bit -- the eight-way version does not close at
    // 100 MHz.
    // The captured word is registered first: the measurement is registered
    // too, and a burst must be judged by the measurement of the same word --
    // otherwise one stale-framed burst escapes on every slip.
    reg [255:0] dq_d;
    // each byte of each lane's transposed word against both patterns,
    // registered with dq_d: data_r's bytes are these bytes rotated, so its
    // flags are these flags rotated the same way (see r55 below)
    reg [31:0]  c55 = 32'd0, cAA = 32'd0;   // lane l, byte b at 8l + b
    reg [7:0]   cb;
    integer     cbl, cbb, cbq;
    always @(posedge pclk) begin
        dq_d <= dq_q;
        for (cbl = 0; cbl < 4; cbl = cbl + 1)
            for (cbb = 0; cbb < 8; cbb = cbb + 1) begin
                for (cbq = 0; cbq < 8; cbq = cbq + 1)
                    cb[cbq] = dq_q[64*cbl + 8*cbq + cbb];
                c55[8*cbl + cbb] <= (cb == 8'h55);
                cAA[8*cbl + cbb] <= (cb == 8'hAA);
            end
    end
    // a lane's byte flags rotated as `aligned` rotates its bytes: right by
    // rlock bytes, in stages of 1, 2 and 4
    function [7:0] frot(input [7:0] f, input [2:0] r);
        reg [7:0] a, b2;
        begin
            a = r[0] ? {f[0], f[7:1]} : f;
            b2 = r[1] ? {a[1:0], a[7:2]} : a;
            frot = r[2] ? {b2[3:0], b2[7:4]} : b2;
        end
    endfunction

    wire [255:0] aligned;
    genvar gl, gb, gq;
    generate
        for (gl = 0; gl < 4; gl = gl + 1) begin : g_lane
            wire [63:0] t, s1, s2, s3;
            for (gb = 0; gb < 8; gb = gb + 1)
                for (gq = 0; gq < 8; gq = gq + 1)
                    assign t[8*gb + gq] = dq_d[64*gl + 8*gq + gb];
            assign s1 = rlock[3*gl]     ? {t[7:0],   t[63:8]}   : t;
            assign s2 = rlock[3*gl + 1] ? {s1[15:0], s1[63:16]} : s1;
            assign s3 = rlock[3*gl + 2] ? {s2[31:0], s2[63:32]} : s2;
            // beat-major: beat b, lane l at byte 4b + l
            for (gb = 0; gb < 8; gb = gb + 1)
                for (gq = 0; gq < 8; gq = gq + 1)
                    assign aligned[32*gb + 8*gl + gq] = s3[8*gb + gq];
        end
    endgenerate

    // The burst is registered once, checked from that register, and
    // presented with its check one cycle later: ok(t) and valid(t) describe
    // data(t), and bad_q(t) is that burst's per-lane mismatch, so `err` is a
    // lane's own failure, not a neighbour's.
    reg [255:0] data_r, data_q;
    reg         valid_r, valid_q, errok_q;
    reg  [1:0]  settle_cnt;         // a burst captured across a relock is not offered
    reg [3:0]   bad, bad_q;
    integer     bl, cl;
    // each byte of data_r against both patterns, registered with data_r
    // and made from c55 and cAA, the same compares of the word before its
    // rotation, rotated, so the check of data_r selects a flag by the pattern
    // bit instead of comparing data_r's bytes: compared there, behind
    // data_r's fan-out, bad_q was 1.5 ns over 100 MHz fully timed, and
    // compared on `aligned`, behind the rotation, 2.9 ns (TOOL-065).  Lane
    // l, beat b at 8l + b; data_r's reset to zero clears both.
    reg [31:0]  r55, rAA;
    always @(posedge pclk) begin
        if (rst || arm)
            settle_cnt <= 2'd0;
        else if (relock_now)
            settle_cnt <= 2'd2;
        else if (settle_cnt != 2'd0)
            settle_cnt <= settle_cnt - 2'd1;

        if (rst || arm) begin
            // drop the presented burst too: a burst captured before the arm
            // must not set err against a lock made after it
            data_r <= 256'd0;
            r55 <= 32'd0;
            rAA <= 32'd0;
            valid_r <= 1'b0;
            data_q <= 256'd0;
            valid_q <= 1'b0;
            bad_q <= 4'b0000;
            errok_q <= 1'b0;
            err_r <= 4'b0000;
        end else begin
            data_r <= aligned;
            for (cl = 0; cl < 4; cl = cl + 1) begin
                r55[8*cl +: 8] <= frot(c55[8*cl +: 8], rlock[3*cl +: 3]);
                rAA[8*cl +: 8] <= frot(cAA[8*cl +: 8], rlock[3*cl +: 3]);
            end
            // a burst is not offered while the frame is known to be moving:
            // the lanes are measured, they disagree with the locks, and the
            // slip has not yet been followed
            valid_r <= stream && (&trained_r) && (&rvalid) &&
                       (settle_cnt == 2'd0) && !moved;
            bad = 4'b0000;
            for (bl = 0; bl < 8; bl = bl + 1)
                for (cl = 0; cl < 4; cl = cl + 1)
                    if (pat[bl] ? !r55[8*cl + bl] : !rAA[8*cl + bl])
                        bad[cl] = 1'b1;
            data_q <= data_r;
            valid_q <= valid_r;
            bad_q <= bad;
            errok_q <= valid_r && settle_cnt == 2'd0;
            if (errok_q)
                err_r <= err_r | bad_q;
        end
    end

    assign trained = trained_r;
    assign rot = rlock;
    assign data = data_q;
    assign valid = valid_q;
    // bad_q == 0 is the registered (bad == 0) the check once kept as a second
    // flop, ok_q, behind the same reduction: 1.3 ns over 100 MHz fully timed
    assign ok = valid_q && (bad_q == 4'b0000);
    assign err = err_r;
    assign drift = drift_r;
    assign pat_ok = pat_ok_r;
    // the live measurement, for anything that needs the phase as it is now
    // rather than as it was locked
    assign phase = meas_rot_r;
    assign phase_ok = meas_ok_r;
    assign relocks = relocks_r;
`ifndef SYNTHESIS
    // the registered compares must equal the compares of their registers
    integer ti;
    always @(posedge pclk)
        if (!rst) begin
            if (uniform_r !== ((&meas_ok_r) && (d0 == d1) && (d0 == d2) && (d0 == d3)) && meas_ok_r !== 4'bxxxx)
                $display("FAIL  rd_align: uniform_r disagrees with its compare");
            for (ti = 0; ti < 4; ti = ti + 1)
                if (tcnt[8*ti +: 8] !== 8'bx &&
                    (tc_nz[ti] !== (tcnt[8*ti +: 8] != 8'd0) ||
                     tc_ge[ti] !== (tcnt[8*ti +: 8] >= LOCK_CYCLES - 1)))
                    $display("FAIL  rd_align: lane %0d's tcnt flags disagree with tcnt", ti);
        end
    integer tb2, tl2;
    always @(posedge pclk)
        for (tl2 = 0; tl2 < 4; tl2 = tl2 + 1)
            for (tb2 = 0; tb2 < 8; tb2 = tb2 + 1)
                if (data_r[32*tb2 + 8*tl2 +: 8] !== 8'bx &&
                    (r55[8*tl2 + tb2] !== (data_r[32*tb2 + 8*tl2 +: 8] == 8'h55) ||
                     rAA[8*tl2 + tb2] !== (data_r[32*tb2 + 8*tl2 +: 8] == 8'hAA)))
                    $display("FAIL  rd_align: the byte flags disagree with data_r");
`endif
endmodule

`default_nettype wire
