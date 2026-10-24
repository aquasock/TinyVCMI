#!/usr/bin/env python3
"""Compare a written DDR3 image with the vendor's, table by table.

`tools/ddr_bank_check.py`, `tools/dqs_pack_check.py` and
`tools/dq_pack_check.py` compare the packer's fuses in memory.  This tool
reads two bitstreams that exist as files -- an image `gowin_pack
--ddr3-context` wrote (`tools/build_ddr3_pad_image.sh`) and a Gowin EDA build
of the same source -- and compares every table the DDR3 interface
configures, decoded from the files themselves:

* `IOB`: the `IOBA` or `IOBB` table of every bank 6/7 pad, used or not, and
  both `BANK` tables -- exactly;
* `IOLOGIC`: the `IOLOGICA` and `IOLOGICB` tables of every bank 6/7 cell,
  outside the `FCLKSEL` entries, because the two routers may carry the probe's
  board clock on different HCLK lanes;
* `DQS`: longfuses table 58 at the four byte groups, outside the lane field;
* with `--exact-lanes`, for a design that pins its `CLKDIV` and so fixes the
  lane in both builds, the lane field and the bank-6 `FCLKSEL` entries as
  well.  Bank 7's serializers are in another HCLK block, where either lane
  carrying the clock is correct and the two tools need not agree, so their
  `FCLKSEL` entries are reported as a NOTE naming both builds' fuses.  Any
  different device-level HCLK mux selections are also reported as notes;
* `DDRDLL`: the `DLL0` table of the bottom-left corner cell, exactly.

It reports every table that differs and writes nothing.  It does not touch
the board.

Usage:
    tools/ddr3_image_check.py build/ddr3_image/full_sstl.fs \\
        --vendor build/ddr3_pads/full_sstl/impl/pnr/probe.fs
    tools/ddr3_image_check.py build/ddr3_phy_bringup/open/bringup.fs \\
        --vendor build/ddr3_phy_bringup/vendor/impl/pnr/probe.fs --exact-lanes

Run it with the open-flow environment sourced (`tools/openflow_env.sh`).  Two
decoded GW5AST-138C bitstreams cost about a gigabyte.
"""

import argparse
import collections
import sys

import ddr_bank_check as dbc
import dqs_param_probe as probe
import fs_attribute as fa
import fs_site_diff as fsd

DDRDLL_CELL = (108, 0)


def field_of(table) -> set:
    return set().union(*({tuple(f) for f in v} for v in table.values()))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image", help="the open-flow .fs to check")
    ap.add_argument("--vendor", required=True, help="vendor .fs built from the same source")
    ap.add_argument("--exact-lanes", action="store_true",
                    help="compare the FCLKSEL entries and the DQS lane field too")
    args = ap.parse_args()

    from apycula import attrids
    dev = fsd.chipdb.load_chipdb(fsd.DB)
    grid = fsd.Grid(dev)
    open_m = fsd.load_matrix(args.image)
    vendor_m = fsd.load_matrix(args.vendor)
    state = {}

    def tile(m, cell):
        key = (id(m), cell)
        if key not in state:
            state[key] = fa.tile_state(dev, grid, m, cell)
        return state[key]

    counts, failures = {}, []

    def compare(kind, label, cell, field):
        a, b = tile(open_m, cell) & field, tile(vendor_m, cell) & field
        counts.setdefault(kind, [0, 0])[0] += 1
        if a != b:
            counts[kind][1] += 1
            failures.append(f"  FAIL  {kind:7s} {label} at {cell}: image only {sorted(a - b)}, "
                            f"vendor only {sorted(b - a)}")
        return a

    # IOB and BANK, every bank 6/7 table
    cells = set()
    for label, cell, table_name in dbc.scope(dev):
        cells.add(cell)
        compare("IOB", label, cell,
                field_of(dev.longval[dev.grid[cell[0]][cell[1]]][table_name]))

    # IOLOGIC on every bank 6/7 cell, outside FCLKSEL unless the lanes are
    # exact, and then outside it on bank 7 only, with a note
    rev = {v: k for k, v in dev.logicinfo["IOLOGIC"].items()}
    fclksel = {v for k, v in attrids.iologic_attrids.items() if k.startswith("FCLKSEL")}
    bank7_rows = {cell[0] for label, cell, _ in dbc.scope(dev) if label.startswith("bank 7 IOL")}
    notes = []
    for cell in sorted(cells):
        for side in "AB":
            table = dev.shortval[dev.grid[cell[0]][cell[1]]].get(f"IOLOGIC{side}")
            if not table:
                continue
            field = field_of(table)
            lanes = set()
            for k, v in table.items():
                if any(i and rev[abs(i)][0] in fclksel for i in k):
                    lanes |= {tuple(f) for f in v}
            exact = args.exact_lanes and cell[0] not in bank7_rows
            if not exact:
                field -= lanes
            compare("IOLOGIC", f"IOLOGIC{side}", cell, field)
            if args.exact_lanes and not exact:
                a, b = tile(open_m, cell) & lanes, tile(vendor_m, cell) & lanes
                if a != b:
                    notes.append((side, tuple(sorted(a)), tuple(sorted(b))))

    # DQS table 58 at each byte group, outside the lane field unless exact
    for n, lane in probe.base.LANES.items():
        bg = lane["byte_group"]
        lane_field = set() if args.exact_lanes else set().union(
            *(probe.at_byte_group(dev, bg, f)[0] for f in probe.T58_LANE.values()))
        got = compare("DQS", f"lane {n} table 58", bg, field_of(probe.t58_table(dev, bg)) - lane_field)
        if not got:
            failures.append(f"  FAIL  DQS     lane {n} table 58 at {bg}: no DQS configured in the image")
            counts["DQS"][1] += 1

    # DDRDLL
    dll = compare("DDRDLL", "DLL0", DDRDLL_CELL,
                  field_of(dev.shortval[dev.grid[DDRDLL_CELL[0]][DDRDLL_CELL[1]]]["DLL0"]))
    if not dll:
        failures.append(f"  FAIL  DDRDLL  DLL0 at {DDRDLL_CELL}: no DDRDLL configured in the image")
        counts["DDRDLL"][1] += 1

    for (side, a, b), n in sorted(collections.Counter(notes).items()):
        print(f"  NOTE  IOLOGIC{side} FCLKSEL on {n} bank-7 cell(s): image {list(a)}, vendor {list(b)}")
    if args.exact_lanes:
        for cell, table in sorted(dev.hclk_pips.items()):
            image_state, vendor_state = tile(open_m, cell), tile(vendor_m, cell)
            for dest, sources in sorted(table.items()):
                image_sel = fa._selected(sources, image_state)
                vendor_sel = fa._selected(sources, vendor_state)
                if image_sel != vendor_sel:
                    print(f"  NOTE  HCLK {cell} {dest}: image {image_sel}, vendor {vendor_sel}")
    for line in failures:
        print(line)
    for kind, (n, bad) in counts.items():
        print(f"  {'PASS' if not bad else 'FAIL'}  {kind:7s} {n - bad} of {n} tables equal")
    print(f"\n{'All tables equal' if not failures else f'{len(failures)} table(s) differ'}; "
          "nothing was written and hardware was not accessed.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
