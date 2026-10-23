#!/usr/bin/env python3
"""Recover which site bits a DQS port's constant selection uses.

A bitstream diff only shows what the router routed, and most DQS inputs are
tied to constants, which the site selects through its own configuration rather
than through a pip. So the way to name them is to change one thing at a time:
build a matched pair that differs only in one port's constant, VCC against GND,
and read which configuration bits move. This is the method that recovered the
DDRDLL's `DLL0` features 12 to 15.

The design is the smallest thing the vendor tool will accept for a lane: a
DDRDLL feeding a DQS's DLLSTEP (Gowin refuses a DQS without one, PR0015), a pad
on DQSIN, and a passthrough output. Pins are fixed in both builds of a pair so
the diff cannot pick up placement noise.

The pad on DQSIN is a DDR3 pad, because a DQS block lives with its byte lane.
That is harmless here -- nothing in this script programs hardware -- and it is
why the shape cannot be used for a probe image.

Usage:
    tools/dqs_port_probe.py --ports RESET,RLOADN
    tools/dqs_port_probe.py            # every single-bit control input
"""

import argparse
import os
import shutil
import subprocess
import sys

GOWIN = os.environ.get("GOWINHOME", "/home/vash/tools/gowin-1.9.11.03")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#: Single-bit DQS control inputs.  A bus is handled a bit at a time by naming
#: the element, e.g. READ[0].
CONTROL_PORTS = ["RESET", "RLOADN", "RMOVE", "RDIR",
                 "WLOADN", "WMOVE", "WDIR", "HOLD"]

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

TEMPLATE = """\
`default_nettype none
module top (input wire clk, input wire dqsi, output wire q);
    wire [7:0] step;
    wire [2:0] rp, wp;
    wire r90, w0, w270, rv, rb, rf, wf, unused;

    DDRDLL #(.DLL_FORCE("FALSE"), .CODESCAL("111"),
             .SCAL_EN("FALSE"), .DIV_SEL(1'b0)) dll (
        .CLKIN(clk), .STOP(1'b1), .UPDNCNTL(1'b1), .RESET(1'b0),
        .STEP(step));

    DQS #(.FIFO_MODE_SEL(1'b0), .RD_PNTR(3'b000),
          .DQS_MODE("X4"), .HWL("true")) u (
        .DQSIN(dqsi), .PCLK(clk), .FCLK(clk),
        .RESET({RESET}), .READ(4'b0000), .RCLKSEL(3'b000),
        .DLLSTEP(step), .WSTEP(8'h00),
        .RLOADN({RLOADN}), .RMOVE({RMOVE}), .RDIR({RDIR}),
        .WLOADN({WLOADN}), .WMOVE({WMOVE}), .WDIR({WDIR}), .HOLD({HOLD}),
        .DQSR90(r90), .DQSW0(w0), .DQSW270(w270),
        .RPOINT(rp), .WPOINT(wp),
        .RVALID(rv), .RBURST(rb), .RFLAG(rf), .WFLAG(wf));

    assign unused = 1'b0;
    assign q = dqsi ^ r90 ^ w0 ^ w270 ^ rv ^ rb ^ rf ^ wf ^ ^rp ^ ^wp;
endmodule
`default_nettype wire
"""


def write_pair(outdir: str, port: str):
    for level in ("1'b1", "1'b0"):
        name = "vcc" if level == "1'b1" else "gnd"
        d = os.path.join(outdir, name)
        os.makedirs(d, exist_ok=True)
        source = TEMPLATE
        for p in CONTROL_PORTS:
            if p != port:                      # the target keeps its placeholder
                source = source.replace("{" + p + "}", "1'b0")
        source = source.replace("{" + port + "}", level)
        for fn, body in (("top.v", source), ("top.cst", CST),
                         ("top.sdc", SDC), ("run.tcl", TCL)):
            with open(os.path.join(d, fn), "w") as f:
                f.write(body)
    return os.path.join(outdir, "vcc"), os.path.join(outdir, "gnd")


def build(d: str) -> bool:
    env = dict(os.environ)
    env["QT_QPA_PLATFORM"] = "offscreen"
    env["LD_PRELOAD"] = "/usr/lib/x86_64-linux-gnu/libfreetype.so.6"
    with open(os.path.join(d, "gw_sh.log"), "w") as log:
        rc = subprocess.call([os.path.join(GOWIN, "IDE/bin/gw_sh"), "run.tcl"],
                             cwd=d, env=env, stdout=log, stderr=subprocess.STDOUT)
    return rc == 0 and os.path.exists(os.path.join(d, "impl/pnr/probe.fs"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ports", default=",".join(CONTROL_PORTS))
    ap.add_argument("--out", default=os.path.join(ROOT, "build/dqs_ports"))
    args = ap.parse_args()

    ports = [p for p in args.ports.split(",") if p]
    if not os.path.isdir(os.path.join(GOWIN, "IDE")):
        print(f"missing Gowin EDA at {GOWIN}", file=sys.stderr)
        return 2

    for port in ports:
        outdir = os.path.join(args.out, port.replace("[", "_").replace("]", ""))
        if os.path.isdir(outdir):
            shutil.rmtree(outdir)
        vcc, gnd = write_pair(outdir, port)
        ok = build(vcc) and build(gnd)
        print(f"{port}: {'built' if ok else 'FAILED'}")
        if not ok:
            return 1
    print(f"\nBuilt {len(ports)} matched pairs under {args.out}.")
    print("Diff each pair's impl/pnr/probe.fs to read that port's site bits.")
    print("Hardware was not accessed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
