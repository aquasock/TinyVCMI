#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Check a synthesised DDR3 controller netlist's I/O boundary (TOOL-051).

    ddr3_boundary_check.py NETLIST.json

The boundary's falling-edge registers must reach nextpnr as the DFFN and
DFFNS top.v instantiates, clocked straight from the CLKDIV, and no LUT may
drive a clock pin anywhere: Yosys once built 25 of them as rising-edge flops
behind a LUT1 inverting pclk, splitting each DRAM command across two PCLK
with nothing in either timer to see it.  Used by tools/build_ddr3_ctrl.sh
and tools/ae350_ddr3_sweep.sh.
"""
import json, re, sys
m = json.load(open(sys.argv[1]))["modules"]["top"]
# flattened, bnd_ff's register is bnd_lo[i].ff.r.ff or bnd_hi[i].ff.s.ff;
# other cells take bnd_ names from the nets they drive
reg = re.compile(r"^(bnd_lo\[|bnd_hi\[)\d+\]\.ff\.[rs]\.ff$")
drv = {}
for name, c in m["cells"].items():
    for p, d in c.get("port_directions", {}).items():
        if d == "output":
            for b in c["connections"][p]:
                drv[b] = (name, c["type"])
bad, want = [], {"bnd_lo[": ("DFFN", 469), "bnd_hi[": ("DFFNS", 18)}
seen = dict.fromkeys(want, 0)
for name, c in m["cells"].items():
    for p in ("CLK", "PCLK", "FCLK", "ICLK", "TCLK"):
        if p in c["connections"] and drv.get(c["connections"][p][0], ("", ""))[1].startswith("LUT"):
            bad.append(f"{name} ({c['type']}) {p} is driven by a LUT")
    r = reg.match(name)
    for pre, (typ, _) in want.items():
        if r and r.group(1) == pre:
            seen[pre] += 1
            src = drv.get(c["connections"].get("CLK", [None])[0], ("", ""))[1]
            if c["type"] != typ or src != "CLKDIV":
                bad.append(f"{name} is {c['type']} clocked from {src or 'nothing'}, not {typ} on the CLKDIV")
bad += [f"{n} of {pre}*] found, {cnt} expected" for pre, n in seen.items()
        for cnt in [want[pre][1]] if n != cnt]
if bad:
    print("\n".join(bad[:20]), file=sys.stderr)
    sys.exit("the I/O boundary did not synthesise as instantiated (TOOL-051)")
print("boundary: 469 DFFN and 18 DFFNS on the CLKDIV; no LUT drives a clock")
