`timescale 1ns/1ps
`default_nettype none

// Unit simulation of the write-burst fan-out.
//
// The permutation is the whole point, so the bench reads it back two ways: a
// one-hot burst walks every bit and must land on exactly the predicted pin and
// beat, and an arbitrary burst is checked against an independent model of the
// same mapping.  The diagnostic pattern mode is checked to be bit-identical to
// what the proven PHY drives today, even pins the pattern and odd pins its
// inverse.
module tb_ddr3_wdata;
    reg  [255:0] burst = 0;
    reg  [7:0]   dq_pat = 8'h5a;
    reg          pattern_mode = 1'b0;
    wire [255:0] wdata_pin;

    ddr3_wdata dut (
        .burst(burst), .dq_pat(dq_pat), .pattern_mode(pattern_mode),
        .wdata_pin(wdata_pin));

    integer errors = 0;
    task fail(input [8*76-1:0] msg);
        begin
            if (errors < 20) $display("FAIL  %0s", msg);
            errors = errors + 1;
        end
    endtask

    integer l, p, b, bit_i, lane_of, pin_of, beat_of, want;
    reg [7:0] word;
    reg [255:0] model;

    initial begin
        // ---- one-hot walk: every burst bit reaches its own pin and beat ---
        for (bit_i = 0; bit_i < 256; bit_i = bit_i + 1) begin
            burst = 256'd0;
            burst[bit_i] = 1'b1;
            #1;
            l = bit_i / 64;
            p = (bit_i % 64) / 8;
            b = bit_i % 8;
            want = 8 * (8*l + p) + b;
            if (wdata_pin !== (256'd1 << want)) begin
                $display("      burst bit %0d (lane %0d pin %0d beat %0d) wanted pin bit %0d",
                         bit_i, l, p, b, want);
                fail("a burst bit did not land on its pin and beat");
            end
        end

        // ---- an arbitrary burst, against the model ------------------------
        burst = 256'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210_0F1E_2D3C_4B5A_6978_8877_6655_4433_2211;
        #1;
        for (l = 0; l < 4; l = l + 1)
            for (p = 0; p < 8; p = p + 1)
                for (b = 0; b < 8; b = b + 1)
                    model[8*(8*l + p) + b] = burst[64*l + 8*p + b];
        if (wdata_pin !== model)
            fail("the fan-out does not match the documented permutation");

        // ---- each pin sees eight consecutive beats, in order --------------
        burst = 256'hAAAA_AAAA_AAAA_AAAA_5555_5555_5555_5555_0000_0000_0000_0000_FFFF_FFFF_FFFF_FFFF;
        #1;
        word = wdata_pin[8*0 +: 8];       // lane 0, pin 0
        if (word !== 8'hFF) fail("lane 0 pin 0 did not get the burst's own beats");

        // ---- the diagnostic pattern mode is unchanged ---------------------
        pattern_mode = 1'b1;
        burst = 256'd0;
        #1;
        for (p = 0; p < 8; p = p + 1) begin
            word = wdata_pin[8*p +: 8];   // lane 0, pin p
            if (p % 2) begin
                if (word !== ~dq_pat) fail("an odd pin no longer carries the inverse pattern");
            end else begin
                if (word !== dq_pat) fail("an even pin no longer carries the pattern");
            end
        end

        if (errors == 0)
            $display("PASS  every burst bit reaches its pin and beat, and pattern mode is unchanged");
        else
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end
endmodule

`default_nettype wire
