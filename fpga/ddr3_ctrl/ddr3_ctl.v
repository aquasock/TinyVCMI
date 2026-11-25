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
// signals -- CKE and ODT -- are not driven here: wr_core holds CKE and
// dfi_phy makes ODT from the WRITEs.  A request's write mask travels beside
// its data, in a FIFO and registers of its own that move with the data's,
// and reaches the DFI with it, a PCLK after the command.
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
    input  wire [31:0]   cmd_wmask,     // 1 suppresses beat b, lane l at 4b + l
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
    output reg  [31:0]   dfi_wrmask = 32'd0,    // with dfi_wrdata, as cmd_wmask
    output wire [3:0]    dfi_wrdata_en,
    output wire [3:0]    dfi_rddata_en,
    input  wire [255:0]  dfi_rddata,
    input  wire [3:0]    dfi_rddata_valid,

    output reg  [31:0]   n_act = 32'd0,
    output reg  [31:0]   n_ref = 32'd0
);
    // ---- the request FIFO, four deep, then nxt and cur ---------------------
    // An entry carries `same`: it is on the bank and row of the request taken
    // before it, so following that request's READ or WRITE it is a row hit
    // with nothing to look up.
    reg [282:0] fq [0:3];               // {same, we, addr, data}
    reg [1:0]   fq_w = 2'd0, fq_r = 2'd0;
    reg [2:0]   fq_n = 3'd0;
    wire [282:0] head = fq[fq_r];
    // the entries' {row, bank} again, in registers beside the FIFO's LUT RAM
    // and written with it: the row compares read the head's from here, not
    // from the 283-bit RAM spread down the device, whose read put m_n_r 1.4
    // ns over 100 MHz fully timed (TOOL-065)
    (* ram_style = "logic" *) reg [17:0] fq_br [0:3];
    // and the head's {row, bank} itself in a register, loaded at every edge
    // with the entry fq_r points to after it (or the request written there
    // at the same edge), so the row compares start from a flop and not from
    // fq_r through a 4-to-1 mux, which put m_n_r 0.4 to 1.6 ns over 100 MHz
    // on nine seeds of sixteen of the AE350 image (core-log entry 16)
    reg [17:0]  head_br = 18'd0;
    // the entries' write masks, beside the FIFO, and nxt's, cur's and the
    // held one beside nxt, cur and wr_hold
    reg  [31:0] fq_m [0:3];
    reg  [31:0] nxt_m = 32'd0, cur_m = 32'd0, wm_hold = 32'd0;
    wire         h_v = (fq_n != 3'd0);
    // fq_n < 3, one slot spare because the ready is registered at the
    // requester; made from fq_n's next value and registered beside it, so it
    // is a flop and not a LUT of fq_n in front of the requesters' enables
    // (ddr3_bist's rcnt, ctrl_glue's b_addr), which missed 100 MHz on three
    // seeds of the AE350 image (core-log entry 16)
    reg         rdy = 1'b1;
    assign cmd_ready = rdy;
    reg          nxt_v = 1'b0, cur_v = 1'b0;
    reg [282:0]  nxt = 283'd0, cur = 283'd0;
    // `same` is made as an entry leaves the FIFO for nxt, against the entry
    // that left before it: entries leave in the order they came, so it is
    // the bit a compare at the request port once wrote into the FIFO, where
    // the compare sat behind the requester's address 1.6 ns over 100 MHz
    // fully timed (TOOL-065)
    reg [17:0]   last_br = 18'd0;       // {row, bank} of the request that left last
    reg          last_v = 1'b0;
    wire         c_we = cur[281];
    wire [14:0]  c_row = cur[280:266];
    wire [2:0]   h_bank = cur[265:263];
    wire [6:0]   c_col = cur[262:256];
    wire [255:0] h_data = cur[255:0];
    wire         n_same = nxt[282];
    wire         n_we = nxt[281];
    wire [14:0]  n_row = nxt[280:266];
    wire [2:0]   n_bank = nxt[265:263];
    wire [6:0]   n_col = nxt[262:256];
    reg          hit = 1'b0, c_open = 1'b0;   // cur's bank on cur's row / open

    // ---- the banks and the timers -----------------------------------------
    reg [7:0]  b_open = 8'd0;
    // in registers, not LUT RAM: the row-hit compare reads it every PCLK and
    // a LUT RAM read in front of it left 1.6 ns too little for 100 MHz
    (* ram_style = "logic" *) reg [14:0] b_row [0:7];
    reg [2:0]  c_act [0:7];             // PCLK until an ACTIVATE may go to the bank
    reg [1:0]  c_cas [0:7];             // until a READ or WRITE may
    reg [2:0]  c_pre [0:7];             // until a PRECHARGE may
    reg [2:0]  c_rrd = 3'd0, c_wtr = 3'd0, c_rtw = 3'd0;
    reg [2:0]  faw [0:3];               // PCLK since each of the last four ACTIVATEs
    // Each timer's `is zero`, registered beside it and made from the timer's
    // value and the plan rather than from its next value, so the decision
    // reads one registered bit per bank instead of comparing a timer behind
    // an 8-to-1 mux, and the refresh's all-bank checks AND eight bits.  Fully
    // timed (TOOL-065) the compares put the decision 3.9 ns over 100 MHz.
    reg [7:0]  za = 8'hff, zc = 8'hff, zp = 8'hff;   // c_act, c_cas, c_pre zero
    reg        z_rrd = 1'b1, z_wtr = 1'b1, z_rtw = 1'b1;
    reg        faw_ok = 1'b1;                       // faw[3] >= T_FAW
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
    wire       pre_ok_all = &(~b_open | zp);
    wire       act_ok_all = &za;

    // cur's and nxt's row against every bank at once, so the select between
    // them comes last instead of feeding an 8-to-1 mux of 15-bit rows and a
    // compare behind it, which put `hit` 4.2 ns over 100 MHz fully timed.
    // m_n and m_h are those compares of the registers now; m_n_r and m_h_r
    // are the same compares made a PCLK early from the values the registers
    // are about to take -- the banks from the plan going out, nxt from the
    // FIFO head when it advances, cur from nxt -- and registered, so they
    // equal m_n and m_h at every PCLK and `hit` reads only them (in one PCLK
    // the compares still put it 1.5 ns over, fully timed).
    reg [7:0]  m_n, m_h;
    always @(*)
        for (i = 0; i < 8; i = i + 1) begin
            m_n[i] = b_open[i] && (b_row[i] == n_row);
            m_h[i] = b_open[i] && (b_row[i] == c_row);
        end
    reg [7:0]  m_n_r = 8'd0, m_h_r = 8'd0;

    // ---- the command decided this PCLK -------------------------------------
    // The decision is registered into the plan (p_*) and goes out a PCLK
    // later, and everything the command changes -- the banks, the timers, the
    // FIFO and cur -- is updated from the plan register, never from the
    // decision itself.  While a plan is pending only one decision is made:
    // when the plan is cur's READ or WRITE, nxt follows it at once if nxt is
    // on the same row (`same`) and goes the same way, a READ after a READ or a
    // WRITE after a WRITE, which no bank state or timer between them can
    // forbid; so a row streams one burst per PCLK, as the PHY's read capture
    // needs, and every other command waits for the plan to go out, which
    // meets its timers with a PCLK to spare.
    localparam [3:0] C_NOP = 4'b1111, C_ACT = 4'b0011, C_RD = 4'b0101, C_WR = 4'b0100,
                     C_PRE = 4'b0010, C_REF = 4'b0001;
    reg  [3:0]  go_c;                   // {cs_n, ras_n, cas_n, we_n}
    reg  [2:0]  go_b;
    reg  [14:0] go_a;
    reg         go_pop;
    reg  [3:0]  p_c = 4'b1111;          // the plan: the command going out next PCLK
    reg  [2:0]  p_b = 3'd0;
    reg  [14:0] p_a = 15'd0;
    reg         p_pop = 1'b0;
    // the plan's row and every bank's row against the head, nxt and cur rows
    integer ie;
    wire       eq_pa_n = (p_a == n_row);
    wire       eq_pa_c = (p_a == c_row);
    reg  [7:0] eq_b_h, eq_b_n, eq_b_c;
    wire       eq_pa_h = (p_a == head_br[17:3]);
    always @(*)
        begin
            for (ie = 0; ie < 8; ie = ie + 1) begin
                eq_b_n[ie] = (b_row[ie] == n_row);
                eq_b_c[ie] = (b_row[ie] == c_row);
            end
            for (ie = 0; ie < 8; ie = ie + 1)
                eq_b_h[ie] = (b_row[ie] == head_br[17:3]);
        end
    wire        p_v = (p_c != C_NOP);
    // A READ or WRITE that went out at the last edge: the next one may follow
    // it at once (a chain, decided while it was planned) or three or more PCLK
    // after it, never two.  On the board a READ two PCLK after a READ comes
    // back as the bus between two bursts, one beat pair repeated (in-order
    // reads at one per two PCLK failed every second word; random reads that
    // hit an open row in another bank, about 1 in 32,768, failed so).
    reg         cas_last = 1'b0;
    always @(*) begin
        go_c = C_NOP;
        go_b = h_bank;
        go_a = 15'd0;
        go_pop = 1'b0;
        if (!p_v) case (f_state)
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
                    if (zc[h_bank] && !cas_last && (c_we ? z_rtw : z_wtr)) begin
                        go_c = c_we ? C_WR : C_RD;
                        go_a = {5'd0, c_col, 3'b000};   // BL8, A10 low: no auto-precharge
                        go_pop = 1'b1;
                    end
                end else if (c_open) begin
                    if (zp[h_bank])
                        go_c = C_PRE;                    // A10 low: this bank
                end else if (za[h_bank] && z_rrd && faw_ok) begin
                    go_c = C_ACT;
                    go_a = c_row;
                end
            end
        endcase
        else if (p_pop && f_state == F_RUN && nxt_v && n_same && n_we == c_we) begin
            go_c = n_we ? C_WR : C_RD;
            go_b = n_bank;
            go_a = {5'd0, n_col, 3'b000};
            go_pop = 1'b1;
        end
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

    // The timers' arithmetic as lookups on their few bits.  Written as
    // compares, additions and subtractions, Yosys maps each onto a carry
    // chain, which fully timed (TOOL-065) cost the timer updates and fq_n up
    // to 2.4 ns at 100 MHz; a case on two or three bits stays in one LUT.
    function [2:0] max3(input [2:0] a, input integer b);
        reg [7:0] below;
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1)
                below[i] = (i < b);
            max3 = below[a] ? b[2:0] : a;
        end
    endfunction
    function [2:0] age(input [2:0] a);  // a PCLK older, saturating
        case (a)
            3'd0: age = 3'd1; 3'd1: age = 3'd2; 3'd2: age = 3'd3; 3'd3: age = 3'd4;
            3'd4: age = 3'd5; 3'd5: age = 3'd6; default: age = 3'd7;
        endcase
    endfunction
    function [2:0] dec3(input [2:0] a); // a PCLK nearer zero, stopping there
        case (a)
            3'd0: dec3 = 3'd0; 3'd1: dec3 = 3'd0; 3'd2: dec3 = 3'd1; 3'd3: dec3 = 3'd2;
            3'd4: dec3 = 3'd3; 3'd5: dec3 = 3'd4; 3'd6: dec3 = 3'd5; default: dec3 = 3'd6;
        endcase
    endfunction
    function [1:0] dec2(input [1:0] a);
        case (a)
            2'd0: dec2 = 2'd0; 2'd1: dec2 = 2'd0; 2'd2: dec2 = 2'd1; default: dec2 = 2'd2;
        endcase
    endfunction
    function [2:0] inc3w(input [2:0] a);    // wrapping, as + 1 does
        case (a)
            3'd0: inc3w = 3'd1; 3'd1: inc3w = 3'd2; 3'd2: inc3w = 3'd3; 3'd3: inc3w = 3'd4;
            3'd4: inc3w = 3'd5; 3'd5: inc3w = 3'd6; 3'd6: inc3w = 3'd7; default: inc3w = 3'd0;
        endcase
    endfunction
    function [2:0] dec3w(input [2:0] a);
        case (a)
            3'd0: dec3w = 3'd7; 3'd1: dec3w = 3'd0; 3'd2: dec3w = 3'd1; 3'd3: dec3w = 3'd2;
            3'd4: dec3w = 3'd3; 3'd5: dec3w = 3'd4; 3'd6: dec3w = 3'd5; default: dec3w = 3'd6;
        endcase
    endfunction
    function [1:0] inc2w(input [1:0] a);
        inc2w = {a[1] ^ a[0], ~a[0]};
    endfunction
    wire f_in = cmd_valid && cmd_ready;
    wire f_out = h_v && (!nxt_v || !cur_v || p_pop);
    // fq_n and fq_r after this edge, as the always block below sets them
    wire [2:0] fq_n_nx = rst ? 3'd0 : (f_in && !f_out) ? inc3w(fq_n) :
                         (f_out && !f_in) ? dec3w(fq_n) : fq_n;
    wire [1:0] fq_r_nx = rst ? 2'd0 : f_out ? inc2w(fq_r) : fq_r;

    // bank k's open flag and row after this edge, as the plan going out and
    // a reset set them below
    function nx_open(input integer kb);
        nx_open = !rst && ((p_c == C_ACT && p_b == kb) ? 1'b1 :
                           (p_c == C_PRE && (p_a[10] || p_b == kb)) ? 1'b0 : b_open[kb]);
    endfunction
    function [14:0] nx_row(input integer kb);
        nx_row = (p_c == C_ACT && p_b == kb) ? p_a : b_row[kb];
    endfunction
    integer k;
    always @(posedge pclk) begin
        // the decision into the plan, the plan onto the DFI, and the write's
        // data on the DFI a PCLK after its command; cur still holds the
        // planned request at the edge its command goes out
        p_c <= rst ? C_NOP : go_c;
        p_b <= go_b;
        p_a <= go_a;
        p_pop <= !rst && go_pop;
        cas_last <= !rst && (p_c == C_RD || p_c == C_WR);
        q_c <= rst ? C_NOP : p_c;
        q_b <= p_b;
        q_a <= p_a;
        wr_hold <= h_data;
        dfi_wrdata <= wr_hold;
        wm_hold <= cur_m;
        dfi_wrmask <= wm_hold;
        rdata_valid <= !rst && dfi_rddata_valid[0];
        rdata <= dfi_rddata;

        // the FIFO, nxt and cur: cur moves on when served, nxt follows, the
        // FIFO refills nxt; cur's flags are made from the banks' registers
        if (cmd_valid && cmd_ready) begin
            fq[fq_w] <= {1'b0, cmd_we, cmd_addr, cmd_wdata};
            fq_m[fq_w] <= cmd_wmask;
            fq_br[fq_w] <= cmd_addr[24:7];
            fq_w <= inc2w(fq_w);
        end
        if (nxt_v && (!cur_v || p_pop)) begin
            cur <= nxt;
            cur_m <= nxt_m;
            cur_v <= 1'b1;
            hit <= m_n_r[n_bank];
            c_open <= b_open[n_bank];
        end else begin
            if (p_pop)
                cur_v <= 1'b0;
            hit <= m_h_r[h_bank];
            c_open <= b_open[h_bank];
        end
        if (h_v && (!nxt_v || !cur_v || p_pop)) begin
            nxt <= {last_v && (head_br == last_br), head[281:0]};
            nxt_m <= fq_m[fq_r];
            last_br <= head_br;
            last_v <= 1'b1;
            nxt_v <= 1'b1;
            fq_r <= inc2w(fq_r);
        end else if (nxt_v && (!cur_v || p_pop))
            nxt_v <= 1'b0;
        fq_n <= (f_in && !f_out) ? inc3w(fq_n) : (f_out && !f_in) ? dec3w(fq_n) : fq_n;
        rdy <= !fq_n_nx[2] && !(fq_n_nx[1] && fq_n_nx[0]);
        head_br <= (f_in && fq_w == fq_r_nx) ? cmd_addr[24:7] : fq_br[fq_r_nx];

        // the row compares of the next PCLK's registers (see m_n_r)
        // Every compare is made from registers: the plan's row and each
        // bank's row against the three candidate rows, the FIFO head, nxt
        // and cur.  The plan's decode (is it bank k's ACTIVATE) and the two
        // advances then only choose among results; deciding the row first and
        // comparing after put m_h_r up to 3.1 ns over 100 MHz fully timed.
        for (k = 0; k < 8; k = k + 1) begin
            m_n_r[k] <= nx_open(k) &&
                (f_out ? ((p_c == C_ACT && p_b == k) ? eq_pa_h : eq_b_h[k])
                       : ((p_c == C_ACT && p_b == k) ? eq_pa_n : eq_b_n[k]));
            m_h_r[k] <= nx_open(k) &&
                ((nxt_v && (!cur_v || p_pop)) ? ((p_c == C_ACT && p_b == k) ? eq_pa_n : eq_b_n[k])
                                              : ((p_c == C_ACT && p_b == k) ? eq_pa_c : eq_b_c[k]));
        end
        // the timers count down unless the command going out, from the
        // plan, sets them; a timer set this PCLK counts from the next, so a
        // value n allows the next command n PCLK later.  Each bank decides
        // its own timers from p_b == k, so no timer is read through an
        // 8-to-1 mux of p_b to be written back through a decoder.
        for (k = 0; k < 8; k = k + 1) begin
            if (p_c == C_REF)
                c_act[k] <= 3'd0;
            else if (p_c == C_ACT && p_b == k)
                c_act[k] <= T_RC - 1;
            else if (p_c == C_PRE && (p_a[10] || p_b == k))
                c_act[k] <= max3(c_act[k], T_RP - 1);
            else
                c_act[k] <= dec3(c_act[k]);
            if (p_c == C_ACT && p_b == k)
                c_cas[k] <= T_RCD - 1;
            else
                c_cas[k] <= dec2(c_cas[k]);
            if (p_c == C_ACT && p_b == k)
                c_pre[k] <= max3(c_pre[k], T_RAS - 1);
            else if (p_c == C_RD && p_b == k)
                c_pre[k] <= max3(c_pre[k], T_RTP - 1);
            else if (p_c == C_WR && p_b == k)
                c_pre[k] <= max3(c_pre[k], T_WR - 1);
            else if (p_c == C_PRE && !p_a[10] && p_b == k)
                c_pre[k] <= max3(c_pre[k], 1);         // cur's flags catch up
            else
                c_pre[k] <= dec3(c_pre[k]);
        end
        c_rrd <= (p_c == C_ACT) ? T_RRD - 1 : dec3(c_rrd);
        c_rtw <= (p_c == C_RD) ? T_RTW - 1 : dec3(c_rtw);
        c_wtr <= (p_c == C_WR) ? T_WTR - 1 : dec3(c_wtr);
        if (p_c == C_ACT) begin
            faw[0] <= 3'd1;
            faw[1] <= age(faw[0]);
            faw[2] <= age(faw[1]);
            faw[3] <= age(faw[2]);
        end else
            for (k = 0; k < 4; k = k + 1)
                faw[k] <= age(faw[k]);
        case (p_c)
            C_ACT: begin
                b_open[p_b] <= 1'b1;
                b_row[p_b] <= p_a;
                if (n_act != 32'hffffffff) n_act <= n_act + 32'd1;
            end
            C_PRE: begin
                if (p_a[10])
                    b_open <= 8'd0;
                else
                    b_open[p_b] <= 1'b0;
            end
            C_REF:
                if (n_ref != 32'hffffffff) n_ref <= n_ref + 32'd1;
            default: ;
        endcase

        // the zero flags, each true when its timer will be zero after this
        // edge: it counts down to zero from 1 or 0 unless the plan sets it,
        // and a max3 set leaves it zero only from zero with a zero floor
        for (k = 0; k < 8; k = k + 1) begin
            za[k] <= (p_c == C_REF) ? 1'b1 :
                     (p_c == C_ACT && p_b == k) ? (T_RC <= 1) :
                     (p_c == C_PRE && (p_a[10] || p_b == k)) ? (c_act[k] == 3'd0 && T_RP <= 1) :
                     (c_act[k] <= 3'd1);
            zc[k] <= (p_c == C_ACT && p_b == k) ? (T_RCD <= 1) : (c_cas[k] <= 2'd1);
            zp[k] <= (p_c == C_ACT && p_b == k) ? (c_pre[k] == 3'd0 && T_RAS <= 1) :
                     (p_c == C_RD && p_b == k) ? (c_pre[k] == 3'd0 && T_RTP <= 1) :
                     (p_c == C_WR && p_b == k) ? (c_pre[k] == 3'd0 && T_WR <= 1) :
                     (p_c == C_PRE && !p_a[10] && p_b == k) ? 1'b0 :
                     (c_pre[k] <= 3'd1);
        end
        z_rrd <= (p_c == C_ACT) ? (T_RRD <= 1) : (c_rrd <= 3'd1);
        z_wtr <= (p_c == C_WR) ? (T_WTR <= 1) : (c_wtr <= 3'd1);
        z_rtw <= (p_c == C_RD) ? (T_RTW <= 1) : (c_rtw <= 3'd1);
        faw_ok <= (p_c == C_ACT) ? (age(faw[2]) >= T_FAW) : (age(faw[3]) >= T_FAW);

        // refresh: due every T_REFI, taken between requests
        refi <= (refi == T_REFI - 1) ? 10'd0 : refi + 10'd1;
        if (refi == T_REFI - 1)
            ref_due <= 1'b1;
        case (f_state)
            // at once, even in a run of row hits, which would never pause;
            // the banks' timers hold the PRECHARGE for what has gone out
            F_RUN: if (ref_due)
                f_state <= F_PRE;
            // only on the precharge of every bank, or with every bank shut and
            // nothing planned: a row command decided before the refresh fell
            // due may still be going out
            F_PRE: if (pre_ok_all && ((b_open == 8'd0 && !p_v) || (p_c == C_PRE && p_a[10])))
                f_state <= F_REF;
            F_REF: if (p_c == C_REF) begin
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
            last_v <= 1'b0;
            b_open <= 8'd0;
            f_state <= F_RUN;
            ref_due <= 1'b0;
            refi <= 10'd0;
            for (k = 0; k < 8; k = k + 1) begin
                c_act[k] <= 3'd0; c_cas[k] <= 2'd0; c_pre[k] <= 3'd0;
            end
            c_rrd <= 3'd0; c_wtr <= 3'd0; c_rtw <= 3'd0;
            for (k = 0; k < 4; k = k + 1) faw[k] <= 3'd7;
            za <= 8'hff; zc <= 8'hff; zp <= 8'hff;
            z_rrd <= 1'b1; z_wtr <= 1'b1; z_rtw <= 1'b1;
            faw_ok <= (7 >= T_FAW);
        end
    end

`ifndef SYNTHESIS
    // the flags must equal their timers' compares at every edge
    integer kz;
    always @(posedge pclk) begin
        if (m_n_r != m_n || m_h_r != m_h)
            $fatal(1, "FAIL  ddr3_ctl: the early row compares disagree with the registers'");
        if (h_v && head_br != fq_br[fq_r])
            $fatal(1, "FAIL  ddr3_ctl: the head's row register disagrees with the FIFO head");
        if (rdy != (!fq_n[2] && !(fq_n[1] && fq_n[0])))
            $fatal(1, "FAIL  ddr3_ctl: the registered ready disagrees with fq_n");
        for (kz = 0; kz < 8; kz = kz + 1)
            if (za[kz] != (c_act[kz] == 3'd0) || zc[kz] != (c_cas[kz] == 2'd0) ||
                    zp[kz] != (c_pre[kz] == 3'd0))
                $fatal(1, "FAIL  ddr3_ctl: bank %0d's zero flags disagree with its timers", kz);
        if (z_rrd != (c_rrd == 3'd0) || z_wtr != (c_wtr == 3'd0) ||
                z_rtw != (c_rtw == 3'd0) || faw_ok != (faw[3] >= T_FAW))
            $fatal(1, "FAIL  ddr3_ctl: a shared timer's zero flag disagrees with it");
    end
`endif
endmodule

`default_nettype wire
