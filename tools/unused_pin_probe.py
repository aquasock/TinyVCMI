#!/usr/bin/env python3
"""Find what decides whether Gowin programs drive strength on an unused pin.

The Apicula fork drops `DRIVE` and `DRIVE_LEVEL` from every unused GW5AST-138C
pin because its vendor corpus (`P3.T26`, `D108`, built by its fuzz harness)
showed none there.  This project's vendor builds show `DRIVE=8` and
`DRIVE_LEVEL=8` on every unused pin (TOOL-013), and both used Gowin EDA
1.9.11.03.  The two flows differ in how they run `gw_sh` and in their
constraint conventions, so this tool builds one plain design -- a clock in,
a register out, both LVCMOS33 on non-DDR banks -- in each combination:

`t_plain`
    This project's non-project `run.tcl` (`tools/dqs_port_probe.py` TCL) and
    `.cst` (`IO_TYPE=LVCMOS33 PULL_MODE=NONE`).
`t_cst`
    The same `run.tcl` with the harness's `.cst` rules: `PULL_STRENGTH=MEDIUM`
    and a `BANK_VCCIO` on every pin.
`t_proj`
    The harness's project-mode `run.tcl` (`create_project ... -force`, sources
    from `run/`, its option set) with this project's `.cst`.
`t_proj_cst`
    The harness's `run.tcl` and `.cst` together.

`--report` then reads every built bitstream and counts, per bank, the unused
left- and right-edge pins whose IOB table carries an entry naming `DRIVE`.
Nothing here is loaded onto the board.

Usage:
    tools/unused_pin_probe.py            # build all four
    tools/unused_pin_probe.py --report

Run `--report` with the open-flow environment sourced (`tools/openflow_env.sh`).
"""

import argparse
import collections
import glob
import os
import re
import shutil
import sys

import dqs_port_probe as base

OUT = os.path.join(base.ROOT, "build/unused_pin")

VERILOG = """\
`default_nettype none
module top (input wire clk, output wire q);
    reg [3:0] c = 4'd0;
    always @(posedge clk) c <= c + 4'd1;
    assign q = c[3];
endmodule
"""

PLAIN_CST = """\
IO_LOC "clk" V22;
IO_PORT "clk" IO_TYPE=LVCMOS33 PULL_MODE=NONE;
IO_LOC "q" F18;
IO_PORT "q" IO_TYPE=LVCMOS33 PULL_MODE=NONE;
"""

HARNESS_CST = """\
IO_LOC "clk" V22;
IO_PORT "clk" IO_TYPE=LVCMOS33 PULL_MODE=NONE PULL_STRENGTH=MEDIUM BANK_VCCIO=3.3;
IO_LOC "q" F18;
IO_PORT "q" IO_TYPE=LVCMOS33 PULL_MODE=NONE PULL_STRENGTH=MEDIUM BANK_VCCIO=3.3;
"""

#: the Apicula fork's `fuzz/gw5ast138c/harness/oracle.py` `render_tcl`,
#: with its device constants filled in
HARNESS_TCL = """\
create_project -name run -pn GW5AST-LV138PG484AC1/I0 -device_version C -force
set_device -name GW5AST-138C GW5AST-LV138PG484AC1/I0
add_file -type verilog  ../top.v
add_file -type cst      ../top.cst
add_file -type sdc      ../top.sdc
set_option -top_module top
set_option -timing_driven 1
set_option -gen_text_timing_rpt 1
set_option -gen_sdf 1
set_option -gen_verilog_sim_netlist 1
set_option -use_cpu_as_gpio 1
run all
"""

#: name -> (harness run.tcl, harness .cst)
DESIGNS = {"t_plain": (False, False), "t_cst": (False, True),
           "t_proj": (True, False), "t_proj_cst": (True, True)}


def bitstream(d: str):
    """The design's `.fs`, wherever its flow put it."""
    found = sorted(glob.glob(os.path.join(d, "**/impl/pnr/*.fs"), recursive=True))
    return found[0] if found else None


def build(name: str) -> str:
    proj, harness_cst = DESIGNS[name]
    d = os.path.join(OUT, name)
    if os.path.isdir(d):
        shutil.rmtree(d)
    os.makedirs(d)
    files = {"top.v": VERILOG, "top.cst": HARNESS_CST if harness_cst else PLAIN_CST,
             "top.sdc": base.SDC, "run.tcl": HARNESS_TCL if proj else base.TCL}
    for fn, body in files.items():
        with open(os.path.join(d, fn), "w") as f:
            f.write(body)
    if proj:
        # create_project makes run/ and works from there, as the harness does
        os.makedirs(os.path.join(d, "run"), exist_ok=True)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen",
               LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libfreetype.so.6")
    import subprocess
    with open(os.path.join(d, "gw_sh.log"), "w") as log:
        subprocess.call([os.path.join(base.GOWIN, "IDE/bin/gw_sh"), "run.tcl"],
                        cwd=d, env=env, stdout=log, stderr=subprocess.STDOUT)
    fs = bitstream(d)
    return f"{name}: {'built ' + os.path.relpath(fs, base.ROOT) if fs else 'FAILED (see gw_sh.log)'}"


def report(names) -> int:
    import ddr_bank_check as dbc
    import fs_attribute as fa
    import fs_site_diff as fsd

    dev = fsd.chipdb.load_chipdb(fsd.DB)
    grid = fsd.Grid(dev)
    name_of = dbc.namer(dev)
    pins = {"V22", "F18"}
    po = dev.pinout["GW5AST-138C"]["PBGA484A"]
    used = {po[p][0] for p in pins}
    for name in names:
        fs = bitstream(os.path.join(OUT, name))
        if fs is None:
            print(f"== {name}: not built")
            continue
        m = fsd.load_matrix(fs)
        counts = collections.Counter()
        for io, bank in sorted(dev.pin_bank.items()):
            mm = re.fullmatch(r"IO([LR])(\d+)([AB])", io)
            if mm is None or io in used:
                continue
            col = 0 if mm.group(1) == "L" else dev.cols - 1
            row = int(mm.group(2)) - 1 + (mm.group(3) == "B")
            table = dev.longval.get(dev.grid[row][col], {}).get(f"IOB{mm.group(3)}")
            if not table:
                counts[(bank, "no table")] += 1
                continue
            field = set().union(*({tuple(f) for f in v} for v in table.values()))
            state = fa.tile_state(dev, grid, m, (row, col)) & field
            keys = dbc.entries_set(table, state)
            drive = any("DRIVE" in name_of("IOB", k) for k in keys)
            counts[(bank, "drive" if drive else "no drive")] += 1
        del m
        print(f"== {name}: " + ", ".join(f"bank {b} {k} {v}" for (b, k), v in sorted(counts.items())))
    print("\nHardware was not accessed.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", help="comma-separated subset of " + ",".join(DESIGNS))
    ap.add_argument("--report", action="store_true",
                    help="count unused pins with drive entries; build nothing")
    args = ap.parse_args()
    names = [n for n in (args.only or ",".join(DESIGNS)).split(",") if n]
    if args.report:
        return report(names)
    if not os.path.isdir(os.path.join(base.GOWIN, "IDE")):
        print(f"missing Gowin EDA at {base.GOWIN}", file=sys.stderr)
        return 2
    for name in names:
        print(build(name), flush=True)
    print("\nHardware was not accessed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
