#!/usr/bin/env python3
"""Locate each DDR3 lane's DQS site and byte-group cell with vendor builds.

Lane 0's `DQS` site (81,5) and byte group (72,0) were found by measuring one
lane in depth.  For the other lanes this tool takes the cheaper first step:
for each lane it builds the B1 `base` design of `tools/dqs_param_probe.py`
and the same design without the `DQS`, with the strobe pad moved to that
lane's `ddr_dqs` pin from the hardware-proven pin map, and attributes the
difference with `tools/fs_attribute.py`.  What it reports is

* every cell whose configuration changed (table 58 marks the byte group), and
* every cell near the left edge whose routing changed, which is where the
  `DQS`'s constant and clock inputs land -- the site tile.

`--report` builds nothing and prints those for every built lane.

The pads are on bank 6.  Nothing here packs an open-flow image or touches the
board.

Usage:
    tools/dq_lane_locate.py                 # build lanes 1..3
    tools/dq_lane_locate.py --report
"""

import argparse
import os
import shutil
import sys

import dqs_param_probe as lane
import dqs_port_probe as base

#: lane -> the `ddr_dqs` pin of Tang-PSX `gateware/ddr3_vendor/tang_psx_ddr3.cst`
DQS_PIN = {0: "Y3", 1: "V9", 2: "W6", 3: "R3"}


def designs():
    out = {}
    cst = base.CST
    for n, pin in DQS_PIN.items():
        if n == 0:
            continue
        c = cst.replace('IO_LOC "dqsi" Y3;', f'IO_LOC "dqsi" {pin};')
        if c == cst:
            raise SystemExit("base constraints changed: dqsi pin not found")
        out[f"lane{n}_base"] = (lane._source(), c)
        out[f"lane{n}_no_dqs"] = (lane._source(dqs=False), c)
    return out


def report(out_dir: str) -> int:
    import fs_attribute as fa
    import fs_site_diff as fsd

    dev = fsd.chipdb.load_chipdb(fsd.DB)
    grid = fsd.Grid(dev)
    fs = lambda n: os.path.join(out_dir, n, "impl/pnr/probe.fs")
    for n in sorted(DQS_PIN):
        if n == 0 or not os.path.exists(fs(f"lane{n}_base")):
            continue
        a, b = fsd.load_matrix(fs(f"lane{n}_no_dqs")), fsd.load_matrix(fs(f"lane{n}_base"))
        reps = fa.attribute(dev, grid, a, b)
        del a, b
        unattr = sum(len(r["unattributed"]) for r in reps)
        print(f"== lane {n} (DQS pad {DQS_PIN[n]}): {sum(r['changed'] for r in reps)} changed fuses, "
              f"{unattr} unattributed")
        for r in reps:
            cfg = [e for e in r["config"] if not e["table"].startswith(("shortval.LUT", "shortval.CLS"))]
            if cfg:
                tables = sorted({e["table"] for e in cfg})
                print(f"   config  ({r['tile'][0]},{r['tile'][1]}) type {r['type']}: {tables}")
        near = [r for r in reps if r["tile"][1] <= 8 and r["route"]]
        for r in sorted(near, key=lambda r: -len(r["route"]))[:6]:
            dests = sorted(d["dest"] for d in r["route"])
            print(f"   route   ({r['tile'][0]},{r['tile'][1]}) type {r['type']}: {len(dests)} destinations, "
                  f"e.g. {dests[:10]}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(base.ROOT, "build/dq_lanes"))
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()
    if args.report:
        return report(args.out)
    if not os.path.isdir(os.path.join(base.GOWIN, "IDE")):
        print(f"missing Gowin EDA at {base.GOWIN}", file=sys.stderr)
        return 2
    for name, (verilog, cst) in designs().items():
        d = os.path.join(args.out, name)
        if os.path.isdir(d):
            shutil.rmtree(d)
        os.makedirs(d)
        for fn, body in (("top.v", verilog), ("top.cst", cst),
                         ("top.sdc", base.SDC), ("run.tcl", base.TCL)):
            with open(os.path.join(d, fn), "w") as f:
                f.write(body)
        ok = base.build(d)
        why = ""
        if not ok:
            with open(os.path.join(d, "gw_sh.log")) as f:
                errors = [l.strip() for l in f if "ERROR" in l]
            why = " -- " + (errors[0] if errors else "no ERROR line")
        print(f"{name}: {'built' if ok else 'REFUSED'}{why}", flush=True)
    print("\nHardware was not accessed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
