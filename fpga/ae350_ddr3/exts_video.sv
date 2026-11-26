// SPDX-License-Identifier: GPL-3.0-only
// The video unit's registers in the AE350's EXTS window, on the bus clock,
// at 0xe8010000 (ae350_sys selects this slave for 0xe8010000 to 0xe801ffff).
// Offsets:
//   0x00  CTRL, read and write: bit 0 shows the frame buffer; 0, the reset
//         value, shows black and fetches nothing.
//   0x04  STATUS, read: bit 0 the raster is in vertical blank, bit 1 a BASE
//         written is still waiting for the next vertical blank.
//   0x08  FRAMES, read: vertical blanks since reset.
//   0x0c  BASE, read and write: the frame buffer's byte address in the DDR3,
//         a multiple of 32 (the low five bits are ignored), taken at the
//         next vertical blank, so writing it between frames flips pages
//         without tearing.  Pixel (x, y) is the 32-bit word at BASE + 5120 y
//         + 4 x, 0x00RRGGBB.  Reset 0x7f000000.
//   0x10  LATE, read: lines shown since reset whose pixels were not all in
//         the line buffer when the line began, as of the last vertical blank.
//   0x14  ID, read: ID_VALUE.
// Any other offset gets an AHB ERROR response.  Each transfer takes one wait
// state, as exts_uart's do, so every output to the AE350 is a flip-flop.
//
// The pixel side (video_ddr3.v) runs on its own clock: BASE crosses by a
// toggle, base_tog, moved with the value, and comes back as
// base_ack; vbl_tog toggles at every vertical blank, and LATE is copied
// when that toggle arrives, the pixel side changing it only at the start of
// a visible line, never in the blank.
module exts_video #(
    parameter [31:0] ID_VALUE = 32'h54565631          // "TVV1"
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [31:0] haddr,
    input  wire [1:0]  htrans,
    input  wire        hsel,
    input  wire        hwrite,
    input  wire [31:0] hwdata,
    input  wire        hready_in,       // the EXTS port's HREADY
    output reg  [31:0] hrdata = 32'd0,
    output reg         hready = 1'b1,
    output reg         hresp = 1'b0,

    output reg         enable = 1'b0,
    output reg  [24:0] base_line = 25'h1f80000,    // BASE[29:5]: 0x7f000000
    output reg         base_tog = 1'b0,
    input  wire        base_ack,        // pix_clk
    input  wire        vbl_tog,         // pix_clk
    input  wire        in_vbl,          // pix_clk
    input  wire [15:0] late             // pix_clk, still during the blank
);
    localparam [2:0] R_CTRL = 3'd0, R_STATUS = 3'd1, R_FRAMES = 3'd2,
                     R_BASE = 3'd3, R_LATE = 3'd4, R_ID = 3'd5, R_NONE = 3'd7;

    reg [2:0]  target = R_NONE;
    reg        write = 1'b0;
    reg        pending = 1'b0;
    reg        error_second = 1'b0;
    reg [31:0] frames = 32'd0;
    reg [15:0] late_r = 16'd0;
    reg [2:0]  vbl_s = 3'd0;
    reg [1:0]  ack_s = 2'd0, blank_s = 2'd0;

    always @(posedge clk) begin
        vbl_s <= {vbl_s[1:0], vbl_tog};
        ack_s <= {ack_s[0], base_ack};
        blank_s <= {blank_s[0], in_vbl};
        if (vbl_s[2] ^ vbl_s[1]) begin
            frames <= frames + 1'b1;
            late_r <= late;
        end

        error_second <= 1'b0;
        if (hready) begin
            hresp <= 1'b0;
            if (hready_in && hsel && htrans[1]) begin
                case (haddr[15:0])
                    16'h0000: target <= R_CTRL;
                    16'h0004: target <= hwrite ? R_NONE : R_STATUS;
                    16'h0008: target <= hwrite ? R_NONE : R_FRAMES;
                    16'h000c: target <= R_BASE;
                    16'h0010: target <= hwrite ? R_NONE : R_LATE;
                    16'h0014: target <= hwrite ? R_NONE : R_ID;
                    default:  target <= R_NONE;
                endcase
                write <= hwrite;
                pending <= 1'b1;
                hready <= 1'b0;
            end
        end
        if (pending) begin
            pending <= 1'b0;
            hready <= 1'b1;
            case (target)
                R_CTRL: begin
                    if (write)
                        enable <= hwdata[0];
                    hrdata <= {31'd0, enable};
                end
                R_STATUS: hrdata <= {30'd0, base_tog != ack_s[1], blank_s[1]};
                R_FRAMES: hrdata <= frames;
                R_BASE: begin
                    // a write while the last is still crossing waits for it
                    if (write && base_tog != ack_s[1]) begin
                        pending <= 1'b1;
                        hready <= 1'b0;
                    end else if (write) begin
                        base_line <= hwdata[29:5];
                    end
                    hrdata <= {2'b01, base_line, 5'd0};
                end
                R_LATE: hrdata <= {16'd0, late_r};
                R_ID: hrdata <= ID_VALUE;
                default: begin
                    hresp <= 1'b1;
                    hready <= 1'b0;
                    error_second <= 1'b1;
                end
            endcase
        end
        // the toggle moves at the edge the value is written, and the pixel
        // side copies the value two of its own clocks after it sees the
        // toggle, so it never copies a BASE that is still changing
        if (pending && target == R_BASE && write && base_tog == ack_s[1])
            base_tog <= ~base_tog;
        if (error_second)
            hready <= 1'b1;

        if (!resetn) begin
            target <= R_NONE;
            write <= 1'b0;
            pending <= 1'b0;
            error_second <= 1'b0;
            hrdata <= 32'd0;
            hready <= 1'b1;
            hresp <= 1'b0;
            enable <= 1'b0;
            frames <= 32'd0;
        end
    end
endmodule
