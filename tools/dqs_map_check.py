#!/usr/bin/env python3
"""Check the recorded DQS port map against the matched vendor pairs.

`docs/ddr3-open-flow.md` and core-reference TOOL-007 record which site wire
each `DQS` port uses.  This tool re-derives every entry from the pairs built
by `tools/dqs_port_probe.py` and `tools/dqs_output_probe.py` and fails if any
of them disagrees, so the table cannot drift from the evidence behind it.

A destination's selected source is read by exact mux state: the fuses a
build programs inside that destination's mux must equal one source's fuse
set.  The weaker "every fuse of the source is set" test lets several sources
of one destination read as selected at once, and it is not used here.

Three kinds of entry are checked.

Inputs.  Among the site-input destinations of tile `(81,5)`, exactly one
changes its selection between the two members of the port's pair, and it is
the recorded wire.  `PCLK` and `RESET` are read from the `clock` pairs,
because tying either to a constant makes the vendor tool redraw the block.

Selected outputs.  Exactly one destination of tile `(81,5)` changes, and in
the target member it selects the recorded source wire.

Default outputs.  Every mux's all-zero state is itself the selection of one
source -- `W810`'s is `Q1`, `W830`'s and `N830`'s are `Q5`, `N800`'s and
`EW10`'s are `Q0` -- so a route that leaves the site through a destination
in that state changes no fuse in tile `(81,5)` at all.  Three outputs do
this.  For each, the tool requires that tile `(81,5)` is unchanged, that the
recorded destination is in its zero state selecting the recorded source,
and that the route's next hop is newly selected in the target and is also
the next hop of a sibling output whose first hop through the same
destination is a measured, non-default selection.  The source wire of a
default output is therefore an inference from the route, not a measurement
of a fuse, and the report says so.

`FCLK` is checked as an open question rather than an entry: the tool asserts
the two observations that keep it unresolved, so a later rebuild that
changes either one is noticed.

Usage:
    tools/dqs_map_check.py            # every entry, then a summary
    tools/dqs_map_check.py --build DIR

Run it with the open-flow environment sourced (`tools/openflow_env.sh`).  It
reads local build artifacts only and does not access hardware.
"""

import argparse
import os
import sys

import fs_site_diff as fsd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = (81, 5)

#: Destinations of tile (81,5) that can be a DQS input pin.  Output routing
#: muxes such as `W810` and `EW10` also change in input pairs, because every
#: output reaches `q`; they are not candidates.
SITE_INPUTS = ([f"{p}{i}" for p in "ABCD" for i in range(8)]
               + [f"{p}{i}" for p in ("CLK", "LSR", "CE") for i in range(4)])

#: port -> (pair directory under build/, reference member, target member, wire)
INPUTS = {
    "RDIR":       ("dqs_routed/RDIR", "const", "routed", "A0"),
    "RLOADN":     ("dqs_routed/RLOADN", "const", "routed", "A1"),
    "RMOVE":      ("dqs_routed/RMOVE", "const", "routed", "A2"),
    "READ[0]":    ("dqs_routed/READ_0", "const", "routed", "A3"),
    "READ[1]":    ("dqs_routed/READ_1", "const", "routed", "A4"),
    "READ[2]":    ("dqs_routed/READ_2", "const", "routed", "A5"),
    "READ[3]":    ("dqs_routed/READ_3", "const", "routed", "A7"),
    "WDIR":       ("dqs_routed/WDIR", "const", "routed", "B0"),
    "WLOADN":     ("dqs_routed/WLOADN", "const", "routed", "B1"),
    "WMOVE":      ("dqs_routed/WMOVE", "const", "routed", "B2"),
    "HOLD":       ("dqs_routed/HOLD", "const", "routed", "B3"),
    "RCLKSEL[0]": ("dqs_routed/RCLKSEL_0", "const", "routed", "C0"),
    "RCLKSEL[1]": ("dqs_routed/RCLKSEL_1", "const", "routed", "C1"),
    "RCLKSEL[2]": ("dqs_routed/RCLKSEL_2", "const", "routed", "C2"),
    "WSTEP[0]":   ("dqs_routed/WSTEP_0", "const", "routed", "D3"),
    "WSTEP[1]":   ("dqs_routed/WSTEP_1", "const", "routed", "D4"),
    "WSTEP[2]":   ("dqs_routed/WSTEP_2", "const", "routed", "D5"),
    "WSTEP[3]":   ("dqs_routed/WSTEP_3", "const", "routed", "D7"),
    "WSTEP[4]":   ("dqs_routed/WSTEP_4", "const", "routed", "CLK2"),
    "WSTEP[5]":   ("dqs_routed/WSTEP_5", "const", "routed", "LSR2"),
    "WSTEP[6]":   ("dqs_routed/WSTEP_6", "const", "routed", "CE1"),
    "WSTEP[7]":   ("dqs_routed/WSTEP_7", "const", "routed", "CE2"),
    "PCLK":       ("dqs_clock/PCLK", "fabric", "clock", "CLK0"),
    "RESET":      ("dqs_clock/RESET", "fabric", "clock", "LSR0"),
}

