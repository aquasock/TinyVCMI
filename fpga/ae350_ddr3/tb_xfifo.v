// SPDX-License-Identifier: GPL-3.0-only
`timescale 1ns/1ps
`default_nettype none

// xfifo_w and xfifo_r alone, as ahb_ddr3 joins them, the writer near 75 MHz
// and the reader near 100 MHz, or 40 MHz with XFIFO_SLOW_READ, at
// incommensurate periods.  The writer pushes
// in two ways, as ahb_ddr3's bus half does: a decision taken on room and
// pushed a clock later, ahb_ram's posted write, and a push in the clock it
// sees full low, a read.  The reader pops at random with stalls of up to
// 300 clocks, so the queue spends long spells full, and checks every entry
// against what was pushed, in order.  The queue's own checks are left out
// (XFIFO_NOCHECK) by the mutant runs, so an overflow or a reordering has to
// show in the data.
module tb_xfifo;
    localparam integer W = 100;
    localparam integer N = 200000;

    reg wclk = 1'b0, rclk = 1'b0;
    always #6.667 wclk = ~wclk;
`ifdef XFIFO_SLOW_READ
    always #12.493 rclk = ~rclk;            // 40.02 MHz: the reader slower
`else
    always #4.993 rclk = ~rclk;
`endif
    reg wrst = 1'b1, rrst = 1'b1;

    wire          full, room, q_we, empty;
    wire [3:0]    q_waddr;
    wire [W-1:0]  q_wdata, head;
    wire [4:0]    q_wgray, q_rgray;
    reg           dec = 1'b0;               // a push decided on room last clock
    reg           iw = 1'b0;                // a push wanted as soon as full is low
    reg  [W-1:0]  nxt = {W{1'b0}};          // the next entry
    wire          imm = iw && !full && !dec;
    wire          push = dec || imm;
    wire          pop;

    xfifo_w #(.W(W), .LOG2(4), .LEAD(2)) fw (
        .clk(wclk), .rst(wrst), .push(push), .din(nxt), .full(full), .room(room),
        .q_we(q_we), .q_waddr(q_waddr), .q_wdata(q_wdata), .q_wgray(q_wgray),
        .q_rgray(q_rgray));
    xfifo_r #(.W(W), .LOG2(4)) fr (
        .wclk(wclk), .q_we(q_we), .q_waddr(q_waddr), .q_wdata(q_wdata), .q_wgray(q_wgray),
        .clk(rclk), .rst(rrst), .empty(empty), .head(head), .pop(pop), .q_rgray(q_rgray));

    reg [W-1:0] sent [0:N-1];
    integer n_push = 0, n_pop = 0, errs = 0, n_full = 0, n_noroom = 0, n_dec = 0, n_imm = 0;

    function [W-1:0] entry(input integer k);
        begin
            entry = {$random, $random, $random, $random};
            entry[31:0] = k;
        end
    endfunction

    // the writer: in spells of up to 200 clocks, either decisions on room
    // pushed a clock later or pushes in the clock full is seen low, each
    // wanted at random
    reg [31:0] sw = 32'h2468ace1;
    integer    spell = 0;
    reg        posted = 1'b0, want;
    initial nxt = entry(0);
    always @(posedge wclk) begin
        sw = sw ^ (sw << 13); sw = sw ^ (sw >> 17); sw = sw ^ (sw << 5);
        if (wrst) begin
            dec <= 1'b0;
            iw <= 1'b0;
        end else begin
            if (full) n_full = n_full + 1;
            if (!room) n_noroom = n_noroom + 1;
            if (push) begin
                sent[n_push] = nxt;
                if (dec) n_dec = n_dec + 1; else n_imm = n_imm + 1;
                n_push = n_push + 1;
                nxt <= entry(n_push);
            end
            if (spell == 0) begin
                spell = 1 + sw[23:16] % 200;
                posted = sw[24];
            end
            spell = spell - 1;
            want = n_push < N && sw[3:0] < 12 && !(iw && !imm);
            dec <= posted && want && room;
            iw <= (!posted && want) || (iw && !imm);
        end
    end

    // the reader
    reg [31:0] sr = 32'h13579bdf;
    integer    rstall = 0;
    reg        ren = 1'b0;
    assign pop = !empty && ren;
    always @(posedge rclk) begin
        sr = sr ^ (sr << 13); sr = sr ^ (sr >> 17); sr = sr ^ (sr << 5);
        if (!rrst && pop) begin
            if (head !== sent[n_pop]) begin
                errs = errs + 1;
                if (errs < 8)
                    $display("FAIL  t=%0t entry %0d came out as %h, not %h", $time, n_pop,
                             head, sent[n_pop]);
            end
            n_pop = n_pop + 1;
        end
        if (rstall > 0) rstall = rstall - 1;
        else if (sr[15:9] == 7'd0) rstall = sr[24:16] % 300;
        ren <= rstall == 0 && sr[1:0] != 2'b00;
    end

    initial begin
        repeat (3) @(posedge rclk);
        rrst = 1'b0;
        repeat (3) @(posedge wclk);
        wrst = 1'b0;
        wait (n_push == N && !push && !dec);
        repeat (40000) @(posedge rclk);
        $display("      %0d pushed (%0d on room, %0d on full low), %0d popped; full %0d and short of room %0d write clocks",
                 n_push, n_dec, n_imm, n_pop, n_full, n_noroom);
        if (n_pop != n_push) begin
            errs = errs + 1;
            $display("FAIL  %0d pushed but %0d popped", n_push, n_pop);
        end
        if (n_full < 10000 || n_dec < N / 4 || n_imm < N / 4) begin
            errs = errs + 1;
            $display("FAIL  the queue was too seldom full, or one way of pushing too seldom used");
        end
        if (errs == 0)
            $display("PASS  xfifo: every entry out once, in order, across both clocks");
        else
            $display("FAIL  xfifo: %0d errors", errs);
        $finish;
    end
endmodule

`default_nettype wire
