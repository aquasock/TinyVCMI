`timescale 1ns / 1ps
`default_nettype none

// Unit simulation of ddr3_seq, the hardware read and write training in
// fpga/ddr3_write/wr_core.v, against a model of the core that decodes its
// requests as wr_core does and answers its counters from a hidden per-lane
// truth, the way the board answers the probe:
//
//   * the sixteen rows are prewritten, bank 0..7 and row 0 or 1 with their
//     patterns, each in write mode;
//   * each pin starts at its own framing and is pulsed with CALIB until it
//     agrees with its lane, so every lane ends with one framing, while the
//     stream's word frame moves by two beats on every pin after every sixth
//     framing pulse, as the board's does now and then (TOOL-023);
//   * RLOADN and STEP - 4 RMOVE pulses at RDIR = 1 leave every tap at 4;
//   * a lane is in the vendor's state only at its gate position and from its
//     RCLKSEL up, and its words are whole only when its lane-wide CALIB count
//     is right and its tap is inside its window; it must lock at its second
//     passing RCLKSEL, with the CALIB count of that sweep;
//   * every setting the search changes after its first trial is changed under
//     a HOLD on that lane;
//   * a whole lane still returns 2 of its 360 counted READs wrong, which the
//     99% rule passes, and every lane's data is wrong in a batch begun fewer
//     than RESTART cycles after a HOLD is released, which the warm-up avoids;
//   * the diagnostics report each lane's two passing trials and its nearest
//     miss in the vendor's state;
//   * centring finds each lane's window and leaves its tap at the window's
//     middle, where it passes;
//   * the write alignment is the first of the two that pass, and the lanes'
//     final rotation is reported.
module tb_seq;
    reg clk = 1'b0;
    always #10 clk = ~clk;

    integer errors = 0;
    task fail(input [8*96-1:0] msg);
        begin
            if (errors < 30) $display("FAIL  t=%0t %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // the hidden truth
    integer P [0:3];                    // gate position, 4 x delay + offset
    integer R [0:3];                    // the vendor's state from this RCLKSEL up
    integer C [0:3];                    // whole when the lane's CALIB count mod 8 is this
    integer U [0:3];                    // whole taps above tap 4
    integer F [0:31];                   // each pin's starting framing
    integer drift = 0;                  // the stream's frame move, every pin alike
    integer fpulses = 0;
    localparam integer W = 12;          // write alignments W and W + 1 pass
    localparam [7:0] STEP = 8'd43;
    localparam integer RESTART = 30;    // cycles after a HOLD release before READs are right

    reg start = 1'b0, abort = 1'b0;
    wire busy, done, req, wfound;
    wire [3:0] err, locked, centred;
    wire [5:0] phase, walign;
    wire [7:0] cmd, arg;
    reg ack = 1'b0;
    wire [31:0] lane_set, lane_u, fin_total, fin_class, cycles;
    wire [15:0] lane_cal, tried;
    wire [63:0] wpass;
    wire [11:0] rot;
    wire [255:0] diag;

    // the model's state and its answers
    reg [2:0] mode = 3'd0;
    wire [8:0] st = {1'b1, 1'b1, mode, (mode == 3'd0) ? 4'd8 : 4'd12};
    reg [255:0] snap = 256'd0;
    reg [31:0] tr_reads = 0, rc_total = 0, rc_class = 0;
    reg [127:0] rv_cnt = 0, rb_fall = 0, lane_own = 0;
    reg [31:0] lag_eval = 0;
    integer dly [0:3], gk [0:3], rcs [0:3], tap [0:3], lcal [0:3], pinc [0:31];
    integer hold_mask = 0, trials = 0, waddr = 0, prew = 0, rowlo = 0, bank = 0;
    reg searching = 1'b0;
    integer cyc = 0, rel_cyc = -1000000;
    reg early = 1'b0;
    always @(posedge clk) cyc <= cyc + 1;
    reg [15:0] prew_seen = 16'd0;

    ddr3_seq #(.BATCH(200), .FILLW(50), .STREAMW(50), .PWW(20), .CALW(10), .WARM(40),
               .SETTLE(4)) dut (
        .clk(clk), .start(start), .abort(abort), .busy(busy), .done(done), .err(err),
        .phase(phase), .req(req), .cmd(cmd), .arg(arg), .ack(ack),
        .st(st), .step(STEP), .snap(snap), .tr_reads(tr_reads), .rv_cnt(rv_cnt),
        .rb_fall(rb_fall), .rc_total(rc_total), .rc_class(rc_class),
        .lag_eval(lag_eval), .lane_own(lane_own),
        .last_rot({3'd4, 3'd0, 3'd0, 3'd0}),
        .locked(locked), .lane_set(lane_set), .lane_cal(lane_cal), .lane_u(lane_u),
        .centred(centred), .wpass(wpass), .walign(walign), .wfound(wfound), .rot(rot),
        .fin_total(fin_total), .fin_class(fin_class), .tried(tried), .cycles(cycles),
        .diag(diag));

    function [7:0] rotb(input [7:0] p, input integer r);
        rotb = (p << (r % 8)) | (p >> (8 - (r % 8)));
    endfunction

    integer l, p, n;
    // the snapshot: pin p of lane l at its framing, odd pins inverted; a copy
    // taken every cycle, as wr_core's sys_clk copy is
    always @(posedge clk)
        for (l = 0; l < 4; l = l + 1)
            for (p = 0; p < 8; p = p + 1)
                snap[64*l + 8*p +: 8] = (p % 2) ? ~rotb(8'h0b, F[8*l + p] + pinc[8*l + p] + drift)
                                                 : rotb(8'h0b, F[8*l + p] + pinc[8*l + p] + drift);

    function in_state(input integer ln);
        in_state = (4 * dly[ln] + gk[ln] == P[ln]) && (rcs[ln] >= R[ln]);
    endfunction
    function whole(input integer ln);
        whole = in_state(ln) && (lcal[ln] % 8 == C[ln]) && tap[ln] >= 0 && tap[ln] <= 4 + U[ln];
    endfunction

    // a batch's counters, from the state the lanes are in when random mode ends
    task answer;
        integer ln;
        begin
            tr_reads = 6000;
            rc_total = 5990;
            lag_eval = 360;
            for (ln = 0; ln < 4; ln = ln + 1) begin
                rv_cnt[32*ln +: 32] = in_state(ln) ? 6000 : 18000;
                rb_fall[32*ln +: 32] = 6000;
                lane_own[32*ln +: 32] = !whole(ln) ? 112 : early ? 300 : 358;
            end
            rc_class = (waddr == W || waddr == W + 1) ? 5990 : 600;
        end
    endtask

    // the decoder: every request is acknowledged a cycle later and applied
    always @(posedge clk) begin
        ack <= 1'b0;
        if (req && !ack) begin
            ack <= 1'b1;
            case (cmd)
                8'h0c: begin
                    if (mode == 3'd4 && arg[2:0] == 3'd0) answer;
                    if (mode == 3'd2 && arg[2:0] == 3'd0 && !searching) begin
                        // a row prewritten: bank, row bit and its pattern
                        prew_seen[{rowlo[0], bank[2:0]}] = 1'b1;
                        prew = prew + 1;
                    end
                    if (arg[2:0] == 3'd4) begin
                        trials = trials + 1;
                        early = (cyc - rel_cyc < RESTART);
                    end
                    mode <= arg[2:0];
                end
                8'h0f: bank = arg;
                8'h20: rowlo = arg;
                8'h08: begin
                    pinc[arg[4:0]] = pinc[arg[4:0]] + 1;
                    if (!searching) begin
                        fpulses = fpulses + 1;
                        if (fpulses % 6 == 0) drift = drift + 2;
                    end
                    if (searching && arg[2:0] == 3'd7) lcal[arg[4:3]] = lcal[arg[4:3]] + 1;
                end
                8'h0a: begin
                    for (n = 0; n < 4; n = n + 1) tap[n] = STEP;
                    searching = 1'b1;
                end
                8'h07: for (n = 0; n < 4; n = n + 1)
                    if (arg[4 + n]) begin
                        if (arg[0]) tap[n] = (tap[n] > 0) ? tap[n] - 1 : 0;
                        else tap[n] = tap[n] + 1;
                    end
                8'h35: begin
                    if (hold_mask != 0 && !(arg[7:4] == 4'hf && arg[3:0] != 0)) rel_cyc = cyc;
                    hold_mask = (arg[7:4] == 4'hf) ? arg[3:0] : 0;
                end
                8'h2c, 8'h2d, 8'h2e: begin
                    if (trials > 0 && !hold_mask[arg[7:6]])
                        fail("a lane's setting changed without a HOLD on it");
                    if (cmd == 8'h2c) dly[arg[7:6]] = arg[2:0];
                    if (cmd == 8'h2d) gk[arg[7:6]] = arg[1:0];
                    if (cmd == 8'h2e) rcs[arg[7:6]] = arg[2:0];
                end
                8'h36: waddr = 8 * arg[6:4] + arg[2:0];
                default: ;
            endcase
        end
    end

    integer exp_cal, k, fr0, okf;
    initial begin
        P[0] = 5; P[1] = 6; P[2] = 6; P[3] = 6;
        R[0] = 4; R[1] = 4; R[2] = 5; R[3] = 4;
        C[0] = 3; C[1] = 4; C[2] = 4; C[3] = 4;
        U[0] = 50; U[1] = 46; U[2] = 52; U[3] = 53;
        for (k = 0; k < 32; k = k + 1) begin
            F[k] = (k * 5 + 3) % 8;
            pinc[k] = 0;
        end
        for (k = 0; k < 4; k = k + 1) begin
            dly[k] = 0; gk[k] = 0; rcs[k] = 0; tap[k] = 0; lcal[k] = 0;
        end
        repeat (4) @(posedge clk);
        start <= 1'b1;
        @(posedge clk) start <= 1'b0;
        wait (done);
        repeat (4) @(posedge clk);

        if (err != 0) begin
            $display("      err %0d at phase %0d", err, phase);
            fail("the training reported an error");
        end
        if (prew != 16 || prew_seen != 16'hffff) fail("the sixteen rows were not each prewritten");
        for (l = 0; l < 4; l = l + 1) begin
            fr0 = (F[8*l] + pinc[8*l]) % 8;
            okf = 1;
            for (p = 1; p < 8; p = p + 1)
                if ((F[8*l + p] + pinc[8*l + p]) % 8 != fr0) okf = 0;
            if (!okf) fail("a lane's pins do not share one framing");
        end
        if (locked != 4'hf) fail("not every lane locked");
        for (l = 0; l < 4; l = l + 1) begin
            // the sweep at gate P whose count, after 9 pulses per earlier gate, is C mod 8
            exp_cal = ((C[l] - 9 * P[l]) % 8 + 8) % 8;
            if (lane_set[8*l +: 8] !== {P[l][4:0], R[l][2:0] + 3'd1}) begin
                $display("      lane %0d set %h, want gate %0d rclksel %0d", l, lane_set[8*l +: 8],
                         P[l], R[l] + 1);
                fail("a lane locked at the wrong setting");
            end
            if (lane_cal[4*l +: 4] != exp_cal) begin
                $display("      lane %0d CALIB %0d, want %0d", l, lane_cal[4*l +: 4], exp_cal);
                fail("a lane locked at the wrong CALIB count");
            end
            if (lane_u[8*l +: 8] != U[l]) fail("a lane's window was measured wrong");
            if (diag[64*l +: 16] != 2) begin
                $display("      lane %0d passed %0d trial(s) before locking", l, diag[64*l +: 16]);
                fail("a lane's passing trials were not its two");
            end
            if (diag[64*l + 16 +: 16] == 0 || diag[64*l + 32 +: 16] != 248 ||
                diag[64*l + 48 +: 16] != 360) begin
                $display("      lane %0d diag %h", l, diag[64*l +: 64]);
                fail("a lane's nearest miss in the vendor's state was reported wrong");
            end
            if (tap[l] != (4 + U[l]) / 2) begin
                $display("      lane %0d tap %0d, want %0d", l, tap[l], (4 + U[l]) / 2);
                fail("a lane was not left at the middle of its window");
            end
        end
        if (centred != 4'hf) fail("a lane did not pass where it was centred");
        if (!wfound || walign != W) fail("the write alignment is not the first passing one");
        if (wpass != (64'd3 << W)) fail("the alignments that passed are not exactly W and W + 1");
        if (rot != {3'd4, 3'd0, 3'd0, 3'd0}) fail("the lanes' rotations were not kept");
        if (waddr != W) fail("the core was not left at the chosen write alignment");

        if (errors == 0)
            $display("PASS  prewrite, framing, tap 4, search under HOLD, centring and write alignment: %0d trials, %0d cycles",
                     tried, cycles);
        else
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end

    initial begin
        #200000000;
        $display("FAIL  timeout at phase %0d", phase);
        $finish;
    end
endmodule

`default_nettype wire
