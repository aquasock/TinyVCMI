#!/usr/bin/env python3
"""Trace the proven DDR3 controller's PHY start-up sequence from its netlist.

The vendor IP's `ddr_sync` block sequences the DLL, the memory-clock stop and
the PHY reset on the 50 MHz board clock.  Its RTL is encrypted, but Tang-PSX
keeps the post-place-and-route netlist, so this tool cuts that block's cells
out of it -- everything named `u_ddr_phy_top/ddr_sync/`, plus the three-flop
`stop_reg` pipeline that turns `stop_d` into `pll_stop` and the
`ddr_rsti_reg` chain that makes `ddr_rst` -- and simulates them with Gowin's
own primitive models.  The cut's only inputs are the board clock, the IP
reset, `pll_lock`, the DLL's `LOCK` and `sys_reset_Z`, the read-calibration
re-sync request, held low here as at first start-up.

Stimulus: the IP reset releases at 1 us, `pll_lock` rises at 5 us, and the
DLL's `LOCK` rises a given time after both `dll_rsti` is low and `pll_lock`
is high, and stays high.  The
tool prints every change of the block's outputs as a timeline, in 50 MHz
cycles from `pll_lock`:

  dll_rsti   the DLL's RESET
  uddcntln   the DLL's UPDNCNTL
  pll_stop   the PLL output enable (`ENCLK2`), low stops the memory clock
  ddr_rst    the CLKDIV's and every lane serializer's reset
  pause      every DQS's HOLD
  memsync3   the state that starts DDR initialization
  ready, ddr_init_st

Usage:
    tools/vendor_memsync_trace.py [--lock-after-us 100]
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

VO = "/run/media/vash/GIT/Tang-PSX/build/gate1-ip/ddr3_memory_interface/ddr3_memory_interface.vo"
GOWIN = os.environ.get("GOWINHOME", "/home/vash/tools/gowin-1.9.11.03")
PRIMS = os.path.join(GOWIN, "IDE/simlib/gw5a/prim_sim.v")

P = "\\gw3_top/u_ddr_phy_top/"
INPUTS = {f"{P}dll_lock ": "dll_lock", f"{P}n7_6 ": "rst", f"{P}sys_reset_Z ": "sys_reset",
          "clk": "clk", "pll_lock": "pll_lock"}
WATCH = {"dll_rsti": f"{P}dll_rsti ", "uddcntln": f"{P}uddcntln ",
         "pll_stop_n": f"{P}stop_reg [2]", "ddr_rst": "ddr_rst", "pause": f"{P}pause ",
         "memsync3": f"{P}cs_memsync [3]", "ready": f"{P}ddr_sync/ready ",
         "ddr_init_st": f"{P}ddr_init_st_Z "}

INST = re.compile(r"^(\w+) (\\\S+ |\w+)\s*\((.*?)\n\);", re.M | re.S)
PORT = re.compile(r"\.(\w+)\(\s*(.*?)\s*\)\s*(?=,\s*\n|\n|$)")
DEFP = re.compile(r"^defparam (\\\S+ )\.(\w+)=(.*?);", re.M)


def cut(text: str):
    cells, params = [], {}
    for m in DEFP.finditer(text):
        params.setdefault(m.group(1), []).append((m.group(2), m.group(3)))
    for m in INST.finditer(text):
        typ, name, body = m.group(1), m.group(2), m.group(3)
        if not (f"{P}ddr_sync/" in name or f"{P}stop_reg_" in name or f"{P}ddr_rsti_reg_" in name):
            continue
        cells.append((typ, name, {p: n for p, n in PORT.findall(body)}))
    return cells, params


def ident(net: str, names: dict) -> str:
    net = net.strip()
    if net in ("GND", "VCC"):
        return "1'b0" if net == "GND" else "1'b1"
    key = net if net.endswith(" ") or "[" in net else net + " "
    for k in (net, key, net + " "):
        if k in INPUTS:
            return INPUTS[k]
    return names.setdefault(net, f"n{len(names)}")


def render(cells, params) -> str:
    names = {}
    body = []
    for i, (typ, name, ports) in enumerate(cells):
        conns = ", ".join(f".{p}({ident(n, names)})" for p, n in ports.items())
        body.append(f"    {typ} c{i} ({conns});")
        for k, v in params.get(name, []):
            body.append(f"    defparam c{i}.{k} = {v};")
    watch = []
    for label, net in WATCH.items():
        n = names.get(net.strip()) or names.get(net) or names.get(net.rstrip())
        if n is None:
            raise SystemExit(f"net {net!r} is not in the cut")
        watch.append((label, n))
    decl = "\n".join(f"    wire {n};" for n in sorted(set(names.values())))
    mon = " or ".join(n for _, n in watch)
    fmt = " ".join(f"{label}=%b" for label, _ in watch)
    args = ", ".join(n for _, n in watch)
    return f"""`timescale 1ns/1ps
module tb;
    reg clk = 1'b0, rst = 1'b1, pll_lock = 1'b0, dll_lock = 1'b0, sys_reset = 1'b0;
    always #10 clk = ~clk;
    GSR GSR (.GSRI(1'b1));
{decl}
{chr(10).join(body)}
    integer lock_after_ns;
    time t_lock = 0;
    initial begin
        if (!$value$plusargs("lock_after_ns=%d", lock_after_ns)) lock_after_ns = 100000;
        #1000 rst = 1'b0;
        #4000 pll_lock = 1'b1; t_lock = $time;
    end
    initial begin
        wait ({watch[0][1]} === 1'b0 && pll_lock === 1'b1);
        #(lock_after_ns) dll_lock = 1'b1;
    end
    always @({mon} or dll_lock)
        $display("%0d cycles  dll_lock=%b {fmt}", ($signed($time) - $signed(t_lock)) / 20, dll_lock, {args});
    initial #3000000 $finish;
endmodule
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lock-after-us", type=float, default=100.0,
                    help="DLL LOCK rises this long after dll_rsti falls")
    args = ap.parse_args()
    with open(VO) as f:
        cells, params = cut(f.read())
    with tempfile.TemporaryDirectory() as d:
        tb = os.path.join(d, "tb.v")
        with open(tb, "w") as f:
            f.write(render(cells, params))
        subprocess.run(["iverilog", "-g2012", "-s", "tb", "-o", os.path.join(d, "tb.vvp"),
                        tb, PRIMS], check=True)
        out = subprocess.run(["vvp", "-n", os.path.join(d, "tb.vvp"),
                              f"+lock_after_ns={int(args.lock_after_us * 1000)}"],
                             check=True, capture_output=True, text=True).stdout
    print(f"{len(cells)} cells cut from {os.path.relpath(VO, '/run/media/vash/GIT')}")
    print("pll_stop is the inverse of pll_stop_n; times are 50 MHz cycles from pll_lock (negative: before it)\n")
    last = None
    for line in out.splitlines():
        if line.startswith("$finish") or "finish called" in line:
            continue
        state = line.split("  ", 1)[1] if "  " in line else line
        if state != last:
            print(line)
            last = state
    return 0


if __name__ == "__main__":
    sys.exit(main())
