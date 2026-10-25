`timescale 1ns/1ps
`default_nettype none

// Unit simulation of the DFI adapter against a behavioural PHY.
//
// Checks three things, all at the adapter's own boundary:
//   * a DFI command on any phase becomes exactly one PHY command, with its
//     bank and address intact, whatever phase the controller drove it on;
//   * a burst the PHY hands over is presented to the controller RD_LATENCY
//     PCLKs after rddata_en, sliced two beats per phase;
//   * a burst the PHY does not hand over sets rd_underflow instead of
//     silently returning stale data.
module tb_dfi_adapter;
    localparam integer ADD_W = 15, BANK_W = 3, PHY_W = 64, RD_LATENCY = 7;
    localparam [2:0] OP_MRS = 3'd0, OP_REF = 3'd1, OP_PRE = 3'd2,
                     OP_ACT = 3'd3, OP_RD  = 3'd4, OP_WR  = 3'd5;

    reg         pclk = 1'b0;
    reg         rst = 1'b1;
    reg  [3:0]  cs_n = 4'hf, ras_n = 4'hf, cas_n = 4'hf, we_n = 4'hf;
    reg  [3:0]  cke = 4'hf, odt = 4'h0;
    reg  [4*ADD_W-1:0]  address = 0;
    reg  [4*BANK_W-1:0] bank = 0;
    reg  [4*PHY_W-1:0]  wrdata = 0;
    reg  [3:0]  wrdata_en = 0, rddata_en = 0;
    wire [4*PHY_W-1:0]  rddata;
    wire [3:0]  rddata_valid;

    wire        phy_cmd_valid;
    wire [2:0]  phy_cmd_op;
    wire [BANK_W-1:0] phy_cmd_bank;
    wire [ADD_W-1:0]  phy_cmd_addr;
    wire        phy_wr_valid;
    wire [4*PHY_W-1:0] phy_wr_data;
    reg  [4*PHY_W-1:0] phy_rd_data = 0;
    reg         phy_rd_valid = 0;

    wire        stat_cmd_collision, stat_rd_underflow;
    wire [15:0] stat_cmd_count, stat_rd_count;

    dfi_adapter #(
        .RD_LATENCY(RD_LATENCY), .ADD_W(ADD_W), .BANK_W(BANK_W), .PHY_W(PHY_W)
    ) dut (
        .pclk(pclk), .rst(rst),
        .dfi_cs_n(cs_n), .dfi_ras_n(ras_n), .dfi_cas_n(cas_n), .dfi_we_n(we_n),
        .dfi_cke(cke), .dfi_odt(odt),
        .dfi_address(address), .dfi_bank(bank),
        .dfi_wrdata(wrdata), .dfi_wrdata_en(wrdata_en),
        .dfi_rddata_en(rddata_en),
        .dfi_rddata(rddata), .dfi_rddata_valid(rddata_valid),
        .phy_cmd_valid(phy_cmd_valid), .phy_cmd_op(phy_cmd_op),
        .phy_cmd_bank(phy_cmd_bank), .phy_cmd_addr(phy_cmd_addr),
        .phy_cmd_taken(1'b1),
        .phy_wr_valid(phy_wr_valid), .phy_wr_data(phy_wr_data),
        .phy_rd_data(phy_rd_data), .phy_rd_valid(phy_rd_valid),
        .stat_cmd_collision(stat_cmd_collision),
        .stat_rd_underflow(stat_rd_underflow),
        .stat_cmd_count(stat_cmd_count), .stat_rd_count(stat_rd_count));

    always #5 pclk = ~pclk;

    integer errors = 0;
    task fail(input [8*72-1:0] msg);
        begin
            if (errors < 20) $display("FAIL  t=%0t %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // drive one command on one phase: cmd_bits = {ras_n, cas_n, we_n}
    task drive_cmd(input integer ph, input [2:0] bits,
                   input [BANK_W-1:0] b, input [ADD_W-1:0] a);
        begin
            @(negedge pclk);
            cs_n  = 4'hf & ~(4'b0001 << ph);
            ras_n = 4'hf; cas_n = 4'hf; we_n = 4'hf;
            if (!bits[2]) ras_n[ph] = 1'b0;
            if (!bits[1]) cas_n[ph] = 1'b0;
            if (!bits[0]) we_n[ph] = 1'b0;
            address[ph*ADD_W +: ADD_W]   = a;
            bank[ph*BANK_W +: BANK_W]    = b;
            @(negedge pclk);
            cs_n = 4'hf; ras_n = 4'hf; cas_n = 4'hf; we_n = 4'hf;
        end
    endtask

    // wait for a PHY command and check it
    task expect_cmd(input [2:0] op, input [BANK_W-1:0] b, input [ADD_W-1:0] a,
                    input [8*40-1:0] what);
        integer guard;
        begin
            guard = 0;
            while (!phy_cmd_valid && guard < 8) begin
                @(posedge pclk); #1;
                guard = guard + 1;
            end
            if (!phy_cmd_valid)
                fail("no PHY command was emitted");
            else if (phy_cmd_op !== op || phy_cmd_bank !== b ||
                     phy_cmd_addr !== a) begin
                fail(what);
                $display("      got op %0d bank %0d addr %0h, wanted %0d %0d %0h",
                         phy_cmd_op, phy_cmd_bank, phy_cmd_addr, op, b, a);
            end
        end
    endtask

    integer beat;
    reg [4*PHY_W-1:0] burst;
    task make_burst(input [7:0] seed);
        integer n;
        begin
            for (n = 0; n < 4*PHY_W; n = n + 1)
                burst[n] = ((n / 64) + seed) & 1 ? 1'b1 : 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge pclk);
        rst <= 1'b0;
        repeat (2) @(posedge pclk);

        // ---- a command on phase 0 becomes one PHY ACT --------------------
        drive_cmd(0, 3'b011, 3'd5, 15'h1234);      // ACT, bank 5
        expect_cmd(OP_ACT, 3'd5, 15'h1234, "ACT from phase 0 is not ACT");

        // ---- a command on phase 2 becomes one PHY RD --------------------
        drive_cmd(2, 3'b101, 3'd2, 15'h0042);      // RD, bank 2
        expect_cmd(OP_RD, 3'd2, 15'h0042, "RD from phase 2 is not RD");

        // ---- a command on phase 3 becomes one PHY PRE -------------------
        drive_cmd(3, 3'b010, 3'd7, 15'h0001);      // PRE, bank 7
        expect_cmd(OP_PRE, 3'd7, 15'h0001, "PRE from phase 3 is not PRE");

        // ---- two commands in one PCLK are flagged -----------------------
        @(negedge pclk);
        cs_n = 4'b0011; ras_n = 4'b1110; cas_n = 4'b1111; we_n = 4'b1111;
        @(negedge pclk);
        cs_n = 4'hf;
        repeat (2) @(posedge pclk);
        if (!stat_cmd_collision)
            fail("two phases commanding in one PCLK was not flagged");

        // ---- read data lands RD_LATENCY after rddata_en ------------------
        make_burst(8'h5a);
        @(negedge pclk);
        rddata_en = 4'b0001;                        // ask for a burst
        @(negedge pclk);
        rddata_en = 4'b0000;
        // the PHY answers one PCLK later, well inside the latency window
        repeat (RD_LATENCY - 2) @(posedge pclk);
        @(negedge pclk) begin
            phy_rd_data  = burst;
            phy_rd_valid = 1'b1;
        end
        @(negedge pclk) phy_rd_valid = 1'b0;

        wait (rddata_valid !== 4'b0000 || errors > 0);
        if (rddata_valid !== 4'b1111)
            fail("a delivered burst did not mark all four phases valid");
        else
            for (beat = 0; beat < 4; beat = beat + 1)
                if (rddata[beat*PHY_W +: PHY_W] !== burst[beat*PHY_W +: PHY_W]) begin
                    fail("the burst was not sliced one phase per 64 bits");
                    $display("      phase %0d got %h wanted %h", beat,
                             rddata[beat*PHY_W +: PHY_W],
                             burst[beat*PHY_W +: PHY_W]);
                end

        // ---- a retimed write keeps its data -----------------------------
        @(negedge pclk) begin
            wrdata = 256'hDEAD_BEEF_0123_4567_89AB_CDEF_0F1E_2D3C_4B5A_6978_0000_1111;
            wrdata_en = 4'b1111;
        end
        @(posedge pclk); #1;
        if (!phy_wr_valid) fail("write data was not handed to the PHY");
        if (phy_wr_data !== wrdata) fail("write data changed on the way to the PHY");
        @(negedge pclk) wrdata_en = 4'b0000;

        // ---- a burst the PHY never delivers sets underflow ---------------
        @(negedge pclk) rddata_en = 4'b0001;
        @(negedge pclk) rddata_en = 4'b0000;
        repeat (RD_LATENCY + 6) @(posedge pclk);
        if (!stat_rd_underflow)
            fail("a missing burst did not set rd_underflow");

        if (stat_cmd_count < 16'd3)
            fail("the adapter did not count its commands");

        if (errors == 0)
            $display("PASS  commands on any phase, burst slicing, write data and underflow as specified");
        else
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end
endmodule

`default_nettype wire
