// SPDX-License-Identifier: GPL-3.0-only
`timescale 1ns/1ps
`default_nettype none

// ahb_ram and ahb_ddr3 under a pipelined AHB master, against a behavioural
// ddr3_ctl request port: random ready with stalls of up to 400 PCLK, so
// the bridge's queue fills and posted writes wait for room, reads returned
// in order after a random delay, writes merged by their mask (1 keeps the
// byte).
//
// The master runs single transfers of every size to random lanes and
// WRAP4 doubleword bursts, reads and writes, as the A25's cache-line fills
// and write-backs come, over 64 lines spread across the whole 1 GiB window,
// and to the block RAM at 0x7fff0000 above them; every read is checked
// against a reference of what was written, byte by byte.  A data transfer
// below the DDR3 window must get ERROR.  The bus clock and PCLK run at
// incommensurate periods near 75 and 100 MHz, so their phases drift through
// every alignment.
module tb_ahb_ddr3;
    localparam integer NL = 64;             // DDR3 lines exercised
    localparam integer NB = 256;            // block RAM bytes exercised
    localparam [31:0] BRAM = 32'h7fff0000;

    reg clk = 1'b0, pclk = 1'b0;
    always #6.667 clk = ~clk;               // 74.99 MHz
    always #4.993 pclk = ~pclk;             // 100.14 MHz
    reg resetn = 1'b0, prst = 1'b1;

    // ---- the AHB master's signals ----------------------------------------
    reg  [31:0] haddr = 32'd0;
    reg  [1:0]  htrans = 2'd0;
    reg         hwrite = 1'b0;
    reg  [2:0]  hsize = 3'd0;
    reg         hprot0 = 1'b1;
    reg  [63:0] hwdata = 64'd0;
    wire [63:0] hrdata;
    wire        hready, hresp, stray;

    wire        sd_req, sd_post, sd_post_ok, sd_ack;
    wire [29:3] sd_addr;
    wire [7:0]  sd_lanes;
    wire [63:0] sd_wdata, sd_rdata;

    ahb_ram ram (
        .clk(clk), .resetn(resetn), .haddr(haddr), .htrans(htrans), .hwrite(hwrite),
        .hsize(hsize), .hprot0(hprot0), .hwdata(hwdata), .hrdata(hrdata), .hready(hready),
        .hresp(hresp), .stray(stray),
        .sd_req(sd_req), .sd_post(sd_post), .sd_post_ok(sd_post_ok), .sd_addr(sd_addr),
        .sd_lanes(sd_lanes), .sd_wdata(sd_wdata), .sd_ack(sd_ack), .sd_rdata(sd_rdata));

    wire         cmd_valid, cmd_we;
    reg          cmd_ready = 1'b0;
    wire [24:0]  cmd_addr;
    wire [255:0] cmd_wdata;
    wire [31:0]  cmd_wmask;
    reg          rdata_valid = 1'b0;
    reg  [255:0] rdata_line = 256'd0;

    ahb_ddr3 #(.AW(25)) dut (
        .clk(clk), .resetn(resetn), .req(sd_req), .post(sd_post), .post_ok(sd_post_ok), .addr(sd_addr),
        .lanes(sd_lanes), .wdata(sd_wdata), .ack(sd_ack), .rdata(sd_rdata),
        .pclk(pclk), .prst(prst), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_we(cmd_we), .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata), .cmd_wmask(cmd_wmask),
        .rdata_valid(rdata_valid), .rdata_line(rdata_line));

    // ---- the lines, and the reference ------------------------------------
    reg [24:0]  tag [0:NL-1];               // each exercised line's DDR3 word address
    reg [255:0] dmem [0:NL-1];              // the model's DDR3
    reg [255:0] ref_l [0:NL-1];             // what the master expects there
    reg [7:0]   ref_b [0:NB-1];             // and in the block RAM
    reg [NB-1:0] b_known = {NB{1'b0}};
    integer i, errs = 0;

    function integer line_of(input [24:0] a);
        integer k;
        begin
            line_of = -1;
            for (k = 0; k < NL; k = k + 1)
                if (tag[k] == a) line_of = k;
        end
    endfunction

    task fail(input [8*80-1:0] what);
        begin
            errs = errs + 1;
            if (errs < 8) $display("FAIL  t=%0t %0s", $time, what);
        end
    endtask

    // ---- the behavioural controller on PCLK ----------------------------
    reg [24:0] rq_a [0:63];
    reg [31:0] rq_t [0:63];
    integer    rq_w = 0, rq_r = 0, n_cmd_wr = 0, n_cmd_rd = 0, n_masked = 0;
    integer    pcyc = 0, k2, ln;
    reg [31:0] seed_p = 32'h1234567;
    integer    stall = 0;
    always @(posedge pclk) begin
        pcyc = pcyc + 1;
        seed_p = seed_p ^ (seed_p << 13); seed_p = seed_p ^ (seed_p >> 17); seed_p = seed_p ^ (seed_p << 5);
        rdata_valid <= 1'b0;
        if (!prst && cmd_valid && cmd_ready) begin
            ln = line_of(cmd_addr);
            if (ln < 0) fail("a request outside the exercised lines");
            else if (cmd_we) begin
                n_cmd_wr = n_cmd_wr + 1;
                for (k2 = 0; k2 < 32; k2 = k2 + 1)
                    if (!cmd_wmask[k2]) dmem[ln][8*k2 +: 8] = cmd_wdata[8*k2 +: 8];
                    else n_masked = n_masked + 1;
            end else begin
                n_cmd_rd = n_cmd_rd + 1;
                rq_a[rq_w % 64] = cmd_addr;
                rq_t[rq_w % 64] = pcyc + 4 + seed_p[4:0];   // 4 to 35 PCLK later
                rq_w = rq_w + 1;
            end
        end
        if (rq_r != rq_w && pcyc >= rq_t[rq_r % 64]) begin
            rdata_valid <= 1'b1;
            rdata_line <= dmem[line_of(rq_a[rq_r % 64])];
            rq_r = rq_r + 1;
        end
        if (stall > 0) stall = stall - 1;
        else if (seed_p[17:12] == 6'd0) stall = seed_p[26:18] % 400;
        cmd_ready <= seed_p[9:8] != 2'b00 && stall == 0;
    end

    // the bus clocks a posted write waited for room, and the writes posted
    // with none
    integer n_wait = 0, n_post = 0;
    always @(posedge clk)
        if (resetn) begin
            if (ram.stage[4]) n_wait = n_wait + 1;
            if (sd_post) n_post = n_post + 1;
        end

    // ---- the AHB master --------------------------------------------------
    // A transfer is queued as {write, size, address, data}; the queue holds
    // one single transfer or one WRAP4 burst, issued back to back.
    reg [31:0] q_a [0:3];
    reg [2:0]  q_s [0:3];
    reg        q_w [0:3];
    reg [63:0] q_d [0:3];
    reg        q_err [0:3];
    integer    q_n, q_i;
    reg        dp_on = 1'b0;                // a transfer in its data phase
    reg [31:0] dp_a;
    reg [2:0]  dp_s;
    reg        dp_w, dp_err;
    reg [63:0] dp_d;
    integer    n_rd = 0, n_wr = 0, n_bursts = 0, n_rburst = 0, n_errs = 0, n_bram = 0;
    integer    n_rd_ddr = 0;                // reads completed from the DDR3 window

    function [7:0] lanes_of(input [2:0] a, input [2:0] s);
        case (s)
            3'd0: lanes_of = 8'h01 << a;
            3'd1: lanes_of = 8'h03 << {a[2:1], 1'b0};
            3'd2: lanes_of = 8'h0f << {a[2], 2'b00};
            default: lanes_of = 8'hff;
        endcase
    endfunction

    // complete the data phase: a write updates the reference, a read is checked
    task complete;
        integer b, ln2, bi;
        reg [7:0] m;
        reg [7:0] want;
        begin
            m = lanes_of(dp_a[2:0], dp_s);
            if (dp_err) begin
                if (!hresp) fail("a transfer outside every window was not refused");
                n_errs = n_errs + 1;
            end else begin
                if (hresp) fail("an ERROR response inside a window");
                for (b = 0; b < 8; b = b + 1)
                    if (m[b]) begin
                        if (dp_a >= BRAM) begin
                            bi = dp_a[7:0] - dp_a[2:0] + b;
                            if (dp_w) begin
                                ref_b[bi] = dp_d[8*b +: 8];
                                b_known[bi] = 1'b1;
                            end else if (b_known[bi] && hrdata[8*b +: 8] !== ref_b[bi])
                                fail("a block RAM byte read back other than written");
                        end else begin
                            ln2 = line_of(dp_a[29:5]);
                            if (dp_w)
                                ref_l[ln2][64*dp_a[4:3] + 8*b +: 8] = dp_d[8*b +: 8];
                            else begin
                                want = ref_l[ln2][64*dp_a[4:3] + 8*b +: 8];
                                if (hrdata[8*b +: 8] !== want)
                                    fail("a DDR3 byte read back other than written");
                            end
                        end
                    end
                if (dp_w) n_wr = n_wr + 1; else n_rd = n_rd + 1;
                if (!dp_w && dp_a < BRAM) n_rd_ddr = n_rd_ddr + 1;
            end
        end
    endtask

    always @(posedge clk) begin
        if (resetn && hready) begin
            if (dp_on) complete;
            dp_on = 1'b0;
            if (htrans[1]) begin            // the address phase just accepted
                dp_on = 1'b1;
                dp_a = haddr; dp_s = hsize; dp_w = hwrite;
                dp_d = q_d[q_i]; dp_err = q_err[q_i];
                hwdata <= dp_w ? q_d[q_i] : {$random, $random};
                q_i = q_i + 1;
            end
            if (q_i < q_n) begin
                haddr <= q_a[q_i];
                hsize <= q_s[q_i];
                hwrite <= q_w[q_i];
                htrans <= (q_i == 0) ? 2'b10 : 2'b11;   // NONSEQ, then SEQ
            end else
                htrans <= 2'b00;
        end
    end

    // pick an exercised line: half the time the last one picked, so a line
    // is read, written and read again while it is in the buffer
    integer last_l = 0;
    function [31:0] pick_ddr(input integer r);
        begin
            if ((r / 7919) % 2 == 0) last_l = r % NL;
            pick_ddr = {2'b01, tag[last_l], 5'd0};
        end
    endfunction

    task run_one;
        integer r, s, l, d0;
        reg [31:0] a;
        begin
            r = $random & 32'h7fffffff;
            q_i = 0;
            case (r % 10)
                0, 1: begin                 // a WRAP4 doubleword burst: a line fill or a write-back
                    l = r / 10;
                    d0 = (r / 1000) % 4;
                    for (s = 0; s < 4; s = s + 1) begin
                        q_a[s] = pick_ddr(l) | (((d0 + s) % 4) << 3);
                        q_s[s] = 3'd3;
                        q_w[s] = (r % 10) == 1;
                        q_d[s] = {$random, $random};
                        q_err[s] = 1'b0;
                    end
                    q_n = 4;
                    n_bursts = n_bursts + 1;
                    if ((r % 10) == 0) n_rburst = n_rburst + 1;
                end
                2: begin                    // the block RAM
                    s = (r / 10) % 4;
                    a = BRAM + (((r / 100) % NB) & ~((1 << s) - 1));
                    q_a[0] = a; q_s[0] = s; q_w[0] = (r / 7) % 2; q_d[0] = {$random, $random};
                    q_err[0] = 1'b0; q_n = 1;
                    n_bram = n_bram + 1;
                end
                3: begin                    // below the DDR3 window: ERROR
                    if ((r / 10) % 8 == 0) begin
                        q_a[0] = 32'h3ffffff8 - ((r / 100) % 64) * 8; q_s[0] = 3'd2;
                        q_w[0] = (r / 7) % 2; q_d[0] = 64'd0; q_err[0] = 1'b1; q_n = 1;
                    end else begin
                        q_a[0] = pick_ddr(r / 100); q_s[0] = 3'd3; q_w[0] = 1'b0;
                        q_d[0] = 64'd0; q_err[0] = 1'b0; q_n = 1;
                    end
                end
                default: begin              // a single transfer of any size
                    s = (r / 10) % 4;
                    a = pick_ddr(r / 100) | ((((r / 7) % 32)) & ~((1 << s) - 1));
                    q_a[0] = a; q_s[0] = s; q_w[0] = (r / 3) % 2; q_d[0] = {$random, $random};
                    q_err[0] = 1'b0; q_n = 1;
                end
            endcase
            // issue, then wait for the queue and its last data phase to finish
            @(negedge clk);
            while (q_i < q_n || dp_on || htrans[1]) @(negedge clk);
            repeat (($random & 3)) @(negedge clk);
        end
    endtask

    integer n;
    initial begin
        for (i = 0; i < NL; i = i + 1) begin
            // spread over all 1 GiB below the block RAM: the low lines, the
            // top lines, and each address bit alone
            tag[i] = (i < 25) ? ((i == 0) ? 25'd0 : 25'd1 << (i - 1)) :
                     (i < 40) ? 25'h1fff7ff - (i - 25) : ($random & 25'h1ff7fff);
            dmem[i] = {$random, $random, $random, $random, $random, $random, $random, $random};
            ref_l[i] = dmem[i];
        end
        for (i = 0; i < NL; i = i + 1)
            for (n = 0; n < i; n = n + 1)
                if (tag[n] == tag[i]) tag[i] = tag[i] ^ 25'h0000400;
        q_n = 0; q_i = 0;
        repeat (5) @(posedge pclk);
        prst = 1'b0;
        repeat (3) @(posedge clk);
        resetn = 1'b1;
        repeat (3) @(posedge clk);
        for (n = 0; n < 40000; n = n + 1) run_one;
        repeat (20) @(posedge clk);
        $display("      %0d reads and %0d writes completed, %0d WRAP4 bursts, %0d refused, %0d to block RAM",
                 n_rd, n_wr, n_bursts, n_errs, n_bram);
        $display("      DDR3: %0d reads and %0d writes requested, %0d bytes masked; %0d of %0d reads from the line buffer",
                 n_cmd_rd, n_cmd_wr, n_masked, n_rd_ddr - n_cmd_rd, n_rd_ddr);
        $display("      %0d writes posted, %0d bus clocks spent waiting for room in the queue",
                 n_post, n_wait);
        // each read burst's last three beats at least come from the buffer
        if (n_rd_ddr - n_cmd_rd < 3 * n_rburst) fail("the line buffer served too few reads");
        if (n_errs < 50 || n_bursts < 5000) fail("too few refusals or bursts");
        if (n_wait < 1000) fail("the queue was too seldom full");
        if (errs == 0)
            $display("PASS  ahb_ddr3: every byte read back as last written, across both clocks");
        else
            $display("FAIL  ahb_ddr3: %0d errors", errs);
        $finish;
    end
endmodule

`default_nettype wire
