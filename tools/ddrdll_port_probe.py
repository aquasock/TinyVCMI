#!/usr/bin/env python3
"""Measure what selects the DDRDLL's `DLL0` configuration.

Every earlier DDRDLL design took the vendor baseline `DLL0` features 5, 17,
18 and 19 (TOOL-003/TOOL-016), which the packer writes under a DDR3 context.
The DDR3 PHY bring-up's vendor build, and the hardware-proven controller,
set features 4 and 21 instead of 5.  This probe found why: feature 5 is
`CLKIN` from the port tile's `CLK0`, and when the DLL's clock also drives a
`CLKDIV` at `LEFTSIDE[4+n]` the vendor takes it from HCLK block-2 lane n
instead, drops the `GB10 -> CLK0` pip and sets features 21 and `4-n`:

    no CLKDIV                5           LEFTSIDE[5]    21 + 3
    LEFTSIDE[4]   21 + 4                 LEFTSIDE[6]    21 + 2
                                         LEFTSIDE[7]    21 + 1

The ports do not move it: `STOP`, `UPDNCNTL` and `RESET` from a constant, a
register or an inverted register, the clock constrained at 20 to 2.5 ns, and
the clock from a PLL at 50, 100 or 400 MHz all leave feature 5, except that
an inverted `RESET` clears feature 19.

Each design is one `DDRDLL` on `DDRDLLM_BL`.  Gowin EDA builds them into
build/ddrdll_ports/<name>; `--decode` prints each bitstream's `DLL0`
features, and `--check` asserts them against `EXPECTED`.

Usage:
    tools/ddrdll_port_probe.py            # build every design
    tools/ddrdll_port_probe.py --decode   # print each design's DLL0 features
    tools/ddrdll_port_probe.py --check    # and fail on any unexpected one
"""

import argparse
import os
import shutil
import sys

import dqs_port_probe as base

OUT = os.path.join(base.ROOT, "build/ddrdll_ports")

#: name -> (STOP, UPDNCNTL, RESET[, clock period in ns[, PLL ODIV0 for CLKIN
#:          [, "div" for a CLKDIV on the same clock[, its LEFTSIDE index]]]])
DESIGNS = {
    "const": ("1'b0", "1'b1", "1'b0"),
    "stop_sig": ("sig[0]", "1'b1", "1'b0"),
    "stop_nsig": ("!sig[0]", "1'b1", "1'b0"),
    "updn_sig": ("1'b0", "sig[1]", "1'b0"),
    "updn_nsig": ("1'b0", "!sig[1]", "1'b0"),
    "rst_sig": ("1'b0", "1'b1", "sig[2]"),
    "rst_nsig": ("1'b0", "1'b1", "!sig[2]"),
    "bringup": ("!sig[0]", "sig[1]", "sig[2]"),
    # the same constant ports, the board clock constrained as a faster one
    "const_p10": ("1'b0", "1'b1", "1'b0", 10.0),
    "const_p5": ("1'b0", "1'b1", "1'b0", 5.0),
    "const_p2_5": ("1'b0", "1'b1", "1'b0", 2.5),
    # the same constant ports, CLKIN from the on-die PLL: 800 MHz VCO / ODIV0
    "pll400": ("1'b0", "1'b1", "1'b0", 2.5, 2),
    "pll100": ("1'b0", "1'b1", "1'b0", 10.0, 8),
    "pll50": ("1'b0", "1'b1", "1'b0", 20.0, 16),
    # pll400 with a CLKDIV on the same clock at LEFTSIDE[4], as in the PHY
    "pll400_div": ("1'b0", "1'b1", "1'b0", 2.5, 2, "div"),
    # the board clock straight into the same CLKDIV
    "const_div": ("1'b0", "1'b1", "1'b0", 20.0, None, "div"),
    # the CLKDIV on HCLK lanes 1 to 3 of the same block
    "const_div5": ("1'b0", "1'b1", "1'b0", 20.0, None, "div", 5),
    "const_div6": ("1'b0", "1'b1", "1'b0", 20.0, None, "div", 6),
    "const_div7": ("1'b0", "1'b1", "1'b0", 20.0, None, "div", 7),
}

