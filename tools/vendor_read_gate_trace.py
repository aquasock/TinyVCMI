#!/usr/bin/env python3
"""Trace the proven DDR3 controller's per-READ DQS gate from its netlist.

Each of the vendor PHY's four lanes drives its own DQS `READ[3:0]`
(`u_ddr_phy_top/read [4n+3:4n]`) from a registered mux over the read-command
pipeline (`read_line1..3` and later taps), selected by that lane's 4-bit
`read_calibration_logic_gen[n].read_i` and its `read_adj`.  Tang-PSX keeps the
post-place-and-route netlist, so this tool cuts lane 0's `READ` cone back to
those taps and selectors -- 19 cells -- and simulates it with Gowin's own
primitive models: for every `read_adj` and `read_i` it issues one READ into
the pipeline and prints `READ[3:0]` (bit 3 first) for ten PCLK.

Usage:
    tools/vendor_read_gate_trace.py
"""

import os
import re
import subprocess
import sys
import tempfile

VO = "/run/media/vash/GIT/Tang-PSX/build/gate1-ip/ddr3_memory_interface/ddr3_memory_interface.vo"
GOWIN = os.environ.get("GOWINHOME", "/home/vash/tools/gowin-1.9.11.03")
PRIMS = os.path.join(GOWIN, "IDE/simlib/gw5a/prim_sim.v")

P = "\\gw3_top/u_ddr_phy_top/"
L = P + "u_ddr_init/read_calibration_logic_gen[0]."
STOP = {P + "u_ddr_phy_wds/u_ddr_phy_cmd_lane/read_line0": "rl0",
        P + "read_line1": "rl1", P + "read_line2": "rl2", P + "read_line3": "rl3",
        L + "read_i [0]": "ri[0]", L + "read_i [1]": "ri[1]",
        L + "read_i [2]": "ri[2]", L + "read_i [3]": "ri[3]",
        P + "read_calibration_logic_gen[0].read_adj": "radj",
        "clk_out": "clk", "ddr_rst": "rst", "VCC": "1'b1", "GND": "1'b0"}
OUTPUTS = [P + f"read [{i}]" for i in range(4)]

INST = re.compile(r"^(\w+) (\\\S+ |\w+)\s*\((.*?)\n\);", re.M | re.S)
PORT = re.compile(r"\.(\w+)\(\s*(.*?)\s*\)\s*(?=,\s*\n|\n|$)")
DEFP = re.compile(r"^defparam (\\\S+ )\.(\w+)=(.*?);", re.M)


def is_out(port: str) -> bool:
    return port in ("Q", "F", "O", "COUT", "SUM")


def cut(text: str):
    params, cells, driver = {}, {}, {}
    for m in DEFP.finditer(text):
        params.setdefault(m.group(1), []).append((m.group(2), m.group(3)))
    for m in INST.finditer(text):
        ports = {p: n.strip() for p, n in PORT.findall(m.group(3))}
        cells[m.group(2)] = (m.group(1), ports)
        for p, n in ports.items():
            if is_out(p):
                driver[n] = m.group(2)
    picked, seen, loose = [], set(), set()

    def walk(net):
        if net in STOP:
            return
        c = driver.get(net)
        if c is None:
            loose.add(net)
            return
        if c in seen:
            return
        seen.add(c)
        picked.append(c)
        for p, n in cells[c][1].items():
            if not is_out(p):
                walk(n)

    for o in OUTPUTS:
        walk(o)
    if loose:
        raise SystemExit(f"cut has undriven inputs: {sorted(loose)}")
    return [(cells[c][0], c, cells[c][1]) for c in picked], params


def render(cells, params) -> str:
    names = {}

    def ident(net):
        return STOP.get(net) or names.setdefault(net, f"n{len(names)}")

    body = []
    for i, (typ, name, ports) in enumerate(cells):
        body.append(f"    {typ} c{i} (" + ", ".join(f".{p}({ident(n)})" for p, n in ports.items()) + ");")
        for k, v in params.get(name, []):
            body.append(f"    defparam c{i}.{k} = {v};")
    rd = [ident(o) for o in OUTPUTS]
    decl = "\n".join(f"    wire {n};" for n in sorted(set(names.values())))
    return f"""`timescale 1ns/1ps
module tb;
    reg clk = 1'b0, rst = 1'b1, rl0 = 1'b0, rl1 = 1'b0, rl2 = 1'b0, rl3 = 1'b0, radj = 1'b0;
    reg [3:0] ri = 4'd0;
    always #5 clk = ~clk;
    GSR GSR (.GSRI(1'b1));
{decl}
{chr(10).join(body)}
    integer a, v, c;
    initial begin
        #22 rst = 1'b0;
        for (a = 0; a < 2; a = a + 1) for (v = 0; v < 16; v = v + 1) begin
            radj = a; ri = v; rl0 = 0; rl1 = 0; rl2 = 0; rl3 = 0;
            repeat (8) @(posedge clk);
            $write("read_adj %0d read_i %2d :", a, v);
            for (c = 0; c < 10; c = c + 1) begin
                @(posedge clk); #1;
                rl0 <= (c == 0); rl1 <= rl0; rl2 <= rl1; rl3 <= rl2;
                $write(" %b%b%b%b", {rd[3]}, {rd[2]}, {rd[1]}, {rd[0]});
            end
            $write("\\n");
        end
        $finish;
    end
endmodule
"""


def main() -> int:
    with open(VO) as f:
        cells, params = cut(f.read())
    with tempfile.TemporaryDirectory() as d:
        tb = os.path.join(d, "tb.v")
        with open(tb, "w") as f:
            f.write(render(cells, params))
        subprocess.run(["iverilog", "-g2012", "-s", "tb", "-o", os.path.join(d, "tb.vvp"),
                        tb, PRIMS], check=True, capture_output=True)
        out = subprocess.run(["vvp", "-n", os.path.join(d, "tb.vvp")],
                             check=True, capture_output=True, text=True).stdout
    print(f"{len(cells)} cells cut from {os.path.relpath(VO, '/run/media/vash/GIT')}")
    print("READ[3:0] of lane 0, bit 3 first, for ten PCLK after one READ enters read_line0\n")
    for line in out.splitlines():
        if line.startswith("read_adj"):
            print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
