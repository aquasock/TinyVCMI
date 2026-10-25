#!/usr/bin/env python3
"""Trace the proven DDR3 controller's read calibration from its netlist.

The vendor IP's `u_ddr_init` block, 1,518 cells, runs the JEDEC power-up,
write leveling and read calibration.  Its RTL is encrypted, but Tang-PSX keeps
the post-place-and-route netlist, so this tool cuts every cell named
`u_ddr_phy_top/u_ddr_init/` out of it as one module with its boundary nets as
ports, and simulates it with Gowin's own primitive models against
`tools/vendor_read_cal/tb_read_cal.v`, which answers each READ the block issues
with RVALID and RBURST only inside a window of lane 0's RCLKSEL and read_i.

For each scenario it prints the (RCLKSEL, read_i) values lane 0 is set to, in
order, how many READs were issued, and the setting the block finishes on, or
TIMEOUT.  The default scenarios show the rule recorded in TOOL-036.

Usage:
    tools/vendor_read_cal_trace.py [--scenario LAT,RVW,RBW,SELLO,SELHI,RILO,RIHI ...]
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

VO = "/run/media/vash/GIT/Tang-PSX/build/gate1-ip/ddr3_memory_interface/ddr3_memory_interface.vo"
GOWIN = os.environ.get("GOWINHOME", "/home/vash/tools/gowin-1.9.11.03")
PRIMS = os.path.join(GOWIN, "IDE/simlib/gw5a/prim_sim.v")
TB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor_read_cal/tb_read_cal.v")
SELECT = re.compile(r"u_ddr_phy_top/u_ddr_init/")

INST = re.compile(r"^(\w+) (\\\S+ |\w+)\s*\((.*?)\n\);", re.M | re.S)
PORT = re.compile(r"\.(\w+)\(\s*(.*?)\s*\)\s*(?=,\s*\n|\n|$)")
DEFP = re.compile(r"^defparam (\\\S+ )\.(\w+)=(.*?);", re.M)

DEFAULT = [
    (8, 1, 1, 0, 7, 0, 15),     # RBURST too short to count: never passes
    (8, 1, 2, 0, 7, 0, 15),     # every setting passes
    (8, 1, 2, 3, 5, 0, 15),     # RCLKSEL 3..5 pass
    (8, 1, 2, 6, 7, 0, 15),     # RCLKSEL 6..7 pass
]


def is_out(port: str) -> bool:
    return port in ("Q", "F", "O", "COUT", "SUM")


def san(net: str) -> str:
    net = net.replace("\\gw3_top/u_ddr_phy_top/", "").replace("\\gw3_top/", "")
    return "n_" + re.sub(r"[^A-Za-z0-9]", "_", net).strip("_")


def cut(text: str) -> str:
    params, cells, driver, users = {}, [], {}, {}
    for m in DEFP.finditer(text):
        params.setdefault(m.group(1), []).append((m.group(2), m.group(3)))
    for m in INST.finditer(text):
        typ, name = m.group(1), m.group(2)
        ports = {p: n.strip() for p, n in PORT.findall(m.group(3))}
        for p, n in ports.items():
            if is_out(p):
                driver[n] = name
            else:
                users.setdefault(n, set()).add(name)
        if SELECT.search(name) and typ.startswith(("LUT", "DFF", "ALU", "INV", "MUX")):
            cells.append((typ, name, ports))
    inside = {c[1] for c in cells}
    ins, outs, nets = set(), set(), set()
    for typ, name, ports in cells:
        for p, n in ports.items():
            if n in ("VCC", "GND"):
                continue
            if is_out(p):
                if any(u not in inside for u in users.get(n, ())):
                    outs.add(n)
            elif driver.get(n) not in inside:
                ins.add(n)
    for typ, name, ports in cells:
        nets.update(n for n in ports.values() if n not in ("VCC", "GND") and n not in ins | outs)
    ref = lambda n: "1'b1" if n == "VCC" else "1'b0" if n == "GND" else san(n)
    lines = ["module cut (" + ", ".join(san(n) for n in sorted(ins) + sorted(outs)) + ");"]
    lines += [f"  input {san(n)};" for n in sorted(ins)]
    lines += [f"  output {san(n)};" for n in sorted(outs)]
    lines += [f"  wire {san(n)};" for n in sorted(nets)]
    for i, (typ, name, ports) in enumerate(cells):
        lines.append(f"  {typ} c{i} (" + ", ".join(f".{p}({ref(n)})" for p, n in ports.items()) + ");")
        lines += [f"  defparam c{i}.{k} = {v};" for k, v in params.get(name, [])]
    lines.append("endmodule")
    return "\n".join(lines) + "\n", len(cells)


def run(vvp: str, sc) -> str:
    lat, rvw, rbw, sello, selhi, rilo, rihi = sc
    out = subprocess.run(["vvp", "-n", vvp, f"+LAT={lat}", f"+RVW={rvw}", f"+RBW={rbw}",
                          f"+SELLO={sello}", f"+SELHI={selhi}", f"+RILO={rilo}", f"+RIHI={rihi}"],
                         capture_output=True, text=True, timeout=3000).stdout
    seq, last = [], None
    for m in re.finditer(r"^\d+   sel0 (\d+) ri0 (\d+)$", out, re.M):
        v = (int(m.group(1)), int(m.group(2)))
        if v != last:
            seq.append(v)
            last = v
    reads = len(re.findall(r"READ #", out))
    done = re.search(r"INIT DONE  sel0 (\d+) ri0 (\d+)", out)
    shown = " ".join(f"{s}/{r}" for s, r in seq[:24]) + (" ..." if len(seq) > 24 else "")
    sweeps = {}
    for s, r in seq:
        if s == 0:
            sweeps[r] = sweeps.get(r, 0) + 1
    if len(seq) > 24:
        shown += "; RCLKSEL sweeps from 0 per read_i: " + ", ".join(
            f"read_i {r}: {n}" for r, n in sorted(sweeps.items()))
    end = f"finished at RCLKSEL {done.group(1)}, read_i {done.group(2)}" if done else "TIMEOUT"
    return (f"LAT {lat} RVALID {rvw} RBURST {rbw} pass RCLKSEL {sello}..{selhi} read_i {rilo}..{rihi}: "
            f"{end}; lane 0 RCLKSEL/read_i tried: {shown}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--scenario", action="append", default=None,
                    help="LAT,RVW,RBW,SELLO,SELHI,RILO,RIHI; repeatable")
    args = ap.parse_args()
    scenarios = [tuple(int(x) for x in s.split(",")) for s in args.scenario] if args.scenario else DEFAULT
    with open(VO) as f:
        text, n = cut(f.read())
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "cut.v")
        with open(src, "w") as f:
            f.write(text)
        vvp = os.path.join(d, "tb.vvp")
        subprocess.run(["iverilog", "-g2012", "-s", "tb", "-o", vvp, TB, src, PRIMS],
                       check=True, capture_output=True)
        print(f"{n} cells cut from {os.path.relpath(VO, '/run/media/vash/GIT')}")
        with ThreadPoolExecutor(max_workers=4) as ex:
            for line in ex.map(lambda sc: run(vvp, sc), scenarios):
                print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
