#!/usr/bin/env python3
"""Build the vendor designs that expose bank 7's DDR3 address and command pads.

Bank 7 carries the hardware-proven controller's address, bank, command, clock
and reset balls (Tang-PSX `tang_psx_ddr3.cst`), in the shapes its vendor
netlist uses (`ddr3_memory_interface.vo`):

* every address, bank and command ball: a plain `OSER8` (`HWL="false"`,
  `TXCLK_POL=0`) on `PCLK`/`FCLK`, its `Q0` into an `OBUF`;
* the clock pair L3/K3: an `OSER8` with the constant pattern `0101...` into
  an `ELVDS_OBUF`;
* `reset_n` on L6: a fabric register into an `OBUF`, no serializer.

All at `SSTL15`/`SSTL15D`, `PULL_MODE=NONE DRIVE=8 BANK_VCCIO=1.5`, as the
proven controller constrains them.

`cmd_full_sstl` carries all 28 bank-7 balls, the real configuration of the
bank.  `cmd_min_sstl` carries only `ddr_addr[0]` on M1 (IOL35A) and
`ddr_addr[9]` on H5 (IOL20B), each with the other side of its cell unused,
plus the clock pair and `reset_n`.  The open flow's `OSER8` takes both IOLOGIC
halves of a cell, so it cannot yet place the full bank, whose address balls
share cells (M1/L1, J5/H5, ...); `cmd_min_sstl` is the bank-7 design it can
route, and so the one whose pad configuration can be compared.  The designs exist to be compared, fuse for fuse, against
the open packer by `tools/ddr_bank_check.py`.  They are built offline by
Gowin EDA and are never loaded onto the board.

Usage:
    tools/cmd_pad_probe.py
    tools/cmd_pad_probe.py --only cmd_min_sstl
"""

import argparse
import os
import shutil
import sys

import dqs_port_probe as base

#: (port, pin) of every bank-7 ball the proven controller uses,
#: except the clock pair and reset_n, which have shapes of their own
CMD_BALLS = [
    ("ddr_bank_2", "M6"), ("ddr_bank_1", "P2"), ("ddr_bank_0", "P5"),
    ("ddr_addr_15", "R1"), ("ddr_addr_14", "D1"), ("ddr_addr_13", "K1"),
    ("ddr_addr_12", "K4"), ("ddr_addr_11", "H3"), ("ddr_addr_10", "L1"),
    ("ddr_addr_9", "H5"), ("ddr_addr_8", "J5"), ("ddr_addr_7", "J1"),
    ("ddr_addr_6", "G3"), ("ddr_addr_5", "H2"), ("ddr_addr_4", "J2"),
    ("ddr_addr_3", "J4"), ("ddr_addr_2", "G2"), ("ddr_addr_1", "K2"),
    ("ddr_addr_0", "M1"), ("ddr_odt", "M2"), ("ddr_cke", "K6"), ("ddr_we", "M5"),
    ("ddr_cas", "L4"), ("ddr_ras", "L5"), ("ddr_cs", "P4"),
]
CLOCK = ("ddr_ck", "L3", "K3")
RESET = ("ddr_reset_n", "L6")

#: name -> the command balls it carries; both carry the clock and reset_n
DESIGNS = {
    "cmd_full_sstl": [p for p, _ in CMD_BALLS],
    "cmd_min_sstl": ["ddr_addr_0", "ddr_addr_9"],
}

OSER8 = """\
    OSER8 #(.HWL("false"), .TXCLK_POL(1'b0)) @N@_ser (
        .D0(@D0@), .D1(@D1@), .D2(@D0@), .D3(@D1@), .D4(@D0@), .D5(@D1@), .D6(@D0@), .D7(@D1@),
        .TX0(1'b0), .TX1(1'b0), .TX2(1'b0), .TX3(1'b0),
        .PCLK(clk), .FCLK(clk), .RESET(1'b0), .Q0(@N@_o), .Q1());
"""


def render(ports) -> str:
    out = ["`default_nettype none",
           "module top (input wire clk, output wire q, output wire ddr_ck_p, "
           "output wire ddr_ck_n, output wire ddr_reset_n"
           + "".join(f", output wire {p}" for p in ports) + ");",
           "    reg [7:0] sig = 8'h01;",
           "    always @(posedge clk) sig <= {sig[6:0], sig[7]};",
           "    reg rst_r = 1'b0;",
           "    always @(posedge clk) rst_r <= 1'b1;",
           "    OBUF reset_buf (.I(rst_r), .O(ddr_reset_n));",
           "    wire ck_o;",
           OSER8.replace("@N@", "ck").replace("@D0@", "1'b0").replace("@D1@", "1'b1"),
           "    ELVDS_OBUF ck_buf (.I(ck_o), .O(ddr_ck_p), .OB(ddr_ck_n));"]
    for i, p in enumerate(ports):
        out.append(f"    wire {p}_o;")
        out.append(OSER8.replace("@N@", p).replace("@D0@", f"sig[{i % 8}]")
                   .replace("@D1@", f"sig[{(i + 3) % 8}]"))
        out.append(f"    OBUF {p}_buf (.I({p}_o), .O({p}));")
    out.append("    assign q = ^sig;")
    out.append("endmodule")
    return "\n".join(out) + "\n"


def cst(ports) -> str:
    single = "IO_TYPE=SSTL15 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=1.5"
    lines = ['IO_LOC "clk" V22;', 'IO_PORT "clk" IO_TYPE=LVCMOS33 PULL_MODE=NONE;',
             'IO_LOC "q" F18;', 'IO_PORT "q" IO_TYPE=LVCMOS33 PULL_MODE=NONE;',
             f'IO_LOC "ddr_ck_p" {CLOCK[1]},{CLOCK[2]};',
             'IO_PORT "ddr_ck_p" IO_TYPE=SSTL15D PULL_MODE=NONE DRIVE=8 BANK_VCCIO=1.5;',
             f'IO_LOC "{RESET[0]}" {RESET[1]};', f'IO_PORT "{RESET[0]}" {single};']
    pins = dict(CMD_BALLS)
    for p in ports:
        lines += [f'IO_LOC "{p}" {pins[p]};', f'IO_PORT "{p}" {single};']
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", help="comma-separated subset of " + ",".join(DESIGNS))
    ap.add_argument("--out", default=os.path.join(base.ROOT, "build/cmd_pad"))
    args = ap.parse_args()
    names = [n for n in (args.only or ",".join(DESIGNS)).split(",") if n]
    unknown = [n for n in names if n not in DESIGNS]
    if unknown:
        print(f"unknown design(s): {unknown}", file=sys.stderr)
        return 2
    if not os.path.isdir(os.path.join(base.GOWIN, "IDE")):
        print(f"missing Gowin EDA at {base.GOWIN}", file=sys.stderr)
        return 2
    for name in names:
        d = os.path.join(args.out, name)
        if os.path.isdir(d):
            shutil.rmtree(d)
        os.makedirs(d)
        ports = DESIGNS[name]
        for fn, body in (("top.v", render(ports)), ("top.cst", cst(ports)),
                         ("top.sdc", base.SDC), ("run.tcl", base.TCL)):
            with open(os.path.join(d, fn), "w") as f:
                f.write(body)
        ok = base.build(d)
        why = ""
        if not ok:
            with open(os.path.join(d, "gw_sh.log")) as f:
                errors = [l.strip() for l in f if "ERROR" in l]
            why = " -- " + (errors[0] if errors else "no ERROR line in gw_sh.log")
        print(f"{name}: {'built' if ok else 'REFUSED'}{why}", flush=True)
    print("\nHardware was not accessed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
