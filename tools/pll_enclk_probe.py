#!/usr/bin/env python3
"""Locate the GW5AST-138C PLL's ENCLK inputs, which the open flow does not model.

The hardware-proven DDR3 controller stops its 400 MHz memory clock while it
resets the CLKDIV and the lanes, so the divided clock and every serializer's
gearbox come up in phase: the vendor IP's `pll_stop` drives `ENCLK2` of
`Gowin_PLL_MOD`, high to run.  Apicula records the PLL's dynamic ports as a
gap (`apycula/chipdb.py`, `_gw5a_pll_slots`), so neither fork can route a
signal to `ENCLK`.

Each design is one PLL on `PLL_L[0]`, 50 MHz x16 / 2 = 400 MHz on the
measured output, driving a `CLKDIV` at `LEFTSIDE[4]` as the PHY does, with
that output's `ENCLK` either tied high or driven by a register.  A matched
pair differs only in the enable, so `tools/fs_site_diff.py` on the pair
shows the port wire's pip and any configuration the enable moves.

Usage:
    tools/pll_enclk_probe.py            # build every design with Gowin EDA
"""

import argparse
import os
import shutil
import sys

import dqs_port_probe as base

OUT = os.path.join(base.ROOT, "build/pll_enclk")

#: name -> (output n, ENCLKn source)
DESIGNS = {
    "out0_const": (0, "1'b1"),
    "out0_sig": (0, "en"),
    "out2_const": (2, "1'b1"),
    "out2_sig": (2, "en"),
}

TOP = """\
module top (input wire clk, input wire en_in, output wire q);
    reg en = 1'b0;
    always @(posedge clk) en <= en_in;
    wire mclk, lock;
    PLL #(
        .FCLKIN("50"), .IDIV_SEL(1), .FBDIV_SEL(1), .MDIV_SEL(16),
        .ODIV@N@_SEL(2), .CLKOUT@N@_EN("TRUE")
    ) pll (
        .CLKIN(clk), .CLKFB(1'b0), .RESET(1'b0), .PLLPWD(1'b0),
        .RESET_I(1'b0), .RESET_O(1'b0),
        .FBDSEL(6'b0), .IDSEL(6'b0), .MDSEL(7'b0), .MDSEL_FRAC(3'b0),
        .ODSEL0(7'b0), .ODSEL0_FRAC(3'b0), .ODSEL1(7'b0), .ODSEL2(7'b0),
        .ODSEL3(7'b0), .ODSEL4(7'b0), .ODSEL5(7'b0), .ODSEL6(7'b0),
        .DT0(4'b0), .DT1(4'b0), .DT2(4'b0), .DT3(4'b0),
        .ICPSEL(6'b0), .LPFRES(3'b0), .LPFCAP(2'b0),
        .PSSEL(3'b0), .PSDIR(1'b0), .PSPULSE(1'b0),
@ENCLK@
        .SSCPOL(1'b0), .SSCON(1'b0), .SSCMDSEL(7'b0), .SSCMDSEL_FRAC(3'b0),
        .LOCK(lock), .CLKOUT@N@(mclk));
    wire pclk;
    CLKDIV #(.DIV_MODE("4")) fdiv (.HCLKIN(mclk), .RESETN(1'b1), .CALIB(1'b0), .CLKOUT(pclk));
    reg [7:0] cnt = 8'd0;
    always @(posedge pclk) cnt <= cnt + 8'd1;
    assign q = ^cnt ^ lock;
endmodule
"""

CST = """\
IO_LOC "clk" V22;
IO_PORT "clk" IO_TYPE=LVCMOS33 PULL_MODE=NONE;
IO_LOC "en_in" V14;
IO_PORT "en_in" IO_TYPE=LVCMOS33 PULL_MODE=UP;
IO_LOC "q" F18;
IO_PORT "q" IO_TYPE=LVCMOS33 PULL_MODE=NONE;
INS_LOC "pll" PLL_L[0];
INS_LOC "fdiv" LEFTSIDE[4];
"""

SDC = """\
create_clock -name clk -period 20.000 [get_ports {clk}]
create_clock -name mclk -period 2.500 [get_nets {mclk}]
"""


def render(n: int, src: str) -> str:
    zero = "1'b0"
    enclk = "\n".join(f"        .ENCLK{i}({src if i == n else zero})," for i in range(7))
    return TOP.replace("@N@", str(n)).replace("@ENCLK@", enclk)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", help="comma-separated subset of " + ",".join(DESIGNS))
    args = ap.parse_args()
    names = [n for n in (args.only or ",".join(DESIGNS)).split(",") if n]
    bad = 0
    for name in names:
        n, src = DESIGNS[name]
        d = os.path.join(OUT, name)
        if os.path.isdir(d):
            shutil.rmtree(d)
        os.makedirs(d)
        for fn, body in (("top.v", render(n, src)), ("top.cst", CST), ("top.sdc", SDC),
                         ("run.tcl", base.TCL)):
            with open(os.path.join(d, fn), "w") as f:
                f.write(body)
        ok = base.build(d)
        bad += not ok
        why = ""
        if not ok:
            with open(os.path.join(d, "gw_sh.log")) as f:
                errors = [l.strip() for l in f if "ERROR" in l]
            why = " -- " + (errors[0] if errors else "no ERROR line in gw_sh.log")
        print(f"{name:11s} CLKOUT{n} ENCLK{n}={src:5s} {'built' if ok else 'REFUSED'}{why}",
              flush=True)
    print("\nHardware was not accessed.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
