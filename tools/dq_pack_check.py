#!/usr/bin/env python3
"""Check the open packer's lane-serializer fuses against the vendor's.

Apicula's `get_OSER8_MEM_fuses` and `get_IDES8_MEM_fuses` write the TOOL-009
attributes through the existing IOLOGIC path.  Like `tools/dqs_pack_check.py`
this runs the packer on an open-flow routed netlist exactly as `gowin_pack`
does -- its own `Netlist`, `Device` and routing stage -- and then only the
serializer's fuse method, so no bitstream is written and the packer's
DDR3-bank guard is never reached.

The packer's IOLOGIC fuses on the serializer side's configuration cell (side
A in the pad's cell, side B in the cell below) must equal the vendor
bitstream's, restricted to that side's IOLOGIC short-value table so the pad's
own IOB settings stay out of it.  The vendor build must be built from the
same source with `FCLK` on the same HCLK lane, which `tools/dq_lane_probe.py`'s
`*_lane0` designs are.  On a mismatch the differing fuses are named by the
attribute entries that own them.

`--fclk-lane N` rewrites the serializer's `FCLKA`/`FCLKB` pip and its
`IOLOGIC_FCLK` attribute to HCLK lane N before packing, which tests the packer's lane encoding where the open router
always chooses lane 0.  `--outside-lane` compares everything except the fuses
owned by `FCLKSEL` entries, for a vendor build whose clock rode another lane.

Usage:
    tools/dq_pack_check.py ROUTED.json --vendor build/dq_lane/oser_lane0/impl/pnr/probe.fs
    tools/dq_pack_check.py ROUTED.json --vendor build/dq_lane/oser_lane2/impl/pnr/probe.fs --fclk-lane 2
    tools/dq_pack_check.py ROUTED.json --vendor build/dq_lane/par_hwl/impl/pnr/probe.fs --outside-lane

Run it with the open-flow environment sourced (`tools/openflow_env.sh`).
"""

import argparse
import json
import os
import re
import sys
import tempfile

import dqs_pack_check
import fs_attribute as fa
import fs_site_diff as fsd


def packer_serializer_fuses(routed: str):
    """(cell, x, y, side, {(x, y): fuses}) for the one lane serializer."""
    from apycula import gowin_pack as gp
    import os

    argv = sys.argv
    sys.argv = ["gowin_pack", "-d", os.environ.get("gowin_family", "GW5AST-138C"),
                "-o", os.devnull, routed]
    try:
        cli = gp.CliArgs()
    finally:
        sys.argv = argv
    pnr = gp.Netlist(cli)
    device = gp.create_device(cli, pnr)
    gp.Pack(cli, pnr, device).route()
    found = []
    for bel in pnr.get_bels():
        if bel.cell.typ not in ("OSER8_MEM", "IDES8_MEM"):
            continue
        cells = {}
        for cfb in getattr(device, f"get_{bel.cell.typ}_fuses")(bel):
            cells.setdefault((cfb.x, cfb.y), set()).update(map(tuple, cfb.bits))
        found.append((bel.cell, bel.x, bel.y, bel.idx_str, cells))
    return found


