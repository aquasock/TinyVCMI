#!/usr/bin/env python3
"""Rewrite every LUT1/LUT2/LUT3 cell of a synthesised Gowin netlist as a LUT4.

The nextpnr-himbaechel Gowin chipdb carries timing arcs for LUT4 only
(gowin_arch_gen.py adds a "LUT4" cell variant and no LUT1..LUT3), so nextpnr
does not time any path through a LUT1, LUT2 or LUT3.  A LUTn becomes a LUT4
with the same function: its INIT replicated across the inputs it does not use,
which are left unconnected, so they are don't-cares.

    lut4ify.py IN.json OUT.json
"""
import json
import sys

src, dst = sys.argv[1], sys.argv[2]
d = json.load(open(src))
n = {1: 0, 2: 0, 3: 0}
for mod in d["modules"].values():
    for name, c in mod["cells"].items():
        t = c["type"]
        if t not in ("LUT1", "LUT2", "LUT3"):
            continue
        k = int(t[3])
        init = c["parameters"].get("INIT", "0")
        if not (isinstance(init, str) and set(init) <= set("01")):
            init = format(int(init), "0%db" % (1 << k))
        init = init.rjust(1 << k, "0")[-(1 << k):]
        c["type"] = "LUT4"
        # bit i of the LUT4 is bit (i mod 2^k) of the LUTn: MSB-first string repeated
        c["parameters"]["INIT"] = init * (16 >> k)
        for i in range(k, 4):
            c["port_directions"].setdefault("I%d" % i, "input")
        n[k] += 1
json.dump(d, open(dst, "w"))
print("lut4ify: LUT1 %d, LUT2 %d, LUT3 %d rewritten as LUT4" % (n[1], n[2], n[3]))
