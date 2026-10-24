#!/usr/bin/env python3
"""Build the vendor designs that expose a DQS block's configuration fuses.

Every design here is the matched lane shape of `tools/dqs_port_probe.py` -- a
DDRDLL feeding DLLSTEP, a pad on DQSIN, fixed pins -- with one thing changed
from a common `base`.  Diffing a variant against `base` with
`tools/fs_attribute.py` separates the routing a change moved from the
configuration it wrote.

Three groups:

`params`
    One DQS parameter moved off the base (`FIFO_MODE_SEL=0`, `RD_PNTR=000`,
    `DQS_MODE="X4"`, `HWL="true"`, the hardware-proven controller's values)
    to each other value Gowin's model `IDE/simlib/gw5a/prim_sim.v` declares.
    `RD_PNTR` is moved one bit at a time.

`presence`
    The same design with no DQS at all.  Against `base` this is every fuse the
    block adds; whatever is not routing is the block's configuration.

`lanes`
    The board clock on `FCLK` and on a `CLKDIV` pinned with
    `INS_LOC "fdiv" LEFTSIDE[4+n]`, whose divided output drives `PCLK` -- the
    shape a DDR3 PHY has.  SUG1018 sec 2.9 and the Apicula fork's P1.T08d
    measurement place that `CLKDIV` on lane n of HCLK block 2 at (81,0), the
    block this DQS's `FCLK` uses, so the clock net and therefore `FCLK` ride
    lane n.  Only `CLKDIV` takes this constraint: `CLKDIV2` and `DHCE` are
    refused with `CT2001`.  The lane selection fuses of longfuses table 58 at
    (72,0) are read from these.

`STEP` is XORed into `q` in every design, base included, so the DDRDLL is
kept when the DQS is absent; the proven vendor netlist also registers `STEP`
into fabric, so this does not move the base away from a real lane.

This tool only builds local Gowin EDA artifacts.  It does not produce or load
a TinyTang core image.

`--report` builds nothing: it attributes each built design against `base`
with `tools/fs_attribute.py`, one pair in memory at a time, and prints the
configuration entries and unattributed fuses, which are what the packer
needs; routing is summarised only.  It needs the open-flow environment.

`--check` builds nothing either: it asserts the recorded encoding below on
every built design -- the exact longfuses table 58 fuses at (72,0), the HCLK
lane chain at (81,0) for the lane designs, and no unattributed fuse in any
design's difference from `base`.

Usage:
    tools/dqs_param_probe.py                    # base and every group
    tools/dqs_param_probe.py --groups lanes
    tools/dqs_param_probe.py --only HWL_false,lane0
    tools/dqs_param_probe.py --report [--only ...]
    tools/dqs_param_probe.py --check [--only ...]
"""

import argparse
import os
import shutil
import sys

import dqs_port_probe as base

BASE_PARAMS = {"FIFO_MODE_SEL": "1'b0", "RD_PNTR": "3'b000",
               "DQS_MODE": '"X4"', "HWL": '"true"'}

PARAM_VARIANTS = {
    "FIFO_MODE_SEL_1": {"FIFO_MODE_SEL": "1'b1"},
    "RD_PNTR_001": {"RD_PNTR": "3'b001"},
    "RD_PNTR_010": {"RD_PNTR": "3'b010"},
    "RD_PNTR_100": {"RD_PNTR": "3'b100"},
    "DQS_MODE_X1": {"DQS_MODE": '"X1"'},
    "DQS_MODE_X2_DDR2": {"DQS_MODE": '"X2_DDR2"'},
    "DQS_MODE_X2_DDR3": {"DQS_MODE": '"X2_DDR3"'},
    "DQS_MODE_X2_DDR3_EXT": {"DQS_MODE": '"X2_DDR3_EXT"'},
    "HWL_false": {"HWL": '"false"'},
}

LANES = range(4)

PARAM_TEXT = ('#(.FIFO_MODE_SEL(1\'b0), .RD_PNTR(3\'b000),\n'
              '          .DQS_MODE("X4"), .HWL("true"))')
Q_TAIL = "^ sig_r ^ sig_s;"


