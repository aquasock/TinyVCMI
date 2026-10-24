`default_nettype none

// DDR3 write leveling, writes and read-back: the control half of the image.
//
// The PHY half is generated into top.v by tools/ddr3_write.py.  This module
// brings the PHY up exactly as fpga/ddr3_mpr does -- the vendor IP's order,
// traced by tools/vendor_memsync_trace.py -- runs the same JEDEC power-up
// with MPR left off, and then runs one of four modes chosen over the link:
//
//   0 idle     banks precharged; a REFRESH every 700 PCLK (7 us)
//   1 level    write leveling: MR1 with A7 set, ODT high, every strobe
//              toggling at the memory clock and every DQ in tristate.  Each
//              device samples CK on its strobe's rising edges and returns
//              the level on its byte's DQ; the core counts, per lane, the
//              PCLK cycles in which the lane's first DQ word is 0xFF.
//              MEASURED on the board 2026-10-24: as built this count is
//              always 0 -- READ stays low outside read mode, so the DQS
//              block never passes the strobe into the read FIFO and the
//              deserializers do not clock (RVALID 0, pointers frozen)
//   2 write    row 0 of bank 0 open; a WRITE every PCLK across the row's 128
//              bursts, ODT high, the strobes and DQ driven continuously with
//              the pattern P on even DQ and ~P on odd DQ in every burst; a
//              REFRESH every 700 PCLK (precharge, refresh, reopen)
//   3 read     row 0 open; a READ every PCLK across the same bursts, DQ and
//              strobes in tristate, ODT low, refreshes as in write; the core
//              counts, per lane, the cycles in which the lane's eight DQ
//              words are one rotation of P on even DQ and its inverse on odd
//              DQ, among the cycles the read stream has run unbroken for 16
//
// Leaving a mode always goes back through idle: write leveling is left with
// MR1 restored, writes and reads with every bank precharged and the bus in
// tristate.  The strobes and DQ toggle for the whole of write mode, so every
// burst the device takes is a whole one whatever the write latency; the
// latency only rotates the pattern within the burst, and the read check
// accepts any rotation.
//
// Each lane's write delay is an absolute WSTEP code loaded by WLOADN, as the
// proven controller drives it (one WSTEP per lane, one shared WLOADN,
// WMOVE and WDIR low).
//
// Requests, AA 00 <cmd> <arg>, 2 Mbaud on the TinyTang link.  The status
// request answers AA 00 04 40 <64 bytes>; every other request answers the
// core ID frame AA 00 02 01 56.
//
//   01        core ID
//   03        status
//   04        snapshot every lane's eight DQ words at the next PCLK
//   05        restart everything from the power-on reset
//   06 n      RCLKSEL = n[2:0] on every lane
//   07 a      one RMOVE pulse on the lanes in a[7:4], RDIR = a[0]
//   0A        RLOADN pulse: every lane's read delay back to its default
//   0B p      READ = p[3:0] while reading
//   0C m      mode m[1:0]
//   0E p      pattern P = p
//   10+n v    lane n's WSTEP = v, then a WLOADN pulse
//
// Status bytes, 68 of them:
//    0  {ready, pll_lock, dll_lock, lock_seen, cke, reset_n, 2'b0}
//    1  DDRDLL STEP
//    2  {mode[1:0], 2'b0, state[3:0]}  (state 8 idle, 9 level, 10 write, 11 read)
//    3  pattern P
//    4  50 MHz counter, low        5  high
//    6  PCLK counter, low          7  high
//    8  eligible read cycles in the last window, low    9  high
//   10  RCLKSEL                   11  0
//   12+6n  lane n {4'b0, RVALID, RBURST, RFLAG, WFLAG}
//   13+6n  lane n {2'b0, RPOINT[2:0], WPOINT[2:0]}
//   14+6n  lane n count in the last 65535-cycle window -- mode 1: cycles its
//          first DQ word was 0xFF; mode 3: pattern cycles -- low   15+6n  high
//   16+6n  lane n WSTEP
//   17+6n  lane n net RMOVE steps, signed
//   36+8n .. 43+8n  lane n snapshot, DQ 8n .. 8n+7
module wr_core (
    input  wire         sys_clk,
    input  wire         uart_rx,
    output wire         uart_tx,

    input  wire         pll_lock,
    output reg          pll_en = 1'b1,
    output reg          dll_rst = 1'b1,
    output reg          updncntl = 1'b1,
    output reg          hold = 1'b0,
    output wire         phy_rst,
    input  wire         dll_lock,
    input  wire [7:0]   step,

    input  wire         pclk,
    output reg  [2:0]   rclksel = 3'd0,
    output reg          rloadn = 1'b1,
    output reg  [3:0]   rmove = 4'b0000,
    output reg          rdir = 1'b0,
    output reg  [3:0]   read_en = 4'b0000,
    output reg          wloadn = 1'b1,
    output reg  [31:0]  wstep = 32'd0,
    input  wire [3:0]   rvalid,
    input  wire [3:0]   rburst,
    input  wire [3:0]   rflag,
    input  wire [3:0]   wflag,
    input  wire [11:0]  rpoint,
    input  wire [11:0]  wpoint,
    input  wire [255:0] dq_q,

    output reg  [7:0]   dq_pat = 8'h1d,
    output reg          dq_drive = 1'b0,
    output reg          dqs_drive = 1'b0,
    output reg          odt = 1'b0,
    output reg          ddr_reset_n = 1'b0,
    output reg          cke = 1'b0,
    output reg          cs_n = 1'b1,
    output reg          ras_n = 1'b1,
    output reg          cas_n = 1'b1,
    output reg          we_n = 1'b1,
    output reg  [2:0]   ba = 3'd0,
    output reg  [15:0]  addr = 16'd0
);
    // ------------------------------------------------------------------
    // PHY start-up, 50 MHz
    // ------------------------------------------------------------------
    reg restart = 1'b0;
    reg [15:0] por = 16'hffff;
    reg por_n = 1'b0;
    always @(posedge sys_clk) begin
        if (restart) begin
            por <= 16'hffff;
            por_n <= 1'b0;
        end else begin
            if (por != 16'd0)
                por <= por - 16'd1;
            por_n <= (por == 16'd0);
        end
    end

    reg [1:0] pll_s = 2'b00, lock_s = 2'b00;
    always @(posedge sys_clk) begin
        pll_s <= {pll_s[0], pll_lock};
        lock_s <= {lock_s[0], dll_lock};
    end
    wire pll_ok = pll_s[1];
    wire lock_ok = lock_s[1];

    // the vendor's reset chain: three flops from the DLL reset, forced high
    // for the sync pulse
    reg [2:0] rst_chain = 3'b111;
    reg sync_rst = 1'b0;
    always @(posedge sys_clk)
        rst_chain <= {rst_chain[1:0], dll_rst | sync_rst};
    assign phy_rst = rst_chain[2];

    localparam [2:0] M_WAIT = 3'd0, M_SETTLE = 3'd1, M_UPDATE = 3'd2,
                     M_SYNC = 3'd3, M_READY = 3'd4;
    reg [2:0] mstate = M_WAIT;
    reg [14:0] mtimer = 15'd0;
    reg ready = 1'b0;
    reg lock_seen = 1'b0;

    always @(posedge sys_clk) begin
        if (!por_n) begin
            dll_rst <= 1'b1;
            updncntl <= 1'b1;
            hold <= 1'b0;
            pll_en <= 1'b1;
            sync_rst <= 1'b0;
            ready <= 1'b0;
            lock_seen <= 1'b0;
            mstate <= M_WAIT;
            mtimer <= 15'd0;
        end else begin
            dll_rst <= 1'b0;
            mtimer <= mtimer + 15'd1;
            if (lock_ok)
                lock_seen <= 1'b1;
            case (mstate)
                M_WAIT: begin
                    mtimer <= 15'd0;
                    if (lock_ok && pll_ok)
                        mstate <= M_SETTLE;
                end
                M_SETTLE: begin
                    if (!lock_ok)
                        mstate <= M_WAIT;
                    else if (mtimer == 15'd16383) begin
                        mstate <= M_UPDATE;
                        mtimer <= 15'd0;
                    end
                end
                // cycle: 0 HOLD, 4 UPDNCNTL low, 8 high, 12 HOLD low
                M_UPDATE: begin
                    if (mtimer == 15'd0) hold <= 1'b1;
                    if (mtimer == 15'd4) updncntl <= 1'b0;
                    if (mtimer == 15'd8) updncntl <= 1'b1;
                    if (mtimer == 15'd12) begin
                        hold <= 1'b0;
                        mstate <= M_SYNC;
                        mtimer <= 15'd0;
                    end
                end
                // cycle: 15 clock off, 19 reset on, 23 reset off, 27 clock
                // on, 36 READY (the chain adds its three flops to the reset)
                M_SYNC: begin
                    if (mtimer == 15'd15) pll_en <= 1'b0;
                    if (mtimer == 15'd16) sync_rst <= 1'b1;
                    if (mtimer == 15'd20) sync_rst <= 1'b0;
                    if (mtimer == 15'd27) pll_en <= 1'b1;
                    if (mtimer == 15'd36) begin
                        ready <= 1'b1;
                        mstate <= M_READY;
                    end
                end
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Settings from the link into the PCLK domain
    // ------------------------------------------------------------------
    reg [1:0] mode_req = 2'd0;
    reg [3:0] read_pat = 4'b1111;
    reg [7:0] pat_req = 8'h1d;
    reg [2:0] rclksel_req = 3'd0;
    reg rdir_req = 1'b0;
    reg [3:0] rmove_mask = 4'b0000;
    reg [31:0] wstep_req = 32'd0;
    reg rmove_tog = 1'b0, rload_tog = 1'b0, snap_tog = 1'b0, wload_tog = 1'b0;

    reg [1:0] ready_p = 2'b00;
    reg [2:0] rmove_p = 3'b000, rload_p = 3'b000, snap_p = 3'b000, wload_p = 3'b000;
    reg [1:0] mode_p1 = 2'd0, mode_p = 2'd0;
    reg [3:0] pat_p1 = 4'b1111, pat_p2 = 4'b1111;
    reg [7:0] dpat_p1 = 8'h1d;
    reg [2:0] sel_p1 = 3'd0;
    reg rdir_p1 = 1'b0;
    reg [3:0] mask_p1 = 4'b0000, mask_p2 = 4'b0000;
    reg [31:0] wstep_p1 = 32'd0;
    always @(posedge pclk) begin
        ready_p <= {ready_p[0], ready};
        rmove_p <= {rmove_p[1:0], rmove_tog};
        rload_p <= {rload_p[1:0], rload_tog};
        snap_p <= {snap_p[1:0], snap_tog};
        wload_p <= {wload_p[1:0], wload_tog};
        mode_p1 <= mode_req;            mode_p <= mode_p1;
        pat_p1 <= read_pat;             pat_p2 <= pat_p1;
        dpat_p1 <= pat_req;             dq_pat <= dpat_p1;
        sel_p1 <= rclksel_req;          rclksel <= sel_p1;
        rdir_p1 <= rdir_req;            rdir <= rdir_p1;
        mask_p1 <= rmove_mask;          mask_p2 <= mask_p1;
        wstep_p1 <= wstep_req;          wstep <= wstep_p1;
    end
    wire ready_pc = ready_p[1];
    wire rmove_pulse = rmove_p[2] ^ rmove_p[1];
    wire rload_pulse = rload_p[2] ^ rload_p[1];
    wire snap_pulse = snap_p[2] ^ snap_p[1];
    wire wload_pulse = wload_p[2] ^ wload_p[1];

    // ------------------------------------------------------------------
    // DDR3 initialization and the four modes, PCLK
    // ------------------------------------------------------------------
    localparam [3:0] I_IDLE = 4'd0, I_RESET = 4'd1, I_CKE = 4'd2, I_XPR = 4'd3,
                     I_MR = 4'd4, I_ZQ = 4'd5, I_WAIT = 4'd6,
                     R_IDLE = 4'd8, R_LEVEL = 4'd9, R_WRITE = 4'd10, R_READ = 4'd11;
    localparam [1:0] M_IDLE = 2'd0, M_LEVEL = 2'd1, M_WRITE = 2'd2, M_READ = 2'd3;

    reg [3:0] istate = I_IDLE;
    reg [3:0] wnext = I_IDLE;
    reg [16:0] itimer = 17'd0;
    reg [16:0] wcount = 17'd0;
    reg [1:0] mr_idx = 2'd0;
    reg [1:0] mode = M_IDLE;
    reg [3:0] rload_cnt = 4'd0;
    reg [3:0] wload_cnt = 4'd0;
    reg [9:0] refi = 10'd0;
    reg [9:0] col = 10'd0;
    reg [3:0] step_no = 4'd0;           // position in an entry/exit/refresh script
    reg [15:0] rd_hist = 16'd0;         // the read stream, one bit per PCLK

    localparam [9:0] TREFI = 10'd700;   // 7 us, under the 7.8 us tREFI

    // MR2, MR3, MR1, MR0, in issue order: {BA, A}
    function [18:0] mr_word;
        input [1:0] i;
        begin
            case (i)
                2'd0: mr_word = {3'd2, 16'h0000};
                2'd1: mr_word = {3'd3, 16'h0000};
                2'd2: mr_word = {3'd1, 16'h0044};
                default: mr_word = {3'd0, 16'h0520};
            endcase
        end
    endfunction

    task deselect;
        begin
            cs_n <= 1'b1; ras_n <= 1'b1; cas_n <= 1'b1; we_n <= 1'b1;
        end
    endtask
    task issue(input [3:0] c, input [2:0] b, input [15:0] a);
        begin
            {cs_n, ras_n, cas_n, we_n} <= c;
            ba <= b;
            addr <= a;
        end
    endtask
    localparam [3:0] C_MRS = 4'b0000, C_REF = 4'b0001, C_PRE = 4'b0010, C_ACT = 4'b0011,
                     C_WR = 4'b0100, C_RD = 4'b0101, C_ZQ = 4'b0110;

    // wait n PCLK, then go to state s
    task pause(input [16:0] n, input [3:0] s);
        begin
            wcount <= n;
            wnext <= s;
            istate <= I_WAIT;
        end
    endtask

    always @(posedge pclk) begin
        deselect;
        itimer <= itimer + 17'd1;
        rmove <= rmove_pulse ? mask_p2 : 4'b0000;
        read_en <= 4'b0000;
        rd_hist <= {rd_hist[14:0], 1'b0};

        if (rload_pulse || (istate == I_IDLE && ready_pc && itimer == 17'd4))
            rload_cnt <= 4'd8;
        else if (rload_cnt != 4'd0)
            rload_cnt <= rload_cnt - 4'd1;
        rloadn <= (rload_cnt == 4'd0);

        if (wload_pulse || (istate == I_IDLE && ready_pc && itimer == 17'd4))
            wload_cnt <= 4'd8;
        else if (wload_cnt != 4'd0)
            wload_cnt <= wload_cnt - 4'd1;
        wloadn <= (wload_cnt == 4'd0);

        if (istate >= R_IDLE && refi != 10'h3ff)
            refi <= refi + 10'd1;

        if (!ready_pc) begin
            istate <= I_IDLE;
            itimer <= 17'd0;
            ddr_reset_n <= 1'b0;
            cke <= 1'b0;
            odt <= 1'b0;
            dq_drive <= 1'b0;
            dqs_drive <= 1'b0;
            mode <= M_IDLE;
        end else begin
            case (istate)
                I_IDLE: if (itimer == 17'd16) begin
                    istate <= I_RESET;
                    itimer <= 17'd0;
                end
                I_RESET: if (itimer == 17'd20000) begin        // 200 us
                    ddr_reset_n <= 1'b1;
                    istate <= I_CKE;
                    itimer <= 17'd0;
                end
                I_CKE: if (itimer == 17'd50000) begin          // 500 us
                    cke <= 1'b1;
                    mr_idx <= 2'd0;
                    pause(17'd32, I_MR);                        // 320 ns
                end
                I_MR: begin
                    {ba, addr} <= mr_word(mr_idx);
                    {cs_n, ras_n, cas_n, we_n} <= C_MRS;
                    mr_idx <= mr_idx + 2'd1;
                    pause(17'd8, mr_idx == 2'd3 ? I_ZQ : I_MR);
                end
                I_ZQ: begin
                    issue(C_ZQ, 3'd0, 16'h0400);                // ZQCL
                    refi <= 10'd0;
                    mode <= M_IDLE;
                    pause(17'd256, R_IDLE);
                end
                I_WAIT: begin
                    if (wcount == 17'd0)
                        istate <= wnext;
                    else
                        wcount <= wcount - 17'd1;
                end

                // banks precharged: refresh, or enter the requested mode
                R_IDLE: begin
                    step_no <= 4'd0;
                    if (refi >= TREFI) begin
                        issue(C_REF, 3'd0, 16'h0000);
                        refi <= 10'd0;
                        pause(17'd30, R_IDLE);                  // tRFC 260 ns
                    end else if (mode_p != M_IDLE) begin
                        mode <= mode_p;
                        istate <= mode_p == M_LEVEL ? R_LEVEL :
                                  mode_p == M_WRITE ? R_WRITE : R_READ;
                    end
                end

                // write leveling
                R_LEVEL: begin
                    case (step_no)
                        4'd0: begin                             // MR1 with A7
                            issue(C_MRS, 3'd1, 16'h00c4);
                            step_no <= 4'd1;
                            pause(17'd16, R_LEVEL);             // tWLMRD 40 tCK
                        end
                        4'd1: begin
                            odt <= 1'b1;
                            step_no <= 4'd2;
                            pause(17'd16, R_LEVEL);             // tWLDQSEN 25 tCK
                        end
                        4'd2: begin
                            dqs_drive <= 1'b1;
                            step_no <= 4'd3;
                        end
                        4'd3: if (mode_p != M_LEVEL) begin
                            dqs_drive <= 1'b0;
                            step_no <= 4'd4;
                            pause(17'd4, R_LEVEL);
                        end
                        4'd4: begin
                            odt <= 1'b0;
                            step_no <= 4'd5;
                            pause(17'd4, R_LEVEL);
                        end
                        default: begin                          // MR1 back
                            issue(C_MRS, 3'd1, 16'h0044);
                            mode <= M_IDLE;
                            pause(17'd16, R_IDLE);
                        end
                    endcase
                end

                // writes and reads share one script: open row 0, stream,
                // refresh (close, refresh, reopen), close on leaving
                R_WRITE, R_READ: begin
                    case (step_no)
                        4'd0: begin
                            issue(C_ACT, 3'd0, 16'h0000);
                            col <= 10'd0;
                            if (istate == R_WRITE) begin
                                odt <= 1'b1;
                                dq_drive <= 1'b1;
                                dqs_drive <= 1'b1;
                            end
                            step_no <= 4'd1;
                            pause(17'd8, istate);               // tRCD, and the bus settles
                        end
                        4'd1: begin
                            if (mode_p != mode || refi >= TREFI) begin
                                step_no <= 4'd2;
                                pause(17'd8, istate);           // tWR / tRTP and the burst tail
                            end else begin
                                issue(istate == R_WRITE ? C_WR : C_RD, 3'd0, {6'd0, col});
                                col <= col + 10'd8;
                                if (istate == R_READ) begin
                                    read_en <= pat_p2;
                                    rd_hist[0] <= 1'b1;
                                end
                            end
                        end
                        4'd2: begin
                            issue(C_PRE, 3'd0, 16'h0400);       // all banks
                            step_no <= 4'd3;
                            pause(17'd4, istate);               // tRP
                        end
                        4'd3: begin
                            if (mode_p != mode) begin
                                // release the bus first: the serializers
                                // carry their last beats out for a few
                                // clocks after their enables drop
                                dq_drive <= 1'b0;
                                dqs_drive <= 1'b0;
                                odt <= 1'b0;
                                step_no <= 4'd5;
                                pause(17'd4, istate);
                            end else begin
                                issue(C_REF, 3'd0, 16'h0000);
                                refi <= 10'd0;
                                step_no <= 4'd4;
                                pause(17'd30, istate);          // tRFC
                            end
                        end
                        4'd5: begin                             // left: idle
                            mode <= M_IDLE;
                            istate <= R_IDLE;
                        end
                        default: begin                          // reopen and stream
                            step_no <= 4'd0;
                        end
                    endcase
                end
                default: istate <= I_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Capture, PCLK
    // ------------------------------------------------------------------
    reg [15:0] pclk_cnt = 16'd0;
    reg [63:0] good = 64'd0;            // lane n at [16n +: 16]
    reg [63:0] good_last = 64'd0;
    reg [15:0] elig = 16'd0, elig_last = 16'd0;
    reg [255:0] snap = 256'd0;
    reg [255:0] dq_r = 256'd0;
    reg eligible = 1'b0;
    reg [63:0] pat_rot = 64'd0;         // the eight rotations of P, rotation r at [8r +: 8]
    reg [3:0] hit = 4'b0000;            // a lane's match, one cycle after its words
    integer l, k, r;
    reg ok, rot;
    reg [7:0] w0;

    // Two stages, so the check fits PCLK: the words are compared into `hit`,
    // and `hit` is counted the cycle after.
    always @(posedge pclk) begin
        pclk_cnt <= pclk_cnt + 16'd1;
        dq_r <= dq_q;
        eligible <= (mode == M_READ) && (&rd_hist);
        for (r = 0; r < 8; r = r + 1)
            pat_rot[8 * r +: 8] <= (dq_pat << r) | (dq_pat >> (8 - r));
        if (snap_pulse)
            snap <= dq_r;
        for (l = 0; l < 4; l = l + 1) begin
            w0 = dq_r[64 * l +: 8];
            if (mode == M_LEVEL) begin
                ok = (w0 == 8'hff);
            end else if (mode == M_READ) begin
                rot = 1'b0;
                for (r = 0; r < 8; r = r + 1)
                    rot = rot || (w0 == pat_rot[8 * r +: 8]);
                ok = eligible && rot;
                for (k = 1; k < 8; k = k + 1)
                    ok = ok && (dq_r[64 * l + 8 * k +: 8] == (k % 2 == 1 ? ~w0 : w0));
            end else begin
                ok = 1'b0;
            end
            hit[l] <= ok;
            // the window is the 65535 cycles before the wrap
            if (pclk_cnt == 16'hffff) begin
                good_last[16 * l +: 16] <= good[16 * l +: 16];
                good[16 * l +: 16] <= 16'd0;
            end else begin
                good[16 * l +: 16] <= good[16 * l +: 16] + {15'd0, hit[l]};
            end
        end
        if (pclk_cnt == 16'hffff) begin
            elig_last <= elig;
            elig <= 16'd0;
        end else begin
            elig <= elig + {15'd0, eligible};
        end
    end

    // ------------------------------------------------------------------
    // Into the 50 MHz domain; values read as levels or "is it moving"
    // ------------------------------------------------------------------
    reg [7:0] step_s1 = 8'h00, step_s2 = 8'h00;
    reg [15:0] pclk_s1 = 16'd0, pclk_s2 = 16'd0;
    reg [15:0] elig_s1 = 16'd0, elig_s2 = 16'd0;
    reg [39:0] lane_s1 = 40'd0, lane_s2 = 40'd0;
    reg [63:0] good_s1 = 64'd0, good_s2 = 64'd0;
    reg [255:0] snap_s1 = 256'd0, snap_s2 = 256'd0;
    reg [7:0] st_s1 = 8'd0, st_s2 = 8'd0;
    wire [39:0] lane_now = {rvalid, rburst, rflag, wflag, rpoint, wpoint};
    always @(posedge sys_clk) begin
        step_s1 <= step;                step_s2 <= step_s1;
        pclk_s1 <= pclk_cnt;            pclk_s2 <= pclk_s1;
        elig_s1 <= elig_last;           elig_s2 <= elig_s1;
        lane_s1 <= lane_now;            lane_s2 <= lane_s1;
        good_s1 <= good_last;           good_s2 <= good_s1;
        snap_s1 <= snap;                snap_s2 <= snap_s1;
        st_s1 <= {cke, ddr_reset_n, mode, istate};
        st_s2 <= st_s1;
    end

    reg [15:0] free_cnt = 16'd0;
    reg [31:0] moves = 32'd0;           // lane n's net RMOVE steps at [8n +: 8]
    always @(posedge sys_clk)
        free_cnt <= free_cnt + 16'd1;

    function [47:0] lane_bytes;
        input [39:0] v;
        input [63:0] g;
        input [31:0] ws;
        input [31:0] mv;
        input integer n;
        begin
            lane_bytes = {mv[8 * n +: 8], ws[8 * n +: 8], g[16 * n +: 16],
                          2'b00, v[12 + 3 * n +: 3], v[3 * n +: 3],
                          4'b0000, v[36 + n], v[32 + n], v[28 + n], v[24 + n]};
        end
    endfunction

    wire [543:0] status = {
        snap_s2,
        lane_bytes(lane_s2, good_s2, wstep_req, moves, 3),
        lane_bytes(lane_s2, good_s2, wstep_req, moves, 2),
        lane_bytes(lane_s2, good_s2, wstep_req, moves, 1),
        lane_bytes(lane_s2, good_s2, wstep_req, moves, 0),
        8'h00, 5'd0, rclksel_req,
        elig_s2, pclk_s2, free_cnt,
        pat_req,
        st_s2[5:4], 2'b00, st_s2[3:0],
        step_s2,
        ready, pll_ok, lock_ok, lock_seen, st_s2[7], st_s2[6], 2'b00
    };

    // ------------------------------------------------------------------
    // The link
    // ------------------------------------------------------------------
    wire rx_valid;
    wire [7:0] rx_data;
    wire tx_ready;
    reg tx_send = 1'b0;
    reg [7:0] tx_data = 8'h00;

    uart_rx_2mbaud rx (.clk(sys_clk), .rx(uart_rx), .valid(rx_valid), .data(rx_data));
    uart_tx_2mbaud tx (.clk(sys_clk), .send(tx_send), .data(tx_data),
                       .ready(tx_ready), .tx(uart_tx));

    reg [1:0] request_state = 2'd0;
    reg [7:0] cmd_byte = 8'h00;
    reg response_active = 1'b0;
    reg response_is_status = 1'b0;
    reg [6:0] response_index = 7'd0;
    reg [543:0] frame = 544'd0;

    function known;
        input [7:0] c;
        begin
            known = (c == 8'h01) || (c == 8'h03) || (c == 8'h04) || (c == 8'h05) ||
                    (c == 8'h06) || (c == 8'h07) || (c == 8'h0a) || (c == 8'h0b) ||
                    (c == 8'h0c) || (c == 8'h0e) || (c[7:2] == 6'b000100);
        end
    endfunction

    integer m;
    always @(posedge sys_clk) begin
        tx_send <= 1'b0;
        restart <= 1'b0;

        if (rx_valid) begin
            case (request_state)
                2'd0: request_state <= (rx_data == 8'haa) ? 2'd1 : 2'd0;
                2'd1: request_state <= (rx_data == 8'h00) ? 2'd2 :
                                       (rx_data == 8'haa) ? 2'd1 : 2'd0;
                2'd2: begin
                    if (known(rx_data)) begin
                        cmd_byte <= rx_data;
                        request_state <= 2'd3;
                    end else begin
                        request_state <= (rx_data == 8'haa) ? 2'd1 : 2'd0;
                    end
                end
                default: begin
                    request_state <= 2'd0;
                    if (!response_active) begin
                        response_active <= 1'b1;
                        response_is_status <= (cmd_byte == 8'h03);
                        response_index <= 7'd0;
                        frame <= status;
                        case (cmd_byte)
                            8'h04: snap_tog <= ~snap_tog;
                            8'h05: begin
                                restart <= 1'b1;
                                mode_req <= 2'd0;
                                moves <= 32'd0;
                            end
                            8'h06: rclksel_req <= rx_data[2:0];
                            8'h07: begin
                                rdir_req <= rx_data[0];
                                rmove_mask <= rx_data[7:4];
                                rmove_tog <= ~rmove_tog;
                                for (m = 0; m < 4; m = m + 1)
                                    if (rx_data[4 + m])
                                        moves[8 * m +: 8] <= rx_data[0] ? moves[8 * m +: 8] + 8'd1
                                                                         : moves[8 * m +: 8] - 8'd1;
                            end
                            8'h0a: begin
                                rload_tog <= ~rload_tog;
                                moves <= 32'd0;
                            end
                            8'h0b: read_pat <= rx_data[3:0];
                            8'h0c: mode_req <= rx_data[1:0];
                            8'h0e: pat_req <= rx_data;
                            default: if (cmd_byte[7:2] == 6'b000100) begin
                                wstep_req[8 * cmd_byte[1:0] +: 8] <= rx_data;
                                wload_tog <= ~wload_tog;
                            end
                        endcase
                    end
                end
            endcase
        end

        if (response_active && tx_ready && !tx_send) begin
            if (response_is_status) begin
                case (response_index)
                    7'd0: tx_data <= 8'haa;
                    7'd1: tx_data <= 8'h00;
                    7'd2: tx_data <= 8'h04;
                    7'd3: tx_data <= 8'h44;
                    default: begin
                        tx_data <= frame[7:0];
                        frame <= frame >> 8;
                    end
                endcase
            end else begin
                case (response_index)
                    7'd0: tx_data <= 8'haa;
                    7'd1: tx_data <= 8'h00;
                    7'd2: tx_data <= 8'h02;
                    7'd3: tx_data <= 8'h01;
                    default: tx_data <= 8'h56; // "V" for TinyVCMI.
                endcase
            end
            tx_send <= 1'b1;
            if (response_index == (response_is_status ? 7'd71 : 7'd4))
                response_active <= 1'b0;
            else
                response_index <= response_index + 7'd1;
        end
    end
endmodule

// The 2 Mbaud link of fpga/ddrdll_liveness, unchanged.
module uart_rx_2mbaud (
    input  wire clk,
    input  wire rx,
    output reg  valid = 1'b0,
    output reg  [7:0] data = 8'h00
);
    reg rx_meta = 1'b1;
    reg rx_sync = 1'b1;
    reg busy = 1'b0;
    reg [4:0] ticks = 5'd0;
    reg [3:0] bit_index = 4'd0;
    reg [7:0] shift = 8'h00;

    always @(posedge clk) begin
        rx_meta <= rx;
        rx_sync <= rx_meta;
        valid <= 1'b0;

        if (!busy) begin
            if (!rx_sync) begin
                busy <= 1'b1;
                ticks <= 5'd11;
                bit_index <= 4'd0;
            end
        end else if (ticks != 0) begin
            ticks <= ticks - 1'b1;
        end else if (bit_index == 0) begin
            if (!rx_sync) begin
                bit_index <= 4'd1;
                ticks <= 5'd24;
            end else begin
                busy <= 1'b0;
            end
        end else if (bit_index <= 8) begin
            shift[bit_index - 1'b1] <= rx_sync;
            bit_index <= bit_index + 1'b1;
            ticks <= 5'd24;
        end else begin
            busy <= 1'b0;
            if (rx_sync) begin
                data <= shift;
                valid <= 1'b1;
            end
        end
    end
endmodule

module uart_tx_2mbaud (
    input  wire clk,
    input  wire send,
    input  wire [7:0] data,
    output wire ready,
    output wire tx
);
    reg busy = 1'b0;
    reg [4:0] ticks = 5'd0;
    reg [3:0] bit_index = 4'd0;
    reg [9:0] shift = 10'h3ff;

    assign ready = !busy;
    assign tx = busy ? shift[0] : 1'b1;

    always @(posedge clk) begin
        if (!busy) begin
            if (send) begin
                busy <= 1'b1;
                ticks <= 5'd24;
                bit_index <= 4'd0;
                shift <= {1'b1, data, 1'b0};
            end
        end else if (ticks != 0) begin
            ticks <= ticks - 1'b1;
        end else if (bit_index == 4'd9) begin
            busy <= 1'b0;
        end else begin
            ticks <= 5'd24;
            bit_index <= bit_index + 1'b1;
            shift <= {1'b1, shift[9:1]};
        end
    end
endmodule

`default_nettype wire
