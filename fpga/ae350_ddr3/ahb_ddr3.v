// SPDX-License-Identifier: GPL-3.0-only
`default_nettype none

// The DDR3 back end for the AE350 RAM port: ahb_ram's 64-bit transfers on
// the bus clock in, ddr3_ctl's 256-bit requests on PCLK out.
//
// ahb_ram hands over one transfer at a time (TinyNES's ahb_sdram contract):
//
//   req stays high, with addr, write, lanes and wdata steady, until ack
//   pulses; for a read, rdata is valid while ack is high.  A request is
//   never accepted in the cycle ack is high.
//
// One DDR3 word is 32 bytes, one A25 cache line, byte k of the line at
// cmd_wdata[8k +: 8] and write-mask bit k (ddr3_ctl's beat k / 4, lane
// k % 4).  The last line read is held in a one-line buffer, so a cache-line
// fill's four doublewords cost one DDR3 read: the first misses and waits for
// the line, the other three are answered from the buffer a bus clock after
// they are accepted.  A write goes to the DDR3 as one masked write of its
// own doubleword's lanes, every other byte of the line masked, and is
// merged into the buffer if it hits the buffered line, so the buffer never
// holds stale data: the A25 is the RAM port's only master.  A write is
// acknowledged as soon as it is registered for the crossing; the next
// transfer that needs the DDR3 waits until the write is in ddr3_ctl's
// FIFO.  ddr3_ctl serves requests strictly in order, so a read after a
// write to the same word returns the written data.
//
// The bus clock and PCLK come from different PLLs, so the two sides meet in
// a toggle handshake.  The bus side registers the request's fields and
// toggles x_tog in the same edge; PCLK sees x_tog through two flops, by
// when the fields have long settled, and copies them.  The PCLK side
// toggles y_tog once a write is in ddr3_ctl's FIFO, or once a read's line
// is in y_line, and the bus side sees that through two flops; y_line then
// holds still until the next read is requested.  Every crossing signal is a
// register on its own clock.
//
// The two halves are modules of their own, ahb_ddr3_bus and ahb_ddr3_pclk,
// so the AE350 image can place each beside its own side: the bus half near
// the AE350 macro, the PCLK half near ddr3_ctl, with only the handshake's
// registers between them.  ahb_ddr3 joins them, for the bench.
//
// Simulation-only: MUT_MASK masks the lanes of the doubleword after the
// written one, MUT_NOMERGE leaves the buffer unmerged on a write hit; the
// bench must fail both.
module ahb_ddr3 #(
    parameter integer AW = 25           // line address bits: 1 GiB
) (
    // the bus clock side, from ahb_ram
    input  wire          clk,
    input  wire          resetn,
    input  wire          req,
    input  wire          write,
    input  wire [AW+4:3] addr,
    input  wire [7:0]    lanes,
    input  wire [63:0]   wdata,
    output wire          ack,
    output wire [63:0]   rdata,

    // the PCLK side, to ddr3_ctl's request port
    input  wire          pclk,
    input  wire          prst,
    output wire          cmd_valid,
    input  wire          cmd_ready,
    output wire          cmd_we,
    output wire [AW-1:0] cmd_addr,
    output wire [255:0]  cmd_wdata,
    output wire [31:0]   cmd_wmask,
    input  wire          rdata_valid,
    input  wire [255:0]  rdata_line
);
    wire          x_tog, x_we, y_tog;
    wire [AW-1:0] x_line;
    wire [1:0]    x_dw;
    wire [7:0]    x_lanes;
    wire [63:0]   x_wd;
    wire [255:0]  y_line;
    ahb_ddr3_bus #(.AW(AW)) bus (
        .clk(clk), .resetn(resetn), .req(req), .write(write), .addr(addr), .lanes(lanes),
        .wdata(wdata), .ack(ack), .rdata(rdata),
        .x_tog(x_tog), .x_we(x_we), .x_line(x_line), .x_dw(x_dw), .x_lanes(x_lanes), .x_wd(x_wd),
        .y_tog(y_tog), .y_line(y_line));
    ahb_ddr3_pclk #(.AW(AW)) pside (
        .pclk(pclk), .prst(prst),
        .x_tog(x_tog), .x_we(x_we), .x_line(x_line), .x_dw(x_dw), .x_lanes(x_lanes), .x_wd(x_wd),
        .y_tog(y_tog), .y_line(y_line),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_we(cmd_we), .cmd_addr(cmd_addr),
        .cmd_wdata(cmd_wdata), .cmd_wmask(cmd_wmask), .rdata_valid(rdata_valid),
        .rdata_line(rdata_line));
endmodule

// the bus clock half: the line buffer and the request's crossing registers
module ahb_ddr3_bus #(
    parameter integer AW = 25
) (
    input  wire          clk,
    input  wire          resetn,
    input  wire          req,
    input  wire          write,
    input  wire [AW+4:3] addr,
    input  wire [7:0]    lanes,
    input  wire [63:0]   wdata,
    output reg           ack = 1'b0,
    output reg  [63:0]   rdata = 64'd0,
    // to the PCLK half, each a register on the bus clock
    output reg           x_tog = 1'b0,
    output reg           x_we = 1'b0,
    output reg  [AW-1:0] x_line = {AW{1'b0}},
    output reg  [1:0]    x_dw = 2'd0,
    output reg  [7:0]    x_lanes = 8'd0,
    output reg  [63:0]   x_wd = 64'd0,
    // from it, each a register on PCLK
    input  wire          y_tog,
    input  wire [255:0]  y_line
);
    reg          lb_valid = 1'b0;           // the line buffer
    reg [AW-1:0] lb_tag = {AW{1'b0}};
    reg [255:0]  lb_data = 256'd0;

    reg          busy = 1'b0;               // a request is crossing
    reg          b_read = 1'b0;             // and it is a read awaiting its line
    reg [2:0]    y_s = 3'd0;                // y_tog through two flops, and the last
    wire         y_edge = y_s[2] ^ y_s[1];

    wire [AW-1:0] line = addr[AW+4:5];
    wire          hit = lb_valid && lb_tag == line;

    function [255:0] merge(input [255:0] old, input [1:0] dw, input [7:0] ln, input [63:0] wd);
        integer k;
        begin
            merge = old;
            for (k = 0; k < 8; k = k + 1)
`ifdef MUT_MASK
                if (ln[k]) merge[64*((dw + 2'd1) & 2'd3) + 8*k +: 8] = wd[8*k +: 8];
`else
                if (ln[k]) merge[64*dw + 8*k +: 8] = wd[8*k +: 8];
`endif
        end
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            ack <= 1'b0;
            rdata <= 64'd0;
            lb_valid <= 1'b0;
            busy <= 1'b0;
            b_read <= 1'b0;
            y_s <= 3'd0;
        end else begin
            ack <= 1'b0;
            y_s <= {y_s[1:0], y_tog};
            if (busy && y_edge) begin
                busy <= 1'b0;
                b_read <= 1'b0;
                if (b_read) begin
                    lb_valid <= 1'b1;
                    lb_tag <= x_line;
                    lb_data <= y_line;
                    rdata <= y_line[64*x_dw +: 64];
                    ack <= 1'b1;
                end
            end
            if (req && !ack && !b_read) begin
                if (!write && hit) begin
                    rdata <= lb_data[64*addr[4:3] +: 64];
                    ack <= 1'b1;
                end else if (!busy) begin
                    x_tog <= ~x_tog;
                    x_we <= write;
                    x_line <= line;
                    x_dw <= addr[4:3];
                    x_lanes <= lanes;
                    x_wd <= wdata;
                    busy <= 1'b1;
                    b_read <= !write;
                    if (write) begin
                        ack <= 1'b1;
`ifndef MUT_NOMERGE
                        if (hit)
                            lb_data <= merge(lb_data, addr[4:3], lanes, wdata);
`endif
                    end
                end
            end
        end
    end

endmodule

// the PCLK half: the request into ddr3_ctl, and the answer back
module ahb_ddr3_pclk #(
    parameter integer AW = 25
) (
    input  wire          pclk,
    input  wire          prst,
    input  wire          x_tog,
    input  wire          x_we,
    input  wire [AW-1:0] x_line,
    input  wire [1:0]    x_dw,
    input  wire [7:0]    x_lanes,
    input  wire [63:0]   x_wd,
    output reg           y_tog = 1'b0,
    output reg  [255:0]  y_line = 256'd0,   // still from y_tog's move until the next read
    output reg           cmd_valid = 1'b0,
    input  wire          cmd_ready,
    output reg           cmd_we = 1'b0,
    output reg  [AW-1:0] cmd_addr = {AW{1'b0}},
    output reg  [255:0]  cmd_wdata = 256'd0,
    output reg  [31:0]   cmd_wmask = 32'd0,
    input  wire          rdata_valid,
    input  wire [255:0]  rdata_line
);
    reg [2:0] x_s = 3'd0;                   // x_tog through two flops, and the last
    reg       p_read = 1'b0;                // a read's line is due
    always @(posedge pclk) begin
        if (prst) begin
            x_s <= 3'd0;
            y_tog <= 1'b0;
            p_read <= 1'b0;
            cmd_valid <= 1'b0;
        end else begin
            x_s <= {x_s[1:0], x_tog};
            if (x_s[2] ^ x_s[1]) begin
                cmd_valid <= 1'b1;
                cmd_we <= x_we;
                cmd_addr <= x_line;
                cmd_wdata <= {4{x_wd}};
                cmd_wmask <= ~({24'd0, x_lanes} << (8 * x_dw));
            end
            if (cmd_valid && cmd_ready) begin
                cmd_valid <= 1'b0;
                if (cmd_we)
                    y_tog <= ~y_tog;
                else
                    p_read <= 1'b1;
            end
            if (p_read && rdata_valid) begin
                p_read <= 1'b0;
                y_line <= rdata_line;
                y_tog <= ~y_tog;
            end
        end
    end

`ifndef SYNTHESIS
    // a toggle may not move again before the other side has answered it
    always @(posedge pclk)
        if (!prst && (x_s[2] ^ x_s[1]) && (cmd_valid || p_read))
            $fatal(1, "ahb_ddr3: a request crossed while the last was still open");
    always @(posedge pclk)
        if (!prst && rdata_valid && !p_read)
            $fatal(1, "ahb_ddr3: read data arrived with no read open");
`endif
endmodule

`default_nettype wire
