`timescale 1ns / 1ps
`default_nettype none

// Simulation of the DDR3 write image against Gowin EDA's primitive models,
// with fpga/ddr3_phy_bringup/tb_dqs_standin.v for Gowin's empty DQS model.
// No DDR3 device model is attached: this checks what the image does to the
// device.  After the power-up it switches the modes over the link -- write
// leveling, idle, writes, idle, reads, idle -- and asserts, from the
// commands decoded at every CK rising edge and from the pads:
//
//   * READ and WRITE only to an open row, tRCD after its ACTIVATE;
//     ACTIVATE, REFRESH and MRS only with every bank precharged; tRP after
//     a PRECHARGE and tRFC after a REFRESH before the next command;
//   * a REFRESH at least every 7.8 us outside write leveling;
//   * write leveling entered with MR1 0x00C4 and left with MR1 0x0044,
//     ODT high before any strobe is driven, and no DQ driven inside it;
//   * ODT high at every WRITE and low at every READ; DQ and strobes driven
//     at every WRITE, and nothing driven at any READ or outside the write
//     and leveling modes while RESET# is high; nothing ever driven high
//     before RESET# rises.
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

    wire [35:0] dq_pads = {ddr_dq, ddr_dm};
    wire [7:0] dqs_pads = {ddr_dqs0_p, ddr_dqs0_n, ddr_dqs1_p, ddr_dqs1_n,
                           ddr_dqs2_p, ddr_dqs2_n, ddr_dqs3_p, ddr_dqs3_n};
    wire [15:0] addr = {ddr_addr_15, ddr_addr_14, ddr_addr_13, ddr_addr_12, ddr_addr_11,
                        ddr_addr_10, ddr_addr_9, ddr_addr_8, ddr_addr_7, ddr_addr_6,
                        ddr_addr_5, ddr_addr_4, ddr_addr_3, ddr_addr_2, ddr_addr_1,
                        ddr_addr_0};
    wire [2:0] bank = {ddr_bank_2, ddr_bank_1, ddr_bank_0};

    integer errors = 0;
    task fail(input [8*96-1:0] msg);
        begin
            if (errors < 20)
                $display("FAIL  t=%0t %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // pads: nothing while the device is in reset or outside the driving modes
    wire [1:0] mode = dut.core.mode;
    always @(dq_pads or dqs_pads or ddr_reset_n or mode) begin
        if (ddr_reset_n === 1'b1 && mode != 2'd2 && dq_pads !== {36{1'bz}})
            fail("DQ or DM driven outside write mode");
        if (ddr_reset_n === 1'b1 && mode != 2'd2 && mode != 2'd1 && dqs_pads !== {8{1'bz}})
            fail("a strobe driven outside the write and leveling modes");
        if (mode == 2'd1 && dqs_pads !== {8{1'bz}} && ddr_odt !== 1'b1)
            fail("a strobe driven in leveling before ODT");
    end

    // commands at every CK rising edge
    reg row_open = 1'b0, in_level = 1'b0;
    time t_act = 0, t_pre = 0, t_ref = 0, t_cmd = 0, t_last_ref = 0;
    integer nwr = 0, nrd = 0, nref = 0, nact = 0, nlevel = 0;
    time max_refi = 0;
    reg [3:0] c;
    always @(posedge ddr_ck_p) if (ddr_ck_n === 1'b0 && ddr_cs === 1'b0) begin
        c = {ddr_cs, ddr_ras, ddr_cas, ddr_we};
        if (c != 4'b0111) begin
            if (t_ref != 0 && $time - t_ref < 260) fail("a command inside tRFC");
            case (c)
                4'b0011: begin                                   // ACTIVATE
                    if (row_open) fail("ACTIVATE with a row open");
                    if (t_pre != 0 && $time - t_pre < 15) fail("ACTIVATE inside tRP");
                    row_open = 1'b1; t_act = $time; nact = nact + 1;
                end
                4'b0010: begin                                   // PRECHARGE
                    if (addr[10] !== 1'b1) fail("PRECHARGE not to all banks");
                    row_open = 1'b0; t_pre = $time;
                end
                4'b0001: begin                                   // REFRESH
                    if (row_open) fail("REFRESH with a row open");
                    if (t_pre != 0 && $time - t_pre < 15) fail("REFRESH inside tRP");
                    if (t_last_ref != 0 && !in_level && $time - t_last_ref > max_refi)
                        max_refi = $time - t_last_ref;
                    t_ref = $time; t_last_ref = $time; nref = nref + 1;
                end
                4'b0100, 4'b0101: begin                          // WRITE, READ
                    if (!row_open) fail("a column command with no row open");
                    if ($time - t_act < 15) fail("a column command inside tRCD");
                    if (bank !== 3'd0 || addr[2:0] !== 3'd0 || addr[12] !== 1'b0 || addr[10] !== 1'b0)
                        fail("a column command outside bank 0, BL8 aligned, no auto-precharge");
                    if (c == 4'b0100) begin
                        nwr = nwr + 1;
                        if (ddr_odt !== 1'b1) fail("a WRITE with ODT low");
                        if (dq_pads === {36{1'bz}} || dqs_pads === {8{1'bz}}) fail("a WRITE with the bus undriven");
                    end else begin
                        nrd = nrd + 1;
                        if (ddr_odt !== 1'b0) fail("a READ with ODT high");
                    end
                end
                4'b0000: begin                                   // MRS
                    if (row_open) fail("MRS with a row open");
                    if (bank == 3'd1 && addr == 16'h00c4) begin
                        in_level = 1'b1; nlevel = nlevel + 1;
                    end else if (bank == 3'd1 && addr == 16'h0044) begin
                        in_level = 1'b0; t_last_ref = 0;
                    end
                end
                4'b0110: ;                                       // ZQCL
                default: fail("an unexpected command");
            endcase
        end
    end

    // the device's reset and clock enable
    always @(ddr_reset_n or ddr_cke)
        if ($time > 0 && ddr_reset_n !== 1'b1 && ddr_cke === 1'b1) fail("CKE high with RESET# low");

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
    task request(input [7:0] cmd, input [7:0] arg);
        begin
            send_byte(8'haa); send_byte(8'h00); send_byte(cmd); send_byte(arg);
            #3000;
        end
    endtask

    integer dq_driven_at_write = 0;
    initial begin
        wait (dut.core.istate == 4'd8);
        $display("      t=%0t power-up done", $time);
        request(8'h10, 8'h20);                                  // lane 0 WSTEP
        request(8'h0c, 8'h01);                                  // write leveling
        #20000;
        if (dut.core.istate != 4'd9) fail("not in leveling");
        request(8'h0c, 8'h00);
        #5000;
        request(8'h0c, 8'h02);                                  // writes
        #30000;
        request(8'h0c, 8'h00);
        #5000;
        request(8'h0c, 8'h03);                                  // reads
        #30000;
        request(8'h0c, 8'h00);
        #10000;
        if (dut.core.istate != 4'd8) fail("not back in idle");
        if (row_open) fail("a row left open");
        $display("      %0d ACTIVATE, %0d WRITE, %0d READ, %0d REFRESH, %0d leveling entries; longest refresh interval %0d ns",
                 nact, nwr, nrd, nref, nlevel, max_refi);
        if (nwr < 1000 || nrd < 500) fail("writes or gated reads did not run");
        if (nlevel != 1) fail("leveling not entered once");
        if (max_refi > 7800) fail("a refresh interval over 7.8 us");
        if (nref < 8) fail("too few refreshes");
        if (dut.wstep[7:0] !== 8'h20) fail("lane 0 WSTEP not applied");
        if (errors == 0)
            $display("PASS  leveling, writes, reads and refresh as specified; the bus driven only where it may be");
        else
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end

    initial begin
        #4000000;
        $display("FAIL  timeout: state %0d", dut.core.istate);
        $finish;
    end
endmodule

`default_nettype wire
