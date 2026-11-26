// SPDX-License-Identifier: GPL-3.0-only
`timescale 1ns/1ps
`default_nettype none

// The video path against a behavioural ddr3_ctl request port, with CPU
// traffic beside it: ddr3_arb, vid_fetch and vid_pix at their real clocks,
// and three TMDS encoders as dvi_tx drives them, decoded here.
//
// The port takes requests with a random ready and returns reads in order
// 4 to 35 PCLK later.  Two frame buffers, pages 0 and 1, hold a pixel
// pattern that names its page, column and row; the CPU's client meanwhile
// writes random words under random masks to 64 lines elsewhere and reads
// them back.  The bench writes BASE as exts_video does, page 0 then a flip
// to page 1 and back in the middle of later frames, and checks, from the
// second frame on, every visible pixel against the page that frame must
// show, the raster's counts and sync positions, that no line was late,
// every CPU read, and that each channel's TMDS symbols decode to the
// pixels and syncs with the running disparity bounded.
module tb_video;
    reg pclk = 1'b0, pix_clk = 1'b0;
    always #4.993 pclk = ~pclk;             // 100.14 MHz
    always #6.734 pix_clk = ~pix_clk;       // 74.25 MHz
    reg rst = 1'b1, pix_rst = 1'b1;

    localparam [24:0] PAGE0 = 25'h1f80000, PAGE1 = 25'h1fa0000;   // 0x7f000000, 0x7f400000
    localparam integer FBW = 115200;        // words in a frame
    localparam integer NL = 64;
    localparam integer FRAMES = 4;

    integer errs = 0;
    task fail(input [8*90-1:0] what);
        begin
            errs = errs + 1;
            if (errs < 10) $display("FAIL  t=%0t %0s", $time, what);
            if (errs == 10) begin
                $display("FAIL  video: stopped at %0d errors", errs);
                $finish;
            end
        end
    endtask

    function [23:0] pix_fn(input integer page, input integer x, input integer y);
        pix_fn = {8'((x * 3 + page * 91) & 255), 8'((y * 5 + x) & 255), 8'((x ^ y ^ (page * 170)) & 255)};
    endfunction
    function [255:0] fb_word(input [24:0] a);
        integer page, w, i, p;
        begin
            page = (a >= PAGE1) ? 1 : 0;
            w = a - (page ? PAGE1 : PAGE0);
            for (i = 0; i < 8; i = i + 1) begin
                p = w * 8 + i;
                fb_word[32*i +: 32] = {8'h5a, pix_fn(page, p % 1280, p / 1280)};  // the X byte is ignored
            end
        end
    endfunction

    // ---- the DUT ---------------------------------------------------------
    wire         v_valid, v_ready, v_rvalid;
    wire [24:0]  v_addr;
    reg          c_valid = 1'b0, c_we = 1'b0;
    wire         c_ready, c_rvalid;
    reg  [24:0]  c_addr = 25'd0;
    reg  [255:0] c_wdata = 256'd0;
    reg  [31:0]  c_wmask = 32'd0;
    wire [255:0] a_rdata;
    wire         x_valid, x_we;
    reg          x_ready = 1'b0, x_rvalid = 1'b0;
    wire [24:0]  x_addr;
    wire [255:0] x_wdata;
    wire [31:0]  x_wmask;
    reg  [255:0] x_rdata = 256'd0;

    ddr3_arb arb (
        .pclk(pclk), .rst(rst),
        .v_valid(v_valid), .v_ready(v_ready), .v_addr(v_addr), .v_rvalid(v_rvalid),
        .c_valid(c_valid), .c_ready(c_ready), .c_we(c_we), .c_addr(c_addr),
        .c_wdata(c_wdata), .c_wmask(c_wmask), .c_rvalid(c_rvalid), .rdata(a_rdata),
        .x_valid(x_valid), .x_ready(x_ready), .x_we(x_we), .x_addr(x_addr),
        .x_wdata(x_wdata), .x_wmask(x_wmask), .x_rvalid(x_rvalid), .x_rdata(x_rdata));

    wire          req_tog;
    wire [24:0]   req_addr;
    wire [2047:0] f_mem;
    wire [3:0]    f_wg, f_rg;
    vid_fetch fetch (
        .pclk(pclk), .rst(rst), .req_tog(req_tog), .req_addr(req_addr),
        .v_valid(v_valid), .v_ready(v_ready), .v_addr(v_addr),
        .v_rvalid(v_rvalid), .v_rdata(a_rdata),
        .f_mem(f_mem), .f_wg(f_wg), .f_rg(f_rg));

    reg          enable = 1'b0, base_tog = 1'b0;
    reg  [24:0]  base_line = PAGE0;
    wire         base_ack, vbl_tog, in_vbl;
    wire [15:0]  late;
    wire [23:0]  rgb;
    wire         de, hs, vs;
    vid_pix pixs (
        .pix_clk(pix_clk), .pix_rst(pix_rst),
        .enable(enable), .base_line(base_line), .base_tog(base_tog), .base_ack(base_ack),
        .vbl_tog(vbl_tog), .in_vbl(in_vbl), .late(late),
        .req_tog(req_tog), .req_addr(req_addr), .f_mem(f_mem), .f_wg(f_wg), .f_rg(f_rg),
        .rgb(rgb), .de(de), .hs(hs), .vs(vs));

    // dvi_tx's encoders, behind its input register
    reg  [23:0] rgb_r = 24'd0;
    reg         de_r = 1'b0, hs_r = 1'b0, vs_r = 1'b0;
    always @(posedge pix_clk) begin
        rgb_r <= rgb; de_r <= de; hs_r <= hs; vs_r <= vs;
    end
    wire [9:0] sym0, sym1, sym2;
    tmds_enc enc0 (.clk(pix_clk), .d(rgb_r[7:0]),   .de(de_r), .c({vs_r, hs_r}), .q(sym0));
    tmds_enc enc1 (.clk(pix_clk), .d(rgb_r[15:8]),  .de(de_r), .c(2'b00),        .q(sym1));
    tmds_enc enc2 (.clk(pix_clk), .d(rgb_r[23:16]), .de(de_r), .c(2'b00),        .q(sym2));

    // ---- the behavioural controller on PCLK -------------------------------
    reg [24:0]  tag [0:NL-1];
    reg [255:0] dmem [0:NL-1];
    reg [255:0] rq_d [0:63];
    reg [31:0]  rq_t [0:63];
    integer     rq_w = 0, rq_r = 0, pcyc = 0, k2, ln, n_vreads = 0;
    reg [31:0]  seed_p = 32'h2345671;
    function integer line_of(input [24:0] a);
        integer k;
        begin
            line_of = -1;
            for (k = 0; k < NL; k = k + 1)
                if (tag[k] == a) line_of = k;
        end
    endfunction
    always @(posedge pclk) begin
        pcyc = pcyc + 1;
        seed_p = seed_p ^ (seed_p << 13); seed_p = seed_p ^ (seed_p >> 17); seed_p = seed_p ^ (seed_p << 5);
        x_rvalid <= 1'b0;
        if (!rst && x_valid && x_ready) begin
            ln = line_of(x_addr);
            if (x_we) begin
                if (ln < 0) fail("a write outside the CPU's lines");
                else for (k2 = 0; k2 < 32; k2 = k2 + 1)
                    if (!x_wmask[k2]) dmem[ln][8*k2 +: 8] = x_wdata[8*k2 +: 8];
            end else begin
                if (ln >= 0) rq_d[rq_w % 64] = dmem[ln];
                else if (x_addr >= PAGE0 && x_addr < PAGE1 + FBW) begin
                    rq_d[rq_w % 64] = fb_word(x_addr);
                    n_vreads = n_vreads + 1;
                end else fail("a read of nothing");
                rq_t[rq_w % 64] = pcyc + 4 + seed_p[4:0];
                rq_w = rq_w + 1;
                if (rq_w - rq_r > 60) fail("the model's read queue overflowed");
            end
        end
        if (rq_r != rq_w && pcyc >= rq_t[rq_r % 64]) begin
            x_rvalid <= 1'b1;
            x_rdata <= rq_d[rq_r % 64];
            rq_r = rq_r + 1;
        end
        x_ready <= seed_p[9:8] != 2'b00;
    end

    // ---- the CPU's client: random masked writes, read back --------------
    reg [255:0] cref [0:NL-1];
    reg [255:0] c_exp [0:63];
    integer     ce_w = 0, ce_r = 0, n_cw = 0, n_cr = 0, ci, cl;
    reg         c_took = 1'b0;
    always @(posedge pclk) c_took <= c_valid && c_ready;
    always @(posedge pclk)
        if (c_rvalid) begin
            if (ce_r == ce_w) fail("the CPU got a word it did not ask for");
            else if (a_rdata !== c_exp[ce_r % 64]) fail("a CPU read returned other than written");
            ce_r = ce_r + 1;
            n_cr = n_cr + 1;
        end
    task c_req(input we, input integer l, input [255:0] d, input [31:0] m);
        integer b;
        begin
            @(negedge pclk);
            c_valid = 1'b1; c_we = we; c_addr = tag[l]; c_wdata = d; c_wmask = m;
            @(negedge pclk);
            while (!c_took) @(negedge pclk);
            c_valid = 1'b0;
            if (we) begin
                for (b = 0; b < 32; b = b + 1)
                    if (!m[b]) cref[l][8*b +: 8] = d[8*b +: 8];
                n_cw = n_cw + 1;
            end else begin
                c_exp[ce_w % 64] = cref[l];
                ce_w = ce_w + 1;
            end
        end
    endtask
    reg cpu_on = 1'b0;
    always begin
        @(negedge pclk);
        if (cpu_on) begin
            cl = $random & (NL - 1);
            if ($random & 1)
                c_req(1'b1, cl, {$random, $random, $random, $random, $random, $random, $random, $random},
                      $random);
            else
                c_req(1'b0, cl, 256'd0, 32'd0);
            repeat ($random & 7) @(negedge pclk);
        end
    end

    // ---- the raster as the sink sees it -----------------------------------
    integer x = 0, y = 0, frame = -1, hcount = 0, de_lines = 0, show_page = 0;
    integer pix_checked = 0, hs_at = -1, vs_line = -1, hs_len = 0;
    reg     de_d = 1'b0, vs_d = 1'b0, hs_d = 1'b0;
    reg [31:0] late_at_frame1 = 32'd0;
    reg [2:0] vbl_s = 3'd0;
    integer page_written = 0, page_pending = -1;
    always @(posedge pix_clk) begin
        if (!pix_rst) begin
            hcount = hcount + 1;
            if (hs && !hs_d) begin
                if (hs_at >= 0 && hcount - hs_at != 1650) fail("a line other than 1650 clocks");
                hs_at = hcount;
            end
            if (hs) hs_len = hs_len + 1;
            if (!hs && hs_d) begin
                if (hs_len != 40) fail("an hsync other than 40 clocks");
                hs_len = 0;
            end
            if (vs && !vs_d) begin
                if (frame >= 0 && de_lines != 720) fail("a frame other than 720 lines");
                frame = frame + 1;
                de_lines = 0;
                y = 0;
                if (frame == 1) late_at_frame1 = late;
            end
            if (de) begin
                if (frame >= 1 && rgb !== pix_fn(show_page, x, y)) begin
                    fail("a pixel other than its page's");
                end
                if (frame >= 1) pix_checked = pix_checked + 1;
                x = x + 1;
            end
            if (!de && de_d) begin
                // from the first vsync: vid_pix's output stages are not reset,
                // so the line under way at reset can be two pixels longer
                if (frame >= 0 && x != 1280) begin
                    $display("      line of %0d pixels at frame %0d row %0d", x, frame, y);
                    fail("a line other than 1280 pixels");
                end
                x = 0;
                y = y + 1;
                de_lines = de_lines + 1;
            end
            de_d = de; vs_d = vs; hs_d = hs;
        end
    end
    // the page a frame shows is the one whose BASE crossed before its blank
    always @(posedge pix_clk) begin
        vbl_s <= {vbl_s[1:0], vbl_tog};
        if (vbl_s[2] ^ vbl_s[1]) begin
            if (page_pending >= 0) begin
                show_page = page_pending;
                page_pending = -1;
            end
        end
    end

    // ---- TMDS: decode each channel, three clocks behind the pixel --------
    // a pixel's symbol leaves the encoder three clocks after it leaves
    // vid_pix, so it is compared with the pixel three edges back
    reg [23:0] rgb_d [0:3];
    reg        de_dd [0:3], hs_dd [0:3], vs_dd [0:3];
    integer    disp [0:2], dk, n_sym = 0;
    function [9:0] symof(input integer c);
        symof = (c == 0) ? sym0 : (c == 1) ? sym1 : sym2;
    endfunction
    function integer ones10(input [9:0] v);
        integer i;
        begin
            ones10 = 0;
            for (i = 0; i < 10; i = i + 1) ones10 = ones10 + v[i];
        end
    endfunction
    reg [9:0] q;
    reg [7:0] dd, dec;
    integer   c, i2;
    always @(posedge pix_clk) begin
        for (dk = 3; dk > 0; dk = dk - 1) begin
            rgb_d[dk] = rgb_d[dk-1]; de_dd[dk] = de_dd[dk-1];
            hs_dd[dk] = hs_dd[dk-1]; vs_dd[dk] = vs_dd[dk-1];
        end
        rgb_d[0] = rgb; de_dd[0] = de; hs_dd[0] = hs; vs_dd[0] = vs;
        if (!pix_rst && frame >= 0) for (c = 0; c < 3; c = c + 1) begin
            q = symof(c);
            if (de_dd[3]) begin
                dd = q[9] ? ~q[7:0] : q[7:0];
                dec[0] = dd[0];
                for (i2 = 1; i2 < 8; i2 = i2 + 1)
                    dec[i2] = q[8] ? (dd[i2] ^ dd[i2-1]) : ~(dd[i2] ^ dd[i2-1]);
                if (dec !== rgb_d[3][8*c +: 8]) fail("a TMDS symbol decoded to another value");
                disp[c] = disp[c] + 2 * ones10(q) - 10;
                if (disp[c] > 20 || disp[c] < -20) fail("TMDS running disparity unbounded");
                n_sym = n_sym + 1;
            end else begin
                disp[c] = 0;
                if (q !== ((c == 0) ? (vs_dd[3] ? (hs_dd[3] ? 10'b1010101011 : 10'b0101010100)
                                                : (hs_dd[3] ? 10'b0010101011 : 10'b1101010100))
                                    : 10'b1101010100))
                    fail("a TMDS control symbol other than its syncs'");
            end
        end
    end

    // ---- BASE, as exts_video writes it --------------------------------
    task write_base(input [24:0] b, input integer page);
        begin
            @(negedge pclk);
            wait (base_ack == base_tog);
            base_line = b;
            base_tog = ~base_tog;
            page_pending = page;
        end
    endtask

    integer n;
    initial begin
        for (n = 0; n < 3; n = n + 1) disp[n] = 0;
        for (n = 0; n < 4; n = n + 1) begin de_dd[n] = 0; hs_dd[n] = 0; vs_dd[n] = 0; rgb_d[n] = 0; end
        for (n = 0; n < NL; n = n + 1) begin
            tag[n] = ($random & 25'h0fffff0) | n;
            dmem[n] = {$random, $random, $random, $random, $random, $random, $random, $random};
            cref[n] = dmem[n];
        end
        repeat (5) @(posedge pclk);
        rst = 1'b0;
        repeat (3) @(posedge pix_clk);
        pix_rst = 1'b0;
        cpu_on = 1'b1;
        enable = 1'b1;
        // frame 0 fills from the middle; frames 1 on are checked
        wait (frame == 1);
        wait (y == 300);
        write_base(PAGE1, 1);                     // frame 2 shows page 1
        wait (frame == 2);
        wait (y == 500);
        write_base(PAGE0, 0);                     // frame 3 shows page 0
        wait (frame == FRAMES);
        cpu_on = 1'b0;
        repeat (200) @(posedge pclk);
        $display("      %0d frames, %0d pixels checked, %0d TMDS data symbols decoded",
                 FRAMES - 1, pix_checked, n_sym);
        $display("      %0d video words read, LATE %0d before frame 1 and %0d after; CPU %0d writes and %0d reads",
                 n_vreads, late_at_frame1, late, n_cw, n_cr);
        if (late != late_at_frame1) fail("a line was late after the first frame");
        if (pix_checked != (FRAMES - 1) * 1280 * 720) fail("not every pixel was checked");
        if (n_cr < 1000) fail("too little CPU traffic");
        if (errs == 0)
            $display("PASS  video: every pixel of every frame from its page, flips at the blank, TMDS decoded");
        else
            $display("FAIL  video: %0d errors", errs);
        $finish;
    end
endmodule

`default_nettype wire
