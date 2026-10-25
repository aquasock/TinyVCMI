`default_nettype none

// PHY start-up, as the hardware-proven controller runs it.
//
// The order is TOOL-019, traced from the vendor netlist by
// tools/vendor_memsync_trace.py and then proven on the board: hold the DLL in
// reset until the PLL is locked and 16384 board clocks have passed, release
// it, wait for LOCK, settle 16384 clocks more, then update the delay line
// under HOLD (UPDNCNTL low for four clocks), stop the memory clock through the
// PLL's output enable, pulse the CLKDIV and lane reset while it is stopped,
// restart it, and only then declare the PHY ready.
//
// Additive like ddr3_init: the diagnostic core keeps its own copy of this
// sequence, and folding the two together is a separate, gated change.
module ddr3_sync #(
    parameter integer LOCK_WAIT   = 16384,   // board clocks after PLL lock
    parameter integer SETTLE_WAIT = 16384    // board clocks after DLL LOCK
) (
    input  wire sys_clk,
    input  wire por_n,        // board power-on reset, active low
    input  wire pll_ok,       // PLL locked
    input  wire lock_ok,      // DDRDLL LOCK

    output reg  dll_rst = 1'b1,
    output reg  updncntl = 1'b1,
    output reg  hold = 1'b0,
    output reg  pll_en = 1'b1,   // the PLL's output enable
    output reg  sync_rst = 1'b0, // CLKDIV and lane reset
    output reg  ready = 1'b0
);
    localparam [2:0] M_PLL = 3'd0, M_DLL = 3'd1, M_SETTLE = 3'd2,
                     M_UPDATE = 3'd3, M_SYNC = 3'd4, M_READY = 3'd5;

    reg [2:0]  mstate = M_PLL;
    reg [15:0] mtimer = 16'd0;

    always @(posedge sys_clk) begin
        if (!por_n) begin
            dll_rst <= 1'b1;
            updncntl <= 1'b1;
            hold <= 1'b0;
            pll_en <= 1'b1;
            sync_rst <= 1'b0;
            ready <= 1'b0;
            mstate <= M_PLL;
            mtimer <= 16'd0;
        end else begin
            mtimer <= mtimer + 16'd1;
            case (mstate)
                // PLL locked and the wait elapsed: release the DLL
                M_PLL: begin
                    dll_rst <= 1'b1;
                    if (!pll_ok)
                        mtimer <= 16'd0;
                    else if (mtimer == LOCK_WAIT - 1) begin
                        dll_rst <= 1'b0;
                        mstate <= M_DLL;
                        mtimer <= 16'd0;
                    end
                end
                // wait for the delay line to lock
                M_DLL: begin
                    dll_rst <= 1'b0;
                    mtimer <= 16'd0;
                    if (!pll_ok)
                        mstate <= M_PLL;
                    else if (lock_ok)
                        mstate <= M_SETTLE;
                end
                // and let it settle before touching it
                M_SETTLE: begin
                    dll_rst <= 1'b0;
                    if (!pll_ok || !lock_ok)
                        mstate <= M_PLL;
                    else if (mtimer == SETTLE_WAIT - 1) begin
                        mstate <= M_UPDATE;
                        mtimer <= 16'd0;
                    end
                end
                // HOLD, then one UPDNCNTL pulse, then release
                M_UPDATE: begin
                    if (mtimer == 16'd0)  hold <= 1'b1;
                    if (mtimer == 16'd4)  updncntl <= 1'b0;
                    if (mtimer == 16'd8)  updncntl <= 1'b1;
                    if (mtimer == 16'd12) begin
                        hold <= 1'b0;
                        mstate <= M_SYNC;
                        mtimer <= 16'd0;
                    end
                end
                // stop the memory clock, reset the divider and the lanes with
                // it stopped, restart, then ready
                M_SYNC: begin
                    if (mtimer == 16'd15) pll_en <= 1'b0;
                    if (mtimer == 16'd16) sync_rst <= 1'b1;
                    if (mtimer == 16'd20) sync_rst <= 1'b0;
                    if (mtimer == 16'd27) pll_en <= 1'b1;
                    if (mtimer == 16'd36) begin
                        ready <= 1'b1;
                        mstate <= M_READY;
                    end
                end
                default: ;
            endcase
        end
    end
endmodule

`default_nettype wire
