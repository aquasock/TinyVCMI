#!/usr/bin/env python3
"""Generate, check and vendor-build the DDR3 write image's source.

The image is `tools/ddr3_mpr.py`'s PHY with the write side switched on: write
leveling, writes of a fixed pattern across one row, and reads back.
`fpga/ddr3_write/wr_core.v` holds the sequencing, the commands, the capture
and the TinyTang responder; this tool generates `top.v`, the PHY around it.
It differs from the MPR image's in these ways only:

* each `DQS` takes its lane's `WSTEP` and `RMOVE` from the core and the
  shared `WLOADN`, as the proven controller drives them (`WMOVE` and `WDIR`
  low);
* the strobe serializers carry `1,0,1,0,1,0,1,0` and drive while the core's
  `dqs_drive` is high; the DQ serializers carry the core's pattern on even
  DQ and its inverse on odd DQ, and DM carries 0, all driving while
  `dq_drive` is high;
* ODT comes from the core.

The rest of the MPR image's description holds:

* the PLL's `ENCLK0` driven by the core, so the memory clock can be stopped
  while the `CLKDIV` and the lanes are reset (`tools/pll_enclk_probe.py`
  located the port; `tools/vendor_memsync_trace.py` the order);
* the `DDRDLL` as the proven controller drives it: `STOP` the inverse of PLL
  lock, `RESET` and `UPDNCNTL` from the core, its clock from the `CLKDIV`'s
  HCLK lane;
* every `DQS` with `HOLD`, `READ`, `RCLKSEL`, `RLOADN`, `RMOVE` and `RDIR`
  from the core and `WLOADN` with `RLOADN`;
* every DQ, DM and strobe serializer with its four `TX` inputs high, so the
  lane pads stay in tristate -- reads only; every `IDES8_MEM` output into the
  core;
* bank 7's command serializers carrying the core's command in the first
  memory-clock slot of each `PCLK` and a deselect in the other three, `CK`
  serialized as 0,1 per clock so its rising edge falls mid-slot, and
  `RESET#` from the core.

The pins, constraints and SDCs are the bring-up's.  `--check` regenerates in
memory and fails unless the committed files are current; `--vendor` builds
the committed source with Gowin EDA into build/ddr3_write/vendor.

Usage:
    tools/ddr3_write.py            # write fpga/ddr3_write/
    tools/ddr3_write.py --check
    tools/ddr3_write.py --vendor
"""

import argparse
import os
import shutil
import sys

import cmd_pad_probe as cmd
import ddr3_pad_set_probe as pads
import ddr3_phy_bringup as bringup
import dqs_port_probe as base

SRC = os.path.join(base.ROOT, "fpga/ddr3_write")
VENDOR = os.path.join(base.ROOT, "build/ddr3_write/vendor")

#: the core's signal for each bank-7 command ball; the four strobes deselect
#: in the slots after the first
SIGNALS = {"ddr_cs": "cs_n", "ddr_ras": "ras_n", "ddr_cas": "cas_n", "ddr_we": "we_n",
           "ddr_cke": "cke", "ddr_odt": "odt",
           **{f"ddr_bank_{i}": f"ba[{i}]" for i in range(3)},
           **{f"ddr_addr_{i}": f"addr[{i}]" for i in range(16)}}
STROBES = {"ddr_cs", "ddr_ras", "ddr_cas", "ddr_we"}

# the core's output enable is declared ahead of the PLL that reads it
PLL = "    wire pll_en;\n" + bringup.PLL.replace(".ENCLK0(1'b1)", ".ENCLK0(pll_en)")

