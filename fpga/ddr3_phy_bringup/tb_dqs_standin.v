`timescale 1ns / 1ps

// Stand-in for the DQS primitive, for simulation only.
//
// Gowin EDA 1.9.11.03's model of DQS (IDE/simlib/gw5a/prim_sim.v) is an empty
// module: ports and parameters, no behaviour, so every output is Z and a
// serializer clocked from it never leaves X.  tools/sim_ddr3_phy_bringup.sh
// therefore removes that stub from a copy of the library and compiles this
// in its place.  It is not a model of the silicon: it gives each serializer a
// running TCLK -- DQSW0 is FCLK, DQSW270 is FCLK three quarters of a period
// later, DQSR90 is DQSIN a quarter period later -- holds the pointers and
// status outputs at 0, and drives nothing at all while RESET is high.
module DQS(DQSR90, DQSW0, DQSW270, RPOINT, WPOINT, RVALID, RBURST, RFLAG, WFLAG, DQSIN,
           DLLSTEP, WSTEP, READ, RLOADN, RMOVE, RDIR, WLOADN, WMOVE, WDIR, HOLD, RCLKSEL,
           PCLK, FCLK, RESET);
input DQSIN, PCLK, FCLK, RESET;
input [3:0] READ;
input [2:0] RCLKSEL;
input [7:0] DLLSTEP;
input [7:0] WSTEP;
input RLOADN, RMOVE, RDIR, WLOADN, WMOVE, WDIR, HOLD;
output DQSR90, DQSW0, DQSW270;
output [2:0] RPOINT, WPOINT;
output RVALID, RBURST, RFLAG, WFLAG;

parameter FIFO_MODE_SEL = 1'b0;
parameter RD_PNTR = 3'b000;
parameter DQS_MODE = "X1";
parameter HWL = "false";

// transport delays: an inertial `assign #` would swallow the 1.25 ns phases
reg fclk_270 = 1'b0, dqsin_90 = 1'b0;
always @(FCLK) fclk_270 <= #1.875 FCLK;
always @(DQSIN) dqsin_90 <= #0.625 DQSIN;

assign DQSW0 = RESET ? 1'b0 : FCLK;
assign DQSW270 = RESET ? 1'b0 : fclk_270;
assign DQSR90 = RESET ? 1'b0 : dqsin_90;
assign RPOINT = 3'b000;
assign WPOINT = 3'b000;
assign {RVALID, RBURST, RFLAG, WFLAG} = 4'b0000;

endmodule
