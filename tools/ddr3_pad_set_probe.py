#!/usr/bin/env python3
"""Build the vendor design that carries the whole DDR3 controller's pad set.

One design with every pad the hardware-proven controller uses (Tang-PSX
`tang_psx_ddr3.cst`), in the shapes of its vendor netlist:

* one `DDRDLL` on `DDRDLLM_BL`, its `STEP` on all four `DQS` blocks;
* per lane: the `ELVDS_IOBUF` strobe pair feeding `DQS.DQSIN` and driven by
  an `OSER8_MEM` on `DQSW270`; eight DQ `IOBUF`s, each driven by an
  `OSER8_MEM` on `DQSW0` and read through a static `IODELAY` by an
  `IDES8_MEM` on `DQSR90`, `WPOINT` and `RPOINT`; one DM `TBUF` driven by an
  `OSER8_MEM`;
* bank 7: `tools/cmd_pad_probe.py`'s address, bank, command, clock and
  `reset_n` shapes on all 28 balls.

Every pad is `SSTL15`/`SSTL15D` at `BANK_VCCIO=1.5`.  `PCLK` and `FCLK` are
the board clock, as in the other probes, so the HCLK lane the two routers
pick may differ and the lane fields are compared apart.  The design is built
offline by Gowin EDA, compared by `tools/ddr_bank_check.py`,
`tools/dq_pack_check.py` and `tools/dqs_pack_check.py`, and never loaded onto
the board.

Usage:
    tools/ddr3_pad_set_probe.py
"""

import argparse
import os
import shutil
import sys

import cmd_pad_probe as cmd
import dqs_port_probe as base

#: per lane: strobe pair, dq[8n .. 8n+7], dm[n]
LANES = {
    0: (("Y3", "AA3"), ["Y4", "AB3", "AA5", "V4", "AA1", "AB2", "AB5", "AB1"], "AA4"),
    1: (("V9", "V8"), ["AA8", "Y8", "AB7", "Y7", "AB8", "W9", "AB6", "Y9"], "V7"),
    2: (("W6", "W5"), ["U5", "R6", "U6", "R4", "Y6", "T4", "V5", "T5"], "T6"),
    3: (("R3", "R2"), ["W2", "Y1", "T1", "U3", "U2", "V2", "U1", "Y2"], "W1"),
}

OSER = """\
    wire {n}_o, {n}_t;
    OSER8_MEM #(.HWL("false"), .TCLK_SOURCE({src}), .TXCLK_POL(1'b0)) {n}_ser (
        .D0(sig[0]), .D1(sig[1]), .D2(sig[2]), .D3(sig[3]),
        .D4(sig[4]), .D5(sig[5]), .D6(sig[6]), .D7(sig[7]),
        .TX0(sig[1]), .TX1(sig[2]), .TX2(sig[3]), .TX3(sig[4]),
        .PCLK(clk), .FCLK(clk), .TCLK({tclk}), .RESET(1'b0),
        .Q0({n}_o), .Q1({n}_t));
"""

LANE = """\
    wire dqsi_{l}, r90_{l}, w0_{l}, w270_{l}, rv_{l}, rb_{l}, rf_{l}, wf_{l};
    wire [2:0] rp_{l}, wp_{l};
    DQS #(.FIFO_MODE_SEL(1'b0), .RD_PNTR(3'b000), .DQS_MODE("X4"), .HWL("true")) dqs_{l} (
        .DQSIN(dqsi_{l}), .PCLK(clk), .FCLK(clk),
        .RESET(1'b0), .READ(4'b0000), .RCLKSEL(3'b000), .DLLSTEP(step), .WSTEP(8'h00),
        .RLOADN(1'b0), .RMOVE(1'b0), .RDIR(1'b0),
        .WLOADN(1'b0), .WMOVE(1'b0), .WDIR(1'b0), .HOLD(1'b0),
        .DQSR90(r90_{l}), .DQSW0(w0_{l}), .DQSW270(w270_{l}),
        .RPOINT(rp_{l}), .WPOINT(wp_{l}),
        .RVALID(rv_{l}), .RBURST(rb_{l}), .RFLAG(rf_{l}), .WFLAG(wf_{l}));
"""

DQ = """\
    wire dq{i}_i, dq{i}_d;
    wire [7:0] dq{i}_q;
    IOBUF dq{i}_buf (.I(dq{i}_o), .OEN(dq{i}_t), .IO(ddr_dq[{i}]), .O(dq{i}_i));
    IODELAY #(.C_STATIC_DLY(5), .DYN_DLY_EN("FALSE"), .ADAPT_EN("FALSE")) dq{i}_delay (
        .DI(dq{i}_i), .SDTAP(1'b0), .VALUE(1'b0), .DLYSTEP(8'h00), .DO(dq{i}_d), .DF());
    IDES8_MEM dq{i}_des (.D(dq{i}_d), .ICLK(r90_{l}), .PCLK(clk), .FCLK(clk),
        .RESET(1'b0), .CALIB(1'b0), .WADDR(wp_{l}), .RADDR(rp_{l}),
        .Q0(dq{i}_q[0]), .Q1(dq{i}_q[1]), .Q2(dq{i}_q[2]), .Q3(dq{i}_q[3]),
        .Q4(dq{i}_q[4]), .Q5(dq{i}_q[5]), .Q6(dq{i}_q[6]), .Q7(dq{i}_q[7]));
"""


