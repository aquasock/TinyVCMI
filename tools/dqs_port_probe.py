#!/usr/bin/env python3
"""Recover which site wires and site bits a `DQS` port's source uses.

A bitstream diff only shows what changed between two builds, so the way to
name a pin is to change one thing at a time.  This script builds that pair:
every port held at a fixed value except one, so the diff between the two
members can only be that port's selection.

Probe modes:

`--mode const` (the original experiment)
    VCC against GND on one port.  A constant source is chosen by the site's
    own configuration, not by a pip, so the diff reads the port's *site bits*.
    This is the method that recovered the `DDRDLL`'s `DLL0` features 12 to 15,
    and it produced the per-port bit sets in `docs/ddr3-open-flow.md`.

`--mode routed`
    A plain fabric net against a constant on one port.  Here the source is a
    routed wire, so the diff reads the port's *destination wire in the site
    tile* -- which is the `portmap` entry a bel needs.  `sig_r` is a
    free-running register driven from `clk`; it exists in both members of the
    pair and reaches `q` in both, so it is never trimmed and the only
    difference between the two builds is where the target port takes its
    source from.

`--mode swap`
    Two fabric registers, both live.  Some pins cannot take
    a constant: tie a clock or a reset down and the vendor tool demotes the
    block, which shows up as a diff across every destination in the tile
    (`PCLK` 93 changed fuses, `RESET` 72, against 6 to 10 for the live
    pairs).  Swapping two live sources measures the same portmap entry
    without giving the tool a reason to redraw the block.

`--mode clock`
    A fabric register against the live board clock.  This gives `PCLK` and
    `RESET` two structurally different live sources: unlike a constant, the
    clock does not demote the DQS block, and unlike the two fabric registers
    in `swap` it may require a different selection at the site's destination
    mux.  This mode exists only to resolve those two controls.

The design is the smallest thing the vendor tool will accept for a lane: a
DDRDLL feeding a DQS's DLLSTEP (Gowin refuses a DQS without one, PR0015), a
pad on DQSIN, and a passthrough output.  Pins are fixed in both builds of a
pair so the diff cannot pick up placement noise.

The pad on DQSIN is a DDR3 pad, because a DQS block lives with its byte lane.
That is harmless here -- nothing in this script programs hardware -- and it is
why the shape cannot be used for a probe image.

`DLLSTEP` is deliberately not probeable: its only legal source is a DDRDLL's
`STEP`, so there is no second source to compare against.  That link is
hard-wired and is modelled with `create_internal_net()`, not with pips.

Usage:
    tools/dqs_port_probe.py --mode const --ports RESET,RLOADN
    tools/dqs_port_probe.py --mode routed --ports RCLKSEL[0],READ[0]
    tools/dqs_port_probe.py --mode routed          # every probeable input
    tools/dqs_port_probe.py --mode clock --ports PCLK,RESET

The pair directories are `routed/` and `const/` in routed mode, `vcc/` and
`gnd/` in const mode.  `tools/fs_site_diff.py` reads either pair.
"""

import argparse
import os
import shutil
import subprocess
import sys

GOWIN = os.environ.get("GOWINHOME", "/home/vash/tools/gowin-1.9.11.03")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#: Scalars are named directly; a bus is named one bit at a time, e.g.
#: `READ[0]`.  Every name here has a matching `@NAME@` placeholder in the
#: template, and every placeholder defaults to `1'b0`.
SCALARS = ["DQSIN", "PCLK", "FCLK", "RESET",
           "RLOADN", "RMOVE", "RDIR", "WLOADN", "WMOVE", "WDIR", "HOLD"]
BUSSES = {"READ": 4, "RCLKSEL": 3, "WSTEP": 8}

PROBES = SCALARS + [f"{bus}[{i}]" for bus, n in BUSSES.items() for i in range(n)]

#: The original experiment's subset: the single-bit control inputs that were
#: probed against constants.
CONTROL_PORTS = ["RESET", "RLOADN", "RMOVE", "RDIR",
                 "WLOADN", "WMOVE", "WDIR", "HOLD"]

MODES = {
    "const": ("vcc", "1'b1", "gnd", "1'b0"),
    "routed": ("routed", "sig_r", "const", "1'b0"),
    # `swap` keeps both members live: two separate fabric registers.  A
    # constant is not a legal source for a clock or a reset -- tying one of
    # those down makes the vendor tool demote the whole block, so its pair
    # differs in every destination of the tile and says nothing about the pin
    # (measured: `PCLK` 93 changed fuses, `RESET` 72, against 6 to 10 for the
    # live pairs).  The DQS pad cannot be the second source either: it is
    # already on DQSIN, and the tool refuses to let one DQS buffer drive two
    # (`CK3001`).
    "swap": ("fab", "sig_r", "fab2", "sig_s"),
    "clock": ("fabric", "sig_r", "clock", "clk"),
}

