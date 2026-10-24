`timescale 1ns / 1ps
`default_nettype none

// Reset-hold simulation of the DDR3 PHY bring-up image against Gowin EDA's
// own primitive models (IDE/simlib/gw5a/prim_sim.v).  It asserts what the
// image promises the DDR3 device, and measures what the models say happens
// while the PHY is in reset:
//
//   * ddr_reset_n and ddr_cke are 0 from the first nanosecond to the last;
//   * once the sequencer reaches RUN, every DQ, DM and strobe pad is high-Z
//     and stays so, and bank 7 holds cs, ras, cas and we high, odt low,
//     address and bank 0, CK low and CK# high;
//   * no DQ, DM or strobe pad is ever driven high;
//   * the status request is answered in the documented frame with PLL lock,
//     DLL LOCK and state RUN.
//
// It reports how long the lane pads drive low while the serializers' tristate
// register is in reset, the window the proven controller also has.
module tb;
    reg sys_clk = 1'b0;
    always #10 sys_clk = ~sys_clk;

    reg uart_rx = 1'b1;
    wire uart_tx;
    wire [31:0] ddr_dq;
    wire [3:0] ddr_dm;
    wire ddr_dqs0_p, ddr_dqs0_n, ddr_dqs1_p, ddr_dqs1_n;
    wire ddr_dqs2_p, ddr_dqs2_n, ddr_dqs3_p, ddr_dqs3_n;
    wire ddr_ck_p, ddr_ck_n, ddr_reset_n;
    wire ddr_bank_2, ddr_bank_1, ddr_bank_0;
    wire ddr_addr_15, ddr_addr_14, ddr_addr_13, ddr_addr_12, ddr_addr_11, ddr_addr_10;
    wire ddr_addr_9, ddr_addr_8, ddr_addr_7, ddr_addr_6, ddr_addr_5, ddr_addr_4;
    wire ddr_addr_3, ddr_addr_2, ddr_addr_1, ddr_addr_0;
    wire ddr_odt, ddr_cke, ddr_we, ddr_cas, ddr_ras, ddr_cs;

    GSR GSR (.GSRI(1'b1));

    top dut (
        .sys_clk(sys_clk), .uart_rx(uart_rx), .uart_tx(uart_tx), .ddr_dq(ddr_dq),
        .ddr_dqs0_p(ddr_dqs0_p), .ddr_dqs0_n(ddr_dqs0_n), .ddr_dqs1_p(ddr_dqs1_p),
        .ddr_dqs1_n(ddr_dqs1_n), .ddr_dqs2_p(ddr_dqs2_p), .ddr_dqs2_n(ddr_dqs2_n),
        .ddr_dqs3_p(ddr_dqs3_p), .ddr_dqs3_n(ddr_dqs3_n),
        .ddr_dm(ddr_dm), .ddr_ck_p(ddr_ck_p), .ddr_ck_n(ddr_ck_n), .ddr_reset_n(ddr_reset_n),
        .ddr_bank_2(ddr_bank_2), .ddr_bank_1(ddr_bank_1), .ddr_bank_0(ddr_bank_0),
        .ddr_addr_15(ddr_addr_15), .ddr_addr_14(ddr_addr_14), .ddr_addr_13(ddr_addr_13),
        .ddr_addr_12(ddr_addr_12), .ddr_addr_11(ddr_addr_11), .ddr_addr_10(ddr_addr_10),
        .ddr_addr_9(ddr_addr_9), .ddr_addr_8(ddr_addr_8), .ddr_addr_7(ddr_addr_7),
        .ddr_addr_6(ddr_addr_6), .ddr_addr_5(ddr_addr_5), .ddr_addr_4(ddr_addr_4),
        .ddr_addr_3(ddr_addr_3), .ddr_addr_2(ddr_addr_2), .ddr_addr_1(ddr_addr_1),
        .ddr_addr_0(ddr_addr_0), .ddr_odt(ddr_odt), .ddr_cke(ddr_cke), .ddr_we(ddr_we),
        .ddr_cas(ddr_cas), .ddr_ras(ddr_ras), .ddr_cs(ddr_cs));

    wire [43:0] lane = {ddr_dq, ddr_dm, ddr_dqs0_p, ddr_dqs0_n, ddr_dqs1_p, ddr_dqs1_n,
                        ddr_dqs2_p, ddr_dqs2_n, ddr_dqs3_p, ddr_dqs3_n};
    wire [15:0] addr = {ddr_addr_15, ddr_addr_14, ddr_addr_13, ddr_addr_12, ddr_addr_11,
                        ddr_addr_10, ddr_addr_9, ddr_addr_8, ddr_addr_7, ddr_addr_6,
                        ddr_addr_5, ddr_addr_4, ddr_addr_3, ddr_addr_2, ddr_addr_1,
                        ddr_addr_0};
    wire [2:0] bank = {ddr_bank_2, ddr_bank_1, ddr_bank_0};

    integer errors = 0;
    time last_driven = 0;
    reg in_run = 1'b0;

    // The device's reset and clock enable, every nanosecond.
    always @(ddr_reset_n or ddr_cke)
        if ($time > 0 && (ddr_reset_n !== 1'b0 || ddr_cke !== 1'b0)) begin
            $display("FAIL  t=%0t ddr_reset_n=%b ddr_cke=%b", $time, ddr_reset_n, ddr_cke);
            errors = errors + 1;
        end

    // Lane pads: never high; high-Z throughout RUN.
    integer k;
    always @(lane) begin
        // bits 7..0 are the strobes, P above N; a driven N half is the
        // complement of its P half, so it is high exactly when P is low
        for (k = 0; k < 44; k = k + 1)
            if (lane[k] === 1'b1 && !(k < 8 && k % 2 == 0 && lane[k + 1] === 1'b0)) begin
                $display("FAIL  t=%0t lane pad %0d driven high", $time, k);
                errors = errors + 1;
            end
        if (lane !== {44{1'bz}}) begin
            last_driven = $time;
            if (in_run) begin
                $display("FAIL  t=%0t lane pads %b in RUN", $time, lane);
                errors = errors + 1;
            end
        end
    end

    task send_byte(input [7:0] b);
        integer i;
        begin
            uart_rx = 1'b0;
            #500;
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = b[i];
                #500;
            end
            uart_rx = 1'b1;
            #500;
        end
    endtask

    reg [7:0] reply [0:21];
    task recv_byte(output [7:0] b);
        integer i;
        begin
            @(negedge uart_tx);
            #750;
            for (i = 0; i < 8; i = i + 1) begin
                b[i] = uart_tx;
                #500;
            end
        end
    endtask

    integer n;
    initial begin
        wait (dut.core.state == 3'd5);
        $display("      t=%0t sequencer reached RUN; DLL lock %b, lock timeout %b",
                 $time, dut.core.lock_ok, dut.core.lock_timeout);
        #2000;
        in_run = 1'b1;
        $display("      lane pads last driven at t=%0t, %0d ns before RUN + 2 us",
                 last_driven, $time - last_driven);
        if (lane !== {44{1'bz}}) begin
            $display("FAIL  lane pads not high-Z in RUN: %b", lane);
            errors = errors + 1;
        end
        if ({ddr_cs, ddr_ras, ddr_cas, ddr_we, ddr_odt} !== 5'b11110 || addr !== 16'd0 ||
            bank !== 3'd0 || ddr_ck_p !== 1'b0 || ddr_ck_n !== 1'b1) begin
            $display("FAIL  bank 7 levels: cs ras cas we odt %b, addr %h, bank %b, ck %b%b",
                     {ddr_cs, ddr_ras, ddr_cas, ddr_we, ddr_odt}, addr, bank, ddr_ck_p, ddr_ck_n);
            errors = errors + 1;
        end
        fork
            begin
                send_byte(8'haa); send_byte(8'h00); send_byte(8'h03); send_byte(8'h01);
            end
            for (n = 0; n < 22; n = n + 1)
                recv_byte(reply[n]);
        join
        $write("      status reply:");
        for (n = 0; n < 22; n = n + 1)
            $write(" %h", reply[n]);
        $write("\n");
        if (reply[0] !== 8'haa || reply[1] !== 8'h00 || reply[2] !== 8'h04 ||
            reply[3] !== 8'h12 || reply[4][1:0] !== 2'b11 || reply[4][7:5] !== 3'd5) begin
            $display("FAIL  status frame or flags");
            errors = errors + 1;
        end
        #20000;
        if (errors == 0)
            $display("PASS  reset held, lanes high-Z in RUN, bank 7 at its levels, status answered");
        else
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end

    initial begin
        #3000000;
        $display("FAIL  timeout: sequencer state %0d", dut.core.state);
        $finish;
    end
endmodule

`default_nettype wire
