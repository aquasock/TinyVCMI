#!/usr/bin/env python3
"""Check the open packer's DDR3-bank IO fuses against the vendor's, without an image.

Banks 6 and 7 of the GW5AST-138C hold every DDR3 ball: the four data lanes on
bank 6 and the address, command and clock balls on bank 7.  Apicula refuses
any design that configures a pad there outside a declared DDR context,
because a wrong pull or drive configuration on the DDR3 rail is a thermal
hazard.  Before that refusal can be lifted for real, the fuses the packer
would write on those banks have to be shown equal to the vendor's.

This tool runs `gowin_pack`'s own stages -- `Netlist`, `Device`, routing,
constant fuses, every bel's fuses and the final fuses -- on an open-flow
routed netlist, with `ddr_context` set on that one in-memory device only.
It never creates the bitstream object, so nothing is written and no image
exists afterwards.  It then compares, against a vendor bitstream built from
the same source:

* the IOB table of every bank 6 and bank 7 pad, used or not: side A's
  `IOBA` in the pad's cell, side B's `IOBB` in the cell below;
* the `BANK` table of bank 6's cell (90,0) and bank 7's cell (18,0).

Each comparison is restricted to that table's own fuses, so routing and
IOLOGIC stay out of it.  A difference is named by the table entries fully
set on each side.

Usage:
    tools/ddr_bank_check.py ROUTED.json --vendor build/dq_pad/dq_sstl/impl/pnr/probe.fs

Run it with the open-flow environment sourced (`tools/openflow_env.sh`).
"""

import argparse
import os
import re
import sys

import fs_attribute as fa
import fs_site_diff as fsd

DDR3_BANKS = (6, 7)


def packer_fuses(routed: str) -> dict:
    """{(row, col): fuses} the packer would write, with no image written."""
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
    # this instance only, in memory; no output bitstream is ever created
    device.ddr_context = True
    pack = gp.Pack(cli, pnr, device)
    pack.route()
    pack.set_const_fuses()
    pack.place()
    cells = {}
    for cfb in pack.get_fuses():
        cells.setdefault((cfb.y, cfb.x), set()).update(map(tuple, cfb.bits))
    return cells


def scope(dev) -> list:
    """[(label, (row, col), table)] for every bank 6/7 pad and bank cell."""
    out = []
    for name, bank in sorted(dev.pin_bank.items()):
        if bank not in DDR3_BANKS:
            continue
        m = re.fullmatch(r"IOL(\d+)([AB])", name)
        if m is None:
            raise SystemExit(f"{name} on bank {bank} is not a left-edge pad")
        row, side = int(m.group(1)) - 1, m.group(2)
        cell = (row, 0) if side == "A" else (row + 1, 0)
        out.append((f"bank {bank} {name}", cell, f"IOB{side}"))
    for bank in DDR3_BANKS:
        out.append((f"bank {bank} BANK", dev.bank_tiles[bank], "BANK"))
    return out


def namer(dev):
    """A function naming one table key by its IOB attribute conditions."""
    from apycula import attrids

    ids = {v: k for k, v in attrids.iob_attrids.items()}
    vals = {v: k for k, v in attrids.iob_attrvals.items()}
    rev = {v: k for k, v in dev.logicinfo["IOB"].items()}

    def name(table: str, key) -> str:
        if table == "BANK":
            return str(tuple(k for k in key if k))
        parts = []
        for i in key:
            if not i:
                continue
            a, v = rev.get(abs(i), (None, None))
            parts.append(f"{'!' if i < 0 else ''}{ids.get(a, a)}={vals.get(v, v)}")
        return " & ".join(parts)
    return name


def entries_set(table: dict, state: set) -> set:
    """Keys whose whole fuse set is in `state`, excluding keys inside another."""
    lit = [(k, {tuple(f) for f in v}) for k, v in table.items()
           if v and {tuple(f) for f in v} <= state]
    return {k for k, f in lit if not any(f < g for _, g in lit)}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("routed")
    ap.add_argument("--vendor", required=True,
                    help="vendor .fs built from the same source")
    args = ap.parse_args()

    packed = packer_fuses(args.routed)
    dev = fsd.chipdb.load_chipdb(fsd.DB)
    grid = fsd.Grid(dev)
    vendor_m = fsd.load_matrix(args.vendor)
    name = namer(dev)

    failures = configured = 0
    for label, cell, table_name in scope(dev):
        table = dev.longval[dev.grid[cell[0]][cell[1]]][table_name]
        field = set().union(*({tuple(f) for f in v} for v in table.values()))
        got = packed.get(cell, set()) & field
        want = fa.tile_state(dev, grid, vendor_m, cell) & field
        configured += bool(got or want)
        if got == want:
            if got:
                print(f"  PASS  {label:16s} {table_name} at {cell}: {len(got)} fuses")
            continue
        failures += 1
        print(f"  FAIL  {label:16s} {table_name} at {cell}: packer {len(got)} fuses, "
              f"vendor {len(want)}; packer only {sorted(got - want)}, "
              f"vendor only {sorted(want - got)}")
        for side, state in (("packer", got), ("vendor", want)):
            keys = entries_set(table, state)
            print(f"        {side} entries: "
                  + ("; ".join(sorted(name(table_name, k) for k in keys)) or "none"))
    pads = len(scope(dev)) - len(DDR3_BANKS)
    print(f"\n{pads} bank 6/7 pads and {len(DDR3_BANKS)} BANK tables compared, "
          f"{configured} configured in either build.")
    print(f"{'All checks passed' if not failures else f'{failures} check(s) failed'}; "
          "no bitstream was written and hardware was not accessed.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
