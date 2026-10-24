#!/usr/bin/env python3
"""Build matched vendor pairs that expose one DQS output route at a time.

One fixed DQS output drives ``q`` in both members so the block and its
placement stay live.  A second fixed output pin named ``probe`` is driven by
the selected DQS output in ``target/`` and by the already-live, fixed ``dqsi``
pad in ``reference/``.  The selected output is otherwise unused, so a
changed pip at the DQS macro is evidence for that output's source wire.

This tool only builds local Gowin EDA artifacts.  It does not produce or load
a TinyTang core image.

Usage:
    tools/dqs_output_probe.py --outputs RVALID,RPOINT[0]
    tools/dqs_output_probe.py
"""

import argparse
import os
import shutil
import sys

import dqs_port_probe as base


SCALARS = {
    "DQSR90": "r90",
    "DQSW0": "w0",
    "DQSW270": "w270",
    "RVALID": "rv",
    "RBURST": "rb",
    "RFLAG": "rf",
    "WFLAG": "wf",
}
BUSSES = {"RPOINT": ("rp", 3), "WPOINT": ("wp", 3)}
OUTPUTS = list(SCALARS) + [
    f"{name}[{i}]" for name, (_, width) in BUSSES.items()
    for i in range(width)
]

CST = base.CST.replace('IO_LOC "q" F18;', 'IO_LOC "q" W1;') + """\
IO_LOC "probe" Y1;
IO_PORT "probe" IO_TYPE=LVCMOS33 PULL_MODE=NONE;
"""


def output_expr(name: str) -> str:
    if name in SCALARS:
        return SCALARS[name]
    bus, bit = name[:-1].split("[")
    signal, _ = BUSSES[bus]
    return f"{signal}[{int(bit)}]"


def render(source: str, anchor: str) -> str:
    text = base.render("", "")
    text = text.replace(
        "module top (input wire clk, input wire dqsi, output wire q);",
        "module top (input wire clk, input wire dqsi, output wire q, "
        "output wire probe);",
    )
    text = text.replace(
        "    assign q = dqsi ^ r90 ^ w0 ^ w270 ^ rv ^ rb ^ rf ^ wf ^ ^rp ^ ^wp\n"
        "               ^ sig_r ^ sig_s;",
        f"    assign q = dqsi ^ {anchor} ^ sig_r ^ sig_s;",
    )
    text = text.replace(
        "endmodule\n`default_nettype wire",
        f"    assign probe = {source};\nendmodule\n`default_nettype wire",
    )
    return text


def write_pair(root: str, output: str, lane: int = 0):
    # Keep the DQS live through an output other than the one being measured,
    # so the target output has no route at all in the reference member.
    anchor = "r90" if output == "DQSW0" else "w0"
    dirs = []
    for name, source in (("target", output_expr(output)),
                         ("reference", "dqsi")):
        directory = os.path.join(root, name)
        os.makedirs(directory, exist_ok=True)
        for filename, body in (("top.v", render(source, anchor)),
                               ("top.cst", base.lane_cst(lane, CST)),
                               ("top.sdc", base.SDC), ("run.tcl", base.TCL)):
            with open(os.path.join(directory, filename), "w") as stream:
                stream.write(body)
        dirs.append(directory)
    return dirs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outputs", help="comma-separated; defaults to all")
    parser.add_argument("--out", default=None)
    parser.add_argument("--lane", type=int, choices=sorted(base.LANES), default=0,
                        help="DDR3 lane whose strobe pin the DQSIN pad takes")
    args = parser.parse_args()
    if args.out is None:
        args.out = base.lane_dir(os.path.join(base.ROOT, "build/dqs_outputs"), args.lane)

    outputs = [name for name in (args.outputs or ",".join(OUTPUTS)).split(",")
               if name]
    unknown = [name for name in outputs if name not in OUTPUTS]
    if unknown:
        print(f"unknown output(s): {unknown}; known: {OUTPUTS}", file=sys.stderr)
        return 2
    if not os.path.isdir(os.path.join(base.GOWIN, "IDE")):
        print(f"missing Gowin EDA at {base.GOWIN}", file=sys.stderr)
        return 2

    for output in outputs:
        root = os.path.join(args.out,
                            output.replace("[", "_").replace("]", ""))
        if os.path.isdir(root):
            shutil.rmtree(root)
        ok = all(base.build(directory) for directory in write_pair(root, output, args.lane))
        print(f"{output}: {'built' if ok else 'FAILED'}")
        if not ok:
            return 1

    print(f"\nBuilt {len(outputs)} matched pairs under {args.out}.")
    print("Hardware was not accessed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