def render() -> str:
    ports = ["input wire clk", "output wire q", "inout wire [31:0] ddr_dq",
             # scalar strobe ports: nextpnr leaves the N half of a bused
             # differential port unconstrained
             ] + [f"inout wire ddr_dqs{l}_p, inout wire ddr_dqs{l}_n" for l in LANES] + [
             "output wire [3:0] ddr_dm", "output wire ddr_ck_p", "output wire ddr_ck_n",
             "output wire ddr_reset_n"] + [f"output wire {p}" for p, _ in cmd.CMD_BALLS]
    out = ["`default_nettype none", "module top (" + ", ".join(ports) + ");",
           "    reg [7:0] sig = 8'h01;",
           "    always @(posedge clk) sig <= {sig[6:0], sig[7]};",
           "    wire [7:0] step;",
           "    DDRDLL #(.DLL_FORCE(\"FALSE\"), .CODESCAL(\"111\"), .SCAL_EN(\"FALSE\"), .DIV_SEL(1'b0)) dll (",
           "        .CLKIN(clk), .STOP(1'b1), .UPDNCNTL(1'b1), .RESET(1'b0), .STEP(step));"]
    keep = ["^sig", "^step"]
    for l in LANES:
        out.append(LANE.format(l=l))
        out.append(OSER.format(n=f"st{l}", src='"DQSW270"', tclk=f"w270_{l}"))
        out.append(f"    ELVDS_IOBUF st{l}_buf (.I(st{l}_o), .OEN(st{l}_t), "
                   f".IO(ddr_dqs{l}_p), .IOB(ddr_dqs{l}_n), .O(dqsi_{l}));")
        for k in range(8):
            i = 8 * l + k
            out.append(OSER.format(n=f"dq{i}", src='"DQSW"', tclk=f"w0_{l}"))
            out.append(DQ.format(i=i, l=l))
            keep.append(f"^dq{i}_q")
        out.append(OSER.format(n=f"dm{l}", src='"DQSW"', tclk=f"w0_{l}"))
        out.append(f"    TBUF dm{l}_buf (.I(dm{l}_o), .OEN(dm{l}_t), .O(ddr_dm[{l}]));")
        keep += [f"rv_{l}", f"rb_{l}", f"rf_{l}", f"wf_{l}"]
    out.append("    reg rst_r = 1'b0;")
    out.append("    always @(posedge clk) rst_r <= 1'b1;")
    out.append("    OBUF reset_buf (.I(rst_r), .O(ddr_reset_n));")
    out.append("    wire ck_o;")
    out.append(cmd.OSER8.replace("@N@", "ck").replace("@D0@", "1'b0").replace("@D1@", "1'b1"))
    out.append("    ELVDS_OBUF ck_buf (.I(ck_o), .O(ddr_ck_p), .OB(ddr_ck_n));")
    for i, (p, _) in enumerate(cmd.CMD_BALLS):
        out.append(f"    wire {p}_o;")
        out.append(cmd.OSER8.replace("@N@", p).replace("@D0@", f"sig[{i % 8}]")
                   .replace("@D1@", f"sig[{(i + 3) % 8}]"))
        out.append(f"    OBUF {p}_buf (.I({p}_o), .O({p}));")
    out.append("    assign q = " + " ^ ".join(keep) + ";")
    out.append("endmodule")
    return "\n".join(out) + "\n"


def cst() -> str:
    single = "IO_TYPE=SSTL15 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=1.5"
    diff = "IO_TYPE=SSTL15D PULL_MODE=NONE DRIVE=8 BANK_VCCIO=1.5"
    lines = ['IO_LOC "clk" V22;', 'IO_PORT "clk" IO_TYPE=LVCMOS33 PULL_MODE=NONE;',
             'IO_LOC "q" F18;', 'IO_PORT "q" IO_TYPE=LVCMOS33 PULL_MODE=NONE;',
             'INS_LOC "dll" DDRDLLM_BL;']
    for l, (strobe, dq, dm) in LANES.items():
        lines += [f'IO_LOC "ddr_dqs{l}_p" {strobe[0]},{strobe[1]};',
                  f'IO_PORT "ddr_dqs{l}_p" {diff};',
                  f'IO_LOC "ddr_dm[{l}]" {dm};', f'IO_PORT "ddr_dm[{l}]" {single};']
        for k, pin in enumerate(dq):
            lines += [f'IO_LOC "ddr_dq[{8 * l + k}]" {pin};',
                      f'IO_PORT "ddr_dq[{8 * l + k}]" {single};']
    # bank 7, exactly as tools/cmd_pad_probe.py constrains cmd_full_sstl
    lines += [l for l in cmd.cst([p for p, _ in cmd.CMD_BALLS]).splitlines()
              if '"clk"' not in l and '"q"' not in l]
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(base.ROOT, "build/ddr3_pads/full_sstl"))
    args = ap.parse_args()
    if not os.path.isdir(os.path.join(base.GOWIN, "IDE")):
        print(f"missing Gowin EDA at {base.GOWIN}", file=sys.stderr)
        return 2
    d = args.out
    if os.path.isdir(d):
        shutil.rmtree(d)
    os.makedirs(d)
    for fn, body in (("top.v", render()), ("top.cst", cst()),
                     ("top.sdc", base.SDC), ("run.tcl", base.TCL)):
        with open(os.path.join(d, fn), "w") as f:
            f.write(body)
    ok = base.build(d)
    why = ""
    if not ok:
        with open(os.path.join(d, "gw_sh.log")) as f:
            errors = [l.strip() for l in f if "ERROR" in l]
        why = " -- " + (errors[0] if errors else "no ERROR line in gw_sh.log")
    print(f"{os.path.relpath(d, base.ROOT)}: {'built' if ok else 'REFUSED'}{why}")
    print("\nHardware was not accessed.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
