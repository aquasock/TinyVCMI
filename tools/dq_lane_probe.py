#!/usr/bin/env python3
"""Build the vendor designs that expose a DDR3 lane's DQ serializers.

Every design is the B1 `base` lane of `tools/dqs_param_probe.py` -- a DDRDLL
on DLLSTEP, the DQS on pin Y3 with the proven controller's parameters -- plus
one memory-mode serializer on lane 0's `dq[0]` pad, Y4 (IOL78A, cell (77,0)),
wired the way the hardware-proven vendor netlist wires lane 0:

* `IDES8_MEM`: `D` from the pad, `ICLK` from `DQSR90`, `WADDR` from `WPOINT`,
  `RADDR` from `RPOINT`, `PCLK` and `FCLK` on the board clock, `Q0..Q7` into
  fabric;
* `OSER8_MEM`: `D0..D7` and `TX0..TX3` from fabric, `TCLK` from `DQSW0` with
  `TCLK_SOURCE="DQSW"`, `Q0` to the pad.

Two kinds of design are built against those:

`ok_*`
    The proven wiring.  Against `base` with `tools/fs_attribute.py`, this is
    every fuse the serializer adds.

`fab_*`
    One of the memory-mode pins (`ICLK`, `WADDR`, `RADDR`, `TCLK`) driven from
    a fabric register instead of its DQS output.  Whether Gowin accepts that
    decides whether the pin is a fabric connection or a hard-wired one; the
    tool reports Gowin's own error line when it refuses.

`par_*`
    `OSER8_MEM` with one parameter moved off the proven values:
    `TCLK_SOURCE="DQSW270"` (with `TCLK` on `DQSW270`, as the proven strobe
    serializer has it), `TXCLK_POL=1`, `HWL="true"`.

`*_lane<n>`
    The proven wiring with the board clock on `FCLK` and on a `CLKDIV` pinned
    to `LEFTSIDE[4+n]`, whose divided output drives every `PCLK` -- the shape
    `tools/dqs_param_probe.py` used to put the DQS on lane n.  These read the
    IOLOGIC `FCLKSEL` fields lane by lane.

`Q1` of `OSER8_MEM` (the tristate control) is left unused and the pad is a
plain output, so the designs stay the smallest lane shape the vendor builds.
The lane pads are on bank 6.  Nothing here packs an open-flow image or
touches the board.

`--check` builds nothing: it asserts the recorded results below on the built
designs -- every `fab_*` refused with `CK2060` and no bitstream, the exact
IOLOGIC attribute set each other design writes on its side's configuration
cell (A in the pad's cell, B in the cell below, as `fuse_cell_offset` has
it), each lane design's HCLK chain at (81,0), and no unattributed fuse in any
design's difference from the B1 `base`.  Attributes are read as the names of
the `IOLOGIC` short-value entries that are fully set and not inside a larger
set entry; several names share one fuse set, which is why aliases such as
`OUTMODE=ODDRX4` beside `OUTMODE=MODDRX4` appear together.

Usage:
    tools/dq_lane_probe.py                      # every design
    tools/dq_lane_probe.py --only ok_ides,fab_iclk
    tools/dq_lane_probe.py --pad AA4 --out build/dq_lane_b --only ok_ides,ok_oser
    tools/dq_lane_probe.py --check [--pad AA4 --out build/dq_lane_b]
"""

import argparse
import os
import shutil
import sys

import dqs_param_probe as lane
import dqs_port_probe as base

PAD = "Y4"     # lane 0 dq[0], IOL78A, cell (77,0)

IDES = """\
    wire [7:0] dq_q;
    IDES8_MEM ser (.D(dq_pad), .ICLK(@ICLK@), .PCLK(@PCLK@), .FCLK(clk),
                   .RESET(1'b0), .CALIB(1'b0), .WADDR(@WADDR@), .RADDR(@RADDR@),
                   .Q0(dq_q[0]), .Q1(dq_q[1]), .Q2(dq_q[2]), .Q3(dq_q[3]),
                   .Q4(dq_q[4]), .Q5(dq_q[5]), .Q6(dq_q[6]), .Q7(dq_q[7]));
"""

