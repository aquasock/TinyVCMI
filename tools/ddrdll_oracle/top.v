`default_nettype none

module top (
    input  wire clk,
    input  wire reset,
    input  wire stop,
    input  wire updn,
    output wire lock,
    output wire step_xor
);
    wire [7:0] step;

    DDRDLL #(
        .DLL_FORCE("FALSE"),
        .CODESCAL("111"),
        .SCAL_EN("FALSE"),
        .DIV_SEL(1'b0)
    ) dll (
        .CLKIN(clk),
        .STOP(stop),
        .UPDNCNTL(updn),
        .RESET(reset),
        .STEP(step),
        .LOCK(lock)
    );

    assign step_xor = ^step;
endmodule

`default_nettype wire
