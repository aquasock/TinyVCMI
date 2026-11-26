// SPDX-License-Identifier: GPL-3.0-only
`default_nettype none

// 1280x720 at 60 Hz from a 32-bit frame buffer in the DDR3, in two halves
// that the top level places apart, as ahb_ddr3's are: vid_fetch on PCLK,
// beside ddr3_ctl, and vid_pix on the pixel clock, beside the HDMI pins.
//
// Each line is 160 DDR3 words of eight pixels, 0x00RRGGBB, pixel i of a word
// in its bits 32i+23 to 32i.  At the start of every line the pixel side asks
// for the next visible one -- line y + 1 during line y, line 0 during the
// last blank line -- by moving req_tog with the line's first word address in
// req_addr, and the fetcher reads those 160 words through ddr3_arb into an
// eight-word FIFO of flip-flops, written on PCLK and read on the pixel clock
// with Gray-coded pointers.  It reads no further ahead than the FIFO has room
// for, counting the reads in flight, so the FIFO never overflows and the CPU
// is never held off for more than eight words.  The pixel side moves each
// word into the line buffer two pixels a clock, so a line's fill takes about
// 640 pixel clocks after its first word arrives, of the 1650 it has.
//
// The line buffers are block RAM with both ports on the pixel clock, because
// block RAM written on one clock and read on another reads back wrong in
// this open flow on this chip (TinyNES core-log entry 14): two banks, even
// and odd pixels, each holding both lines, 24 bits wide.  A request is made
// only once the last one's 160 words have all arrived, so each request's
// words are exactly the next 160 the FIFO gives; a line whose pixels are not
// all in when it begins is counted in late and shown with what is there.
//
// The raster is CEA-861's 1280x720p60, 1650 by 750 clocks of 74.25 MHz,
// syncs positive.  BASE is taken at the first blank line, so a frame never
// mixes two buffers.  With enable low nothing is fetched and the picture is
// black.
//
// Simulation-only: MUT_PAIR writes each pixel pair swapped; the video bench
// (tb_video.v) must fail it.

// ---- PCLK: the fetcher and the FIFO's write side ----------------------------
module vid_fetch #(
    parameter integer WORDS = 160
) (
    input  wire           pclk,
    input  wire           rst,              // ctrl_glue's x_rst
    input  wire           req_tog,          // pix_clk
    input  wire [24:0]    req_addr,         // still from req_tog's move
    output reg            v_valid = 1'b0,
    input  wire           v_ready,
    output reg  [24:0]    v_addr = 25'd0,
    input  wire           v_rvalid,
    input  wire [255:0]   v_rdata,
    output reg  [2047:0]  f_mem = 2048'd0,  // the FIFO's eight words
    output reg  [3:0]     f_wg = 4'd0,      // its write pointer, Gray
    input  wire [3:0]     f_rg              // its read pointer, Gray, pix_clk
);
    function [3:0] g2b(input [3:0] g);
        g2b = {g[3], g[3] ^ g[2], g[3] ^ g[2] ^ g[1], g[3] ^ g[2] ^ g[1] ^ g[0]};
    endfunction
    function [3:0] b2g(input [3:0] b);
        b2g = b ^ {1'b0, b[3:1]};
    endfunction

    reg [2:0] r_s = 3'd0;                   // req_tog through two flops, and the last
    reg [3:0] rg_s1 = 4'd0, rg_s2 = 4'd0;   // the read pointer, synchronised
    reg [3:0] f_w = 4'd0;                   // the write pointer, binary
    reg [7:0] left = 8'd0;                  // words of this request not yet asked for
    reg [3:0] flight = 4'd0;                // asked for, not yet in the FIFO
    wire [3:0] occ = f_w - g2b(rg_s2);      // in the FIFO, as far as PCLK can tell
    wire       take = v_valid && v_ready;
    wire [7:0] left_n = left - take;
    // in flight plus in the FIFO after this edge: a read taken adds one, a
    // word arriving moves one from flight to the FIFO
    wire [4:0] used_n = flight + occ + take;

    always @(posedge pclk) begin
        r_s <= {r_s[1:0], req_tog};
        rg_s1 <= f_rg;
        rg_s2 <= rg_s1;
        if (take)
            v_addr <= v_addr + 1'b1;
        left <= left_n;
        flight <= flight + take - v_rvalid;
        if (r_s[2] ^ r_s[1]) begin          // a new line: nothing of the last is left
            v_addr <= req_addr;
            left <= WORDS;
        end
        v_valid <= (r_s[2] ^ r_s[1]) || (left_n != 8'd0 && used_n < 5'd8);
        if (v_rvalid) begin
            f_mem[256*f_w[2:0] +: 256] <= v_rdata;
            f_w <= f_w + 1'b1;
            f_wg <= b2g(f_w + 1'b1);
        end
        if (rst) begin
            r_s <= {3{req_tog}};
            v_valid <= 1'b0;
            left <= 8'd0;
            flight <= 4'd0;
        end
    end

`ifndef SYNTHESIS
    always @(posedge pclk)
        if (!rst && (r_s[2] ^ r_s[1]) && (left != 8'd0 || flight != 4'd0))
            $fatal(1, "vid_fetch: a line was asked for before the last had arrived");
    always @(posedge pclk)
        if (!rst && v_rvalid && occ == 4'd8)
            $fatal(1, "vid_fetch: a word arrived to a full FIFO");
`endif
endmodule

// ---- the pixel clock: raster, line buffers, the FIFO's read side ------------
module vid_pix #(
    parameter integer WORDS = 160
) (
    input  wire           pix_clk,
    input  wire           pix_rst,
    // the bus side's registers (exts_video), on bus_clk
    input  wire           enable,
    input  wire [24:0]    base_line,
    input  wire           base_tog,
    output reg            base_ack = 1'b0,
    output reg            vbl_tog = 1'b0,
    output reg            in_vbl = 1'b0,
    output reg  [15:0]    late = 16'd0,
    // the fetcher
    output reg            req_tog = 1'b0,
    output reg  [24:0]    req_addr = 25'd0,
    input  wire [2047:0]  f_mem,            // PCLK; a word is still once f_wg says it is in
    input  wire [3:0]     f_wg,             // PCLK
    output reg  [3:0]     f_rg = 4'd0,
    // to dvi_tx
    output reg  [23:0]    rgb = 24'd0,
    output reg            de = 1'b0,
    output reg            hs = 1'b0,
    output reg            vs = 1'b0
);
    localparam integer H_ACTIVE = 1280, H_TOTAL = 1650, HS_START = 1390, HS_END = 1430;
    localparam integer V_ACTIVE = 720,  V_TOTAL = 750,  VS_START = 725,  VS_END = 730;

    function [3:0] b2g(input [3:0] b);
        b2g = b ^ {1'b0, b[3:1]};
    endfunction

    // ---- the registers, synchronised ----
    reg [1:0]  en_s = 2'b00;
    reg [2:0]  bt_s = 3'd0;
    reg [24:0] base_pend = 25'h1f80000, base_cur = 25'h1f80000;   // BASE's reset value
    reg        pend = 1'b0;

    // ---- the raster ----
    reg [10:0] cx = 11'd0;
    reg [9:0]  cy = 10'd0;
    wire       line_start = (cx == 11'd0);

    // ---- the fill ----
    reg [3:0]  wg_s1 = 4'd0, wg_s2 = 4'd0;
    reg [3:0]  f_r = 4'd0;                  // the read pointer, binary
    wire       f_any = (b2g(f_r) != wg_s2);
    reg        filling = 1'b0;
    reg [1:0]  done = 2'b00;                // line buffer b holds a whole line
    reg        wbuf = 1'b0;
    reg [9:0]  wptr = 10'd0;                // pixel pair being written
    reg [255:0] wd = 256'd0;                // the word being written
    reg [1:0]  wsub = 2'd0;                 // its pixel pair
    reg        wv = 1'b0;                   // wd holds pairs not yet written
    reg [7:0]  words_in = 8'd0;             // of this request

    // the line buffers: pixel pair p of buffer b at {b, p}, even and odd
    reg [23:0] even_mem [0:2047];
    reg [23:0] odd_mem  [0:2047];
    reg [23:0] even_q = 24'd0, odd_q = 24'd0;
    wire       pair_last = (wsub == 2'd3);
    wire       pop = filling && f_any && (!wv || pair_last);

    // the visible line's next visible and its buffer
    wire       want = (cy == V_TOTAL - 1) || (cy < V_ACTIVE - 1);
    wire [9:0] ny = (cy == V_TOTAL - 1) ? 10'd0 : cy + 1'b1;

    // display pipeline: stage 1 has the buffers' outputs, stage 2 the pixel
    reg        de1 = 1'b0, hs1 = 1'b0, vs1 = 1'b0, odd1 = 1'b0, on1 = 1'b0;

    always @(posedge pix_clk) begin
        en_s <= {en_s[0], enable};
        bt_s <= {bt_s[1:0], base_tog};
        if (bt_s[2] ^ bt_s[1]) begin
            base_pend <= base_line;
            pend <= 1'b1;
        end

        // raster
        cx <= (cx == H_TOTAL - 1) ? 11'd0 : cx + 1'b1;
        if (cx == H_TOTAL - 1)
            cy <= (cy == V_TOTAL - 1) ? 10'd0 : cy + 1'b1;

        if (line_start && cy == V_ACTIVE) begin     // the first blank line
            vbl_tog <= ~vbl_tog;
            in_vbl <= 1'b1;
            if (pend || (bt_s[2] ^ bt_s[1])) begin
                base_cur <= (bt_s[2] ^ bt_s[1]) ? base_line : base_pend;
                pend <= 1'b0;
                base_ack <= bt_s[1];
            end
        end
        if (line_start && cy == 10'd0)
            in_vbl <= 1'b0;
        if (line_start && cy < V_ACTIVE && en_s[1] && !done[cy[0]])
            late <= late + 1'b1;

        // a fill is asked for at the start of a line, once the last is in
        if (line_start && want && en_s[1] && !filling) begin
            req_addr <= base_cur + {ny, 7'd0} + {ny, 5'd0};  // + 160 ny
            req_tog <= ~req_tog;
            filling <= 1'b1;
            wbuf <= ny[0];
            done[ny[0]] <= 1'b0;
            wptr <= 10'd0;
            words_in <= 8'd0;
        end

        // the FIFO's words into the line buffer, a pixel pair a clock
        wg_s1 <= f_wg;
        wg_s2 <= wg_s1;
        if (wv) begin
`ifdef MUT_PAIR
            even_mem[{wbuf, wptr}] <= wd[64*wsub + 32 +: 24];   // the pair swapped
            odd_mem[{wbuf, wptr}]  <= wd[64*wsub +: 24];
`else
            even_mem[{wbuf, wptr}] <= wd[64*wsub +: 24];
            odd_mem[{wbuf, wptr}]  <= wd[64*wsub + 32 +: 24];
`endif
            wptr <= wptr + 1'b1;
            wsub <= wsub + 1'b1;
            if (pair_last) begin
                wv <= 1'b0;
                if (words_in == WORDS) begin
                    filling <= 1'b0;
                    done[wbuf] <= 1'b1;
                end
            end
        end
        if (pop) begin
            wd <= f_mem[256*f_r[2:0] +: 256];
            wv <= 1'b1;
            wsub <= 2'd0;
            words_in <= words_in + 1'b1;
            f_r <= f_r + 1'b1;
            f_rg <= b2g(f_r + 1'b1);
        end

        // display: read both banks at the pair, choose the half
        even_q <= even_mem[{cy[0], cx[10:1]}];
        odd_q  <= odd_mem[{cy[0], cx[10:1]}];
        de1 <= (cx < H_ACTIVE) && (cy < V_ACTIVE);
        hs1 <= (cx >= HS_START) && (cx < HS_END);
        vs1 <= (cy >= VS_START) && (cy < VS_END);
        odd1 <= cx[0];
        on1 <= en_s[1];
        rgb <= (de1 && on1) ? (odd1 ? odd_q : even_q) : 24'd0;
        de <= de1;
        hs <= hs1;
        vs <= vs1;

        if (pix_rst) begin
            cx <= 11'd0;
            cy <= 10'd0;
            filling <= 1'b0;
            done <= 2'b00;
            wv <= 1'b0;
            pend <= 1'b0;
            f_r <= 4'd0;
            f_rg <= 4'd0;
            late <= 16'd0;
        end
    end
endmodule

`default_nettype wire