DIV = """\
    wire pclk;
    CLKDIV #(.DIV_MODE("4")) fdiv (.HCLKIN(@CLKIN@), .RESETN(1'b1), .CALIB(1'b0), .CLKOUT(pclk));
    reg [7:0] pcnt = 8'd0;
    always @(posedge pclk) pcnt <= pcnt + 8'd1;
"""

PLL = """\
    wire dclk;
    PLL #(.FCLKIN("50"), .IDIV_SEL(1), .FBDIV_SEL(1), .MDIV_SEL(16), .ODIV0_SEL(@ODIV@),
          .CLKOUT0_EN("TRUE")) pll (
        .CLKIN(clk), .CLKFB(1'b0), .RESET(1'b0), .PLLPWD(1'b0), .RESET_I(1'b0), .RESET_O(1'b0),
        .FBDSEL(6'b0), .IDSEL(6'b0), .MDSEL(7'b0), .MDSEL_FRAC(3'b0),
        .ODSEL0(7'b0), .ODSEL0_FRAC(3'b0), .ODSEL1(7'b0), .ODSEL2(7'b0),
        .ODSEL3(7'b0), .ODSEL4(7'b0), .ODSEL5(7'b0), .ODSEL6(7'b0),
        .DT0(4'b0), .DT1(4'b0), .DT2(4'b0), .DT3(4'b0),
        .ICPSEL(6'b0), .LPFRES(3'b0), .LPFCAP(2'b0), .PSSEL(3'b0), .PSDIR(1'b0), .PSPULSE(1'b0),
        .ENCLK0(1'b1), .ENCLK1(1'b0), .ENCLK2(1'b0), .ENCLK3(1'b0),
        .ENCLK4(1'b0), .ENCLK5(1'b0), .ENCLK6(1'b0),
        .SSCPOL(1'b0), .SSCON(1'b0), .SSCMDSEL(7'b0), .SSCMDSEL_FRAC(3'b0),
        .CLKOUT0(dclk));
"""

TOP = """\
module top (input wire clk, output wire q, output wire lock);
    reg [23:0] cnt = 24'd0;
    always @(posedge clk) cnt <= cnt + 24'd1;
    wire [2:0] sig = cnt[23:21];
@PLL@    wire [7:0] step;
    DDRDLL #(.DLL_FORCE("FALSE"), .CODESCAL("111"), .SCAL_EN("FALSE"), .DIV_SEL(1'b0)) dll (
        .CLKIN(@CLKIN@), .STOP(@STOP@), .UPDNCNTL(@UPDN@), .RESET(@RESET@),
        .STEP(step), .LOCK(lock));
@DIV@    assign q = ^step@DIVQ@;
endmodule
"""

CST = """\
IO_LOC "clk" V22;
IO_PORT "clk" IO_TYPE=LVCMOS33 PULL_MODE=NONE;
IO_LOC "q" F18;
IO_PORT "q" IO_TYPE=LVCMOS33 PULL_MODE=NONE;
IO_LOC "lock" V18;
IO_PORT "lock" IO_TYPE=LVCMOS33 PULL_MODE=NONE;
INS_LOC "dll" DDRDLLM_BL;
"""

DLL_CELL = (108, 0)

#: `DLL0` features every design sets: `CODESCAL` 111 (12, and 6 to 11, the
#: entries its three bits also satisfy) and the unattributed 17 and 18
_COMMON = [6, 7, 8, 9, 10, 11, 12, 17, 18]
#: the clock-source and reset-polarity features, MEASURED 2026-10-24
EXPECTED = {name: sorted(_COMMON + extra) for name, extra in {
    "const": [5, 19], "stop_sig": [5, 19], "stop_nsig": [5, 19],
    "updn_sig": [5, 19], "updn_nsig": [5, 19], "rst_sig": [5, 19], "rst_nsig": [5],
    "bringup": [5, 19], "const_p10": [5, 19], "const_p5": [5, 19], "const_p2_5": [5, 19],
    "pll400": [5, 19], "pll100": [5, 19], "pll50": [5, 19],
    "pll400_div": [4, 19, 21], "const_div": [4, 19, 21],
    "const_div5": [3, 19, 21], "const_div6": [2, 19, 21], "const_div7": [1, 19, 21],
}.items()}


