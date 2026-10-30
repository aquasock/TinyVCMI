#!/usr/bin/env python3
"""Attribute a fill's failures to the address, not to the data.

The training's write-alignment search fills a region with address data -- one
distinct pattern per burst -- and then reads it back at pseudo-random closed-page
addresses.  A burst that holds another burst's pattern shows up here as a
failing READ whose capture is a whole, valid necklace, which is exactly what a
row written with a single pattern (the sixteen rd_check rows, every paced
prewrite) cannot reveal.

This drives that fill once and reads the result out of rd_check's READ log,
which carries each READ's bank, row bit, burst and every lane's captured
necklace.  It repeats the analysis in the open-flow document: how many READs
held their own address's data, how far the nearest burst holding the captured
class is, and how many burst-index bits separate it from the read's own.

    tools/ddr3_fill_attrib.py --wstep 8 --json out.json

Run it against an image whose training has finished, not against one that has
handed the bus over: after hand-over the controller owns the pads and the fill
never reaches them.
"""

import argparse
import json
import sys
import time
from collections import Counter, defaultdict

import ddr3_write_probe as P


def own(e: dict) -> bool:
    """A READ whose four lanes all held its address's pattern, pins agreeing."""
    return all(e["lanes"][lane]["pat"] == e["exp"] and e["lanes"][lane]["pins"]
               for lane in range(4))


def address(e: dict) -> tuple[int, int, int]:
    """The logged READ's (bank, row's low four bits, burst).

    The log carries {row bit, bank} and the row's upper three bits; the row's
    low bit is the row bit, because the random generator's address data takes
    xs[6:3] as the row's low four bits and xs[3] as the row bit.
    """
    return e["loc"] & 7, (e["rhi"] << 1) | (e["loc"] >> 3), e["burst"]


def analyse(ents: list) -> dict:
    """The attribution of every failing READ in `ents`."""
    rows = {}

    def row(bank: int, row4: int) -> list:
        key = (bank, row4)
        if key not in rows:
            rows[key] = [P.adata_pattern(bank, row4, b) for b in range(128)]
        return rows[key]

    good = sum(own(e) for e in ents)
    nearest = Counter()
    bits = Counter()
    by_bank = defaultdict(lambda: [0, 0])
    by_row4 = defaultdict(lambda: [0, 0])
    stale = 0
    failing = 0
    for e in ents:
        bank, row4, burst = address(e)
        for table, key in ((by_bank, bank), (by_row4, row4)):
            table[key][0] += own(e)
            table[key][1] += 1
        if own(e):
            continue
        failing += 1
        got = e["lanes"][0]["pat"]
        if got == P.RC_PATTERNS[((e["loc"] >> 3) << 3) | bank]:
            stale += 1        # still holding the paced prewrite's pattern
        cl = row(bank, row4)
        offs = [b - burst for b in range(128) if cl[b] == got]
        if offs:
            nearest[min(offs, key=lambda o: (abs(o), o))] += 1
        for step in [b for b in range(128) if cl[b] == got and bin(b ^ burst).count("1") == 1]:
            bits[(step ^ burst).bit_length() - 1] += 1
    return {"reads": len(ents), "good": good, "failing": failing,
            "nearest_burst_offset": nearest, "burst_bit": bits,
            "by_bank": dict(by_bank), "by_row4": dict(by_row4), "stale": stale}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", default="/dev/ttyACM0")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--wstep", type=int, default=8,
                    help="the write strobe alignment to fill at, 8d + b as command 0x36 takes it")
    ap.add_argument("--gap", type=int, default=12,
                    help="random READ spacing in PCLK (0x09).  At 8 PCLK the capture itself "
                         "fails as well and the address attribution washes out; 12 and above "
                         "settle to the same answer")
    ap.add_argument("--pace", type=int, default=0,
                    help="idle PCLK between the fill's WRITEs (command 0x30).  Zero writes a "
                         "burst every PCLK, as the training's fill always has; the region takes "
                         "longer to fill at a higher pace and --fill-ms is scaled to match")
    ap.add_argument("--fill-ms", type=float, default=None,
                    help="fill time in ms; default covers the whole region at --pace")
    ap.add_argument("--reads-ms", type=float, default=200.0,
                    help="random-mode time in ms; the log keeps the first 1024 READs")
    ap.add_argument("--json", metavar="FILE", help="save the raw log and the attribution")
    args = ap.parse_args()

    core = P.Core(args.port, args.baud)
    core.request(0x37, 1)                      # address data on
    core.request(0x36, ((args.wstep >> 3) & 7) << 4 | (args.wstep & 7))
    core.request(0x30, args.pace)
    # 128 rows of 128 bursts, each burst one PCLK plus the pace, plus a refresh
    # pause a row; a third again for margin
    fill_s = args.fill_ms / 1000 if args.fill_ms is not None else \
        1.35 * 128 * (128 * (args.pace + 1) + 40) / 100e6
    core.mode(5)
    time.sleep(fill_s)
    core.mode(0)
    core.request(0x09, args.gap)               # READ spacing, PCLK
    core.request(0x32, 0)                      # the log from the first READ after the arm
    core.mode(4)
    time.sleep(args.reads_ms / 1000)
    core.mode(0)
    ents = core.read_log(adata=True)
    core.close()

    a = analyse(ents)
    pct = 100.0 * a["good"] / max(a["reads"], 1)
    print(f"WSTEP {args.wstep}, fill pace {args.pace}, READ spacing {args.gap} PCLK: "
          f"{a['good']} of {a['reads']} "
          f"READs held their own address's data ({pct:.2f}%)")
    print("nearest burst holding the captured class, per failing READ:")
    for off, n in a["nearest_burst_offset"].most_common(8):
        print(f"  {n:4d}  {off:+d} bursts")
    print("burst-index bits separating the capture from the read's own burst:")
    for bit, n in sorted(a["burst_bit"].items()):
        print(f"  bit {bit}: {n:4d}")
    print(f"failures still holding the paced prewrite's pattern: {a['stale']}")
    print("by bank (good/total): " +
          "  ".join(f"{b}:{g}/{t}" for b, (g, t) in sorted(a["by_bank"].items())))
    print("by row bit (good/total): " +
          "  ".join(f"{r}:{g}/{t}" for r, (g, t) in sorted(a["by_row4"].items())))
    if args.json:
        json.dump({"wstep": args.wstep, "entries": ents, "attribution": a}, open(args.json, "w"))
        print(f"saved to {args.json}")
    return 0 if a["failing"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