#: output -> (source wire in (81,5), first destination there, next hop or
#: None).  A next hop `(tile, dest, source)` marks a default output.
OUTPUTS = {
    "DQSR90":    ("Q0", "N800", ((73, 5), "N800", "N808")),
    "DQSW0":     ("F1", "EW10", None),
    "DQSW270":   ("Q1", "W810", ((81, 1), "N210", "W814")),
    "RVALID":    ("Q5", "W830", ((81, 1), "N250", "W834")),
    "RBURST":    ("F6", "N830", None),
    "RFLAG":     ("Q6", "W830", None),
    "WFLAG":     ("Q7", "EW10", None),
    "RPOINT[0]": ("F2", "W810", None),
    "RPOINT[1]": ("Q2", "W810", None),
    "RPOINT[2]": ("F4", "EW10", None),
    "WPOINT[0]": ("F3", "N800", None),
    "WPOINT[1]": ("Q3", "N800", None),
    "WPOINT[2]": ("F5", "N830", None),
}

#: FCLK's open question: (pair, reference, target, tile, input dests that
#: must change there).  The same fabric source lands on CLK1 in one template
#: revision and CLK2 in the next; on the board clock it selects neither.
FCLK_OBSERVATIONS = [
    ("dqs_routed/FCLK", "const", "routed", (81, 0), {"CLK1"}),
    ("dqs_clock/FCLK", "fabric", "clock", (81, 0), {"CLK2", "LSR2"}),
]


class Pairs:
    """One matched pair in memory at a time.

    A decoded GW5AST-138C bitstream costs about half a gigabyte, so nothing
    here keeps one past the pair it belongs to: `load()` replaces both
    members, and every query reads the pair loaded last.
    """

    def __init__(self, build: str):
        self.build = build
        self.dev = fsd.chipdb.load_chipdb(fsd.DB)
        self.grid = fsd.Grid(self.dev)
        self.ref = self.tgt = None

    def load(self, pair: str, ref: str, tgt: str):
        self.ref = self.tgt = None
        paths = [os.path.join(self.build, pair, m, "impl/pnr/probe.fs")
                 for m in (ref, tgt)]
        for path in paths:
            if not os.path.exists(path):
                raise FileNotFoundError(path)
        self.ref = fsd.load_matrix(paths[0])
        self.tgt = fsd.load_matrix(paths[1])

    def tile_state(self, matrix, tile):
        ry, cx = tile
        t = self.dev.tiles[self.dev.grid[ry][cx]]
        y0, x0 = self.grid.origin(ry, cx)
        state = set()
        for r in range(y0, y0 + t.height):
            row = matrix[r]
            for c in range(x0, x0 + t.width):
                if row[c]:
                    state.add((r - y0, c - x0))
        return t, state

    @staticmethod
    def selected(t, dest: str, state: set):
        """The one source whose fuse set equals this destination's mux state."""
        mux = set().union(*t.pips[dest].values())
        hits = [src for src, fuses in t.pips[dest].items() if fuses == state & mux]
        return hits[0] if len(hits) == 1 else None

    def moved(self, tile, dests=None):
        """dest -> (reference source, target source) for every dest that changed."""
        t, before = self.tile_state(self.ref, tile)
        _, after = self.tile_state(self.tgt, tile)
        out = {}
        for dest in (dests if dests is not None else t.pips):
            if dest not in t.pips:
                continue
            a, b = self.selected(t, dest, before), self.selected(t, dest, after)
            if a != b:
                out[dest] = (a, b)
        return out, len(before ^ after)

    def zero_source(self, tile, dest):
        t = self.dev.tiles[self.dev.grid[tile[0]][tile[1]]]
        empty = [src for src, fuses in t.pips[dest].items() if not fuses]
        return empty[0] if len(empty) == 1 else None


