`default_nettype none

// Write-burst fan-out: one 256-bit burst in, one eight-bit word per DQ pin out.
//
// The proven PHY drives all 32 DQ serializers from a single eight-bit pattern,
// which is what a pattern generator needs and what a memory controller cannot
// use.  This module is the replacement source for those serializer inputs: the
// adapter hands over a whole BL8 burst and each pin receives its own eight
// beats, so the serializer wiring in ddr3_phy.v can be repointed at it without
// changing any primitive or parameter.
//
// Layout.  The controller side and rd_align both use lane l, pin p, beat b at
// bit 64*l + 8*p + b.  A serializer wants pin i's beats in order, D0..D7, so
// the output is pin-major: pin i (= 8*l + p) occupies wdata_pin[8*i +: 8], and
// the permutation is
//
//     wdata_pin[8*(8*l + p) + b] = burst[64*l + 8*p + b]
//
// `pattern_mode` selects the old behaviour for the diagnostic images, where
// every even pin carries the pattern and every odd pin its inverse; with it
// low the burst path is used.  Keeping both means the extracted PHY can be
// repointed without changing what the existing images do until the controller
// asks for it.
module ddr3_wdata (
    input  wire [255:0] burst,        // lane l, pin p, beat b at 64l + 8p + b
    input  wire [7:0]   dq_pat,       // the pattern the diagnostic core drives
    input  wire         pattern_mode, // 1: broadcast the pattern, as before
    output wire [255:0] wdata_pin     // pin i's beats D0..D7 at 8i +: 8
);
    wire [7:0] dq_npat = ~dq_pat;

    genvar lane, pin, beat;
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : lane_g
            for (pin = 0; pin < 8; pin = pin + 1) begin : pin_g
                for (beat = 0; beat < 8; beat = beat + 1) begin : beat_g
                    assign wdata_pin[8*(8*lane + pin) + beat] =
                        pattern_mode ? ((pin % 2) ? dq_npat[beat] : dq_pat[beat])
                                     : burst[64*lane + 8*pin + beat];
                end
            end
        end
    endgenerate
endmodule

`default_nettype wire
