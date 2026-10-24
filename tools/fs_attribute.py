#!/usr/bin/env python3
"""Attribute every fuse that differs between two builds.

`tools/fs_site_diff.py` names the destination that moved inside one tile.
This tool accounts for the whole difference instead, tile by tile, so that a
pair can be said to contain nothing unexplained:

* `route` -- the fuse belongs to a destination mux of the tile's `pips`
  table; the destination and its exact selection in each build are reported.
* `clock` -- the same, for the tile's global-clock `clock_pips` table.
* `hclk` -- the same, for the device-level `hclk_pips` table.
* `config` -- the fuse belongs to an entry of one of the tile type's
  `shortval`, `longval` or `longfuses` tables; every entry that is fully set
  in one build and touches a changed fuse is reported, by table and key.
  Entries of one table can nest (`longfuses` table 58 has key 37 inside key
  39), so an entry inside a larger entry that is also reported is dropped.
* `unattributed` -- none of the above.  These are the fuses nothing in the
  chipdb describes, and the ones a packer would have to learn.

A selection is read by exact mux state, as in `tools/dqs_map_check.py`: the
fuses a build sets inside a mux must equal one source's fuse set.

Usage:
    tools/fs_attribute.py a.fs b.fs              # per-tile summary
    tools/fs_attribute.py a.fs b.fs --detail     # every destination and entry
    tools/fs_attribute.py a.fs b.fs --json

Run it with the open-flow environment sourced (`tools/openflow_env.sh`).  A
decoded GW5AST-138C bitstream costs about half a gigabyte, so this tool holds
exactly two and nothing else.
"""

import argparse
import collections
import json
import sys

import fs_site_diff as fsd


def _fuses(value):
    return {tuple(f) for f in value}


def _selected(sources: dict, state: set):
    mux = set().union(*sources.values()) if sources else set()
    hits = [s for s, f in sources.items() if f == state & mux]
    return hits[0] if len(hits) == 1 else None


def tile_state(dev, grid, matrix, tile):
    ry, cx = tile
    t = dev.tiles[dev.grid[ry][cx]]
    y0, x0 = grid.origin(ry, cx)
    state = set()
    for r in range(y0, y0 + t.height):
        row = matrix[r]
        for c in range(x0, x0 + t.width):
            if row[c]:
                state.add((r - y0, c - x0))
    return state


def attribute_tile(dev, tile, before: set, after: set) -> dict:
    ry, cx = tile
    ttyp = dev.grid[ry][cx]
    t = dev.tiles[ttyp]
    changed = before ^ after
    claimed = set()
    out = {"tile": list(tile), "type": ttyp, "changed": len(changed),
           "route": [], "clock": [], "hclk": [], "config": [], "unattributed": []}

    for kind, table in (("route", t.pips), ("clock", getattr(t, "clock_pips", {})),
                        ("hclk", dev.hclk_pips.get(tile, {}))):
        for dest in sorted(table):
            sources = table[dest]
            mux = set().union(*sources.values()) if sources else set()
            hit = changed & mux
            if not hit:
                continue
            claimed |= hit
            out[kind].append({"dest": dest, "fuses": len(hit),
                              "before": _selected(sources, before),
                              "after": _selected(sources, after)})

    rest = changed - claimed
    found = []
    for tabname in ("shortval", "longval", "longfuses"):
        for table, entries in getattr(dev, tabname).get(ttyp, {}).items():
            for key, value in entries.items():
                fuses = _fuses(value)
                if not fuses or not fuses & rest:
                    continue
                in_before, in_after = fuses <= before, fuses <= after
                if in_before == in_after:
                    continue
                found.append({"table": f"{tabname}.{table}",
                              "key": list(key) if isinstance(key, tuple) else key,
                              "fuses": sorted(fuses),
                              "set_in": "a" if in_before else "b"})
                claimed |= fuses & rest
    out["config"] = [e for e in found
                     if not any(o is not e and o["table"] == e["table"]
                                and o["set_in"] == e["set_in"]
                                and set(e["fuses"]) < set(o["fuses"]) for o in found)]
    out["unattributed"] = sorted(changed - claimed)
    return out


def attribute(dev, grid, ma, mb) -> list:
    changed = fsd.changed_bits(ma, mb)
    tiles = sorted({grid.tile_of(r, c) for r, c in changed})
    return [attribute_tile(dev, k, tile_state(dev, grid, ma, k),
                           tile_state(dev, grid, mb, k)) for k in tiles]


def summary_line(rep: dict) -> str:
    n_route = sum(d["fuses"] for d in rep["route"])
    n_clock = sum(d["fuses"] for d in rep["clock"])
    n_hclk = sum(d["fuses"] for d in rep["hclk"])
    n_cfg = len({tuple(f) for e in rep["config"] for f in e["fuses"]})
    return (f"tile ({rep['tile'][0]},{rep['tile'][1]}) type {rep['type']:3d}: "
            f"{rep['changed']:3d} changed  route {n_route:3d}  clock {n_clock:2d}  hclk {n_hclk:2d}  "
            f"config {len(rep['config']):2d} entries  "
            f"unattributed {len(rep['unattributed']):2d}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--detail", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    dev = fsd.chipdb.load_chipdb(fsd.DB)
    grid = fsd.Grid(dev)
    ma = fsd.load_matrix(args.a)
    mb = fsd.load_matrix(args.b)
    reports = attribute(dev, grid, ma, mb)
    del ma, mb

    if args.json:
        print(json.dumps({"a": args.a, "b": args.b, "tiles": reports}, indent=1))
        return 0
    totals = collections.Counter()
    for rep in reports:
        totals["changed"] += rep["changed"]
        totals["unattributed"] += len(rep["unattributed"])
        if rep["config"] or rep["unattributed"] or args.detail:
            print(summary_line(rep))
            for e in rep["config"]:
                print(f"    config {e['table']} {e['key']} set in {e['set_in']}: {e['fuses']}")
            if rep["unattributed"]:
                print(f"    unattributed: {rep['unattributed']}")
            if args.detail:
                for kind in ("route", "clock", "hclk"):
                    for d in rep[kind]:
                        print(f"    {kind} {d['dest']}: {d['before']} -> {d['after']}")
    print(f"{totals['changed']} changed fuses in {len(reports)} tiles; "
          f"{totals['unattributed']} unattributed.  Tiles with only routing "
          f"changes are not listed{'' if args.detail else ' (use --detail)'}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
