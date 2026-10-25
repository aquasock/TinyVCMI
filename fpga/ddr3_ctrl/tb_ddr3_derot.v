`timescale 1ns/1ps
`default_nettype none

// Unit simulation of the static derotator.
//
// For each lane rotation 0..7 and a pseudo-random payload, the bench builds the
// capture that a lane rotated by that amount would produce -- the inverse of
// the three mux stages, t[i] = tprime[(i - 8r) mod 64] -- and requires the
// module to recover the original beat-major payload exactly.  A wrong rotation
// direction or a transposed byte shows up immediately as a mismatch.
module tb_ddr3_derot;
    reg pclk = 1'b0;
    reg [255:0] dq_q = 0;
    reg [11:0]  rot = 0;
    wire [255:0] data;

    always #5 pclk = ~pclk;

    ddr3_derot dut (.pclk(pclk), .dq_q(dq_q), .rot(rot), .data(data));

    integer errors = 0;
    task fail(input [8*72-1:0] msg);
        begin
            if (errors < 20) $display("FAIL  %0s", msg);
            errors = errors + 1;
        end
    endtask

    // payload[b*32 + l*8 + q], and the captured word built for rotation r
    reg [255:0] payload;
    reg [63:0]  tprime, t;
    integer l, b, q, r, i, j;
    integer seed = 32'h1234_5678;

    initial begin
        for (r = 0; r < 8; r = r + 1) begin
            // a payload that changes with r, so a stale latch cannot pass
            payload = 256'd0;
            for (i = 0; i < 256; i = i + 1)
                payload[i] = $random(seed);

            for (l = 0; l < 4; l = l + 1) begin
                // the transpose the module expects to undo
                for (b = 0; b < 8; b = b + 1)
                    for (q = 0; q < 8; q = q + 1)
                        tprime[8*b + q] = payload[32*b + 8*l + q];
                // t[i] = tprime[(i - 8r) mod 64], so the three stages undo to tprime
                for (i = 0; i < 64; i = i + 1) begin
                    j = (i - 8*r) % 64;
                    if (j < 0) j = j + 64;
                    t[i] = tprime[j];
                end
                // back to the capture layout: pin q, beat b
                for (q = 0; q < 8; q = q + 1)
                    for (b = 0; b < 8; b = b + 1)
                        dq_q[64*l + 8*q + b] = t[8*b + q];
            end

            rot[2:0]   = r;   rot[5:3]   = r;
            rot[8:6]   = r;   rot[11:9]  = r;
            @(posedge pclk); #1;                 // the module registers dq_q
            @(posedge pclk); #1;

            if (data !== payload) begin
                fail("a rotated capture was not derotated back to its payload");
                for (i = 0; i < 256; i = i + 1)
                    if (data[i] !== payload[i]) begin
                        $display("      first difference at bit %0d (beat %0d lane %0d)",
                                 i, i / 32, (i % 32) / 8);
                        i = 256;
                    end
            end
        end

        // per-lane independence: three lanes at 0, one at 5
        payload = 256'd0;
        for (i = 0; i < 256; i = i + 1)
            payload[i] = $random(seed);
        rot = 12'd0;
        for (l = 0; l < 4; l = l + 1) begin
            for (b = 0; b < 8; b = b + 1)
                for (q = 0; q < 8; q = q + 1)
                    tprime[8*b + q] = payload[32*b + 8*l + q];
            r = (l == 2) ? 5 : 0;
            for (i = 0; i < 64; i = i + 1) begin
                j = (i - 8*r) % 64;
                if (j < 0) j = j + 64;
                t[i] = tprime[j];
            end
            for (q = 0; q < 8; q = q + 1)
                for (b = 0; b < 8; b = b + 1)
                    dq_q[64*l + 8*q + b] = t[8*b + q];
        end
        rot[8:6] = 3'd5;
        @(posedge pclk); #1;
        @(posedge pclk); #1;
        if (data !== payload)
            fail("a rotation on one lane disturbed another lane");

        if (errors == 0)
            $display("PASS  every lane rotation 0..7 is undone, and lanes are independent");
        else
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end
endmodule

`default_nettype wire
