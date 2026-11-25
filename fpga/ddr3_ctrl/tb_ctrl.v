`timescale 1ns / 1ps
`default_nettype none

// Simulation of the controller's fabric, ctrl_glue -- ddr3_ctl, dfi_phy and
// the memory test -- against a model of the trained PHY and the DDR3 array
// behind the pads, cycle by cycle at PCLK.  The model takes, in each PCLK,
// the four memory clocks' commands from the pads' per-phase command
// registers, memory clock 4 x PCLK + phase, and requires:
//
//   * READ and WRITE only in memory clock 0, and only to a bank with a row
//     open, rows 0 to 3, which the test's 2^12 words span; ACTIVATE only to a
//     closed bank, PRECHARGE of one bank or all, REFRESH with all closed;
//   * DDR3-800 timing in memory clocks of 2.5 ns, from the devices'
//     figures rather than the controller's: tRCD and tRP 6, tRAS 15, tRC
//     21, tRRD 4, tFAW 16, tCCD 4, tRTP 4, WRITE to PRECHARGE CWL + 4 + tWR
//     = 15, WRITE to READ CWL + 4 + tWTR = 13, READ to WRITE CL + 4 + 2 -
//     CWL = 7, tRFC 104 (260 ns) and a REFRESH at least every 3,120 (7.8 us);
//   * our DQ never driven in a PCLK that holds a read burst on the bus, CL
//     after its READ with a clock of preamble before and of postamble after
//     -- serializer word t carries memory clocks 4t .. 4t + 3, as the trained
//     write alignment places a WRITE's burst at CWL;
//   * a WRITE's burst in the serializer words as the trained write alignment
//     (d, b) places it on the board -- beats 0 .. 7-b of each pin in beats
//     b .. 7 of the word d PCLK after the WRITE, the rest in beats 0 .. b-1
//     of the next -- with DQ and DQS driven over both and ODT high in the
//     WRITE's PCLK;
//   * ODT low at every READ;
//
// and answers each READ with the burst on the raw deserializer outputs RDO
// PCLK after it, 7 as on the board, nothing valid otherwise.  The test runs
// two passes over 2^12 words with 2^12 random READs each, so random READs
// switch rows in a bank, and every word must come back as written, with no
// READ or WRITE off phase 0.
//
// The model honours DM: each WRITE's mask is taken from the DM pads' words
// with the same shift as its data, and a byte whose DM bit is set keeps what
// it held.  The test writes every word twice a pass, the second time inverted
// under a mask, so a burst whose mask is lost, a beat off or on the wrong
// lane leaves bytes that differ in all eight bits; MODEL_NODM, MODEL_DMBEAT
// and MODEL_DMLANE make the model do exactly those, and the test must see it.
//
// With MODEL_FAULTS the model leaves word 100 wrong after its masked write,
// the first time, lane 1 pin 1 beat 3 flipped (after the merge, so the fault
// is the word's whatever its mask), and reads word 2000 wrong the first time, lane 2
// pin 1 beat 5 flipped, and the test's diagnostics must say so: those pins
// and beats counted and nothing else, both words logged, the first re-read
// as wrong as the first read and the second right.
//
// MODEL_RDO and MODEL_D override the model's read offset and write
// alignment, so that a design whose offset or alignment were not the
// trained one's is seen to fail, and CTL_T_* shorten the controller's timing,
// so that the checks are seen to catch it (tools/sim_ddr3_ctrl.sh runs the
// ones this traffic can show).  The test's traffic turns from reading to
// writing only between passes, so READ to WRITE spacing and the bus
// turnaround it guards are checked but never exercised closely.
module tb_ctrl;
    reg pclk = 1'b0, sys_clk = 1'b0;
    always #5 pclk = ~pclk;             // 100 MHz
    always #10 sys_clk = ~sys_clk;      // 50 MHz

`ifdef MODEL_RDO
    localparam integer RDO = `MODEL_RDO;
`else
    localparam integer RDO = 7;
`endif
`ifdef MODEL_D
    localparam integer WD = `MODEL_D;