OSER = """\
    reg [7:0] dq_d = 8'h00;
    always @(posedge clk) dq_d <= {dq_d[6:0], sig_r};
    OSER8_MEM #(.HWL(@HWL@), .TCLK_SOURCE(@TCLK_SOURCE@), .TXCLK_POL(@TXCLK_POL@)) ser (
        .D0(dq_d[0]), .D1(dq_d[1]), .D2(dq_d[2]), .D3(dq_d[3]),
        .D4(dq_d[4]), .D5(dq_d[5]), .D6(dq_d[6]), .D7(dq_d[7]),
        .TX0(1'b0), .TX1(1'b0), .TX2(1'b0), .TX3(1'b0),
        .PCLK(@PCLK@), .FCLK(clk), .TCLK(@TCLK@), .RESET(1'b0),
        .Q0(dq_pad), .Q1());
"""

#: name -> (serializer, overrides of the proven sources and parameters, lane)
DESIGNS = {
    "ok_ides": ("ides", {}, None),
    "fab_iclk": ("ides", {"ICLK": "sig_s"}, None),
    "fab_waddr": ("ides", {"WADDR": "{sig_s, sig_r, sig_s}"}, None),
    "fab_raddr": ("ides", {"RADDR": "{sig_s, sig_r, sig_s}"}, None),
    "ok_oser": ("oser", {}, None),
    "fab_tclk": ("oser", {"TCLK": "sig_s"}, None),
    "par_tclk270": ("oser", {"TCLK": "w270", "TCLK_SOURCE": '"DQSW270"'}, None),
    "par_txpol1": ("oser", {"TXCLK_POL": "1'b1"}, None),
    "par_hwl": ("oser", {"HWL": '"true"'}, None),
}
for _n in range(4):
    DESIGNS[f"ides_lane{_n}"] = ("ides", {}, _n)
    DESIGNS[f"oser_lane{_n}"] = ("oser", {}, _n)
PROVEN = {"ICLK": "r90", "WADDR": "wp", "RADDR": "rp", "TCLK": "w0", "PCLK": "clk",
          "HWL": '"false"', "TCLK_SOURCE": '"DQSW"', "TXCLK_POL": "1'b0"}


#: The measured IOLOGIC attributes, as decoded entry names.
IDES_MODE = {"INMODE=MIDDRX4", "FIFO=ENABLE", "CLKIMUX=ENABLE"}
OSER_MODE = {"OUTMODE=MODDRX4", "OUTMODE=ODDRX4", "CLKOMUX=ENABLE"}
_L3_IDES = {"FCLKSEL5=HCLK1", "FCLKSEL5=HCLK3"} | {
    f"FCLKSEL6=HCLK{a} & FCLKSEL7=HCLK{b}_" for a in (1, 3) for b in (1, 3)}
_L02_OSER = {f"FCLKSEL1=HCLK{a} & FCLKSEL2=HCLK{b}_" for a in (0, 2) for b in (0, 2)}
IDES_LANE = {0: {"FCLKSEL3=HCLK0", "FCLKSEL3=HCLK0_", "FCLKSEL5=HCLK0"},
             1: _L3_IDES | {"FCLKSEL4=HCLK1", "FCLKSEL4=HCLK1_"},
             2: set(),
             3: _L3_IDES}
OSER_LANE = {0: _L02_OSER | {"FCLKSEL0=HCLK0", "FCLKSEL3=HCLK0", "FCLKSEL3=HCLK0_"},
             1: {"FCLKSEL0=HCLK1", "FCLKSEL0=HCLK3", "FCLKSEL4=HCLK1", "FCLKSEL4=HCLK1_"},
             2: _L02_OSER,
             3: {"FCLKSEL0=HCLK1", "FCLKSEL0=HCLK3"}}