CORE = """\
    wire pclk, dll_rst, updncntl, hold, phy_rst, dll_lock, rloadn, rdir, wloadn;
    wire [3:0] rmove;
    wire [31:0] wstep;
    wire [7:0] dq_pat;
    wire dq_drive, dqs_drive, odt;
    wire [3:0] dq_tx = {4{!dq_drive}};
    wire [3:0] dqs_tx = {4{!dqs_drive}};
    wire [7:0] step;
    wire [2:0] rclksel;
    wire [3:0] read_en;
    wire ddr_rst_n, cke, cs_n, ras_n, cas_n, we_n;
    wire [2:0] ba;
    wire [15:0] addr;
    CLKDIV #(.DIV_MODE("4")) fdiv (.HCLKIN(mclk), .RESETN(!phy_rst), .CALIB(1'b0), .CLKOUT(pclk));
    DDRDLL #(.DLL_FORCE("FALSE"), .CODESCAL("111"), .SCAL_EN("FALSE"), .DIV_SEL(1'b0)) dll (
        .CLKIN(mclk), .STOP(!pll_lock), .UPDNCNTL(updncntl), .RESET(dll_rst),
        .STEP(step), .LOCK(dll_lock));
"""

LANE = """\
    wire dqsi_{l}, r90_{l}, w0_{l}, w270_{l};
    wire [2:0] rp_{l}, wp_{l};
    DQS #(.FIFO_MODE_SEL(1'b0), .RD_PNTR(3'b000), .DQS_MODE("X4"), .HWL("true")) dqs_{l} (
        .DQSIN(dqsi_{l}), .PCLK(pclk), .FCLK(mclk),
        .RESET(phy_rst), .READ(read_en), .RCLKSEL(rclksel), .DLLSTEP(step),
        .WSTEP(wstep[{w}+:8]), .RLOADN(rloadn), .RMOVE(rmove[{l}]), .RDIR(rdir),
        .WLOADN(wloadn), .WMOVE(1'b0), .WDIR(1'b0), .HOLD(hold),
        .DQSR90(r90_{l}), .DQSW0(w0_{l}), .DQSW270(w270_{l}),
        .RPOINT(rp_{l}), .WPOINT(wp_{l}),
        .RVALID(rvalid[{l}]), .RBURST(rburst[{l}]), .RFLAG(rflag[{l}]), .WFLAG(wflag[{l}]));
    assign rpoint[{l3}+:3] = rp_{l};
    assign wpoint[{l3}+:3] = wp_{l};
"""

DQ = """\
    wire dq{i}_i, dq{i}_d;
    IOBUF dq{i}_buf (.I(dq{i}_o), .OEN(dq{i}_t), .IO(ddr_dq[{i}]), .O(dq{i}_i));
    IODELAY #(.C_STATIC_DLY(5), .DYN_DLY_EN("FALSE"), .ADAPT_EN("FALSE")) dq{i}_delay (
        .DI(dq{i}_i), .SDTAP(1'b0), .VALUE(1'b0), .DLYSTEP(8'h00), .DO(dq{i}_d), .DF());
    IDES8_MEM dq{i}_des (.D(dq{i}_d), .ICLK(r90_{l}), .PCLK(pclk), .FCLK(mclk),
        .RESET(phy_rst), .CALIB(1'b0), .WADDR(wp_{l}), .RADDR(rp_{l}),
        .Q0(dq_q[{b}]), .Q1(dq_q[{b1}]), .Q2(dq_q[{b2}]), .Q3(dq_q[{b3}]),
        .Q4(dq_q[{b4}]), .Q5(dq_q[{b5}]), .Q6(dq_q[{b6}]), .Q7(dq_q[{b7}]));
"""

OSER_MEM = """\
    wire {n}_o, {n}_t;
    OSER8_MEM #(.HWL("false"), .TCLK_SOURCE({src}), .TXCLK_POL(1'b0)) {n}_ser (
        .D0({d}[0]), .D1({d}[1]), .D2({d}[2]), .D3({d}[3]),
        .D4({d}[4]), .D5({d}[5]), .D6({d}[6]), .D7({d}[7]),
        .TX0({t}[0]), .TX1({t}[1]), .TX2({t}[2]), .TX3({t}[3]),
        .PCLK(pclk), .FCLK(mclk), .TCLK({tclk}), .RESET(phy_rst),
        .Q0({n}_o), .Q1({n}_t));
"""

