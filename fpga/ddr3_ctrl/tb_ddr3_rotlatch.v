`timescale 1ns/1ps
`default_nettype none

// Unit simulation of the rotation latch: a partial training must never be
// frozen, a complete one must latch all four lanes and release pattern mode,
// and a rearm must put it back to the untrained state.
module tb_ddr3_rotlatch;
    reg pclk = 1'b0, rearm = 1'b0;
    reg [3:0] trained = 0;
    reg [11:0] rot_in = 0;
    wire [11:0] rot;
    wire done, pattern_mode;

    always #5 pclk = ~pclk;

    ddr3_rotlatch dut (
        .pclk(pclk), .rearm(rearm), .trained(trained), .rot_in(rot_in),
        .rot(rot), .done(done), .pattern_mode(pattern_mode));

    integer errors = 0;
    task fail(input [8*72-1:0] msg);
        begin
            if (errors < 20) $display("FAIL  t=%0t %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    initial begin
        repeat (2) @(posedge pclk);
        if (done !== 1'b0 || pattern_mode !== 1'b1)
            fail("the latch started trained");

        // partial training: two lanes only
        rot_in = 12'o1234;
        trained = 4'b0011;
        repeat (4) @(posedge pclk);
        if (done !== 1'b0) fail("a partial training was frozen");
        if (rot !== 12'd0) fail("rot moved before all four lanes trained");
        if (pattern_mode !== 1'b1) fail("pattern mode was released early");

        // complete: it latches and releases
        trained = 4'b1111;
        rot_in = 12'o4567;
        @(posedge pclk); #1;
        if (done !== 1'b1) fail("a complete training was not frozen");
        if (rot !== 12'o4567) fail("the wrong rotation vector was frozen");
        if (pattern_mode !== 1'b0) fail("pattern mode stayed on after training");

        // the vector must hold even as rd_align keeps reporting new values
        rot_in = 12'o0011;
        repeat (4) @(posedge pclk);
        if (rot !== 12'o4567) fail("the frozen vector followed a later report");

        // rearm returns to the untrained state; a real retrain clears the
        // training mask at the same time, otherwise the latch is right to
        // freeze again immediately
        rearm = 1'b1;
        trained = 4'b0000;
        @(posedge pclk); #1;
        rearm = 1'b0;
        @(posedge pclk); #1;
        if (done !== 1'b0) fail("rearm did not clear done");
        if (pattern_mode !== 1'b1) fail("rearm did not restore pattern mode");

        // and a fresh complete training freezes the new vector
        trained = 4'b1111;
        rot_in = 12'o7654;
        @(posedge pclk); #1;
        if (!done || rot !== 12'o7654)
            fail("a retrain did not freeze the new rotation vector");

        if (errors == 0)
            $display("PASS  partial training refused, complete training frozen, rearm clears");
        else
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end
endmodule

`default_nettype wire
