// SPDX-License-Identifier: GPL-3.0-only
// From TinyNES f0f8501 fpga/ae350_soc/ahb_ram.sv, with the SDRAM window made
// the 1 GiB DDR3 window and the block RAM moved inside it.
//
// The AE350's 64-bit RAM AHB port (DDR_H*): block RAM at BASE for BYTES
// bytes, and the DDR3 at SDRAM_BASE for SDRAM_BYTES bytes, less the block
// RAM where they overlap, through the ahb_ddr3 back end (sd_* below). The
// RAM port is proven only from 0x40000000 to 0x7fffffff (TinyNES DEV-011),
// so the block RAM sits at the top of the DDR3 window, which it hides, rather
// than below it. A data transfer to any other address
// gets an AHB ERROR response, and an erroneous write changes nothing. An
// instruction fetch (HPROT[0] 0) to any other address reads zero with an
// OKAY response instead: the A25 fetches down mispredicted paths, address
// 0 included, and with both of its caches on it stops for good after such
// a line fill gets ERROR (core-log entry 7). Zero is an illegal
// instruction, so a fetch that is really executed still traps. stray
// pulses as each transfer outside both windows completes. Byte, halfword,
// word and doubleword writes update only their own byte lanes. Burst type
// is not needed: every beat is a complete transfer here.
//
// As in ahb_boot_rom, the transfer is registered when accepted and the
// macro's inputs come from flip-flops. A block RAM write is done in the
// cycle after it is accepted, when its data is on the bus (one wait state);
// a read takes two wait states, the second registering the block RAM
// output. A DDR3 write is posted to ahb_ddr3's queue (sd_post) in its data
// phase with no wait state while sd_post_ok promises room, and otherwise
// waits in its data phase until it does. A DDR3 read is requested (sd_req)
// from the cycle after it is accepted and completes in the cycle after
// sd_ack. sd_addr and sd_lanes hold the transfer in the cycle after it is
// accepted, and sd_wdata is the bus's write data.
module ahb_ram #(
    parameter integer BYTES = 65536,
    parameter [31:0] BASE = 32'h7fff0000,
    parameter integer SDRAM_SPAN_BITS = 30,     // 1 GiB
    parameter [31:0] SDRAM_BASE = 32'h40000000
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [31:0] haddr,
    input  wire [1:0]  htrans,
    input  wire        hwrite,
    input  wire [2:0]  hsize,
    input  wire        hprot0,
    input  wire [63:0] hwdata,
    output reg  [63:0] hrdata,
    output reg         hready,
    output reg         hresp,
    output reg         stray,

    output reg         sd_req,
    output reg         sd_post,
    input  wire        sd_post_ok,
    output reg  [SDRAM_SPAN_BITS-1:3] sd_addr,
    output reg  [7:0]  sd_lanes,
    output wire [63:0] sd_wdata,
    input  wire        sd_ack,
    input  wire [63:0] sd_rdata
);
    localparam integer WORDS = BYTES / 8;
    localparam integer ADDR_BITS = $clog2(WORDS);
    localparam integer SPAN_BITS = ADDR_BITS + 3;

    function [7:0] lane_mask(input [2:0] addr, input [2:0] size);
        case (size)
            3'd0: lane_mask = 8'h01 << addr;
            3'd1: lane_mask = 8'h03 << {addr[2:1], 1'b0};
            3'd2: lane_mask = 8'h0f << {addr[2], 2'b00};
            default: lane_mask = 8'hff;
        endcase
    endfunction

    reg [ADDR_BITS-1:0] word = 0;
    reg write = 1'b0;
    reg hit = 1'b0;
    reg fetch = 1'b0;
    reg [7:0] lanes = 8'd0;
    // stage[0]: the cycle after acceptance; stage[1]: a block RAM read's
    // second wait state; stage[2]: the first cycle of an ERROR response;
    // stage[3]: waiting for sd_ack; stage[4]: a DDR3 write waiting for room.
    reg [4:0] stage = 5'b00000;
    wire [63:0] q;
    wire sd_win = (haddr >> SDRAM_SPAN_BITS) == (SDRAM_BASE >> SDRAM_SPAN_BITS)
                  && (haddr >> SPAN_BITS) != (BASE >> SPAN_BITS);
    assign sd_wdata = hwdata;

    genvar lane;
    generate
        for (lane = 0; lane < 8; lane = lane + 1) begin : lane_ram
            reg [7:0] mem [0:WORDS-1];
            reg [7:0] lane_q;
            always @(posedge clk) begin
                if (stage[0] && hit && write && lanes[lane])
                    mem[word] <= hwdata[8 * lane +: 8];
                lane_q <= mem[word];
            end
            assign q[8 * lane +: 8] = lane_q;
        end
    endgenerate

    always @(posedge clk) begin
        if (!resetn) begin
            word <= 0;
            write <= 1'b0;
            hit <= 1'b0;
            fetch <= 1'b0;
            lanes <= 8'd0;
            stage <= 5'b00000;
            hrdata <= 64'd0;
            hready <= 1'b1;
            hresp <= 1'b0;
            stray <= 1'b0;
            sd_req <= 1'b0;
            sd_post <= 1'b0;
            sd_addr <= 0;
            sd_lanes <= 8'd0;
        end else begin
            stage <= 5'b00000;
            stray <= 1'b0;
            sd_post <= 1'b0;
            if (hready) begin
                hresp <= 1'b0;
                if (htrans[1]) begin
                    word <= haddr[SPAN_BITS-1:3];
                    write <= hwrite;
                    hit <= (haddr >> SPAN_BITS) == (BASE >> SPAN_BITS);
                    sd_addr <= haddr[SDRAM_SPAN_BITS-1:3];
                    sd_lanes <= lane_mask(haddr[2:0], hsize);
                    fetch <= !hprot0 && !hwrite;
                    lanes <= lane_mask(haddr[2:0], hsize);
                    if (sd_win && hwrite && sd_post_ok) begin
                        sd_post <= 1'b1;            // posted in its data phase
                    end else begin
                        hready <= 1'b0;
                        if (!sd_win)
                            stage <= 5'b00001;
                        else if (hwrite)
                            stage <= 5'b10000;
                        else begin
                            sd_req <= 1'b1;
                            stage <= 5'b01000;
                        end
                    end
                end
            end
            if (stage[0]) begin
                if (!hit && !fetch) begin
                    hresp <= 1'b1;
                    stage <= 5'b00100;
                end else if (write) begin
                    hready <= 1'b1;
                end else begin
                    stage <= 5'b00010;
                end
            end
            if (stage[4]) begin
                // the write data stays on the bus until hready rises with
                // the post
                if (sd_post_ok) begin
                    sd_post <= 1'b1;
                    hready <= 1'b1;
                end else begin
                    stage <= 5'b10000;
                end
            end
            if (stage[3]) begin
                if (sd_ack) begin
                    sd_req <= 1'b0;
                    hrdata <= sd_rdata;
                    hready <= 1'b1;
                end else begin
                    stage <= 5'b01000;
                end
            end
            if (stage[1]) begin
                hrdata <= hit ? q : 64'd0;
                hready <= 1'b1;
                stray <= !hit;
            end
            if (stage[2]) begin
                hready <= 1'b1;
                stray <= 1'b1;
            end
        end
    end
endmodule