OSER8 = """\
    wire {n}_o;
    OSER8 #(.HWL("false"), .TXCLK_POL(1'b0)) {n}_ser (
        .D0({d0}), .D1({d0}), .D2({d2}), .D3({d2}), .D4({d2}), .D5({d2}), .D6({d2}), .D7({d2}),
        .TX0(1'b0), .TX1(1'b0), .TX2(1'b0), .TX3(1'b0),
        .PCLK(pclk), .FCLK(mclk), .RESET(phy_rst), .Q0({n}_o), .Q1());
"""

CK = """\
    wire ck_o;
    OSER8 #(.HWL("false"), .TXCLK_POL(1'b0)) ck_ser (
        .D0(1'b0), .D1(1'b1), .D2(1'b0), .D3(1'b1), .D4(1'b0), .D5(1'b1), .D6(1'b0), .D7(1'b1),
        .TX0(1'b0), .TX1(1'b0), .TX2(1'b0), .TX3(1'b0),
        .PCLK(pclk), .FCLK(mclk), .RESET(phy_rst), .Q0(ck_o), .Q1());
    ELVDS_OBUF ck_buf (.I(ck_o), .O(ddr_ck_p), .OB(ddr_ck_n));
"""


def render() -> str:
    ports = (["input wire sys_clk", "input wire uart_rx", "output wire uart_tx",
              "inout wire [31:0] ddr_dq"]
             + [f"inout wire ddr_dqs{l}_p, inout wire ddr_dqs{l}_n" for l in pads.LANES]
             + ["output wire [3:0] ddr_dm", "output wire ddr_ck_p", "output wire ddr_ck_n",
                "output wire ddr_reset_n"]
             + [f"output wire {p}" for p, _ in cmd.CMD_BALLS])
    out = ["// Generated by tools/ddr3_write.py; do not edit.",
           "`default_nettype none",
           "module top (\n    " + ",\n    ".join(ports) + "\n);",
           PLL, CORE,
           "    wire [3:0] rvalid, rburst, rflag, wflag;",
           "    wire [11:0] rpoint, wpoint;",
           "    // the strobe toggles each half clock; odd DQ carry the inverse",
           "    wire [7:0] dqs_d = 8'b01010101;",
           "    wire [7:0] dq_npat = ~dq_pat;",
           "    wire [7:0] dm_d = 8'h00;    // DM low: every byte written",
           "    // lane n, DQ 8n+k, IDES8_MEM output b at 64n + 8k + b",
           "    wire [255:0] dq_q;"]
    for l in pads.LANES:
        out.append(LANE.format(l=l, l3=3 * l, w=8 * l))
        out.append(OSER_MEM.format(n=f"st{l}", src='"DQSW270"', tclk=f"w270_{l}",
                                   d="dqs_d", t="dqs_tx"))
        out.append(f"    ELVDS_IOBUF st{l}_buf (.I(st{l}_o), .OEN(st{l}_t), "
                   f".IO(ddr_dqs{l}_p), .IOB(ddr_dqs{l}_n), .O(dqsi_{l}));")
        for k in range(8):
            i = 8 * l + k
            b = 64 * l + 8 * k
            out.append(OSER_MEM.format(n=f"dq{i}", src='"DQSW"', tclk=f"w0_{l}",
                                       d="dq_pat" if k % 2 == 0 else "dq_npat", t="dq_tx"))
            out.append(DQ.format(i=i, l=l, b=b, b1=b + 1, b2=b + 2, b3=b + 3,
                                 b4=b + 4, b5=b + 5, b6=b + 6, b7=b + 7))
        out.append(OSER_MEM.format(n=f"dm{l}", src='"DQSW"', tclk=f"w0_{l}",
                                   d="dm_d", t="dq_tx"))
        out.append(f"    TBUF dm{l}_buf (.I(dm{l}_o), .OEN(dm{l}_t), .O(ddr_dm[{l}]));")
    out.append("    OBUF reset_buf (.I(ddr_rst_n), .O(ddr_reset_n));")
    out.append(CK)
    for p, _ in cmd.CMD_BALLS:
        v = SIGNALS[p]
        out.append(OSER8.format(n=p, d0=v, d2="1'b1" if p in STROBES else v))
        out.append(f"    OBUF {p}_buf (.I({p}_o), .O({p}));")
    out.append("""\
    wr_core core (
        .sys_clk(sys_clk), .uart_rx(uart_rx), .uart_tx(uart_tx),
        .pll_lock(pll_lock), .pll_en(pll_en), .dll_rst(dll_rst), .updncntl(updncntl),
        .hold(hold), .phy_rst(phy_rst), .dll_lock(dll_lock), .step(step),
        .pclk(pclk), .rclksel(rclksel), .rloadn(rloadn), .rmove(rmove), .rdir(rdir),
        .read_en(read_en), .wloadn(wloadn), .wstep(wstep),
        .rvalid(rvalid), .rburst(rburst), .rflag(rflag), .wflag(wflag),
        .rpoint(rpoint), .wpoint(wpoint), .dq_q(dq_q),
        .dq_pat(dq_pat), .dq_drive(dq_drive), .dqs_drive(dqs_drive), .odt(odt),
        .ddr_reset_n(ddr_rst_n), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n),
        .we_n(we_n), .ba(ba), .addr(addr));""")
    out.append("endmodule")
    out.append("`default_nettype wire")
    return "\n".join(out) + "\n"