def with_fclk_lane(routed: str, lane: int) -> str:
    """A temporary copy of `routed` whose serializer rides HCLK lane `lane`.

    Two places carry the lane and both are rewritten: the serializer's one
    `FCLKA`/`FCLKB` pip, and the `IOLOGIC_FCLK` attribute nextpnr writes on the
    cell, which is what the packer reads.
    """
    with open(routed) as f:
        design = json.load(f)
    top = next(m for m in design["modules"].values() if m.get("cells"))
    sers = [c for c in top["cells"].values() if c["type"] in ("OSER8_MEM", "IDES8_MEM")]
    if len(sers) != 1 or "IOLOGIC_FCLK" not in sers[0]["attributes"]:
        raise SystemExit(f"expected one serializer with IOLOGIC_FCLK in {routed}")
    sers[0]["attributes"]["IOLOGIC_FCLK"] = f"HCLK_OUT{lane}"
    pips = 0
    for net in top["netnames"].values():
        r = net["attributes"].get("ROUTING", "")
        new = re.sub(r"(X0Y\d+/FCLK[AB]/HCLK2)[0-3]", lambda m: m.group(1) + str(lane), r)
        pips += new != r
        net["attributes"]["ROUTING"] = new
    if pips != 1:
        raise SystemExit(f"expected one serializer FCLK pip in {routed}, found {pips} nets")
    fd, path = tempfile.mkstemp(suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump(design, f)
    return path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("routed")
    ap.add_argument("--vendor", required=True)
    ap.add_argument("--fclk-lane", type=int, choices=range(4))
    ap.add_argument("--outside-lane", action="store_true")
    args = ap.parse_args()

    routed = args.routed if args.fclk_lane is None else with_fclk_lane(args.routed, args.fclk_lane)
    try:
        found = packer_serializer_fuses(routed)
    finally:
        if routed != args.routed:
            os.unlink(routed)
    if len(found) != 1:
        print(f"FAIL  expected one lane serializer, found {len(found)}")
        return 1
    cell, x, y, side, cells = found[0]
    cfg = (x, y if side == "A" else y + 1)          # packer cells are (x, y)
    failures = 0

    def report(ok, line):
        nonlocal failures
        print(f"  {'PASS' if ok else 'FAIL'}  {line}")
        failures += not ok

    report(set(cells) <= {cfg}, f"{cell.typ} {cell.name} at X{x}Y{y} side {side}: packer "
                                f"writes cells {sorted(f'X{a}Y{b}' for a, b in cells)}")

    dev = fsd.chipdb.load_chipdb(fsd.DB)
    grid = fsd.Grid(dev)
    row, col = cfg[1], cfg[0]
    table = dev.shortval[dev.grid[row][col]][f"IOLOGIC{side}"]
    field = set().union(*({tuple(f) for f in v} for v in table.values()))
    if args.outside_lane:
        from apycula import attrids
        fclksel = {v for k, v in attrids.iologic_attrids.items() if k.startswith("FCLKSEL")}
        lane_fuses = set()
        for k, v in table.items():
            if any(i and dev.logicinfo["IOLOGIC"] and
                   {a for (a, _), n in dev.logicinfo["IOLOGIC"].items() if n == abs(i)} & fclksel
                   for i in k):
                lane_fuses |= {tuple(f) for f in v}
        field -= lane_fuses
    got = cells.get(cfg, set()) & field
    vendor = fa.tile_state(dev, grid, fsd.load_matrix(args.vendor), (row, col)) & field
    ok = got == vendor
    scope = " outside the lane field" if args.outside_lane else ""
    report(ok, f"IOLOGIC{side} at X{col}Y{row}{scope}: {len(got)} packer fuses vs {len(vendor)} vendor")
    if not ok:
        from apycula import attrids
        ids = {v: k for k, v in attrids.iologic_attrids.items()}
        vals = {v: k for k, v in attrids.iologic_attrvals.items()}
        rev = {v: k for k, v in dev.logicinfo["IOLOGIC"].items()}
        for label, fuses in (("packer only", got - vendor), ("vendor only", vendor - got)):
            for f in sorted(fuses):
                def name(i):
                    # a negative key is the entry for that attribute's absence
                    a, b = rev[abs(i)]
                    return ("NOT " if i < 0 else "") + f"{ids.get(a)}={vals.get(b)}"
                owners = sorted({" & ".join(name(i) for i in k if i)
                                 for k, v in table.items() if f in {tuple(t) for t in v}})
                print(f"        {label} {f}: {owners[:4]}")

    print(f"\n{'All checks passed' if not failures else f'{failures} check(s) failed'}; "
          "no bitstream was written and hardware was not accessed.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
