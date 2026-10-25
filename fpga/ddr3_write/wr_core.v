`default_nettype none

// DDR3 write leveling, writes and read-back: the control half of the image.
//
// The PHY half is generated into top.v by tools/ddr3_write.py.  This module
// brings the PHY up exactly as fpga/ddr3_mpr does -- the vendor IP's order,
// traced by tools/vendor_memsync_trace.py -- runs the same JEDEC power-up
// with MPR left off, and then runs one of four modes chosen over the link.
// The PLL must remain locked for 16384 sys_clk cycles before the DLL and lane
// reset chain are released; the later DLL update and clock-stop sync retain
// the proven controller's order.
//
//   0 idle     banks precharged; a REFRESH every 700 PCLK (7 us)
//   1 level    write leveling: MR1 with A7 set, ODT high, every strobe
//              toggling at the memory clock and every DQ in tristate.  Each
//              device samples CK on its strobe's rising edges and returns
//              the level on its byte's DQ; the core counts, per lane, the
//              PCLK cycles in which the lane's first DQ word is 0xFF.
//              READ is asserted while the strobe toggles so the returned
//              level reaches the lane FIFO and can be counted.
//   2 write    row 0 of bank 0 open; a WRITE every PCLK across the row's 128
//              bursts, ODT high, the strobes and DQ driven continuously with
//              the pattern P on even DQ and ~P on odd DQ in every burst; a
//              REFRESH every 700 PCLK (precharge, refresh, reopen)
//   3 read     row 0 open; a READ every PCLK across the same bursts, DQ and
//              strobes in tristate, ODT low, refreshes as in write; the core
//              counts, per lane, the cycles in which the lane's eight DQ
//              words are one rotation of P on even DQ and its inverse on odd
//              DQ, among the cycles the read stream has run unbroken for 16
//   4 random   closed-page single READs: every max(gap,8) PCLK an ACTIVATE of
//              a pseudo-random one of sixteen locations -- bank 0..7, row
//              {row[14:1], 0 or 1} -- and three PCLK later a READ with
//              auto-precharge of a pseudo-random burst in it; a REFRESH in
//              place of an access every 700 PCLK.  The host writes each of
//              the sixteen rows beforehand with its rd_check.v pattern, so
//              rd_check knows what every READ must return and measures the
//              read latency and whether the word frame holds from one
//              isolated READ to the next.  Nothing is driven; ODT stays low.
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
// request answers AA 00 04 7F <127 bytes>, the checker's status request
// AA 00 05 7F <127 bytes>; every other request answers the core ID frame
// AA 00 02 01 56.
//
//   01        core ID
//   03        status
//   04        snapshot every lane's eight DQ words at the next PCLK
//   05        restart everything from the power-on reset
//   06 n      RCLKSEL = n[2:0] on every lane (2E sets one lane)
//   07 a      one RMOVE pulse on the lanes in a[7:4], RDIR = a[0]
//   08 n      one CALIB pulse on DQ n[4:0]
//   09 n      gap of max(n,1) PCLK between gated READ groups
//   0A        RLOADN pulse: every lane's read delay back to its default
//   0B p      READ = p[3:0] while reading
//   0C m      mode m[2:0]; 5..7 are idle
//   0D n      max(n,1) consecutive READ commands per gated group
//   0E p      pattern P = p
//   0F b      active bank b[2:0]
//   10+n v    lane n's WSTEP = v, then a WLOADN pulse
//   20 v      active row[7:0]
//   21 v      active row[14:8] = v[6:0]
//   22 n      delay DQS READ gating n[2:0] PCLK after each READ command, on
//             every lane (2C sets one lane)
//   23        re-arm rd_align: discard every lane's locked rotation
//   24 n      clear the RBURST counters; n = 0 lets them run and wrap, n
//             = 1..23 counts for 2^n PCLK, saturating at 255, then holds
//   25 k      open each READ's DQS gate k[1:0] memory clocks later: READ[i]
//             follows the delayed READ of this PCLK for i >= k and of the
//             previous PCLK for i < k (bit 0 is the earliest clock), on
//             every lane (2D sets one lane)
//   26 n      rd_check's check offset n[4:0]
//   27        the checker's status
//   28 s      rd_check's expected rotation advance per READ, s[2:0]
//   2A v      set lane v[4:3]'s two-word beat slip to v[2:0]; v[7] enables
//             the reassembler after all four lane values have been written
//   2B        burst position: for every isolated READ, which of the two known
//             capture offsets held it and the refresh phase at that check,
//             answered with 34 payload bytes (see status3)
//   2C v      lane v[7:6]'s READ gating delay = v[2:0] PCLK
//   2D v      lane v[7:6]'s READ gate offset = v[1:0] memory clocks
//   2E v      lane v[7:6]'s RCLKSEL = v[2:0]
//   2F        lag and RBURST level: for every isolated READ with nine
//             distinct recent patterns, which READ's pattern each lane held
//             at the check offset, each lane's RBURST level count and RVALID
//             count, answered with 206 payload bytes (see status4)
//   31        read-training counters: READs issued in random mode since the
//             arm, the PCLK counted, and per lane RVALID-high cycles and RBURST
//             pulses, answered with 40 payload bytes (see status5)
//   32 n      rd_check's READ log passes over n x 1024 READs after its arm
//             before keeping 1024 (applied at the next arm)
//   33 p      copy page p[5:0] of the READ log, entries 16p .. 16p + 15, to
//             the page frame
//   34        the READ log page: entries logged, the page copied and 16
//             entries, answered with 148 payload bytes (see status6)
//   29 v      v[0]: rd_check takes each lane's word only on cycles whose RVALID
//             is high, holding it between them, as the proven controller's
//             read FIFO does (TOOL-033); clear by default
//
// The proven vendor controller drives READ, RCLKSEL and HOLD per lane and
// trains each lane's gate on an RBURST level (TOOL-033), so this image gives
// every lane its own gate delay, gate offset and RCLKSEL; the commands that
// set all four keep their old meaning.  The status frames report lane 0's.
//
// The read data path ends in rd_align, the trained read-valid boundary: it
// locks each lane's whole-word rotation from the live stream, derotates it,
// transposes the lane's eight pins into eight beat bytes and presents a
// 256-bit burst (eight beats of 32 bits) with a valid.  Training arms itself
// whenever read mode is entered, on every CALIB pulse and on command 0x23.
// rd_check, the single-burst checker, arms on entering random mode and on
// command 0x23.
//
// Status bytes, 110 of them:
//    0  {ready, pll_lock, dll_lock, lock_seen, cke, reset_n, 2'b0}
//    1  DDRDLL STEP
//    2  {mode[1:0], mode[2], 1'b0, state[3:0]}
//          (state 8 idle, 9 level, 10 write, 11 read, 12 random)
//    3  pattern P
//    4  50 MHz counter, low        5  high
//    6  PCLK counter, low          7  high
//    8  eligible read cycles in the last window, low    9  high
//   10  lane 0's RCLKSEL          11  READ group length in PCLK
//   12+6n  lane n {4'b0, RVALID, RBURST, RFLAG, WFLAG}
//   13+6n  lane n {2'b0, RPOINT[2:0], WPOINT[2:0]}
//   14+6n  lane n count in the last 65535-cycle window -- mode 1: cycles its
//          first DQ word was 0xFF; mode 3: pattern cycles -- low   15+6n  high
//   16+6n  lane n WSTEP
//   17+6n  lane n net RMOVE steps, signed
//   36+8n .. 43+8n  lane n snapshot, DQ 8n .. 8n+7
//   68     {1'b0, pat_ok, 2'b00, trained[3:0]}  -- rd_align's locks
//   69-70  aligned bursts whose 32 bytes all matched in the last window
//   71-72  lane n's locked rotation at [3n +: 3], 71 low
//   73     {4'b0, drift[3:0]}   a lane's live rotation left its lock
//   74     {4'b0, err[3:0]}     a lane's aligned byte did not match
//   75-76  aligned bursts presented in the last window
//   78+32b+8l .. +7  aligned snapshot: beat b, lane l, byte b of lane l
//          at bit 0, i.e. lane 0 is DQ[7:0] of the 32-bit beat
//   110-111  phase moves seen while streaming since the last arm
//   112-113  those seen at the first live cycle after a gated gap
//   114-115  PCLK cycles between the last two moves
//   116      {skew_changed, 1'b0, lane 1 step, lane 0 step}, 3 bits each
//   117      {2'b0, lane 3 step, lane 2 step}
//   118-119  the live rotation: 118 low, 119 {phase_ok[3:0], phase[11:8]}
//   120-121  uniform slips rd_align followed since the last arm
//   122      {window open, 3'b0, burst_seen[3:0]}  an RBURST edge was
//            counted on that lane
//   123-126  per-lane RBURST edge count since command 0x24
//
// Checker status bytes (command 0x27), 127 of them, counters since the arm:
//    0  {locked, random mode, lane 0's gate k[1:0], 1'b0, step[2:0]}
//    1  {3'b0, check offset[4:0]}
//    2-5   READs checked        6-9   good: all lanes at the expected rotation
//   10-13  class_ok: all lanes hold the READ's pattern
//   14-17  READs whose rotation differed from the previous READ's
//   18-19  READs counted in hist (a pattern unlike the previous READ's)
//   20-21  expected rotation of the next READ, lane n at [3n +: 3]
//   22-23  last READ's rotation     24  {fail, 3'b0, failing lanes[3:0]}
//   25     first failure's pattern  26-27  its {row bit, bank, burst}
//   28     {4'b0, last READ's lanes holding its pattern}
//   29+2j  hist[j], j = 0..31, 16 bits: all lanes held the READ's pattern
//          j cycles after it; the burst reached dq_q j - 3 cycles after the
//          cycle the READ left the core
//   93+8n+p  first failure's raw word, lane n DQ p
//   125-126  first failure's rotation
//
// GowinSynthesis otherwise packs the two-flop setting synchronizers into
// counter-addressed LUT-RAM shift registers, whose read sits on PCLK's
// critical paths; Yosys ignores the attribute.
(* syn_srlstyle = "registers" *)
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
    input  wire [3:0]   burst_tog,

    input  wire         pclk,
    output reg  [11:0]  rclksel = 12'd0,     // lane n at [3n +: 3]
    output reg          rloadn = 1'b1,
    output reg  [3:0]   rmove = 4'b0000,
    output reg          rdir = 1'b0,
    output reg  [15:0]  read_en = 16'd0,     // lane n's READ[3:0] at [4n +: 4]
    output reg  [31:0]  calib = 32'd0,
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

    localparam [2:0] M_PLL = 3'd0, M_DLL = 3'd1, M_SETTLE = 3'd2,
                     M_UPDATE = 3'd3, M_SYNC = 3'd4, M_READY = 3'd5;
    reg [2:0] mstate = M_PLL;
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
            mstate <= M_PLL;
            mtimer <= 15'd0;
        end else begin
            mtimer <= mtimer + 15'd1;
            if (lock_ok)
                lock_seen <= 1'b1;
            case (mstate)
                M_PLL: begin
                    dll_rst <= 1'b1;
                    if (!pll_ok)
                        mtimer <= 15'd0;
                    else if (mtimer == 15'd16383) begin
                        dll_rst <= 1'b0;
                        mstate <= M_DLL;
                        mtimer <= 15'd0;
                    end
                end
                M_DLL: begin
                    dll_rst <= 1'b0;
                    mtimer <= 15'd0;
                    if (!pll_ok)
                        mstate <= M_PLL;
                    else if (lock_ok)
                        mstate <= M_SETTLE;
                end
                M_SETTLE: begin
                    dll_rst <= 1'b0;
                    if (!pll_ok || !lock_ok)
                        mstate <= M_PLL;
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
    reg [2:0] mode_req = 3'd0;
    reg [7:0] gate_req = 8'd0;          // lane n at [2n +: 2]
    reg [4:0] lat_req = 5'd12;
    reg [2:0] rstep_req = 3'd0;
    reg [11:0] slip_req = 12'd0;
    reg slip_en_req = 1'b0;
    reg rv_en_req = 1'b0;
    reg [4:0] bwin_req = 5'd0;
    reg [3:0] read_pat = 4'b1111;
    reg [7:0] pat_req = 8'h1d;
    reg [11:0] rclksel_req = 12'd0;     // lane n at [3n +: 3]
    reg rdir_req = 1'b0;
    reg [3:0] rmove_mask = 4'b0000;
    reg [31:0] wstep_req = 32'd0;
    reg [31:0] calib_mask = 32'd0;
    reg [7:0] read_run_req = 8'd32;
    reg [7:0] read_gap_req = 8'd8;
    reg [11:0] read_delay_req = {4{3'd3}};  // lane n at [3n +: 3]
    reg [2:0] bank_req = 3'd0;
    reg [14:0] row_req = 15'd0;
    reg rmove_tog = 1'b0, rload_tog = 1'b0, snap_tog = 1'b0, wload_tog = 1'b0,
        calib_tog = 1'b0, bclr_tog = 1'b0;
    reg [7:0] log_skip_req = 8'd0;
    reg [5:0] log_page_req = 6'd0;
    reg log_tog = 1'b0;

    reg [1:0] ready_p = 2'b00;
    reg [2:0] rmove_p = 3'b000, rload_p = 3'b000, snap_p = 3'b000,
              wload_p = 3'b000, calib_p = 3'b000, bclr_p = 3'b000;
    reg [2:0] mode_p1 = 3'd0, mode_p = 3'd0;
    reg [7:0] gate_p1 = 8'd0, gate_p2 = 8'd0;
    reg [4:0] lat_p1 = 5'd12, lat_p2 = 5'd12;
    reg [2:0] rstep_p1 = 3'd0, rstep_p2 = 3'd0;
    reg [11:0] slip_p1 = 12'd0, slip_p2 = 12'd0;
    reg slip_en_p1 = 1'b0, slip_en_p2 = 1'b0;
    reg rv_en_p1 = 1'b0, rv_en_p2 = 1'b0;
    reg [4:0] bwin_p1 = 5'd0, bwin_p2 = 5'd0;
    reg [3:0] pat_p1 = 4'b1111, pat_p2 = 4'b1111;
    reg [7:0] dpat_p1 = 8'h1d;
    reg [11:0] sel_p1 = 12'd0;
    reg rdir_p1 = 1'b0;
    reg [3:0] mask_p1 = 4'b0000, mask_p2 = 4'b0000;
    reg [31:0] wstep_p1 = 32'd0;
    reg [31:0] calib_p1 = 32'd0, calib_p2 = 32'd0;
    reg [7:0] read_run_p1 = 8'd32, read_run_p2 = 8'd32;
    reg [7:0] read_gap_p1 = 8'd8, read_gap_p2 = 8'd8;
    reg [11:0] read_delay_p1 = {4{3'd3}}, read_delay_p2 = {4{3'd3}};
    reg [2:0] bank_p1 = 3'd0, bank_p2 = 3'd0;
    reg [14:0] row_p1 = 15'd0, row_p2 = 15'd0;
    reg [7:0] log_skip_p1 = 8'd0, log_skip_p2 = 8'd0;
    reg [5:0] log_page_p1 = 6'd0, log_page_p2 = 6'd0;
    reg [3:0] log_p = 4'b0000;
    always @(posedge pclk) begin
        ready_p <= {ready_p[0], ready};
        rmove_p <= {rmove_p[1:0], rmove_tog};
        rload_p <= {rload_p[1:0], rload_tog};
        snap_p <= {snap_p[1:0], snap_tog};
        wload_p <= {wload_p[1:0], wload_tog};
        calib_p <= {calib_p[1:0], calib_tog};
        bclr_p <= {bclr_p[1:0], bclr_tog};
        mode_p1 <= mode_req;            mode_p <= mode_p1;
        gate_p1 <= gate_req;            gate_p2 <= gate_p1;
        lat_p1 <= lat_req;              lat_p2 <= lat_p1;
        rstep_p1 <= rstep_req;          rstep_p2 <= rstep_p1;
        slip_p1 <= slip_req;            slip_p2 <= slip_p1;
        slip_en_p1 <= slip_en_req;      slip_en_p2 <= slip_en_p1;
        rv_en_p1 <= rv_en_req;          rv_en_p2 <= rv_en_p1;
        bwin_p1 <= bwin_req;            bwin_p2 <= bwin_p1;
        pat_p1 <= read_pat;             pat_p2 <= pat_p1;
        dpat_p1 <= pat_req;             dq_pat <= dpat_p1;
        sel_p1 <= rclksel_req;          rclksel <= sel_p1;
        rdir_p1 <= rdir_req;            rdir <= rdir_p1;
        mask_p1 <= rmove_mask;          mask_p2 <= mask_p1;
        wstep_p1 <= wstep_req;          wstep <= wstep_p1;
        calib_p1 <= calib_mask;         calib_p2 <= calib_p1;
        read_run_p1 <= read_run_req;      read_run_p2 <= read_run_p1;
        read_gap_p1 <= read_gap_req;      read_gap_p2 <= read_gap_p1;
        read_delay_p1 <= read_delay_req;  read_delay_p2 <= read_delay_p1;
        bank_p1 <= bank_req;            bank_p2 <= bank_p1;
        row_p1 <= row_req;              row_p2 <= row_p1;
        log_skip_p1 <= log_skip_req;    log_skip_p2 <= log_skip_p1;
        log_page_p1 <= log_page_req;    log_page_p2 <= log_page_p1;
        log_p <= {log_p[2:0], log_tog};
    end
    wire ready_pc = ready_p[1];
    wire rmove_pulse = rmove_p[2] ^ rmove_p[1];
    wire rload_pulse = rload_p[2] ^ rload_p[1];
    wire snap_pulse = snap_p[2] ^ snap_p[1];
    wire wload_pulse = wload_p[2] ^ wload_p[1];
    wire calib_pulse = calib_p[2] ^ calib_p[1];
    wire bclr_tog_pulse = bclr_p[2] ^ bclr_p[1];
    // the page number changes with the toggle; the pulse comes a PCLK after
    // the toggle's own synchronizer, so the number has settled in log_page_p2
    wire log_go_pulse = log_p[3] ^ log_p[2];
    // the clear is seen in PCLK, where the counters live
    reg bclr_d = 1'b0;
    wire bclr_pulse = bclr_tog_pulse || bclr_d;
    always @(posedge pclk)
        bclr_d <= bclr_tog_pulse;

    // ------------------------------------------------------------------
    // DDR3 initialization and the four modes, PCLK
    // ------------------------------------------------------------------
    localparam [3:0] I_IDLE = 4'd0, I_RESET = 4'd1, I_CKE = 4'd2, I_XPR = 4'd3,
                     I_MR = 4'd4, I_ZQ = 4'd5, I_WAIT = 4'd6,
                     R_IDLE = 4'd8, R_LEVEL = 4'd9, R_WRITE = 4'd10, R_READ = 4'd11,
                     R_RAND = 4'd12;
    localparam [2:0] M_IDLE = 3'd0, M_LEVEL = 3'd1, M_WRITE = 3'd2, M_READ = 3'd3,
                     M_RAND = 3'd4;

    reg [3:0] istate = I_IDLE;
    reg [3:0] wnext = I_IDLE;
    reg [16:0] itimer = 17'd0;
    reg [16:0] wcount = 17'd0;
    reg [1:0] mr_idx = 2'd0;
    reg [2:0] mode = M_IDLE;
    reg [3:0] rload_cnt = 4'd0;
    reg [3:0] wload_cnt = 4'd0;
    reg [9:0] refi = 10'd0;
    reg [9:0] col = 10'd0;
    reg [3:0] step_no = 4'd0;           // position in an entry/exit/refresh script
    reg [15:0] rd_hist = 16'd0;         // the read stream, one bit per PCLK
    reg [7:0] read_count = 8'd0;
    reg [8:0] read_pipe = 9'd0;         // READs issued, one bit per PCLK
    reg read_active = 1'b1;
    reg [1:0] calib_cnt = 2'd0;
    // random mode: the access in flight and the address source
    reg [31:0] xs = 32'd1;
    reg [2:0] acc_bank = 3'd0;
    reg acc_rowbit = 1'b0;
    reg [6:0] acc_col = 7'd0;
    reg rc_issue = 1'b0;                // a READ leaves the core this cycle
    // the pause after a random READ: the access period, at least 8, less
    // the ACTIVATE-to-READ cycles and the pause's own two; set from the
    // link, so registered off the counter's path
    reg [16:0] rand_wait = 17'd3;
    always @(posedge pclk)
        rand_wait <= (read_gap_p2 < 8'd8) ? 17'd3 : {9'd0, read_gap_p2} - 17'd5;
    localparam [31:0] XS_SEED = 32'h2545f491;

    function [31:0] xorshift(input [31:0] x);
        reg [31:0] y;
        begin
            y = x ^ (x << 13);
            y = y ^ (y >> 17);
            xorshift = y ^ (y << 5);
        end
    endfunction

    // The DQS gate of each READ: four memory clocks, k of them late.
    // READ[i] for i >= k follows this PCLK's delayed READ and for i < k the
    // previous PCLK's, so the window starts at clock k of the delayed PCLK.
    // Each lane has its own delay and k, as the proven controller's read_i.
    wire [15:0] gate_win;
    wire [3:0]  g_lane;
    genvar gl;
    generate
        for (gl = 0; gl < 4; gl = gl + 1) begin: lane_gate
            wire [2:0] d = read_delay_p2[3*gl +: 3];
            wire [1:0] k = gate_p2[2*gl +: 2];
            wire now = read_pipe[d];
            wire prev = read_pipe[d + 4'd1];
            assign g_lane[gl] = now;
            // bit 3, the latest clock, always follows this PCLK's READ
            assign gate_win[4*gl +: 4] = {now,
                                          k > 2'd2 ? prev : now,
                                          k > 2'd1 ? prev : now,
                                          k > 2'd0 ? prev : now};
        end
    endgenerate
    wire g_now = g_lane[0];     // the stream bookkeeping follows lane 0

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
        rc_issue <= 1'b0;
        read_pipe <= {read_pipe[7:0], 1'b0};
        read_en <= (mode == M_READ || mode == M_RAND) ? ({4{pat_p2}} & gate_win) : 16'd0;
        if (read_count == 8'd0) begin
            read_active <= 1'b1;
            read_count <= read_run_p2;
        end else if (read_count == 8'd1) begin
            read_active <= !read_active;
            read_count <= read_active ? read_gap_p2 : read_run_p2;
        end else begin
            read_count <= read_count - 8'd1;
        end
        if (calib_pulse)
            calib_cnt <= 2'd2;
        else if (calib_cnt != 2'd0)
            calib_cnt <= calib_cnt - 2'd1;
        calib <= (calib_cnt != 2'd0) ? calib_p2 : 32'd0;
        rd_hist <= {rd_hist[14:0], mode == M_READ && g_now};

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

        // the interval runs through the pauses a running state takes, or a
        // mode that spends most of its time in them would outrun tREFI
        if ((istate >= R_IDLE || (istate == I_WAIT && wnext >= R_IDLE)) && refi != 10'h3ff)
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
            read_pipe <= 9'd0;
            read_count <= 8'd0;
            read_active <= 1'b1;
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
                        xs <= XS_SEED;
                        istate <= mode_p == M_LEVEL ? R_LEVEL :
                                  mode_p == M_WRITE ? R_WRITE :
                                  mode_p == M_READ ? R_READ : R_RAND;
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
                        4'd3: begin
                            read_en <= 16'hffff;
                            if (mode_p != M_LEVEL) begin
                                dqs_drive <= 1'b0;
                                step_no <= 4'd4;
                                pause(17'd4, R_LEVEL);
                            end
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
                            issue(C_ACT, bank_p2, {1'b0, row_p2});
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
                            end else if (istate == R_WRITE || read_active) begin
                                issue(istate == R_WRITE ? C_WR : C_RD, bank_p2, {6'd0, col});
                                col <= col + 10'd8;
                                if (istate == R_READ) begin
                                    read_pipe[0] <= 1'b1;
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

                // closed-page single READs: ACTIVATE, READ with
                // auto-precharge three PCLK later (tRCD), the next access
                // `spacing` PCLK after the ACTIVATE -- past tRAS, tRTP, tRP
                // and tRC, and one ACTIVATE in 8 PCLK keeps tRRD and tFAW
                R_RAND: begin
                    if (step_no == 4'd0) begin
                        if (mode_p != mode) begin
                            mode <= M_IDLE;
                            istate <= R_IDLE;
                        end else if (refi >= TREFI) begin
                            issue(C_REF, 3'd0, 16'h0000);
                            refi <= 10'd0;
                            pause(17'd30, R_RAND);              // tRFC
                        end else begin
                            acc_bank <= xs[2:0];
                            acc_rowbit <= xs[3];
                            acc_col <= xs[10:4];
                            issue(C_ACT, xs[2:0], {1'b0, row_p2[14:1], xs[3]});
                            step_no <= 4'd1;
                            pause(17'd1, R_RAND);               // READ 3 PCLK on
                        end
                    end else begin
                        // A10 high: auto-precharge
                        issue(C_RD, acc_bank, {5'd0, 1'b1, acc_col, 3'b000});
                        read_pipe[0] <= 1'b1;
                        rc_issue <= 1'b1;
                        xs <= xorshift(xs);
                        step_no <= 4'd0;
                        pause(rand_wait, R_RAND);
                    end
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
    reg [255:0] dq_r2 = 256'd0;
    reg [255:0] dq_r3 = 256'd0;
    reg [255:0] dq_r4 = 256'd0;         // the word ra_data was aligned from
    reg [3:0]   rvalid_r = 4'd0;        // rvalid beside dq_r, for rd_align
    // rd_align's own copy of dq_r: merged with the core's, one register
    // would feed both from wherever it lands
    (* syn_preserve = 1, keep = 1 *) reg [255:0] dq_ra = 256'd0;
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
        dq_r2 <= dq_r;
        dq_r3 <= dq_r2;
        dq_r4 <= dq_r3;
        rvalid_r <= rvalid;
        dq_ra <= dq_q;
        eligible <= (mode == M_READ) && (&rd_hist);
        for (r = 0; r < 8; r = r + 1)
            pat_rot[8 * r +: 8] <= (dq_pat << r) | (dq_pat >> (8 - r));
        if (snap_pulse || eligible)
            snap <= dq_r4;
        for (l = 0; l < 4; l = l + 1) begin
            w0 = dq_r[64 * l +: 8];
            if (mode == M_LEVEL) begin
                ok = rvalid[l] && (w0 == 8'hff);
            end else if (mode == M_READ) begin
                rot = 1'b0;
                for (r = 0; r < 8; r = r + 1)
                    rot = rot || (w0 == pat_rot[8 * r +: 8]);
                ok = eligible && rvalid[l] && rot;
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
    // The trained read-valid boundary, PCLK
    // ------------------------------------------------------------------
    wire [255:0] ra_data;
    wire [11:0]  ra_rot, ra_phase;
    wire [3:0]   ra_trained, ra_err, ra_drift, ra_phase_ok;
    wire [15:0]  ra_relocks;
    wire         ra_valid, ra_ok, ra_pat_ok;
    reg          arm_tog = 1'b0, ra_arm = 1'b0, mode_read_d = 1'b0;
    reg  [2:0]   arm_p = 3'b000;

    // arm on entering read mode, on every CALIB pulse (framing may have
    // moved) and on command 0x23; never on a silent hint
    always @(posedge pclk) begin
        arm_p <= {arm_p[1:0], arm_tog};
        mode_read_d <= (mode == M_READ);
        ra_arm <= !ready_pc || ((mode == M_READ) && !mode_read_d) ||
                  (arm_p[2] ^ arm_p[1]) || calib_pulse;
    end

    rd_align align (
        .pclk(pclk), .rst(!ready_pc), .stream(eligible),
        .dq_q(dq_ra), .rvalid(rvalid_r), .pat(dq_pat), .arm(ra_arm),
        .trained(ra_trained), .rot(ra_rot), .data(ra_data), .valid(ra_valid),
        .ok(ra_ok), .err(ra_err), .drift(ra_drift), .pat_ok(ra_pat_ok),
        .phase(ra_phase), .phase_ok(ra_phase_ok), .relocks(ra_relocks));

    // ------------------------------------------------------------------
    // The single-burst checker, PCLK
    // ------------------------------------------------------------------
    wire         rc_locked, rc_fail;
    wire [11:0]  rc_expect, rc_last_rot, rc_fail_rot;
    wire [3:0]   rc_last_cls, rc_fail_lanes;
    wire [31:0]  rc_total, rc_good, rc_class, rc_moves;
    wire [15:0]  rc_hist_n;
    wire [511:0] rc_hist;
    wire [7:0]   rc_fail_pat;
    wire [10:0]  rc_fail_addr;
    wire [255:0] rc_fail_words;
    wire [31:0]  rc_n_both, rc_n_only11, rc_n_only19, rc_n_other;
    wire [127:0] rc_pos_range;
    wire [15:0]  rc_pos_cls;
    wire [31:0]  rc_lag_eval;
    wire [1279:0] rc_lag_cnt;
    wire [10:0]  rc_log_n;
    wire [1151:0] rc_log_buf;
    wire [5:0]   rc_log_page;
    reg          rc_arm = 1'b0, mode_rand_d = 1'b0;
    // the refresh phase for rd_check's statistics, one PCLK late: a copy, so
    // the checker's compares do not load the refresh counter's own path
    reg  [9:0]   refi_rc = 10'd0;
    always @(posedge pclk)
        refi_rc <= refi;
    always @(posedge pclk) begin
        mode_rand_d <= (mode == M_RAND);
        rc_arm <= !ready_pc || ((mode == M_RAND) && !mode_rand_d) || (arm_p[2] ^ arm_p[1]);
    end

    rd_check check (
        .pclk(pclk), .rst(!ready_pc), .arm(rc_arm), .dq_q(dq_q),
        .rvalid(rvalid), .rv_enable(rv_en_p2),
        .issue(rc_issue), .issue_idx({acc_rowbit, acc_bank}), .issue_col(acc_col),
        .lat(lat_p2), .step(rstep_p2), .slip_enable(slip_en_p2), .slip(slip_p2),
        .refi(refi_rc),
        .log_skip(log_skip_p2), .log_page(log_page_p2), .log_go(log_go_pulse),
        .log_n(rc_log_n), .log_buf(rc_log_buf), .log_buf_page(rc_log_page),
        .n_both(rc_n_both), .n_only11(rc_n_only11), .n_only19(rc_n_only19),
        .n_other(rc_n_other), .pos_range(rc_pos_range), .pos_cls(rc_pos_cls),
        .lag_eval(rc_lag_eval), .lag_cnt(rc_lag_cnt),
        .locked(rc_locked), .expect_rot(rc_expect), .last_rot(rc_last_rot),
        .last_cls(rc_last_cls), .total(rc_total), .good(rc_good), .class_ok(rc_class),
        .rot_moves(rc_moves), .hist_n(rc_hist_n), .hist(rc_hist),
        .fail_seen(rc_fail), .fail_lanes(rc_fail_lanes), .fail_pat(rc_fail_pat),
        .fail_addr(rc_fail_addr), .fail_rot(rc_fail_rot), .fail_words(rc_fail_words));

    // ------------------------------------------------------------------
    // RBURST as a level, the way the proven controller samples it
    // ------------------------------------------------------------------
    // Its per-lane read calibration takes RBURST high only when it is high
    // at a PCLK rising edge and at two consecutive falling edges (TOOL-033).
    // Here that level is counted per lane for every PCLK of random mode
    // since rd_check's arm, beside the number of cycles counted.
    reg  [3:0]   rb_pos = 4'd0, rb_neg = 4'd0, rb_neg_r = 4'd0, rb_lvl = 4'd0;
    reg  [127:0] rb_cnt = 128'd0;       // lane n at [32n +: 32]
    reg  [127:0] rv_cnt = 128'd0;       // RVALID high, lane n at [32n +: 32]
    reg  [3:0]   rv_r = 4'd0;
    // The proven controller's read calibration passes a lane only with one
    // RVALID-high cycle and one RBURST pulse per READ (TOOL-036); a pulse is
    // a falling edge of the level above, counted as its rburst_cnt counts it.
    reg  [127:0] rb_fall = 128'd0;      // RBURST pulses, lane n at [32n +: 32]
    reg  [31:0]  tr_reads = 32'd0;      // READs issued while counting
    wire [3:0]   rb_t = rb_pos & rb_neg & rb_neg_r;
    reg  [31:0]  rb_cyc = 32'd0;
    reg          rb_on = 1'b0;
    integer      rbl;
    always @(negedge pclk) begin
        rb_neg <= rburst;
        rb_neg_r <= rb_neg;
    end
    always @(posedge pclk) begin
        rb_pos <= rburst;
        rb_lvl <= rb_pos & rb_neg & rb_neg_r;
        rv_r <= rvalid;
        rb_on <= (mode == M_RAND);
        if (rc_arm) begin
            rb_cnt <= 128'd0;
            rv_cnt <= 128'd0;
            rb_fall <= 128'd0;
            tr_reads <= 32'd0;
            rb_cyc <= 32'd0;
        end else if (rb_on) begin
            rb_cyc <= rb_cyc + 32'd1;
            if (rc_issue)
                tr_reads <= tr_reads + 32'd1;
            for (rbl = 0; rbl < 4; rbl = rbl + 1) begin
                if (rb_lvl[rbl])
                    rb_cnt[32*rbl +: 32] <= rb_cnt[32*rbl +: 32] + 32'd1;
                if (rv_r[rbl])
                    rv_cnt[32*rbl +: 32] <= rv_cnt[32*rbl +: 32] + 32'd1;
                if (rb_lvl[rbl] && !rb_t[rbl])
                    rb_fall[32*rbl +: 32] <= rb_fall[32*rbl +: 32] + 32'd1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Phase dynamics, PCLK: how the read stream's word rotation moves
    // ------------------------------------------------------------------
    // rd_align normalises a rotation it has locked, but the rotation itself
    // is only observable cycle by cycle, and a host poll of the status frame
    // is hundreds of microseconds apart -- far coarser than the events.  This
    // counts the moves here instead, and separates a move seen mid-stream
    // from one seen at the first live cycle after a gated gap.
    reg [11:0] ph_prev = 12'd0;
    reg [15:0] chg_total = 16'd0, chg_gap = 16'd0, delta_last = 16'd0;
    reg [15:0] last_change = 16'd0;
    reg [2:0]  step0 = 3'd0, step1 = 3'd0, step2 = 3'd0, step3 = 3'd0;
    reg        skew_changed = 1'b0, stream_d = 1'b0, moved_d = 1'b0;
    always @(posedge pclk) begin
        stream_d <= eligible;
        // the lanes' steps are compared the cycle after they are recorded
        moved_d <= !ra_arm && eligible && (&ra_phase_ok) && (ra_phase != ph_prev);
        if (moved_d && (step0 != step1 || step0 != step2 || step0 != step3))
            skew_changed <= 1'b1;
        if (ra_arm) begin
            chg_total <= 16'd0;
            chg_gap <= 16'd0;
            delta_last <= 16'd0;
            step0 <= 3'd0; step1 <= 3'd0; step2 <= 3'd0; step3 <= 3'd0;
            skew_changed <= 1'b0;
            ph_prev <= 12'd0;
        end else if (eligible && (&ra_phase_ok) && (ra_phase != ph_prev)) begin
            chg_total <= chg_total + 16'd1;
            if (!stream_d)
                chg_gap <= chg_gap + 16'd1;
            delta_last <= pclk_cnt - last_change;
            last_change <= pclk_cnt;
            step0 <= ra_phase[2:0]  - ph_prev[2:0];
            step1 <= ra_phase[5:3]  - ph_prev[5:3];
            step2 <= ra_phase[8:6]  - ph_prev[8:6];
            step3 <= ra_phase[11:9] - ph_prev[11:9];
            ph_prev <= ra_phase;
        end else if (eligible && (&ra_phase_ok)) begin
            ph_prev <= ra_phase;
        end
    end

    reg [255:0] al_snap = 256'd0;
    reg [15:0]  al_good = 16'd0, al_good_last = 16'd0;
    reg [15:0]  al_seen = 16'd0, al_seen_last = 16'd0;

    // the aligned snapshot and the raw snapshot must describe one word, so
    // both latch on the same condition: rd_align takes dq_ra, a copy of
    // dq_r, which arrives
    // off the IDES8_MEM outputs a cycle earlier, and presents
    // ra_data = aligned(dq_r4)
    always @(posedge pclk) begin
        if (snap_pulse || eligible)
            al_snap <= ra_data;
        if (pclk_cnt == 16'hffff) begin
            al_good_last <= al_good;
            al_good <= 16'd0;
            al_seen_last <= al_seen;
            al_seen <= 16'd0;
        end else begin
            al_good <= al_good + {15'd0, ra_ok};
            al_seen <= al_seen + {15'd0, ra_valid};
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
    reg [8:0] st_s1 = 9'd0, st_s2 = 9'd0;
    reg [255:0] al_snap_s1 = 256'd0, al_snap_s2 = 256'd0;
    reg [15:0] al_good_s1 = 16'd0, al_good_s2 = 16'd0;
    reg [15:0] al_seen_s1 = 16'd0, al_seen_s2 = 16'd0;
    reg [11:0] ra_rot_s1 = 12'd0, ra_rot_s2 = 12'd0;
    reg [3:0] ra_trained_s1 = 4'd0, ra_trained_s2 = 4'd0;
    reg [3:0] ra_err_s1 = 4'd0, ra_err_s2 = 4'd0;
    reg [3:0] ra_drift_s1 = 4'd0, ra_drift_s2 = 4'd0;
    reg ra_pat_ok_s1 = 1'b0, ra_pat_ok_s2 = 1'b0;
    reg [11:0] ra_phase_s1 = 12'd0, ra_phase_s2 = 12'd0;
    reg [3:0] ra_phase_ok_s1 = 4'd0, ra_phase_ok_s2 = 4'd0;
    reg [15:0] chg_total_s1 = 16'd0, chg_total_s2 = 16'd0;
    reg [15:0] chg_gap_s1 = 16'd0, chg_gap_s2 = 16'd0;
    reg [15:0] delta_last_s1 = 16'd0, delta_last_s2 = 16'd0;
    reg [2:0] step0_s1 = 3'd0, step0_s2 = 3'd0, step1_s1 = 3'd0, step1_s2 = 3'd0;
    reg [2:0] step2_s1 = 3'd0, step2_s2 = 3'd0, step3_s1 = 3'd0, step3_s2 = 3'd0;
    reg skew_s1 = 1'b0, skew_s2 = 1'b0;
    reg [15:0] relocks_s1 = 16'd0, relocks_s2 = 16'd0;
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
        al_snap_s1 <= al_snap;          al_snap_s2 <= al_snap_s1;
        al_good_s1 <= al_good_last;     al_good_s2 <= al_good_s1;
        al_seen_s1 <= al_seen_last;     al_seen_s2 <= al_seen_s1;
        ra_rot_s1 <= ra_rot;            ra_rot_s2 <= ra_rot_s1;
        ra_trained_s1 <= ra_trained;    ra_trained_s2 <= ra_trained_s1;
        ra_err_s1 <= ra_err;            ra_err_s2 <= ra_err_s1;
        ra_drift_s1 <= ra_drift;        ra_drift_s2 <= ra_drift_s1;
        ra_pat_ok_s1 <= ra_pat_ok;      ra_pat_ok_s2 <= ra_pat_ok_s1;
        ra_phase_s1 <= ra_phase;        ra_phase_s2 <= ra_phase_s1;
        ra_phase_ok_s1 <= ra_phase_ok;  ra_phase_ok_s2 <= ra_phase_ok_s1;
        chg_total_s1 <= chg_total;      chg_total_s2 <= chg_total_s1;
        chg_gap_s1 <= chg_gap;          chg_gap_s2 <= chg_gap_s1;
        delta_last_s1 <= delta_last;    delta_last_s2 <= delta_last_s1;
        step0_s1 <= step0;              step0_s2 <= step0_s1;
        step1_s1 <= step1;              step1_s2 <= step1_s1;
        step2_s1 <= step2;              step2_s2 <= step2_s1;
        step3_s1 <= step3;              step3_s2 <= step3_s1;
        skew_s1 <= skew_changed;        skew_s2 <= skew_s1;
        relocks_s1 <= ra_relocks;       relocks_s2 <= relocks_s1;
    end

    // The memory clock toggles one bit per RBURST edge; counting happens
    // here, where a wide incrementer costs a fifth of the clock rate.
    // An 8-bit count over a host-timed interval cannot tell a rare edge
    // from one per burst, which wraps it every 256 PCLK; command 0x24 n
    // therefore counts for exactly 2^n PCLK, saturating, and holds.
    reg [3:0]  btog_1 = 4'd0, btog_2 = 4'd0;
    reg [31:0] bcnt = 32'd0;            // per lane, 8 bits
    reg [23:0] bwin_cnt = 24'd0, bwin_last = 24'd0;
    reg        bwin_on = 1'b0, bwin_sat = 1'b0;
    integer    bl;
    always @(posedge pclk) begin
        bwin_last <= (24'd1 << bwin_p2) - 24'd1;
        btog_1 <= burst_tog;
        btog_2 <= btog_1;
        if (bclr_pulse) begin
            bcnt <= 32'd0;
            bwin_cnt <= 24'd0;
            bwin_sat <= (bwin_p2 != 5'd0);
            bwin_on <= (bwin_p2 != 5'd0);
        end else begin
            if (bwin_on) begin
                bwin_cnt <= bwin_cnt + 24'd1;
                if (bwin_cnt == bwin_last)
                    bwin_on <= 1'b0;
            end
            for (bl = 0; bl < 4; bl = bl + 1)
                if (btog_2[bl] != btog_1[bl] && (bwin_on || !bwin_sat) &&
                    !(bwin_sat && bcnt[8*bl +: 8] == 8'hff))
                    bcnt[8*bl +: 8] <= bcnt[8*bl +: 8] + 8'd1;
        end
    end

    reg [3:0]  bseen_s1 = 4'd0, bseen_s2 = 4'd0;
    reg        bwin_s1 = 1'b0, bwin_s2 = 1'b0;
    reg [31:0] bcnt_s1 = 32'd0, bcnt_s2 = 32'd0;
    always @(posedge sys_clk) begin
        bseen_s1 <= {bcnt[7:0] != 8'd0, bcnt[15:8] != 8'd0,
                     bcnt[23:16] != 8'd0, bcnt[31:24] != 8'd0};
        bseen_s2 <= bseen_s1;
        bwin_s1 <= bwin_on;     bwin_s2 <= bwin_s1;
        bcnt_s1 <= bcnt;   bcnt_s2 <= bcnt_s1;
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

    wire [1015:0] status = {
        bcnt_s2[31:24],                                         // 126
        bcnt_s2[23:16],                                         // 125
        bcnt_s2[15:8],                                          // 124
        bcnt_s2[7:0],                                           // 123
        {bwin_s2, 3'b000, bseen_s2},                            // 122
        relocks_s2,                                             // 120..121
        {ra_phase_ok_s2, ra_phase_s2[11:8]},                    // 119
        ra_phase_s2[7:0],                                       // 118
        {2'b00, step3_s2, step2_s2},                            // 117
        {skew_s2, 1'b0, step1_s2, step0_s2},                    // 116
        delta_last_s2,                                          // 114..115
        chg_gap_s2,                                             // 112..113
        chg_total_s2,                                           // 110..111
        al_snap_s2,                                             // 78..109
        8'h00,                                                  // 77
        al_seen_s2,                                             // 75..76
        {4'b0000, ra_err_s2},                                   // 74
        {4'b0000, ra_drift_s2},                                 // 73
        {4'b0000, ra_rot_s2[11:8]},                             // 72
        ra_rot_s2[7:0],                                         // 71
        al_good_s2,                                             // 69..70
        {1'b0, ra_pat_ok_s2, 2'b00, ra_trained_s2},             // 68
        snap_s2,
        lane_bytes(lane_s2, good_s2, wstep_req, moves, 3),
        lane_bytes(lane_s2, good_s2, wstep_req, moves, 2),
        lane_bytes(lane_s2, good_s2, wstep_req, moves, 1),
        lane_bytes(lane_s2, good_s2, wstep_req, moves, 0),
        read_run_req, 5'd0, rclksel_req[2:0],
        elig_s2, pclk_s2, free_cnt,
        pat_req,
        st_s2[5:4], st_s2[6], 1'b0, st_s2[3:0],
        step_s2,
        ready, pll_ok, lock_ok, lock_seen, st_s2[8], st_s2[7], 2'b00
    };

    // the checker's counters are static once random mode is left, which is
    // when the host reads them; one flop here and the frame make two
    reg          rc_locked_s = 1'b0, rc_fail_s = 1'b0, rand_s = 1'b0;
    reg [11:0]   rc_expect_s = 12'd0, rc_last_rot_s = 12'd0, rc_fail_rot_s = 12'd0;
    reg [3:0]    rc_last_cls_s = 4'd0, rc_fail_lanes_s = 4'd0;
    reg [31:0]   rc_total_s = 32'd0, rc_good_s = 32'd0, rc_class_s = 32'd0, rc_moves_s = 32'd0;
    reg [15:0]   rc_hist_n_s = 16'd0;
    reg [511:0]  rc_hist_s = 512'd0;
    reg [7:0]    rc_fail_pat_s = 8'd0;
    reg [10:0]   rc_fail_addr_s = 11'd0;
    reg [255:0]  rc_fail_words_s = 256'd0;
    always @(posedge sys_clk) begin
        rc_locked_s <= rc_locked;           rc_fail_s <= rc_fail;
        rand_s <= (mode == M_RAND);
        rc_expect_s <= rc_expect;           rc_last_rot_s <= rc_last_rot;
        rc_fail_rot_s <= rc_fail_rot;       rc_last_cls_s <= rc_last_cls;
        rc_fail_lanes_s <= rc_fail_lanes;   rc_total_s <= rc_total;
        rc_good_s <= rc_good;               rc_class_s <= rc_class;
        rc_moves_s <= rc_moves;             rc_hist_n_s <= rc_hist_n;
        rc_hist_s <= rc_hist;               rc_fail_pat_s <= rc_fail_pat;
        rc_fail_addr_s <= rc_fail_addr;     rc_fail_words_s <= rc_fail_words;
    end

    wire [1015:0] status2 = {
        {4'b0000, rc_fail_rot_s},                               // 125..126
        rc_fail_words_s,                                        // 93..124
        rc_hist_s,                                              // 29..92
        {4'b0000, rc_last_cls_s},                               // 28
        {5'b00000, rc_fail_addr_s},                             // 26..27
        rc_fail_pat_s,                                          // 25
        {rc_fail_s, 3'b000, rc_fail_lanes_s},                   // 24
        {4'b0000, rc_last_rot_s},                               // 22..23
        {4'b0000, rc_expect_s},                                 // 20..21
        rc_hist_n_s,                                            // 18..19
        rc_moves_s,                                             // 14..17
        rc_class_s,                                             // 10..13
        rc_good_s,                                              // 6..9
        rc_total_s,                                             // 2..5
        {3'b000, lat_req},                                      // 1
        {rc_locked_s, rand_s, gate_req[1:0], 1'b0, rstep_req}   // 0
    };

    // Burst position (command 0x2B), 34 payload bytes: which of the two known
    // capture offsets held each isolated READ, and the refresh phase at the
    // check that decided it.  Little-endian, byte 0 in the low bits.
    //    0-3   READs that matched at both 11 and 19
    //    4-7   at 11 only        8-11  at 19 only        12-15 at neither
    //   16-31  min,max of the refresh phase for each of the four classes,
    //          in the order both, only11, only19, other
    //   32-33  the last eight classes, 2 bits each, newest at [1:0]
    wire [271:0] status3 = {
        rc_pos_cls,                                             // 32..33
        rc_pos_range[127:112], rc_pos_range[111:96],            // 30..31, 28..29
        rc_pos_range[95:80],   rc_pos_range[79:64],              // 26..27, 24..25
        rc_pos_range[63:48],   rc_pos_range[47:32],              // 22..23, 20..21
        rc_pos_range[31:16],   rc_pos_range[15:0],               // 18..19, 16..17
        rc_n_other, rc_n_only19, rc_n_only11, rc_n_both         // 12..15, 8..11, 4..7, 0..3
    };

    // Lag, RBURST level and RVALID (command 0x2F), 206 payload bytes, static once
    // random mode is left.  Little-endian, byte 0 in the low bits.
    //    0-3     READs classified: nine distinct recent patterns
    //    4+40l+4k  lane l, lag k: the lane held the pattern of the READ k
    //            before (k = 0 its own, up to 8), k = 9 none of the nine
    //  164+4l    lane l's PCLK cycles with RBURST high as a level
    //  180-183   random-mode PCLK cycles those were counted over
    //  184-185   per-lane READ gating delay, lane n at [3n +: 3]
    //  186       per-lane READ gate offset, lane n at [2n +: 2]
    //  187-188   per-lane RCLKSEL, lane n at [3n +: 3]
    //  189+4l    lane l's PCLK cycles with RVALID high
    //  205       {7'b0, RVALID-held capture enabled (command 0x29)}
    // Until 2026-10-25 the classifier named three earlier READs and this
    // frame was 126 bytes, with every field from RBURST on 80 bytes lower.
    reg [31:0]  rc_lag_eval_s = 32'd0, rb_cyc_s = 32'd0;
    reg [1279:0] rc_lag_cnt_s = 1280'd0;
    reg [127:0] rb_cnt_s = 128'd0, rv_cnt_s = 128'd0;
    always @(posedge sys_clk) begin
        rc_lag_eval_s <= rc_lag_eval;   rc_lag_cnt_s <= rc_lag_cnt;
        rb_cnt_s <= rb_cnt;             rb_cyc_s <= rb_cyc;
        rv_cnt_s <= rv_cnt;
    end
    wire [1647:0] status4 = {
        {7'd0, rv_en_req},                                      // 205
        rv_cnt_s,                                               // 189..204
        {4'b0000, rclksel_req},                                 // 187..188
        gate_req,                                               // 186
        {4'b0000, read_delay_req},                              // 184..185
        rb_cyc_s,                                               // 180..183
        rb_cnt_s,                                               // 164..179
        rc_lag_cnt_s,                                           // 4..163
        rc_lag_eval_s                                           // 0..3
    };

    // Read-training counters (command 0x31), 40 payload bytes, static once
    // random mode is left.  Little-endian, byte 0 in the low bits.
    //    0-3     READs issued in random mode since the arm
    //    4-7     random-mode PCLK counted
    //    8+4l    lane l's PCLK with RVALID high
    //   24+4l    lane l's RBURST pulses
    reg [127:0] rb_fall_s = 128'd0;
    reg [31:0]  tr_reads_s = 32'd0;
    always @(posedge sys_clk) begin
        rb_fall_s <= rb_fall;           tr_reads_s <= tr_reads;
    end
    wire [319:0] status5 = {rb_fall_s, rv_cnt_s, rb_cyc_s, tr_reads_s};

    // READ log page (command 0x34), 148 payload bytes, static once random
    // mode is left and the copy (command 0x33) has finished, a few PCLK
    // after it.  Little-endian, byte 0 in the low bits.
    //    0-1     entries logged since the arm, up to 1024
    //    2       the page copied, 0 to 63
    //    3       the READs passed over before the log, in 1024s (command 0x32)
    //    4+9e    entry e of the page, the log entry 16 page + e, 72 bits as
    //            laid out in rd_check.v
    reg [10:0]   rc_log_n_s = 11'd0;
    reg [1151:0] rc_log_buf_s = 1152'd0;
    reg [5:0]    rc_log_page_s = 6'd0;
    always @(posedge sys_clk) begin
        rc_log_n_s <= rc_log_n;         rc_log_buf_s <= rc_log_buf;
        rc_log_page_s <= rc_log_page;
    end
    wire [1183:0] status6 = {rc_log_buf_s, log_skip_req, {2'b00, rc_log_page_s},
                             {5'd0, rc_log_n_s}};

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
    reg [7:0] response_type = 8'h04;    // frame type byte
    reg [7:0] response_len = 8'h7f;     // payload bytes
    reg [7:0] response_index = 8'd0;
    reg [1647:0] frame = 1648'd0;      // the longest frame, 0x2F's

    function known;
        input [7:0] c;
        begin
            known = (c == 8'h01) || (c == 8'h03) || (c == 8'h04) || (c == 8'h05) ||
                    (c == 8'h06) || (c == 8'h07) || (c == 8'h08) || (c == 8'h09) ||
                    (c == 8'h0a) ||
                    (c == 8'h0b) || (c == 8'h0c) || (c == 8'h0d) || (c == 8'h0e) ||
                    (c == 8'h0f) || (c[7:2] == 6'b000100) || (c == 8'h20) ||
                    (c == 8'h21) || (c == 8'h22) || (c == 8'h23) || (c == 8'h24) ||
                    (c == 8'h25) || (c == 8'h26) || (c == 8'h27) || (c == 8'h28) ||
                    (c == 8'h29) || (c == 8'h2a) || (c == 8'h2b) || (c == 8'h2c) || (c == 8'h2d) ||
                    (c == 8'h2e) || (c == 8'h2f) || (c == 8'h31) || (c == 8'h32) ||
                    (c == 8'h33) || (c == 8'h34);
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
                        response_is_status <= (cmd_byte == 8'h03) || (cmd_byte == 8'h27) ||
                                              (cmd_byte == 8'h2b) || (cmd_byte == 8'h2f) ||
                                              (cmd_byte == 8'h31) || (cmd_byte == 8'h34);
                        response_type <= (cmd_byte == 8'h27) ? 8'h05 :
                                         (cmd_byte == 8'h2b) ? 8'h00 :
                                         (cmd_byte == 8'h2f) ? 8'h06 :
                                         (cmd_byte == 8'h31) ? 8'h07 :
                                         (cmd_byte == 8'h34) ? 8'h08 : 8'h04;
                        response_len <= (cmd_byte == 8'h2b) ? 8'd34 :
                                        (cmd_byte == 8'h2f) ? 8'd206 :
                                        (cmd_byte == 8'h31) ? 8'd40 :
                                        (cmd_byte == 8'h34) ? 8'd148 : 8'd127;
                        response_index <= 8'd0;
                        frame <= (cmd_byte == 8'h27) ? {632'd0, status2} :
                                 (cmd_byte == 8'h2b) ? {1376'd0, status3} :
                                 (cmd_byte == 8'h2f) ? status4 :
                                 (cmd_byte == 8'h31) ? {1328'd0, status5} :
                                 (cmd_byte == 8'h34) ? {464'd0, status6} : {632'd0, status};
                        case (cmd_byte)
                            8'h04: snap_tog <= ~snap_tog;
                            8'h05: begin
                                restart <= 1'b1;
                                mode_req <= 3'd0;
                                moves <= 32'd0;
                            end
                            8'h06: rclksel_req <= {4{rx_data[2:0]}};
                            8'h07: begin
                                rdir_req <= rx_data[0];
                                rmove_mask <= rx_data[7:4];
                                rmove_tog <= ~rmove_tog;
                                for (m = 0; m < 4; m = m + 1)
                                    if (rx_data[4 + m])
                                        moves[8 * m +: 8] <= rx_data[0] ? moves[8 * m +: 8] + 8'd1
                                                                         : moves[8 * m +: 8] - 8'd1;
                            end
                            8'h08: begin
                                calib_mask <= 32'b1 << rx_data[4:0];
                                calib_tog <= ~calib_tog;
                            end
                            8'h09: read_gap_req <= rx_data == 8'd0 ? 8'd1 : rx_data;
                            8'h0a: begin
                                rload_tog <= ~rload_tog;
                                moves <= 32'd0;
                            end
                            8'h0b: read_pat <= rx_data[3:0];
                            8'h0c: mode_req <= rx_data[2:0] > 3'd4 ? 3'd0 : rx_data[2:0];
                            8'h0d: read_run_req <= rx_data == 8'd0 ? 8'd1 : rx_data;
                            8'h0e: pat_req <= rx_data;
                            8'h0f: bank_req <= rx_data[2:0];
                            8'h20: row_req[7:0] <= rx_data;
                            8'h21: row_req[14:8] <= rx_data[6:0];
                            8'h22: read_delay_req <= {4{rx_data[2:0]}};
                            8'h23: arm_tog <= ~arm_tog;
                            8'h24: begin
                                bwin_req <= rx_data > 8'd23 ? 5'd23 : rx_data[4:0];
                                bclr_tog <= ~bclr_tog;
                            end
                            8'h25: gate_req <= {4{rx_data[1:0]}};
                            8'h2c: read_delay_req[3 * rx_data[7:6] +: 3] <= rx_data[2:0];
                            8'h2d: gate_req[2 * rx_data[7:6] +: 2] <= rx_data[1:0];
                            8'h2e: rclksel_req[3 * rx_data[7:6] +: 3] <= rx_data[2:0];
                            8'h29: rv_en_req <= rx_data[0];
                            8'h32: log_skip_req <= rx_data;
                            8'h33: begin
                                log_page_req <= rx_data[5:0];
                                log_tog <= ~log_tog;
                            end
                            8'h26: lat_req <= rx_data[4:0];
                            8'h28: rstep_req <= rx_data[2:0];
                            8'h2a: begin
                                slip_req[3 * rx_data[4:3] +: 3] <= rx_data[2:0];
                                slip_en_req <= rx_data[7];
                            end
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
                    8'd0: tx_data <= 8'haa;
                    8'd1: tx_data <= 8'h00;
                    8'd2: tx_data <= response_type;
                    8'd3: tx_data <= response_len;
                    default: begin
                        tx_data <= frame[7:0];
                        frame <= frame >> 8;
                    end
                endcase
            end else begin
                case (response_index)
                    8'd0: tx_data <= 8'haa;
                    8'd1: tx_data <= 8'h00;
                    8'd2: tx_data <= 8'h02;
                    8'd3: tx_data <= 8'h01;
                    default: tx_data <= 8'h56; // "V" for TinyVCMI.
                endcase
            end
            tx_send <= 1'b1;
            if (response_index == (response_is_status ? response_len + 8'd3 : 8'd4))
                response_active <= 1'b0;
            else
                response_index <= response_index + 8'd1;
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
