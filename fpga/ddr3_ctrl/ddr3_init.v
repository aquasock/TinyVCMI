`default_nettype none

// DDR3 power-up, as the hardware-proven controller runs it.
//
// Order and counts come from TOOL-019, which was traced out of the vendor
// netlist by tools/vendor_memsync_trace.py: once the PHY reports ready,
// RESET# is released 200 us later, CKE follows 500 us after that, then MR2,
// MR3, MR1 and MR0 are written in that order with a tMRD gap between them,
// and ZQCL starts a 256-clock calibration before the controller may use the
// device.  The values are the DDR3-800 set the proven controller uses
// (MR0 0x0520 with CL6 and BL8, MR1 0x0044, MR2 and MR3 clear).
//
// This module is deliberately additive: it is the controller's own init, and
// it does not touch the diagnostic core in fpga/ddr3_write.  That core still
// carries its copy of the same sequence, and folding the two together is a
// separate change with its own gate -- the requirement being that the
// diagnostic image still equals its vendor build on all 306 DDR3 tables
// afterwards.
module ddr3_init #(
    parameter integer T_IDLE   = 16,      // PCLK after the PHY reports ready
    parameter integer T_RESET  = 20000,   // 200 us before RESET# releases
    parameter integer T_CKE    = 50000,   // 500 us before CKE rises
    parameter integer T_MR     = 32,      // tMRD before the first MRS
    parameter integer T_MR_GAP = 8,       // tMRD between MRS writes
    parameter integer T_ZQ     = 256      // ZQCL calibration
) (
    input  wire        pclk,
    input  wire        phy_ready,     // PHY sync done: PLL, DLL and clock stop

    output reg         cs_n,
    output reg         ras_n,
    output reg         cas_n,
    output reg         we_n,
    output reg  [2:0]  ba,
    output reg  [15:0] addr,
    output reg         ddr_reset_n,
    output reg         cke,
    output reg         odt,
    output reg         init_done
);
    localparam [3:0] C_MRS = 4'b0000, C_ZQ = 4'b0110;
    localparam [3:0] I_IDLE = 4'd0, I_RESET = 4'd1, I_CKE = 4'd2,
                     I_MR = 4'd3, I_ZQ = 4'd4, I_DONE = 4'd5;

    reg [3:0]  state = I_IDLE;
    reg [31:0] timer = 32'd0;
    reg [1:0]  mr_idx = 2'd0;

    // MR2, MR3, MR1, MR0, in issue order: {BA, A}
    function [18:0] mr_word;
        input [1:0] i;
        begin
            case (i)
                2'd0: mr_word = {3'd2, 16'h0000};
                2'd1: mr_word = {3'd3, 16'h0000};
                2'd2: mr_word = {3'd1, 16'h0044};
                default: mr_word = {3'd0, 16'h0520};
            endcase
        end
    endfunction

    // deselect every cycle; a command is one cycle wide
    task deselect;
        begin
            cs_n <= 1'b1; ras_n <= 1'b1; cas_n <= 1'b1; we_n <= 1'b1;
        end
    endtask

    always @(posedge pclk) begin
        deselect;
        timer <= timer + 32'd1;

        if (!phy_ready) begin
            state <= I_IDLE;
            timer <= 32'd0;
            ddr_reset_n <= 1'b0;
            cke <= 1'b0;
            odt <= 1'b0;
            init_done <= 1'b0;
        end else begin
            case (state)
                I_IDLE: if (timer == T_IDLE) begin
                    state <= I_RESET;
                    timer <= 32'd0;
                end
                I_RESET: if (timer == T_RESET) begin
                    ddr_reset_n <= 1'b1;            // RESET# released
                    state <= I_CKE;
                    timer <= 32'd0;
                end
                I_CKE: if (timer == T_CKE) begin
                    cke <= 1'b1;
                    mr_idx <= 2'd0;
                    state <= I_MR;
                    timer <= 32'd0;
                end
                I_MR: if (timer == (mr_idx == 2'd0 ? T_MR : T_MR_GAP)) begin
                    {ba, addr} <= mr_word(mr_idx);
                    {cs_n, ras_n, cas_n, we_n} <= C_MRS;
                    mr_idx <= mr_idx + 2'd1;
                    timer <= 32'd0;
                    if (mr_idx == 2'd3)
                        state <= I_ZQ;
                end
                I_ZQ: begin
                    if (timer == 32'd0) begin
                        {cs_n, ras_n, cas_n, we_n} <= C_ZQ;
                        ba  <= 3'd0;
                        addr <= 16'h0400;           // A10 high: ZQCL
                    end else if (timer == T_ZQ) begin
                        state <= I_DONE;
                        init_done <= 1'b1;
                    end
                end
                default: init_done <= 1'b1;
            endcase
        end
    end
endmodule

`default_nettype wire