def _source(params=None, dqs=True, fclk=None) -> str:
    text = base.render("", "")
    for needle in (PARAM_TEXT, Q_TAIL):
        if needle not in text:
            raise SystemExit(f"dqs_port_probe template changed: {needle!r} not found")
    text = text.replace(Q_TAIL, "^ sig_r ^ sig_s ^ ^step;")
    p = dict(BASE_PARAMS, **(params or {}))
    text = text.replace(PARAM_TEXT,
                        f"#(.FIFO_MODE_SEL({p['FIFO_MODE_SEL']}), "
                        f".RD_PNTR({p['RD_PNTR']}),\n"
                        f"          .DQS_MODE({p['DQS_MODE']}), .HWL({p['HWL']}))")
    if fclk is not None:
        text = text.replace(".PCLK(clk)", ".PCLK(pclk_div)")
        text = text.replace(
            "    DDRDLL #",
            "    wire pclk_div;\n"
            "    CLKDIV #(.DIV_MODE(\"2\")) fdiv (.HCLKIN(clk), .RESETN(1'b1),\n"
            "                                  .CALIB(1'b0), .CLKOUT(pclk_div));\n\n"
            "    DDRDLL #")
    if not dqs:
        start = text.index("    DQS #")
        end = text.index(");", start) + 2
        text = (text[:start]
                + "    assign {r90, w0, w270, rv, rb, rf, wf} = 7'b0;\n"
                + "    assign rp = 3'b0;\n    assign wp = 3'b0;"
                + text[end:])
    return text


def designs():
    """name -> (verilog, extra cst lines)"""
    out = {"base": (_source(), "")}
    for name, params in PARAM_VARIANTS.items():
        out[name] = (_source(params=params), "")
    out["no_dqs"] = (_source(dqs=False), "")
    for lane in LANES:
        out[f"lane{lane}"] = (_source(fclk=lane),
                              f'INS_LOC "fdiv" LEFTSIDE[{4 + lane}];\n')
    return out


#: The measured DQS encoding in longfuses table 58 of the byte group's config
#: tile, (72,0) for this lane, as fuse coordinates inside that tile.
BYTE_GROUP = (72, 0)
HCLK_BLOCK = (81, 0)
#: set in every design with a DQS and in none without; constant across every
#: parameter and lane tried, but every design here uses the same ports
T58_PRESENCE = {(20, 57), (20, 58), (20, 59), (20, 62),
                (20, 63), (20, 68), (20, 73), (20, 91)}
T58_FIFO_MODE_SEL_1 = {(20, 36), (20, 67)}
T58_RD_PNTR = [(20, 64), (20, 49), (20, 52)]           # bit 0, 1, 2
T58_DQS_MODE = {"X1": set(), "X2_DDR2": {(20, 79)}, "X2_DDR3": {(20, 78)},
                "X4": {(20, 78), (20, 79)}, "X2_DDR3_EXT": {(20, 78), (20, 90)}}
T58_HWL_TRUE = {(20, 103)}
#: the lane field: two identical 2-bit fields holding the HCLK lane number;
#: lane 0 sets nothing, so it reads the same as an unclocked block
T58_LANE = {0: set(), 1: {(20, 53), (20, 56)}, 2: {(20, 107), (20, 108)},
            3: {(20, 53), (20, 56), (20, 107), (20, 108)}}


def expected_t58(params=None, dqs=True, lane=3) -> set:
    """Table-58 fuses a design should set; the board clock on FCLK is lane 3."""
    if not dqs:
        return set()
    p = dict(BASE_PARAMS, **(params or {}))
    out = set(T58_PRESENCE) | T58_DQS_MODE[p["DQS_MODE"].strip('"')] | T58_LANE[lane]
    if p["FIFO_MODE_SEL"] == "1'b1":
        out |= T58_FIFO_MODE_SEL_1
    if p["HWL"] == '"true"':
        out |= T58_HWL_TRUE
    rd = p["RD_PNTR"].split("'b")[1]
    out |= {T58_RD_PNTR[i] for i, bit in enumerate(reversed(rd)) if bit == "1"}
    return out


