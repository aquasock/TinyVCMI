`default_nettype none

// The controller image's fabric between wr_core and the pads.
//
// Until wr_core hands the bus over (ctrl_own, mode 6, after its training),
// the pads carry wr_core's own command in the first memory clock of each
// PCLK and a deselect in the other three, its pattern on even DQ and the
// inverse on odd DQ, and its drive enables and ODT -- what the write image's
// top.v wires directly.  From then on they carry dfi_phy's, which serves the
// controller ddr3_ctl, whose request port the memory test ddr3_bist drives.
// The controller, dfi_phy and the test are held in reset while the bus is
// wr_core's, so the controller starts from all banks precharged, as wr_core
// leaves them.
//
// dfi_phy's write alignment is built in (WD, WB); ctrl_accept tells wr_core
// whether the training found it, and wr_core hands the bus over only then.
//
// The link reaches this through wr_core: command 0x3C v delivers v here, and
// frame 0x3D returns 64 bytes of status.
//
//   0x3C 0x10 + r   read offset r (0..3): a READ's burst 6 + r PCLK after it
//                   sat in the command registers; 1, the board's 7, at reset
//   0x3C 0x20 / 21  the memory test stopped / running (running at reset)
//   0x3C 0x30       the test's counts and first error cleared
//
// Frame 0x3D, little-endian, byte 0 in the low bits:
//   0      {ctrl_own, trained, test running, READ/WRITE off phase 0,
//           read offset[1:0], an error seen, 0}
//   1      {the training found dfi_phy's write alignment, 0, 0, 0, the test's
//          state: 0 idle, 1/2 writing, 3/4 reading in order, 5/6 at random}
//   2-3    passes completed
//   4-7    words written       8-11   words read and checked
//   12+4l  words whose lane l differed
//   28-31  the first failing word's address (25 bits)
//   32-63  that word's XOR with what was written, beat b, DQ q at 32b + q
module ctrl_glue #(
    parameter integer WD = 1,           // dfi_phy's built-in write alignment
    parameter integer WB = 2,
    parameter integer N_LOG2 = 25,      // the test's words per pass: all 1 GiB
    parameter integer R_LOG2 = 20,
    parameter integer SNAP_LOG2 = 10    // PCLK between status snapshots
) (
    input  wire         sys_clk,
    input  wire         pclk,
    input  wire [255:0] dq_q,

    // wr_core's bus, as the write image drives the pads with it
    input  wire         wc_cs_n, wc_ras_n, wc_cas_n, wc_we_n,
    input  wire [2:0]   wc_ba,
    input  wire [15:0]  wc_addr,
    input  wire         wc_odt,
    input  wire [7:0]   wc_dq_pat,
    input  wire         wc_dq_drive, wc_dqs_drive,

    input  wire         ctrl_own,       // PCLK
    input  wire         ctrl_trained,   // sys_clk
    input  wire [6:0]   ctrl_walign,    // PCLK, still once trained
    input  wire [11:0]  ctrl_rot,       // sys_clk, still once trained
    input  wire [7:0]   ext_cmd,        // sys_clk
    input  wire         ext_tog,

    output wire [3:0]   p_cs_n, p_ras_n, p_cas_n, p_we_n,
    output wire [11:0]  p_ba,
    output wire [63:0]  p_addr,
    output wire         p_odt, p_dq_drive, p_dqs_drive,
    output wire [255:0] wdq,
    output wire         ctrl_rd,
    output reg          ctrl_accept = 1'b0, // sys_clk: the training found dfi_phy's alignment
    output reg  [511:0] ext_status = 512'd0
);
    // ---- the write alignment: dfi_phy's is built in -------------------
    localparam [2:0] WD3 = WD, WB3 = WB;
    reg walign_ok = 1'b0;
    reg [1:0] accept_s = 2'b00;
    always @(posedge pclk)
        walign_ok <= (ctrl_walign == {WD3, 1'b0, WB3});
    always @(posedge sys_clk) begin
        accept_s <= {accept_s[0], walign_ok};
        ctrl_accept <= accept_s[1];
    end

    // ---- the link's commands, into PCLK ---------------------------------
    reg [2:0] tog_p = 3'd0;
    reg [1:0] rd_off = 2'd1;
    reg       bist_en = 1'b1, bist_clr = 1'b0;
    reg [7:0] cmd_p = 8'd0;
    always @(posedge pclk) begin
        tog_p <= {tog_p[1:0], ext_tog};
        cmd_p <= ext_cmd;               // still for many PCLK when tog_p moves
        bist_clr <= 1'b0;
        if (tog_p[2] ^ tog_p[1])
            case (cmd_p[7:4])
                4'h1: rd_off <= cmd_p[1:0];
                4'h2: bist_en <= cmd_p[0];
                4'h3: bist_clr <= 1'b1;
                default: ;
            endcase
    end
    reg ld_rst = 1'b1;
    always @(posedge pclk)
        ld_rst <= !ctrl_own;

    // ---- the controller ---------------------------------------------------
    wire [3:0]   dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n, dfi_wrdata_en, dfi_rddata_en;
    wire [59:0]  dfi_address;
    wire [11:0]  dfi_bank;
    wire [255:0] dfi_wrdata, dfi_rddata;
    wire [3:0]   dfi_rddata_valid;
    wire         cmd_valid, cmd_ready, cmd_we, rdata_valid;
    wire [24:0]  cmd_addr;
    wire [255:0] cmd_wdata, rdata_data;
    wire [31:0]  n_act, n_ref;
    ddr3_ctl ctl (
        .pclk(pclk), .rst(ld_rst),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_we(cmd_we), .cmd_addr(cmd_addr),
        .cmd_wdata(cmd_wdata), .rdata_valid(rdata_valid), .rdata(rdata_data),
        .dfi_cs_n(dfi_cs_n), .dfi_ras_n(dfi_ras_n), .dfi_cas_n(dfi_cas_n), .dfi_we_n(dfi_we_n),
        .dfi_address(dfi_address), .dfi_bank(dfi_bank), .dfi_wrdata(dfi_wrdata),
        .dfi_wrdata_en(dfi_wrdata_en), .dfi_rddata_en(dfi_rddata_en),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rddata_valid),
        .n_act(n_act), .n_ref(n_ref));

    // ---- the PHY's DFI side ---------------------------------------------
    wire [3:0]   c_cs_n, c_ras_n, c_cas_n, c_we_n;
    wire [11:0]  c_ba;
    wire [63:0]  c_addr;
    wire         c_odt, c_dq_drive, c_dqs_drive, c_rd_load, bad_phase;
    wire [255:0] c_wdq;
    wire [31:0]  n_wr, n_rd;
    dfi_phy #(.WD(WD), .WB(WB)) phy (
        .pclk(pclk), .rst(ld_rst),
        .dfi_cs_n(dfi_cs_n), .dfi_ras_n(dfi_ras_n), .dfi_cas_n(dfi_cas_n), .dfi_we_n(dfi_we_n),
        .dfi_address(dfi_address), .dfi_bank(dfi_bank), .dfi_wrdata(dfi_wrdata),
        .dfi_wrdata_en(dfi_wrdata_en), .dfi_rddata_en(dfi_rddata_en),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rddata_valid),
        .rot(ctrl_rot), .rd_off(rd_off), .dq_q(dq_q),
        .p_cs_n(c_cs_n), .p_ras_n(c_ras_n), .p_cas_n(c_cas_n), .p_we_n(c_we_n),
        .p_ba(c_ba), .p_addr(c_addr), .p_odt(c_odt), .p_dq_drive(c_dq_drive),
        .p_dqs_drive(c_dqs_drive), .wdq(c_wdq), .rd_load(c_rd_load),
        .bad_phase(bad_phase), .n_wr(n_wr), .n_rd(n_rd));
    assign ctrl_rd = c_rd_load;

    // ---- the memory test ------------------------------------------------
    wire [3:0]   b_state;
    wire [15:0]  b_passes;
    wire [31:0]  b_written, b_checked;
    wire [127:0] b_lane_err;
    wire         b_err_seen;
    wire [24:0]  b_err_addr;
    wire [255:0] b_err_diff;
    ddr3_bist #(.AW(25), .N_LOG2(N_LOG2), .R_LOG2(R_LOG2)) bist (
        .pclk(pclk), .rst(ld_rst || !bist_en), .clr(bist_clr),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_we(cmd_we), .cmd_addr(cmd_addr),
        .cmd_wdata(cmd_wdata), .rdata_valid(rdata_valid), .rdata_data(rdata_data),
        .state(b_state), .passes(b_passes), .n_written(b_written), .n_checked(b_checked),
        .lane_err(b_lane_err), .err_seen(b_err_seen), .err_addr(b_err_addr),
        .err_diff(b_err_diff));

    // ---- the pads -------------------------------------------------------
    wire [255:0] wc_wdq;
    genvar gi;
    generate
        for (gi = 0; gi < 32; gi = gi + 1) begin : g_pat
            assign wc_wdq[8*gi +: 8] = (gi % 2 == 1) ? ~wc_dq_pat : wc_dq_pat;
        end
    endgenerate
    assign p_cs_n  = ctrl_own ? c_cs_n  : {3'b111, wc_cs_n};
    assign p_ras_n = ctrl_own ? c_ras_n : {3'b111, wc_ras_n};
    assign p_cas_n = ctrl_own ? c_cas_n : {3'b111, wc_cas_n};
    assign p_we_n  = ctrl_own ? c_we_n  : {3'b111, wc_we_n};
    assign p_ba    = ctrl_own ? c_ba    : {4{wc_ba}};
    assign p_addr  = ctrl_own ? c_addr  : {4{wc_addr}};
    assign p_odt   = ctrl_own ? c_odt   : wc_odt;
    assign p_dq_drive  = ctrl_own ? c_dq_drive  : wc_dq_drive;
    assign p_dqs_drive = ctrl_own ? c_dqs_drive : wc_dqs_drive;
    assign wdq     = ctrl_own ? c_wdq   : wc_wdq;

    // ---- status: a snapshot every 2^SNAP_LOG2 PCLK, copied whole --------
    // The snapshot holds still for 2^SNAP_LOG2 PCLK after its toggle moves,
    // far longer than the toggle takes to cross, so the copy is coherent.
    reg [2:0]   trained_p = 3'd0;
    always @(posedge pclk)
        trained_p <= {trained_p[1:0], ctrl_trained};
    reg [SNAP_LOG2-1:0] snap_t = {SNAP_LOG2{1'b0}};
    reg [511:0] snap = 512'd0;
    reg         snap_tog = 1'b0;
    always @(posedge pclk) begin
        snap_t <= snap_t + 1'b1;
        if (snap_t == {SNAP_LOG2{1'b0}}) begin
            snap <= {b_err_diff, 7'd0, b_err_addr, b_lane_err, b_checked, b_written, b_passes,
                     walign_ok, 3'd0, b_state,
                     ctrl_own, trained_p[2], bist_en && !ld_rst, bad_phase, rd_off,
                     b_err_seen, 1'b0};
            snap_tog <= ~snap_tog;
        end
    end
    reg [2:0] snap_s = 3'd0;
    always @(posedge sys_clk) begin
        snap_s <= {snap_s[1:0], snap_tog};
        if (snap_s[2] ^ snap_s[1])
            ext_status <= snap;
    end
endmodule

`default_nettype wire