def out_dir(name: str) -> str:
    return "dqs_outputs/" + name.replace("[", "_").replace("]", "")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build", default=os.path.join(ROOT, "build"))
    args = ap.parse_args()

    pairs = Pairs(args.build)
    failures = []

    def report(ok: bool, line: str):
        print(f"  {'PASS' if ok else 'FAIL'}  {line}")
        if not ok:
            failures.append(line)

    print(f"inputs at tile {SITE}")
    for port, (pair, ref, tgt, wire) in INPUTS.items():
        pairs.load(pair, ref, tgt)
        moved, _ = pairs.moved(SITE, SITE_INPUTS)
        ok = set(moved) == {wire}
        report(ok, f"{port:10s} -> {wire:5s} moved {sorted(moved) or '-'}")

    print(f"\noutputs at tile {SITE}")
    # every pair's selection at every default output's next hop, read while
    # that pair is loaded so the sibling check needs no second load
    next_hops = {n for _, _, n in OUTPUTS.values() if n is not None}
    seen = {}
    for name, (src, dest, nxt) in OUTPUTS.items():
        pairs.load(out_dir(name), "reference", "target")
        for tile, ndest, nsrc in next_hops:
            nmoved, _ = pairs.moved(tile, [ndest])
            seen[name, tile, ndest] = nmoved.get(ndest, (None, None))[1]
        moved, nchanged = pairs.moved(SITE)
        if nxt is None:
            ok = set(moved) == {dest} and moved[dest][1] == src
            report(ok, f"{name:10s} -> {src:3s} via {dest:5s} selected   "
                       f"moved {sorted(moved) or '-'}")
            continue
        tile, ndest, nsrc = nxt
        t, after = pairs.tile_state(pairs.tgt, SITE)
        here = pairs.selected(t, dest, after)
        ok = (nchanged == 0 and here == src == pairs.zero_source(SITE, dest)
              and seen[name, tile, ndest] == nsrc)
        report(ok, f"{name:10s} -> {src:3s} via {dest:5s} default    "
                   f"site unchanged, next hop {tile} {ndest}<-{nsrc}")

    print("\ndefault outputs share their next hop with a measured sibling")
    for name, (_, dest, nxt) in OUTPUTS.items():
        if nxt is None:
            continue
        tile, ndest, nsrc = nxt
        shared = [o for o, (_, d, n) in OUTPUTS.items()
                  if d == dest and n is None and seen[o, tile, ndest] == nsrc]
        report(bool(shared), f"{name:10s} next hop shared by {shared or 'none'}")
    hops = [n for n in OUTPUTS.values() if n[2] is not None]

    sources = [src for src, _, _ in OUTPUTS.values()]
    report(len(set(sources)) == len(sources),
           f"output source wires distinct: {' '.join(sorted(sources))}")

    print("\nFCLK (unresolved)")
    for pair, ref, tgt, tile, expect in FCLK_OBSERVATIONS:
        pairs.load(pair, ref, tgt)
        moved, _ = pairs.moved(tile, SITE_INPUTS)
        report(set(moved) == expect,
               f"{pair:16s} {tile} moved {sorted(moved) or '-'}")

    print()
    if failures:
        print(f"{len(failures)} check(s) failed.")
        return 1
    print(f"All {len(INPUTS)} inputs and {len(OUTPUTS)} outputs agree with the "
          f"pairs; {len(hops)} output source wires are route inferences; FCLK "
          f"is unresolved.  Hardware was not accessed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
