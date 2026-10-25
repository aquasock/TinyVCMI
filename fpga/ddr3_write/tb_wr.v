`timescale 1ns / 1ps
`default_nettype none

// Simulation of the DDR3 write image against Gowin EDA's primitive models,
// with fpga/ddr3_phy_bringup/tb_dqs_standin.v for Gowin's empty DQS model.
// No DDR3 device model is attached: this checks what the image does to the
// device.  After the power-up it switches the modes over the link -- write
// leveling, idle, writes, idle, reads, idle, random single READs, idle --
// and asserts, from the commands decoded at every CK rising edge and from
// the pads:
//
//   * READ and WRITE only to an open row of their bank, tRCD after its
//     ACTIVATE; REFRESH and MRS only with every bank precharged, ACTIVATE
//     only to a precharged bank; tRP after a bank's precharge, tRC between
//     ACTIVATEs to one bank, tRRD and tFAW between ACTIVATEs, tRAS before a
//     precharge, and tRFC after a REFRESH before the next command;
//   * streaming modes in bank 0 without auto-precharge; random mode only
//     READs with auto-precharge, to the sixteen rows {row[14:1], 0 or 1};
//   * a REFRESH at least every 7.8 us outside write leveling;
//   * write leveling entered with MR1 0x00C4 and left with MR1 0x0044,
//     ODT high before any strobe is driven, and no DQ driven inside it;
//   * ODT high at every WRITE and low at every READ; DQ and strobes driven
//     at every WRITE, and nothing driven at any READ or outside the write
//     and leveling modes while RESET# is high; nothing ever driven high
//     before RESET# rises;
//   * each lane's DQS READ gate follows its own delay and offset and each
//     lane's RCLKSEL its own setting (commands 2C, 2D, 2E over 22, 25, 06),
//     and the lag and RBURST-level counters of frame 0x2F run in random mode,
//     with the RVALID-held capture switched on by command 29, and the read-
//     training counters of frame 0x31 count the random READs;
//   * frame 0x2F, the longest, reaches the link whole: its header and all
//     206 payload bytes equal to status4;
//   * the READ log keeps every random READ, and a page copied by command 33
//     reaches the link whole in frame 0x34, its entries those of the log;
//   * command 35 holds exactly the lanes it names for 4 x (v[7:4] + 1) PCLK,
//     or with code 15 until a command naming no lane releases them.
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
    wire [2:0] mode = dut.core.mode;
    always @(dq_pads or dqs_pads or ddr_reset_n or mode) begin
        if (ddr_reset_n === 1'b1 && mode != 3'd2 && dq_pads !== {36{1'bz}})
            fail("DQ or DM driven outside write mode");
        if (ddr_reset_n === 1'b1 && mode != 3'd2 && mode != 3'd1 && dqs_pads !== {8{1'bz}})
            fail("a strobe driven outside the write and leveling modes");
        if (mode == 3'd1 && dqs_pads !== {8{1'bz}} && ddr_odt !== 1'b1)
            fail("a strobe driven in leveling before ODT");
    end

    // commands at every CK rising edge, per bank: DDR3-800E, tCK 2.5 ns
    reg [7:0] open_b = 8'd0;
    reg [15:0] open_row [0:7];
    time t_act_b [0:7];
    time t_pre_b [0:7];                 // the bank's precharge began
    time t_act4 [0:3];                  // the last four ACTIVATEs, any bank
    reg in_level = 1'b0;
    wire row_open = |open_b;
    time t_ref = 0, t_last_ref = 0, t_last_act = 0, t_last_pre = 0;
    integer nwr = 0, nrd = 0, nref = 0, nact = 0, nlevel = 0, nrand = 0, b;
    time max_refi = 0;
    reg [3:0] c;
    initial for (b = 0; b < 8; b = b + 1) begin
        t_act_b[b] = 0; t_pre_b[b] = 0; open_row[b] = 16'd0;
        if (b < 4) t_act4[b] = 0;
    end
    task precharge(input integer bk, input time at);
        begin
            if (open_b[bk] && at - t_act_b[bk] < 37) fail("a precharge inside tRAS");
            open_b[bk] = 1'b0; t_pre_b[bk] = at;
            if (at > t_last_pre) t_last_pre = at;
        end
    endtask
    always @(posedge ddr_ck_p) if (ddr_ck_n === 1'b0 && ddr_cs === 1'b0) begin
        c = {ddr_cs, ddr_ras, ddr_cas, ddr_we};
        if (c != 4'b0111) begin
            if (t_ref != 0 && $time - t_ref < 260) fail("a command inside tRFC");
            case (c)
                4'b0011: begin                                   // ACTIVATE
                    if (open_b[bank]) fail("ACTIVATE to a bank with a row open");
                    if (t_pre_b[bank] != 0 && $time < t_pre_b[bank] + 15) fail("ACTIVATE inside tRP");
                    if (t_act_b[bank] != 0 && $time - t_act_b[bank] < 52) fail("ACTIVATE inside tRC");
                    if (t_last_act != 0 && $time - t_last_act < 10) fail("ACTIVATE inside tRRD");
                    if (t_act4[3] != 0 && $time - t_act4[3] < 50) fail("ACTIVATE inside tFAW");
                    if (mode == 3'd4 && addr[15:1] !== dut.core.row_p2[14:1])
                        fail("a random ACTIVATE outside the sixteen rows");
                    open_b[bank] = 1'b1; open_row[bank] = addr; t_act_b[bank] = $time;
                    t_act4[3] = t_act4[2]; t_act4[2] = t_act4[1]; t_act4[1] = t_act4[0];
                    t_act4[0] = $time; t_last_act = $time; nact = nact + 1;
                end
                4'b0010: begin                                   // PRECHARGE
                    if (addr[10] !== 1'b1) fail("PRECHARGE not to all banks");
                    for (b = 0; b < 8; b = b + 1) precharge(b, $time);
                end
                4'b0001: begin                                   // REFRESH
                    if (row_open) fail("REFRESH with a row open");
                    if (t_last_pre != 0 && $time < t_last_pre + 15) fail("REFRESH inside tRP");
                    if (t_last_ref != 0 && !in_level && $time - t_last_ref > max_refi)
                        max_refi = $time - t_last_ref;
                    t_ref = $time; t_last_ref = $time; nref = nref + 1;
                end
                4'b0100, 4'b0101: begin                          // WRITE, READ
                    if (!open_b[bank]) fail("a column command to a bank with no row open");
                    if ($time - t_act_b[bank] < 15) fail("a column command inside tRCD");
                    if (addr[2:0] !== 3'd0 || addr[12] !== 1'b0)
                        fail("a column command not BL8 aligned");
                    if (mode == 3'd4) begin
                        if (c != 4'b0101 || addr[10] !== 1'b1)
                            fail("random mode issued other than READ with auto-precharge");
                        nrand = nrand + 1;
                        // auto-precharge begins tRTP (4 tCK) after the READ
                        precharge(bank, $time + 10);
                    end else if (bank !== 3'd0 || addr[10] !== 1'b0) begin
                        fail("a streaming column command outside bank 0 or with auto-precharge");
                    end
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

    // The core's replies, decoded at 2 Mbaud while `listen` is set
    reg [7:0] rx_buf [0:255];
    integer rx_n = 0;
    integer listen = 0;
    always @(negedge uart_tx) if (listen) begin : rx_byte
        integer bi;
        reg [7:0] b;
        #750;                                                   // mid first data bit
        for (bi = 0; bi < 8; bi = bi + 1) begin
            b[bi] = uart_tx;
            #500;
        end
        if (rx_n < 256) rx_buf[rx_n] = b;
        rx_n = rx_n + 1;
    end

    integer dq_driven_at_write = 0;
    integer idle_wait = 0;
    integer fi, frame_bad;
    // PCLK each lane's DQS HOLD is high while hold_count is set
    integer hold_hi [0:3];
    integer hold_count = 0;
    integer hl;
    always @(posedge dut.pclk)
        if (hold_count)
            for (hl = 0; hl < 4; hl = hl + 1)
                if (dut.hold[hl] === 1'b1)
                    hold_hi[hl] = hold_hi[hl] + 1;

    // Per-lane READ gates in random mode: lanes 0 and 1 at delay 2, k 0;
    // lane 2 at delay 5; lane 3 at delay 2, k 3.  Every gate a lane opens is
    // compared with lane 0's: lane 2 opens 3 PCLK later, lane 3 as
    // 1000 with lane 0's 1111 and 0111 on the next PCLK.
    reg [15:0] re_d1 = 16'd0, re_d2 = 16'd0, re_d3 = 16'd0;
    integer gates_seen = 0;
    always @(posedge dut.pclk) begin
        re_d1 <= dut.read_en; re_d2 <= re_d1; re_d3 <= re_d2;
        if (mode == 3'd4 && dut.core.read_delay_p2 == {3'd2, 3'd5, 3'd2, 3'd2} &&
            dut.core.gate_p2 == {2'd3, 2'd0, 2'd0, 2'd0}) begin
            if (dut.read_en[7:4] !== dut.read_en[3:0])
                fail("lane 1's READ gate differs from lane 0's at the same setting");
            if (dut.read_en[11:8] !== re_d3[3:0])
                fail("lane 2's READ gate is not lane 0's three PCLK later");
            if (dut.read_en[3:0] == 4'b1111) begin
                gates_seen = gates_seen + 1;
                if (dut.read_en[15:12] !== 4'b1000)
                    fail("lane 3's READ gate does not open at its offset 3");
            end
            if (re_d1[3:0] == 4'b1111 && dut.read_en[15:12] !== 4'b0111)
                fail("lane 3's READ gate does not close one PCLK after lane 0's");
        end
    end
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
        #5000;
        request(8'h22, 8'h02);                                  // every lane's delay 2
        #30000;                                                 // its reply
        request(8'h25, 8'h00);                                  // every lane's k 0
        #30000;                                                 // its reply
        request(8'h06, 8'h03);                                  // every lane's RCLKSEL 3
        #30000;                                                 // its reply
        request(8'h2c, 8'h85);                                  // lane 2 delay 5
        #30000;                                                 // its reply
        request(8'h2d, 8'hc3);                                  // lane 3 k 3
        #30000;                                                 // its reply
        request(8'h2e, 8'h46);                                  // lane 1 RCLKSEL 6
        #30000;                                                 // its reply
        request(8'h29, 8'h01);                                  // RVALID-held capture
        #30000;                                                 // its reply
        request(8'h0c, 8'h04);                                  // random single READs
        #30000;
        if (dut.core.istate != 4'd12 && dut.core.istate != 4'd6) fail("not in random mode");
        if (dut.core.rc_total == 0) fail("rd_check saw no READ");
        if (dut.rclksel !== {3'd3, 3'd3, 3'd6, 3'd3}) fail("per-lane RCLKSEL not applied");
        if (gates_seen < 100) fail("too few per-lane READ gates compared");
        if (dut.core.rc_lag_eval == 0) fail("no READ classified for lag");
        if (dut.core.rb_cyc == 0) fail("the RBURST level was not counted in random mode");
        if (dut.core.rv_en_p2 !== 1'b1) fail("RVALID-held capture not enabled");
        if (dut.core.tr_reads == 0 || dut.core.tr_reads > dut.core.rc_total + 4)
            fail("the read-training READ count does not follow the random READs");
        request(8'h0c, 8'h00);
        #10000;
        if (dut.core.status4[184*8 +: 12] !== {3'd2, 3'd5, 3'd2, 3'd2} ||
            dut.core.status4[186*8 +: 8] !== {2'd3, 2'd0, 2'd0, 2'd0} ||
            dut.core.status4[187*8 +: 12] !== {3'd3, 3'd3, 3'd6, 3'd3} ||
            dut.core.status4[205*8] !== 1'b1 ||
            dut.core.status5[31:0] !== dut.core.tr_reads ||
            dut.core.status5[63:32] !== dut.core.rb_cyc)
            fail("frame 0x2F does not carry the per-lane settings");
        $display("      per-lane gates: %0d compared; %0d READs classified for lag over %0d PCLK",
                 gates_seen, dut.core.rc_lag_eval, dut.core.rb_cyc);
        // frame 0x2F over the link: the header and all 206 payload bytes
        #30000;                                                 // the mode request's reply
        rx_n = 0;
        listen = 1;
        request(8'h2f, 8'h00);
        idle_wait = 0;
        while (rx_n < 210 && idle_wait < 1200000) begin
            #1000;
            idle_wait = idle_wait + 1000;
        end
        #2000;
        listen = 0;
        frame_bad = 0;
        if (rx_n != 210 || rx_buf[0] !== 8'haa || rx_buf[1] !== 8'h00 ||
            rx_buf[2] !== 8'h06 || rx_buf[3] !== 8'd206)
            frame_bad = 1;
        for (fi = 0; fi < 206; fi = fi + 1)
            if (rx_buf[4 + fi] !== dut.core.status4[8*fi +: 8])
                frame_bad = frame_bad + 1;
        if (frame_bad != 0) begin
            $display("      %0d bytes, header %h %h %h %h, %0d wrong",
                     rx_n, rx_buf[0], rx_buf[1], rx_buf[2], rx_buf[3], frame_bad);
            fail("frame 0x2F does not arrive whole over the link");
        end
        $display("      frame 0x2F: %0d bytes received, payload equal to status4", rx_n);
        // the READ log: copy page 1, then frame 0x34 over the link
        if (dut.core.rc_log_n < 300 || dut.core.rc_log_n > dut.core.rc_total + 2 ||
            dut.core.rc_log_n + 2 < dut.core.rc_total)
            fail("the READ log did not keep every random READ");
        request(8'h33, 8'h01);
        #30000;                                                 // its reply
        if (dut.core.rc_log_page !== 6'd1) fail("log page 1 was not copied");
        rx_n = 0;
        listen = 1;
        request(8'h34, 8'h00);
        idle_wait = 0;
        while (rx_n < 152 && idle_wait < 1200000) begin
            #1000;
            idle_wait = idle_wait + 1000;
        end
        #2000;
        listen = 0;
        frame_bad = 0;
        if (rx_n != 152 || rx_buf[0] !== 8'haa || rx_buf[1] !== 8'h00 ||
            rx_buf[2] !== 8'h08 || rx_buf[3] !== 8'd148 || rx_buf[6] !== 8'd1)
            frame_bad = 1;
        for (fi = 0; fi < 148; fi = fi + 1)
            if (rx_buf[4 + fi] !== dut.core.status6[8*fi +: 8])
                frame_bad = frame_bad + 1;
        if (dut.core.status6[0 +: 16] !== {5'd0, dut.core.rc_log_n} ||
            dut.core.status6[32 +: 72] !== dut.core.check.log_mem[16])
            frame_bad = frame_bad + 1;
        if (frame_bad != 0) begin
            $display("      %0d bytes, header %h %h %h %h, %0d wrong",
                     rx_n, rx_buf[0], rx_buf[1], rx_buf[2], rx_buf[3], frame_bad);
            fail("frame 0x34 does not carry log page 1 whole over the link");
        end
        $display("      READ log: %0d entries; page 1 over the link, entry 16 equal to the log",
                 dut.core.rc_log_n);
        // per-lane HOLD: lanes 0 and 2 for 4 x (1 + 1) PCLK, the others not at all
        hold_count = 1;
        hold_hi[0] = 0; hold_hi[1] = 0; hold_hi[2] = 0; hold_hi[3] = 0;
        request(8'h35, 8'h15);
        #30000;                                                 // its reply
        hold_count = 0;
        if (hold_hi[0] != 8 || hold_hi[2] != 8 || hold_hi[1] != 0 || hold_hi[3] != 0) begin
            $display("      HOLD high for %0d %0d %0d %0d PCLK", hold_hi[0], hold_hi[1],
                     hold_hi[2], hold_hi[3]);
            fail("command 0x35 did not hold exactly lanes 0 and 2 for 8 PCLK");
        end
        $display("      HOLD: lanes 0 and 2 for 8 PCLK, lanes 1 and 3 untouched");
        // the level form: lanes 1 and 3 held until a command naming no lane
        request(8'h35, 8'hfa);
        #30000;
        if (dut.hold !== 4'b1010) fail("command 0x35 with code 15 did not hold lanes 1 and 3");
        #20000;
        if (dut.hold !== 4'b1010) fail("the level HOLD did not stay until the next command");
        request(8'h35, 8'h00);
        #30000;
        if (dut.hold !== 4'b0000) fail("command 0x35 naming no lane did not release the HOLD");
        $display("      HOLD: level on lanes 1 and 3 held and released");
        // idle mode refreshes every 7 us and waits tRFC after each, so the
        // core is given up to 2 us to be seen in its idle state
        idle_wait = 0;
        while (dut.core.istate != 4'd8 && idle_wait < 2000) begin
            #10;
            idle_wait = idle_wait + 10;
        end
        if (dut.core.istate != 4'd8 || dut.core.mode != 3'd0) begin
            $display("      state %0d mode %0d", dut.core.istate, dut.core.mode);
            fail("not back in idle");
        end
        if (row_open) fail("a row left open");
        $display("      %0d ACTIVATE, %0d WRITE, %0d READ (%0d random), %0d REFRESH, %0d leveling entries; longest refresh interval %0d ns",
                 nact, nwr, nrd, nrand, nref, nlevel, max_refi);
        if (nwr < 1000 || nrd < 500) fail("writes or gated reads did not run");
        if (nrand < 300) fail("random READs did not run");
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
        #6000000;
        $display("FAIL  timeout: state %0d", dut.core.istate);
        $finish;
    end
endmodule

`default_nettype wire