def maximal_keys(table, state):
    """Table keys selected by `state`, excluding keys contained in another."""
    selected = [(key, {tuple(f) for f in fuses})
                for key, fuses in table.items()
                if fuses and {tuple(f) for f in fuses} <= state]
    return {key for key, fuses in selected
            if not any(fuses < other for _, other in selected)}


def t58_table(dev, byte_group):
    """Longfuses table 58 of the cell at `byte_group`, `(row, col)`."""
    return dev.longfuses[dev.grid[byte_group[0]][byte_group[1]]]["unknown_58"]


def at_byte_group(dev, byte_group, fuses):
    """(fuses, keys, missing keys): lane-0 table-58 `fuses`, in the
    coordinates of `BYTE_GROUP`, moved to `byte_group`'s cell through the
    table keys they select there.  The byte groups' cell types put the same
    keys at different coordinates (TOOL-012)."""
    keys = maximal_keys(t58_table(dev, BYTE_GROUP), fuses)
    table = t58_table(dev, byte_group)
    missing = keys - set(table)
    moved = set().union(*({tuple(f) for f in table[key]} for key in keys)) \
        if keys and not missing else set()
    return moved, keys, missing


def expectations():
    """name -> (table-58 fuses, HCLK lane or None)"""
    out = {"base": (expected_t58(), None), "no_dqs": (expected_t58(dqs=False), None)}
    for name, params in PARAM_VARIANTS.items():
        out[name] = (expected_t58(params=params), None)
    for lane in LANES:
        out[f"lane{lane}"] = (expected_t58(lane=lane), lane)
    return out


GROUPS = {
    "params": list(PARAM_VARIANTS),
    "presence": ["no_dqs"],
    "lanes": [f"lane{lane}" for lane in LANES],
}


def report(out_dir: str, names) -> int:
    import fs_attribute as fa
    import fs_site_diff as fsd

    dev = fsd.chipdb.load_chipdb(fsd.DB)
    grid = fsd.Grid(dev)
    fs = lambda n: os.path.join(out_dir, n, "impl/pnr/probe.fs")
    if not os.path.exists(fs("base")):
        print(f"missing {fs('base')}", file=sys.stderr)
        return 2
    for name in names:
        if name == "base":
            continue
        if not os.path.exists(fs(name)):
            print(f"== {name}: not built")
            continue
        ma, mb = fsd.load_matrix(fs("base")), fsd.load_matrix(fs(name))
        reps = fa.attribute(dev, grid, ma, mb)
        del ma, mb
        changed = sum(r["changed"] for r in reps)
        unattr = sum(len(r["unattributed"]) for r in reps)
        print(f"== {name}: {changed} changed fuses in {len(reps)} tiles, "
              f"{unattr} unattributed (a = base, b = {name})")
        for r in reps:
            cfg = [e for e in r["config"]
                   if not e["table"].startswith(("shortval.LUT", "shortval.CLS"))]
            if cfg or r["unattributed"]:
                print("  " + fa.summary_line(r))
                for e in cfg:
                    print(f"      {e['table']} {e['key']} set in {e['set_in']}: {e['fuses']}")
                if r["unattributed"]:
                    print(f"      unattributed: {r['unattributed']}")
        sys.stdout.flush()
    return 0