`else
    localparam integer WD = 1;
`endif
    localparam integer WB = 2;          // the board's d 1, b 2
    localparam integer NL = 12;         // rows 0..3 of every bank

    integer errors = 0;
    task fail(input [8*96-1:0] msg);
        begin
            if (errors < 20) $display("FAIL  t=%0t %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    reg  [255:0] dq_q = 256'd0;
    reg          ctrl_own = 1'b0;
    reg  [7:0]   ext_cmd = 8'd0;
    reg          ext_tog = 1'b0;
    wire [3:0]   p_cs_n, p_ras_n, p_cas_n, p_we_n;
    wire [11:0]  p_ba;
    wire [63:0]  p_addr;
    wire         p_odt, p_dq_drive, p_dqs_drive, ctrl_rd, ctrl_accept;
    wire [255:0] wdq;
    wire [31:0]  dm;
    wire [511:0] ext_status;

    // TB_CPU: the AE350 image's glue, handed to the x_ port after the test
`ifdef TB_CPU
    localparam integer CPU = 1;
`else
    localparam integer CPU = 0;
`endif
    reg          x_valid = 1'b0, x_we = 1'b0;
    reg  [24:0]  x_addr = 25'd0;
    reg  [255:0] x_wdata = 256'd0;
    reg  [31:0]  x_wmask = 32'd0;
    wire         x_ready, x_rvalid, x_rst, cpu_run;
    wire [255:0] x_rdata;
    ctrl_glue #(.N_LOG2(NL), .R_LOG2(NL), .SNAP_LOG2(4), .CPU(CPU), .HAND_LOG2(4)) dut (
        .sys_clk(sys_clk), .pclk(pclk), .dq_q(dq_q),
        .wc_cs_n(1'b1), .wc_ras_n(1'b1), .wc_cas_n(1'b1), .wc_we_n(1'b1),
        .wc_ba(3'd0), .wc_addr(16'd0), .wc_odt(1'b0), .wc_dq_pat(8'h00),
        .wc_dq_drive(1'b0), .wc_dqs_drive(1'b0),
        .ctrl_own(ctrl_own), .ctrl_own_x({7{ctrl_own}}), .ctrl_trained(1'b1), .ctrl_walign({3'd1, 1'b0, 3'd2}),
        .ctrl_rot(12'd0), .ext_cmd(ext_cmd), .ext_tog(ext_tog),
        .p_cs_n(p_cs_n), .p_ras_n(p_ras_n), .p_cas_n(p_cas_n), .p_we_n(p_we_n),
        .p_ba(p_ba), .p_addr(p_addr), .p_odt(p_odt), .p_dq_drive(p_dq_drive),
        .p_dqs_drive(p_dqs_drive), .wdq(wdq), .dm(dm), .ctrl_rd(ctrl_rd), .ctrl_accept(ctrl_accept),
        .ext_status(ext_status),
        .x_valid(x_valid), .x_we(x_we), .x_addr(x_addr), .x_wdata(x_wdata), .x_wmask(x_wmask),
        .x_ready(x_ready), .x_rvalid(x_rvalid), .x_rdata(x_rdata), .x_rst(x_rst), .cpu_run(cpu_run));

    // a controller a timing short, so the monitor is seen to catch it
`ifdef CTL_T_RCD
    defparam dut.ctl.T_RCD = `CTL_T_RCD;
`endif
`ifdef CTL_T_WTR
    defparam dut.ctl.T_WTR = `CTL_T_WTR;
`endif
`ifdef CTL_T_RTW
    defparam dut.ctl.T_RTW = `CTL_T_RTW;
`endif
`ifdef CTL_T_RAS
    defparam dut.ctl.T_RAS = `CTL_T_RAS;
`endif
`ifdef CTL_T_RP
    defparam dut.ctl.T_RP = `CTL_T_RP;
`endif
`ifdef CTL_T_RC
    defparam dut.ctl.T_RC = `CTL_T_RC;
`endif

    // ---- the model --------------------------------------------------------
    reg [255:0] mem [0:(1 << NL) - 1];  // {row[1:0], bank, column burst}
    reg         open [0:7];
    reg [14:0]  orow [0:7];
    integer     cyc = 0;
    // pending writes: the WRITE's cycle and where its burst goes
    integer     wr_cyc [0:63];
    integer     wr_key [0:63];
    integer     wr_n = 0;
    // READs to answer: cycle and key
    integer     rd_at [0:63];
    integer     rd_key [0:63];
    integer     rd_n = 0;
    reg [255:0] wdq_hist [0:15];        // the serializers' words, newest at 0
    reg [31:0]  dm_hist [0:15];         // and the DM pads' words
    integer     n_mbytes = 0, n100 = 0;
    reg [15:0]  drv_hist = 16'd0;
    integer     n_reads = 0, n_writes = 0, n_bad_pin = 0, n_refs = 0;
    reg         fault_w = 1'b0, fault_r = 1'b0;
    // timing, in memory clocks; -1000 is long ago
    integer     t_act [0:7], t_pre [0:7], t_rd [0:7], t_wr [0:7];
    integer     t_act4 [0:3];
    integer     t_act_any = -1000, t_cas_any = -1000, t_rd_any = -1000, t_wr_any = -1000;
    integer     t_pre_any = -1000, t_ref = -1000, max_refi = 0;
    integer     ck, rb;
    reg [63:0]  rd_busy = 64'd0;        // PCLK holding a read burst, bit 0 the next one once shifted
    task need(input integer gap, input integer min, input [8*48-1:0] what);
        if (gap < min) begin
            $display("      %0s: %0d memory clocks, %0d needed", what, gap, min);
            fail(what);
        end
    endtask

    integer i, ph, k, pn, bb, key;
    reg [2:0]  cb;
    reg [15:0] ca;
    reg [255:0] burst, w_first, w_second;
    reg [31:0]  d_first, d_second, mburst;     // mburst: 1 suppresses beat b, lane l at 4b + l
    integer     ml, mp, mb2;
    reg        cmd_cs, cmd_ras, cmd_cas, cmd_we;
    initial begin
        for (i = 0; i < 8; i = i + 1) begin
            open[i] = 1'b0; orow[i] = 15'd0;
            t_act[i] = -1000; t_pre[i] = -1000; t_rd[i] = -1000; t_wr[i] = -1000;
        end
        for (i = 0; i < 4; i = i + 1) t_act4[i] = -1000;
        for (i = 0; i < (1 << NL); i = i + 1) mem[i] = 256'd0;
        for (i = 0; i < 16; i = i + 1) begin
            wdq_hist[i] = 256'd0;
            dm_hist[i] = 32'd0;
        end
    end

    // the pads hold a PCLK's values from one rising edge to the next; read
    // them at the falling edge, and set dq_q there for the next rising edge
    always @(negedge pclk) begin
        cyc = cyc + 1;
        for (i = 15; i > 0; i = i - 1) begin
            wdq_hist[i] = wdq_hist[i - 1];
            dm_hist[i] = dm_hist[i - 1];
        end
        wdq_hist[0] = wdq;
        dm_hist[0] = dm;
        drv_hist = {drv_hist[14:0], p_dq_drive && p_dqs_drive};

        // our drive against a read burst on the bus in this PCLK
        if (p_dq_drive && rd_busy[0]) fail("DQ driven while a read burst is on the bus");
        rd_busy = rd_busy >> 1;

        // the four memory clocks' commands
        for (ph = 0; ph < 4; ph = ph + 1) begin
            ck = 4 * cyc + ph;
            cmd_cs = !p_cs_n[ph];
            cmd_ras = !p_ras_n[ph]; cmd_cas = !p_cas_n[ph]; cmd_we = !p_we_n[ph];
            cb = p_ba[3*ph +: 3];
            ca = p_addr[16*ph +: 16];
            if (cmd_cs) begin
                if (cmd_ras && !cmd_cas && !cmd_we) begin           // ACTIVATE
                    if (open[cb]) fail("ACTIVATE to an open bank");
                    need(ck - t_pre[cb], 6, "tRP before an ACTIVATE");
                    need(ck - t_act[cb], 21, "tRC");
                    need(ck - t_act_any, 4, "tRRD");
                    need(ck - t_act4[3], 16, "tFAW");
                    need(ck - t_ref, 104, "tRFC before an ACTIVATE");
                    open[cb] = 1'b1;
                    orow[cb] = ca[14:0];
                    t_act[cb] = ck; t_act_any = ck;
                    t_act4[3] = t_act4[2]; t_act4[2] = t_act4[1]; t_act4[1] = t_act4[0];
                    t_act4[0] = ck;
                end else if (cmd_ras && !cmd_cas && cmd_we) begin   // PRECHARGE
                    for (i = 0; i < 8; i = i + 1)
                        if ((ca[10] || i == cb) && open[i]) begin
                            need(ck - t_act[i], 15, "tRAS");
                            need(ck - t_rd[i], 4, "tRTP");
                            need(ck - t_wr[i], 15, "WRITE to PRECHARGE (tWR)");
                        end
                    if (ca[10]) for (i = 0; i < 8; i = i + 1) open[i] = 1'b0;
                    else open[cb] = 1'b0;
                    if (ca[10]) for (i = 0; i < 8; i = i + 1) t_pre[i] = ck;
                    else t_pre[cb] = ck;
                    t_pre_any = ck;
                end else if (cmd_ras && cmd_cas && !cmd_we) begin   // REFRESH
                    for (i = 0; i < 8; i = i + 1)
                        if (open[i]) fail("REFRESH with a bank open");
                    need(ck - t_pre_any, 6, "tRP before a REFRESH");
                    need(ck - t_ref, 104, "tRFC between REFRESHes");
                    if (t_ref > 0 && ck - t_ref > max_refi) max_refi = ck - t_ref;
                    t_ref = ck;
                    n_refs = n_refs + 1;
                end else if (!cmd_ras && cmd_cas) begin             // READ or WRITE
                    if (ph != 0) fail("a READ or WRITE off memory clock 0");
                    if (!open[cb]) fail("a READ or WRITE to a closed bank");
                    if (orow[cb] > 15'd3) fail("a READ or WRITE outside rows 0 to 3");
                    need(ck - t_act[cb], 6, "tRCD");
                    need(ck - t_cas_any, 4, "tCCD");
                    // not a DDR3 rule but this PHY's: on the board a READ two
                    // PCLK after a READ returns the bus between two bursts, so
                    // ddr3_ctl puts none there (one PCLK apart or three or more)
                    if (ck - t_cas_any == 8)
                        fail("a READ or WRITE two PCLK after the last, which the PHY cannot read");
                    if (cmd_we) need(ck - t_rd_any, 7, "READ to WRITE");
                    else need(ck - t_wr_any, 13, "WRITE to READ (tWTR)");
                    t_cas_any = ck;
                    if (cmd_we) begin t_wr[cb] = ck; t_wr_any = ck; end
                    else begin
                        t_rd[cb] = ck; t_rd_any = ck;
                        // the burst, CL 6 on, with a clock either side
                        for (rb = ck + 5; rb < ck + 11; rb = rb + 1)
                            if (rb / 4 - cyc - 1 < 64) rd_busy[rb / 4 - cyc - 1] = 1'b1;
                    end
                    key = {orow[cb][1:0], cb, ca[9:3]};
                    if (cmd_we) begin
                        if (!p_odt) fail("ODT low at a WRITE");
                        wr_cyc[wr_n] = cyc;
                        wr_key[wr_n] = key;
                        wr_n = wr_n + 1;
                        n_writes = n_writes + 1;
                    end else begin
                        if (p_odt) fail("ODT high at a READ");
                        rd_at[rd_n] = cyc + RDO;
                        rd_key[rd_n] = key;
                        rd_n = rd_n + 1;
                        n_reads = n_reads + 1;
                    end
                end
            end
        end

        // a WRITE's burst, once its second word has gone by
        while (wr_n > 0 && cyc == wr_cyc[0] + WD + 1) begin
            w_first = wdq_hist[1];
            w_second = wdq_hist[0];
            d_first = dm_hist[1];
            d_second = dm_hist[0];
            if (!drv_hist[0] || !drv_hist[1]) fail("DQ or DQS not driven over a burst");
            for (pn = 0; pn < 32; pn = pn + 1)
                for (bb = 0; bb < 8; bb = bb + 1)
                    burst[8*pn + bb] = (bb < 8 - WB) ? w_first[8*pn + WB + bb]
                                                     : w_second[8*pn + bb - (8 - WB)];
            // DM takes the same shift as each of its lane's pins
            for (ml = 0; ml < 4; ml = ml + 1)
                for (bb = 0; bb < 8; bb = bb + 1)
                    mburst[4*bb + ml] = (bb < 8 - WB) ? d_first[8*ml + WB + bb]
                                                      : d_second[8*ml + bb - (8 - WB)];
`ifdef MODEL_NODM
            mburst = 32'd0;                     // a DM that never reaches the device
`endif
`ifdef MODEL_DMBEAT
            mburst = {mburst[27:0], mburst[31:28]};   // every lane's DM a beat late
`endif
`ifdef MODEL_DMLANE
            for (mb2 = 0; mb2 < 8; mb2 = mb2 + 1)     // lane l's DM on lane l + 1
                mburst[4*mb2 +: 4] = {mburst[4*mb2 +: 3], mburst[4*mb2 + 3]};
`endif
            for (mb2 = 0; mb2 < 32; mb2 = mb2 + 1) n_mbytes = n_mbytes + mburst[mb2];
            // a suppressed byte, beat b of lane l, keeps what the word held
            for (ml = 0; ml < 4; ml = ml + 1)
                for (bb = 0; bb < 8; bb = bb + 1)
                    if (mburst[4*bb + ml])
                        for (mp = 0; mp < 8; mp = mp + 1)
                            burst[64*ml + 8*mp + bb] = mem[wr_key[0]][64*ml + 8*mp + bb];
            mem[wr_key[0]] = burst;
`ifdef MODEL_FAULTS
            if (wr_key[0] == 100) begin
                n100 = n100 + 1;
                if (n100 == 2 && !fault_w) begin   // after its masked write
                    mem[100][8*9 + 3] = ~mem[100][8*9 + 3];
                    fault_w = 1'b1;
                end
            end
`endif
            for (i = 0; i < wr_n - 1; i = i + 1) begin
                wr_cyc[i] = wr_cyc[i + 1];
                wr_key[i] = wr_key[i + 1];
            end
            wr_n = wr_n - 1;
        end

        // the raw deserializer word for the coming rising edge
        dq_q = {8{32'hdeadbeef}};
        if (rd_n > 0 && cyc == rd_at[0]) begin
            dq_q = mem[rd_key[0]];
`ifdef MODEL_FAULTS
            if (rd_key[0] == 2000 && !fault_r) begin
                dq_q[64*2 + 8*1 + 5] = ~dq_q[64*2 + 8*1 + 5];
                fault_r = 1'b1;
            end
`endif
            for (i = 0; i < rd_n - 1; i = i + 1) begin
                rd_at[i] = rd_at[i + 1];
                rd_key[i] = rd_key[i + 1];
            end
            rd_n = rd_n - 1;
        end
    end

    // ---- the diagnostics, against the two injected faults ------------------
    task check_faults;
        integer q, e, found_w, found_r;
        reg [63:0] en;
        begin
            for (q = 0; q < 32; q = q + 1)
                if ((q == 9 || q == 17) != (dut.bist.pin_err[16*q +: 16] != 16'd0)) begin
                    $display("      DQ %0d counted %0d", q, dut.bist.pin_err[16*q +: 16]);
                    fail("a pin's count is not the injected faults'");
                end
            if (dut.bist.pin_err[16*17 +: 16] != 16'd1) fail("the read fault was not counted once");
            for (q = 0; q < 32; q = q + 1)
                if ((q == 8 + 3 || q == 16 + 5) != (dut.bist.beat_err[16*q +: 16] != 16'd0))
                    fail("a lane and beat's count is not the injected faults'");
            if (dut.bist.lane_err[0 +: 32] != 0 || dut.bist.lane_err[96 +: 32] != 0 ||
                dut.bist.lane_err[64 +: 32] != 1 || dut.bist.lane_err[32 +: 32] == 0)
                fail("the lanes' counts are not the injected faults'");
            found_w = 0; found_r = 0;
            for (e = 0; e < dut.bist.n_log; e = e + 1) begin
                en = dut.bist.elog[64*e +: 64];
                $display("      log %0d: word %0d lanes %b beats %b re-read issued %b checked %b right %b same %b",
                         e, en[24:0], en[28:25], en[36:29], en[37], en[38], en[39], en[40]);
                if (en[24:0] == 100 && en[28:25] == 4'b0010 && en[36:29] == 8'b0000_1000) begin
                    found_w = found_w + 1;
                    if (e == 0 && !(en[38] && !en[39] && en[40]))
                        fail("the written-wrong word's re-read was not as wrong as its read");
                end
                if (en[24:0] == 2000 && en[28:25] == 4'b0100 && en[36:29] == 8'b0010_0000) begin
                    found_r = found_r + 1;
                    if (!(en[38] && en[39] && !en[40]))
                        fail("the read-wrong word's re-read was not right");
                end
            end
            if (found_w == 0 || found_r != 1) fail("the faults were not both logged");
            if (errors == 0)
                $display("PASS  diagnostics: the injected pins, beats and lanes counted, a write fault re-read wrong and a read fault re-read right");
        end
    endtask

    // ---- the run ----------------------------------------------------------
    wire [15:0]  st_passes = ext_status[16 +: 16];
    wire [31:0]  st_written = ext_status[32 +: 32];
    wire [31:0]  st_checked = ext_status[64 +: 32];
    wire [127:0] st_lane = ext_status[96 +: 128];
    wire         st_err = ext_status[1];
    wire         st_badph = ext_status[4];
    initial begin
        repeat (20) @(posedge pclk);
        ctrl_own <= 1'b1;
        // two passes: 2 x (2^10 written, 2^10 + 2^10 read)
        wait (dut.bist.passes == 16'd2);
        repeat (40) @(posedge sys_clk);
        $display("      %0d WRITEs, %0d READs at the pads; status: %0d passes, %0d written, %0d checked",
                 n_writes, n_reads, st_passes, st_written, st_checked);
        if (st_passes < 2) fail("the status frame did not report two passes");
        if (dut.bist.n_checked < 2 * 2 * (1 << NL)) fail("fewer words checked than read");
`ifdef MODEL_FAULTS
        check_faults;
`else
        if (dut.bist.err_seen || st_err) begin
            $display("      lane errors %0d %0d %0d %0d, first at word %0d",
                     dut.bist.lane_err[0 +: 32], dut.bist.lane_err[32 +: 32],
                     dut.bist.lane_err[64 +: 32], dut.bist.lane_err[96 +: 32], dut.bist.err_addr);
            fail("a word came back other than written");
        end
`endif
        if (dut.phy.bad_phase || st_badph) fail("a READ or WRITE reached the DFI off phase 0");
        $display("      %0d bytes masked at the pads", n_mbytes);
        if (n_mbytes < (1 << NL) * 8) fail("too few bytes were masked for the masked pass to have run");
        $display("      %0d REFRESHes, the longest interval %0d memory clocks", n_refs, max_refi);
        if (n_refs < (4 * cyc) / 3120 - 1) fail("fewer REFRESHes than the run's length needs");
        if (max_refi > 3120) fail("a refresh interval over 7.8 us");
        if (!ctrl_accept || !ext_status[15]) fail("the controller did not accept the trained alignment");
`ifdef TB_CPU
        cpu_client;
`endif
`ifndef MODEL_FAULTS
        if (errors == 0)
            $display("PASS  ddr3_ctl through dfi_phy: %0d words written and %0d read back whole",
                     dut.bist.n_written, dut.bist.n_checked);
        else
`endif
        if (errors != 0)
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end

`ifdef TB_CPU
    // After the test, command 0x3C 0x50 hands the controller to the x_
    // port: the test must stop, x_rst fall and cpu_run rise; then the port
    // writes 256 words whole, overwrites them under random masks, with
    // some reads straight after a write to the same word, and reads them
    // all back, every byte checked against its own reference.
    localparam integer XW = 256;
    reg [255:0] x_ref [0:XW-1];
    reg [24:0]  x_q [0:1023];
    reg [255:0] x_e [0:1023];               // each read's expected word, as at its issue
    integer     x_qw = 0, x_qr = 0, x_reads = 0, x_bad = 0, xi, xk;
    always @(posedge pclk)
        if (x_rvalid) begin
            if (x_qr == x_qw) fail("the x_ port got read data it did not ask for");
            else begin
                if (x_rdata !== x_e[x_qr % 1024]) x_bad = x_bad + 1;
                x_qr = x_qr + 1;
                x_reads = x_reads + 1;
            end
        end
    // The driver works on the falling edge and learns whether the rising
    // edge took its request from x_took, which an always block samples as
    // the controller does; a task that reads x_ready just after the rising
    // edge can see the FIFO's new state instead.  Called at a falling edge.
    reg x_took = 1'b0;
    always @(posedge pclk) x_took <= x_valid && x_ready;
    task x_req(input we, input [24:0] a, input [255:0] d, input [31:0] m);
        begin
            x_valid = 1'b1; x_we = we; x_addr = a; x_wdata = d; x_wmask = m;
            @(negedge pclk);
            while (!x_took) @(negedge pclk);
            x_valid = 1'b0;
            if (we) begin
                for (xk = 0; xk < 32; xk = xk + 1)
                    if (!m[xk]) x_ref[a % XW][8*xk +: 8] = d[8*xk +: 8];
            end else begin
                x_q[x_qw % 1024] = a;
                x_e[x_qw % 1024] = x_ref[a % XW];
                x_qw = x_qw + 1;
            end
        end
    endtask
    function [255:0] rnd256(input integer dummy);
        rnd256 = {$random, $random, $random, $random, $random, $random, $random, $random};
    endfunction
    task cpu_client;
        reg [24:0] a;
        begin
            @(posedge sys_clk) ext_cmd <= 8'h50;
            @(posedge sys_clk) ext_tog <= ~ext_tog;
            wait (!x_rst);
            if (dut.bist.cmd_valid) fail("the test still requests after the hand-over");
            wait (cpu_run);
            repeat (40) @(posedge sys_clk);
            if (!ext_status[0]) fail("the status frame does not show the hand-over");
            @(negedge pclk);
            for (xi = 0; xi < XW; xi = xi + 1)
                x_req(1'b1, 25'h000100 + xi * 25'd13, rnd256(0), 32'd0);
            for (xi = 0; xi < 4 * XW; xi = xi + 1) begin
                a = 25'h000100 + ($random & 255) * 25'd13;
                x_req(1'b1, a, rnd256(0), $random);
                if (xi % 3 == 0) x_req(1'b0, a, 256'd0, 32'd0);
            end
            for (xi = 0; xi < XW; xi = xi + 1)
                x_req(1'b0, 25'h000100 + xi * 25'd13, 256'd0, 32'd0);
            wait (x_qr == x_qw);
            repeat (10) @(posedge pclk);
            if (x_bad != 0) fail("a word read on the x_ port differed from what it wrote");
            if (dut.bist.state != 0) fail("the test ran after the hand-over");
            $display("      the CPU port after the hand-over: %0d WRITEs, %0d READs, %0d wrong",
                     5 * XW, x_reads, x_bad);
        end
    endtask
`endif

    // progress, so a stall shows at once
    always begin
        #20000;
        $display("      t=%0t state %0d passes %0d written %0d checked %0d; pads %0d WRITE %0d READ; cmd valid %b ready %b",
                 $time, dut.bist.state, dut.bist.passes, dut.bist.n_written, dut.bist.n_checked,
                 n_writes, n_reads, dut.bist.cmd_valid, dut.cmd_ready);
`ifdef TB_CPU
        $display("      x: own %b rst %b run %b valid %b ready %b, %0d reads asked %0d back, item %0d",
                 dut.cpu_own, x_rst, cpu_run, x_valid, x_ready, x_qw, x_qr, xi);
`endif
    end

    initial begin
        #5000000;
        $display("FAIL  timeout: test state %0d, passes %0d", dut.bist.state, dut.bist.passes);
        $finish;
    end
endmodule

`default_nettype wire
