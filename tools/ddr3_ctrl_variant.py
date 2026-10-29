#!/usr/bin/env python3
"""Render the DDR3 controller image's top with one direction of its I/O
boundary registered on PCLK's falling edge and the other wired straight
through, as before entry 75, for the bisection of TOOL-052.  Diagnostic only:
fpga/ddr3_ctrl/top.v is not touched.

  tools/ddr3_ctrl_variant.py in|out <dir>    writes <dir>/src/top.v

`in` registers only the deserializers' words and RVALID (dq_q, rvalid);
`out` registers only what the serializers and the DQS sample.  It prints the
DFFN and DFFNS counts tools/build_ddr3_ctrl_variant.sh then checks for.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ddr3_write as w  # noqa: E402

INPUTS = {"dq_q", "rvalid"}


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in ("in", "out"):
        print(__doc__, file=sys.stderr)
        return 2
    which, out = sys.argv[1], os.path.join(sys.argv[2], "src")
    keep = [r for r in w.BOUNDARY_REGS if (r[0] in INPUTS) == (which == "in")]
    lines = ["    wire [255:0] dq_io;                 // the deserializers' outputs",
             "    wire [3:0] rvalid_io;"]
    for q, wd, _, _ in w.BOUNDARY_REGS:
        lines.append(f"    wire [{wd - 1}:0] {q};" if wd > 1 else f"    wire {q};")
    for r in w.BOUNDARY_REGS:
        if r not in keep:
            lines.append(f"    assign {r[0]} = {r[2]};       // diagnostic: not registered")
    counts = {}
    for hi in (False, True):
        regs = [r for r in keep if r[3] == hi]
        n = counts[hi] = sum(r[1] for r in regs)
        if not n:
            continue
        s = "hi" if hi else "lo"
        lines += [f"    wire [{n - 1}:0] bnd_{s}_d = {{{', '.join(r[2] for r in regs)}}};",
                  f"    wire [{n - 1}:0] bnd_{s}_q;",
                  f"    assign {{{', '.join(r[0] for r in regs)}}} = bnd_{s}_q;",
                  f"    genvar bnd_{s}_i;",
                  f"    generate for (bnd_{s}_i = 0; bnd_{s}_i < {n}; bnd_{s}_i = bnd_{s}_i + 1)"
                  f" begin : bnd_{s}",
                  f"        bnd_ff #(.INIT(1'b{int(hi)})) ff (.CLK(pclk), .D(bnd_{s}_d[bnd_{s}_i]),"
                  f" .Q(bnd_{s}_q[bnd_{s}_i]));",
                  "    end endgenerate"]
    w.BOUNDARY = "\n".join(lines)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "top.v"), "w") as f:
        f.write(w.render(ctrl=True))
    print(f"{which}: registered {', '.join(r[0] for r in keep)}; "
          f"DFFN {counts[False]}, DFFNS {counts[True]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
