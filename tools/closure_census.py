#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Summarise a seed sweep's closure and its failing endpoints.

    closure_census.py OUT_DIR

Reads OUT_DIR/s*/nextpnr.log for each seed's clocks and OUT_DIR/s*/sta.json
where tools/ddr3_sta.py ran as a post-route hook (TINYVCMI_SWEEP_STA=1), and
prints, per seed, whether every clock met and by how much, then the failing
endpoints across all seeds counted by register, so a path that binds on many
seeds is visible rather than only the worst seed's worst path.

Unrecorded numbers are left out rather than guessed: a seed with no routed
design is reported as refused, and a seed with no dump contributes to the
clock table only.
"""
import collections
import glob
import os
import re
import subprocess
import sys

FREQ = re.compile(r"Max frequency for clock\s+'([^']+)':\s+([0-9.]+) MHz")
# The constraint each clock is held to, in MHz, from fpga/ae350_ddr3/open.sdc.
NEED = {"pclk": 100.0, "bus_clk": 75.01, "pix_clk": 74.25, "mclk": 400.0,
        "core.rx.clk": 50.0}


def seed_clocks(log):
    """The last reported frequency of each clock, in MHz."""
    out = {}
    try:
        text = open(log, errors="replace").read()
    except OSError:
        return out
    for name, mhz in FREQ.findall(text):
        out[name] = float(mhz)
    return out


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    root = sys.argv[1]
    rows = []
    dumps = []
    dirs = [d for d in glob.glob(os.path.join(root, "s*")) if os.path.isdir(d)]
    for d in sorted(dirs, key=lambda p: int(re.sub(r"\D", "", os.path.basename(p)) or 0)):
        seed = os.path.basename(d)
        log = os.path.join(d, "nextpnr.log")
        routed = os.path.isfile(os.path.join(d, "ctrl.fs"))
        clocks = seed_clocks(log)
        rows.append((seed, routed, clocks))
        sta = os.path.join(d, "sta.json")
        if os.path.isfile(sta):
            dumps.append((seed, sta))

    print(f"{'seed':>6}  {'routed':>6}  clocks: MHz (need)  /  slack ns")
    closed = 0
    for seed, routed, clocks in rows:
        if not routed:
            print(f"{seed:>6}  {'no':>6}")
            continue
        parts, ok = [], True
        for name in ("pclk", "bus_clk", "core.rx.clk", "pix_clk", "mclk"):
            if name not in clocks:
                continue
            need = NEED.get(name)
            got = clocks[name]
            if need:
                slack = 1000.0 / need - 1000.0 / got
                flag = "" if got >= need else "!"
                if got < need:
                    ok = False
                parts.append(f"{name} {got:.2f}/{need:.0f}{flag} ({slack:+.2f})")
            else:
                parts.append(f"{name} {got:.2f}")
        closed += 1 if ok else 0
        print(f"{seed:>6}  {'yes':>6}  {'  '.join(parts)}")
    print(f"\nclosed every clock: {closed} of {len(rows)}")

    if not dumps:
        print("no sta.json dumps; rerun the sweep with TINYVCMI_SWEEP_STA=1")
        return 0

    # Count failing endpoints across seeds, so a path that binds repeatedly
    # shows up rather than the worst seed's worst path.
    counts = collections.Counter()
    worst = {}
    for seed, sta in dumps:
        r = subprocess.run([sys.executable,
                            os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                         "ddr3_sta.py"), sta, "--top", "40"],
                           capture_output=True, text=True)
        for line in r.stdout.splitlines():
            m = re.match(r"\s+(-?[0-9.]+)\s+pclk\s+(\S+)$", line)
            if not m:
                continue
            slack, reg = float(m.group(1)), m.group(2)
            counts[reg] += 1
            if reg not in worst or slack < worst[reg]:
                worst[reg] = slack
    print("\nfailing pclk endpoints, worst slack seen and how many seeds:")
    for reg, n in counts.most_common(25):
        print(f"  {n:>2} seed(s)  {worst[reg]:+.2f} ns  {reg}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
