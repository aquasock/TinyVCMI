#!/usr/bin/env python3
"""Check the open packer's DQS fuses against the vendor's, without an image.

Apicula's `get_DQS_fuses` writes a DQS's whole configuration into longfuses
table 58 of its byte group's cell (TOOL-008).  This tool runs the packer on
an open-flow routed netlist exactly as `gowin_pack` does -- its own `Netlist`,
`Device` and routing stage -- and then only the `DQS` bel's fuse method, so it
writes no bitstream.  That keeps it outside the packer's DDR3-bank guard,
which refuses any image configuring a bank 6/7 pad: a lane design's DQSIN pad
is on bank 6, and an image is not what this check needs.

It then requires that the table-58 fuses the packer emits equal both

* the encoding recorded in `tools/dqs_param_probe.py` for the cell's
  parameters and the HCLK lane the router chose, and
* the table-58 state of a vendor bitstream built from the same source
  (`--vendor`), read straight from its `.fs`.  When the two routers chose
  different HCLK lanes, everything outside the lane field must agree and each
  lane field must read as a lane.

`--fclk-lane N` tests the packer's lane encoding rather than the router: the
open router puts `FCLK` on lane 0 even when a pinned `CLKDIV` holds the same
net on another lane, so this option rewrites the netlist's one
`X5Y81/DQS_FCLK/HCLK2<m>` pip to lane N, in memory, before packing.

Usage:
    tools/dqs_pack_check.py ROUTED.json --vendor build/dqs_b1/lane0/impl/pnr/probe.fs
    tools/dqs_pack_check.py ROUTED.json --vendor build/dqs_b1/lane2/impl/pnr/probe.fs --fclk-lane 2

Run it with the open-flow environment sourced (`tools/openflow_env.sh`).
"""

import argparse
import json
import os
import re
import sys
import tempfile

import dqs_param_probe as probe
import fs_attribute as fa
import fs_site_diff as fsd


def with_fclk_lane(routed: str, lane: int) -> str:
    """A temporary copy of `routed` whose DQS FCLK pip names lane `lane`."""
    with open(routed) as f:
        text = f.read()
    pips = re.findall(r"X5Y81/DQS_FCLK/HCLK2[0-3]", text)
    if len(pips) != 1:
        raise SystemExit(f"expected one DQS FCLK pip in {routed}, found {len(pips)}")
    text = text.replace(pips[0], f"X5Y81/DQS_FCLK/HCLK2{lane}")
    json.loads(text)
    fd, path = tempfile.mkstemp(suffix=".json")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    return path


def packer_dqs_fuses(routed: str):
    """(cell name, parameters, lane, {(x, y): fuses}) for each DQS cell."""
    from apycula import gowin_pack as gp

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
    out = []
    for bel in pnr.get_bels():
        if bel.cell.typ != "DQS":
            continue
        cells = {}
        for cfb in device.get_DQS_fuses(bel):
            cells.setdefault((cfb.x, cfb.y), set()).update(map(tuple, cfb.bits))
        src = device._dqs_fclk_src.get((bel.x, bel.y))
        lane = int(src[-1]) if src else None
        out.append((bel.cell.name, bel.cell.parms, lane, cells))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("routed")
    ap.add_argument("--vendor", required=True,
                    help="vendor .fs built from the same source")
    ap.add_argument("--fclk-lane", type=int, choices=range(4),
                    help="rewrite the DQS FCLK pip to this lane before packing")
    args = ap.parse_args()

    routed = args.routed
    if args.fclk_lane is not None:
        routed = with_fclk_lane(args.routed, args.fclk_lane)
    try:
        found = packer_dqs_fuses(routed)
    finally:
        if routed != args.routed:
            os.unlink(routed)
    if len(found) != 1:
        print(f"FAIL  expected one DQS cell, found {len(found)}")
        return 1
    name, parms, lane, cells = found[0]
    y, x = probe.BYTE_GROUP
    cfg = (x, y)                                     # packer cells are (x, y)
    failures = 0

    def report(ok, line):
        nonlocal failures
        print(f"  {'PASS' if ok else 'FAIL'}  {line}")
        failures += not ok

    report(set(cells) == {cfg},
           f"{name}: packer writes only cell X{cfg[0]}Y{cfg[1]} (got "
           f"{sorted(f'X{a}Y{b}' for a, b in cells)})")
    got = cells.get(cfg, set())

    params = {k: parms.get(k) for k in probe.BASE_PARAMS}
    as_probe = {"FIFO_MODE_SEL": f"1'b{int(params['FIFO_MODE_SEL'] or '0', 2)}",
                "RD_PNTR": f"3'b{params['RD_PNTR'] or '000'}",
                "DQS_MODE": f'"{params["DQS_MODE"] or "X1"}"',
                "HWL": f'"{(params["HWL"] or "FALSE").lower()}"'}
    want = probe.expected_t58(params=as_probe, lane=lane or 0)
    report(got == want, f"{name}: lane {lane}, {as_probe}: {len(got)} fuses vs recorded "
                        f"encoding {len(want)}; extra {sorted(got - want)} missing "
                        f"{sorted(want - got)}")

    dev = fsd.chipdb.load_chipdb(fsd.DB)
    grid = fsd.Grid(dev)
    t58 = dev.longfuses[dev.grid[y][x]]["unknown_58"]
    field = set().union(*({tuple(f) for f in v} for v in t58.values()))
    vendor = fa.tile_state(dev, grid, fsd.load_matrix(args.vendor), probe.BYTE_GROUP) & field
    lane_field = set().union(*probe.T58_LANE.values())
    vendor_lane = next((n for n, f in probe.T58_LANE.items()
                        if f == vendor & lane_field), None)
    if vendor_lane == (lane or 0):
        report(got == vendor, f"{name}: open packer vs vendor, both lane {vendor_lane}: "
                              f"extra {sorted(got - vendor)} missing {sorted(vendor - got)}")
    else:
        # the routers chose different lanes; everything outside the lane
        # field must still agree, and each lane field must read as a lane
        a, b = got - lane_field, vendor - lane_field
        report(a == b and vendor_lane is not None,
               f"{name}: open packer lane {lane} vs vendor lane {vendor_lane}; outside "
               f"the lane field extra {sorted(a - b)} missing {sorted(b - a)}")

    print(f"\n{'All checks passed' if not failures else f'{failures} check(s) failed'}; "
          "no bitstream was written and hardware was not accessed.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
