// SPDX-License-Identifier: GPL-3.0-only
// The TinyVCMI AE350 system, from TinyNES f0f8501 fpga/ae350_soc/ae350_soc.sv
// with the SDRAM replaced by the DDR3, TinyNES's video replaced by this
// project's registers for its own (exts_video; the video unit itself is at
// the top level, video_ddr3.v), and the audio, pads and link left out.  The
// A25 boots C firmware from a block-RAM ROM on the ROM port (ahb_boot_rom),
// keeps the boot ROM's data and stack in 64 KiB of block RAM at 0x7fff0000
// on the RAM port (ahb_ram), reaches the DDR3 at 0x40000000 to 0x7ffeffff on
// the same port through ahb_ddr3's bus half, and sends and receives on the
// FPGA UART at 2,000,000 baud 8N1 through registers in the EXTS window
// (exts_uart).  The CPU and bus clocks, from PLL_R[0], come from the top
// level, which must place that PLL.
//
// run holds the whole system in reset until the DDR3 is the CPU's: the top
// level raises it once the controller is trained and handed over, and it
// never falls again.  The reset counter clears asynchronously while run or
// the PLL's lock is low and releases the system 256 bus clocks after both
// are high, so run may come from any clock.  Every fabric register below it
// takes resetn synchronously: nextpnr times an asynchronous clear as a path
// through the register's clear-to-Q arc, which put the reset flop at the
// head of every bus_clk path through ahb_ram and the bridge (core-log entry
// 16), while a synchronous reset is a timed setup on DFFRE's reset pin, and
// resetn, released from a bus_clk flop, holds for 256 bus clocks.
//
// If the CPU has written nothing to the UART 2^NOBOOT_BITS bus clocks after
// reset (about 1.8 s), fabric reports instead, about once a second until the
// CPU writes, how many transfers each port has accepted, the addresses of the
// last ROM and RAM transfers, the RAM port state (see ST below) and the
// addresses of the first and last RAM transfers outside the RAM window:
//   NOBOOT ROM=<count> LAST=<address> RAM=<count> EXT=<count>
//          RAML=<address> ST=<state> S1=<address> SL=<address>   (one line)
//
// A diagnostic for a stopped CPU: if no port accepts a transfer for
// 2^STALL_BITS bus clocks (about 1.8 s), the same report is forced out even
// after the CPU owns the UART, headed STALL instead of NOBOOT and with ST,
// S1 and SL replaced: ST holds ddr3_perf's snapshot word 11, ddr3_arb's
// state and the bridge's reads in flight on PCLK as of its last copy (about
// every 10 us), S1 the DDR3 path's live bus-clock state (see stall_state
// below) and SL the address of the last EXTS transfer. It repeats about once
// a second while nothing moves.
module ae350_sys #(
    parameter INIT_FILE = "build/firmware/boot/boot.hex",
    parameter integer UART_DIV2 = 75, // 2 * 75 MHz / 2,000,000 baud
    parameter integer NOBOOT_BITS = 27,
    parameter integer STALL_BITS = 27
) (
    input  wire          bus_clk,
    input  wire          core_clk,
    input  wire          pll_locked,
    input  wire          run,
    output wire          uart_tx,
    input  wire          uart_rx,

    // the DDR3 bridge's crossing to its PCLK half (ahb_ddr3_pclk), which
    // the top level places beside ddr3_ctl: registers on each side's clock,
    // the queue RAM's write port (q_we, q_waddr, q_wdata) on the bus clock,
    // and the line slots' LUT RAM read asynchronously at r_way (r_slot)
    output wire          q_we,
    output wire [3:0]    q_waddr,
    output wire [99:0]   q_wdata,
    output wire [4:0]    q_wgray,
    input  wire [4:0]    q_rgray,
    input  wire [3:0]    r_tog,
    output wire [1:0]    r_way,
    input  wire [255:0]  r_slot,

    // the video unit's registers (exts_video), to and from its pixel side
    output wire          vid_enable,
    output wire [24:0]   vid_base,
    output wire          vid_base_tog,
    input  wire          vid_base_ack,
    input  wire          vid_vbl_tog,
    input  wire          vid_in_vbl,
    input  wire [15:0]   vid_late,

    // ddr3_perf's PCLK snapshot, for exts_perf
    input  wire [383:0]  perf_snap,
    input  wire          perf_snap_tog
);
    wire arst_n = pll_locked && run;
    reg [7:0] reset_count = 8'd0;
    reg resetn = 1'b0;
    always @(posedge bus_clk or negedge arst_n) begin
        if (!arst_n) begin
            reset_count <= 8'd0;
            resetn <= 1'b0;
        end else if (!resetn) begin
            reset_count <= reset_count + 1'b1;
            if (&reset_count)
                resetn <= 1'b1;
        end
    end

    wire [31:0] rom_addr;
    wire [1:0] rom_trans;
    wire [31:0] rom_rdata;
    wire rom_ready;

    wire [31:0] ram_addr;
    wire [1:0] ram_trans;
    wire ram_write;
    wire [2:0] ram_size;
    wire [63:0] ram_wdata;
    wire [63:0] ram_rdata;
    wire ram_ready;
    wire ram_resp;
    wire ram_stray;
    wire [2:0] ram_burst;
    wire [3:0] ram_prot;

    wire [1:0] ddr_dbg;
    wire [1:0] pf_depth;
    wire p_miss, p_wait, p_pf, p_pfhit;
    wire [31:0] perf_tap;
    wire [1:0] sd_ldw;
    wire sd_lhit;
    wire [63:0] sd_ldata;
    wire sd_req;
    wire sd_post;
    wire sd_post_ok;
    wire [29:3] sd_addr;
    wire [7:0] sd_lanes;
    wire [63:0] sd_wdata;
    wire sd_ack;
    wire [63:0] sd_rdata;

    wire [31:0] exts_addr;
    wire [31:0] exts_wdata;
    wire exts_sel;
    wire [1:0] exts_trans;
    wire exts_write;
    wire [31:0] exts_rdata;
    wire [2:0] exts_size;
    wire exts_ready;
    wire exts_resp;

    ahb_boot_rom #(.INIT_FILE(INIT_FILE)) boot_rom (
        .clk(bus_clk),
        .resetn(resetn),
        .haddr(rom_addr),
        .htrans(rom_trans),
        .hrdata(rom_rdata),
        .hready(rom_ready)
    );

    ahb_ram ram (
        .clk(bus_clk),
        .resetn(resetn),
        .haddr(ram_addr),
        .htrans(ram_trans),
        .hwrite(ram_write),
        .hsize(ram_size),
        .hburst(ram_burst),
        .hprot0(ram_prot[0]),
        .hwdata(ram_wdata),
        .hrdata(ram_rdata),
        .hready(ram_ready),
        .hresp(ram_resp),
        .stray(ram_stray),
        .sd_ldw(sd_ldw),
        .sd_lhit(sd_lhit),
        .sd_ldata(sd_ldata),
        .sd_req(sd_req),
        .sd_post(sd_post),
        .sd_post_ok(sd_post_ok),
        .sd_addr(sd_addr),
        .sd_lanes(sd_lanes),
        .sd_wdata(sd_wdata),
        .sd_ack(sd_ack),
        .sd_rdata(sd_rdata)
    );

    ahb_ddr3_bus #(.AW(25)) ddr (
        .clk(bus_clk), .resetn(resetn),
        .l_dw(sd_ldw), .l_hit(sd_lhit), .l_data(sd_ldata),
        .req(sd_req), .post(sd_post), .post_ok(sd_post_ok), .addr(sd_addr), .lanes(sd_lanes),
        .wdata(sd_wdata), .ack(sd_ack), .rdata(sd_rdata),
        .q_we(q_we), .q_waddr(q_waddr), .q_wdata(q_wdata), .q_wgray(q_wgray),
        .q_rgray(q_rgray), .r_tog(r_tog), .r_way(r_way), .r_slot(r_slot), .pf_depth(pf_depth), .dbg(ddr_dbg),
        .p_miss(p_miss), .p_wait(p_wait), .p_pf(p_pf), .p_pfhit(p_pfhit)
    );

    // The EXTS window holds the UART's registers at 0xe8000000, the video
    // unit's at 0xe8010000 (exts_video) and the read-latency counters and
    // the bridge's prefetch depth at 0xe8020000 (exts_perf); TinyNES's link, pads and
    // audio are not here, so the link's inputs are idle.  Each slave drives
    // its own hready and hresp, which are combined, and the read data is
    // that of the slave the last transfer went to, as TinyNES chooses it.
    wire perf_hit = exts_addr[17];
    wire video_hit = exts_addr[16] && !perf_hit;
    wire uart_hit = !exts_addr[16] && !perf_hit;
    wire [31:0] uart_rdata, video_rdata, perf_rdata;
    wire uart_ready, uart_resp, video_ready, video_resp, perf_ready, perf_resp;
    reg  data_video = 1'b0, data_perf = 1'b0;
    always @(posedge bus_clk)
        if (!resetn) begin
            data_video <= 1'b0;
            data_perf <= 1'b0;
        end else if (exts_ready && exts_sel && exts_trans[1]) begin
            data_video <= video_hit;
            data_perf <= perf_hit;
        end
    assign exts_rdata = data_perf ? perf_rdata : data_video ? video_rdata : uart_rdata;
    assign exts_ready = uart_ready & video_ready & perf_ready;
    assign exts_resp = uart_resp | video_resp | perf_resp;

    exts_perf perf_regs (
        .clk(bus_clk),
        .resetn(resetn),
        .haddr(exts_addr),
        .htrans(exts_trans),
        .hsel(exts_sel && perf_hit),
        .hwrite(exts_write),
        .hwdata(exts_wdata),
        .hready_in(exts_ready),
        .hrdata(perf_rdata),
        .hready(perf_ready),
        .hresp(perf_resp),
        .sd_req(sd_req),
        .p_miss(p_miss),
        .p_wait(p_wait),
        .p_pf(p_pf),
        .p_pfhit(p_pfhit),
        .ram_ready(ram_ready),
        .ram_trans(ram_trans),
        .snap(perf_snap),
        .snap_tog(perf_snap_tog),
        .pf_depth(pf_depth),
        .tap(perf_tap)
    );

    exts_video video_regs (
        .clk(bus_clk),
        .resetn(resetn),
        .haddr(exts_addr),
        .htrans(exts_trans),
        .hsel(exts_sel && video_hit),
        .hwrite(exts_write),
        .hwdata(exts_wdata),
        .hready_in(exts_ready),
        .hrdata(video_rdata),
        .hready(video_ready),
        .hresp(video_resp),
        .enable(vid_enable),
        .base_line(vid_base),
        .base_tog(vid_base_tog),
        .base_ack(vid_base_ack),
        .vbl_tog(vid_vbl_tog),
        .in_vbl(vid_in_vbl),
        .late(vid_late)
    );

    wire fb_valid;
    wire [7:0] fb_data;
    wire fb_ready;
    wire fb_force;
    wire cpu_owns;
    exts_uart #(.UART_DIV2(UART_DIV2), .ID_VALUE(32'h54563031)) regs (   // "TV01"
        .clk(bus_clk),
        .resetn(resetn),
        .haddr(exts_addr),
        .htrans(exts_trans),
        .hsel(exts_sel && uart_hit),
        .hready_in(exts_ready),
        .hwrite(exts_write),
        .hwdata(exts_wdata),
        .hrdata(uart_rdata),
        .hready(uart_ready),
        .hresp(uart_resp),
        .fb_valid(fb_valid),
        .fb_data(fb_data),
        .fb_ready(fb_ready),
        .fb_force(fb_force),
        .cpu_owns(cpu_owns),
        .link(),
        .rx_link_valid(),
        .rx_link_data(),
        .txt_valid(),
        .txt_data(),
        .txt_ready(1'b1),
        .ln_valid(1'b0),
        .ln_data(8'd0),
        .ln_ready(),
        .link_idle(1'b1),
        .link_flush(),
        .link_status(32'd0),
        .link_pads(32'd0),
        .tx(uart_tx),
        .rx(uart_rx)
    );

    AE350_SOC cpu (
        .POR_N(1'b1),
        .HW_RSTN(resetn),
        .CORE_CLK(core_clk),
        .DDR_CLK(bus_clk),
        .AHB_CLK(bus_clk),
        .APB_CLK(bus_clk),
        .DBG_TCK(1'b1),
        .RTC_CLK(bus_clk),
        .CORE_CE(1'b1),
        .AXI_CE(1'b1),
        .DDR_CE(1'b1),
        .AHB_CE(1'b1),
        .APB_CE(8'b00000001),
        .APB2AHB_CE(1'b1),
        .GP_INT(16'b0),
        .DMA_REQ(8'b0),
        .WAKEUP_IN(1'b0),
        .SCAN_TEST(1'b0),
        .SCAN_EN(1'b0),
        .SCAN_IN(20'hfffff),
        .TEST_CLK(1'b0),
        .TEST_MODE(1'b0),
        .TEST_RSTN(1'b1),
        .INTEG_TCK(1'b1),
        .INTEG_TDI(1'b1),
        .INTEG_TMS(1'b1),
        .INTEG_TRST(1'b0),
        .PGEN_CHAIN_I(1'b1),
        .EMA(3'b011),
        .EMAW(2'b01),
        .EMAS(1'b0),
        .RET1N(1'b1),
        .RET2N(1'b1),
        .ROM_HADDR(rom_addr),
        .ROM_HTRANS(rom_trans),
        .ROM_HRDATA(rom_rdata),
        .ROM_HREADY(rom_ready),
        .ROM_HRESP(1'b0),
        .APB_PRDATA(32'b0),
        .APB_PREADY(1'b1),
        .APB_PSLVERR(1'b0),
        .EXTS_HADDR(exts_addr),
        .EXTS_HSEL(exts_sel),
        .EXTS_HTRANS(exts_trans),
        .EXTS_HWRITE(exts_write),
        .EXTS_HSIZE(exts_size),
        .EXTS_HWDATA(exts_wdata),
        .EXTS_HRDATA(exts_rdata),
        .EXTS_HREADYIN(exts_ready),
        .EXTS_HRESP(exts_resp),
        .EXTM_HADDR(32'b0),
        .EXTM_HBURST(3'b0),
        .EXTM_HPROT(4'b0),
        .EXTM_HREADY(1'b1),
        .EXTM_HSEL(1'b0),
        .EXTM_HSIZE(3'b0),
        .EXTM_HTRANS(2'b0),
        .EXTM_HWDATA(64'b0),
        .EXTM_HWRITE(1'b0),
        .DDR_HADDR(ram_addr),
        .DDR_HTRANS(ram_trans),
        .DDR_HWRITE(ram_write),
        .DDR_HSIZE(ram_size),
        .DDR_HBURST(ram_burst),
        .DDR_HPROT(ram_prot),
        .DDR_HWDATA(ram_wdata),
        .DDR_HRDATA(ram_rdata),
        .DDR_HREADY(ram_ready),
        .DDR_HRESP(ram_resp),
        .TMS_IN(1'b1),
        // Keep the AE350 JTAG test-reset deasserted, as in the working
        // Tang-Phosphor smoke design.
        .TRST_IN(1'b1),
        .TDI_IN(1'b1),
        .SPI2_HOLDN_IN(1'b1),
        .SPI2_WPN_IN(1'b1),
        .SPI2_CLK_IN(1'b1),
        .SPI2_CSN_IN(1'b1),
        .SPI2_MISO_IN(1'b1),
        .SPI2_MOSI_IN(1'b1),
        .I2C_SCL_IN(1'b1),
        .I2C_SDA_IN(1'b1),
        .UART1_RXD(1'b1),
        .UART1_CTSN(1'b1),
        .UART1_DSRN(1'b1),
        .UART1_DCDN(1'b1),
        .UART1_RIN(1'b1),
        .UART2_RXD(1'b1),
        .UART2_CTSN(1'b1),
        .UART2_DSRN(1'b1),
        .UART2_DCDN(1'b1),
        .UART2_RIN(1'b1),
        .GPIO_IN(32'b0)
    );

    // Transfers accepted on each port, for the NOBOOT report.
    reg [31:0] rom_count = 32'd0;
    reg [31:0] rom_last = 32'd0;
    reg [31:0] ram_count = 32'd0;
    reg [31:0] ext_count = 32'd0;
    reg [31:0] ram_last = 32'd0;
    reg [7:0] ram_info = 8'd0;
    reg [7:0] stray_info = 8'd0;
    reg [31:0] stray_first = 32'd0;
    reg [31:0] stray_last = 32'd0;
    reg [15:0] stray_count = 16'd0;
    reg [31:0] ext_last = 32'd0;
    reg [STALL_BITS:0] stall_count = 0;
    wire stalled = stall_count[STALL_BITS];
    wire moved = (rom_ready && rom_trans[1]) || (ram_ready && ram_trans[1])
                 || (exts_ready && exts_sel && exts_trans[1]);
    always @(posedge bus_clk) begin
        if (!resetn) begin
            rom_count <= 32'd0;
            rom_last <= 32'd0;
            ram_count <= 32'd0;
            ext_count <= 32'd0;
            ram_last <= 32'd0;
            ram_info <= 8'd0;
            stray_info <= 8'd0;
            stray_first <= 32'd0;
            stray_last <= 32'd0;
            stray_count <= 16'd0;
            ext_last <= 32'd0;
            stall_count <= 0;
        end else begin
            if (moved)
                stall_count <= 0;
            else if (!stalled)
                stall_count <= stall_count + 1'b1;
            if (exts_ready && exts_sel && exts_trans[1])
                ext_last <= exts_addr;
            if (rom_ready && rom_trans[1]) begin
                rom_count <= rom_count + 1'b1;
                rom_last <= rom_addr;
            end
            if (ram_ready && ram_trans[1]) begin
                ram_count <= ram_count + 1'b1;
                ram_last <= ram_addr;
                ram_info <= {ram_prot[0], ram_burst, ram_write, ram_size};
            end
            // ram_last still holds the transfer that stray completes.
            if (ram_stray) begin
                stray_count <= stray_count + 1'b1;
                stray_info <= ram_info;
                stray_last <= ram_last;
                if (stray_count == 16'd0)
                    stray_first <= ram_last;
            end
            if (exts_ready && exts_sel && exts_trans[1])
                ext_count <= ext_count + 1'b1;
        end
    end

    // ST in a NOBOOT report: the last stray transfer's {HPROT[0], HBURST}
    // (HPROT[0] is 0 for an instruction fetch) and {HWRITE, HSIZE}, then the
    // live {ROM HREADY, RAM HREADY, RAM HRESP, EXTS HREADY} and {RAM HTRANS,
    // ROM HTRANS}, then the number of stray transfers (16 bits).  In a STALL
    // report, exts_perf's tap: {ddr3_arb's c_err, v_err, x_vid, v_slot,
    // x_valid, x_ready, CPU and video reads in flight (6 bits each), tag
    // write and read pointers (5 bits each), the bridge's PCLK reads in
    // flight (3 bits), a zero}.
    wire [31:0] noboot_state = {stray_info,
                                rom_ready, ram_ready, ram_resp, exts_ready,
                                ram_trans, rom_trans, stray_count};

    // S1 in a STALL report: {RAM sd_req, sd_post, sd_post_ok, sd_ack, the
    // bridge's busy (not idle) and any way pending, video base_tog,
    // base_ack, in_vbl, enable, EXTS HSEL, HTRANS, HWRITE, the queue's write
    // and read Gray pointers (5 bits each), RAM HWRITE, RAM HSIZE, the
    // read-back's four way toggles}.
    wire [31:0] stall_state = {sd_req, sd_post, sd_post_ok, sd_ack, ddr_dbg,
                               vid_base_tog, vid_base_ack, vid_in_vbl,
                               vid_enable, exts_sel, exts_trans, exts_write,
                               q_wgray, q_rgray, ram_write, ram_size, r_tog};

    // Hex fields at characters 11, 25, 38, 51, 65, 77, 89 and 101; CR at 109
    // and LF at 110.
    localparam [8*109-1:0] NOBOOT_TEXT =
        {"NOBOOT ROM=........ LAST=........ RAM=........ EXT=........ ",
         "RAML=........ ST=........ S1=........ SL=........"};
    localparam [8*6-1:0] STALL_TEXT = "STALL:";
    reg [NOBOOT_BITS-1:0] noboot_wait = 0;
    reg noboot_armed = 1'b0;
    reg [6:0] noboot_index = 7'd0;
    reg [31:0] line_rom = 32'd0;
    reg [31:0] line_last = 32'd0;
    reg [31:0] line_ram = 32'd0;
    reg [31:0] line_ext = 32'd0;
    reg [31:0] line_raml = 32'd0;
    reg [31:0] line_state = 32'd0;
    reg [31:0] line_e1 = 32'd0;
    reg [31:0] line_el = 32'd0;
    reg line_stall = 1'b0;

    function [7:0] hex_char(input [3:0] value);
        hex_char = (value < 4'd10) ? ("0" + value) : ("a" + value - 4'd10);
    endfunction

    function [7:0] hex_field(input [6:0] index, input [6:0] first,
                             input [31:0] value);
        hex_field = hex_char(value >> (4 * (first + 7'd7 - index)));
    endfunction

    function [7:0] noboot_char(input [6:0] index, input stall);
        if (index >= 7'd11 && index <= 7'd18)
            noboot_char = hex_field(index, 7'd11, line_rom);
        else if (index >= 7'd25 && index <= 7'd32)
            noboot_char = hex_field(index, 7'd25, line_last);
        else if (index >= 7'd38 && index <= 7'd45)
            noboot_char = hex_field(index, 7'd38, line_ram);
        else if (index >= 7'd51 && index <= 7'd58)
            noboot_char = hex_field(index, 7'd51, line_ext);
        else if (index >= 7'd65 && index <= 7'd72)
            noboot_char = hex_field(index, 7'd65, line_raml);
        else if (index >= 7'd77 && index <= 7'd84)
            noboot_char = hex_field(index, 7'd77, line_state);
        else if (index >= 7'd89 && index <= 7'd96)
            noboot_char = hex_field(index, 7'd89, line_e1);
        else if (index >= 7'd101 && index <= 7'd108)
            noboot_char = hex_field(index, 7'd101, line_el);
        else if (index == 7'd109)
            noboot_char = 8'h0d;
        else if (index == 7'd110)
            noboot_char = 8'h0a;
        else if (stall && index <= 7'd5)
            noboot_char = STALL_TEXT[8 * (7'd5 - index) +: 8];
        else
            noboot_char = NOBOOT_TEXT[8 * (7'd108 - index) +: 8];
    endfunction

    // A line once begun is finished; a STALL line begins only while stalled.
    assign fb_force = stalled || noboot_index != 7'd0;
    assign fb_valid = noboot_armed && noboot_wait == 0 && (!cpu_owns || fb_force);
    assign fb_data = noboot_char(noboot_index, noboot_index == 7'd0 ? cpu_owns : line_stall);

    always @(posedge bus_clk) begin
        if (!resetn) begin
            noboot_wait <= 0;
            noboot_armed <= 1'b0;
            noboot_index <= 7'd0;
            line_rom <= 32'd0;
            line_last <= 32'd0;
            line_ram <= 32'd0;
            line_ext <= 32'd0;
            line_raml <= 32'd0;
            line_state <= 32'd0;
            line_e1 <= 32'd0;
            line_el <= 32'd0;
            line_stall <= 1'b0;
        end else if (!noboot_armed) begin
            noboot_wait <= noboot_wait - 1'b1;
            if (noboot_wait == 1)
                noboot_armed <= 1'b1;
        end else if (noboot_wait != 0) begin
            noboot_wait <= noboot_wait - 1'b1;
        end else if (fb_valid && fb_ready) begin
            if (noboot_index == 7'd0) begin
                line_rom <= rom_count;
                line_last <= rom_last;
                line_ram <= ram_count;
                line_ext <= ext_count;
                line_raml <= ram_last;
                line_state <= cpu_owns ? perf_tap : noboot_state;
                line_e1 <= cpu_owns ? stall_state : stray_first;
                line_el <= cpu_owns ? ext_last : stray_last;
                line_stall <= cpu_owns;
            end
            if (noboot_index == 7'd110) begin
                noboot_index <= 7'd0;
                noboot_wait <= {1'b0, {(NOBOOT_BITS - 1){1'b1}}};
            end else begin
                noboot_index <= noboot_index + 1'b1;
            end
        end
    end
endmodule