def expected_attrs(name: str) -> set:
    """Decoded IOLOGIC attributes a built design should carry."""
    kind, overrides, fclk_lane = DESIGNS[name]
    lane_n = 3 if fclk_lane is None else fclk_lane      # board clock rides lane 3
    if kind == "ides":
        return IDES_MODE | IDES_LANE[lane_n]
    out = OSER_MODE | OSER_LANE[lane_n]
    out.add("WRFCLKSEL=" + overrides.get("TCLK_SOURCE", '"DQSW"').strip('"'))
    if overrides.get("TXCLK_POL") == "1'b1":
        out.add("TXCLK_POL=1")
    if overrides.get("HWL") == '"true"':
        out.add("HWL=TRUE")
    return out


def check(out_dir: str, pad: str, names) -> int:
    import fs_attribute as fa
    import fs_site_diff as fsd
    from apycula import attrids

    side = {"Y4": "A", "AA4": "B"}.get(pad)
    if side is None:
        print(f"--check knows the IOLOGIC side of Y4 and AA4 only, not {pad}", file=sys.stderr)
        return 2
    cell = (77, 0) if side == "A" else (78, 0)
    dev = fsd.chipdb.load_chipdb(fsd.DB)
    grid = fsd.Grid(dev)
    ids = {v: k for k, v in attrids.iologic_attrids.items()}
    vals = {v: k for k, v in attrids.iologic_attrvals.items()}
    rev = {v: k for k, v in dev.logicinfo["IOLOGIC"].items()}
    table = dev.shortval[dev.grid[cell[0]][cell[1]]][f"IOLOGIC{side}"]
    hclk = dev.hclk_pips[lane.HCLK_BLOCK]

    def decoded(state):
        lit = [(k, {tuple(f) for f in v}) for k, v in table.items()
               if v and {tuple(f) for f in v} <= state]
        top = [k for k, f in lit if not any(f < g for _, g in lit)]
        return {" & ".join(f"{ids.get(rev[i][0])}={vals.get(rev[i][1])}" for i in k if i)
                for k in top}

    fs = lambda n: os.path.join(out_dir, n, "impl/pnr/probe.fs")
    base_fs = os.path.join(base.ROOT, "build/dqs_b1/base/impl/pnr/probe.fs")
    base_m = fsd.load_matrix(base_fs)
    failures = 0
    for name in names:
        kind, overrides, fclk_lane = DESIGNS[name]
        if name.startswith("fab_"):
            log = os.path.join(out_dir, name, "gw_sh.log")
            text = open(log).read() if os.path.exists(log) else ""
            ok = "CK2060" in text and not os.path.exists(fs(name))
            print(f"  {'PASS' if ok else 'FAIL'}  {name:12s} refused with CK2060", flush=True)
            failures += not ok
            continue
        if not os.path.exists(fs(name)):
            print(f"  FAIL  {name:12s} not built")
            failures += 1
            continue
        m = fsd.load_matrix(fs(name))
        got = decoded(fa.tile_state(dev, grid, m, cell))
        want = expected_attrs(name)
        ok = got == want
        line = f"{name:12s} IOLOGIC{side} at {cell}: {len(got)} attributes"
        if not ok:
            line += f"; extra {sorted(got - want)} missing {sorted(want - got)}"
        if fclk_lane is not None:
            st = fa.tile_state(dev, grid, m, lane.HCLK_BLOCK)
            n = f"2{fclk_lane}"
            chain_ok = (fa._selected(hclk[f"HCLK_MUX_BETA{n}"], st) == f"L2HCLK{n}"
                        and fa._selected(hclk[f"HCLK_BUF_BI{n}"], st) == f"HCLK_MUX_BETA{n}")
            ok = ok and chain_ok
            line += f"; lane {fclk_lane} chain {'present' if chain_ok else 'MISSING'}"
        unattr = sum(len(r["unattributed"]) for r in fa.attribute(dev, grid, base_m, m))
        del m
        ok = ok and unattr == 0
        line += f"; {unattr} unattributed against base"
        print(f"  {'PASS' if ok else 'FAIL'}  {line}", flush=True)
        failures += not ok
    print(f"\n{len(names) - failures} of {len(names)} designs match.  Hardware was not accessed.")
    return 1 if failures else 0