TCL = bringup.TCL.replace("bringup_core.v", "wr_core.v")

GENERATED = {"top.v": render, "top.cst": bringup.cst,
             "open.sdc": lambda: bringup.SDC_OPEN, "vendor.sdc": lambda: bringup.SDC_VENDOR}


def vendor_build() -> int:
    if not os.path.isdir(os.path.join(base.GOWIN, "IDE")):
        print(f"missing Gowin EDA at {base.GOWIN}", file=sys.stderr)
        return 2
    if os.path.isdir(VENDOR):
        shutil.rmtree(VENDOR)
    os.makedirs(VENDOR)
    for fn in ("top.v", "wr_core.v", "top.cst"):
        shutil.copy(os.path.join(SRC, fn), VENDOR)
    shutil.copy(os.path.join(SRC, "vendor.sdc"), os.path.join(VENDOR, "top.sdc"))
    with open(os.path.join(VENDOR, "run.tcl"), "w") as f:
        f.write(TCL)
    ok = base.build(VENDOR)
    rel = os.path.relpath(VENDOR, base.ROOT)
    if not ok:
        with open(os.path.join(VENDOR, "gw_sh.log")) as f:
            errors = [l.strip() for l in f if "ERROR" in l]
        print(f"{rel}: REFUSED -- " + (errors[0] if errors else "no ERROR line in gw_sh.log"))
        return 1
    print(f"{rel}: built, impl/pnr/probe.fs")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true",
                    help="fail unless the committed sources equal fresh ones")
    ap.add_argument("--vendor", action="store_true",
                    help="build the committed sources with Gowin EDA")
    args = ap.parse_args()
    if args.vendor:
        return vendor_build()
    bad = []
    for fn, make in GENERATED.items():
        path = os.path.join(SRC, fn)
        text = make()
        if args.check:
            try:
                with open(path) as f:
                    if f.read() != text:
                        bad.append(fn)
            except FileNotFoundError:
                bad.append(fn)
        else:
            with open(path, "w") as f:
                f.write(text)
    rel = os.path.relpath(SRC, base.ROOT)
    if args.check:
        print(f"{'PASS' if not bad else 'FAIL'}  {rel}: "
              + ("generated sources current" if not bad else "stale: " + ", ".join(bad)))
        return 1 if bad else 0
    print(f"wrote {rel}: " + ", ".join(GENERATED))
    return 0


if __name__ == "__main__":
    sys.exit(main())
