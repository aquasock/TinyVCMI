`default_nettype none

// TinyVCMI's DDR3 controller: LiteDRAM's control layer on the proven PHY.
//
//   LiteDRAM core  --DFI-->  dfi_adapter  --commands-->  ddr3_cmdmux  --> PHY
//        ^                        |                          ^
//        +---- read bursts <-- ddr3_derot <-- dq_q --------  |
//                                                           |
//   ddr3_sync (start-up) --+--> ddr3_init (power-up) -------+
//
// The power-up owns the command bus until it is done; the adapter owns it
// afterwards.  Read calibration is not in this image yet: `rot` and the read
// delay are inputs of this module so the boot training pass can drive them,
// and they are zero here, which means the raw frame is passed through.
module top (
    input  wire        sys_clk,

    inout  wire [31:0] ddr_dq,
    inout  wire        ddr_dqs0_p, ddr_dqs0_n,
    inout  wire        ddr_dqs1_p, ddr_dqs1_n,
    inout  wire        ddr_dqs2_p, ddr_dqs2_n,
    inout  wire        ddr_dqs3_p, ddr_dqs3_n,
    output wire [3:0]  ddr_dm,
    output wire        ddr_ck_p, ddr_ck_n, ddr_reset_n,
    output wire        ddr_bank_2, ddr_bank_1, ddr_bank_0,
    output wire        ddr_addr_15, ddr_addr_14, ddr_addr_13, ddr_addr_12,
    output wire        ddr_addr_11, ddr_addr_10, ddr_addr_9,  ddr_addr_8,
    output wire        ddr_addr_7,  ddr_addr_6,  ddr_addr_5,  ddr_addr_4,
    output wire        ddr_addr_3,  ddr_addr_2,  ddr_addr_1,  ddr_addr_0,
    output wire        ddr_odt, ddr_cke, ddr_we, ddr_cas, ddr_ras, ddr_cs
);
    // ---- clocks and PHY status ---------------------------------------
    wire pclk, mclk, pll_lock, dll_lock;
    wire [7:0]  step;
    wire [255:0] dq_q;
    wire [3:0]  rvalid, rburst, rflag, wflag, burst_tog;
    wire [11:0] rpoint, wpoint;



    // ---- start-up sequencer (sys_clk) --------------------------------
    reg [15:0] por_cnt = 16'hffff;
    wire       por_n = (por_cnt == 16'h0000);
    always @(posedge sys_clk)
        if (por_cnt != 16'h0000) por_cnt <= por_cnt - 16'd1;

    wire dll_rst, updncntl, hold, pll_en, sync_rst, sync_ready;
    ddr3_sync sync (
        .sys_clk(sys_clk), .por_n(por_n), .pll_ok(pll_lock), .lock_ok(dll_lock),
        .dll_rst(dll_rst), .updncntl(updncntl), .hold(hold),
        .pll_en(pll_en), .sync_rst(sync_rst), .ready(sync_ready));

    // ---- the PHY -----------------------------------------------------
    wire [2:0]  phy_rclksel = 3'd0;
    wire        phy_rloadn = 1'b1, phy_rdir = 1'b0, phy_wloadn = 1'b1;
    wire [3:0]  phy_rmove = 4'b0000;
    wire [31:0] phy_wstep = 32'd0;
    wire [31:0] phy_calib = 32'd0;
    wire [3:0]  phy_read_en;
    wire        wdata_pattern_mode;
    wire        phy_dqs_drive = 1'b0;
    wire        phy_cs_n, phy_ras_n, phy_cas_n, phy_we_n;
    wire [2:0]  phy_ba;
    wire [15:0] phy_addr;
    wire [255:0] phy_dq_wdata;

    ddr3_phy phy (
        .sys_clk(sys_clk),
        .ddr_dq(ddr_dq),
        .ddr_dqs0_p(ddr_dqs0_p), .ddr_dqs0_n(ddr_dqs0_n),
        .ddr_dqs1_p(ddr_dqs1_p), .ddr_dqs1_n(ddr_dqs1_n),
        .ddr_dqs2_p(ddr_dqs2_p), .ddr_dqs2_n(ddr_dqs2_n),
        .ddr_dqs3_p(ddr_dqs3_p), .ddr_dqs3_n(ddr_dqs3_n),
        .ddr_dm(ddr_dm),
        .ddr_ck_p(ddr_ck_p), .ddr_ck_n(ddr_ck_n), .ddr_reset_n(ddr_reset_n),
        .ddr_bank_2(ddr_bank_2), .ddr_bank_1(ddr_bank_1), .ddr_bank_0(ddr_bank_0),
        .ddr_addr_15(ddr_addr_15), .ddr_addr_14(ddr_addr_14), .ddr_addr_13(ddr_addr_13),
        .ddr_addr_12(ddr_addr_12), .ddr_addr_11(ddr_addr_11), .ddr_addr_10(ddr_addr_10),
        .ddr_addr_9(ddr_addr_9),  .ddr_addr_8(ddr_addr_8),  .ddr_addr_7(ddr_addr_7),
        .ddr_addr_6(ddr_addr_6),  .ddr_addr_5(ddr_addr_5),  .ddr_addr_4(ddr_addr_4),
        .ddr_addr_3(ddr_addr_3),  .ddr_addr_2(ddr_addr_2),  .ddr_addr_1(ddr_addr_1),
        .ddr_addr_0(ddr_addr_0),
        .ddr_odt(ddr_odt), .ddr_cke(ddr_cke), .ddr_we(ddr_we),
        .ddr_cas(ddr_cas), .ddr_ras(ddr_ras), .ddr_cs(ddr_cs),
        // controller side
        .pll_en(pll_en), .dll_rst(dll_rst), .updncntl(updncntl), .hold(hold),
        .phy_rst(sync_rst),
        .pll_lock(pll_lock), .dll_lock(dll_lock), .step(step),
        .pclk(pclk), .mclk(mclk),
        .rclksel(phy_rclksel), .rloadn(phy_rloadn), .rmove(phy_rmove),
        .rdir(phy_rdir), .read_en(phy_read_en), .calib(phy_calib),
        .wloadn(phy_wloadn), .wstep(phy_wstep),
        .rvalid(rvalid), .rburst(rburst), .rflag(rflag), .wflag(wflag),
        .rpoint(rpoint), .wpoint(wpoint),
        .dq_q(dq_q), .dq_pat(tr_dq_pat),
        .dq_wdata(phy_dq_wdata), .wdata_pattern_mode(wdata_pattern_mode),
        .dq_drive(tr_dq_drive), .dqs_drive(phy_dqs_drive), .odt(init_odt),
        .ddr_rst_n(init_reset_n),
        .cke(init_cke), .cs_n(phy_cs_n), .ras_n(phy_ras_n),
        .cas_n(phy_cas_n), .we_n(phy_we_n), .ba(phy_ba), .addr(phy_addr),
        .burst_tog(burst_tog));


    // ---- power-up, in the controller clock ---------------------------
    reg [1:0] ready_p = 2'b00;
    wire      phy_ready = ready_p[1];
    always @(posedge pclk)
        ready_p <= {ready_p[0], sync_ready};

    wire        init_cs_n, init_ras_n, init_cas_n, init_we_n;
    wire [2:0]  init_ba;
    wire [15:0] init_addr;
    wire        init_done, init_reset_n, init_cke, init_odt;

    ddr3_init init (
        .pclk(pclk), .phy_ready(phy_ready),
        .cs_n(init_cs_n), .ras_n(init_ras_n), .cas_n(init_cas_n),
        .we_n(init_we_n), .ba(init_ba), .addr(init_addr),
        .ddr_reset_n(init_reset_n), .cke(init_cke), .odt(init_odt),
        .init_done(init_done));

    // ---- read path: capture, frozen derotation ----------------------
    wire [255:0] rd_burst;
    wire [11:0]  rot;                 // frozen by ddr3_rotlatch
    ddr3_derot derot (.pclk(pclk), .dq_q(dq_q), .rot(rot), .data(rd_burst));

    // ---- boot training: pattern pass, aligner, frozen rotations ------
    wire        tr_cmd_valid, tr_dq_drive, tr_read_en, tr_stream;
    wire [2:0]  tr_cmd_op, tr_cmd_bank;
    wire [14:0] tr_cmd_addr;
    wire [7:0]  tr_dq_pat;
    wire        train_done, train_failed, tr_done;

    wire [3:0]  ra_trained;
    wire [11:0] ra_rot;

    ddr3_rotlatch latch (
        .pclk(pclk), .rearm(1'b0), .trained(ra_trained), .rot_in(ra_rot),
        .rot(rot), .done(train_done), .pattern_mode(wdata_pattern_mode));

    rd_align align (
        .pclk(pclk), .rst(!phy_ready), .stream(tr_stream), .dq_q(dq_q),
        .rvalid(4'b1111), .pat(tr_dq_pat), .arm(1'b0),
        .trained(ra_trained), .rot(ra_rot), .data(), .valid(), .ok(),
        .err(), .drift(), .pat_ok(), .phase(), .phase_ok(), .relocks());

    ddr3_train trainer (
        .pclk(pclk), .rst(!phy_ready), .init_done(init_done),
        .trained(ra_trained),
        .cmd_valid(tr_cmd_valid), .cmd_op(tr_cmd_op), .cmd_bank(tr_cmd_bank),
        .cmd_addr(tr_cmd_addr), .dq_pat(tr_dq_pat), .dq_drive(tr_dq_drive),
        .read_en(tr_read_en), .stream(tr_stream), .done(tr_done),
        .failed(train_failed));

    // ---- DFI adapter -------------------------------------------------
    wire [255:0] wr_burst;
    wire         rd_underflow, cmd_collision;
    wire [15:0]  cmd_count, rd_count;
    wire         phy_cmd_valid, phy_wr_valid;
    wire [2:0]   phy_cmd_op;
    wire [2:0]   phy_cmd_bank;
    wire [14:0]  phy_cmd_addr;

    dfi_adapter #(.RD_LATENCY(7)) adapter (
        .pclk(pclk), .rst(!phy_ready),
        .dfi_cs_n({dfi_p3_cs_n, dfi_p2_cs_n, dfi_p1_cs_n, dfi_p0_cs_n}),
        .dfi_ras_n({dfi_p3_ras_n, dfi_p2_ras_n, dfi_p1_ras_n, dfi_p0_ras_n}),
        .dfi_cas_n({dfi_p3_cas_n, dfi_p2_cas_n, dfi_p1_cas_n, dfi_p0_cas_n}),
        .dfi_we_n({dfi_p3_we_n, dfi_p2_we_n, dfi_p1_we_n, dfi_p0_we_n}),
        .dfi_cke({dfi_p3_cke, dfi_p2_cke, dfi_p1_cke, dfi_p0_cke}),
        .dfi_odt({dfi_p3_odt, dfi_p2_odt, dfi_p1_odt, dfi_p0_odt}),
        .dfi_address({dfi_p3_address, dfi_p2_address, dfi_p1_address, dfi_p0_address}),
        .dfi_bank({dfi_p3_bank, dfi_p2_bank, dfi_p1_bank, dfi_p0_bank}),
        .dfi_wrdata({dfi_p3_wrdata, dfi_p2_wrdata, dfi_p1_wrdata, dfi_p0_wrdata}),
        .dfi_wrdata_en({dfi_p3_wrdata_en, dfi_p2_wrdata_en, dfi_p1_wrdata_en, dfi_p0_wrdata_en}),
        .dfi_rddata_en({dfi_p3_rddata_en, dfi_p2_rddata_en, dfi_p1_rddata_en, dfi_p0_rddata_en}),
        .dfi_rddata({dfi_p3_rddata, dfi_p2_rddata, dfi_p1_rddata, dfi_p0_rddata}),
        .dfi_rddata_valid({dfi_p3_rddata_valid, dfi_p2_rddata_valid,
                           dfi_p1_rddata_valid, dfi_p0_rddata_valid}),
        .phy_cmd_valid(phy_cmd_valid), .phy_cmd_op(phy_cmd_op),
        .phy_cmd_bank(phy_cmd_bank), .phy_cmd_addr(phy_cmd_addr),
        .phy_cmd_taken(1'b1),
        .phy_wr_valid(phy_wr_valid), .phy_wr_data(wr_burst),
        .phy_rd_data(rd_burst), .phy_rd_valid(1'b1),
        .stat_cmd_collision(cmd_collision), .stat_rd_underflow(rd_underflow),
        .stat_cmd_count(cmd_count), .stat_rd_count(rd_count));

    assign phy_dq_wdata = wr_burst;
    // The DQS gate: the trainer holds it open while it trains, and afterwards
    // it opens whenever the controller expects read data.
    assign phy_read_en = train_done
        ? {4{|{dfi_p3_rddata_en, dfi_p2_rddata_en,
                dfi_p1_rddata_en, dfi_p0_rddata_en}}}
        : {4{tr_read_en}};

    // ---- command bus arbitration -------------------------------------
    ddr3_cmdmux cmdmux (
        .pclk(pclk), .init_done(init_done), .train_done(train_done),
        .t_valid(tr_cmd_valid), .t_op(tr_cmd_op),
        .t_ba(tr_cmd_bank), .t_addr({1'b0, tr_cmd_addr}),
        .i_cs_n(init_cs_n), .i_ras_n(init_ras_n), .i_cas_n(init_cas_n),
        .i_we_n(init_we_n), .i_ba(init_ba), .i_addr(init_addr),
        .a_valid(phy_cmd_valid), .a_op(phy_cmd_op),
        .a_ba(phy_cmd_bank), .a_addr({1'b0, phy_cmd_addr}),
        .cs_n(phy_cs_n), .ras_n(phy_ras_n), .cas_n(phy_cas_n),
        .we_n(phy_we_n), .ba(phy_ba), .addr(phy_addr));

    // ---- LiteDRAM's control layer ------------------------------------
    wire dfi_p0_cs_n, dfi_p0_ras_n, dfi_p0_cas_n, dfi_p0_we_n;
    wire dfi_p1_cs_n, dfi_p1_ras_n, dfi_p1_cas_n, dfi_p1_we_n;
    wire dfi_p2_cs_n, dfi_p2_ras_n, dfi_p2_cas_n, dfi_p2_we_n;
    wire dfi_p3_cs_n, dfi_p3_ras_n, dfi_p3_cas_n, dfi_p3_we_n;
    wire dfi_p0_cke, dfi_p1_cke, dfi_p2_cke, dfi_p3_cke;
    wire dfi_p0_odt, dfi_p1_odt, dfi_p2_odt, dfi_p3_odt;
    wire [14:0] dfi_p0_address, dfi_p1_address, dfi_p2_address, dfi_p3_address;
    wire [2:0]  dfi_p0_bank, dfi_p1_bank, dfi_p2_bank, dfi_p3_bank;
    wire [63:0] dfi_p0_wrdata, dfi_p1_wrdata, dfi_p2_wrdata, dfi_p3_wrdata;
    wire dfi_p0_wrdata_en, dfi_p1_wrdata_en, dfi_p2_wrdata_en, dfi_p3_wrdata_en;
    wire [7:0]  dfi_p0_wrdata_mask, dfi_p1_wrdata_mask;
    wire [7:0]  dfi_p2_wrdata_mask, dfi_p3_wrdata_mask;
    wire dfi_p0_rddata_en, dfi_p1_rddata_en, dfi_p2_rddata_en, dfi_p3_rddata_en;
    wire [63:0] dfi_p0_rddata, dfi_p1_rddata, dfi_p2_rddata, dfi_p3_rddata;
    wire dfi_p0_rddata_valid, dfi_p1_rddata_valid;
    wire dfi_p2_rddata_valid, dfi_p3_rddata_valid;



    litedram_core ddr (
        .sys_clk(pclk), .sys_rst(!phy_ready),
        .sys4x_clk(mclk), .sys4x_rst(!phy_ready),
        .dfi_p0_cs_n(dfi_p0_cs_n), .dfi_p0_ras_n(dfi_p0_ras_n),
        .dfi_p0_cas_n(dfi_p0_cas_n), .dfi_p0_we_n(dfi_p0_we_n),
        .dfi_p0_cke(dfi_p0_cke), .dfi_p0_odt(dfi_p0_odt),
        .dfi_p0_address(dfi_p0_address), .dfi_p0_bank(dfi_p0_bank),
        .dfi_p0_wrdata(dfi_p0_wrdata), .dfi_p0_wrdata_en(dfi_p0_wrdata_en),
        .dfi_p0_wrdata_mask(dfi_p0_wrdata_mask),
        .dfi_p0_rddata_en(dfi_p0_rddata_en),
        .dfi_p0_rddata(dfi_p0_rddata), .dfi_p0_rddata_valid(dfi_p0_rddata_valid),
        .dfi_p1_cs_n(dfi_p1_cs_n), .dfi_p1_ras_n(dfi_p1_ras_n),
        .dfi_p1_cas_n(dfi_p1_cas_n), .dfi_p1_we_n(dfi_p1_we_n),
        .dfi_p1_cke(dfi_p1_cke), .dfi_p1_odt(dfi_p1_odt),
        .dfi_p1_address(dfi_p1_address), .dfi_p1_bank(dfi_p1_bank),
        .dfi_p1_wrdata(dfi_p1_wrdata), .dfi_p1_wrdata_en(dfi_p1_wrdata_en),
        .dfi_p1_wrdata_mask(dfi_p1_wrdata_mask),
        .dfi_p1_rddata_en(dfi_p1_rddata_en),
        .dfi_p1_rddata(dfi_p1_rddata), .dfi_p1_rddata_valid(dfi_p1_rddata_valid),
        .dfi_p2_cs_n(dfi_p2_cs_n), .dfi_p2_ras_n(dfi_p2_ras_n),
        .dfi_p2_cas_n(dfi_p2_cas_n), .dfi_p2_we_n(dfi_p2_we_n),
        .dfi_p2_cke(dfi_p2_cke), .dfi_p2_odt(dfi_p2_odt),
        .dfi_p2_address(dfi_p2_address), .dfi_p2_bank(dfi_p2_bank),
        .dfi_p2_wrdata(dfi_p2_wrdata), .dfi_p2_wrdata_en(dfi_p2_wrdata_en),
        .dfi_p2_wrdata_mask(dfi_p2_wrdata_mask),
        .dfi_p2_rddata_en(dfi_p2_rddata_en),
        .dfi_p2_rddata(dfi_p2_rddata), .dfi_p2_rddata_valid(dfi_p2_rddata_valid),
        .dfi_p3_cs_n(dfi_p3_cs_n), .dfi_p3_ras_n(dfi_p3_ras_n),
        .dfi_p3_cas_n(dfi_p3_cas_n), .dfi_p3_we_n(dfi_p3_we_n),
        .dfi_p3_cke(dfi_p3_cke), .dfi_p3_odt(dfi_p3_odt),
        .dfi_p3_address(dfi_p3_address), .dfi_p3_bank(dfi_p3_bank),
        .dfi_p3_wrdata(dfi_p3_wrdata), .dfi_p3_wrdata_en(dfi_p3_wrdata_en),
        .dfi_p3_wrdata_mask(dfi_p3_wrdata_mask),
        .dfi_p3_rddata_en(dfi_p3_rddata_en),
        .dfi_p3_rddata(dfi_p3_rddata), .dfi_p3_rddata_valid(dfi_p3_rddata_valid),
        // the user port is idle until the AE350 bridge drives it
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_payload_addr(cmd_payload_addr), .cmd_payload_we(cmd_payload_we),
        .cmd_last(cmd_last),
        .wdata_valid(wdata_valid), .wdata_ready(wdata_ready),
        .wdata_payload_data(wdata_payload_data),
        .rdata_valid(rdata_valid), .rdata_ready(rdata_ready),
        .rdata_payload_data(rdata_payload_data));

    // The generated port's direction is fixed by how it was created: the core
    // drives valid and the payload, so those are observed and the handshake
    // inputs are tied idle until the AE350 bridge takes this over.
    wire        cmd_valid, cmd_ready;
    wire        cmd_last = 1'b0, cmd_payload_we = 1'b0;
    wire [24:0] cmd_payload_addr = 25'd0;
    wire        wdata_valid = 1'b0, wdata_ready;
    wire [255:0] wdata_payload_data = 256'd0;
    wire        rdata_valid, rdata_ready;
    wire [255:0] rdata_payload_data;

endmodule

`default_nettype wire