def render(kind: str, overrides: dict, fclk_lane=None) -> str:
    text = lane._source(fclk=fclk_lane)
    if fclk_lane is not None:
        overrides = dict(overrides, PCLK="pclk_div")
    head = "module top (input wire clk, input wire dqsi, output wire q);"
    if head not in text:
        raise SystemExit("lane template changed: module header not found")
    direction = "input" if kind == "ides" else "output"
    text = text.replace(head, "module top (input wire clk, input wire dqsi, "
                              f"output wire q, {direction} wire dq_pad);")
    body = IDES if kind == "ides" else OSER
    for port, source in PROVEN.items():
        body = body.replace(f"@{port}@", overrides.get(port, source))
    text = text.replace("    assign unused = 1'b0;", body + "    assign unused = 1'b0;")
    if kind == "ides":
        text = text.replace("^ sig_r ^ sig_s ^ ^step;", "^ sig_r ^ sig_s ^ ^step ^ ^dq_q;")
    return text


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", help="comma-separated subset of " + ",".join(DESIGNS))
    ap.add_argument("--out", default=os.path.join(base.ROOT, "build/dq_lane"))
    ap.add_argument("--pad", default=PAD,
                    help=f"lane-0 pad for the serializer (default {PAD}, IOLOGIC A; "
                         "AA4 is dm[0] on IOLOGIC B of the same cell)")
    ap.add_argument("--check", action="store_true",
                    help="assert the recorded results on built designs; build nothing")
    args = ap.parse_args()
    if args.check and not args.only:
        args.only = ",".join(n for n in DESIGNS
                             if os.path.isdir(os.path.join(args.out, n)))
    names = [n for n in (args.only or ",".join(DESIGNS)).split(",") if n]
    unknown = [n for n in names if n not in DESIGNS]
    if unknown:
        print(f"unknown design(s): {unknown}", file=sys.stderr)
        return 2
    if args.check:
        return check(args.out, args.pad, names)
    if not os.path.isdir(os.path.join(base.GOWIN, "IDE")):
        print(f"missing Gowin EDA at {base.GOWIN}", file=sys.stderr)
        return 2

    cst = base.CST + (f'IO_LOC "dq_pad" {args.pad};\n'
                      'IO_PORT "dq_pad" IO_TYPE=LVCMOS33 PULL_MODE=NONE;\n')
    for name in names:
        kind, overrides, fclk_lane = DESIGNS[name]
        d = os.path.join(args.out, name)
        if os.path.isdir(d):
            shutil.rmtree(d)
        os.makedirs(d)
        extra = f'INS_LOC "fdiv" LEFTSIDE[{4 + fclk_lane}];\n' if fclk_lane is not None else ""
        for fn, body in (("top.v", render(kind, overrides, fclk_lane)), ("top.cst", cst + extra),
                         ("top.sdc", base.SDC), ("run.tcl", base.TCL)):
            with open(os.path.join(d, fn), "w") as f:
                f.write(body)
        ok = base.build(d)
        why = ""
        if not ok:
            with open(os.path.join(d, "gw_sh.log")) as f:
                errors = [l.strip() for l in f if "ERROR" in l]
            why = " -- " + (errors[0] if errors else "no ERROR line in gw_sh.log")
        print(f"{name}: {'built' if ok else 'REFUSED'}{why}", flush=True)
    print("\nHardware was not accessed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
