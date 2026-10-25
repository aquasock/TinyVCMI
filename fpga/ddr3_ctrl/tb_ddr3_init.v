`timescale 1ns/1ps
`default_nettype none

// Unit simulation of the DDR3 power-up sequencer, with the microsecond waits
// scaled down so the order and the gaps are what is checked, not the wall
// time: RESET# before CKE, CKE before the first MRS, MR2/MR3/MR1/MR0 in that
// order with their DDR3-800 values, ZQCL with A10 high, then init_done.
module tb_ddr3_init;
    localparam integer T_IDLE = 4, T_RESET = 10, T_CKE = 12,
                       T_MR = 3, T_MR_GAP = 2, T_ZQ = 6;

    reg pclk = 1'b0, phy_ready = 1'b0;
    wire cs_n, ras_n, cas_n, we_n;
    wire [2:0] ba;
    wire [15:0] addr;
    wire ddr_reset_n, cke, odt, init_done;

    ddr3_init #(
        .T_IDLE(T_IDLE), .T_RESET(T_RESET), .T_CKE(T_CKE),
        .T_MR(T_MR), .T_MR_GAP(T_MR_GAP), .T_ZQ(T_ZQ)
    ) dut (
        .pclk(pclk), .phy_ready(phy_ready),
        .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
        .ba(ba), .addr(addr), .ddr_reset_n(ddr_reset_n),
        .cke(cke), .odt(odt), .init_done(init_done));

    always #5 pclk = ~pclk;

    integer errors = 0;
    task fail(input [8*72-1:0] msg);
        begin
            if (errors < 20) $display("FAIL  t=%0t %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // record every command as it leaves, with the state of the pins
    integer ncmd = 0;
    reg [3:0] c_cmd [0:15];
    reg [2:0] c_ba  [0:15];
    reg [15:0] c_addr [0:15];
    always @(posedge pclk) begin
        if (!cs_n) begin
            c_cmd[ncmd]  = {ras_n, cas_n, we_n, cs_n};
            c_ba[ncmd]   = ba;
            c_addr[ncmd] = addr;
            ncmd = ncmd + 1;
        end
    end

    reg reset_seen = 1'b0, cke_seen = 1'b0;
    integer first_mrs = -1;
    always @(posedge pclk) begin
        if (ddr_reset_n) reset_seen = 1'b1;
        if (cke)         cke_seen = 1'b1;
    end

    integer i;
    initial begin
        repeat (3) @(posedge pclk);
        if (ddr_reset_n !== 1'b0 || cke !== 1'b0)
            fail("RESET# or CKE was high before the PHY reported ready");

        phy_ready <= 1'b1;
        wait (init_done === 1'b1);
        repeat (2) @(posedge pclk);

        if (!reset_seen || !cke_seen)
            fail("RESET# or CKE never rose");
        if (ncmd != 5) begin
            fail("the sequencer did not issue exactly five commands");
            $display("      saw %0d commands", ncmd);
        end else begin
            // four MRS, then ZQCL
            if (c_cmd[0][3:0] !== 4'b0000 || c_ba[0] !== 3'd2 || c_addr[0] !== 16'h0000)
                fail("the first command is not MR2 = 0");
            if (c_cmd[1][3:0] !== 4'b0000 || c_ba[1] !== 3'd3 || c_addr[1] !== 16'h0000)
                fail("the second command is not MR3 = 0");
            if (c_cmd[2][3:0] !== 4'b0000 || c_ba[2] !== 3'd1 || c_addr[2] !== 16'h0044)
                fail("the third command is not MR1 = 0x0044");
            if (c_cmd[3][3:0] !== 4'b0000 || c_ba[3] !== 3'd0 || c_addr[3] !== 16'h0520)
                fail("the fourth command is not MR0 = 0x0520");
            // ZQCL: CS# low, RAS# high, CAS# high, WE# low -> {ras,cas,we,cs}
            if (c_cmd[4][3:0] !== 4'b1100 || c_addr[4] !== 16'h0400)
                fail("the fifth command is not ZQCL with A10 high");
        end
        if (init_done !== 1'b1)
            fail("init_done was not raised after ZQCL");

        if (errors == 0)
            $display("PASS  RESET#, CKE, MR2/MR3/MR1/MR0 and ZQCL in the proven order");
        else
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end
endmodule

`default_nettype wire
