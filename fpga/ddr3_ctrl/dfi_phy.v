`default_nettype none

// The DFI side of the trained PHY: a controller's four DFI phases in, the
// pads' per-phase commands, per-pin write words and drive enables out, and
// the captured bursts back to the controller at a fixed latency.
//
// Everything here is relative to the trained PHY of fpga/ddr3_write, which
// issues one command per PCLK in its first memory clock and whose training
// (TOOL-045) leaves:
//
//   * a write alignment {d, 0, b}: wr_core sets a WRITE's word one PCLK
//     before the WRITE reaches the command registers, and its serializers
//     carry that word d PCLK and b beats later -- beats b..7 of the burst
//     starting in one serializer word, beats 0..b-1 the burst before.  Here
//     d and b are built in, WD and WB, d 1 and b 2 as every training of the
//     open-flow image has found: selecting them at run time put a word and
//     a beat multiplexer on each of the 256 bits, which pulled some 4,000
//     LUTs to the lanes' corner and left the image unplaceable; ctrl_glue
//     hands the bus over only when the training found these;
//   * a read burst on the raw deserializer outputs a fixed number of PCLK,
//     7 on the board (TOOL-043, offset 11 less rd_check's PIPE of 4), after
//     the cycle the READ sat in the command registers, whole, with each
//     lane's trained rotation.
//
// The controller, ddr3_ctl, puts READ and WRITE on phase 0 only, a WRITE's
// data on the DFI WRITE_LATENCY = 1 PCLK after its wrdata_en, and takes a
// READ's data READ_LATENCY = 15 PCLK after its rddata_en.  So:
//
//   * every phase's command reaches the pads three PCLK after the DFI
//     presented it, all alike, so every spacing the controller kept holds
//     on the bus; a CAS command on another phase is flagged, never issued
//     differently;
//   * a WRITE's data, on the DFI the PCLK after its wrdata_en, is registered
//     so it is this module's newest word the PCLK before the WRITE reaches
//     the command registers -- where wr_core's fill sets its word -- and then
//     takes the same d PCLK and b beats per pin;
//   * DQ and DQS are driven from the PCLK before a burst's first serializer
//     word to the PCLK after its last, and ODT is high in the WRITE's PCLK
//     and the next (ODTH8), never at a READ, which the controller keeps at
//     least four PCLK after a WRITE;
//   * a READ's burst is taken from the raw deserializers 6 + rd_off PCLK
//     after the READ sat in the command registers, rd_off 0..3 settable from
//     the link and 1 by default, the board's 7, de-rotated by
//     ddr3_derot with the trained rotations, and handed to the DFI at
//     PCLK 12 after the command registers whatever rd_off is, which is
//     READ_LATENCY 15 after the DFI.
//
// Data layouts.  The DFI's phase p, bit j is beat 2p + j / 32 of DQ j % 32,
// so the four phases together are beat-major: beat b, DQ q at 32b + q, which
// is ddr3_derot's output.  The pads take each pin's eight beats: lane l, pin
// p, beat b at 64l + 8p + b.
module dfi_phy #(
    parameter integer WD = 1,           // the write alignment's d, PCLK
    parameter integer WB = 2            // and b, beats
) (
    input  wire         pclk,
    input  wire         rst,            // the bus is not the controller's

    // DFI, phase p in bit p or at p * width
    input  wire [3:0]   dfi_cs_n,
    input  wire [3:0]   dfi_ras_n,
    input  wire [3:0]   dfi_cas_n,
    input  wire [3:0]   dfi_we_n,
    input  wire [59:0]  dfi_address,    // phase p at 15p +: 15
    input  wire [11:0]  dfi_bank,       // phase p at 3p +: 3
    input  wire [255:0] dfi_wrdata,     // phase p at 64p +: 64
    input  wire [31:0]  dfi_wrmask,     // 1 suppresses beat b, lane l at 4b + l
    input  wire [3:0]   dfi_wrdata_en,
    input  wire [3:0]   dfi_rddata_en,
    output reg  [255:0] dfi_rddata = 256'd0,
    output reg  [3:0]   dfi_rddata_valid = 4'd0,

    // the training's results, still while the controller owns the bus
    input  wire [11:0]  rot,            // per lane, 3 bits
    input  wire [1:0]   rd_off,         // the burst 6 + rd_off PCLK after the READ
    input  wire [255:0] dq_q,           // lane l, pin p, beat b at 64l + 8p + b

    // the pads
    output reg  [3:0]   p_cs_n = 4'hf,
    output reg  [3:0]   p_ras_n = 4'hf,
    output reg  [3:0]   p_cas_n = 4'hf,
    output reg  [3:0]   p_we_n = 4'hf,
    output reg  [11:0]  p_ba = 12'd0,
    output reg  [63:0]  p_addr = 64'd0, // phase p at 16p +: 16
    output reg          p_odt = 1'b0,
    output reg          p_dq_drive = 1'b0,
    output reg          p_dqs_drive = 1'b0,
    output reg  [255:0] wdq = 256'd0,
    output reg  [31:0]  p_dm = 32'd0,   // lane l, beat b at 8l + b: the DM pads
    output reg          rd_load = 1'b0, // a READ loads the command registers at this edge
    output reg          bad_phase = 1'b0,   // a READ or WRITE came on phase 1, 2 or 3
    output reg  [31:0]  n_wr = 32'd0,
    output reg  [31:0]  n_rd = 32'd0
);
    // ---- commands: two stages, then the pads' registers ------------------
    reg [3:0]  s1_cs_n = 4'hf, s1_ras_n = 4'hf, s1_cas_n = 4'hf, s1_we_n = 4'hf;
    reg [11:0] s1_ba = 12'd0;
    reg [59:0] s1_addr = 60'd0;
    reg [3:0]  s2_cs_n = 4'hf, s2_ras_n = 4'hf, s2_cas_n = 4'hf, s2_we_n = 4'hf;
    reg [11:0] s2_ba = 12'd0;
    reg [59:0] s2_addr = 60'd0;
    reg        s2_rd = 1'b0, s2_wr = 1'b0, out_wr = 1'b0;
    // phase 0 of stage 1: a READ or a WRITE
    wire s1_cas = !s1_cs_n[0] && s1_ras_n[0] && !s1_cas_n[0];
    integer ph;
    always @(posedge pclk) begin
        if (rst) begin
            s1_cs_n <= 4'hf; s2_cs_n <= 4'hf; p_cs_n <= 4'hf;
            s2_rd <= 1'b0; s2_wr <= 1'b0; out_wr <= 1'b0;
            rd_load <= 1'b0;
            p_odt <= 1'b0;
            bad_phase <= 1'b0;
            n_wr <= 32'd0;
            n_rd <= 32'd0;
        end else begin
            s1_cs_n <= dfi_cs_n;
            s2_cs_n <= s1_cs_n;
            p_cs_n <= s2_cs_n;
            s2_rd <= s1_cas && s1_we_n[0];
            s2_wr <= s1_cas && !s1_we_n[0];
            rd_load <= s1_cas && s1_we_n[0];
            out_wr <= s2_wr;
            p_odt <= s2_wr || out_wr;
            for (ph = 1; ph < 4; ph = ph + 1)
                if (!s1_cs_n[ph] && s1_ras_n[ph] && !s1_cas_n[ph])
                    bad_phase <= 1'b1;
            if (s2_wr && n_wr != 32'hffffffff) n_wr <= n_wr + 32'd1;
            if (s2_rd && n_rd != 32'hffffffff) n_rd <= n_rd + 32'd1;
        end
        s1_ras_n <= dfi_ras_n; s1_cas_n <= dfi_cas_n; s1_we_n <= dfi_we_n;
        s1_ba <= dfi_bank;     s1_addr <= dfi_address;
        s2_ras_n <= s1_ras_n;  s2_cas_n <= s1_cas_n;  s2_we_n <= s1_we_n;
        s2_ba <= s1_ba;        s2_addr <= s1_addr;
        p_ras_n <= s2_ras_n;   p_cas_n <= s2_cas_n;   p_we_n <= s2_we_n;
        p_ba <= s2_ba;
        for (ph = 0; ph < 4; ph = ph + 1)
            p_addr[16*ph +: 16] <= {1'b0, s2_addr[15*ph +: 15]};
    end

    // ---- write data ----------------------------------------------------
    // wrdata_en with the WRITE at the DFI (cycle C), its data on the DFI at
    // C + 1 while wen_d is high, this module's newest word at C + 2, the
    // WRITE in the command registers at C + 3
    reg wen_d = 1'b0;
    always @(posedge pclk)
        wen_d <= !rst && (|dfi_wrdata_en);
    // the DFI's beat-major burst, pin-major for the serializers
    wire [255:0] wr_pin;
    genvar gl, gp, gb;
    generate
        for (gl = 0; gl < 4; gl = gl + 1) begin : g_wl
            for (gp = 0; gp < 8; gp = gp + 1) begin : g_wp
                for (gb = 0; gb < 8; gb = gb + 1) begin : g_wb
                    assign wr_pin[64*gl + 8*gp + gb] = dfi_wrdata[32*gb + 8*gl + gp];
                end
            end
        end
    endgenerate
    // word k of the delay line, k = 0 the newest: wd[k] and its flag wf[k];
    // wfx[k + 1] is wf[k], and wfx[0] the flag of the word loading now
    reg [255:0] wd [0:WD+1];
    reg [31:0]  wm [0:WD+1];            // the write masks, beside the data
    reg [WD+3:0] wf = {(WD+4){1'b0}};
    wire [WD+4:0] wfx = {wf, wen_d};
    integer k;
    initial for (k = 0; k < WD + 2; k = k + 1) begin
        wd[k] = 256'd0;
        wm[k] = 32'd0;
    end
    always @(posedge pclk) begin
        wd[0] <= wen_d ? wr_pin : 256'd0;
        wm[0] <= wen_d ? dfi_wrmask : 32'd0;
        for (k = 1; k < WD + 2; k = k + 1) begin
            wd[k] <= wd[k - 1];
            wm[k] <= wm[k - 1];
        end
        wf <= {wf[WD+2:0], wen_d} & {(WD+4){!rst}};
    end
    // beats b..7 carry the burst in word d, 0..b-1 the one before in word
    // d + 1, as wr_core's fill; DQ and DQS driven from the PCLK before the
    // burst's first serializer word to the one after its last, words
    // d - 1 .. d + 2 at this edge
    wire [255:0] w_new = wd[WD];
    wire [255:0] w_old = wd[WD + 1];
    // the mask of each of those two words: a lane's 8 DM bits are gathered
    // from the mask's 4 bits a beat, then rotated by the same shift the data
    // takes, so a beat's DM bit sits where that beat's data does
    wire [31:0] m_new = wm[WD];
    wire [31:0] m_old = wm[WD + 1];
    reg  [31:0] mbyte_new, mbyte_old;
    integer ml, mb;
    always @(*) begin
        for (ml = 0; ml < 4; ml = ml + 1)
            for (mb = 0; mb < 8; mb = mb + 1) begin
                mbyte_new[8*ml + mb] = m_new[4*mb + ml];
                mbyte_old[8*ml + mb] = m_old[4*mb + ml];
            end
    end
    integer pn;
    reg [15:0] pair;
    reg [15:0] mpair;
    always @(posedge pclk) begin
        for (pn = 0; pn < 32; pn = pn + 1) begin
            pair = {w_new[8*pn +: 8], w_old[8*pn +: 8]};
            wdq[8*pn +: 8] <= pair >> (8 - WB);
        end
        for (ml = 0; ml < 4; ml = ml + 1) begin
            mpair = {mbyte_new[8*ml +: 8], mbyte_old[8*ml +: 8]};
            p_dm[8*ml +: 8] <= mpair >> (8 - WB);
        end
        p_dq_drive <= !rst && (|wfx[WD+3:WD]);
        p_dqs_drive <= !rst && (|wfx[WD+3:WD]);
    end

    // ---- read data -----------------------------------------------------
    // rp[j]: a READ sat in the command registers j PCLK ago
    reg [11:0] rp = 12'd0;
    always @(posedge pclk)
        rp <= {rp[10:0], rd_load} & {12{!rst}};
    wire [255:0] rd_derot;              // the deserializers' word of the PCLK before
    ddr3_derot derot (.pclk(pclk), .dq_q(dq_q), .rot(rot), .data(rd_derot));
    // a burst on dq_q at PCLK 6 + rd_off is in rs1 at 8 + rd_off, rs4 at 11
    // for rd_off 0, rs1 at 11 for rd_off 3
    reg [255:0] rs1 = 256'd0, rs2 = 256'd0, rs3 = 256'd0, rs4 = 256'd0;
    always @(posedge pclk) begin
        rs1 <= rd_derot;
        rs2 <= rs1;
        rs3 <= rs2;
        rs4 <= rs3;
        case (rd_off)
            2'd0: dfi_rddata <= rs4;
            2'd1: dfi_rddata <= rs3;
            2'd2: dfi_rddata <= rs2;
            default: dfi_rddata <= rs1;
        endcase
        dfi_rddata_valid <= {4{rp[11]}};
    end
endmodule

`default_nettype wire
