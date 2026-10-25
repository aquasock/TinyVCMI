`timescale 1ns/1ps
`default_nettype none

// Unit simulation of rd_check's single-READ burst-position classifier: the
// counters that say which of the two known capture offsets (11 and 19) held
// each isolated READ, and the refresh phase recorded with it.
//
// The responder drives the READ's pattern for exactly one PCLK, at one or
// both of the two offsets, and drives an all-zero word everywhere else.  A
// pattern from the table has weight three to five, so a zero word matches
// none of its rotations and cannot be counted by accident; the histogram
// then attributes the single driving cycle to exactly one offset.
//
//   mode 1: the pattern at offset 11 only  -> n_only11
//   mode 2: the pattern at offset 19 only  -> n_only19
//   mode 3: at both                        -> n_both
//   mode 0: never                          -> n_other
module tb_pos;
    reg         pclk = 1'b0;
    reg         rst = 1'b1;
    reg         arm = 1'b0;
    reg         issue = 1'b0;
    reg  [3:0]  issue_idx = 4'd0;
    reg  [6:0]  issue_col = 7'd0;
    reg  [255:0] dq_q = 256'd0;
    reg  [3:0]   rvalid = 4'b1111;
    reg          rv_enable = 1'b0;
    reg  [9:0]  refi = 10'd0;
    reg  [4:0]  lat = 5'd11;
    reg  [2:0]  step = 3'd0;
    reg         slip_enable = 1'b0;
    reg  [11:0] slip = 12'd0;

    wire        locked, fail_seen;
    wire [11:0] expect_rot, last_rot, fail_rot;
    wire [3:0]  last_cls, fail_lanes;
    wire [31:0] total, good, class_ok, rot_moves;
    wire [15:0] hist_n, pos_cls;
    wire [511:0] hist;
    wire [7:0]  fail_pat;
    wire [10:0] fail_addr;
    wire [255:0] fail_words;
    wire [31:0] n_both, n_only11, n_only19, n_other;
    wire [127:0] pos_range;

    rd_check dut (
        .pclk(pclk), .rst(rst), .arm(arm), .dq_q(dq_q), .issue(issue),
        .rvalid(rvalid), .rv_enable(rv_enable),
        .issue_idx(issue_idx), .issue_col(issue_col), .lat(lat), .step(step),
        .slip_enable(slip_enable), .slip(slip), .refi(refi),
        .n_both(n_both), .n_only11(n_only11), .n_only19(n_only19),
        .n_other(n_other), .pos_range(pos_range), .pos_cls(pos_cls),
        .locked(locked), .expect_rot(expect_rot), .last_rot(last_rot),
        .last_cls(last_cls), .total(total), .good(good), .class_ok(class_ok),
        .rot_moves(rot_moves), .hist_n(hist_n), .hist(hist),
        .fail_seen(fail_seen), .fail_lanes(fail_lanes), .fail_pat(fail_pat),
        .fail_addr(fail_addr), .fail_rot(fail_rot), .fail_words(fail_words));

    always #5 pclk = ~pclk;

    integer errors = 0;
    task fail(input [8*80-1:0] msg);
        begin
            if (errors < 20)
                $display("FAIL  t=%0t %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // the same table as rd_check.v, so each READ is answered with the
    // pattern its own address expects
    function [7:0] rom(input [3:0] i);
        case (i)
            4'd0:  rom = 8'h0b;  4'd1:  rom = 8'h0d;  4'd2:  rom = 8'h13;  4'd3:  rom = 8'h15;
            4'd4:  rom = 8'h17;  4'd5:  rom = 8'h19;  4'd6:  rom = 8'h1b;  4'd7:  rom = 8'h1d;
            4'd8:  rom = 8'h25;  4'd9:  rom = 8'h27;  4'd10: rom = 8'h2b;  4'd11: rom = 8'h2d;
            4'd12: rom = 8'h35;  4'd13: rom = 8'h37;  4'd14: rom = 8'h3b;  default: rom = 8'h57;
        endcase
    endfunction
    function [7:0] rot8(input [7:0] p, input integer r);
        rot8 = (p << r) | (p >> (8 - r));
    endfunction

    // one lane's eight pins for a word, odd pins inverted as the write side
    // drives them
    function [63:0] lane_word(input [7:0] w);
        integer pp;
        begin
            for (pp = 0; pp < 8; pp = pp + 1)
                lane_word[8*pp +: 8] = (pp % 2) ? ~w : w;
        end
    endfunction

    integer mode = 3;                     // which offsets carry the pattern
    // rd_check's offset window is 32 cycles wide, so the bench spaces READs
    // by 32: every READ's window is then entirely its own and each drive
    // lands at exactly one offset.  The age at which a drive lands is
    // calibrated against the histogram below.
    integer off_a = 7, off_b = 15;
    integer spacing = 32;

    // one pending READ: no overlap, no slot ambiguity
    integer age0 = 0;
    reg     v0 = 1'b0;
    reg [7:0] pat0 = 8'd0;

    integer cyc = 0, issued = 0, limit = 400;
    integer drive_age = 0;
    reg [7:0] drive_pat = 8'd0;
    reg [255:0] nxt;
    integer sl;

    always @(posedge pclk) begin
        cyc <= cyc + 1;

        // a READ every `spacing` cycles
        issue <= 1'b0;
        if (cyc != 0 && (cyc % spacing) == 0 && issued < limit) begin
            issue <= 1'b1;
            issue_idx <= issued[3:0];
            issue_col <= issued[6:0];
            issued <= issued + 1;
            v0 <= 1'b1; age0 <= 0; pat0 <= rom(issued[3:0]);
        end

        // the responder: the pattern for one cycle at each armed offset
        nxt = 256'd0;
        if (v0) begin
            if (((mode & 1) != 0) && age0 == off_a)
                nxt = {4{lane_word(rot8(pat0, 2))}};
            if (((mode & 2) != 0) && age0 == off_b)
                nxt = {4{lane_word(rot8(pat0, 5))}};
        end
        dq_q <= nxt;

        // advance and retire
        if (v0) begin
            age0 <= age0 + 1;
            if (age0 >= off_b + 1) v0 <= 1'b0;
        end


        refi <= (refi == 10'd699) ? 10'd0 : refi + 10'd1;
    end

    task run_mode(input integer m, input integer n);
        begin
            @(negedge pclk) arm <= 1'b1;
            @(negedge pclk) arm <= 1'b0;
            mode = m;
            issued = 0;
            limit = n;
            wait (issued == n);
            repeat (40) @(posedge pclk);
        end
    endtask

    task expect_counts(input [31:0] e_both, input [31:0] e_11,
                       input [31:0] e_19, input [31:0] e_other);
        begin
            if (n_both !== e_both || n_only11 !== e_11 ||
                n_only19 !== e_19 || n_other !== e_other) begin
                fail("classifier counts are not as the responder drove them");
                $display("      got both=%0d only11=%0d only19=%0d other=%0d",
                         n_both, n_only11, n_only19, n_other);
                $display("      want both=%0d only11=%0d only19=%0d other=%0d",
                         e_both, e_11, e_19, e_other);
            end
        end
    endtask

    initial begin
        repeat (6) @(posedge pclk);
        rst <= 1'b0;
        repeat (4) @(posedge pclk);

        run_mode(3, 40);
        expect_counts(40, 0, 0, 0);

        run_mode(1, 40);
        expect_counts(0, 40, 0, 0);

        run_mode(2, 40);
        expect_counts(0, 0, 40, 0);

        run_mode(0, 40);
        expect_counts(0, 0, 0, 40);

        // the phase range must bracket what the responder's counter swept
        if (pos_range[15:0] === 16'h03ff)
            fail("no phase was recorded for a class that counted");

        if (errors == 0)
            $display("PASS  burst position classified at 11, 19, both and neither, with its phase");
        else
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end
endmodule

`default_nettype wire
