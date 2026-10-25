`default_nettype none

// Static derotator: the trained part of the read boundary, with the training
// removed.
//
// rd_align discovers each lane's word rotation by comparing against a known
// pattern, which a memory controller cannot do because its data is arbitrary.
// What a controller needs is the *result*: once the pattern-based training has
// run at start-up and the per-lane rotations are known, the same transpose and
// byte rotation can be applied to every captured burst as a fixed operation.
//
// The arithmetic is copied from rd_align so the two agree bit for bit: pin p,
// beat b of lane l is at 64l + 8p + b on the capture side, the lane's 64-bit
// word is transposed so byte b holds beat b, and the rotation is three 2:1 mux
// stages of eight bits -- the eight-way mux on every bit does not close at
// 100 MHz.  Output is beat-major: beat b, lane l at 32b + 8l, the layout the
// checker and the probe already use.
module ddr3_derot (
    input  wire         pclk,
    input  wire [255:0] dq_q,     // lane l, pin p, beat b at 64l + 8p + b
    input  wire [11:0]  rot,      // per lane, 3 bits, frozen after training
    output wire [255:0] data      // beat b, lane l at 32b + 8l
);
    // registered first: a burst is judged by the frame it was captured in
    reg [255:0] dq_d;
    always @(posedge pclk)
        dq_d <= dq_q;

    genvar gl, gb, gq;
    generate
        for (gl = 0; gl < 4; gl = gl + 1) begin : g_lane
            wire [63:0] t, s1, s2, s3;
            for (gb = 0; gb < 8; gb = gb + 1)
                for (gq = 0; gq < 8; gq = gq + 1)
                    assign t[8*gb + gq] = dq_d[64*gl + 8*gq + gb];
            assign s1 = rot[3*gl]     ? {t[7:0],   t[63:8]}   : t;
            assign s2 = rot[3*gl + 1] ? {s1[15:0], s1[63:16]} : s1;
            assign s3 = rot[3*gl + 2] ? {s2[31:0], s2[63:32]} : s2;
            for (gb = 0; gb < 8; gb = gb + 1)
                for (gq = 0; gq < 8; gq = gq + 1)
                    assign data[32*gb + 8*gl + gq] = s3[8*gb + gq];
        end
    endgenerate
endmodule

`default_nettype wire
