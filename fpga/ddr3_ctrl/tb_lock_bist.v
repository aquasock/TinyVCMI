`default_nettype none

`timescale 1ns/1ps
// Lockstep of ddr3_bist against a reference version of itself (tools/sim_ddr3_lockstep.sh):
// a memory model returns what was written, a bit flipped in about one read
// in 4096 so the log and the re-read run, and every output is compared
// every PCLK.  Small N_LOG2 and R_LOG2 make the passes turn over often.
module tb_lock_bist;
    localparam AW = 25, NL = 8, RL = 7;
    reg pclk = 0; always #5 pclk = ~pclk;
    reg rst = 1, clr = 0, cmd_ready = 0, rdata_valid = 0;
    reg [255:0] rdata = 0;
    wire v0, v1, we0, we1; wire [AW-1:0] a0, a1, ea0, ea1; wire [255:0] wd0, wd1, ed0, ed1;
    wire [3:0] st0, st1, nl0, nl1; wire [15:0] p0, p1; wire [31:0] nw0, nw1, nc0, nc1;
    wire [127:0] le0, le1; wire es0, es1; wire [511:0] pe0, pe1, be0, be1, el0, el1;
    ddr3_bist_ref #(.AW(AW), .N_LOG2(NL), .R_LOG2(RL)) o (.pclk(pclk), .rst(rst), .clr(clr),
        .cmd_valid(v0), .cmd_ready(cmd_ready), .cmd_we(we0), .cmd_addr(a0), .cmd_wdata(wd0),
        .rdata_valid(rdata_valid), .rdata_data(rdata), .state(st0), .passes(p0), .n_written(nw0),
        .n_checked(nc0), .lane_err(le0), .err_seen(es0), .err_addr(ea0), .err_diff(ed0),
        .pin_err(pe0), .beat_err(be0), .elog(el0), .n_log(nl0));
    ddr3_bist #(.AW(AW), .N_LOG2(NL), .R_LOG2(RL)) n (.pclk(pclk), .rst(rst), .clr(clr),
        .cmd_valid(v1), .cmd_ready(cmd_ready), .cmd_we(we1), .cmd_addr(a1), .cmd_wdata(wd1),
        .rdata_valid(rdata_valid), .rdata_data(rdata), .state(st1), .passes(p1), .n_written(nw1),
        .n_checked(nc1), .lane_err(le1), .err_seen(es1), .err_addr(ea1), .err_diff(ed1),
        .pin_err(pe1), .beat_err(be1), .elog(el1), .n_log(nl1));
    reg [255:0] mem [0:(1<<NL)-1];
    reg [AW-1:0] q [0:255]; reg [7:0] qw = 0, qr = 0;
    integer cyc = 0, errs = 0, clrs = 0, retries = 0, fl, me;
    // ddr3_bist marks a re-read's issue in bit 37 of its log entry a PCLK
    // after the reference does, so bit 37 is compared against the
    // reference's log of the PCLK before and every other bit at once
    // (within a PCLK of a clear the two may differ for that PCLK, the clear
    // wiping the reference's mark a PCLK early, so bit 37 is not compared then)
    reg [511:0] m37, el0_d = 512'd0;
    reg         clr_d = 1'b0;
    initial for (me = 0; me < 8; me = me + 1) begin m37 = (me == 0) ? 512'd0 : m37; m37[64*me + 37] = 1'b1; end
    reg [31:0] r;
    always @(posedge pclk) begin
        cyc <= cyc + 1;
        if (cyc == 10) rst <= 0;
        el0_d <= el0;
        clr_d <= clr;
        if (cyc > 10 && ({v0,we0,a0,wd0,st0,p0,nw0,nc0,le0,es0,ea0,ed0,pe0,be0,el0 & ~m37,nl0} !==
                         {v1,we1,a1,wd1,st1,p1,nw1,nc1,le1,es1,ea1,ed1,pe1,be1,el1 & ~m37,nl1} ||
                         ((el1 & m37) !== (el0_d & m37) && !clr && !clr_d))) begin
            errs = errs + 1;
            if (errs < 6) $display("MISMATCH cycle %0d: state %0d/%0d addr %h/%h nlog %0d/%0d", cyc, st0, st1, a0, a1, nl0, nl1);
        end
        r = $random;
        cmd_ready <= r[2:0] != 0;
        if (v0 && cmd_ready) begin
            if (we0) mem[a0[NL-1:0]] <= wd0;
            else begin q[qw] <= a0; qw <= qw + 1; end
        end
        rdata_valid <= 0;
        if (qr != qw && r[5:3] != 0) begin
            rdata_valid <= 1;
            rdata <= mem[q[qr][NL-1:0]];
            fl = r[15:8];
            if (r[31:20] == 0) rdata[fl] <= ~mem[q[qr][NL-1:0]][fl];   // a read fault, 1 in 4096
            qr <= qr + 1;
        end
        if (r[31:16] == 16'h0001) begin clr <= 1; clrs = clrs + 1; end else clr <= 0;
        if (o.cmd_retry && v0 && cmd_ready) retries = retries + 1;
        if (cyc == 3000000) begin
            if (errs == 0 && p0 > 50 && retries > 10)
                $display("PASS  bist lockstep: %0d cycles, %0d passes, %0d re-reads, %0d clears, %0d logged at the end, no output differs but bit 37, a PCLK later as intended", cyc, p0, retries, clrs, nl0);
            else $display("FAIL  bist lockstep: %0d mismatching cycles, %0d passes, %0d re-reads", errs, p0, retries);
            $finish;
        end
    end
endmodule

`default_nettype wire