def build_all(names) -> int:
    bad = 0
    for name in names:
        spec = DESIGNS[name] + (None,) * (7 - len(DESIGNS[name]))
        stop, updn, rst, period, odiv, div, side = spec
        period = period or 20.0
        side = side or 4
        if odiv:
            # the PLL output is the DLL's clock; the board clock keeps 20 ns
            sdc = ("create_clock -name clk -period 20.000 [get_ports {clk}]\n"
                   f"create_clock -name dclk -period {period:.3f} [get_nets {{dclk}}]\n")
        else:
            sdc = f"create_clock -name clk -period {period:.3f} [get_ports {{clk}}]\n"
        clkin = "dclk" if odiv else "clk"
        top = (TOP.replace("@PLL@", PLL.replace("@ODIV@", str(odiv)) if odiv else "")
               .replace("@DIV@", DIV.replace("@CLKIN@", clkin) if div else "")
               .replace("@DIVQ@", " ^ ^pcnt" if div else "")
               .replace("@CLKIN@", clkin)
               .replace("@STOP@", stop).replace("@UPDN@", updn).replace("@RESET@", rst))
        cst = (CST + ('INS_LOC "pll" PLL_L[0];\n' if odiv else "")
               + (f'INS_LOC "fdiv" LEFTSIDE[{side}];\n' if div else ""))
        d = os.path.join(OUT, name)
        if os.path.isdir(d):
            shutil.rmtree(d)
        os.makedirs(d)
        for fn, body in (("top.v", top), ("top.cst", cst), ("top.sdc", sdc),
                         ("run.tcl", base.TCL)):
            with open(os.path.join(d, fn), "w") as f:
                f.write(body)
        ok = base.build(d)
        bad += not ok
        print(f"{name:10s} STOP={stop:8s} UPDNCNTL={updn:8s} RESET={rst:8s} {period:5.1f} ns "
              + (f"PLL /{odiv} " if odiv else "")
              + (f"CLKDIV LEFTSIDE[{side}] " if div else "")
              + ("built" if ok else "REFUSED"), flush=True)
    return 1 if bad else 0


def decode(names, check: bool = False) -> int:
    import fs_attribute as fa
    import fs_site_diff as fsd

    dev = fsd.chipdb.load_chipdb(fsd.DB)
    grid = fsd.Grid(dev)
    table = dev.shortval[dev.grid[DLL_CELL[0]][DLL_CELL[1]]]["DLL0"]
    bad = 0
    for name in names:
        fs = os.path.join(OUT, name, "impl/pnr/probe.fs")
        state = fa.tile_state(dev, grid, fsd.load_matrix(fs), DLL_CELL)
        feats = sorted(k[0] for k, v in table.items()
                       if len(k) == 2 and k[1] == 0 and v and {tuple(f) for f in v} <= state)
        field = set().union(*({tuple(f) for f in v} for v in table.values()))
        verdict = ""
        if check:
            ok = feats == EXPECTED[name]
            bad += not ok
            verdict = "PASS  " if ok else f"FAIL  expected {EXPECTED[name]}, "
        print(f"{verdict}{name:10s} {' '.join(map(str, DESIGNS[name])):28s} DLL0 features {feats}"
              f"  fuses {sorted(state & field)}", flush=True)
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--decode", action="store_true")
    ap.add_argument("--check", action="store_true", help="decode and assert EXPECTED")
    ap.add_argument("--only", help="comma-separated subset of " + ",".join(DESIGNS))
    args = ap.parse_args()
    names = [n for n in (args.only or ",".join(DESIGNS)).split(",") if n]
    unknown = [n for n in names if n not in DESIGNS]
    if unknown:
        print(f"unknown design(s): {', '.join(unknown)}", file=sys.stderr)
        return 2
    if args.decode or args.check:
        rc = decode(names, args.check)
    else:
        rc = build_all(names)
    print("\nHardware was not accessed.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
