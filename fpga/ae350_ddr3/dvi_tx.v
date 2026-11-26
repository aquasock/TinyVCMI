// SPDX-License-Identifier: GPL-3.0-only
`default_nettype none

// A DVI transmitter for the HDMI port: three TMDS channels and the clock
// lane, on the pixel clock and its five-times serial clock.  DVI carries
// video only (no data islands, so no audio or InfoFrames), which every HDMI
// sink accepts.
//
// Each channel encodes as DVI 1.0 section 3.2 gives it: during display
// enable, the 8-bit value is transition-minimised (XOR or XNOR chain,
// whichever gives fewer transitions) and then DC-balanced against a running
// disparity; outside it the channel sends one of four control symbols, and
// channel 0's are hsync and vsync.  Blue is channel 0, green 1, red 2.  Word
// bit 0 is sent first, OSER10's D0.
//
// The clock lane is an OSER10 sending 0000011111, as TinyNES learned to make
// it (TinyNES DEV-018): a pixel clock driven straight into its output buffer
// glitched when warm.  The serialisers take no run-time reset; FPGA
// configuration initialises them.
//
// Simulation-only: MUT_DISP gets one disparity update's sign wrong; the
// video bench (tb_video.v) must fail it.
//
// Timing: rgb, de, hs and vs are registered here, the encoder is two
// registered stages, so the picture leaves three pixel clocks after its
// inputs; the caller delays its syncs with its pixels and needs nothing else.
module dvi_tx (
    input  wire        pix_clk,
    input  wire        pix_clk5,
    input  wire [23:0] rgb,             // {red, green, blue}
    input  wire        de,
    input  wire        hs,
    input  wire        vs,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_d_p,
    output wire [2:0]  tmds_d_n
);
    reg [23:0] rgb_r = 24'd0;
    reg        de_r = 1'b0, hs_r = 1'b0, vs_r = 1'b0;
    always @(posedge pix_clk) begin
        rgb_r <= rgb;
        de_r <= de;
        hs_r <= hs;
        vs_r <= vs;
    end

    wire [9:0] sym0, sym1, sym2;
    tmds_enc enc0 (.clk(pix_clk), .d(rgb_r[7:0]),   .de(de_r), .c({vs_r, hs_r}), .q(sym0));
    tmds_enc enc1 (.clk(pix_clk), .d(rgb_r[15:8]),  .de(de_r), .c(2'b00),        .q(sym1));
    tmds_enc enc2 (.clk(pix_clk), .d(rgb_r[23:16]), .de(de_r), .c(2'b00),        .q(sym2));
    wire [39:0] word = {10'b0000011111, sym2, sym1, sym0};   // lane 3 is the clock

    wire [3:0] ser;
    genvar ch;
    generate
        for (ch = 0; ch < 4; ch = ch + 1) begin : lane
            OSER10 ser10 (
                .Q(ser[ch]),
                .D0(word[10*ch+0]), .D1(word[10*ch+1]), .D2(word[10*ch+2]),
                .D3(word[10*ch+3]), .D4(word[10*ch+4]), .D5(word[10*ch+5]),
                .D6(word[10*ch+6]), .D7(word[10*ch+7]), .D8(word[10*ch+8]),
                .D9(word[10*ch+9]),
                .PCLK(pix_clk), .FCLK(pix_clk5), .RESET(1'b0));
        end
    endgenerate

    // {clock lane, red, green, blue}
    ELVDS_OBUF tmds_buf [3:0] (
        .I(ser),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n}));
endmodule

// One TMDS channel's encoder, DVI 1.0 section 3.2.2, in two registered
// stages: the transition-minimised word and its ones count, then the
// DC balance, whose running disparity is the one loop between them.
module tmds_enc (
    input  wire       clk,
    input  wire [7:0] d,
    input  wire       de,
    input  wire [1:0] c,                // {C1, C0}
    output reg  [9:0] q = 10'd0
);
    function [3:0] ones8(input [7:0] v);
        integer i;
        begin
            ones8 = 4'd0;
            for (i = 0; i < 8; i = i + 1)
                ones8 = ones8 + v[i];
        end
    endfunction

    // stage 1: q_m and its ones count
    wire [3:0] n1d = ones8(d);
    wire       use_xnor = (n1d > 4'd4) || (n1d == 4'd4 && !d[0]);
    reg  [8:0] qm;
    integer i;
    always @(*) begin
        qm[0] = d[0];
        for (i = 1; i < 8; i = i + 1)
            qm[i] = use_xnor ? ~(qm[i-1] ^ d[i]) : (qm[i-1] ^ d[i]);
        qm[8] = !use_xnor;
    end
    reg [8:0] qm_r = 9'd0;
    reg [3:0] n1q_r = 4'd0;
    reg       de1 = 1'b0;
    reg [1:0] c1 = 2'b00;
    always @(posedge clk) begin
        qm_r <= qm;
        n1q_r <= ones8(qm[7:0]);
        de1 <= de;
        c1 <= c;
    end

    // stage 2: DC balance; cnt is the running disparity, ones minus zeros
    reg signed [4:0] cnt = 5'sd0;
    wire signed [4:0] n1 = {1'b0, n1q_r};
    wire signed [4:0] diff = n1 + n1 - 5'sd8;               // ones - zeros
    always @(posedge clk) begin
        if (!de1) begin
            cnt <= 5'sd0;
            case (c1)
                2'b00: q <= 10'b1101010100;
                2'b01: q <= 10'b0010101011;
                2'b10: q <= 10'b0101010100;
                default: q <= 10'b1010101011;
            endcase
        end else if (cnt == 5'sd0 || diff == 5'sd0) begin
            q <= {~qm_r[8], qm_r[8], qm_r[8] ? qm_r[7:0] : ~qm_r[7:0]};
            cnt <= qm_r[8] ? cnt + diff : cnt - diff;
        end else if ((cnt > 5'sd0 && diff > 5'sd0) || (cnt < 5'sd0 && diff < 5'sd0)) begin
            q <= {1'b1, qm_r[8], ~qm_r[7:0]};
`ifdef MUT_DISP
            cnt <= cnt + (qm_r[8] ? 5'sd2 : 5'sd0) + diff;     // the balance's sign wrong
`else
            cnt <= cnt + (qm_r[8] ? 5'sd2 : 5'sd0) - diff;
`endif
        end else begin
            q <= {1'b0, qm_r[8], qm_r[7:0]};
            cnt <= cnt - (qm_r[8] ? 5'sd0 : 5'sd2) + diff;
        end
    end
endmodule

`default_nettype wire
