`default_nettype none

// DDR3 MPR read-back: the control and readout half of the image.
//
// The PHY half is generated into top.v by tools/ddr3_mpr.py, in the shapes
// of fpga/ddr3_phy_bringup.  This module brings the PHY up in the order the
// hardware-proven controller does, initializes the DDR3 device, puts it in
// MPR mode and streams reads, so the read path can be checked against a
// pattern the device produces by itself -- nothing is ever written to it.
//
// PHY start-up, 50 MHz board clock.  The order and spacing are the vendor
// IP's `ddr_sync` block, traced from its netlist by
// tools/vendor_memsync_trace.py:
//
//   power-on reset (65536 cycles), then release the DLL, and the CLKDIV and
//   lanes three cycles later; wait for DLL LOCK, then 16384 cycles;
//   HOLD high; UPDNCNTL low for 4 cycles; HOLD low after 4 more;
//   stop the memory clock (PLL ENCLK low) 15 cycles later;
//   pulse the CLKDIV and lane reset for 4 cycles with the clock stopped;
//   restart the clock 4 cycles later; READY 9 cycles after that.
//
// DDR3 initialization, PCLK (100 MHz, four memory clocks per cycle), JEDEC
// power-up with DDR3-800 timing, every command in the cycle's first slot:
//
//   RESET# low 200 us after READY, then high; CKE low 500 us more, then
//   high; 320 ns; MRS MR2, MR3, MR1, MR0 80 ns apart; ZQCL and 2.56 us;
//   MRS MR3 with MPR on; then a READ every cycle while reads are on.
//
//   MR0 0x0520  BL8, CL 6, DLL reset, write recovery 6
//   MR1 0x0044  DLL on, RZQ/6 drive, RTT_NOM RZQ/6 (off: ODT is held low)
//   MR2 0x0000  CWL 5
//   MR3 0x0004  MPR on, predefined pattern (0x0000 before)
//
// No refresh is issued: MPR reads return a pattern, not stored data, and
// nothing in the array is relied on.  ODT stays low, and every DQ, DM and
// strobe output stays in tristate.
//
// Every MPR burst is 0,1,0,1,0,1,0,1 on every DQ, so with back-to-back reads
// each IDES8_MEM word is 0x55 or 0xAA whatever the alignment.  Per lane the
// core counts PCLK cycles in which all eight DQ words are equal and one of
// the two, over a window of 65535 cycles.
//
// Requests, AA 00 <cmd> <arg>, 2 Mbaud on the TinyTang link.  The status
// request answers AA 00 04 38 <56 bytes>; every other request answers the
// core ID frame AA 00 02 01 56 as an acknowledgement.
//
//   01        core ID
//   03        status
//   04        snapshot every lane's eight DQ words at the next PCLK
//   05        restart everything from the power-on reset
//   06 n      RCLKSEL = n[2:0] on every lane
//   07 d      one RMOVE pulse on every lane, RDIR = d[0]
//   08 b      reads on (b[0] = 1) or off
//   0A        RLOADN pulse: every lane's read delay back to its default
//   0B p      READ = p[3:0] while reads are on
//
// Status bytes:
//    0  {ready, pll_lock, dll_lock, lock_seen, cke, reset_n, reads_on, 0}
//    1  DDRDLL STEP
//    2  {1'b0, RCLKSEL[2:0], init state[3:0]}
//    3  net RMOVE steps, signed (RDIR 1 counts up)
//    4  50 MHz counter, low       5  high
//    6  PCLK counter, low         7  high
//    8+12n   lane n {4'b0, RVALID, RBURST, RFLAG, WFLAG}
//    9+12n   lane n {2'b0, RPOINT[2:0], WPOINT[2:0]}
//   10+12n   lane n pattern cycles in the last window, low
//   11+12n                                             high
//   12+12n.. lane n snapshot, DQ 8n .. 8n+7, one byte each
module mpr_core (
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
    output reg          rmove = 1'b0,
    output reg          rdir = 1'b0,
    output reg  [3:0]   read_en = 4'b0000,
    input  wire [3:0]   rvalid,
    input  wire [3:0]   rburst,
    input  wire [3:0]   rflag,
    input  wire [3:0]   wflag,
    input  wire [11:0]  rpoint,
    input  wire [11:0]  wpoint,
    input  wire [255:0] dq_q,

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
    reg reads_on = 1'b0;
    reg [3:0] read_pat = 4'b1111;
    reg [2:0] rclksel_req = 3'd0;
    reg rdir_req = 1'b0;
    reg rmove_tog = 1'b0, rload_tog = 1'b0, snap_tog = 1'b0;

    reg [1:0] ready_p = 2'b00, reads_p = 2'b00;
    reg [2:0] rmove_p = 3'b000, rload_p = 3'b000, snap_p = 3'b000;
    reg [3:0] pat_p1 = 4'b1111, pat_p2 = 4'b1111;
    reg [2:0] sel_p1 = 3'd0;
    reg rdir_p1 = 1'b0;
    always @(posedge pclk) begin
        ready_p <= {ready_p[0], ready};
        reads_p <= {reads_p[0], reads_on};
        rmove_p <= {rmove_p[1:0], rmove_tog};
        rload_p <= {rload_p[1:0], rload_tog};
        snap_p <= {snap_p[1:0], snap_tog};
        pat_p1 <= read_pat;
        pat_p2 <= pat_p1;
        sel_p1 <= rclksel_req;
        rclksel <= sel_p1;
        rdir_p1 <= rdir_req;
        rdir <= rdir_p1;
    end
    wire ready_pc = ready_p[1];
    wire rmove_pulse = rmove_p[2] ^ rmove_p[1];
    wire rload_pulse = rload_p[2] ^ rload_p[1];
    wire snap_pulse = snap_p[2] ^ snap_p[1];

    // ------------------------------------------------------------------
    // DDR3 initialization and reads, PCLK
    // ------------------------------------------------------------------
    localparam [3:0] I_IDLE = 4'd0, I_RESET = 4'd1, I_CKE = 4'd2, I_XPR = 4'd3,
                     I_MR = 4'd4, I_ZQ = 4'd5, I_MPR = 4'd6, I_READ = 4'd7;
    reg [3:0] istate = I_IDLE;
    reg [16:0] itimer = 17'd0;
    reg [1:0] mr_idx = 2'd0;
    reg [3:0] rload_cnt = 4'd0;

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

    always @(posedge pclk) begin
        deselect;
        itimer <= itimer + 17'd1;
        rmove <= rmove_pulse;
        read_en <= 4'b0000;

        // read delay back to its default once the PHY is up, and on request
        if (rload_pulse || (istate == I_IDLE && ready_pc && itimer == 17'd4))
            rload_cnt <= 4'd8;
        else if (rload_cnt != 4'd0)
            rload_cnt <= rload_cnt - 4'd1;
        rloadn <= (rload_cnt == 4'd0);

        if (!ready_pc) begin
            istate <= I_IDLE;
            itimer <= 17'd0;
            ddr_reset_n <= 1'b0;
            cke <= 1'b0;
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
                    istate <= I_XPR;
                    itimer <= 17'd0;
                end
                I_XPR: if (itimer == 17'd32) begin             // 320 ns
                    istate <= I_MR;
                    itimer <= 17'd0;
                    mr_idx <= 2'd0;
                end
                I_MR: begin
                    if (itimer == 17'd0) begin
                        {ba, addr} <= mr_word(mr_idx);
                        cs_n <= 1'b0; ras_n <= 1'b0; cas_n <= 1'b0; we_n <= 1'b0;
                    end
                    if (itimer == 17'd8) begin
                        itimer <= 17'd0;
                        mr_idx <= mr_idx + 2'd1;
                        if (mr_idx == 2'd3)
                            istate <= I_ZQ;
                    end
                end
                I_ZQ: begin
                    if (itimer == 17'd0) begin
                        ba <= 3'd0;
                        addr <= 16'h0400;                       // A10: ZQCL
                        cs_n <= 1'b0; ras_n <= 1'b1; cas_n <= 1'b1; we_n <= 1'b0;
                    end
                    if (itimer == 17'd256) begin
                        istate <= I_MPR;
                        itimer <= 17'd0;
                    end
                end
                I_MPR: begin
                    if (itimer == 17'd0) begin
                        ba <= 3'd3;
                        addr <= 16'h0004;                       // MPR on
                        cs_n <= 1'b0; ras_n <= 1'b0; cas_n <= 1'b0; we_n <= 1'b0;
                    end
                    if (itimer == 17'd16) begin
                        istate <= I_READ;
                        itimer <= 17'd0;
                    end
                end
                default: begin
                    if (reads_p[1]) begin
                        ba <= 3'd0;
                        addr <= 16'h0000;                       // BL8, no auto-precharge
                        cs_n <= 1'b0; ras_n <= 1'b1; cas_n <= 1'b0; we_n <= 1'b1;
                        read_en <= pat_p2;
                    end
                end
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Capture, PCLK
    // ------------------------------------------------------------------
    reg [15:0] pclk_cnt = 16'd0;
    reg [63:0] good = 64'd0;        // lane n at [16n +: 16]
    reg [63:0] good_last = 64'd0;
    reg [255:0] snap = 256'd0;
    reg [255:0] dq_r = 256'd0;
    integer l, k;
    reg ok;

    always @(posedge pclk) begin
        pclk_cnt <= pclk_cnt + 16'd1;
        dq_r <= dq_q;
        if (snap_pulse)
            snap <= dq_r;
        for (l = 0; l < 4; l = l + 1) begin
            ok = (dq_r[64 * l +: 8] == 8'h55) || (dq_r[64 * l +: 8] == 8'haa);
            for (k = 1; k < 8; k = k + 1)
                ok = ok && (dq_r[64 * l + 8 * k +: 8] == dq_r[64 * l +: 8]);
            // the window is the 65535 cycles before the wrap, so a lane
            // that matches on every cycle reads 65535, not 0
            if (pclk_cnt == 16'hffff) begin
                good_last[16 * l +: 16] <= good[16 * l +: 16];
                good[16 * l +: 16] <= 16'd0;
            end else begin
                good[16 * l +: 16] <= good[16 * l +: 16] + {15'd0, ok};
            end
        end
    end

    // ------------------------------------------------------------------
    // Into the 50 MHz domain; values read as levels or "is it moving"
    // ------------------------------------------------------------------
    reg [7:0] step_s1 = 8'h00, step_s2 = 8'h00;
    reg [15:0] pclk_s1 = 16'd0, pclk_s2 = 16'd0;
    reg [39:0] lane_s1 = 40'd0, lane_s2 = 40'd0;
    reg [63:0] good_s1 = 64'd0, good_s2 = 64'd0;
    reg [255:0] snap_s1 = 256'd0, snap_s2 = 256'd0;
    reg [5:0] st_s1 = 6'd0, st_s2 = 6'd0;
    wire [39:0] lane_now = {rvalid, rburst, rflag, wflag, rpoint, wpoint};
    always @(posedge sys_clk) begin
        step_s1 <= step;                step_s2 <= step_s1;
        pclk_s1 <= pclk_cnt;            pclk_s2 <= pclk_s1;
        lane_s1 <= lane_now;            lane_s2 <= lane_s1;
        good_s1 <= good_last;
        good_s2 <= good_s1;
        snap_s1 <= snap;                snap_s2 <= snap_s1;
        st_s1 <= {cke, ddr_reset_n, istate};
        st_s2 <= st_s1;
    end

    reg [15:0] free_cnt = 16'd0;
    reg signed [7:0] moves = 8'sd0;
    always @(posedge sys_clk)
        free_cnt <= free_cnt + 16'd1;

    function [95:0] lane_bytes;
        input [39:0] v;
        input [63:0] g;
        input [255:0] s;
        input integer n;
        begin
            lane_bytes = {s[64 * n +: 64], g[16 * n +: 16],
                          2'b00, v[12 + 3 * n +: 3], v[3 * n +: 3],
                          4'b0000, v[36 + n], v[32 + n], v[28 + n], v[24 + n]};
        end
    endfunction

    wire [447:0] status = {
        lane_bytes(lane_s2, good_s2, snap_s2, 3), lane_bytes(lane_s2, good_s2, snap_s2, 2),
        lane_bytes(lane_s2, good_s2, snap_s2, 1), lane_bytes(lane_s2, good_s2, snap_s2, 0),
        pclk_s2, free_cnt, moves,
        1'b0, rclksel_req, st_s2[3:0],
        step_s2,
        ready, pll_ok, lock_ok, lock_seen, st_s2[5], st_s2[4], reads_on, 1'b0
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
    reg [5:0] response_index = 6'd0;
    reg [447:0] frame = 448'd0;

    function known;
        input [7:0] c;
        begin
            known = (c == 8'h01) || (c == 8'h03) || (c == 8'h04) || (c == 8'h05) ||
                    (c == 8'h06) || (c == 8'h07) || (c == 8'h08) || (c == 8'h0a) ||
                    (c == 8'h0b);
        end
    endfunction

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
                        response_index <= 6'd0;
                        frame <= status;
                        case (cmd_byte)
                            8'h04: snap_tog <= ~snap_tog;
                            8'h05: begin
                                restart <= 1'b1;
                                reads_on <= 1'b0;
                                moves <= 8'sd0;
                            end
                            8'h06: rclksel_req <= rx_data[2:0];
                            8'h07: begin
                                rdir_req <= rx_data[0];
                                rmove_tog <= ~rmove_tog;
                                moves <= rx_data[0] ? moves + 8'sd1 : moves - 8'sd1;
                            end
                            8'h08: reads_on <= rx_data[0];
                            8'h0a: begin
                                rload_tog <= ~rload_tog;
                                moves <= 8'sd0;
                            end
                            8'h0b: read_pat <= rx_data[3:0];
                            default: ;
                        endcase
                    end
                end
            endcase
        end

        if (response_active && tx_ready && !tx_send) begin
            if (response_is_status) begin
                case (response_index)
                    6'd0: tx_data <= 8'haa;
                    6'd1: tx_data <= 8'h00;
                    6'd2: tx_data <= 8'h04;
                    6'd3: tx_data <= 8'h38;
                    default: begin
                        tx_data <= frame[7:0];
                        frame <= frame >> 8;
                    end
                endcase
            end else begin
                case (response_index)
                    6'd0: tx_data <= 8'haa;
                    6'd1: tx_data <= 8'h00;
                    6'd2: tx_data <= 8'h02;
                    6'd3: tx_data <= 8'h01;
                    default: tx_data <= 8'h56; // "V" for TinyVCMI.
                endcase
            end
            tx_send <= 1'b1;
            if (response_index == (response_is_status ? 6'd59 : 6'd4))
                response_active <= 1'b0;
            else
                response_index <= response_index + 6'd1;
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
