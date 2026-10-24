`default_nettype none

// Primitive probes for offline toolchain characterization.  The DQS and
// serializer probes are constrained onto lane 0's DDR3 pins, Y3 and Y4, in
// constraint files of their own, because a DQS takes DQSIN only from its
// lane's pad (Gowin PR0014) and a serializer's memory-mode pins only from its
// lane's DQS (CK2060).  The preflight never packs an image, so nothing reaches
// the board.

// The DDRDLL probe drives its result from `STEP` and `LOCK`.  `LOCK` leaves
// the primitive on a dedicated path that reaches the fabric on `Q7` of cell
// (99,1) with no configurable bit in between; the chip database models that
// as a fuse-free node, so routing `LOCK` here tests the link.
module probe_ddrdll (
    input  wire sys_clk,
    input  wire probe_in,
    output wire probe_out
);
    wire [7:0] step;
    wire lock;

    DDRDLL #(
        .DLL_FORCE("FALSE"),
        .CODESCAL("111"),
        .SCAL_EN("FALSE"),
        .DIV_SEL(1'b0)
    ) ddrdll (
        .CLKIN(sys_clk),
        .STOP(1'b0),
        .UPDNCNTL(1'b1),
        .RESET(1'b0),
        .STEP(step),
        .LOCK(lock)
    );

    assign probe_out = ^step ^ lock;
endmodule

module probe_dqs (
    input  wire sys_clk,
    input  wire probe_in,
    output wire probe_out
);
    wire [2:0] rpoint;
    wire [2:0] wpoint;
    wire dqsr90;
    wire dqsw0;
    wire dqsw270;
    wire rvalid;
    wire rburst;
    wire rflag;
    wire wflag;
    wire [7:0] step;

    // A DQS does not build without a DDRDLL on DLLSTEP (Gowin PR0015), so the
    // probe is the smallest lane the vendor tool accepts.
    DDRDLL #(
        .DLL_FORCE("FALSE"),
        .CODESCAL("111"),
        .SCAL_EN("FALSE"),
        .DIV_SEL(1'b0)
    ) ddrdll (
        .CLKIN(sys_clk),
        .STOP(1'b1),
        .UPDNCNTL(1'b1),
        .RESET(1'b0),
        .STEP(step)
    );

    DQS #(
        .FIFO_MODE_SEL(1'b0),
        .RD_PNTR(3'b000),
        .DQS_MODE("X1"),
        .HWL("false")
    ) dqs (
        .DQSIN(probe_in),
        .PCLK(sys_clk),
        .FCLK(sys_clk),
        .RESET(1'b0),
        .READ(4'b0000),
        .RCLKSEL(3'b000),
        .DLLSTEP(step),
        .WSTEP(8'h00),
        .RLOADN(1'b1),
        .RMOVE(1'b0),
        .RDIR(1'b0),
        .WLOADN(1'b1),
        .WMOVE(1'b0),
        .WDIR(1'b0),
        .HOLD(1'b0),
        .DQSR90(dqsr90),
        .DQSW0(dqsw0),
        .DQSW270(dqsw270),
        .RPOINT(rpoint),
        .WPOINT(wpoint),
        .RVALID(rvalid),
        .RBURST(rburst),
        .RFLAG(rflag),
        .WFLAG(wflag)
    );

    assign probe_out = dqsr90 ^ dqsw0 ^ dqsw270 ^ rvalid ^ rburst ^ rflag ^
                       wflag ^ ^rpoint ^ ^wpoint;
endmodule

// The serializer probes are lane 0 as the proven controller wires it: a
// DDRDLL on DLLSTEP, the DQS on Y3, and the serializer on dq[0], Y4.  Its
// TCLK, ICLK, WADDR and RADDR take only their DQS outputs (Gowin CK2060), so
// an isolated serializer is not a shape either toolchain should accept.
module probe_oser8_mem (
    input  wire sys_clk,
    input  wire probe_in,
    output wire probe_out
);
    wire [7:0] step;
    wire [2:0] rpoint;
    wire [2:0] wpoint;
    wire dqsr90, dqsw0, dqsw270, rvalid, rburst, rflag, wflag;

    DDRDLL #(
        .DLL_FORCE("FALSE"), .CODESCAL("111"), .SCAL_EN("FALSE"), .DIV_SEL(1'b0)
    ) ddrdll (
        .CLKIN(sys_clk), .STOP(1'b1), .UPDNCNTL(1'b1), .RESET(1'b0), .STEP(step)
    );

    DQS #(
        .FIFO_MODE_SEL(1'b0), .RD_PNTR(3'b000), .DQS_MODE("X4"), .HWL("true")
    ) dqs (
        .DQSIN(probe_in), .PCLK(sys_clk), .FCLK(sys_clk), .RESET(1'b0),
        .READ(4'b0000), .RCLKSEL(3'b000), .DLLSTEP(step), .WSTEP(8'h00),
        .RLOADN(1'b1), .RMOVE(1'b0), .RDIR(1'b0),
        .WLOADN(1'b1), .WMOVE(1'b0), .WDIR(1'b0), .HOLD(1'b0),
        .DQSR90(dqsr90), .DQSW0(dqsw0), .DQSW270(dqsw270),
        .RPOINT(rpoint), .WPOINT(wpoint),
        .RVALID(rvalid), .RBURST(rburst), .RFLAG(rflag), .WFLAG(wflag)
    );

    wire q1_unused;

    OSER8_MEM #(
        .HWL("false"),
        .TCLK_SOURCE("DQSW"),
        .TXCLK_POL(1'b0)
    ) oser (
        .D0(dqsr90 ^ rvalid), .D1(1'b0), .D2(1'b1), .D3(1'b0),
        .D4(1'b1), .D5(rburst ^ rflag), .D6(1'b1), .D7(wflag ^ dqsw270),
        .TX0(1'b0), .TX1(1'b0), .TX2(1'b0), .TX3(1'b0),
        .PCLK(sys_clk), .FCLK(sys_clk), .TCLK(dqsw0), .RESET(1'b0),
        .Q0(probe_out), .Q1(q1_unused)
    );
endmodule

module probe_ides8_mem (
    input  wire sys_clk,
    input  wire probe_in,
    input  wire dq_in,
    output wire probe_out
);
    wire [7:0] step;
    wire [2:0] rpoint;
    wire [2:0] wpoint;
    wire dqsr90, dqsw0, dqsw270, rvalid, rburst, rflag, wflag;

    DDRDLL #(
        .DLL_FORCE("FALSE"), .CODESCAL("111"), .SCAL_EN("FALSE"), .DIV_SEL(1'b0)
    ) ddrdll (
        .CLKIN(sys_clk), .STOP(1'b1), .UPDNCNTL(1'b1), .RESET(1'b0), .STEP(step)
    );

    DQS #(
        .FIFO_MODE_SEL(1'b0), .RD_PNTR(3'b000), .DQS_MODE("X4"), .HWL("true")
    ) dqs (
        .DQSIN(probe_in), .PCLK(sys_clk), .FCLK(sys_clk), .RESET(1'b0),
        .READ(4'b0000), .RCLKSEL(3'b000), .DLLSTEP(step), .WSTEP(8'h00),
        .RLOADN(1'b1), .RMOVE(1'b0), .RDIR(1'b0),
        .WLOADN(1'b1), .WMOVE(1'b0), .WDIR(1'b0), .HOLD(1'b0),
        .DQSR90(dqsr90), .DQSW0(dqsw0), .DQSW270(dqsw270),
        .RPOINT(rpoint), .WPOINT(wpoint),
        .RVALID(rvalid), .RBURST(rburst), .RFLAG(rflag), .WFLAG(wflag)
    );

    wire [7:0] q;

    IDES8_MEM ides (
        .PCLK(sys_clk), .D(dq_in), .ICLK(dqsr90), .FCLK(sys_clk),
        .RESET(1'b0), .CALIB(1'b0), .WADDR(wpoint), .RADDR(rpoint),
        .Q0(q[0]), .Q1(q[1]), .Q2(q[2]), .Q3(q[3]),
        .Q4(q[4]), .Q5(q[5]), .Q6(q[6]), .Q7(q[7])
    );

    assign probe_out = ^q ^ dqsw0 ^ dqsw270 ^ rvalid ^ rburst ^ rflag ^ wflag;
endmodule

module probe_iodelay (
    input  wire sys_clk,
    input  wire probe_in,
    output wire probe_out
);
    wire df_unused;

    IODELAY #(
        .C_STATIC_DLY(8'd128),
        .DYN_DLY_EN("FALSE"),
        .ADAPT_EN("FALSE")
    ) iodelay (
        .DI(probe_in),
        .SDTAP(1'b0),
        .VALUE(1'b0),
        .DLYSTEP(8'h00),
        .DF(df_unused),
        .DO(probe_out)
    );
endmodule

module probe_clkdiv (
    input  wire sys_clk,
    input  wire probe_in,
    output wire probe_out
);
    CLKDIV #(.DIV_MODE("4")) clkdiv (
        .HCLKIN(sys_clk),
        .RESETN(1'b1),
        .CALIB(1'b0),
        .CLKOUT(probe_out)
    );
endmodule

`default_nettype wire
