// SPDX-License-Identifier: GPL-3.0-only
`default_nettype none

// Two clients onto ctrl_glue's CPU port (x_), on PCLK: the video fetcher
// (v_, reads only) before the CPU's bridge (c_, ahb_ddr3_pclk).
//
// The request going to the controller is a register, so no client's logic
// reaches into ddr3_ctl's request FIFO through a mux in the same PCLK.  It is
// loaded only while it is empty, so no signal from ddr3_ctl's ready reaches
// its 314 clock enables: ready used to be in the load condition, and
// x_ready's route to those enables was 2.67 ns over 100 MHz on eight seeds of
// core-log entry 34's sweep.  Ready now reaches one flop, the clear of
// x_valid, and a request a client is ready to make is taken in the PCLK the
// register is free, so the accepted rate is a request every two PCLK, against
// the video's one line read per 145 ns and the CPU's one posted write per
// 69 ns.  The video's request is first taken into a one-entry slot whose
// ready, v_ready, is a register, so the fetcher's next request does not wait
// on ddr3_ctl's ready across the die: that path, rdy to vid_fetch's v_valid,
// was the worst on six seeds of sixteen.  The slot costs the video a PCLK and
// limits it to a read every two PCLK, eight times what the screen needs.  The
// CPU's ready is high in the PCLK its request is copied, so it holds valid
// and its fields until then, as ddr3_ctl's own port asks.  The video fetcher
// limits itself to as many reads as its FIFO has room for (video_ddr3.v), so
// it cannot hold the CPU off for longer than that many words.
//
// ddr3_ctl returns reads in the order it took them, so a FIFO of one bit per
// read taken says whose each returning word is.  It must hold every read the
// controller can have in flight; TAGS is far above the controller's FIFO,
// nxt, cur and the PHY's latency, and the simulation stops if it is ever
// exceeded or a word returns with no read open.
//
// dbg is for the board's stall dump (ae350_sys.sv): each client's reads in
// flight, counted up as the controller takes one and down as its word
// returns, a sticky flag per client set by a word returned to it with none
// in flight, the request register's state and the tag FIFO's pointers.
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
    input  wire [255:0]  x_rdata,

    // {c_err, v_err, x_vid, v_slot, x_valid, x_ready, c_fl[5:0], v_fl[5:0], t_w, t_r}
    output wire [17+2*TAG_LOG2:0] dbg
);
    reg  x_vid = 1'b0;                  // the request held is the video's
    reg  v_slot = 1'b0;                 // the video's request, taken
    reg  [24:0] v_slot_addr = 25'd0;
    wire load = !x_valid;               // the register is free at this edge
`ifdef MUT_LOAD
    // the mutant: ready back in the enable.  The register is then reloaded in
    // the very cycle it retires, and the request just committed is lost; the
    // invariant below must fail it.
    wire load_m = !x_valid || x_ready;
`else
    wire load_m = load;
`endif
    assign v_ready = !v_slot;
    assign c_ready = load && !v_slot;
`ifndef SYNTHESIS
    wire loaded = load_m && (v_slot || c_valid);      // the invariant's, below
`endif

    always @(posedge pclk) begin
        if (load_m && (v_slot || c_valid)) begin
            x_valid <= 1'b1;
            x_vid <= v_slot;
            x_we <= !v_slot && c_we;
            x_addr <= v_slot ? v_slot_addr : c_addr;
            x_wdata <= c_wdata;
            x_wmask <= c_wmask;
            if (v_slot)
                v_slot <= 1'b0;
        end
        if (x_valid && x_ready)
            x_valid <= 1'b0;
        if (v_valid && !v_slot) begin
            v_slot <= 1'b1;
            v_slot_addr <= v_addr;
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

    reg  [5:0] c_fl = 6'd0, v_fl = 6'd0;
    reg        c_err = 1'b0, v_err = 1'b0;
    wire       r_vid = tag[t_r];
    // The counts' increments are registered first.  In front of the adders the
    // tag read (tag[t_r], a 32-bit select by a counter) and the push's x_ready
    // term were 2.8 ns over 100 MHz on ten seeds of twelve, and the counts are
    // the STALL report's diagnostics, not the datapath: they are one PCLK late
    // and identical once settled.  c_err and v_err read the count as it stands
    // before this cycle's change, which is the count the word returned into.
    reg        c_inc = 1'b0, c_dec = 1'b0, v_inc = 1'b0, v_dec = 1'b0;
    always @(posedge pclk) begin
        c_inc <= push && !x_vid;
        v_inc <= push && x_vid;
        c_dec <= x_rvalid && !r_vid;
        v_dec <= x_rvalid && r_vid;
        c_fl <= c_fl + c_inc - c_dec;
        v_fl <= v_fl + v_inc - v_dec;
        if (c_dec && c_fl == 6'd0) c_err <= 1'b1;
        if (v_dec && v_fl == 6'd0) v_err <= 1'b1;
        if (rst) begin
            c_fl <= 6'd0;
            v_fl <= 6'd0;
            c_inc <= 1'b0;
            c_dec <= 1'b0;
            v_inc <= 1'b0;
            v_dec <= 1'b0;
            c_err <= 1'b0;
            v_err <= 1'b0;
        end
    end
`ifndef SYNTHESIS
    // A held request lives until the controller takes it, and nothing is
    // loaded while one is held.  The first clause fails MUT_LOAD, which
    // reloads the register in the cycle the old request retires and so loses
    // the new one; the second fails a register cleared while the controller
    // was not ready.  Neither can be true of the real logic, where the load
    // needs an empty register and the clear needs x_ready.
    reg held = 1'b0;
    always @(posedge pclk) begin
        if (!rst && loaded && x_valid && x_ready)
            $display("FAIL  ddr3_arb: a request was loaded in the cycle it was taken");
        held <= !rst && x_valid && !x_ready;
        if (!rst && held && !x_valid)
            $display("FAIL  ddr3_arb: a held request was dropped before it was taken");
        if ((!rst && loaded && x_valid && x_ready) || (!rst && held && !x_valid))
            $finish;
    end
`endif
    assign dbg = {c_err, v_err, x_vid, v_slot, x_valid, x_ready, c_fl, v_fl, t_w, t_r};

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
