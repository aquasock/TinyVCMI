// SPDX-License-Identifier: GPL-3.0-only
`default_nettype none

// Two clients onto ctrl_glue's CPU port (x_), on PCLK: the video fetcher
// (v_, reads only) before the CPU's bridge (c_, ahb_ddr3_pclk).
//
// The request going to the controller is a register, so no client's logic
// reaches into ddr3_ctl's request FIFO through a mux in the same PCLK; it is
// loaded whenever it is empty or the controller takes it, with the video's
// request if there is one, the CPU's otherwise.  The video's request is first
// taken into a one-entry slot whose ready, v_ready, is a register, so the
// fetcher's next request does not wait on ddr3_ctl's ready across the die:
// that path, rdy to vid_fetch's v_valid, was the worst on six seeds of
// sixteen.  The slot costs the video a PCLK and limits it to a read every
// two PCLK, eight times what the screen needs.  The CPU's ready is high in
// the PCLK its request is copied, so it holds valid and its fields until
// then, as ddr3_ctl's own port asks.  The video fetcher limits itself to as
// many reads as its FIFO has room for (video_ddr3.v), so it cannot hold the
// CPU off for longer than that many words.
//
// ddr3_ctl returns reads in the order it took them, so a FIFO of one bit per
// read taken says whose each returning word is.  It must hold every read the
// controller can have in flight; TAGS is far above the controller's FIFO,
// nxt, cur and the PHY's latency, and the simulation stops if it is ever
// exceeded or a word returns with no read open.
//
// Simulation-only: MUT_TAG routes each word by the tag of the read before it;
// tools/sim_ae350_ddr3.sh's video bench must fail it.
module ddr3_arb #(
    parameter integer TAG_LOG2 = 5
) (
    input  wire          pclk,
    input  wire          rst,

    // the video fetcher: reads only
    input  wire          v_valid,
    output wire          v_ready,
    input  wire [24:0]   v_addr,
    output reg           v_rvalid = 1'b0,

    // the CPU's bridge
    input  wire          c_valid,
    output wire          c_ready,
    input  wire          c_we,
    input  wire [24:0]   c_addr,
    input  wire [255:0]  c_wdata,
    input  wire [31:0]   c_wmask,
    output reg           c_rvalid = 1'b0,

    // both clients' read data, valid with v_rvalid or c_rvalid
    output reg  [255:0]  rdata = 256'd0,

    // to ctrl_glue's x_ port
    output reg           x_valid = 1'b0,
    input  wire          x_ready,
    output reg           x_we = 1'b0,
    output reg  [24:0]   x_addr = 25'd0,
    output reg  [255:0]  x_wdata = 256'd0,
    output reg  [31:0]   x_wmask = 32'd0,
    input  wire          x_rvalid,
    input  wire [255:0]  x_rdata
);
    reg  x_vid = 1'b0;                  // the request held is the video's
    reg  v_slot = 1'b0;                 // the video's request, taken
    reg  [24:0] v_slot_addr = 25'd0;
    wire load = !x_valid || x_ready;    // the register is free at this edge
    assign v_ready = !v_slot;
    assign c_ready = load && !v_slot;

    always @(posedge pclk) begin
        if (v_valid && !v_slot) begin
            v_slot <= 1'b1;
            v_slot_addr <= v_addr;
        end
        if (load) begin
            x_valid <= !rst && (v_slot || c_valid);
            x_vid <= v_slot;
            x_we <= !v_slot && c_we;
            x_addr <= v_slot ? v_slot_addr : c_addr;
            x_wdata <= c_wdata;
            x_wmask <= c_wmask;
            if (v_slot)
                v_slot <= 1'b0;
        end
        if (rst) begin
            x_valid <= 1'b0;
            v_slot <= 1'b0;
        end
    end

    // whose each read is: pushed as the controller takes a read, popped as
    // its word returns
    localparam integer TAGS = 1 << TAG_LOG2;
    reg [TAGS-1:0]     tag = {TAGS{1'b0}};
    reg [TAG_LOG2-1:0] t_w = 0, t_r = 0;
    wire push = x_valid && x_ready && !x_we;
    always @(posedge pclk) begin
        v_rvalid <= 1'b0;
        c_rvalid <= 1'b0;
        rdata <= x_rdata;
        if (push) begin
            tag[t_w] <= x_vid;
            t_w <= t_w + 1'b1;
        end
        if (x_rvalid) begin
`ifdef MUT_TAG
            v_rvalid <= tag[t_r - 1'b1];        // the tag before this word's
            c_rvalid <= !tag[t_r - 1'b1];
`else
            v_rvalid <= tag[t_r];
            c_rvalid <= !tag[t_r];
`endif
            t_r <= t_r + 1'b1;
        end
        if (rst) begin
            t_w <= 0;
            t_r <= 0;
            v_rvalid <= 1'b0;
            c_rvalid <= 1'b0;
        end
    end

`ifndef SYNTHESIS
    integer open_reads = 0;
    always @(posedge pclk) begin
        if (rst)
            open_reads = 0;
        else begin
            open_reads = open_reads + push - x_rvalid;
            if (open_reads < 0)
                $fatal(1, "ddr3_arb: a word returned with no read open");
            if (open_reads >= TAGS)
                $fatal(1, "ddr3_arb: more reads in flight than tags");
        end
    end
`endif
endmodule

`default_nettype wire
