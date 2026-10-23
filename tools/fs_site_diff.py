#!/usr/bin/env python3
"""Attribute the fuse difference between two builds to one tile's destinations.

Every measurement in this project that names a pin comes from a matched pair:
two builds that differ in exactly one thing.  What is left is bookkeeping --
diff the two bitstreams, find which tiles moved, and inside the tile under
study say which destination wire moved and which of its sources became
selected.

The chipdb's `pips` table is `dest -> source -> fuses`, with the fuse
coordinates relative to the tile's own origin.  A source is *satisfied* when
every fuse in its set is programmed.  One destination's sources share a
select field, so several can look satisfied at once; that is why the useful
question is not "which source is selected" but "which destination changed",
and why the answer comes from the difference rather than from one build.

Changed bits that fall outside every destination's source fuses are the
site's own configuration -- for a `DQS` that is the constant-selection table
`docs/ddr3-open-flow.md` records.

Usage:
    tools/fs_site_diff.py a.fs b.fs                    # every changed tile
    tools/fs_site_diff.py a.fs b.fs --tile 81,5        # one tile, by dest
    tools/fs_site_diff.py a.fs b.fs --tile 81,5 --json # machine-readable

Run it with the open-flow environment sourced (`tools/openflow_env.sh`), since
it needs the chipdb and its Python dependencies.
"""

import argparse
import collections
import json
import os
import sys

APICULA = os.environ.get("APICULA_FORK",
                         "/run/media/vash/GIT/apicula-mathieufro")
sys.path.insert(0, APICULA)
sys.path.insert(0, os.environ.get("PYDEPS", "/home/vash/tools/pydeps"))

import apycula.chipdb as chipdb            # noqa: E402
from apycula import bslib                  # noqa: E402

DB = os.path.join(APICULA, "apycula", "GW5AST-138C.msgpack.xz")


def load_matrix(path: str):
    """The bitstream as a row-indexed matrix of 0/1.

    `bslib` returns the bit matrix in pure Python here (numpy is absent from
    the OSS CAD Suite interpreter), and a full device is five million fuses,
    so nothing in this tool builds a set of every programmed bit: the rows of
    the two builds are compared as lists first, which is fast, and only rows
    that differ are walked.
    """
    matrix = bslib.read_bitstream(path)
    return matrix[0] if isinstance(matrix, tuple) else matrix


def changed_bits(ma, mb) -> set:
    # Apicula returns numpy arrays when numpy is installed and Python lists
    # otherwise.  Comparing two numpy rows produces an array of booleans, not
    # the single boolean the list path below expects, so use numpy's own
    # nonzero result without importing or requiring numpy here.
    if hasattr(ma, "shape") and hasattr(mb, "shape"):
        rows, cols = (ma != mb).nonzero()
        return set(zip(rows.tolist(), cols.tolist()))

    out = set()
    for r, row in enumerate(ma):
        other = mb[r]
        if row == other:
            continue
        for c, value in enumerate(row):
            if value != other[c]:
                out.add((r, c))
    return out


def window(ma, mb, y0: int, x0: int, height: int, width: int):
    """The (before, after) fuses inside one tile, in tile-relative coordinates."""
    before, after = set(), set()
    for r in range(y0, min(y0 + height, len(ma))):
        ra, rb = ma[r], mb[r]
        for c in range(x0, min(x0 + width, len(ra))):
            if ra[c]:
                before.add((r - y0, c - x0))
            if rb[c]:
                after.add((r - y0, c - x0))
    return before, after


class Grid:
    """Fuse coordinate -> (tile row, tile column), from the chipdb's geometry."""

    def __init__(self, dev):
        self.dev = dev
        self.row_off = [0]
        for i in range(dev.rows):
            self.row_off.append(self.row_off[-1] + dev[i, 0].height)
        self.col_off = [0]
        for j in range(dev.cols):
            self.col_off.append(self.col_off[-1] + dev[0, j].width)

    def tile_of(self, r: int, c: int):
        ry = max(i for i in range(self.dev.rows) if self.row_off[i] <= r)
        cx = max(j for j in range(self.dev.cols) if self.col_off[j] <= c)
        return ry, cx

    def origin(self, ry: int, cx: int):
        return self.row_off[ry], self.col_off[cx]


def decode_tile(dev, ry: int, cx: int, rel_before: set, rel_after: set,
                rel_changed: set) -> dict:
    """Attribute a tile's changed fuses to its destinations' source muxes.

    All three sets are in tile-relative coordinates.
    """
    ttyp = dev.grid[ry][cx]
    tile = dev.tiles[ttyp]

    # fuse coordinates that belong to some destination's source mux
    owned = collections.defaultdict(set)
    for dest, sources in tile.pips.items():
        for fuses in sources.values():
            owned[dest] |= fuses

    report = {"tile": [ry, cx], "tile_type": ttyp,
              "changed": len(rel_changed), "dests": [], "config_bits": 0}
    claimed = set()
    for dest in sorted(owned):
        mux = owned[dest]
        hits = sorted(rel_changed & mux)
        if not hits:
            continue
        claimed |= mux
        before_sel = sorted(s for s, f in tile.pips[dest].items() if f and f <= rel_before)
        after_sel = sorted(s for s, f in tile.pips[dest].items() if f and f <= rel_after)
        report["dests"].append({
            "dest": dest,
            "changed_bits": len(hits),
            "selected_before": before_sel,
            "selected_after": after_sel,
        })
    report["config_bits"] = len(rel_changed & (rel_before | rel_after) - claimed)
    report["unattributed"] = sorted(rel_changed - claimed)
    return report


