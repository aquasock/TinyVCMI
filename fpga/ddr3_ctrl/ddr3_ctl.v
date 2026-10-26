`default_nettype none

// The DDR3 controller: requests in, the DFI that dfi_phy serves out.
//
// It replaces LiteDRAM's, whose command logic reached 77 MHz in the open
// flow and 90 MHz in Gowin's against the 100 MHz the PHY's 1:4 DFI needs.
// This one serves requests strictly in order, one command per PCLK, every
// command in memory clock 0 (DFI phase 0, the others deselected), with each
// bank's row left open until a request needs another row or a refresh is
// due.  Read data therefore returns in request order.
//
// Requests are 256-bit words, one BL8 burst of the x32 array: address
// {row[14:0], bank[2:0], column burst[6:0]}, so consecutive words run along
// a row and then on to the next bank.  A write carries its data with it.
//
// Timing, in PCLK (10 ns, four memory clocks of 2.5 ns), each the DDR3-800
// figure for the array's H5TQ4G63 devices rounded up to whole PCLK:
//
//   tRCD 13.75 ns, tRP 13.75 ns           T_RCD = T_RP = 2
//   tRAS 37.5 ns, tRC 52.5 ns             T_RAS = 4, T_RC = 6
//   tRRD 4 CK, tFAW 40 ns                 T_RRD = 1, T_FAW = 4 (ACTIVATEs per window: 4)
//   WRITE to PRECHARGE: CWL 5 + BL8 4 CK + tWR 15 ns = 37.5 ns    T_WR = 4
//   READ to PRECHARGE: tRTP 4 CK           T_RTP = 1
//   WRITE to READ: CWL + 4 CK + tWTR 4 CK = 32.5 ns               T_WTR = 4
//   READ to WRITE: the read burst, CL 6 + 4 CK + its postamble, off the bus
//     before dfi_phy drives the write's, a PCLK ahead of its data      T_RTW = 4
//   tRFC 260 ns (4 Gb), tREFI 7.8 us       T_RFC = 28, T_REFI = 700 (7 us)
//
// A refresh due stops new commands, precharges every open bank once its
// timers allow, waits tRP, refreshes and waits tRFC.
//
// For 100 MHz the decision reads only registers: a request passes from the
// FIFO to `nxt` to `cur`, and whether its bank is open and on its row is
// registered as it enters `cur` and refreshed each PCLK.  Those flags lag a
// PCLK behind an ACTIVATE or PRECHARGE of the request's own bank, which costs
// nothing: tRCD and tRP forbid the next command to that bank in that PCLK
// anyway, and a PRECHARGE holds the bank's PRECHARGE timer for one PCLK so a
// stale flag cannot repeat it.  Gowin's build of a single-stage decision put
// 15.6 ns, twelve levels, from the FIFO through the row compare.  The DFI's other
// signals -- CKE, ODT, the masks -- are not driven here: wr_core holds CKE
// and dfi_phy makes ODT from the WRITEs.
module ddr3_ctl #(
    parameter integer T_RCD = 2,
    parameter integer T_RP = 2,
    parameter integer T_RAS = 4,
    parameter integer T_RC = 6,
    parameter integer T_RRD = 1,
    parameter integer T_FAW = 4,
    parameter integer T_WR = 4,
    parameter integer T_RTP = 1,
    parameter integer T_WTR = 4,
    parameter integer T_RTW = 4,
    parameter integer T_RFC = 28,
    parameter integer T_REFI = 700
) (
    input  wire          pclk,
    input  wire          rst,

    // requests
    input  wire          cmd_valid,
    output wire          cmd_ready,
    input  wire          cmd_we,
    input  wire [24:0]   cmd_addr,
    input  wire [255:0]  cmd_wdata,     // beat b, DQ q at 32b + q
    output reg           rdata_valid = 1'b0,
    output reg  [255:0]  rdata = 256'd0,

    // the DFI, phase p in bit p or at p * width; only phase 0 commands
    output wire [3:0]    dfi_cs_n,
    output wire [3:0]    dfi_ras_n,
    output wire [3:0]    dfi_cas_n,
    output wire [3:0]    dfi_we_n,
    output wire [59:0]   dfi_address,
    output wire [11:0]   dfi_bank,
    output reg  [255:0]  dfi_wrdata = 256'd0,
    output wire [3:0]    dfi_wrdata_en,
    output wire [3:0]    dfi_rddata_en,
    input  wire [255:0]  dfi_rddata,
    input  wire [3:0]    dfi_rddata_valid,

    output reg  [31:0]   n_act = 32'd0,
    output reg  [31:0]   n_ref = 32'd0
);
    // ---- the request FIFO, four deep, then nxt and cur ---------------------
    reg [281:0] fq [0:3];               // {we, addr, data}
    reg [1:0]   fq_w = 2'd0, fq_r = 2'd0;
    reg [2:0]   fq_n = 3'd0;
    wire [281:0] head = fq[fq_r];
    wire         h_v = (fq_n != 3'd0);
    assign cmd_ready = (fq_n < 3'd3);   // one slot spare: the ready is registered
    reg          nxt_v = 1'b0, cur_v = 1'b0;
    reg [281:0]  nxt = 282'd0, cur = 282'd0;
    wire         c_we = cur[281];
    wire [14:0]  c_row = cur[280:266];
    wire [2:0]   h_bank = cur[265:263];
    wire [6:0]   c_col = cur[262:256];
    wire [255:0] h_data = cur[255:0];
    wire [14:0]  n_row = nxt[280:266];
    wire [2:0]   n_bank = nxt[265:263];
    reg          hit = 1'b0, c_open = 1'b0;   // cur's bank on cur's row / open

    // ---- the banks and the timers -----------------------------------------
    reg [7:0]  b_open = 8'd0;
    reg [14:0] b_row [0:7];
    reg [2:0]  c_act [0:7];             // PCLK until an ACTIVATE may go to the bank
    reg [1:0]  c_cas [0:7];             // until a READ or WRITE may
    reg [2:0]  c_pre [0:7];             // until a PRECHARGE may
    reg [2:0]  c_rrd = 3'd0, c_wtr = 3'd0, c_rtw = 3'd0;
    reg [2:0]  faw [0:3];               // PCLK since each of the last four ACTIVATEs
    integer i, ib, iw;
    initial begin
        for (ib = 0; ib < 8; ib = ib + 1) begin
            b_row[ib] = 15'd0; c_act[ib] = 3'd0; c_cas[ib] = 2'd0; c_pre[ib] = 3'd0;
        end
        for (iw = 0; iw < 4; iw = iw + 1) faw[iw] = 3'd7;
    end

    // ---- refresh ----------------------------------------------------------
    localparam [2:0] F_RUN = 3'd0, F_PRE = 3'd1, F_REF = 3'd2, F_WAIT = 3'd3;
    reg [2:0]  f_state = F_RUN;
    reg [9:0]  refi = 10'd0;
    reg        ref_due = 1'b0;
    reg [4:0]  f_wait = 5'd0;
    reg        pre_ok_all, act_ok_all;
    always @(*) begin
        pre_ok_all = 1'b1;
        act_ok_all = 1'b1;
        for (i = 0; i < 8; i = i + 1) begin
            if (b_open[i] && c_pre[i] != 3'd0) pre_ok_all = 1'b0;
            if (c_act[i] != 3'd0) act_ok_all = 1'b0;
        end
    end

    // ---- the command this PCLK --------------------------------------------
    localparam [3:0] C_NOP = 4'b1111, C_ACT = 4'b0011, C_RD = 4'b0101, C_WR = 4'b0100,
                     C_PRE = 4'b0010, C_REF = 4'b0001;
    reg  [3:0]  go_c;                   // {cs_n, ras_n, cas_n, we_n}
    reg  [2:0]  go_b;
    reg  [14:0] go_a;
    reg         go_pop;
    always @(*) begin
        go_c = C_NOP;
        go_b = h_bank;
        go_a = 15'd0;
        go_pop = 1'b0;
        case (f_state)
            F_PRE: if (pre_ok_all) begin
                if (b_open != 8'd0) begin
                    go_c = C_PRE;
                    go_a = 15'h0400;            // A10: all banks
                end
            end
            F_REF: if (act_ok_all && b_open == 8'd0)
                go_c = C_REF;
            F_WAIT: ;
            default: if (cur_v) begin
                if (hit) begin
                    if (c_cas[h_bank] == 2'd0 && (c_we ? c_rtw == 3'd0 : c_wtr == 3'd0)) begin
                        go_c = c_we ? C_WR : C_RD;
                        go_a = {5'd0, c_col, 3'b000};   // BL8, A10 low: no auto-precharge
                        go_pop = 1'b1;
                    end
                end else if (c_open) begin
                    if (c_pre[h_bank] == 3'd0)
                        go_c = C_PRE;                    // A10 low: this bank
                end else if (c_act[h_bank] == 3'd0 && c_rrd == 3'd0 && faw[3] >= T_FAW) begin
                    go_c = C_ACT;
                    go_a = c_row;
                end
            end
        endcase
    end

    // ---- the DFI's registers ----------------------------------------------
    reg [3:0]  q_c = C_NOP;
    reg [2:0]  q_b = 3'd0;
    reg [14:0] q_a = 15'd0;
    assign dfi_cs_n  = {3'b111, q_c[3]};
    assign dfi_ras_n = {3'b111, q_c[2]};
    assign dfi_cas_n = {3'b111, q_c[1]};
    assign dfi_we_n  = {3'b111, q_c[0]};
    assign dfi_address = {45'd0, q_a};
    assign dfi_bank = {9'd0, q_b};
    assign dfi_wrdata_en = {3'b000, q_c == C_WR};
    assign dfi_rddata_en = {3'b000, q_c == C_RD};
    reg [255:0] wr_hold = 256'd0;

    function [2:0] max3(input [2:0] a, input integer b);
        max3 = (a > b) ? a : b;
    endfunction
    function [2:0] age(input [2:0] a);  // a PCLK older, saturating
        age = (a == 3'd7) ? a : a + 3'd1;
    endfunction

    integer k;
    always @(posedge pclk) begin
        // the command, and the write's data on the DFI a PCLK after it
        q_c <= rst ? C_NOP : go_c;
        q_b <= go_b;
        q_a <= go_a;
        wr_hold <= h_data;
        dfi_wrdata <= wr_hold;
        rdata_valid <= !rst && dfi_rddata_valid[0];
        rdata <= dfi_rddata;

        // the FIFO, nxt and cur: cur moves on when served, nxt follows, the
        // FIFO refills nxt; cur's flags are made from the banks' registers
        if (cmd_valid && cmd_ready) begin
            fq[fq_w] <= {cmd_we, cmd_addr, cmd_wdata};
            fq_w <= fq_w + 2'd1;
        end
        if (nxt_v && (!cur_v || go_pop)) begin
            cur <= nxt;
            cur_v <= 1'b1;
            hit <= b_open[n_bank] && (b_row[n_bank] == n_row);
            c_open <= b_open[n_bank];
        end else begin
            if (go_pop)
                cur_v <= 1'b0;
            hit <= b_open[h_bank] && (b_row[h_bank] == c_row);
            c_open <= b_open[h_bank];
        end
        if (h_v && (!nxt_v || !cur_v || go_pop)) begin
            nxt <= head;
            nxt_v <= 1'b1;
            fq_r <= fq_r + 2'd1;
        end else if (nxt_v && (!cur_v || go_pop))
            nxt_v <= 1'b0;
        fq_n <= fq_n + ((cmd_valid && cmd_ready) ? 3'd1 : 3'd0) -
                ((h_v && (!nxt_v || !cur_v || go_pop)) ? 3'd1 : 3'd0);

        // the timers count down
        for (k = 0; k < 8; k = k + 1) begin
            if (c_act[k] != 3'd0) c_act[k] <= c_act[k] - 3'd1;
            if (c_cas[k] != 2'd0) c_cas[k] <= c_cas[k] - 2'd1;
            if (c_pre[k] != 3'd0) c_pre[k] <= c_pre[k] - 3'd1;
        end
        if (c_rrd != 3'd0) c_rrd <= c_rrd - 3'd1;
        if (c_wtr != 3'd0) c_wtr <= c_wtr - 3'd1;
        if (c_rtw != 3'd0) c_rtw <= c_rtw - 3'd1;
        for (k = 0; k < 4; k = k + 1)
            faw[k] <= age(faw[k]);

        // and are set by the command going out; a timer set this PCLK counts
        // from the next, so a value n allows the next command n PCLK later
        case (go_c)
            C_ACT: begin
                b_open[go_b] <= 1'b1;
                b_row[go_b] <= go_a;
                c_cas[go_b] <= T_RCD - 1;
                c_pre[go_b] <= max3(c_pre[go_b], T_RAS - 1);
                c_act[go_b] <= T_RC - 1;
                c_rrd <= T_RRD - 1;
                faw[0] <= 3'd1;
                faw[1] <= age(faw[0]);
                faw[2] <= age(faw[1]);
                faw[3] <= age(faw[2]);
                if (n_act != 32'hffffffff) n_act <= n_act + 32'd1;
            end
            C_RD: begin
                c_pre[go_b] <= max3(c_pre[go_b], T_RTP - 1);
                c_rtw <= T_RTW - 1;
            end
            C_WR: begin
                c_pre[go_b] <= max3(c_pre[go_b], T_WR - 1);
                c_wtr <= T_WTR - 1;
            end
            C_PRE: begin
                if (go_a[10]) begin
                    b_open <= 8'd0;
                    for (k = 0; k < 8; k = k + 1)
                        c_act[k] <= max3(c_act[k], T_RP - 1);
                end else begin
                    b_open[go_b] <= 1'b0;
                    c_act[go_b] <= max3(c_act[go_b], T_RP - 1);
                    c_pre[go_b] <= max3(c_pre[go_b], 1);    // cur's flags catch up
                end
            end
            C_REF: begin
                for (k = 0; k < 8; k = k + 1)
                    c_act[k] <= 3'd0;
                if (n_ref != 32'hffffffff) n_ref <= n_ref + 32'd1;
            end
            default: ;
        endcase

        // refresh: due every T_REFI, taken between requests
        refi <= (refi == T_REFI - 1) ? 10'd0 : refi + 10'd1;
        if (refi == T_REFI - 1)
            ref_due <= 1'b1;
        case (f_state)
            // at once, even in a run of row hits, which would never pause;
            // the banks' timers hold the PRECHARGE for what has gone out
            F_RUN: if (ref_due)
                f_state <= F_PRE;
            F_PRE: if (pre_ok_all && (b_open == 8'd0 || go_c == C_PRE))
                f_state <= F_REF;
            F_REF: if (go_c == C_REF) begin
                ref_due <= 1'b0;
                f_wait <= T_RFC - 1;
                f_state <= F_WAIT;
            end
            F_WAIT: if (f_wait == 5'd0)
                f_state <= F_RUN;
            else
                f_wait <= f_wait - 5'd1;
            default: f_state <= F_RUN;
        endcase

        if (rst) begin
            fq_w <= 2'd0; fq_r <= 2'd0; fq_n <= 3'd0;
            nxt_v <= 1'b0; cur_v <= 1'b0;
            b_open <= 8'd0;
            f_state <= F_RUN;
            ref_due <= 1'b0;
            refi <= 10'd0;
            for (k = 0; k < 8; k = k + 1) begin
                c_act[k] <= 3'd0; c_cas[k] <= 2'd0; c_pre[k] <= 3'd0;
            end
            c_rrd <= 3'd0; c_wtr <= 3'd0; c_rtw <= 3'd0;
            for (k = 0; k < 4; k = k + 1) faw[k] <= 3'd7;
        end
    end
endmodule

`default_nettype wire
