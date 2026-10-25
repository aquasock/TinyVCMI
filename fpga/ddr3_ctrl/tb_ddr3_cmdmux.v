`timescale 1ns/1ps
`default_nettype none

// Unit simulation of the command-bus arbitration.
//
// Three properties matter and each is checked directly: the power-up owns the
// pins until init_done and its levels pass through unchanged, the controller's
// op codes become exactly the pin levels the proven core uses, and a cycle
// without a command is deselected rather than repeating the last one.
module tb_ddr3_cmdmux;
    reg pclk = 1'b0, init_done = 1'b0, train_done = 1'b1;
    reg i_cs_n = 1, i_ras_n = 1, i_cas_n = 1, i_we_n = 1;
    reg [2:0] i_ba = 0;
    reg [15:0] i_addr = 0;
    reg t_valid = 0;
    reg [2:0] t_op = 0, t_ba = 0;
    reg [15:0] t_addr = 0;
    reg a_valid = 0;
    reg [2:0] a_op = 0, a_ba = 0;
    reg [15:0] a_addr = 0;
    wire cs_n, ras_n, cas_n, we_n;
    wire [2:0] ba;
    wire [15:0] addr;

    always #5 pclk = ~pclk;

    ddr3_cmdmux dut (
        .pclk(pclk), .init_done(init_done), .train_done(train_done),
        .t_valid(t_valid), .t_op(t_op), .t_ba(t_ba), .t_addr(t_addr),
        .i_cs_n(i_cs_n), .i_ras_n(i_ras_n), .i_cas_n(i_cas_n), .i_we_n(i_we_n),
        .i_ba(i_ba), .i_addr(i_addr),
        .a_valid(a_valid), .a_op(a_op), .a_ba(a_ba), .a_addr(a_addr),
        .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
        .ba(ba), .addr(addr));

    integer errors = 0;
    task fail(input [8*72-1:0] msg);
        begin
            if (errors < 20) $display("FAIL  t=%0t %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // the adapter's op -> the pins the proven core drives
    task expect_op(input [2:0] op, input [3:0] pins, input [8*24-1:0] what);
        begin
            @(negedge pclk);
            a_op = op; a_valid = 1'b1;
            a_ba = 3'd6; a_addr = 16'h1A5A;
            @(negedge pclk);
            a_valid = 1'b0;
            if ({cs_n, ras_n, cas_n, we_n} !== pins || ba !== 3'd6 || addr !== 16'h1A5A) begin
                fail(what);
                $display("      got %b ba %0d addr %h, wanted %b", {cs_n, ras_n, cas_n, we_n}, ba, addr, pins);
            end
        end
    endtask

    initial begin
        // ---- power-up owns the bus -----------------------------------
        @(negedge pclk);
        i_cs_n = 1'b0; i_ras_n = 1'b1; i_cas_n = 1'b1; i_we_n = 1'b0;
        i_ba = 3'd0; i_addr = 16'h0400;          // ZQCL, as ddr3_init drives it
        @(posedge pclk); #1;
        // {cs, ras, cas, we}: ZQCL is CS low, RAS high, CAS high, WE low
        if ({cs_n, ras_n, cas_n, we_n} !== 4'b0110 || addr !== 16'h0400)
            fail("the power-up's command did not reach the PHY");
        // a controller command must be ignored while the power-up owns it
        a_valid = 1'b1; a_op = 3'd4; a_ba = 3'd1; a_addr = 16'h0011;
        @(posedge pclk); #1;
        if ({cs_n, ras_n, cas_n, we_n} !== 4'b0110)
            fail("the controller drove the bus during power-up");
        a_valid = 1'b0;

        // ---- hand over, then every op maps to its pins ---------------
        init_done <= 1'b1;
        @(posedge pclk);
        expect_op(3'd0, 4'b0000, "MRS did not map to 0000");
        expect_op(3'd1, 4'b0001, "REF did not map to 0001");
        expect_op(3'd2, 4'b0010, "PRE did not map to 0010");
        expect_op(3'd3, 4'b0011, "ACT did not map to 0011");
        expect_op(3'd5, 4'b0100, "WR did not map to 0100");
        expect_op(3'd4, 4'b0101, "RD did not map to 0101");

        // ---- the training tier owns the bus once the power-up is done --
        train_done <= 1'b0;
        @(posedge pclk);
        // a controller command must not reach the pins while training owns it
        a_valid = 1'b1; a_op = 3'd4; a_ba = 3'd1; a_addr = 16'h0011;
        @(posedge pclk); #1;
        if ({cs_n, ras_n, cas_n, we_n} !== 4'b1111)
            fail("the controller drove the bus during training");
        a_valid = 1'b0;
        // a training command does reach them
        @(negedge pclk);
        t_valid = 1'b1; t_op = 3'd3; t_ba = 3'd2; t_addr = 16'h0022;
        @(negedge pclk);
        t_valid = 1'b0;
        if ({cs_n, ras_n, cas_n, we_n} !== 4'b0011 || ba !== 3'd2 || addr !== 16'h0022) begin
            fail("a training ACT did not reach the pins");
            $display("      got %b ba %0d addr %h", {cs_n, ras_n, cas_n, we_n}, ba, addr);
        end
        // and once training is done the controller owns it again
        train_done <= 1'b1;
        repeat (2) @(posedge pclk);      // let the hand-over settle
        expect_op(3'd4, 4'b0101, "RD did not map to 0101 after training");

        // ---- an idle cycle deselects ---------------------------------
        @(negedge pclk);
        a_valid = 1'b0;
        @(posedge pclk); #1;
        if ({cs_n, ras_n, cas_n, we_n} !== 4'b1111)
            fail("an idle cycle did not deselect the bus");

        if (errors == 0)
            $display("PASS  power-up owns the bus, every op maps to its pins, idle deselects");
        else
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end
endmodule

`default_nettype wire
