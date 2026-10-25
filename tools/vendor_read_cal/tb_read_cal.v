`timescale 1ns/1ps
// Bench for tools/vendor_read_cal_trace.py: the proven DDR3 controller's
// u_ddr_init block, cut out of Tang-PSX's post-route netlist as module `cut`,
// simulated with Gowin's primitive models.  The model answers every READ the
// block issues LAT PCLK later with RVALID high for RVW cycles and RBURST high
// for RBW cycles on all four lanes, but only while lane 0's RCLKSEL is in
// [SELLO, SELHI] and its read_i in [RILO, RIHI]; during write leveling each
// lane's DQ0 reads 1 once its WSTEP reaches 64.  The other modules the block
// waits on (init_rmove, eye_calib) answer done 200 PCLK after their start.
module tb;
  reg clk=0, rst=1, st=0; always #5 clk=~clk;
  integer LAT, RVW, RBW, NRB, SELLO, SELHI, RILO, RIHI;
  GSR GSR(.GSRI(1'b1));
  reg [3:0] rv=0, rb=0, dq0=4'h0; reg rmdone=0, eyedone=0; reg rl1=0, rl2=0, rl3=0;
  wire cs3, ras3, cas3, we3, rmstart, eyestart, initdone, wrlvl_done, wrlvl_start;
  cut dut(
    .n_clk_out(clk), .n_ddr_rst(rst), .n_ddr_init_st_Z(st),
    .n_RBURST__0(rb[0]), .n_RBURST_0__1(rb[1]), .n_RBURST_1__2(rb[2]), .n_RBURST_2__3(rb[3]),
    .n_rvalid_Z__0(rv[0]), .n_rvalid_Z_0__1(rv[1]), .n_rvalid_Z_1__2(rv[2]), .n_rvalid_Z_2__3(rv[3]),
    .n_phy_rdbk_data_valid__0(rv[0]), .n_phy_rdbk_data_valid__1(rv[1]),
    .n_phy_rdbk_data_valid__2(rv[2]), .n_phy_rdbk_data_valid__3(rv[3]),
    .n_in_dq0_Z__0(dq0[0]), .n_in_dq0_Z__1(dq0[1]), .n_in_dq0_Z__2(dq0[2]), .n_in_dq0_Z__3(dq0[3]),
    .n_init_rmove_done_r(rmdone), .n_eye_calib_done_r(eyedone),
    .n_read_line1(rl1), .n_read_line2(rl2), .n_read_line3(rl3),
    .n_phy_cs_n__3(cs3), .n_phy_ras_n__3(ras3), .n_phy_cas_n__3(cas3), .n_phy_we_n__3(we3),
    .n_init_rmove_start_Z(rmstart), .n_eye_calib_start_Z(eyestart), .n_ddr_init_internal(initdone),
    .n_wrlvl_complete_Z(wrlvl_done), .n_wrlvl_start(wrlvl_start));
  // eye_calib_rdata tied low by default (unconnected inputs float; tie them)
  wire rd = (cs3===1'b0) && (ras3===1'b1) && (cas3===1'b0) && (we3===1'b1);
  reg [63:0] rdp = 0;
  integer cyc=0, nrd=0, l;
  always @(posedge clk) begin
    cyc <= cyc+1;
    rdp <= {rdp[62:0], rd};
    rl1 <= rdp[2]; rl2 <= rl1; rl3 <= rl2;
    for (l=0;l<4;l=l+1) begin
      rv[l] <= 1'b0; rb[l] <= 1'b0;
    end
    // responses: any READ LAT..LAT+W-1 cycles ago
    begin : resp
      integer k;
      for (k=0;k<RVW;k=k+1) if (rdp[LAT-1+k] && ok) rv <= 4'hf;
      for (k=0;k<RBW;k=k+1) if (rdp[LAT-1+k] && ok) rb <= 4'hf;
    end
    if (rd) nrd <= nrd+1;
  end
  reg [31:0] rmc=0, eyc=0;
  always @(posedge clk) begin
    rmc <= rmstart ? rmc+1 : 0; if (rmc==200) rmdone<=1; if (!rmstart) rmdone<=0;
    eyc <= eyestart ? eyc+1 : 0; if (eyc==200) eyedone<=1; if (!eyestart) eyedone<=0;
  end
  wire [16:0] rcs = {dut.n_u_ddr_init_read_cal_state__16, dut.n_u_ddr_init_read_cal_state__15,
    dut.n_u_ddr_init_read_cal_state__14, dut.n_u_ddr_init_read_cal_state__13, dut.n_u_ddr_init_read_cal_state__12,
    dut.n_u_ddr_init_read_cal_state__11, dut.n_u_ddr_init_read_cal_state__10, dut.n_u_ddr_init_read_cal_state__9,
    dut.n_u_ddr_init_read_cal_state__8, dut.n_u_ddr_init_read_cal_state__7, dut.n_u_ddr_init_read_cal_state__6,
    dut.n_u_ddr_init_read_cal_state__5, dut.n_u_ddr_init_read_cal_state__4, dut.n_u_ddr_init_read_cal_state__3,
    dut.n_u_ddr_init_read_cal_state__2, dut.n_u_ddr_init_read_cal_state__1, dut.n_u_ddr_init_read_cal_state__0};
  wire [19:0] ist = {dut.n_u_ddr_init_init_state__19, dut.n_u_ddr_init_init_state__18, dut.n_u_ddr_init_init_state__17,
    dut.n_u_ddr_init_init_state__16, dut.n_u_ddr_init_init_state__15, dut.n_u_ddr_init_init_state__14,
    dut.n_u_ddr_init_init_state__13, dut.n_u_ddr_init_init_state__12, dut.n_u_ddr_init_init_state__11,
    dut.n_u_ddr_init_init_state__10, dut.n_u_ddr_init_init_state__9, dut.n_u_ddr_init_init_state__8,
    dut.n_u_ddr_init_init_state__7, dut.n_u_ddr_init_init_state__6, dut.n_u_ddr_init_init_state__5,
    dut.n_u_ddr_init_init_state__4, dut.n_u_ddr_init_init_state__3, dut.n_u_ddr_init_init_state__2,
    dut.n_u_ddr_init_init_state__1, dut.n_u_ddr_init_init_state__0};
  wire [7:0] rcc = {dut.n_u_ddr_init_read_cmd_cnt__7, dut.n_u_ddr_init_read_cmd_cnt__6, dut.n_u_ddr_init_read_cmd_cnt__5,
    dut.n_u_ddr_init_read_cmd_cnt__4, dut.n_u_ddr_init_read_cmd_cnt__3, dut.n_u_ddr_init_read_cmd_cnt__2,
    dut.n_u_ddr_init_read_cmd_cnt__1, dut.n_u_ddr_init_read_cmd_cnt__0};
  wire [9:0] rvc = {dut.n_u_ddr_init_rvalid_cnt__9, dut.n_u_ddr_init_rvalid_cnt__8, dut.n_u_ddr_init_rvalid_cnt__7,
    dut.n_u_ddr_init_rvalid_cnt__6, dut.n_u_ddr_init_rvalid_cnt__5, dut.n_u_ddr_init_rvalid_cnt__4,
    dut.n_u_ddr_init_rvalid_cnt__3, dut.n_u_ddr_init_rvalid_cnt__2, dut.n_u_ddr_init_rvalid_cnt__1, dut.n_u_ddr_init_rvalid_cnt__0};
  wire [9:0] rbc = {dut.n_u_ddr_init_rburst_cnt__9, dut.n_u_ddr_init_rburst_cnt__8, dut.n_u_ddr_init_rburst_cnt__7,
    dut.n_u_ddr_init_rburst_cnt__6, dut.n_u_ddr_init_rburst_cnt__5, dut.n_u_ddr_init_rburst_cnt__4,
    dut.n_u_ddr_init_rburst_cnt__3, dut.n_u_ddr_init_rburst_cnt__2, dut.n_u_ddr_init_rburst_cnt__1, dut.n_u_ddr_init_rburst_cnt__0};
  wire ok = (sel0 >= SELLO) && (sel0 <= SELHI) && (ri0 >= RILO) && (ri0 <= RIHI);
  wire [2:0] sel0 = {dut.n_rclk_sel__2, dut.n_rclk_sel__1, dut.n_rclk_sel__0};
  wire [3:0] ri0 = {dut.n_u_ddr_init_read_calibration_logic_gen_0__read_i__3, dut.n_u_ddr_init_read_calibration_logic_gen_0__read_i__2,
    dut.n_u_ddr_init_read_calibration_logic_gen_0__read_i__1, dut.n_u_ddr_init_read_calibration_logic_gen_0__read_i__0};
  wire [3:0] gate0 = {dut.n_read__3, dut.n_read__2, dut.n_read__1, dut.n_read__0};
  wire chk = dut.n_u_ddr_init_rvalid_cnt_check__0, bchk = dut.n_u_ddr_init_rburst_cnt_check__0;
  wire [7:0] ws0 = {dut.n_u_ddr_init_wstep_reg__7, dut.n_u_ddr_init_wstep_reg__6, dut.n_u_ddr_init_wstep_reg__5, dut.n_u_ddr_init_wstep_reg__4, dut.n_u_ddr_init_wstep_reg__3, dut.n_u_ddr_init_wstep_reg__2, dut.n_u_ddr_init_wstep_reg__1, dut.n_u_ddr_init_wstep_reg__0};
  wire [7:0] ws1 = {dut.n_u_ddr_init_wstep_reg__15, dut.n_u_ddr_init_wstep_reg__14, dut.n_u_ddr_init_wstep_reg__13, dut.n_u_ddr_init_wstep_reg__12, dut.n_u_ddr_init_wstep_reg__11, dut.n_u_ddr_init_wstep_reg__10, dut.n_u_ddr_init_wstep_reg__9, dut.n_u_ddr_init_wstep_reg__8};
  wire [7:0] ws2 = {dut.n_u_ddr_init_wstep_reg__23, dut.n_u_ddr_init_wstep_reg__22, dut.n_u_ddr_init_wstep_reg__21, dut.n_u_ddr_init_wstep_reg__20, dut.n_u_ddr_init_wstep_reg__19, dut.n_u_ddr_init_wstep_reg__18, dut.n_u_ddr_init_wstep_reg__17, dut.n_u_ddr_init_wstep_reg__16};
  wire [7:0] ws3 = {dut.n_u_ddr_init_wstep_reg__31, dut.n_u_ddr_init_wstep_reg__30, dut.n_u_ddr_init_wstep_reg__29, dut.n_u_ddr_init_wstep_reg__28, dut.n_u_ddr_init_wstep_reg__27, dut.n_u_ddr_init_wstep_reg__26, dut.n_u_ddr_init_wstep_reg__25, dut.n_u_ddr_init_wstep_reg__24};
  always @* dq0 = {ws3 >= 8'd64, ws2 >= 8'd64, ws1 >= 8'd64, ws0 >= 8'd64};
  wire [11:0] wls = {dut.n_u_ddr_init_wrlvl_state__11, dut.n_u_ddr_init_wrlvl_state__10, dut.n_u_ddr_init_wrlvl_state__9, dut.n_u_ddr_init_wrlvl_state__8, dut.n_u_ddr_init_wrlvl_state__7, dut.n_u_ddr_init_wrlvl_state__6, dut.n_u_ddr_init_wrlvl_state__5, dut.n_u_ddr_init_wrlvl_state__4, dut.n_u_ddr_init_wrlvl_state__3, dut.n_u_ddr_init_wrlvl_state__2, dut.n_u_ddr_init_wrlvl_state__1, dut.n_u_ddr_init_wrlvl_state__0};
  always @(wls) $display("%0d   wrlvl_state %b ws %0d %0d %0d %0d dq0 %b", cyc, wls, ws0, ws1, ws2, ws3, dq0);
  always @(ist) $display("%0d init_state %b", cyc, ist);
  always @(rcs) $display("%0d   read_cal_state %b  rcmd %0d rvc %0d rbc %0d sel0 %0d ri0 %0d chk %b%b nrd %0d", cyc, rcs, rcc, rvc, rbc, sel0, ri0, chk, bchk, nrd);
  always @(posedge clk) if (rd && rcs != 0 && nrd < 140) $display("%0d     READ #%0d  gate0 %b", cyc, nrd, gate0);
  always @(sel0 or ri0) $display("%0d   sel0 %0d ri0 %0d", cyc, sel0, ri0);
  always @(posedge initdone) begin $display("%0d INIT DONE  sel0 %0d ri0 %0d", cyc, sel0, ri0); #2000 $finish; end
  always @(posedge wrlvl_done) $display("%0d write leveling complete", cyc);
  initial begin
    if (!$value$plusargs("LAT=%d", LAT)) LAT=8;
    if (!$value$plusargs("RVW=%d", RVW)) RVW=1;
    if (!$value$plusargs("RBW=%d", RBW)) RBW=1;
    if (!$value$plusargs("SELLO=%d", SELLO)) SELLO=0;
    if (!$value$plusargs("SELHI=%d", SELHI)) SELHI=7;
    if (!$value$plusargs("RILO=%d", RILO)) RILO=0;
    if (!$value$plusargs("RIHI=%d", RIHI)) RIHI=15;
    #100 rst=0; #1000 st=1;
    #8000000 $display("TIMEOUT"); $finish;
  end
endmodule
