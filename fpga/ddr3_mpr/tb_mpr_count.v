`timescale 1ns / 1ps
`default_nettype none

// The pattern counter of mpr_core on its own: a lane whose eight DQ words are
// 0xAA on every PCLK must read 65535 for a full window, and one whose words
// disagree must read 0.  The first board run read 0 on every lane while the
// snapshot showed the pattern, because a 65536-cycle window that matched
// throughout overflowed its 16-bit count.
module tb_count;
    reg sys_clk = 1'b0, pclk = 1'b0;
    always #10 sys_clk = ~sys_clk;
    always #5 pclk = ~pclk;
    // lanes 0 to 2 the pattern; lane 3 with one DQ word wrong
    wire [255:0] dq_q = {8'h55, {7{8'haa}}, {24{8'haa}}};
    wire uart_tx;
    mpr_core core (.sys_clk(sys_clk), .uart_rx(1'b1), .uart_tx(uart_tx), .pll_lock(1'b1),
        .dll_lock(1'b0), .step(8'h00), .pclk(pclk), .rvalid(4'h0), .rburst(4'h0),
        .rflag(4'h0), .wflag(4'h0), .rpoint(12'h000), .wpoint(12'h000), .dq_q(dq_q));
    initial begin
        #1400000;
        if (core.good_last === {16'h0000, {3{16'hffff}}})
            $display("PASS  pattern counter: 65535 on a matching lane, 0 on a mismatched one");
        else
            $display("FAIL  pattern counter reads %h", core.good_last);
        $finish;
    end
endmodule

`default_nettype wire
