`default_nettype none

// Single-burst read checker: read latency and frame stability per READ.
//
// rd_align follows a continuous read stream; it cannot say which READ a
// burst answers.  This module can, because every READ it is told about
// names a location whose content the host wrote beforehand: one of sixteen
// (bank, row) pairs, each holding its own pattern across the whole row,
// even DQ the pattern and odd DQ its inverse as the write side drives them.
// The sixteen patterns are distinct aperiodic 8-bit necklaces stored as
// their least rotation, so any captured word identifies its pattern
// whatever its rotation, and its rotation as well.
//
// Every captured cycle is reduced per lane to (pins consistent, least
// rotation, rotation index).  Two things are measured from it:
//
//   hist[j]  for each READ whose pattern differs from the previous READ's,
//            the cycles j after the READ at which all four lanes hold that
//            READ's pattern.  A burst that arrives D cycles after the READ
//            reaches dq_q then and is held until the next one arrives, so
//            hist is full from j = D + PIPE for as long as the READs are
//            apart, and empty for as long again before it, where the words
//            are the previous READ's -- the read latency, measured.
//   check    at the configured offset `lat`, each READ's capture is judged:
//            class_ok when all four lanes hold its pattern, good when they
//            also hold it at the expected rotation.  The first good capture
//            after `arm` locks each lane's rotation; every later READ
//            expects the previous expectation advanced by `step` (0 for a
//            frame that holds, otherwise the move per READ).  The first
//            failure after `arm` is kept with its raw words and address.
//
//   lag      at the same offset `lat`, each lane of each READ is classified
//            by which READ's pattern it holds: its own (0), or that of the
//            READ issued k = 1 to LAGS before it, or none of these (LAGS + 1).
//            Only READs whose LAGS + 1 patterns are all distinct are
//            classified, so a lane's class is never ambiguous; with sixteen
//            patterns drawn at random that is about 6% of READs at LAGS = 8.
//            A lane that delivers an earlier READ's burst shows here as a
//            steady non-zero lag, which a stream of one pattern could never
//            reveal.  Before 2026-10-25 LAGS was 3 and four patterns had to
//            be distinct.
//
//   log      at the same offset `lat`, every READ from the log_skip * 1024th
//            after `arm` on is written to a 1024-entry log: its location and
//            burst, the refresh phase at the check, and per lane the least
//            rotation it held, whether its pins agreed, and the rotation.
//            Nothing is filtered, so the host can condition each lane's
//            result on any property of the READ or of the READs around it.
//            A log_go pulse copies 16 entries, page log_page, into log_buf.
//
// RVALID: the proven controller takes a lane's deserializer word only on a
// cycle whose DQS RVALID is high (TOOL-033).  With rv_enable set, each lane's
// input here is a word held from the last such cycle instead of the raw
// deserializer output, one PCLK later than the raw word would arrive; with
// it clear, nothing changes.
//
// PIPE is this module's own depth: the burst on dq_q in cycle c + D, for a
// READ marked by `issue` in cycle c, is compared with that READ in hist[D + 4].
// The first of the four stages registers the deserializer words and RVALID
// before any selection, as the proven controller does; before 2026-10-24
// PIPE was 3, so every offset recorded until then is one lower than the same
// arrival measured now.  The two burst positions of the classifier are
// 8 + PIPE and 16 + PIPE, the arrivals formerly reported as 11 and 19.
// Offsets below 1 are checked at 1.  The check runs three stages behind the
// capture, which READs at least eight cycles apart leave room for.
module rd_check #(
    parameter integer PIPE = 4,     // documented above; not a knob
    parameter integer LAGS = 8      // earlier READs the lag classifier names
) (
    input  wire         pclk,
    input  wire         rst,
    input  wire         arm,        // clear counters, lock, hist and failure
    input  wire [255:0] dq_q,       // lane l, pin p, beat b at 64l + 8p + b
    input  wire [3:0]   rvalid,     // each lane's DQS RVALID, same cycle as dq_q
    input  wire         rv_enable,  // take each lane's word only where RVALID is high
    input  wire         issue,      // a READ leaves the core this cycle
    input  wire [3:0]   issue_idx,  // its location: {row bit, bank}
    input  wire [6:0]   issue_col,  // its burst within the row
    input  wire [4:0]   lat,        // check offset, in hist's units
    input  wire [2:0]   step,       // expected rotation advance per READ
    input  wire         slip_enable,
    input  wire [11:0]  slip,       // one LiteDRAM-style beat slip per lane
    input  wire [9:0]   refi,       // PCLK since the last refresh, the phase
    input  wire [7:0]   log_skip,   // READs passed over before the log, in 1024s
    input  wire [5:0]   log_page,   // the log page log_go copies
    input  wire         log_go,     // one PCLK: copy that page into log_buf

    // Which of the two known burst positions held each READ (command 0x2B),
    // and the refresh phase at the check that decided it.
    output reg  [31:0]  n_both = 32'd0,
    output reg  [31:0]  n_only11 = 32'd0,
    output reg  [31:0]  n_only19 = 32'd0,
    output reg  [31:0]  n_other = 32'd0,
    output reg  [127:0] pos_range = 128'd0,  // min,max per class, 16 bits each
    output reg  [15:0]  pos_cls = 16'd0,     // last 8 classes, newest at [1:0]

    // Which READ's pattern each lane held at `lat` (command 0x2F): READs
    // classified, then lane l, lag k (LAGS + 1 = none) at
    // [32 * ((LAGS + 2) l + k) +: 32].
    output reg  [31:0]  lag_eval = 32'd0,
    output reg  [128*(LAGS+2)-1:0] lag_cnt = {128*(LAGS+2){1'b0}},

    // The READ log (commands 0x32 to 0x34): entries written since `arm`, and
    // one page of 16, entry e at [72e +: 72] laid out as
    //   [9l +: 8] lane l's least rotation, [9l + 8] its pins agreed,
    //   [36 + 3l +: 3] its rotation, [51:48] the READ's location {row bit,
    //   bank}, [58:52] its burst, [68:59] the refresh phase at the check.
    output reg  [10:0]  log_n = 11'd0,
    output reg  [1151:0] log_buf = 1152'd0,
    output reg  [5:0]   log_buf_page = 6'd0,

    output reg          locked = 1'b0,
    output reg  [11:0]  expect_rot = 12'd0,   // per lane, for the next READ
    output reg  [11:0]  last_rot = 12'd0,
    output reg  [3:0]   last_cls = 4'd0,
    output reg  [31:0]  total = 32'd0,
    output reg  [31:0]  good = 32'd0,
    output reg  [31:0]  class_ok = 32'd0,
    output reg  [31:0]  rot_moves = 32'd0,
    output reg  [15:0]  hist_n = 16'd0,
    output wire [511:0] hist,                 // hist[j] at [16j +: 16]
    output reg          fail_seen = 1'b0,
    output reg  [3:0]   fail_lanes = 4'd0,
    output reg  [7:0]   fail_pat = 8'd0,
    output reg  [10:0]  fail_addr = 11'd0,    // {row bit, bank, burst}
    output reg  [11:0]  fail_rot = 12'd0,
    output reg  [255:0] fail_words = 256'd0
);
    // The sixteen patterns, least rotations of distinct aperiodic necklaces
    // of weight 3 to 5; tools/ddr3_write_probe.py carries the same table.
    function [7:0] rom(input [3:0] i);
        case (i)
            4'd0:  rom = 8'h0b;  4'd1:  rom = 8'h0d;  4'd2:  rom = 8'h13;  4'd3:  rom = 8'h15;
            4'd4:  rom = 8'h17;  4'd5:  rom = 8'h19;  4'd6:  rom = 8'h1b;  4'd7:  rom = 8'h1d;
            4'd8:  rom = 8'h25;  4'd9:  rom = 8'h27;  4'd10: rom = 8'h2b;  4'd11: rom = 8'h2d;
            4'd12: rom = 8'h35;  4'd13: rom = 8'h37;  4'd14: rom = 8'h3b;  default: rom = 8'h57;
        endcase
    endfunction

    // derotate: the word w = (P << r) | (P >> (8 - r)) gives back P
    function [7:0] derot(input [7:0] w, input integer r);
        derot = (w >> r) | (w << (8 - r));
    endfunction

    // one registered clear for everything below: rst and arm both come from
    // flops elsewhere, and their OR would otherwise fan out unregistered
    reg clr = 1'b1;
    always @(posedge pclk)
        clr <= rst || arm;

    // ------------------------------------------------------------------
    // Capture reduction: per lane, pins consistent, least rotation, index
    // ------------------------------------------------------------------
    // The core registers the same word for its own checks; merged, the one
    // register would drive both from wherever it lands, so this copy stays.
    (* syn_preserve = 1, keep = 1 *) reg [255:0] dq_r = 256'd0;
    reg [255:0] dq_prev = 256'd0;
    reg [255:0] dq_in = 256'd0;     // the deserializer words, registered first
    reg [3:0]   rv_in = 4'd0;       // and RVALID, the same cycle
    reg [255:0] dq_held = 256'd0;   // lane l's word from its last RVALID cycle
    reg         rv_en_r = 1'b0;
    wire [255:0] dq_src = rv_en_r ? dq_held : dq_in;
    wire [255:0] dq_slipped;
    genvar gl, gp;
    generate
        for (gl = 0; gl < 4; gl = gl + 1) begin: lane_slip
            always @(posedge pclk)
                if (rv_in[gl])
                    dq_held[64*gl +: 64] <= dq_in[64*gl +: 64];
            for (gp = 0; gp < 8; gp = gp + 1) begin: pin_slip
                wire [15:0] pair = {dq_src[64*gl + 8*gp +: 8],
                                    dq_prev[64*gl + 8*gp +: 8]};
                assign dq_slipped[64*gl + 8*gp +: 8] = pair >> slip[3*gl +: 3];
            end
        end
    endgenerate
    wire [255:0] dq_selected = slip_enable ? dq_slipped : dq_src;
    // Each lane's pin-0 word again, one copy per comparator pair of the
    // least-rotation search: in dq_r it also feeds the pin check, and that
    // fanout put a 7 ns route in front of the search in the Gowin control.
    // Lane l, pair i at 32l + 8i; the same cycle as dq_r.
    (* syn_preserve = 1, keep = 1 *) reg [127:0] w0_r = 128'd0;
    reg [255:0] dq_b1 = 256'd0, dq_b2 = 256'd0, dq_b3 = 256'd0;
    reg [3:0]   pins_b1 = 4'd0, pins_b2 = 4'd0, pins_b3 = 4'd0;
    reg [127:0] pmin_b1 = 128'd0;   // lane l, pair i: least of the pair at 32l + 8i
    reg [47:0]  pidx_b1 = 48'd0;    // and its rotation index at 12l + 3i
    reg [87:0]  qmin_b2 = 88'd0;    // lane l, half h: {idx, least} at 22l + 11h
    reg [31:0]  canon_b3 = 32'd0;   // per lane, 8 bits
    reg [11:0]  crot_b3 = 12'd0;    // per lane, 3 bits

    integer l, i, p;
    reg [7:0] w0, wp, ca, cb;
    reg       ok;
    reg [10:0] e0, e1, e2, e3, q0, q1;

    always @(posedge pclk) begin
        rv_en_r <= rv_enable;
        dq_in <= dq_q;
        rv_in <= rvalid;
        dq_prev <= dq_src;
        dq_r <= dq_selected;
        for (l = 0; l < 4; l = l + 1)
            for (i = 0; i < 4; i = i + 1)
                w0_r[32*l + 8*i +: 8] <= dq_selected[64*l +: 8];
        dq_b1 <= dq_r;
        dq_b2 <= dq_b1;
        dq_b3 <= dq_b2;
        for (l = 0; l < 4; l = l + 1) begin
            w0 = dq_r[64*l +: 8];
            ok = 1'b1;
            for (p = 1; p < 8; p = p + 1) begin
                wp = dq_r[64*l + 8*p +: 8];
                if (wp != ((p % 2) ? ~w0 : w0))
                    ok = 1'b0;
            end
            pins_b1[l] <= ok;
            // first half of the least-rotation search: four pairs
            for (i = 0; i < 4; i = i + 1) begin
                ca = derot(w0_r[32*l + 8*i +: 8], 2*i);
                cb = derot(w0_r[32*l + 8*i +: 8], 2*i + 1);
                pmin_b1[32*l + 8*i +: 8] <= (cb < ca) ? cb : ca;
                pidx_b1[12*l + 3*i +: 3] <= (cb < ca) ? 2*i + 1 : 2*i;
            end
        end
        pins_b2 <= pins_b1;
        pins_b3 <= pins_b2;
        for (l = 0; l < 4; l = l + 1) begin
            // second stage: two halves
            e0 = {pidx_b1[12*l + 0 +: 3], pmin_b1[32*l + 0 +: 8]};
            e1 = {pidx_b1[12*l + 3 +: 3], pmin_b1[32*l + 8 +: 8]};
            e2 = {pidx_b1[12*l + 6 +: 3], pmin_b1[32*l + 16 +: 8]};
            e3 = {pidx_b1[12*l + 9 +: 3], pmin_b1[32*l + 24 +: 8]};
            qmin_b2[22*l +: 11] <= (e1[7:0] < e0[7:0]) ? e1 : e0;
            qmin_b2[22*l + 11 +: 11] <= (e3[7:0] < e2[7:0]) ? e3 : e2;
            // third stage: the least
            q0 = qmin_b2[22*l +: 11];
            q1 = qmin_b2[22*l + 11 +: 11];
            canon_b3[8*l +: 8] <= (q1[7:0] < q0[7:0]) ? q1[7:0] : q0[7:0];
            crot_b3[3*l +: 3] <= (q1[7:0] < q0[7:0]) ? q1[10:8] : q0[10:8];
        end
    end

    // ------------------------------------------------------------------
    // READs in flight: exp[j] is the READ marked j + 1 cycles ago
    // ------------------------------------------------------------------
    reg [31:0]  ex_v = 32'd0;       // a READ
    reg [31:0]  ex_h = 32'd0;       // counted in hist
    reg [255:0] ex_pat = 256'd0;    // its pattern, 8 bits each
    reg [351:0] ex_addr = 352'd0;   // its address, 11 bits each
    localparam integer PW = 4 * LAGS + 1;  // {distinct, idx of READs n-1 .. n-LAGS}
    reg [32*PW-1:0] ex_prev = {32*PW{1'b0}};
    reg [7:0]   prev_pat = 8'd0;
    reg         have_prev = 1'b0;
    reg [4*LAGS-1:0] prev_idx = {4*LAGS{1'b0}};  // the last LAGS READs' locations, newest at [3:0]
    reg [3:0]   prev_n = 4'd0;      // how many of them exist since `arm`, saturating
    wire [7:0]  issue_pat = rom(issue_idx);
    wire        fresh = issue && (!have_prev || issue_pat != prev_pat) && hist_n != 16'hffff;
    // Whether the earlier READs are distinct among themselves, and which
    // locations they hold, are registered from prev_idx, so only the new
    // READ's own lookup is in front of ex_prev.  They describe prev_idx as it
    // was a cycle ago, which is prev_idx now unless a READ was marked then;
    // a READ marked on the cycle after another is not classified.
    reg [15:0]  prev_mask = 16'd0, pm;
    reg         prev_ok = 1'b0, prev_cur = 1'b0, po;
    integer pa, pb;
    always @(posedge pclk) begin
        pm = 16'd0;
        po = 1'b1;
        for (pa = 0; pa < LAGS; pa = pa + 1) begin
            pm[prev_idx[4*pa +: 4]] = 1'b1;
            for (pb = pa + 1; pb < LAGS; pb = pb + 1)
                if (prev_idx[4*pa +: 4] == prev_idx[4*pb +: 4])
                    po = 1'b0;
        end
        prev_mask <= pm;
        prev_ok <= po;
        prev_cur <= !issue;
    end
    wire        distinct = prev_n == LAGS && prev_cur && prev_ok && !prev_mask[issue_idx];

    always @(posedge pclk) begin
        // pattern and address only mean something where ex_v is set
        ex_pat <= {ex_pat[247:0], issue_pat};
        ex_addr <= {ex_addr[340:0], issue_idx, issue_col};
        ex_prev <= {ex_prev[31*PW-1:0], distinct, prev_idx};
        if (clr) begin
            ex_v <= 32'd0;
            ex_h <= 32'd0;
            have_prev <= 1'b0;
            prev_n <= 4'd0;
            hist_n <= 16'd0;
        end else begin
            ex_v <= {ex_v[30:0], issue};
            ex_h <= {ex_h[30:0], fresh};
            if (issue) begin
                prev_pat <= issue_pat;
                have_prev <= 1'b1;
                prev_idx <= {prev_idx[4*LAGS-5:0], issue_idx};
                if (prev_n != LAGS)
                    prev_n <= prev_n + 4'd1;
            end
            if (fresh)
                hist_n <= hist_n + 16'd1;
        end
    end

    // ------------------------------------------------------------------
    // hist: every offset compares every cycle
    // ------------------------------------------------------------------
    reg [31:0]  hit = 32'd0;
    reg [511:0] hcnt = 512'd0;
    integer j, hl;
    reg all, all_any;
    // the two positions an isolated burst lands in, named for their PIPE 3
    // offsets: m11 at 8 + PIPE, m19 at 16 + PIPE
    localparam integer POS_A = 8 + PIPE, POS_B = 16 + PIPE;
    reg m11 = 1'b0, m19 = 1'b0;     // this READ matched at that offset
    always @(posedge pclk) begin
        for (j = 0; j < 32; j = j + 1) begin
            all_any = 1'b1;
            for (hl = 0; hl < 4; hl = hl + 1)
                if (!pins_b3[hl] || canon_b3[8*hl +: 8] != ex_pat[8*j +: 8])
                    all_any = 1'b0;
            all = ex_h[j] && all_any;
            hit[j] <= all && !clr;
            // The two positions an isolated burst lands in, for every READ,
            // not only the ones the histogram counts.
            if (j == POS_A) m11 <= all_any && ex_v[POS_A] && !clr;
            if (j == POS_B) m19 <= all_any && ex_v[POS_B] && !clr;
        end
        if (clr)
            hcnt <= 512'd0;
        else
            for (j = 0; j < 32; j = j + 1)
                hcnt[16*j +: 16] <= hcnt[16*j +: 16] + {15'd0, hit[j]};
    end

    // ------------------------------------------------------------------
    // Which position held each READ, and at what refresh phase
    // ------------------------------------------------------------------
    // A READ's offset-11 check happens 8 PCLK before its offset-19 check, so
    // m11 delayed by eight belongs to the same READ as m19 now.  Deciding
    // both at the offset-19 check gives one classification per READ: 3 both,
    // 2 only 19, 1 only 11, 0 neither.  The phase is the refresh counter at
    // that check, so the host can see whether the two positions occupy
    // disjoint phases (a refresh epoch) or both appear at every phase (a
    // per-READ property, which a fixed latency cannot cover).
    // m11 and m19 are registered from the check cycle, so both describe one
    // READ only on the cycle after its offset-19 check: that is `ev19`.
    reg  [7:0] m11_d = 8'd0;
    reg        ev19 = 1'b0;
    wire [1:0] cls_w = {m19, m11_d[7]};
    always @(posedge pclk) begin
        m11_d <= {m11_d[6:0], m11};
        ev19  <= ex_v[POS_B] && !clr;
        if (clr) begin
            n_both <= 32'd0;
            n_only11 <= 32'd0;
            n_only19 <= 32'd0;
            n_other <= 32'd0;
            pos_cls <= 16'd0;
            pos_range <= {16'h03ff, 16'd0, 16'h03ff, 16'd0,
                          16'h03ff, 16'd0, 16'h03ff, 16'd0};
        end else if (ev19) begin
            pos_cls <= {pos_cls[13:0], cls_w};
            case (cls_w)
                2'd3: n_both <= n_both + 32'd1;
                2'd2: n_only19 <= n_only19 + 32'd1;
                2'd1: n_only11 <= n_only11 + 32'd1;
                default: n_other <= n_other + 32'd1;
            endcase
            if ({6'd0, refi} < pos_range[32*cls_w +: 16])
                pos_range[32*cls_w +: 16] <= {6'd0, refi};
            if ({6'd0, refi} > pos_range[32*cls_w + 16 +: 16])
                pos_range[32*cls_w + 16 +: 16] <= {6'd0, refi};
        end
    end
    assign hist = hcnt;

    // ------------------------------------------------------------------
    // The check at `lat`
    // ------------------------------------------------------------------
    // The READ at offset `lat` is selected two cycles ahead, from `lat - 2`.
    // The 32-entry mux is split into registered 4-way and 8-way stages;
    // Gowin otherwise puts the whole select on one PCLK path.
    reg  [4:0]   lat_m2 = 5'd0;
    reg  [7:0]   sel_v_block = 8'd0;
    reg  [63:0]  sel_pat_block = 64'd0;
    reg  [87:0]  sel_addr_block = 88'd0;
    reg  [8*PW-1:0] sel_prev_block = {8*PW{1'b0}};
    reg  [2:0]   sel_low = 3'd0;
    reg          sel_v = 1'b0;
    reg  [7:0]   sel_pat = 8'd0;
    reg  [10:0]  sel_addr = 11'd0;
    reg  [PW-1:0] sel_prev = {PW{1'b0}};
    always @(posedge pclk) begin
        lat_m2 <= (lat < 5'd2) ? 5'd0 : lat - 5'd2;
        sel_low <= lat_m2[2:0];
        case (lat_m2[4:3])
            2'd0: begin
                sel_v_block <= ex_v[7:0];
                sel_pat_block <= ex_pat[63:0];
                sel_addr_block <= ex_addr[87:0];
                sel_prev_block <= ex_prev[8*PW-1:0];
            end
            2'd1: begin
                sel_v_block <= ex_v[15:8];
                sel_pat_block <= ex_pat[127:64];
                sel_addr_block <= ex_addr[175:88];
                sel_prev_block <= ex_prev[16*PW-1:8*PW];
            end
            2'd2: begin
                sel_v_block <= ex_v[23:16];
                sel_pat_block <= ex_pat[191:128];
                sel_addr_block <= ex_addr[263:176];
                sel_prev_block <= ex_prev[24*PW-1:16*PW];
            end
            default: begin
                sel_v_block <= ex_v[31:24];
                sel_pat_block <= ex_pat[255:192];
                sel_addr_block <= ex_addr[351:264];
                sel_prev_block <= ex_prev[32*PW-1:24*PW];
            end
        endcase
        sel_v <= !clr && sel_v_block[sel_low];
        sel_pat <= sel_pat_block[8*sel_low +: 8];
        sel_addr <= sel_addr_block[11*sel_low +: 11];
        sel_prev <= sel_prev_block[PW*sel_low +: PW];
    end

    // first: does each lane hold the READ's pattern
    reg         ck_v = 1'b0;
    reg [3:0]   ck_cls = 4'd0;
    reg [11:0]  ck_rot = 12'd0;
    reg [7:0]   ck_pat = 8'd0;
    reg [10:0]  ck_addr = 11'd0;
    reg [255:0] ck_words = 256'd0;
    integer cl;
    // and does it hold one of the LAGS READs' before it
    reg         ck_distinct = 1'b0;
    reg [4*LAGS-1:0] ck_older = {4*LAGS{1'b0}};  // lane l, lag k = 1..LAGS at LAGS l + k - 1
    // and, for the log, what each lane held
    reg [31:0]  ck_canon = 32'd0;
    reg [3:0]   ck_pins = 4'd0;
    reg [9:0]   ck_refi = 10'd0;
    integer ck_k;
    always @(posedge pclk) begin
        ck_v <= !clr && sel_v;
        ck_canon <= canon_b3;
        ck_pins <= pins_b3;
        ck_refi <= refi;
        ck_pat <= sel_pat;
        ck_addr <= sel_addr;
        for (cl = 0; cl < 4; cl = cl + 1) begin
            ck_cls[cl] <= pins_b3[cl] && canon_b3[8*cl +: 8] == sel_pat;
            for (ck_k = 0; ck_k < LAGS; ck_k = ck_k + 1)
                ck_older[LAGS*cl + ck_k] <= pins_b3[cl] &&
                                            canon_b3[8*cl +: 8] == rom(sel_prev[4*ck_k +: 4]);
        end
        ck_distinct <= sel_prev[4*LAGS];
        ck_rot <= crot_b3;
        ck_words <= dq_b3;
    end

    // lag: one-hot per lane, the nearest READ first, registered before it
    // counts so the compare chain is not in front of the 32-bit increments
    localparam integer LC = LAGS + 2;   // classes per lane
    reg         lg_v = 1'b0;
    reg [4*LC-1:0] lg_hit = {4*LC{1'b0}};  // lane l, lag k at LC l + k
    reg         lg_seen;
    integer lgl, lgk;
    always @(posedge pclk) begin
        lg_v <= !clr && ck_v && ck_distinct;
        for (lgl = 0; lgl < 4; lgl = lgl + 1) begin
            lg_seen = ck_cls[lgl];
            lg_hit[LC*lgl] <= lg_seen;
            for (lgk = 1; lgk <= LAGS; lgk = lgk + 1) begin
                lg_hit[LC*lgl + lgk] <= !lg_seen && ck_older[LAGS*lgl + lgk - 1];
                lg_seen = lg_seen || ck_older[LAGS*lgl + lgk - 1];
            end
            lg_hit[LC*lgl + LAGS + 1] <= !lg_seen;
        end
        if (clr) begin
            lag_eval <= 32'd0;
            lag_cnt <= {128*LC{1'b0}};
        end else if (lg_v) begin
            lag_eval <= lag_eval + 32'd1;
            for (lgk = 0; lgk < 4*LC; lgk = lgk + 1)
                if (lg_hit[lgk])
                    lag_cnt[32*lgk +: 32] <= lag_cnt[32*lgk +: 32] + 32'd1;
        end
    end

    // the log: one entry per READ once log_skip * 1024 READs have passed,
    // the entry registered before it is written
    reg  [17:0] lw_skip = 18'd0;    // READs still to pass over
    reg         lw_v = 1'b0;
    reg  [9:0]  lw_a = 10'd0;
    reg  [71:0] lw_d = 72'd0;
    integer lwl;
    always @(posedge pclk) begin
        lw_v <= 1'b0;
        lw_a <= log_n[9:0];
        for (lwl = 0; lwl < 4; lwl = lwl + 1)
            lw_d[9*lwl +: 9] <= {ck_pins[lwl], ck_canon[8*lwl +: 8]};
        lw_d[47:36] <= ck_rot;
        lw_d[51:48] <= ck_addr[10:7];  // {row bit, bank}
        lw_d[58:52] <= ck_addr[6:0];   // burst
        lw_d[68:59] <= ck_refi;
        lw_d[71:69] <= 3'd0;
        if (clr) begin
            log_n <= 11'd0;
            lw_skip <= {log_skip, 10'd0};
        end else if (ck_v) begin
            if (lw_skip != 18'd0)
                lw_skip <= lw_skip - 18'd1;
            else if (!log_n[10]) begin
                lw_v <= 1'b1;
                log_n <= log_n + 11'd1;
            end
        end
    end
    reg [71:0] log_mem [0:1023];
    reg [71:0] lr_d = 72'd0;
    reg [9:0]  lr_a = 10'd0;
    always @(posedge pclk) begin
        if (lw_v)
            log_mem[lw_a] <= lw_d;
        lr_d <= log_mem[lr_a];
    end
    // a page: sixteen reads, shifted in as they come, entry 0 ending lowest
    reg        lr_busy = 1'b0, lr_v = 1'b0;
    reg [3:0]  lr_i = 4'd0;
    always @(posedge pclk) begin
        lr_v <= lr_busy;
        if (log_go) begin
            lr_busy <= 1'b1;
            lr_i <= 4'd0;
            lr_a <= {log_page, 4'd0};
            log_buf_page <= log_page;
        end else if (lr_busy) begin
            lr_a <= lr_a + 10'd1;
            lr_i <= lr_i + 4'd1;
            if (lr_i == 4'd15)
                lr_busy <= 1'b0;
        end
        if (lr_v)
            log_buf <= {lr_d, log_buf[1151:72]};
    end

    // second: is it at the expected rotation; expect_rot only changes in
    // the third stage, one READ before, so it is settled here
    reg         ev_v = 1'b0, ev_all = 1'b0;
    reg [3:0]   ev_cls = 4'd0, ev_bad = 4'd0;
    reg [11:0]  ev_rot = 12'd0;
    reg [7:0]   ev_pat = 8'd0;
    reg [10:0]  ev_addr = 11'd0;
    reg [255:0] ev_words = 256'd0;
    // The move pulse is registered before it counts: the comparison against
    // the previous rotation, the class check and the count's own zero test
    // put eleven levels in front of a 32-bit increment on pclk otherwise.
    reg         ev_move = 1'b0;
    integer el;
    always @(posedge pclk) begin
        ev_move <= !clr && ev_v && ev_all && (&last_cls) &&
                   (ev_rot != last_rot) && (total != 32'd0);
        ev_v <= !clr && ck_v;
        ev_all <= &ck_cls;
        ev_cls <= ck_cls;
        for (el = 0; el < 4; el = el + 1)
            ev_bad[el] <= !ck_cls[el] || ck_rot[3*el +: 3] != expect_rot[3*el +: 3];
        ev_rot <= ck_rot;
        ev_pat <= ck_pat;
        ev_addr <= ck_addr;
        ev_words <= ck_words;
    end

    // one 3-bit field per lane, so no borrow or carry crosses lanes
    function [11:0] add_rot(input [11:0] r, input [2:0] s);
        add_rot = {r[11:9] + s, r[8:6] + s, r[5:3] + s, r[2:0] + s};
    endfunction

    // third: count, lock, keep the first failure
    always @(posedge pclk) begin
        if (clr) begin
            locked <= 1'b0;
            expect_rot <= 12'd0;
            last_rot <= 12'd0;
            last_cls <= 4'd0;
            total <= 32'd0;
            good <= 32'd0;
            class_ok <= 32'd0;
            rot_moves <= 32'd0;
            fail_seen <= 1'b0;
            fail_lanes <= 4'd0;
            fail_pat <= 8'd0;
            fail_addr <= 11'd0;
            fail_rot <= 12'd0;
            fail_words <= 256'd0;
        end else begin
            if (ev_v) begin
                total <= total + 32'd1;
                last_rot <= ev_rot;
                last_cls <= ev_cls;
                if (ev_all)
                    class_ok <= class_ok + 32'd1;
                if (!locked) begin
                    if (ev_all) begin
                        locked <= 1'b1;
                        good <= good + 32'd1;
                        expect_rot <= add_rot(ev_rot, step);
                    end
                end else begin
                    expect_rot <= add_rot(expect_rot, step);
                    if (ev_bad == 4'b0000)
                        good <= good + 32'd1;
                    else if (!fail_seen) begin
                        fail_seen <= 1'b1;
                        fail_lanes <= ev_bad;
                        fail_pat <= ev_pat;
                        fail_addr <= ev_addr;
                        fail_rot <= ev_rot;
                        fail_words <= ev_words;
                    end
                end
            end
            // counted a cycle after its own response left ev_v, so the
            // 32-bit increment starts from a flop and the rotation
            // comparison, the class check and the zero test are not in
            // front of it
            if (ev_move)
                rot_moves <= rot_moves + 32'd1;
        end
    end
endmodule

`default_nettype wire
