`default_nettype none

// The controller's first user: a memory test on ddr3_ctl's request port.
//
// Each pass writes words 0 .. 2^N_LOG2 - 1 in order, reads them back in
// order with a READ offered every PCLK, then reads 2^R_LOG2 words at
// pseudo-random addresses in that range, and checks every word read against
// what its address was written with.  Words are 256 bits, one BL8 burst of
// the x32 array, so N_LOG2 = 25 covers the whole 1 GiB.
//
// The data is each address's own and changes every pass: beat k, 32 bits,
// is one xorshift32 round (XOR only, no carry chain) of the address, k and
// the pass's seed, so every DQ pin carries its own sequence and no two
// words, beats or passes are alike.
//
// A write carries its data, made from its address as the port takes it.
// ddr3_ctl returns read data in request order, so each word read is checked
// against the oldest read address, kept in a FIFO; a READ is offered only
// with room in it, and every request is held until the port takes it.
//
// Errors are counted per lane, a word whose lane l (DQ 8l..8l+7, any beat)
// differs counting once for that lane, and the first failing word's address
// and the XOR of what came back with what was owed are kept.
module ddr3_bist #(
    parameter integer AW = 25,          // native port address, 256-bit words
    parameter integer N_LOG2 = 25,      // words written and read per pass
    parameter integer R_LOG2 = 20       // random READs per pass
) (
    input  wire          pclk,
    input  wire          rst,           // also stops the test
    input  wire          clr,           // clear the counts and the first error

    output reg           cmd_valid = 1'b0,
    input  wire          cmd_ready,
    output reg           cmd_we = 1'b0,
    output reg  [AW-1:0] cmd_addr = {AW{1'b0}},
    output wire [255:0]  cmd_wdata,
    input  wire          rdata_valid,
    input  wire [255:0]  rdata_data,

    output reg  [3:0]    state = 4'd0,
    output reg  [15:0]   passes = 16'd0,
    output reg  [31:0]   n_written = 32'd0,
    output reg  [31:0]   n_checked = 32'd0,
    output reg  [127:0]  lane_err = 128'd0,     // lane l at [32l +: 32]
    output reg           err_seen = 1'b0,
    output reg  [AW-1:0] err_addr = {AW{1'b0}},
    output reg  [255:0]  err_diff = 256'd0
);

    function [255:0] gen(input [AW-1:0] a, input [31:0] s);
        integer gk;
        reg [2:0] g3;
        reg [31:0] x;
        begin
            for (gk = 0; gk < 8; gk = gk + 1) begin
                g3 = gk;
                x = {a, g3} ^ s ^ (32'h9e3779b9 * (gk + 1));
                x = x ^ (x << 13);
                x = x ^ (x >> 17);
                x = x ^ (x << 5);
                gen[32*gk +: 32] = x;
            end
        end
    endfunction

    function [31:0] xs_next(input [31:0] x);
        reg [31:0] y;
        begin
            y = x ^ (x << 13);
            y = y ^ (y >> 17);
            xs_next = y ^ (y << 5);
        end
    endfunction

    localparam [3:0] S_IDLE = 4'd0, S_WR = 4'd1, S_WRW = 4'd2, S_RD = 4'd3, S_RDW = 4'd4,
                     S_RR = 4'd5, S_RRW = 4'd6;
    localparam integer DEPTH = 64;
    localparam [AW-1:0] LAST = (1 << N_LOG2) - 1;
    localparam [31:0] RLAST = (1 << R_LOG2) - 1;

    reg [31:0]   seed = 32'h2545f491;
    reg [31:0]   rcnt = 32'd0;
    reg [31:0]   lfsr = 32'h1;

    // the words owed, as their addresses
    reg [AW-1:0] rq [0:DEPTH-1];
    reg [5:0]    rq_w = 6'd0, rq_r = 6'd0;
    reg [6:0]    rq_n = 7'd0;
    wire         take = cmd_valid && cmd_ready;
    wire         rpop = rdata_valid && (rq_n != 7'd0);
    assign cmd_wdata = gen(cmd_addr, seed);

    // the check, a PCLK behind the word
    reg          ck_v = 1'b0;
    reg [AW-1:0] ck_a = {AW{1'b0}};
    reg [255:0]  ck_got = 256'd0, ck_exp = 256'd0;
    wire [255:0] diff = ck_got ^ ck_exp;
    reg  [3:0]   lane_bad;
    integer cl, cb;
    always @(*)
        for (cl = 0; cl < 4; cl = cl + 1) begin
            lane_bad[cl] = 1'b0;
            for (cb = 0; cb < 8; cb = cb + 1)
                if (diff[32*cb + 8*cl +: 8] != 8'd0)
                    lane_bad[cl] = 1'b1;
        end

    // room for one more READ after the one being taken
    wire rroom = (rq_n + (take && !cmd_we ? 7'd1 : 7'd0)) < DEPTH - 2;

    integer ql;
    always @(posedge pclk) begin
        // the FIFO
        if (take && !cmd_we) begin
            rq[rq_w] <= cmd_addr;
            rq_w <= rq_w + 6'd1;
        end
        if (rpop)
            rq_r <= rq_r + 6'd1;
        rq_n <= rq_n + ((take && !cmd_we) ? 7'd1 : 7'd0) - (rpop ? 7'd1 : 7'd0);

        // the check
        ck_v <= rpop;
        ck_a <= rq[rq_r];
        ck_got <= rdata_data;
        ck_exp <= gen(rq[rq_r], seed);
        if (take && cmd_we && n_written != 32'hffffffff)
            n_written <= n_written + 32'd1;
        if (ck_v) begin
            if (n_checked != 32'hffffffff)
                n_checked <= n_checked + 32'd1;
            for (ql = 0; ql < 4; ql = ql + 1)
                if (lane_bad[ql] && lane_err[32*ql +: 32] != 32'hffffffff)
                    lane_err[32*ql +: 32] <= lane_err[32*ql +: 32] + 32'd1;
            if (|lane_bad && !err_seen) begin
                err_seen <= 1'b1;
                err_addr <= ck_a;
                err_diff <= diff;
            end
        end
        if (clr) begin
            passes <= 16'd0;
            n_written <= 32'd0;
            n_checked <= 32'd0;
            lane_err <= 128'd0;
            err_seen <= 1'b0;
        end

        // the passes
        case (state)
            S_IDLE: begin
                cmd_we <= 1'b1;
                cmd_addr <= {AW{1'b0}};
                cmd_valid <= 1'b1;
                state <= S_WR;
            end
            S_WR: if (take) begin
                if (cmd_addr == LAST) begin
                    cmd_valid <= 1'b0;
                    state <= S_WRW;
                end else
                    cmd_addr <= cmd_addr + 1'b1;
            end
            S_WRW: begin
                cmd_we <= 1'b0;
                cmd_addr <= {AW{1'b0}};
                cmd_valid <= 1'b1;
                state <= S_RD;
            end
            S_RD: if (take) begin
                if (cmd_addr == LAST) begin
                    cmd_valid <= 1'b0;
                    state <= S_RDW;
                end else begin
                    cmd_addr <= cmd_addr + 1'b1;
                    cmd_valid <= rroom;
                end
            end else if (!cmd_valid && rroom)
                cmd_valid <= 1'b1;
            S_RDW: if (rq_n == 7'd0 && !ck_v) begin
                rcnt <= 32'd0;
                cmd_addr <= lfsr[AW-1:0] & LAST;
                cmd_valid <= 1'b1;
                state <= S_RR;
            end
            S_RR: if (take) begin
                lfsr <= xs_next(lfsr);          // the next random address
                if (rcnt == RLAST) begin
                    cmd_valid <= 1'b0;
                    state <= S_RRW;
                end else begin
                    rcnt <= rcnt + 32'd1;
                    cmd_addr <= xs_next(lfsr) & LAST;
                    cmd_valid <= rroom;
                end
            end else if (!cmd_valid && rroom)
                cmd_valid <= 1'b1;
            S_RRW: if (rq_n == 7'd0 && !ck_v) begin
                if (passes != 16'hffff)
                    passes <= passes + 16'd1;
                seed <= seed + 32'h9e3779b9;
                cmd_we <= 1'b1;
                cmd_addr <= {AW{1'b0}};
                cmd_valid <= 1'b1;
                state <= S_WR;
            end
            default: state <= S_IDLE;
        endcase
        if (rst) begin
            state <= S_IDLE;
            cmd_valid <= 1'b0;
            rq_w <= 6'd0; rq_r <= 6'd0; rq_n <= 7'd0;
            ck_v <= 1'b0;
        end
    end
endmodule

`default_nettype wire
