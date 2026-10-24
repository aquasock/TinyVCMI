`timescale 1ns / 1ps
`default_nettype none

// Unit simulation of fpga/ddr3_write/rd_align.v: the trained read-valid
// boundary on its own, with no PHY and no device model.
//
// The test drives each lane's eight pins at a chosen whole-word rotation
// with the write side's even/odd inversion, and asserts that:
//
//   * no lane reports trained, and no burst is presented, until the lock
//     counter has run LOCK_CYCLES consistent stream cycles;
//   * each lane locks the rotation the pins actually hold, and every
//     presented burst is the written pattern in burst order -- byte 0x55
//     where P's bit is set, 0xAA where it is clear -- on all eight beats and
//     all four lanes;
//   * a lane whose rotation moves after the lock sets drift and err, and
//     clears both only when re-armed and retrained;
//   * a pattern whose rotations are not distinct never trains;
//   * a single mis-framed pin blocks that lane's lock and withholds valid,
//     rather than being averaged away;
//   * reset holds everything cleared.
module tb_align;
    reg pclk = 1'b0;
    always #5 pclk = ~pclk;

    reg         rst = 1'b1;
    reg         stream = 1'b0;
    reg         arm = 1'b0;
    reg  [7:0]  pat = 8'h1d;
    reg  [255:0] dq_q = 256'd0;
    reg  [3:0]  rvalid = 4'b0000;

    wire [3:0]  trained, err, drift;
    wire [11:0] rot;
    wire [255:0] data;
    wire        valid, ok, pat_ok;
    wire [11:0] phase;
    wire [3:0]  phase_ok;
    wire [15:0] relocks;

    rd_align dut (
        .pclk(pclk), .rst(rst), .stream(stream), .dq_q(dq_q),
        .rvalid(rvalid), .pat(pat), .arm(arm), .trained(trained),
        .rot(rot), .data(data), .valid(valid), .ok(ok), .err(err),
        .drift(drift), .pat_ok(pat_ok), .phase(phase), .phase_ok(phase_ok),
        .relocks(relocks));

    integer errors = 0;
    task fail(input [8*96-1:0] msg);
        begin
            if (errors < 20)
                $display("FAIL  t=%0t %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    integer l0 = 0, l1 = 3, l2 = 5, l3 = 7;
    integer lp, ll;
    integer bad_lane = -1, bad_pin = 0;
    integer expect_bad = 0;
    reg [7:0] w, wd, bad_word = 8'h00;

    function [7:0] rot8(input [7:0] p, input integer r);
        rot8 = (p << r) | (p >> (8 - r));
    endfunction

    // all eight pins of a lane at one rotation, odd pins inverted
    task lane_word(input integer lane, input integer r);
        integer p;
        begin
            for (p = 0; p < 8; p = p + 1) begin
                wd = rot8(pat, r);
                if (p % 2) wd = ~wd;
                if (lane == bad_lane && p == bad_pin) wd = bad_word;
                dq_q[64*lane + 8*p +: 8] = wd;
            end
        end
    endtask

    task drive_all;
        begin
            lane_word(0, l0);
            lane_word(1, l1);
            lane_word(2, l2);
            lane_word(3, l3);
        end
    endtask

    task set_pin(input integer lane, input integer pin, input [7:0] word);
        begin
            dq_q[64*lane + 8*pin +: 8] = word;
        end
    endtask

    // the core gates its reads: the stream is live for part of each group
    task gated_hold(input integer groups);
        integer g, i;
        begin
            for (g = 0; g < groups; g = g + 1) begin
                for (i = 0; i < 13; i = i + 1) begin
                    @(negedge pclk);
                    stream = 1'b1;
                    drive_all;
                end
                for (i = 0; i < 27; i = i + 1) begin
                    @(negedge pclk);
                    stream = 1'b0;
                    drive_all;
                end
            end
            @(posedge pclk);
            #1;
            stream = 1'b1;
        end
    endtask

    task hold(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge pclk);
                drive_all;
            end
            @(posedge pclk);
            #1;
        end
    endtask

    task expect_trained(input [3:0] mask);
        begin
            if (trained !== mask)
                fail("trained mask is not the expected one");
        end
    endtask

    task expect_rot(input integer r0, input integer r1, input integer r2,
                    input integer r3);
        begin
            if (rot[0 +: 3] !== r0[2:0] || rot[3 +: 3] !== r1[2:0] ||
                rot[6 +: 3] !== r2[2:0] || rot[9 +: 3] !== r3[2:0]) begin
                fail("locked rotations are not the measured ones");
                $display("      rot: L0 %0d L1 %0d L2 %0d L3 %0d, expected %0d %0d %0d %0d",
                         rot[0 +: 3], rot[3 +: 3], rot[6 +: 3], rot[9 +: 3],
                         r0, r1, r2, r3);
            end
        end
    endtask

    // every presented burst must be the written pattern in burst order
    integer bursts = 0, bad_bytes = 0;
    reg [7:0] exp;
    integer mb, ml;
    always @(posedge pclk) if (valid) begin
        bursts = bursts + 1;
        if (!ok && !expect_bad)
            fail("ok low on a presented burst");
        for (mb = 0; mb < 8; mb = mb + 1) begin
            exp = pat[mb] ? 8'h55 : 8'hAA;
            for (ml = 0; ml < 4; ml = ml + 1)
                if (data[32*mb + 8*ml +: 8] !== exp) begin
                    bad_bytes = bad_bytes + 1;
                    if (!expect_bad && bad_bytes <= 8)
                        $display("FAIL  t=%0t beat %0d lane %0d is %02x, expected %02x",
                                 $time, mb, ml, data[32*mb + 8*ml +: 8], exp);
                end
        end
    end

    integer bad_at_lock = 0;

    initial begin
        // ---- reset holds everything cleared -------------------------
        drive_all;
        stream = 1'b1;
        rvalid = 4'b1111;
        hold(5);
        rst = 1'b0;
        hold(4);
        expect_trained(4'b0000);
        if (valid !== 1'b0) fail("valid high before any lock");

        // ---- training takes exactly LOCK_CYCLES consistent cycles ---
        hold(27);                       // 31 stream cycles so far
        expect_trained(4'b0000);
        hold(2);                        // 33
        expect_trained(4'b1111);
        if (pat_ok !== 1'b1) fail("pat_ok low for an identifiable pattern");
        expect_rot(l0, l1, l2, l3);
        // the live measurement must agree with the pins, not only the lock
        if (phase_ok !== 4'b1111) fail("phase_ok low on a consistent stream");
        if (phase[2:0] !== l0[2:0] || phase[5:3] !== l1[2:0] ||
            phase[8:6] !== l2[2:0] || phase[11:9] !== l3[2:0]) begin
            fail("the live phase does not match the pins");
            $display("      phase %0d %0d %0d %0d, pins %0d %0d %0d %0d",
                     phase[2:0], phase[5:3], phase[8:6], phase[11:9], l0, l1, l2, l3);
        end

        // ---- every presented burst is in pattern order --------------
        bad_at_lock = bad_bytes;
        hold(20);
        if (bursts < 10) fail("too few bursts presented after the lock");
        if (bad_bytes != bad_at_lock) fail("aligned data is not pattern order");
        if (err !== 4'b0000) fail("err set on a correct stream");
        if (drift !== 4'b0000) fail("drift set while the rotation is steady");

        // ---- a lane's rotation moves after the lock -----------------
        expect_bad = 1;         // the decay is the point of this phase
        l2 = 6;
        hold(40);               // DRIFT_CYCLES before a lone lane is judged
        if (drift[2] !== 1'b1) fail("lane 2's rotation moved without drift");
        if (err[2] !== 1'b1) fail("lane 2's data mismatch was not reported");
        if (err[0] !== 1'b0 || err[1] !== 1'b0 || err[3] !== 1'b0)
            fail("a lane that did not move reported an error");
        if (bad_bytes == bad_at_lock) fail("the moved lane did not corrupt the burst");

        // ---- re-arm retrains to the new rotation --------------------
        @(negedge pclk) arm = 1'b1;
        @(negedge pclk) arm = 1'b0;
        hold(1);
        expect_bad = 0;
        expect_trained(4'b0000);
        if (err !== 4'b0000) fail("err survived the re-arm");
        if (drift !== 4'b0000) fail("drift survived the re-arm");
        hold(33);
        expect_trained(4'b1111);
        expect_rot(l0, l1, l2, l3);
        bad_at_lock = bad_bytes;
        hold(20);
        if (bad_bytes != bad_at_lock) fail("data is wrong after retraining");
        if (err !== 4'b0000 || drift !== 4'b0000)
            fail("err or drift set on the retrained stream");

        // ---- a uniform slip is followed, not reported ---------------
        expect_bad = 1;
        l0 = 2; l1 = 5; l2 = 0; l3 = 1;      // every lane +2
        hold(12);                            // RELOCK_CYCLES and settle
        expect_bad = 0;
        if (relocks == 16'd0) fail("a uniform slip was not followed");
        if (drift !== 4'b0000) fail("drift set on a uniform slip");
        if (err !== 4'b0000) fail("err set on a uniform slip");
        expect_trained(4'b1111);
        expect_rot(l0, l1, l2, l3);
        bad_at_lock = bad_bytes;
        hold(20);
        if (bad_bytes != bad_at_lock) fail("data is wrong after following a slip");
        if (valid !== 1'b1) fail("valid low after a followed slip");

        // ---- an unidentifiable pattern never trains -----------------
        pat = 8'h00;
        @(negedge pclk) arm = 1'b1;
        @(negedge pclk) arm = 1'b0;
        hold(64);
        if (pat_ok !== 1'b0) fail("pat_ok high for a pattern with equal rotations");
        expect_trained(4'b0000);
        if (valid !== 1'b0) fail("valid high with an untrainable pattern");

        // ---- one mis-framed pin blocks that lane only ---------------
        pat = 8'h1d;
        l0 = 0; l1 = 3; l2 = 5; l3 = 7;
        @(negedge pclk) arm = 1'b1;
        @(negedge pclk) arm = 1'b0;
        hold(33);
        expect_trained(4'b1111);
        // corrupt pin 3 of lane 1 and let the lock expire
        @(negedge pclk) arm = 1'b1;
        @(negedge pclk) arm = 1'b0;
        bad_lane = 1; bad_pin = 3; bad_word = rot8(8'h1d, 2);
        hold(64);
        if (trained !== 4'b1101) begin
            fail("a mis-framed pin did not block its own lane's lock");
            $display("      trained %04b, expected 1101", trained);
        end
        if (valid !== 1'b0) fail("valid high with a lane unlocked");
        if (pat_ok !== 1'b1) fail("pat_ok dropped for a good pattern");

        // ---- a gated stream still trains, across the gaps -------------
        bad_lane = -1;
        pat = 8'h1d;
        l0 = 0; l1 = 3; l2 = 5; l3 = 7;
        @(negedge pclk) arm = 1'b1;
        @(negedge pclk) arm = 1'b0;
        gated_hold(3);
        expect_trained(4'b1111);
        expect_rot(l0, l1, l2, l3);
        bad_at_lock = bad_bytes;
        gated_hold(2);
        if (bad_bytes != bad_at_lock) fail("gated data is not pattern order");
        if (err !== 4'b0000) fail("err set on a gated but steady stream");

        // a rotation that moves inside a gap must still be caught
        expect_bad = 1;
        l3 = 1;
        gated_hold(6);          // DRIFT_CYCLES of live stream before a lone lane is judged
        if (drift[3] !== 1'b1) fail("a rotation that moved in a gap was not caught");
        if (err[3] !== 1'b1) fail("the gated mismatch was not reported for its lane");
        expect_bad = 0;

        if (errors == 0) begin
            $display("PASS  %0d bursts presented and every byte matched; rotations 0,3,6,7 ",
                     bursts);
            $display("      locked, drift and err raised only for the lane that moved, an");
            $display("      unidentifiable pattern refused, and a mis-framed pin blocked its lane");
        end else begin
            $display("FAIL  %0d error(s)", errors);
        end
        $finish;
    end

    initial begin
        #500000;
        $display("FAIL  timeout: trained %04b valid %b", trained, valid);
        $finish;
    end
endmodule

`default_nettype wire
