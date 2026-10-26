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
//   0C m      mode m[2:0]; 6 and 7 are idle
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
//   36 v      the fill's write data, d = v[6:4] whole PCLK and b = v[2:0] beats
//             later than its earliest place, which is a PCLK ahead of its WRITE
//             (TOOL-043)
//   38 v      v[0] = 1 runs the read and write training in hardware, v[0] = 0
//             aborts it; while it runs the link may only read (TOOL-044)
//   39        the training's result, 40 payload bytes (see status7)
//   37 v      v[0]: address data in random mode -- bank, four row bits and the
//             burst from the address source, and rd_check expects each READ's
//             pattern from its whole address, as the fill writes it
//   35 v      HOLD on the lanes in v[3:0]: for 4 x (v[7:4] + 1) PCLK, or with
//             v[7:4] = 15 until the next 0x35, so the host can change a
//             lane's settings inside it as the proven controller changes
//             RCLKSEL inside its 11-PCLK HOLD on unconfigured lanes (TOOL-042);
//             every 0x35 ends the previous one, and one naming no lane
//             releases them all
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
module wr_core #(
    // nonzero: train once the PHY is up, up to three times, and on success
    // hand the bus to the controller (mode 6), as fpga/ddr3_ctrl does
    parameter integer AUTOTRAIN = 0
) (
    input  wire         sys_clk,
    input  wire         uart_rx,
    output wire         uart_tx,

    input  wire         pll_lock,
    output reg          pll_en = 1'b1,
    output reg          dll_rst = 1'b1,
    output reg          updncntl = 1'b1,
    output wire [3:0]   hold,       // per lane DQS HOLD: the start-up update or command 0x35
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
    output reg  [15:0]  addr = 16'd0,

    // the controller of fpga/ddr3_ctrl: its READ loading into the command
    // registers at this PCLK edge, so the trained gate opens for it; that it
    // owns the bus (mode 6); the trained write alignment {d, 0, b} and read
    // rotations; a byte from the link (command 0x3C) and the controller's
    // status (frame 0x3D).  The controller accepts a training only with the
    // write alignment its PHY is built for.  The diagnostic image ties the
    // inputs off.
    input  wire         ctrl_rd,
    input  wire         ctrl_accept,    // sys_clk: the controller can take this training
    output reg          ctrl_own = 1'b0,
    output wire [6:0]   ctrl_walign,
    output wire [11:0]  ctrl_rot,
    output wire         ctrl_trained,
    output reg  [7:0]   ext_cmd = 8'd0,
    output reg          ext_tog = 1'b0,
    input  wire [511:0] ext_status
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
    // the start-up sequence's HOLD, on every lane, around the DLL update
    reg hold_upd = 1'b0;
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
            hold_upd <= 1'b0;
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
                    if (mtimer == 15'd0) hold_upd <= 1'b1;
                    if (mtimer == 15'd4) updncntl <= 1'b0;
                    if (mtimer == 15'd8) updncntl <= 1'b1;
                    if (mtimer == 15'd12) begin
                        hold_upd <= 1'b0;
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
    reg [6:0] walign_req = 7'd0;        // {d[2:0], 1'b0, b[2:0]}
    reg adata_req = 1'b0;
    reg [3:0] hold_mask_req = 4'd0;
    reg [3:0] hold_len_req = 4'd0;
    reg hold_tog = 1'b0;
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
    reg [6:0] walign_p1 = 7'd0, walign_p2 = 7'd0;
    reg adata_p1 = 1'b0, adata_p2 = 1'b0;
    reg [3:0] hold_mask_p1 = 4'd0, hold_mask_p2 = 4'd0;
    reg [3:0] hold_len_p1 = 4'd0, hold_len_p2 = 4'd0;
    reg [3:0] hold_p = 4'b0000;
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
        dpat_p1 <= pat_req;
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
        hold_mask_p1 <= hold_mask_req;  hold_mask_p2 <= hold_mask_p1;
        walign_p1 <= walign_req;        walign_p2 <= walign_p1;
        adata_p1 <= adata_req;          adata_p2 <= adata_p1;
        hold_len_p1 <= hold_len_req;    hold_len_p2 <= hold_len_p1;
        hold_p <= {hold_p[2:0], hold_tog};
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
    // HOLD on command 0x35, in PCLK as the proven controller drives it; the
    // mask and length settle a PCLK before the pulse, as the log page does
    wire hold_go = hold_p[3] ^ hold_p[2];
    reg  [3:0] hold_lanes = 4'd0;
    reg  [6:0] hold_cnt = 7'd0;
    always @(posedge pclk) begin
        if (hold_go) begin
            hold_lanes <= hold_mask_p2;
            // code 15 holds until the next command: no count
            hold_cnt <= (hold_len_p2 == 4'd15) ? 7'd0 : {hold_len_p2, 2'b00} + 7'd4;
        end else if (hold_cnt != 7'd0) begin
            hold_cnt <= hold_cnt - 7'd1;
            if (hold_cnt == 7'd1)
                hold_lanes <= 4'd0;
        end
    end
    // both terms come from flops, so the OR adds no edge to the update's HOLD
    assign hold = {4{hold_upd}} | hold_lanes;
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
                     R_RAND = 4'd12, R_FILL = 4'd13, R_CTRL = 4'd14;
    localparam [2:0] M_IDLE = 3'd0, M_LEVEL = 3'd1, M_WRITE = 3'd2, M_READ = 3'd3,
                     M_RAND = 3'd4, M_FILL = 3'd5, M_CTRL = 3'd6;

    reg [3:0] istate = I_IDLE;
    reg [3:0] wnext = I_IDLE;
    reg [16:0] itimer = 17'd0;
    reg [16:0] wcount = 17'd0;
    reg [1:0] mr_idx = 2'd0;
    reg [2:0] mode = M_IDLE;
    // The mode request's compares, registered: in front of every pause they
    // put the Gowin control 1.25 ns short of PCLK.  A mode is entered through
    // a one-PCLK pause, so mode_chg has caught up with it before it is read.
    reg mode_chg = 1'b0, mode_go = 1'b0, mode_lvl_off = 1'b0;
    reg [3:0] mode_next = 4'd12;
    always @(posedge pclk) begin
        mode_chg <= (mode_p != mode);
        mode_go <= (mode_p != M_IDLE);
        mode_lvl_off <= (mode_p != M_LEVEL);
        mode_next <= (mode_p == M_LEVEL) ? R_LEVEL :
                     (mode_p == M_WRITE) ? R_WRITE :
                     (mode_p == M_READ) ? R_READ :
                     (mode_p == M_FILL) ? R_FILL :
                     (mode_p == M_CTRL) ? R_CTRL : R_RAND;
    end
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
    reg [3:0] acc_row4 = 4'd0;          // with address data, the row's low four bits
    reg [7:0] acc_exp = 8'd0;           // and the pattern the fill wrote there
    reg rc_issue = 1'b0;                // a READ leaves the core this cycle

    // Address data (TOOL-043): every burst of the fill region, banks 0..7,
    // rows {row[14:4], 0..15}, bursts 0..127, carries one of the thirty
    // aperiodic 8-bit necklaces, as its least rotation, picked by a fold of
    // its address; even DQ carry it and odd DQ its inverse, as every write
    // here does.  tools/ddr3_write_probe.py carries the same table and fold.
    function [7:0] apat(input [4:0] i);
        case (i)
            5'd0:  apat = 8'h01; 5'd1:  apat = 8'h03; 5'd2:  apat = 8'h05; 5'd3:  apat = 8'h07;
            5'd4:  apat = 8'h09; 5'd5:  apat = 8'h0b; 5'd6:  apat = 8'h0d; 5'd7:  apat = 8'h0f;
            5'd8:  apat = 8'h13; 5'd9:  apat = 8'h15; 5'd10: apat = 8'h17; 5'd11: apat = 8'h19;
            5'd12: apat = 8'h1b; 5'd13: apat = 8'h1d; 5'd14: apat = 8'h1f; 5'd15: apat = 8'h25;
            5'd16: apat = 8'h27; 5'd17: apat = 8'h2b; 5'd18: apat = 8'h2d; 5'd19: apat = 8'h2f;
            5'd20: apat = 8'h35; 5'd21: apat = 8'h37; 5'd22: apat = 8'h3b; 5'd23: apat = 8'h3d;
            5'd24: apat = 8'h3f; 5'd25: apat = 8'h57; 5'd26: apat = 8'h5b; 5'd27: apat = 8'h5f;
            5'd28: apat = 8'h6f; 5'd29: apat = 8'h7f; 5'd30: apat = 8'h0b; default: apat = 8'h13;
        endcase
    endfunction
    function [7:0] adata(input [2:0] b, input [3:0] r, input [6:0] c);
        reg [13:0] x;
        begin
            x = {c, r, b};
            adata = apat(x[4:0] ^ x[9:5] ^ {1'b0, x[13:10]} ^ {x[1:0], x[13:11]});
        end
    endfunction

    // the fill's position, and the word each of its WRITEs carries, delayed
    // d PCLK and b beats on the way to the serializers (command 0x36).  The
    // word is set a PCLK before its WRITE goes out (fill_wr), and word 0 is
    // that newest one: at d = 0 the data reaches the serializers two PCLK
    // ahead of where a delay line behind the command would put it, which a
    // first search on the board showed the write path needs (TOOL-043).
    reg [2:0] fb = 3'd0;                // bank
    reg [3:0] fr = 4'd0;                // row's low bits
    reg [6:0] fc = 7'd0;                // burst
    reg [7:0] wq_in = 8'd0;
    reg [63:0] wq = 64'd0;              // word k + 1 at [8k +: 8]
    reg fill_wr = 1'b0;                 // the WRITE of the word set last PCLK
    reg [2:0] fill_wr_b = 3'd0;
    reg [6:0] fill_wr_c = 7'd0;
    wire [2:0] wa_d = walign_p2[6:4];
    wire [2:0] wa_b = walign_p2[2:0];
    wire [79:0] wq_all = {wq, wq_in, 8'd0};       // word k at [8k + 8 +: 8]
    // beats b..7 carry the burst starting in this word, 0..b-1 the one before
    wire [15:0] wq_pair = {wq_all[8 * wa_d + 8 +: 8], wq_all[8 * wa_d + 16 +: 8]};
    wire [7:0] wq_out = wq_pair >> (5'd8 - {2'b00, wa_b});
    always @(posedge pclk) begin
        wq <= {wq[55:0], wq_in};
        // the serializers' pattern: the fill's words in fill mode, else P
        dq_pat <= (mode == M_FILL) ? wq_out : dpat_p1;
    end
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
    // The refresh compares, registered: in front of the command address they
    // cost the Gowin control.  Every REFRESH is followed by a pause of at
    // least 30 PCLK, so the flags have caught up before they are read again.
    reg refi_due = 1'b0, refi_due_fill = 1'b0;
    always @(posedge pclk) begin
        refi_due <= (refi >= TREFI);
        refi_due_fill <= (refi >= TREFI - 10'd160);
    end

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
        wq_in <= 8'd0;                  // a fill WRITE sets its word
        fill_wr <= 1'b0;
        if (fill_wr)                    // a PCLK after its word
            issue(C_WR, fill_wr_b, {6'd0, fill_wr_c, 3'b000});
        itimer <= itimer + 17'd1;
        rmove <= rmove_pulse ? mask_p2 : 4'b0000;
        rc_issue <= 1'b0;
        read_pipe <= {read_pipe[7:0], 1'b0};
        if (mode == M_CTRL && ctrl_rd)  // the controller's READ, as one of ours
            read_pipe[0] <= 1'b1;
        read_en <= (mode == M_READ || mode == M_RAND || mode == M_CTRL) ?
                   ({4{pat_p2}} & gate_win) : 16'd0;
        // the bus is the controller's from the PCLK after R_CTRL is entered
        // until the edge that leaves it, which precharges every bank
        ctrl_own <= (istate == R_CTRL) && !mode_chg;
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
                    if (refi_due) begin
                        issue(C_REF, 3'd0, 16'h0000);
                        refi <= 10'd0;
                        pause(17'd30, R_IDLE);                  // tRFC 260 ns
                    end else if (mode_go) begin
                        mode <= mode_p;
                        xs <= XS_SEED;
                        // through a PCLK so mode_chg compares with the new mode
                        pause(17'd1, mode_next);
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
                            if (mode_lvl_off) begin
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
                            if (mode_chg || refi_due) begin
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
                            if (mode_chg) begin
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
                        if (mode_chg) begin
                            mode <= M_IDLE;
                            istate <= R_IDLE;
                        end else if (refi_due) begin
                            issue(C_REF, 3'd0, 16'h0000);
                            refi <= 10'd0;
                            pause(17'd30, R_RAND);              // tRFC
                        end else if (adata_p2) begin
                            // the fill's region and the pattern it wrote here
                            acc_bank <= xs[2:0];
                            acc_rowbit <= xs[3];
                            acc_row4 <= xs[6:3];
                            acc_col <= xs[13:7];
                            acc_exp <= adata(xs[2:0], xs[6:3], xs[13:7]);
                            issue(C_ACT, xs[2:0], {1'b0, row_p2[14:4], xs[6:3]});
                            step_no <= 4'd1;
                            pause(17'd1, R_RAND);
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
                // fill: every row of the region in turn, ACTIVATE, 128 back
                // to back WRITEs each with its address's pattern, PRECHARGE,
                // a refresh between rows when one is due, and round again
                // until the mode changes; the bus is driven throughout, as in
                // write mode
                R_FILL: begin
                    case (step_no)
                        4'd0: begin
                            odt <= 1'b1;
                            dq_drive <= 1'b1;
                            dqs_drive <= 1'b1;
                            fb <= 3'd0;
                            fr <= 4'd0;
                            step_no <= 4'd1;
                            pause(17'd8, R_FILL);               // the bus settles
                        end
                        4'd1: begin
                            if (mode_chg) begin
                                dq_drive <= 1'b0;
                                dqs_drive <= 1'b0;
                                odt <= 1'b0;
                                step_no <= 4'd4;
                                pause(17'd4, R_FILL);
                            end else if (refi_due_fill) begin
                                // a row takes about 150 PCLK and refreshes
                                // wait for its end, so one is due a row early
                                issue(C_REF, 3'd0, 16'h0000);
                                refi <= 10'd0;
                                pause(17'd30, R_FILL);          // tRFC
                            end else begin
                                issue(C_ACT, fb, {1'b0, row_p2[14:4], fr});
                                fc <= 7'd0;
                                step_no <= 4'd2;
                                pause(17'd8, R_FILL);           // tRCD
                            end
                        end
                        4'd2: begin
                            fill_wr <= 1'b1;
                            fill_wr_b <= fb;
                            fill_wr_c <= fc;
                            wq_in <= adata(fb, fr, fc);
                            fc <= fc + 7'd1;
                            if (fc == 7'd127) begin
                                step_no <= 4'd3;
                                pause(17'd8, R_FILL);           // the last WRITE, tWR, the burst tail
                            end
                        end
                        4'd3: begin
                            issue(C_PRE, 3'd0, 16'h0400);       // all banks
                            fr <= fr + 4'd1;
                            if (fr == 4'd15)
                                fb <= fb + 3'd1;
                            step_no <= 4'd1;
                            pause(17'd4, R_FILL);               // tRP
                        end
                        default: begin
                            mode <= M_IDLE;
                            istate <= R_IDLE;
                        end
                    endcase
                end
                // the controller's: nothing is issued here, not even a
                // REFRESH, until the mode changes; then every bank is
                // precharged and the core is idle again
                R_CTRL: if (mode_chg) begin
                    issue(C_PRE, 3'd0, 16'h0400);       // all banks
                    mode <= M_IDLE;
                    pause(17'd4, R_IDLE);               // tRP
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
    reg [3:0] hit = 4'b0000;            // a lane's match, two cycles after its words
    // the match's parts, registered before they are combined: the rotation
    // search and the pin check in one cycle put the Gowin control 0.47 ns
    // short of PCLK
    reg [3:0] h_rot = 4'b0000, h_pins = 4'b0000, h_lvl = 4'b0000;
    reg h_read = 1'b0, h_level = 1'b0;
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
        h_level <= (mode == M_LEVEL);
        h_read <= (mode == M_READ) && eligible;
        for (l = 0; l < 4; l = l + 1) begin
            w0 = dq_r[64 * l +: 8];
            rot = 1'b0;
            for (r = 0; r < 8; r = r + 1)
                rot = rot || (w0 == pat_rot[8 * r +: 8]);
            ok = 1'b1;
            for (k = 1; k < 8; k = k + 1)
                ok = ok && (dq_r[64 * l + 8 * k +: 8] == (k % 2 == 1 ? ~w0 : w0));
            h_rot[l] <= rvalid[l] && rot;
            h_pins[l] <= ok;
            h_lvl[l] <= rvalid[l] && (w0 == 8'hff);
            hit[l] <= h_level ? h_lvl[l] : (h_read && h_rot[l] && h_pins[l]);
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
        .exp_sel(adata_p2), .issue_exp(acc_exp), .issue_rhi(acc_row4[3:1]),
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
    // a pulse's end, from the registered level and registered before it is
    // counted: rb_t comes off the falling-edge flops, which left half a PCLK
    // for its compare into all 128 counter enables in the Gowin control
    reg  [3:0]   rb_lvl_d = 4'd0, rb_fev = 4'd0;
    integer      rbl;
    always @(negedge pclk) begin
        rb_neg <= rburst;
        rb_neg_r <= rb_neg;
    end
    always @(posedge pclk) begin
        rb_pos <= rburst;
        rb_lvl <= rb_pos & rb_neg & rb_neg_r;
        rb_lvl_d <= rb_lvl;
        rb_fev <= rb_lvl_d & ~rb_lvl;
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
                if (rb_fev[rbl])
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
    // A move is registered as an event with the values it compares, and the
    // counters update from those a PCLK later: the compare in front of all
    // their enables put the Gowin control 0.38 ns short of PCLK.
    reg        ph_ev = 1'b0, ph_gap = 1'b0;
    reg [11:0] ph_new = 12'd0, ph_old = 12'd0;
    reg [15:0] ph_cnt = 16'd0;
    always @(posedge pclk) begin
        stream_d <= eligible;
        ph_ev <= !ra_arm && eligible && (&ra_phase_ok) && (ra_phase != ph_prev);
        ph_new <= ra_phase;
        ph_old <= ph_prev;
        ph_gap <= !stream_d;
        ph_cnt <= pclk_cnt;
        // the lanes' steps are compared the cycle after they are recorded
        moved_d <= ph_ev;
        if (moved_d && (step0 != step1 || step0 != step2 || step0 != step3))
            skew_changed <= 1'b1;
        if (ra_arm)
            ph_prev <= 12'd0;
        else if (eligible && (&ra_phase_ok))
            ph_prev <= ra_phase;
        if (ra_arm) begin
            chg_total <= 16'd0;
            chg_gap <= 16'd0;
            delta_last <= 16'd0;
            step0 <= 3'd0; step1 <= 3'd0; step2 <= 3'd0; step3 <= 3'd0;
            skew_changed <= 1'b0;
        end else if (ph_ev) begin
            chg_total <= chg_total + 16'd1;
            if (ph_gap)
                chg_gap <= chg_gap + 16'd1;
            delta_last <= ph_cnt - last_change;
            last_change <= ph_cnt;
            step0 <= ph_new[2:0]  - ph_old[2:0];
            step1 <= ph_new[5:3]  - ph_old[5:3];
            step2 <= ph_new[8:6]  - ph_old[8:6];
            step3 <= ph_new[11:9] - ph_old[11:9];
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

    // ------------------------------------------------------------------
    // The training in hardware (command 0x38 v: v[0] 1 starts, 0 aborts)
    // ------------------------------------------------------------------
    // The data check per lane: READs whose lane held their own pattern among
    // those the lag classifier counts (nine distinct recent patterns, about
    // 6% of READs), against how many it counted, taken from the existing
    // counters.  The placement failures once blamed on edits to rd_check were
    // nextpnr's attempt-budget overflow (TOOL-044).
    wire [127:0] seq_lane_own = {rc_lag_cnt_s[32*30 +: 32], rc_lag_cnt_s[32*20 +: 32],
                                 rc_lag_cnt_s[32*10 +: 32], rc_lag_cnt_s[0 +: 32]};
    reg  seq_start = 1'b0, seq_abort = 1'b0, seq_ack = 1'b0;
    reg  [1:0] auto_tries = 2'd0;       // AUTOTRAIN: trainings redone after a failure
    reg  auto_wait = 1'b0, auto_done = 1'b0;
    wire seq_busy, seq_done, seq_req, seq_wfound;
    wire [7:0] seq_cmd, seq_arg;
    wire [3:0] seq_err, seq_locked, seq_centred;
    wire [5:0] seq_phase, seq_walign;
    wire [31:0] seq_lane_set, seq_lane_u, seq_fin_total, seq_fin_class, seq_cycles;
    wire [15:0] seq_lane_cal, seq_tried;
    wire [63:0] seq_wpass;
    wire [11:0] seq_rot;
    wire [255:0] seq_diag;
    ddr3_seq seq (
        .clk(sys_clk), .start(seq_start && ready), .abort(seq_abort),
        .busy(seq_busy), .done(seq_done), .err(seq_err), .phase(seq_phase),
        .req(seq_req), .cmd(seq_cmd), .arg(seq_arg), .ack(seq_ack),
        .st(st_s2), .step(step_s2), .snap(snap_s2), .tr_reads(tr_reads_s),
        .rv_cnt(rv_cnt_s), .rb_fall(rb_fall_s), .rc_total(rc_total_s), .rc_class(rc_class_s),
        .lag_eval(rc_lag_eval_s), .lane_own(seq_lane_own), .last_rot(rc_last_rot_s),
        .locked(seq_locked), .lane_set(seq_lane_set), .lane_cal(seq_lane_cal),
        .lane_u(seq_lane_u), .centred(seq_centred), .wpass(seq_wpass), .walign(seq_walign),
        .wfound(seq_wfound), .rot(seq_rot), .fin_total(seq_fin_total),
        .fin_class(seq_fin_class), .tried(seq_tried), .cycles(seq_cycles), .diag(seq_diag));
    assign ctrl_walign = walign_p2;
    assign ctrl_rot = seq_rot;
    assign ctrl_trained = seq_done && (seq_err == 4'd0) && !seq_busy;

    // Training result (command 0x39), 72 payload bytes, little-endian.
    //    0     {done, busy, 2'b0, err[3:0]}  (err 1/2 framing, 3 no write
    //          alignment, 15 aborted)
    //    1     the sequencer's state, for progress
    //    2     {centred[3:0], locked[3:0]}
    //    3     {write alignment found, 1'b0, alignment 8d + b}
    //    4+l   lane l's lock {d[2:0], k[1:0], RCLKSEL[2:0]}
    //    8-9   lane l's CALIB pulses at its gate, at [4l +: 4]
    //   10+l   lane l's passing taps above tap 4
    //   14-15  the lanes' read rotations at the write alignment, [3l +: 3]
    //   16-23  the write alignments that passed, bit 8d + b
    //   24-27  READs checked at the chosen alignment   28-31 all four lanes right
    //   32-33  trials in the read search
    //   34-37  sys_clk cycles since the start
    //   38-39  0
    //   40+8l  lane l over the search before it locked, 16 bits each: trials
    //          that passed, trials in the vendor's state whose data failed,
    //          the fewest READs not its own in one of those, and the READs
    //          counted in that one
    wire [575:0] status7 = {seq_diag, 16'd0, seq_cycles, seq_tried, seq_fin_class, seq_fin_total,
                            seq_wpass, {4'd0, seq_rot}, seq_lane_u, seq_lane_cal,
                            seq_lane_set, {seq_wfound, 1'b0, seq_walign},
                            {seq_centred, seq_locked}, {2'd0, seq_phase},
                            {seq_done, seq_busy, 2'b00, seq_err}};

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
                    (c == 8'h33) || (c == 8'h34) || (c == 8'h35) || (c == 8'h36) ||
                    (c == 8'h37) || (c == 8'h38) || (c == 8'h39) || (c == 8'h3c) ||
                    (c == 8'h3d);
        end
    endfunction

    integer m;
    // A command's effect, from the link or from the training sequencer
    task exec_cmd(input [7:0] c, input [7:0] a);
        begin
                case (c)
                    8'h04: snap_tog <= ~snap_tog;
                    8'h05: begin
                        restart <= 1'b1;
                        mode_req <= 3'd0;
                        moves <= 32'd0;
                    end
                    8'h06: rclksel_req <= {4{a[2:0]}};
                    8'h07: begin
                        rdir_req <= a[0];
                        rmove_mask <= a[7:4];
                        rmove_tog <= ~rmove_tog;
                        for (m = 0; m < 4; m = m + 1)
                            if (a[4 + m])
                                moves[8 * m +: 8] <= a[0] ? moves[8 * m +: 8] + 8'd1
                                                                 : moves[8 * m +: 8] - 8'd1;
                    end
                    8'h08: begin
                        calib_mask <= 32'b1 << a[4:0];
                        calib_tog <= ~calib_tog;
                    end
                    8'h09: read_gap_req <= a == 8'd0 ? 8'd1 : a;
                    8'h0a: begin
                        rload_tog <= ~rload_tog;
                        moves <= 32'd0;
                    end
                    8'h0b: read_pat <= a[3:0];
                    8'h0c: mode_req <= a[2:0] > 3'd6 ? 3'd0 : a[2:0];
                    8'h3c: begin
                        ext_cmd <= a;
                        ext_tog <= ~ext_tog;
                    end
                    8'h0d: read_run_req <= a == 8'd0 ? 8'd1 : a;
                    8'h0e: pat_req <= a;
                    8'h0f: bank_req <= a[2:0];
                    8'h20: row_req[7:0] <= a;
                    8'h21: row_req[14:8] <= a[6:0];
                    8'h22: read_delay_req <= {4{a[2:0]}};
                    8'h23: arm_tog <= ~arm_tog;
                    8'h24: begin
                        bwin_req <= a > 8'd23 ? 5'd23 : a[4:0];
                        bclr_tog <= ~bclr_tog;
                    end
                    8'h25: gate_req <= {4{a[1:0]}};
                    8'h2c: read_delay_req[3 * a[7:6] +: 3] <= a[2:0];
                    8'h2d: gate_req[2 * a[7:6] +: 2] <= a[1:0];
                    8'h2e: rclksel_req[3 * a[7:6] +: 3] <= a[2:0];
                    8'h29: rv_en_req <= a[0];
                    8'h32: log_skip_req <= a;
                    8'h36: walign_req <= {a[6:4], 1'b0, a[2:0]};
                    8'h37: adata_req <= a[0];
                    8'h35: begin
                        hold_mask_req <= a[3:0];
                        hold_len_req <= a[7:4];
                        hold_tog <= ~hold_tog;
                    end
                    8'h33: begin
                        log_page_req <= a[5:0];
                        log_tog <= ~log_tog;
                    end
                    8'h26: lat_req <= a[4:0];
                    8'h28: rstep_req <= a[2:0];
                    8'h2a: begin
                        slip_req[3 * a[4:3] +: 3] <= a[2:0];
                        slip_en_req <= a[7];
                    end
                    default: if (c[7:2] == 6'b000100) begin
                        wstep_req[8 * c[1:0] +: 8] <= a;
                        wload_tog <= ~wload_tog;
                    end
                endcase
        end
    endtask

    // the requests the link may still make while the sequencer runs: reads
    function readonly;
        input [7:0] c;
        readonly = (c == 8'h01) || (c == 8'h03) || (c == 8'h27) || (c == 8'h2b) ||
                   (c == 8'h2f) || (c == 8'h31) || (c == 8'h34) || (c == 8'h39) ||
                   (c == 8'h3d);
    endfunction

    always @(posedge sys_clk) begin
        tx_send <= 1'b0;
        restart <= 1'b0;
        seq_start <= 1'b0;
        seq_abort <= 1'b0;
        // AUTOTRAIN: train once the PHY is up, again after a failure up to
        // three times in all, and on success request mode 6 if the
        // controller accepts the training; ahead of the link below, so a
        // command from the host still wins
        if (AUTOTRAIN != 0) begin
            if (!ready) begin
                auto_tries <= 2'd0;
                auto_wait <= 1'b0;
                auto_done <= 1'b0;
            end else if (!auto_done && !seq_busy && !seq_start) begin
                if (!auto_wait) begin
                    seq_start <= 1'b1;
                    auto_wait <= 1'b1;
                end else if (seq_done) begin
                    if (seq_err == 4'd0) begin
                        if (ctrl_accept)
                            mode_req <= 3'd6;
                        auto_done <= 1'b1;
                    end else if (auto_tries == 2'd2)
                        auto_done <= 1'b1;
                    else begin
                        auto_tries <= auto_tries + 2'd1;
                        seq_start <= 1'b1;
                    end
                end
            end
        end
        // the sequencer's requests, in a cycle the link is not using
        seq_ack <= 1'b0;
        if (seq_req && !seq_ack && !rx_valid) begin
            exec_cmd(seq_cmd, seq_arg);
            seq_ack <= 1'b1;
        end

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
                                              (cmd_byte == 8'h31) || (cmd_byte == 8'h34) ||
                                              (cmd_byte == 8'h39) || (cmd_byte == 8'h3d);
                        response_type <= (cmd_byte == 8'h27) ? 8'h05 :
                                         (cmd_byte == 8'h2b) ? 8'h00 :
                                         (cmd_byte == 8'h2f) ? 8'h06 :
                                         (cmd_byte == 8'h31) ? 8'h07 :
                                         (cmd_byte == 8'h34) ? 8'h08 :
                                         (cmd_byte == 8'h39) ? 8'h09 :
                                         (cmd_byte == 8'h3d) ? 8'h0a : 8'h04;
                        response_len <= (cmd_byte == 8'h2b) ? 8'd34 :
                                        (cmd_byte == 8'h2f) ? 8'd206 :
                                        (cmd_byte == 8'h31) ? 8'd40 :
                                        (cmd_byte == 8'h34) ? 8'd148 :
                                        (cmd_byte == 8'h39) ? 8'd72 :
                                        (cmd_byte == 8'h3d) ? 8'd64 : 8'd127;
                        response_index <= 8'd0;
                        frame <= (cmd_byte == 8'h27) ? {632'd0, status2} :
                                 (cmd_byte == 8'h2b) ? {1376'd0, status3} :
                                 (cmd_byte == 8'h2f) ? status4 :
                                 (cmd_byte == 8'h31) ? {1328'd0, status5} :
                                 (cmd_byte == 8'h34) ? {464'd0, status6} :
                                 (cmd_byte == 8'h39) ? {1072'd0, status7} :
                                 (cmd_byte == 8'h3d) ? {1136'd0, ext_status} : {632'd0, status};
                        if (cmd_byte == 8'h38) begin
                            seq_start <= rx_data[0];
                            seq_abort <= !rx_data[0];
                        end else if (!seq_busy || readonly(cmd_byte))
                            exec_cmd(cmd_byte, rx_data);
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

// The read and write training in hardware (TOOL-044): what
// tools/ddr3_write_probe.py train --vendor-delay --vendor-search --hold vendor
// --center --write-train does from the host, as (command, argument) pairs fed
// to wr_core's own decoder, judged from the same counters the host reads.
//
//   1. prewrite the sixteen rd_check rows, bank 0..7, row 0 and 1, each with
//      its pattern, streamed so the write alignment does not matter;
//   2. per-bit framing on a read stream of 0x0b: each lane's pins are pulsed
//      with CALIB until they agree with its first pin that holds a rotation
//      of the pattern (the probe takes the lanes' majority; any common framing
//      serves, since the search frames each lane as a whole);
//   3. the proven controller's start: RLOADN, then STEP - 4 RMOVE pulses at
//      RDIR = 1 on every lane, read tap 4 (TOOL-041);
//   4. its search (TOOL-036, TOOL-039, TOOL-042): gate positions 0..31 outer,
//      nine RCLKSEL sweeps each, every lane not yet locked held (HOLD) while
//      its settings change between trials, one CALIB pulse on its eight DQ
//      after each sweep that leaves it unlocked; a lane passes a setting with
//      one RVALID cycle and one RBURST pulse per READ, within two, and its
//      own pattern on every READ the lag classifier counts, and locks at its
//      second pass in a row;
//   5. centring: from tap 4 a locked lane is stepped up a tap at a time while
//      it passes, then set to the middle of the window from tap 0 to the last
//      passing tap, which needs no step past the bottom (TOOL-040, TOOL-041);
//   6. the fill's write alignment over d 0..7, b 0..7 with address data,
//      choosing the first of two passing neighbours (TOOL-043), and at it the
//      lanes' read rotations; the core is left filled, with address data on.
//
// Waits are in sys_clk cycles; the defaults are the probe's, shortened where
// a batch of random READs is long enough at about 6,500 READs.
module ddr3_seq #(
    parameter integer BATCH = 131072,   // random mode per trial, 2.6 ms
    parameter integer FILLW = 50000,    // fill mode per alignment, 1 ms
    parameter integer STREAMW = 100000, // a read stream settles, 2 ms
    parameter integer PWW = 1000,       // write mode per prewritten row, 20 us
    parameter integer CALW = 2500,      // after a framing CALIB pulse, 50 us
    parameter integer WARM = 50000,     // after a search trial's settings, before its READs, 1 ms
    parameter integer SETTLE = 16       // after any command, for its synchronizers
) (
    input  wire         clk,
    input  wire         start,          // one cycle: begin (ignored while busy)
    input  wire         abort,          // one cycle: stop where it is
    output reg          busy = 1'b0,
    output reg          done = 1'b0,
    output reg  [3:0]   err = 4'd0,     // 1/2 framing, 3 no write alignment, 15 aborted
    output reg  [5:0]   phase = 6'd0,   // the state, for progress
    // a request to wr_core's decoder, held until acknowledged
    output reg          req = 1'b0,
    output reg  [7:0]   cmd = 8'h00,
    output reg  [7:0]   arg = 8'h00,
    input  wire         ack,
    // what the host would read, sys_clk copies
    input  wire [8:0]   st,             // {cke, reset_n, mode[2:0], istate[3:0]}
    input  wire [7:0]   step,
    input  wire [255:0] snap,
    input  wire [31:0]  tr_reads,
    input  wire [127:0] rv_cnt,
    input  wire [127:0] rb_fall,
    input  wire [31:0]  rc_total,
    input  wire [31:0]  rc_class,
    input  wire [31:0]  lag_eval,       // READs the lag classifier counted
    input  wire [127:0] lane_own,       // lane l at [32l +: 32]: of those, its own pattern
    input  wire [11:0]  last_rot,
    // the result
    output reg  [3:0]   locked = 4'd0,
    output reg  [31:0]  lane_set = 32'd0,   // lane l at [8l +: 8]: {d[2:0], k[1:0], rclksel[2:0]}
    output reg  [15:0]  lane_cal = 16'd0,   // lane l at [4l +: 4]: CALIB pulses at its gate
    output reg  [31:0]  lane_u = 32'd0,     // lane l at [8l +: 8]: passing taps above tap 4
    output reg  [3:0]   centred = 4'd0,     // the lane passed where it was set
    output reg  [63:0]  wpass = 64'd0,      // alignment 8d + b passed
    output reg  [5:0]   walign = 6'd0,
    output reg          wfound = 1'b0,
    output reg  [11:0]  rot = 12'd0,
    output reg  [31:0]  fin_total = 32'd0,
    output reg  [31:0]  fin_class = 32'd0,
    output reg  [15:0]  tried = 16'd0,
    output reg  [31:0]  cycles = 32'd0,    // since start
    // why lanes did or did not lock, over the search's trials before each
    // lane locked; lane l at [64l +: 64], each field saturating at 0xFFFF:
    // {READs counted in the nearest miss, its READs not the lane's own,
    //  trials in the vendor's state whose data failed, trials that passed}
    output reg  [255:0] diag = 256'd0
);
    function [7:0] rcpat(input [3:0] i);
        case (i)
            4'd0:  rcpat = 8'h0b;  4'd1:  rcpat = 8'h0d;  4'd2:  rcpat = 8'h13;  4'd3:  rcpat = 8'h15;
            4'd4:  rcpat = 8'h17;  4'd5:  rcpat = 8'h19;  4'd6:  rcpat = 8'h1b;  4'd7:  rcpat = 8'h1d;
            4'd8:  rcpat = 8'h25;  4'd9:  rcpat = 8'h27;  4'd10: rcpat = 8'h2b;  4'd11: rcpat = 8'h2d;
            4'd12: rcpat = 8'h35;  4'd13: rcpat = 8'h37;  4'd14: rcpat = 8'h3b;  default: rcpat = 8'h57;
        endcase
    endfunction
    function isrot(input [7:0] w);      // a rotation of the framing pattern 0x0b
        integer r;
        begin
            isrot = 1'b0;
            for (r = 0; r < 8; r = r + 1)
                if (w == (((8'h0b << r) | (8'h0b >> (8 - r))) & 8'hff))
                    isrot = 1'b1;
        end
    endfunction
    function [31:0] adiff(input [31:0] a, input [31:0] b);
        adiff = (a > b) ? a - b : b - a;
    endfunction

    function [15:0] sat16(input [31:0] a);
        sat16 = (a > 32'd65535) ? 16'hffff : a[15:0];
    endfunction

    // per lane, the trial just read: in the vendor's state, one RVALID cycle
    // and one RBURST pulse per READ, and passing when at least 99% of the
    // READs the lag classifier counted were its own, the probe's lane_pass
    // rule; registered, the counters being still from S_B3 on
    reg [3:0]  vstate = 4'd0, pass_now = 4'd0;
    reg [63:0] miss = 64'd0;            // lane l at [16l +: 16]: READs not its own
    reg [31:0] pm;
    integer pl;
    always @(posedge clk)
        for (pl = 0; pl < 4; pl = pl + 1) begin
            pm = (lane_own[32*pl +: 32] < lag_eval) ? lag_eval - lane_own[32*pl +: 32] : 32'd0;
            vstate[pl] <= (tr_reads > 32'd100) && (lag_eval > 32'd50) &&
                          (adiff(rv_cnt[32*pl +: 32], tr_reads) <= 32'd2) &&
                          (adiff(rb_fall[32*pl +: 32], tr_reads) <= 32'd2);
            pass_now[pl] <= (tr_reads > 32'd100) && (lag_eval > 32'd50) &&
                            (adiff(rv_cnt[32*pl +: 32], tr_reads) <= 32'd2) &&
                            (adiff(rb_fall[32*pl +: 32], tr_reads) <= 32'd2) &&
                            ({16'd0, sat16(pm)} * 32'd100 <= lag_eval);
            miss[16*pl +: 16] <= sat16(pm);
        end
    wire wpass_now = (rc_total > 32'd100) && (rc_class == rc_total);

    // the snapshot's normalized word of lane li, pin pi: odd pins carry ~P.
    // A pin is framed against its lane's pin 0 in the same snapshot, not
    // against a fixed target, because the stream's word frame moves now and
    // then, uniformly over every pin (TOOL-023): pins pulsed to a target
    // chosen before a move end one memory clock or more off the rest.
    reg  [1:0] li = 2'd0;
    reg  [2:0] pi = 3'd0;
    wire [7:0] wsel = snap[64 * li + 8 * pi +: 8];
    wire [7:0] wnorm = pi[0] ? ~wsel : wsel;
    wire [7:0] wref = snap[64 * li +: 8];
    reg        tgt_ok;
    reg  [7:0] tgt_w;
    integer tp;
    reg [7:0] tw;
    always @(*) begin
        tgt_ok = 1'b0;
        tgt_w = 8'h00;
        for (tp = 7; tp >= 0; tp = tp - 1) begin
            tw = snap[64 * li + 8 * tp +: 8];
            if (tp % 2 == 1) tw = ~tw;
            if (isrot(tw)) begin
                tgt_ok = 1'b1;
                tgt_w = tw;
            end
        end
    end
    // per lane, its eight pins agree on a rotation of the framing pattern
    reg [3:0] agree;
    integer al, ap;
    always @(*)
        for (al = 0; al < 4; al = al + 1) begin
            agree[al] = isrot(snap[64 * al +: 8]);
            for (ap = 1; ap < 8; ap = ap + 1)
                if (((ap % 2 == 1) ? ~snap[64 * al + 8 * ap +: 8] : snap[64 * al + 8 * ap +: 8]) !=
                    snap[64 * al +: 8])
                    agree[al] = 1'b0;
        end

    localparam [5:0] S_IDLE = 6'd0, S_SEND = 6'd1, S_SENT = 6'd2, S_WAIT = 6'd3, S_MODEW = 6'd4,
                     S_B1 = 6'd5, S_B2 = 6'd6, S_B3 = 6'd7,
                     S_PW1 = 6'd8, S_PW2 = 6'd9, S_PW3 = 6'd10, S_PW4 = 6'd11, S_PW5 = 6'd12,
                     S_PW6 = 6'd13, S_PW7 = 6'd14, S_PW8 = 6'd15, S_PW9 = 6'd16,
                     S_AD1 = 6'd17, S_AD2 = 6'd18,
                     S_FR0 = 6'd19, S_FR1 = 6'd20, S_FR2 = 6'd21, S_FR4 = 6'd22, S_FR5 = 6'd23,
                     S_FR6 = 6'd24, S_FR8 = 6'd25,
                     S_ST0 = 6'd26, S_ST1 = 6'd27, S_ST2 = 6'd28, S_ST3 = 6'd29, S_ST4 = 6'd30,
                     S_T0 = 6'd31, S_T1 = 6'd32,
                     S_S1 = 6'd33, S_S3 = 6'd34, S_S5 = 6'd35, S_S6 = 6'd36, S_S7 = 6'd37,
                     S_S9 = 6'd38, S_S11 = 6'd39,
                     S_C1 = 6'd40, S_C2 = 6'd41, S_C3 = 6'd42, S_C4 = 6'd43, S_C5 = 6'd44,
                     S_C6 = 6'd45, S_C7 = 6'd46,
                     S_W0 = 6'd47, S_W1 = 6'd48, S_W2 = 6'd49, S_W3 = 6'd50, S_W4 = 6'd51,
                     S_W5 = 6'd52, S_W6 = 6'd53, S_W7 = 6'd54, S_W8 = 6'd55, S_W9 = 6'd56,
                     S_W10 = 6'd57, S_W11 = 6'd58, S_W12 = 6'd59, S_W13 = 6'd60,
                     S_FAIL = 6'd61, S_FIN = 6'd62;
    reg [5:0]  ret = S_IDLE, mret = S_IDLE, bret = S_IDLE;
    reg [23:0] wcnt = 24'd0;
    reg [2:0]  mtgt = 3'd0;
    reg [4:0]  pw = 5'd0;               // prewrite row
    reg [4:0]  pc = 5'd0;               // framing pulses on this pin
    reg [1:0]  ftry = 2'd0;             // framing passes redone after a failed check
    reg [2:0]  vcnt = 3'd0;             // framing checks passed
    reg [7:0]  tcnt = 8'd0;
    reg [4:0]  pos = 5'd0;
    reg [3:0]  cal = 4'd0;
    reg [2:0]  rs = 3'd0;
    reg [1:0]  sub = 2'd0;
    reg [3:0]  prev = 4'd0;
    reg [7:0]  u = 8'd0;
    reg [7:0]  cnt = 8'd0;
    reg [6:0]  widx = 7'd0;
    reg        up_failed = 1'b0;
    reg [5:0]  state = S_IDLE;          // declared before the tasks that set it

    task go_send(input [7:0] c, input [7:0] a, input [5:0] r);
        begin
            cmd <= c;
            arg <= a;
            ret <= r;
            phase <= r;
            state <= S_SEND;
        end
    endtask
    task go_mode(input [2:0] m, input [5:0] r);
        begin
            mtgt <= m;
            mret <= r;
            go_send(8'h0c, {5'd0, m}, S_MODEW);
        end
    endtask
    task go_wait(input [23:0] n, input [5:0] r);
        begin
            wcnt <= n;
            ret <= r;
            state <= S_WAIT;
        end
    endtask
    task go_batch(input [5:0] r);
        begin
            bret <= r;
            go_mode(3'd4, S_B1);
        end
    endtask

    reg [3:0] nl;
    integer q;
    always @(posedge clk) begin
        if (busy)
            cycles <= cycles + 32'd1;
        if (abort && busy) begin
            err <= 4'd15;
            req <= 1'b0;
            go_mode(3'd0, S_FAIL);
        end else case (state)
            S_IDLE: if (start) begin
                busy <= 1'b1;
                done <= 1'b0;
                err <= 4'd0;
                locked <= 4'd0;
                centred <= 4'd0;
                lane_set <= 32'd0;
                lane_cal <= 16'd0;
                lane_u <= 32'd0;
                wpass <= 64'd0;
                wfound <= 1'b0;
                tried <= 16'd0;
                cycles <= 32'd0;
                diag <= {4{16'd0, 16'hffff, 16'd0, 16'd0}};
                pw <= 5'd0;
                go_mode(3'd0, S_PW2);
            end
            // ---- the subroutines
            S_SEND: begin
                req <= 1'b1;
                if (ack) begin
                    req <= 1'b0;
                    wcnt <= SETTLE;
                    state <= S_SENT;
                end
            end
            S_SENT, S_WAIT: begin
                if (wcnt == 24'd0)
                    state <= ret;
                else
                    wcnt <= wcnt - 24'd1;
            end
            S_MODEW: if (st[6:4] == mtgt && (mtgt != 3'd0 || st[3:0] == 4'd8))
                state <= mret;
            S_B1: go_wait(BATCH, S_B2);
            S_B2: go_mode(3'd0, S_B3);
            S_B3: go_wait(24'd16, bret);        // the counters reach their copies and the rule
            // ---- 1. prewrite
            S_PW2: go_send(8'h0f, {5'd0, pw[2:0]}, S_PW3);
            S_PW3: go_send(8'h20, {7'd0, pw[3]}, S_PW4);
            S_PW4: go_send(8'h21, 8'h00, S_PW5);
            S_PW5: go_send(8'h0e, rcpat(pw[3:0]), S_PW6);
            S_PW6: go_mode(3'd2, S_PW7);
            S_PW7: go_wait(PWW, S_PW8);
            S_PW8: go_mode(3'd0, S_PW9);
            S_PW9: if (pw == 5'd15) begin
                go_send(8'h0f, 8'h00, S_AD1);
            end else begin
                pw <= pw + 5'd1;
                state <= S_PW2;
            end
            S_AD1: go_send(8'h20, 8'h00, S_AD2);
            S_AD2: go_send(8'h21, 8'h00, S_FR0);
            // ---- 2. per-bit framing
            S_FR0: go_send(8'h0e, 8'h0b, S_FR1);
            S_FR1: go_mode(3'd3, S_FR2);
            S_FR2: begin
                li <= 2'd0;
                ftry <= 2'd0;
                go_wait(STREAMW, S_FR4);
            end
            S_FR4: if (!tgt_ok) begin
                err <= 4'd1;
                go_mode(3'd0, S_FAIL);
            end else begin
                pi <= 3'd1;
                pc <= 5'd0;
                state <= S_FR5;
            end
            S_FR5: if (wnorm == wref && isrot(wref)) begin
                pc <= 5'd0;
                if (pi == 3'd7) begin
                    if (li == 2'd3) begin
                        vcnt <= 3'd0;
                        state <= S_FR8;
                    end else begin
                        li <= li + 2'd1;
                        state <= S_FR4;
                    end
                end else
                    pi <= pi + 3'd1;
            end else if (pc == 5'd16) begin
                err <= 4'd2;
                go_mode(3'd0, S_FAIL);
            end else begin
                pc <= pc + 5'd1;
                go_send(8'h08, {3'd0, li, pi}, S_FR6);
            end
            S_FR6: go_wait(CALW, S_FR5);
            // every lane's pins agree in eight snapshots CALW apart, as the
            // probe's calibrate checks over its sessions; else frame again
            S_FR8: if (agree != 4'hf) begin
                if (ftry == 2'd3) begin
                    err <= 4'd2;
                    go_mode(3'd0, S_FAIL);
                end else begin
                    ftry <= ftry + 2'd1;
                    li <= 2'd0;
                    state <= S_FR4;
                end
            end else if (vcnt == 3'd7)
                go_mode(3'd0, S_ST0);
            else begin
                vcnt <= vcnt + 3'd1;
                go_wait(CALW, S_FR8);
            end
            // ---- the checker's settings, as the probe leaves them
            S_ST0: go_send(8'h2a, 8'h00, S_ST1);        // two-word reassembler off
            S_ST1: go_send(8'h09, 8'd40, S_ST2);        // access period
            S_ST2: go_send(8'h29, 8'h01, S_ST3);        // RVALID-held capture
            S_ST3: go_send(8'h26, 8'd20, S_ST4);        // check offset
            S_ST4: go_send(8'h37, 8'h00, S_T0);         // the sixteen rows
            // ---- 3. read tap 4
            S_T0: begin
                tcnt <= (step > 8'd4) ? step - 8'd4 : 8'd0;
                go_send(8'h0a, 8'h00, S_T1);
            end
            S_T1: if (tcnt == 8'd0) begin
                pos <= 5'd0;
                cal <= 4'd0;
                rs <= 3'd0;
                prev <= 4'd0;
                state <= S_S1;
            end else begin
                tcnt <= tcnt - 8'd1;
                go_send(8'h07, 8'hf1, S_T1);
            end
            // ---- 4. the search
            S_S1: begin
                li <= 2'd0;
                sub <= 2'd0;
                if (tried != 16'd0)
                    go_send(8'h35, {4'hf, ~locked}, S_S3);
                else
                    state <= S_S3;
            end
            S_S3: begin
                if (locked[li] || sub == 2'd3) begin
                    sub <= 2'd0;
                    if (li == 2'd3) begin
                        if (tried != 16'd0)
                            go_send(8'h35, 8'h00, S_S5);
                        else
                            state <= S_S5;
                    end else
                        li <= li + 2'd1;
                end else begin
                    sub <= sub + 2'd1;
                    case (sub)
                        2'd0: go_send(8'h2c, {li, 3'd0, pos[4:2]}, S_S3);
                        2'd1: go_send(8'h2d, {li, 4'd0, pos[1:0]}, S_S3);
                        default: go_send(8'h2e, {li, 3'd0, rs}, S_S3);
                    endcase
                end
            end
            S_S5: go_wait(WARM, S_S6);          // the lanes settle, as between the probe's trials
            S_S6: go_batch(S_S7);
            S_S7: begin
                nl = locked | (pass_now & prev & ~locked);
                for (q = 0; q < 4; q = q + 1) begin
                    if (!locked[q] && pass_now[q] && prev[q]) begin
                        lane_set[8*q +: 8] <= {pos, rs};
                        lane_cal[4*q +: 4] <= cal;
                    end
                    if (!locked[q] && pass_now[q] && diag[64*q +: 16] != 16'hffff)
                        diag[64*q +: 16] <= diag[64*q +: 16] + 16'd1;
                    if (!locked[q] && vstate[q] && !pass_now[q]) begin
                        if (diag[64*q + 16 +: 16] != 16'hffff)
                            diag[64*q + 16 +: 16] <= diag[64*q + 16 +: 16] + 16'd1;
                        if (miss[16*q +: 16] < diag[64*q + 32 +: 16]) begin
                            diag[64*q + 32 +: 16] <= miss[16*q +: 16];
                            diag[64*q + 48 +: 16] <= sat16(lag_eval);
                        end
                    end
                end
                prev <= pass_now & ~locked;
                locked <= nl;
                tried <= tried + 16'd1;
                if (nl == 4'hf) begin
                    li <= 2'd0;
                    state <= S_C1;
                end else if (rs == 3'd7) begin
                    li <= 2'd0;
                    pi <= 3'd0;
                    state <= S_S9;
                end else begin
                    rs <= rs + 3'd1;
                    state <= S_S1;
                end
            end
            S_S9: begin                         // CALIB on every lane still unlocked
                if (locked[li]) begin
                    pi <= 3'd0;
                    if (li == 2'd3) state <= S_S11; else li <= li + 2'd1;
                end else begin
                    if (pi == 3'd7) begin
                        pi <= 3'd0;
                        go_send(8'h08, {3'd0, li, pi}, (li == 2'd3) ? S_S11 : S_S9);
                        li <= li + 2'd1;
                    end else begin
                        pi <= pi + 3'd1;
                        go_send(8'h08, {3'd0, li, pi}, S_S9);
                    end
                end
            end
            S_S11: begin
                rs <= 3'd0;
                prev <= 4'd0;
                if (cal == 4'd8) begin
                    cal <= 4'd0;
                    if (pos == 5'd31) begin
                        li <= 2'd0;
                        state <= S_C1;          // search exhausted: centre what locked
                    end else begin
                        pos <= pos + 5'd1;
                        state <= S_S1;
                    end
                end else begin
                    cal <= cal + 4'd1;
                    state <= S_S1;
                end
            end
            // ---- 5. centring, lane by lane
            S_C1: if (!locked[li]) begin
                if (li == 2'd3) state <= S_W0; else li <= li + 2'd1;
            end else begin
                u <= 8'd0;
                state <= S_C2;
            end
            S_C2: go_send(8'h07, {(4'd1 << li), 4'h0}, S_C3);   // RDIR = 0: a tap up
            S_C3: go_batch(S_C4);
            S_C4: if (pass_now[li] && u != 8'd96) begin
                u <= u + 8'd1;
                state <= S_C2;
            end else begin
                // now at tap 4 + u + 1 after a failure, or 4 + u at the limit;
                // the window is taps 0 .. 4 + u, its middle (4 + u) / 2
                lane_u[8*li +: 8] <= u;
                cnt <= (8'd4 + u + (pass_now[li] ? 8'd0 : 8'd1)) - ((8'd4 + u) >> 1);
                state <= S_C5;
            end
            S_C5: if (cnt == 8'd0)
                go_batch(S_C7);
            else begin
                cnt <= cnt - 8'd1;
                go_send(8'h07, {(4'd1 << li), 4'h1}, S_C5);      // RDIR = 1: a tap down
            end
            S_C7: begin
                centred[li] <= pass_now[li];
                if (li == 2'd3) state <= S_W0; else begin
                    li <= li + 2'd1;
                    state <= S_C1;
                end
            end
            // ---- 6. the write alignment, then the lanes' read rotations
            S_W0: begin
                widx <= 7'd0;
                go_send(8'h37, 8'h01, S_W1);
            end
            S_W1: go_send(8'h36, {1'b0, widx[5:3], 1'b0, widx[2:0]}, S_W2);
            S_W2: go_mode(3'd5, S_W3);
            S_W3: go_wait(FILLW, S_W4);
            S_W4: go_mode(3'd0, S_W5);
            S_W5: go_batch(S_W6);
            S_W6: begin
                wpass[widx[5:0]] <= wpass_now;
                if (widx == 7'd63) begin
                    widx <= 7'd0;
                    state <= S_W7;
                end else begin
                    widx <= widx + 7'd1;
                    state <= S_W1;
                end
            end
            S_W7: begin                         // the first of two passing neighbours
                if (wpass[widx[5:0]] && widx != 7'd63 && wpass[widx[5:0] + 6'd1]) begin
                    walign <= widx[5:0];
                    wfound <= 1'b1;
                    state <= S_W9;
                end else if (widx == 7'd63) begin
                    widx <= 7'd0;
                    state <= S_W8;
                end else
                    widx <= widx + 7'd1;
            end
            S_W8: begin                         // else the first that passed
                if (wpass[widx[5:0]]) begin
                    walign <= widx[5:0];
                    wfound <= 1'b1;
                    state <= S_W9;
                end else if (widx == 7'd63) begin
                    err <= 4'd3;
                    go_send(8'h37, 8'h00, S_FIN);
                end else
                    widx <= widx + 7'd1;
            end
            S_W9: go_send(8'h36, {1'b0, walign[5:3], 1'b0, walign[2:0]}, S_W10);
            S_W10: go_mode(3'd5, S_W11);
            S_W11: go_wait(FILLW, S_W12);
            S_W12: go_mode(3'd0, S_W13);
            S_W13: go_batch(S_FIN);             // left with address data on
            S_FIN: begin
                if (wfound) begin
                    rot <= last_rot;
                    fin_total <= rc_total;
                    fin_class <= rc_class;
                end
                busy <= 1'b0;
                done <= 1'b1;
                state <= S_IDLE;
            end
            S_FAIL: begin
                busy <= 1'b0;
                done <= 1'b1;
                state <= S_IDLE;
            end
            default: state <= S_IDLE;
        endcase
    end
endmodule