def check(out_dir: str, names, lane: int = 0) -> int:
    import fs_attribute as fa
    import fs_site_diff as fsd

    dev = fsd.chipdb.load_chipdb(fsd.DB)
    grid = fsd.Grid(dev)
    byte_group = base.LANES[lane]["byte_group"]
    t58 = t58_table(dev, byte_group)
    field = set().union(*({tuple(f) for f in v} for v in t58.values()))
    hclk = dev.hclk_pips[HCLK_BLOCK]
    fs = lambda n: os.path.join(out_dir, n, "impl/pnr/probe.fs")
    expect = expectations()
    base_m = fsd.load_matrix(fs("base"))
    failures = 0

    for name in names:
        if not os.path.exists(fs(name)):
            print(f"  FAIL  {name}: not built")
            failures += 1
            continue
        m = base_m if name == "base" else fsd.load_matrix(fs(name))
        want_reference, fclk_lane = expect[name]
        want, want_keys, missing_keys = at_byte_group(dev, byte_group, want_reference)
        got = fa.tile_state(dev, grid, m, byte_group) & field
        got_keys = maximal_keys(t58, got)
        ok = not missing_keys and got == want and got_keys == want_keys
        line = (f"{name:22s} table 58 at {byte_group} {len(got):2d} fuses; "
                f"keys {sorted(got_keys)}")
        if not ok:
            line += (f"; expected keys {sorted(want_keys)}"
                     f"; missing table keys {sorted(missing_keys)}"
                     f"; extra fuses {sorted(got - want)} missing fuses {sorted(want - got)}")
        if fclk_lane is not None:
            st = fa.tile_state(dev, grid, m, HCLK_BLOCK)
            n = f"2{fclk_lane}"
            chain = {f"HCLK_MUX_BETA{n}": f"L2HCLK{n}",
                     f"HCLK_BUF_BI{n}": f"HCLK_MUX_BETA{n}",
                     f"HCLK_MUX_ALPHA{n}": f"HCLK_BUF_BO{n}"}
            lane_ok = all(fa._selected(hclk[d], st) == src for d, src in chain.items())
            ok = ok and lane_ok
            line += f"; lane {fclk_lane} chain {'present' if lane_ok else 'MISSING'}"
        if name != "base":
            unattr = sum(len(r["unattributed"]) for r in fa.attribute(dev, grid, base_m, m))
            ok = ok and unattr == 0
            line += f"; {unattr} unattributed against base"
            del m
        print(f"  {'PASS' if ok else 'FAIL'}  {line}", flush=True)
        failures += not ok
    print(f"\n{len(names) - failures} of {len(names)} designs match the recorded "
          f"encoding.  Hardware was not accessed.")
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--groups", default=",".join(GROUPS),
                    help="comma-separated subset of " + ",".join(GROUPS))
    ap.add_argument("--only", help="comma-separated design names; overrides --groups")
    ap.add_argument("--out", default=None)
    ap.add_argument("--lane", type=int, choices=sorted(base.LANES), default=0,
                    help="DDR3 lane whose strobe pin the DQSIN pad takes; --check reads "
                         "that lane's byte group")
    ap.add_argument("--report", action="store_true",
                    help="attribute built designs against base; build nothing")
    ap.add_argument("--check", action="store_true",
                    help="assert the recorded encoding on built designs; build nothing")
    args = ap.parse_args()
    if args.out is None:
        args.out = base.lane_dir(os.path.join(base.ROOT, "build/dqs_b1"), args.lane)

    all_designs = designs()
    if args.only:
        names = [n for n in args.only.split(",") if n]
    else:
        names = ["base"] + [n for g in args.groups.split(",") if g
                            for n in GROUPS[g]]
    unknown = [n for n in names if n not in all_designs]
    if unknown:
        print(f"unknown design(s): {unknown}; known: {list(all_designs)}",
              file=sys.stderr)
        return 2
    if args.report:
        return report(args.out, names)
    if args.check:
        return check(args.out, names, args.lane)
    if not os.path.isdir(os.path.join(base.GOWIN, "IDE")):
        print(f"missing Gowin EDA at {base.GOWIN}", file=sys.stderr)
        return 2

    failed = []
    for name in names:
        verilog, cst_extra = all_designs[name]
        d = os.path.join(args.out, name)
        if os.path.isdir(d):
            shutil.rmtree(d)
        os.makedirs(d)
        for fn, body in (("top.v", verilog), ("top.cst", base.lane_cst(args.lane) + cst_extra),
                         ("top.sdc", base.SDC), ("run.tcl", base.TCL)):
            with open(os.path.join(d, fn), "w") as f:
                f.write(body)
        ok = base.build(d)
        print(f"{name}: {'built' if ok else 'FAILED (see gw_sh.log)'}", flush=True)
        if not ok:
            failed.append(name)

    print(f"\n{len(names) - len(failed)} of {len(names)} designs built under {args.out}.")
    if failed:
        print("failed: " + ", ".join(failed))
    print("Hardware was not accessed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
