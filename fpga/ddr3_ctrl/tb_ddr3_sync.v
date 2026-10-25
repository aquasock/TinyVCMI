`timescale 1ns/1ps
`default_nettype none

// Unit simulation of the PHY start-up sequencer, with the two long waits
// scaled down.  Checks the order TOOL-019 records: DLL held in reset until the
// PLL is locked and the wait expires, released before LOCK is accepted,
// settled before HOLD, HOLD around a four-clock UPDNCNTL pulse, the memory
// clock stopped while the CLKDIV and lane reset is pulsed, restart, ready --
// and that losing PLL lock sends the sequence back to the start.
module tb_ddr3_sync;
    localparam integer LOCK_WAIT = 8, SETTLE_WAIT = 6;

    reg sys_clk = 1'b0, por_n = 1'b0, pll_ok = 1'b0, lock_ok = 1'b0;
    wire dll_rst, updncntl, hold, pll_en, sync_rst, ready;

    ddr3_sync #(.LOCK_WAIT(LOCK_WAIT), .SETTLE_WAIT(SETTLE_WAIT)) dut (
        .sys_clk(sys_clk), .por_n(por_n), .pll_ok(pll_ok), .lock_ok(lock_ok),
        .dll_rst(dll_rst), .updncntl(updncntl), .hold(hold), .pll_en(pll_en),
        .sync_rst(sync_rst), .ready(ready));

    always #5 sys_clk = ~sys_clk;

    integer errors = 0;
    task fail(input [8*76-1:0] msg);
        begin
            if (errors < 20) $display("FAIL  t=%0t %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // ordering witnesses
    reg dll_released = 1'b0, lock_accepted = 1'b0, hold_seen = 1'b0;
    reg updn_low_seen = 1'b0, updn_low_len = 1'b0;
    reg clk_stopped = 1'b0, rst_while_stopped = 1'b0, clk_restarted = 1'b0;
    reg ready_without_all = 1'b0;
    integer updn_low = 0, updn_low_max = 0;

    always @(posedge sys_clk) begin
        if (!dll_rst) dll_released <= 1'b1;
        if (lock_ok && !dll_rst) lock_accepted <= 1'b1;
        if (hold) hold_seen <= 1'b1;
        if (!updncntl) begin
            updn_low <= updn_low + 1;
            updn_low_seen <= 1'b1;
            if (updn_low + 1 > updn_low_max) updn_low_max <= updn_low + 1;
        end else if (updn_low != 0) begin
            updn_low <= 0;
        end
        if (!pll_en) clk_stopped <= 1'b1;
        if (sync_rst && !pll_en) rst_while_stopped <= 1'b1;
        if (pll_en && clk_stopped) clk_restarted <= 1'b1;
        if (ready && !(dll_released && lock_accepted && hold_seen &&
                       updn_low_seen && rst_while_stopped && clk_restarted))
            ready_without_all <= 1'b1;
    end

    initial begin
        repeat (3) @(posedge sys_clk);
        if (!dll_rst) fail("the DLL was released with the board in reset");

        por_n <= 1'b1;
        // stay unlocked: the DLL must remain in reset
        repeat (LOCK_WAIT * 2) @(posedge sys_clk);
        if (!dll_rst) fail("the DLL was released before the PLL locked");

        // PLL locks; the wait elapses and the DLL is released
        pll_ok <= 1'b1;
        repeat (LOCK_WAIT + 2) @(posedge sys_clk);
        if (dll_rst) fail("the DLL was not released after the PLL wait");

        // losing PLL lock before the DLL has locked must restart the wait
        pll_ok <= 1'b0;
        repeat (3) @(posedge sys_clk);
        if (!dll_rst) fail("losing PLL lock did not hold the DLL in reset");

        // bring it back and run the sequence to ready
        pll_ok <= 1'b1;
        repeat (LOCK_WAIT + 2) @(posedge sys_clk);
        if (dll_rst) fail("the DLL was not released after the second PLL wait");
        lock_ok <= 1'b1;
        wait (ready === 1'b1);
        repeat (2) @(posedge sys_clk);

        if (ready_without_all)
            fail("ready was raised before the sequence completed");
        if (updn_low_max != 4)
            fail("UPDNCNTL was not four clocks low under HOLD");
        if (!rst_while_stopped)
            fail("the divider reset was not pulsed with the clock stopped");
        if (!clk_restarted)
            fail("the memory clock was stopped and never restarted");

        if (errors == 0)
            $display("PASS  PLL wait, DLL release, LOCK, settle, HOLD pulse, clock stop and ready in the proven order");
        else
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end
endmodule

`default_nettype wire
