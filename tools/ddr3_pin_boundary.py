#!/usr/bin/env python3
"""Pin the DDR3 I/O boundary's fabric cells where a reference placement put them.

nextpnr has no timing arcs for IDES8_MEM, OSER8, OSER8_MEM or DQS (TOOL-050),
so every path between those cells and the fabric is placed and routed with no
timing check, and each placement draws a new set of delays across it.  This
tool takes a routed netlist whose image is known to work and writes an INS_LOC
constraint for every fabric cell on one of those untimed paths, so that later
builds of the same netlist keep the boundary the reference had:

  outbound  each DDR3 boundary flop (bnd_lo / bnd_hi) and any LUT between it
            and the I/O cell it drives;
  inbound   every LUT and DFF from an IDES8_MEM output or a DQS RVALID up to
            and including the first DFF on the path.

Pass-through LUTs that nextpnr's packer inserts in front of a DFF are not
pinned: they do not exist in the synthesised netlist, and the packer places
them with their DFF.  Every name written is checked against the synthesised
netlist, since that is what the constraints are applied to.

Usage: ddr3_pin_boundary.py ROUTED.json SYNTH.json OUT.cst

Result (TOOL-067): the pins hold, 1302 of 1302 once each pinned DFF's
D-driving LUT is pinned with it, but pinning does not make placements work;
the placement-dependent failures were fabric paths that nextpnr never timed
because they pass through a LUT1, LUT2 or LUT3 (TOOL-065).  Kept as a
diagnostic, not a fix.
"""
import collections
import json
import re
import sys

IO_TYPES = {"IDES8_MEM", "OSER8_MEM", "OSER8", "DQS"}
INBOUND = {"IDES8_MEM": None, "DQS": {"RVALID"}}   # None: every output
BND = re.compile(r"^bnd_(lo|hi)\[\d+\]\.ff\.[rs]\.ff$")
BEL = re.compile(r"^X(\d+)Y(\d+)/(LUT|DFF)(\d+)$")


def ins_loc(name: str, bel: str) -> str:
    """INS_LOC for a CLS half-slot: tile (x, y) is R(y+1)C(x+1), and LUT i or
    DFF i is CLS i // 2, half A for even i (nextpnr cst.cc, gowin_arch_gen)."""
    m = BEL.match(bel)
    if not m:
        raise ValueError(f"{name}: bel {bel} is not a CLS LUT or DFF")
    x, y, _, i = int(m[1]), int(m[2]), m[3], int(m[4])
    return f'INS_LOC "{name}" R{y + 1}C{x + 1}[{i // 2}][{"AB"[i % 2]}];'


def main() -> int:
    routed_path, synth_path, out_path = sys.argv[1:4]
    cells = json.load(open(routed_path))["modules"]["top"]["cells"]
    synth = set(json.load(open(synth_path))["modules"]["top"]["cells"])

    sinks = collections.defaultdict(list)
    for n, c in cells.items():
        for p, d in c["port_directions"].items():
            if d == "input":
                for b in c["connections"][p]:
                    sinks[b].append(n)

    def out_nets(c):
        return [b for p, d in c["port_directions"].items() if d == "output"
                for b in c["connections"][p]]

    pins = {}           # cell name -> (bel, side)

    def take(n, side):
        if "passthrough" in n:
            return
        pins[n] = (cells[n]["attributes"]["NEXTPNR_BEL"], side)

    # outbound: the boundary flops, and LUTs from them up to an I/O cell
    nbnd = 0
    for n, c in cells.items():
        if not BND.match(n):
            continue
        nbnd += 1
        take(n, "out")
        frontier = [n]
        while frontier:
            for b in out_nets(cells[frontier.pop()]):
                for s in sinks[b]:
                    if cells[s]["type"].startswith("LUT") and s not in pins:
                        take(s, "out")
                        frontier.append(s)

    # inbound: from the lanes' outputs through LUTs to the first DFF
    for n, c in cells.items():
        if c["type"] not in INBOUND:
            continue
        ports = INBOUND[c["type"]]
        frontier = [b for p, d in c["port_directions"].items()
                    if d == "output" and (ports is None or p in ports)
                    for b in c["connections"][p]]
        seen = set()
        while frontier:
            b = frontier.pop()
            for s in sinks[b]:
                if s in seen:
                    continue
                seen.add(s)
                t = cells[s]["type"]
                if t in IO_TYPES:
                    continue
                if t.startswith("DFF"):
                    take(s, "in")
                elif t.startswith("LUT"):
                    take(s, "in")
                    frontier += out_nets(cells[s])
                else:
                    raise SystemExit(f"{s}: unexpected {t} on an inbound boundary path")

    # A pinned DFF whose D comes from a LUT packed in the same half-slot moves
    # with that LUT: nextpnr clusters LUT-FF pairs and places the cluster by
    # its LUT, so 297 of 304 such outbound flops left their pins in the first
    # trial (seed 1).  Pin the paired LUT on its own bel too.
    drv = {}
    for n, c in cells.items():
        for p, d in c["port_directions"].items():
            if d == "output":
                for b in c["connections"][p]:
                    drv[b] = n
    for n, (bel, side) in list(pins.items()):
        if not cells[n]["type"].startswith("DFF"):
            continue
        d = drv.get(cells[n]["connections"]["D"][0])
        if d is None or "passthrough" in d or not cells[d]["type"].startswith("LUT"):
            continue
        m = BEL.match(bel)
        if cells[d]["attributes"]["NEXTPNR_BEL"] == f"X{m[1]}Y{m[2]}/LUT{m[4]}" and d not in pins:
            take(d, side)

    missing = sorted(n for n in pins if n not in synth)
    if missing:
        raise SystemExit(f"{len(missing)} pinned cells are not in {synth_path}: {missing[:5]}")
    bels = collections.Counter(b for b, _ in pins.values())
    dup = [b for b, k in bels.items() if k > 1]
    if dup:
        raise SystemExit(f"bels assigned twice: {dup[:5]}")

    side = collections.Counter((s, cells[n]["type"].rstrip("0123456789"))
                               for n, (_, s) in pins.items())
    with open(out_path, "w") as f:
        f.write(f"// DDR3 boundary pinned from {routed_path}\n")
        f.write(f"// {len(pins)} cells: "
                + ", ".join(f"{k} {s} {t}" for (s, t), k in sorted(side.items())) + "\n")
        for n in sorted(pins, key=lambda n: (pins[n][1], n)):
            f.write(ins_loc(n, pins[n][0]) + "\n")
    print(f"{nbnd} boundary flops; {len(pins)} cells pinned: "
          + ", ".join(f"{k} {s} {t}" for (s, t), k in sorted(side.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
