`timescale 1ns / 1ps
`default_nettype none

// Simulation of the DDR3 MPR read-back image against Gowin EDA's primitive
// models (IDE/simlib/gw5a/prim_sim.v), with tb_dqs_standin.v from
// fpga/ddr3_phy_bringup in place of Gowin's empty DQS model.  No DDR3 device
// model is attached: this checks what the image does to the device, not
// what the device answers.  It asserts:
//
//   * the PHY start-up: the memory clock stops once, the CLKDIV and lane
//     reset is pulsed with it stopped, and READY follows the restart;
//   * RESET# stays low until 200 us after READY, CKE until 500 us after
//     RESET#, and ODT is never high;
//   * the commands, decoded at every CK rising edge: MRS MR2, MR3, MR1, MR0
//     with their values, ZQCL, MRS MR3 with MPR on, and then only READs to
//     bank 0 column 0 once reads are switched on -- never ACTIVATE, WRITE,
//     PRECHARGE or REFRESH, and every command with CKE high;
//   * no DQ, DM or strobe pad is ever driven while RESET# is high, and none
//     is ever driven high;
//   * the link: reads switched on with `AA 00 08 01`, and the status frame
//     reporting READY, CKE, RESET#, reads on and init state 7.
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
    time t_ready = 0, t_reset = 0, t_cke = 0;

    task fail(input [8*96-1:0] msg);
        begin
            $display("FAIL  t=%0t %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // PHY start-up: one clock stop, the reset pulse inside it
    integer stops = 0, resets_while_stopped = 0;
    always @(negedge dut.pll_en) if ($time > 0) stops = stops + 1;
    always @(posedge dut.phy_rst) if (!dut.pll_en) resets_while_stopped = resets_while_stopped + 1;
    always @(negedge dut.phy_rst) if (stops > 0 && dut.pll_en) fail("lane reset released with the clock running");
    always @(posedge dut.core.ready) begin
        t_ready = $time;
        $display("      t=%0t READY; clock stops %0d, reset pulses while stopped %0d",
                 $time, stops, resets_while_stopped);
        if (stops != 1 || resets_while_stopped != 1)
            fail("PHY start-up is not one stop with one reset inside it");
    end

    // the device's reset, clock enable and termination
    always @(posedge ddr_reset_n) begin
        t_reset = $time;
        $display("      t=%0t RESET# high, %0d us after READY", $time, (t_reset - t_ready) / 1000);
        if (t_ready == 0 || t_reset - t_ready < 200000) fail("RESET# released early");
    end
    always @(posedge ddr_cke) begin
        t_cke = $time;
        $display("      t=%0t CKE high, %0d us after RESET#", $time, (t_cke - t_reset) / 1000);
        if (t_reset == 0 || t_cke - t_reset < 500000) fail("CKE raised early");
    end
    always @(ddr_odt) if ($time > 0 && ddr_odt !== 1'b0) fail("ODT not low");

    // lane pads: never high, never driven with the device out of reset
    integer k;
    always @(lane or ddr_reset_n) begin
        for (k = 0; k < 44; k = k + 1)
            if (lane[k] === 1'b1 && !(k < 8 && k % 2 == 0 && lane[k + 1] === 1'b0))
                fail("a lane pad driven high");
        if (ddr_reset_n === 1'b1 && lane !== {44{1'bz}})
            fail("a lane pad driven with RESET# high");
    end

    // commands at every CK rising edge
    integer ncmd = 0, nreads = 0;
    reg [3:0] c;
    always @(posedge ddr_ck_p) if (ddr_ck_n === 1'b0) begin
        c = {ddr_cs, ddr_ras, ddr_cas, ddr_we};
        if (c[3] === 1'b0 && c !== 4'b0111) begin
            if (ddr_cke !== 1'b1) fail("a command with CKE low");
            if (c == 4'b0101) begin
                nreads = nreads + 1;
                if (ncmd != 6) fail("a READ before the MPR enable");
                if (bank !== 3'd0 || addr !== 16'h0000) fail("a READ outside bank 0 column 0");
            end else begin
                case (ncmd)
                    0: if (c !== 4'b0000 || bank !== 3'd2 || addr !== 16'h0000) fail("command 1 is not MRS MR2 0x0000");
                    1: if (c !== 4'b0000 || bank !== 3'd3 || addr !== 16'h0000) fail("command 2 is not MRS MR3 0x0000");
                    2: if (c !== 4'b0000 || bank !== 3'd1 || addr !== 16'h0044) fail("command 3 is not MRS MR1 0x0044");
                    3: if (c !== 4'b0000 || bank !== 3'd0 || addr !== 16'h0520) fail("command 4 is not MRS MR0 0x0520");
                    4: if (c !== 4'b0110 || addr[10] !== 1'b1) fail("command 5 is not ZQCL");
                    5: if (c !== 4'b0000 || bank !== 3'd3 || addr !== 16'h0004) fail("command 6 is not MRS MR3 MPR on");
                    default: fail("a command after the MPR enable that is not a READ");
                endcase
                $display("      t=%0t command %0d: %b bank %0d addr %h", $time, ncmd + 1, c, bank, addr);
                ncmd = ncmd + 1;
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

    reg [7:0] reply [0:59];
    integer n;
    initial begin
        wait (dut.core.istate == 4'd7);
        $display("      t=%0t init done; switching reads on", $time);
        fork
            begin send_byte(8'haa); send_byte(8'h00); send_byte(8'h08); send_byte(8'h01); end
            for (n = 0; n < 5; n = n + 1) recv_byte(reply[n]);
        join
        if (reply[2] !== 8'h02 || reply[4] !== 8'h56) fail("no acknowledgement for reads on");
        #5000;
        fork
            begin send_byte(8'haa); send_byte(8'h00); send_byte(8'h03); send_byte(8'h01); end
            for (n = 0; n < 60; n = n + 1) recv_byte(reply[n]);
        join
        $write("      status:");
        for (n = 0; n < 12; n = n + 1) $write(" %h", reply[n]);
        $write(" ...\n");
        if (reply[3] !== 8'h38) fail("status frame length");
        if (reply[4][7] !== 1'b1 || reply[4][3:1] !== 3'b111) fail("status flags: ready, CKE, RESET#, reads on");
        if (reply[6][3:0] !== 4'd7) fail("status init state");
        if (nreads < 100) fail("reads did not stream");
        $display("      %0d READs issued", nreads);
        if (errors == 0)
            $display("PASS  PHY start-up, JEDEC init, MPR enable and reads as specified; lanes never driven");
        else
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end

    initial begin
        #4000000;
        $display("FAIL  timeout: init state %0d, ready %b", dut.core.istate, dut.core.ready);
        $finish;
    end
endmodule

`default_nettype wire