TCL = """\
set_device GW5AST-LV138PG484AC1/I0 -device_version C
add_file -type verilog top.v
add_file -type cst top.cst
add_file -type sdc top.sdc
set_option -top_module top
set_option -output_base_name probe
set_option -verilog_std v2001
set_option -timing_driven 1
set_option -use_cpu_as_gpio 1
set_option -bit_compress 0
run all
"""

CST = """\
IO_LOC "clk" V22;
IO_PORT "clk" IO_TYPE=LVCMOS33 PULL_MODE=NONE;
IO_LOC "dqsi" Y3;
IO_PORT "dqsi" IO_TYPE=LVCMOS33 PULL_MODE=NONE;
IO_LOC "q" F18;
IO_PORT "q" IO_TYPE=LVCMOS33 PULL_MODE=NONE;
INS_LOC "dll" DDRDLLM_BL;
"""

SDC = "create_clock -name clk -period 20.000 [get_ports {clk}]\n"

#: The four DDR3 lanes of the hardware-proven controller (Tang-PSX
#: `tang_psx_ddr3.cst`) as located by TinyVCMI TOOL-011: the strobe pin, the
#: `DQS` site tile and the byte group's table-58 cell, both as (row, col).
LANES = {
    0: {"pin": "Y3", "site": (81, 5), "byte_group": (72, 0)},
    1: {"pin": "V9", "site": (99, 0), "byte_group": (99, 0)},
    2: {"pin": "W6", "site": (90, 0), "byte_group": (90, 0)},
    3: {"pin": "R3", "site": (81, 6), "byte_group": (63, 0)},
}


def lane_cst(lane: int, cst: str = None) -> str:
    """`cst` (default `CST`) with the strobe pad moved to `lane`'s pin."""
    cst = CST if cst is None else cst
    out = cst.replace('IO_LOC "dqsi" Y3;', f'IO_LOC "dqsi" {LANES[lane]["pin"]};')
    if out == cst and lane != 0:
        raise SystemExit("constraints changed: dqsi pin not found")
    return out


def lane_dir(path: str, lane: int) -> str:
    """Lane 0 keeps the original build directories; lane n gets `_l<n>`."""
    return path if lane == 0 else f"{path}_l{lane}"


def _bus(name: str, n: int) -> str:
    """`{@READ3@, @READ2@, ...}`, most significant bit first."""
    return "{" + ", ".join("@" + name + str(i) + "@" for i in reversed(range(n))) + "}"


TEMPLATE = """\
`default_nettype none
module top (input wire clk, input wire dqsi, output wire q);
    wire [7:0] step;
    wire [2:0] rp, wp;
    wire r90, w0, w270, rv, rb, rf, wf, unused;

    // Two plain fabric sources for the swapped pairs: each pair uses two of
    // these so both members stay live.  They are registered so a port under
    // test can never close a combinational loop through the DQS, and both are
    // XORed into `q` so neither is ever trimmed.
    reg sig_r = 1'b0;
    reg sig_s = 1'b0;
    always @(posedge clk) sig_r <= ~sig_r;
    always @(posedge clk) sig_s <= sig_r ^ sig_s;

    DDRDLL #(.DLL_FORCE("FALSE"), .CODESCAL("111"),
             .SCAL_EN("FALSE"), .DIV_SEL(1'b0)) dll (
        .CLKIN(clk), .STOP(1'b1), .UPDNCNTL(1'b1), .RESET(1'b0),
        .STEP(step));

    DQS #(.FIFO_MODE_SEL(1'b0), .RD_PNTR(3'b000),
          .DQS_MODE("X4"), .HWL("true")) u (
        .DQSIN(@DQSIN@), .PCLK(@PCLK@), .FCLK(@FCLK@),
        .RESET(@RESET@), .READ(@READ@), .RCLKSEL(@RCLKSEL@),
        .DLLSTEP(step), .WSTEP(@WSTEP@),
        .RLOADN(@RLOADN@), .RMOVE(@RMOVE@), .RDIR(@RDIR@),
        .WLOADN(@WLOADN@), .WMOVE(@WMOVE@), .WDIR(@WDIR@), .HOLD(@HOLD@),
        .DQSR90(r90), .DQSW0(w0), .DQSW270(w270),
        .RPOINT(rp), .WPOINT(wp),
        .RVALID(rv), .RBURST(rb), .RFLAG(rf), .WFLAG(wf));

    assign unused = 1'b0;
    assign q = dqsi ^ r90 ^ w0 ^ w270 ^ rv ^ rb ^ rf ^ wf ^ ^rp ^ ^wp
               ^ sig_r ^ sig_s;
endmodule
`default_nettype wire
""".replace("@READ@", _bus("READ", 4)) \
   .replace("@RCLKSEL@", _bus("RCLKSEL", 3)) \
   .replace("@WSTEP@", _bus("WSTEP", 8))