def scan_pairs(root: str, tile):
    """Decode every two-member pair directly under `root` at one tile.

    Returns `(name, report)` in directory order.  A pair is any directory with
    two subdirectories that each hold `impl/pnr/probe.fs`.
    """
    out = []
    for name in sorted(os.listdir(root)):
        d = os.path.join(root, name)
        if not os.path.isdir(d):
            continue
        members = sorted(m for m in os.listdir(d)
                         if os.path.exists(os.path.join(d, m, "impl/pnr/probe.fs")))
        if len(members) != 2:
            print(f"skipping {name}: {len(members)} build members", file=sys.stderr)
            continue
        out.append((name,
                    os.path.join(d, members[0], "impl/pnr/probe.fs"),
                    os.path.join(d, members[1], "impl/pnr/probe.fs")))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("a", nargs="?")
    ap.add_argument("b", nargs="?")
    ap.add_argument("--tile", help="ROW,COL to decode by destination")
    ap.add_argument("--scan", metavar="DIR",
                    help="decode every two-member pair under DIR at --tile")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--limit", type=int, default=12)
    args = ap.parse_args()

    dev = chipdb.load_chipdb(DB)
    grid = Grid(dev)

    if args.scan:
        if not args.tile:
            print("--scan needs --tile", file=sys.stderr)
            return 2
        ry, cx = (int(v) for v in args.tile.split(","))
        ttyp = dev.grid[ry][cx]
        y0, x0 = grid.origin(ry, cx)
        height, width = dev.tiles[ttyp].height, dev.tiles[ttyp].width
        rows = []
        for name, a, b in scan_pairs(args.scan, args.tile):
            ma, mb = load_matrix(a), load_matrix(b)
            changed = changed_bits(ma, mb)
            rel_before, rel_after = window(ma, mb, y0, x0, height, width)
            rel_changed = {(r - y0, c - x0) for r, c in changed
                           if y0 <= r < y0 + height and x0 <= c < x0 + width}
            report = decode_tile(dev, ry, cx, rel_before, rel_after, rel_changed)
            dests = [d for d in report["dests"]
                     if d["changed_bits"] >= 2
                     and set(d["selected_before"]).isdisjoint(d["selected_after"])]
            pin = max(dests, key=lambda d: d["changed_bits"])["dest"] if dests else "-"
            rows.append({"pair": name, "pin": pin,
                         "changed": report["changed"], "dests": report["dests"]})
            if not args.json:
                print(f"{name:12s} {pin:6s}  {report['changed']:3d} changed fuses")
        if args.json:
            print(json.dumps({"tile": [ry, cx], "pairs": rows}, indent=2))
        return 0

    ma, mb = load_matrix(args.a), load_matrix(args.b)
    changed = changed_bits(ma, mb)
    moved = collections.Counter()
    for r, c in changed:
        moved[grid.tile_of(r, c)] += 1

    if not args.tile:
        out = {"a": args.a, "b": args.b, "changed_fuses": len(changed),
               "tiles_changed": len(moved),
               "tiles": [{"tile": list(k), "type": dev.grid[k[0]][k[1]], "changed": n}
                         for k, n in moved.most_common(args.limit)]}
        if args.json:
            print(json.dumps(out, indent=2))
            return 0
        print(f"{args.a}\n{args.b}")
        print(f"changed fuses {len(changed)} in {len(moved)} tiles; largest:")
        for entry in out["tiles"]:
            print(f"  tile ({entry['tile'][0]},{entry['tile'][1]}) "
                  f"type {entry['type']:5d}: {entry['changed']:5d}")
        return 0

    ry, cx = (int(v) for v in args.tile.split(","))
    ttyp = dev.grid[ry][cx]
    y0, x0 = grid.origin(ry, cx)
    height, width = dev.tiles[ttyp].height, dev.tiles[ttyp].width
    rel_before, rel_after = window(ma, mb, y0, x0, height, width)
    rel_changed = {(r - y0, c - x0) for r, c in changed
                   if y0 <= r < y0 + height and x0 <= c < x0 + width}
    report = decode_tile(dev, ry, cx, rel_before, rel_after, rel_changed)
    if args.json:
        print(json.dumps(report, indent=2))
        return 0
    print(f"tile ({ry},{cx}) type {report['tile_type']}: {report['changed']} changed fuses")
    for entry in report["dests"]:
        before = ",".join(entry["selected_before"]) or "-"
        after = ",".join(entry["selected_after"]) or "-"
        print(f"  dest {entry['dest']:6s} {entry['changed_bits']:3d} changed bits   "
              f"{before} -> {after}")
    print(f"  {report['config_bits']} changed bits outside every destination's mux")
    return 0


if __name__ == "__main__":
    sys.exit(main())
