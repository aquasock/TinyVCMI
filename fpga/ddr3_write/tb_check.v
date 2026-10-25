`timescale 1ns / 1ps
`default_nettype none

// Unit simulation of fpga/ddr3_write/rd_check.v: the single-burst checker on
// its own, with no PHY and no device model beyond this one.
//
// The model answers each READ D cycles after it with that location's
// pattern, even pins the pattern and odd pins its inverse, each lane at its
// own rotation, and holds the words until the next answer, as the
// deserializers do.  The test asserts that:
//
//   * hist is full exactly from D + 3 for as many cycles as the READs are
//     apart, and empty for as many cycles before, so the latency reads off it;
//   * at the right offset every READ is class_ok and good, the lock takes
//     each lane's own rotation and nothing is counted as a move;
//   * one offset early nearly nothing is class_ok -- the words are the
//     previous READ's;
//   * a frame that jumps once is a failure, kept with all four lanes, and
//     one counted move;
//   * a frame that moves on every READ passes when `step` predicts it;
//   * one mis-framed pin fails only its own lane;
//   * a second latency and spacing is measured as well.
module tb_check;
    reg pclk = 1'b0;
    always #5 pclk = ~pclk;

    reg          rst = 1'b1, arm = 1'b0;
    reg  [255:0] dq_q = 256'd0;
    reg          issue = 1'b0;
    reg  [3:0]   issue_idx = 4'd0;
    reg  [6:0]   issue_col = 7'd0;
    reg  [4:0]   lat = 5'd10;
    reg  [2:0]   step = 3'd0;
    reg          slip_enable = 1'b0;
    reg  [11:0]  slip = 12'd0;

    wire         locked, fail_seen;
    wire [11:0]  expect_rot, last_rot, fail_rot;
    wire [3:0]   last_cls, fail_lanes;
    wire [31:0]  total, good, class_ok, rot_moves;
    wire [15:0]  hist_n;
    wire [511:0] hist;
    wire [7:0]   fail_pat;
    wire [10:0]  fail_addr;
    wire [255:0] fail_words;
    wire [31:0]  n_both, n_only11, n_only19, n_other;
    wire [127:0] pos_range;
    wire [15:0]  pos_cls;
    reg  [9:0]   refi = 10'd0;

    rd_check dut (
        .pclk(pclk), .rst(rst), .arm(arm), .dq_q(dq_q), .issue(issue),
        .issue_idx(issue_idx), .issue_col(issue_col), .lat(lat), .step(step),
        .slip_enable(slip_enable), .slip(slip), .refi(refi),
        .n_both(n_both), .n_only11(n_only11), .n_only19(n_only19),
        .n_other(n_other), .pos_range(pos_range), .pos_cls(pos_cls),
        .locked(locked), .expect_rot(expect_rot), .last_rot(last_rot),
        .last_cls(last_cls), .total(total), .good(good), .class_ok(class_ok),
        .rot_moves(rot_moves), .hist_n(hist_n), .hist(hist),
        .fail_seen(fail_seen), .fail_lanes(fail_lanes), .fail_pat(fail_pat),
        .fail_addr(fail_addr), .fail_rot(fail_rot), .fail_words(fail_words));

    integer errors = 0;
    task fail(input [8*96-1:0] msg);
        begin
            if (errors < 30)
                $display("FAIL  t=%0t %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // the same table as rd_check.v, kept separately on purpose
    function [7:0] rom(input [3:0] i);
        case (i)
            4'd0:  rom = 8'h0b;  4'd1:  rom = 8'h0d;  4'd2:  rom = 8'h13;  4'd3:  rom = 8'h15;
            4'd4:  rom = 8'h17;  4'd5:  rom = 8'h19;  4'd6:  rom = 8'h1b;  4'd7:  rom = 8'h1d;
            4'd8:  rom = 8'h25;  4'd9:  rom = 8'h27;  4'd10: rom = 8'h2b;  4'd11: rom = 8'h2d;
            4'd12: rom = 8'h35;  4'd13: rom = 8'h37;  4'd14: rom = 8'h3b;  default: rom = 8'h57;
        endcase
    endfunction
    function [7:0] rot_at(input [7:0] p, input integer r);
        rot_at = (p << r) | (p >> (8 - r));
    endfunction

    // ------------------------------------------------------------------
    // The READ source and the device model
    // ------------------------------------------------------------------
    integer spacing = 8, delay = 7;
    integer running = 0;
    integer cyc = 0, nissued = 0;
    integer base_rot [0:3];
    integer frame = 0;              // added to every lane's rotation
    integer move_at = -1;           // jump the frame by move_by at this READ
    integer move_by = 0;
    integer move_each = 0;          // or move it by this much every READ
    integer bad_at = -1;            // mis-frame lane 2 pin 3 at this READ
    reg [7:0] pend_pat [0:1023];
    integer   pend_no [0:1023];
    integer   seed = 32'h1234;
    integer   q, r;

    task drive(input [7:0] pat, input integer n);
        integer ll, pp;
        reg [7:0] w;
        begin
            for (ll = 0; ll < 4; ll = ll + 1) begin
                w = rot_at(pat, (base_rot[ll] + frame) & 7);
                for (pp = 0; pp < 8; pp = pp + 1)
                    dq_q[64*ll + 8*pp +: 8] <= (pp % 2) ? ~w : w;
            end
            if (n == bad_at)
                dq_q[64*2 + 8*3 +: 8] <= rot_at(pat, (base_rot[2] + frame + 1) & 7);
        end
    endtask

    always @(posedge pclk) begin
        cyc <= cyc + 1;
        issue <= 1'b0;
        if (running && cyc % spacing == 0) begin
            r = $random(seed);
            issue <= 1'b1;
            issue_idx <= r[3:0];
            issue_col <= r[10:4];
            pend_pat[cyc % 1024] <= rom(r[3:0]);
            pend_no[cyc % 1024] <= nissued;
            nissued <= nissued + 1;
        end else begin
            pend_no[cyc % 1024] <= -1;
        end
        q = (cyc - delay) % 1024;
        if (cyc >= delay && pend_no[q] >= 0) begin
            if (pend_no[q] == move_at)
                frame = frame + move_by;
            if (move_each != 0 && pend_no[q] > 0)
                frame = frame + move_each;
            drive(pend_pat[q], pend_no[q]);
        end
    end

    task run(input integer n);
        begin
            nissued = 0;
            running = 1;
            wait (nissued == n);
            running = 0;
            repeat (64) @(posedge pclk);
        end
    endtask

    task rearm;
        begin
            @(posedge pclk) arm <= 1'b1;
            @(posedge pclk) arm <= 1'b0;
            frame = 0;
            move_at = -1; move_by = 0; move_each = 0; bad_at = -1;
        end
    endtask

    function [15:0] h(input integer jj);
        h = hist[16*jj +: 16];
    endfunction

    task expect_hist(input integer from, input integer len);
        integer jj;
        begin
            if (hist_n < 16'd100) fail("too few fresh READs counted in hist");
            for (jj = 0; jj < 32; jj = jj + 1) begin
                if (jj >= from && jj < from + len) begin
                    if (h(jj) != hist_n) begin
                        $display("      hist[%0d] = %0d of %0d", jj, h(jj), hist_n);
                        fail("hist not full inside the burst's window");
                    end
                end else if (jj < from && jj >= from - len) begin
                    // the previous READ's words, a different pattern
                    if (h(jj) != 16'd0) begin
                        $display("      hist[%0d] = %0d of %0d", jj, h(jj), hist_n);
                        fail("hist not empty before the burst arrives");
                    end
                end else if (h(jj) > hist_n / 4) begin
                    // older or newer READs: a different pattern but for chance
                    $display("      hist[%0d] = %0d of %0d", jj, h(jj), hist_n);
                    fail("hist too full outside the burst's window");
                end
            end
        end
    endtask

    initial begin
        base_rot[0] = 1; base_rot[1] = 3; base_rot[2] = 6; base_rot[3] = 0;
        repeat (4) @(posedge pclk);
        rst <= 1'b0;
        rearm;

        // 1: latency 7, spacing 8, checked at 10
        run(300);
        expect_hist(10, 8);
        if (!locked) fail("never locked");
        if (total < 290 || good != total || class_ok != total)
            fail("a READ at the right offset was not good");
        if (rot_moves != 0) fail("a move counted on a still frame");
        if (fail_seen) fail("a failure kept on a clean run");
        if (last_rot != {3'd0, 3'd6, 3'd3, 3'd1}) fail("the lanes' rotations not reported");
        $display("      1: hist from 10, %0d/%0d good, rot %h", good, total, last_rot);

        // 2: one offset early, the words are the previous READ's
        rearm;
        lat <= 5'd9;
        run(300);
        if (class_ok > total / 8) fail("class_ok one offset early");
        $display("      2: one early: %0d/%0d class_ok", class_ok, total);
        lat <= 5'd10;

        // 3: the frame jumps once by -2
        rearm;
        move_at = 100; move_by = 6;
        run(300);
        if (!fail_seen || fail_lanes != 4'b1111) fail("a frame jump not kept as a four-lane failure");
        if (good > 101 || good < 95) fail("good counted past the jump");
        if (class_ok != total) fail("a frame jump counted as a wrong burst");
        if (rot_moves != 1) fail("a frame jump not counted once");
        $display("      3: jump: %0d/%0d good, moves %0d, lanes %b", good, total, rot_moves, fail_lanes);

        // 4: the frame moves by -2 on every READ, predicted by step
        rearm;
        move_each = 6; step <= 3'd6;
        run(300);
        if (good != total || fail_seen) fail("a predicted move per READ failed");
        if (rot_moves < total - 2) fail("moves per READ not counted");
        $display("      4: predicted: %0d/%0d good, moves %0d", good, total, rot_moves);
        step <= 3'd0;

        // 5: one mis-framed pin fails only its lane
        rearm;
        bad_at = 150;
        run(300);
        if (!fail_seen || fail_lanes != 4'b0100) fail("a mis-framed pin not kept as lane 2's");
        if (class_ok != total - 1 || good != total - 1) fail("a mis-framed pin counted wrongly");
        $display("      5: pin: %0d/%0d good, lanes %b", good, total, fail_lanes);

        // 6: latency 5, spacing 12
        rearm;
        delay = 5; spacing = 12; lat <= 5'd8;
        run(300);
        expect_hist(8, 12);
        if (good != total || total < 290) fail("latency 5 not good at 8");
        $display("      6: hist from 8, %0d/%0d good", good, total);

        // 7: the two-word reassembler applies one lane-wide beat slip to
        // every DQ word.  Once both halves hold the new response, every
        // slip is a rotation of the same aperiodic pattern.
        rearm;
        slip <= {3'd7, 3'd4, 3'd2, 3'd0};
        slip_enable <= 1'b1;
        lat <= 5'd9;
        run(300);
        if (good != total || total < 290 || fail_seen)
            fail("the configured two-word lane slips did not reassemble every READ");
        $display("      7: two-word slips 0,2,4,7: %0d/%0d good", good, total);
        slip_enable <= 1'b0;

        if (errors == 0)
            $display("PASS  latency, lock, jump, predicted move, pin faults and lane slips as specified");
        else
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL  timeout");
        $finish;
    end
endmodule

`default_nettype wire