#: Everything the pair does not vary keeps the sanest possible source, so the
#: DQS still looks like a lane: a pad on DQSIN and the board clock on both
#: clock inputs.  The original constant experiment used the same base.
BASE = {"DQSIN": "dqsi", "PCLK": "clk", "FCLK": "clk"}


def render(port: str, source: str) -> str:
    """Template with every probe placeholder resolved; `port` gets `source`."""
    values = {p: BASE.get(p, "1'b0") for p in SCALARS}
    for bus, n in BUSSES.items():
        for i in range(n):
            values[f"{bus}[{i}]"] = "1'b0"
    if port:
        values[port] = source
    source_text = TEMPLATE
    for name, value in values.items():
        source_text = source_text.replace("@" + name.replace("[", "").replace("]", "") + "@", value)
    missing = [n for n in ("DQSIN", "PCLK", "FCLK", "RESET") if "@" + n + "@" in source_text]
    if missing:
        raise SystemExit(f"template left {missing} unsubstituted")
    return source_text


def write_pair(outdir: str, port: str, mode: str, lane: int = 0):
    """Write the two members of one matched pair; return their directories."""
    first, first_source, second, second_source = MODES[mode]
    dirs = []
    for name, source in ((first, first_source), (second, second_source)):
        d = os.path.join(outdir, name)
        os.makedirs(d, exist_ok=True)
        for fn, body in (("top.v", render(port, source)), ("top.cst", lane_cst(lane)),
                         ("top.sdc", SDC), ("run.tcl", TCL)):
            with open(os.path.join(d, fn), "w") as f:
                f.write(body)
        dirs.append(d)
    return dirs


def build(d: str) -> bool:
    env = dict(os.environ)
    env["QT_QPA_PLATFORM"] = "offscreen"
    env["LD_PRELOAD"] = "/usr/lib/x86_64-linux-gnu/libfreetype.so.6"
    with open(os.path.join(d, "gw_sh.log"), "w") as log:
        rc = subprocess.call([os.path.join(GOWIN, "IDE/bin/gw_sh"), "run.tcl"],
                             cwd=d, env=env, stdout=log, stderr=subprocess.STDOUT)
    return rc == 0 and os.path.exists(os.path.join(d, "impl/pnr/probe.fs"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mode", choices=sorted(MODES), default="const")
    ap.add_argument("--ports", default=None,
                    help="comma-separated; defaults to the control inputs in "
                         "const mode and to every probeable input in routed mode")
    ap.add_argument("--out", default=None,
                    help="defaults to build/dqs_ports in const mode and "
                         "build/dqs_routed in routed mode")
    ap.add_argument("--lane", type=int, choices=sorted(LANES), default=0,
                    help="DDR3 lane whose strobe pin the DQSIN pad takes; lane n > 0 "
                         "builds into the default directory with an `_l<n>` suffix")
    args = ap.parse_args()

    default_ports = CONTROL_PORTS if args.mode == "const" else PROBES
    ports = [p for p in (args.ports or ",".join(default_ports)).split(",") if p]
    unknown = [p for p in ports if p not in PROBES]
    if unknown:
        print(f"unknown port(s): {unknown}; known: {PROBES}", file=sys.stderr)
        return 2

    out = args.out or lane_dir(os.path.join(
        ROOT, {"const": "build/dqs_ports",
               "routed": "build/dqs_routed",
               "swap": "build/dqs_swap",
               "clock": "build/dqs_clock"}[args.mode]), args.lane)
    if not os.path.isdir(os.path.join(GOWIN, "IDE")):
        print(f"missing Gowin EDA at {GOWIN}", file=sys.stderr)
        return 2

    for port in ports:
        outdir = os.path.join(out, port.replace("[", "_").replace("]", ""))
        if os.path.isdir(outdir):
            shutil.rmtree(outdir)
        pair = write_pair(outdir, port, args.mode, args.lane)
        ok = all(build(d) for d in pair)
        print(f"{port}: {'built' if ok else 'FAILED'}")
        if not ok:
            return 1
    first, _, second, _ = MODES[args.mode]
    print(f"\nBuilt {len(ports)} matched pairs under {out}.")
    print(f"Diff each pair's {first}/ against {second}/ to read that port's selection.")
    print("Hardware was not accessed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
