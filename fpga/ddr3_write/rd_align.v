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
    parameter integer DRIFT_CYCLES = 32
) (
    input  wire         pclk,
    input  wire         rst,        // hold in reset while the PHY is not ready
    input  wire         stream,     // the read path is live this cycle
    input  wire [255:0] dq_q,       // lane l, pin p, beat b at 64l + 8p + b
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

    // Measure each lane's rotation: pin 0's word must be exactly one
    // rotation of P, and every other pin must hold that word or its
    // inverse, odd pins inverted as the write serializers drive them.
    reg  [3:0]  meas_ok;
    reg  [11:0] meas_rot;
    reg  [7:0]  w0, wp;
    reg  [3:0]  nmatch;
    reg         pins_ok;
    integer     ml, mr, mp;
    always @(*) begin
        meas_ok = 4'b0000;
        meas_rot = 12'd0;
        for (ml = 0; ml < 4; ml = ml + 1) begin
            w0 = dq_q[64*ml +: 8];
            nmatch = 4'd0;
            for (mr = 0; mr < 8; mr = mr + 1)
                if (w0 == rot_pat[8*mr +: 8]) begin
                    nmatch = nmatch + 4'd1;
                    meas_rot[3*ml +: 3] = mr;
                end
            pins_ok = 1'b1;
            for (mp = 1; mp < 8; mp = mp + 1) begin
                wp = dq_q[64*ml + 8*mp +: 8];
                if (wp != ((mp % 2) ? ~w0 : w0))
                    pins_ok = 1'b0;
            end
            meas_ok[ml] = (nmatch == 4'd1) && pins_ok;
        end
    end

    // The measurement is registered before the lock logic uses it: the
    // pattern's rotations, eight comparisons and a count per lane in one
    // clock, followed by the counter, does not close at 100 MHz otherwise.
    reg [3:0]  meas_ok_r;
    reg [11:0] meas_rot_r;
    always @(posedge pclk) begin
        meas_ok_r <= rst ? 4'b0000 : meas_ok;
        meas_rot_r <= meas_rot;
    end

    reg [11:0] rlock;               // per lane, 3 bits
    reg [31:0] tcnt;                // per lane, 8 bits
    reg [11:0] tcand;               // per lane, 3 bits
    reg [3:0]  trained_r, err_r, drift_r;
    reg [15:0] relocks_r;
    reg [3:0]  rcnt;                // stability of a uniform move
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
    // from one lane's field into the next
    wire [2:0] d0 = meas_rot_r[2:0]  - rlock[2:0];
    wire [2:0] d1 = meas_rot_r[5:3]  - rlock[5:3];
    wire [2:0] d2 = meas_rot_r[8:6]  - rlock[8:6];
    wire [2:0] d3 = meas_rot_r[11:9] - rlock[11:9];
    wire uniform = (&meas_ok_r) && (d0 == d1) && (d0 == d2) && (d0 == d3);
    wire moved = uniform && (d0 != 3'd0);
    wire relock_now = stream && moved && (rcnt >= RELOCK_CYCLES - 1);

    always @(posedge pclk) begin
        if (rst || arm) begin
            trained_r <= 4'b0000;
            drift_r <= 4'b0000;
            tcnt <= 32'd0;
            tcand <= 12'd0;
            rlock <= 12'd0;
            relocks_r <= 16'd0;
            rcnt <= 4'd0;
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
                    if (tcnt[8*tl +: 8] != 8'd0 &&
                        (meas_rot_r[3*tl +: 3] != tcand[3*tl +: 3])) begin
                        tcnt[8*tl +: 8] <= 8'd1;
                        tcand[3*tl +: 3] <= meas_rot_r[3*tl +: 3];
                    end else if (tcnt[8*tl +: 8] >= LOCK_CYCLES - 1) begin
                        tcnt[8*tl +: 8] <= 8'd0;
                        trained_r[tl] <= 1'b1;
                        rlock[3*tl +: 3] <= meas_rot_r[3*tl +: 3];
                    end else begin
                        tcnt[8*tl +: 8] <= tcnt[8*tl +: 8] + 8'd1;
                        tcand[3*tl +: 3] <= meas_rot_r[3*tl +: 3];
                    end
                end else if (stream) begin
                    // live, but not identifying one rotation: a pin is out of
                    // frame or the pattern is unusable, so the count restarts
                    tcnt[8*tl +: 8] <= 8'd0;
                end
            end

            // follow a move all four lanes make together, once it holds
            if (stream && moved) begin
                if (relock_now) begin
                    rlock <= meas_rot_r;
                    relocks_r <= relocks_r + 16'd1;
                    rcnt <= 4'd0;
                end else begin
                    rcnt <= rcnt + 4'd1;
                end
            end else if (stream) begin
                rcnt <= 4'd0;
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
    always @(posedge pclk)
        dq_d <= dq_q;

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

    // The burst is registered once, then checked the cycle it is presented:
    // ok(t) and valid(t) describe data(t), and bad_r(t) is that burst's
    // per-lane mismatch, so `err` is a lane's own failure, not a neighbour's.
    reg [255:0] data_r;
    reg         valid_r, ok_r;
    reg  [1:0]  settle_cnt;         // a burst captured across a relock is not offered
    reg [7:0]   exp;
    reg [3:0]   bad, bad_r;
    integer     bl, cl;
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
            valid_r <= 1'b0;
            ok_r <= 1'b1;
            bad_r <= 4'b0000;
            err_r <= 4'b0000;
        end else begin
            data_r <= aligned;
            // a burst is not offered while the frame is known to be moving:
            // the lanes are measured, they disagree with the locks, and the
            // slip has not yet been followed
            valid_r <= stream && (&trained_r) && (&rvalid) &&
                       (settle_cnt == 2'd0) && !moved;
            bad = 4'b0000;
            for (bl = 0; bl < 8; bl = bl + 1) begin
                exp = pat[bl] ? 8'h55 : 8'hAA;
                for (cl = 0; cl < 4; cl = cl + 1)
                    if (aligned[32*bl + 8*cl +: 8] != exp)
                        bad[cl] = 1'b1;
            end
            bad_r <= bad;
            ok_r <= (bad == 4'b0000);
            if (valid_r && settle_cnt == 2'd0)
                err_r <= err_r | bad_r;
        end
    end

    assign trained = trained_r;
    assign rot = rlock;
    assign data = data_r;
    assign valid = valid_r;
    assign ok = valid_r && ok_r;
    assign err = err_r;
    assign drift = drift_r;
    assign pat_ok = pat_ok_r;
    // the live measurement, for anything that needs the phase as it is now
    // rather than as it was locked
    assign phase = meas_rot_r;
    assign phase_ok = meas_ok_r;
    assign relocks = relocks_r;
endmodule

`default_nettype wire
