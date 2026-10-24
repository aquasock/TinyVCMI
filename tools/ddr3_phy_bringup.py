#!/usr/bin/env python3
"""Generate, check and vendor-build the DDR3 PHY bring-up image's source.

The bring-up image is the first DDR3 image meant for the board.  It carries
the hardware-proven controller's PHY with nothing behind it, clocked the way
that controller is clocked (read from its netlist and bitstream):

* one PLL, 50 MHz x16 / 2 = 400 MHz, the memory clock, on `PLL_L[0]`;
* one `CLKDIV`, `DIV_MODE=4`, at `LEFTSIDE[4]`: the 100 MHz `PCLK` of every
  lane, and HCLK lane 0 for every `FCLK`, which is where the proven bitstream
  puts all four `DQS` blocks;
* the `DDRDLL` on `DDRDLLM_BL`, `CLKIN` the memory clock, `STOP` the inverse
  of PLL lock (the vendor drives it through a `LUT1` with `INIT=2'h1`),
  `STEP` on all four `DQS` blocks;
* per lane, the shapes of `tools/ddr3_pad_set_probe.py`: the strobe pair and
  its `OSER8_MEM`, eight DQ `IOBUF`s each with an `OSER8_MEM`, a static
  `IODELAY` and an `IDES8_MEM`, and the DM `TBUF` with its `OSER8_MEM`;
* bank 7's command, address and clock serializers.

`fpga/ddr3_phy_bringup/bringup_core.v` sequences the DLL, `CLKDIV` and lanes
and answers TinyTang.  The DDR3 device is held in reset for the life of the
image: `ddr_reset_n` and `ddr_cke` are driven low from constants, `ddr_cs` is
high and `ddr_odt` low, and every DQ, DM and strobe serializer has all four
`TX` inputs tied high, which holds its pad in tristate.

The generated files are committed.  `--check` regenerates them in memory and
fails unless they equal the committed ones; `--vendor` builds the source with
Gowin EDA into build/ddr3_phy_bringup/vendor, the reference
`tools/ddr3_image_check.py` compares the open-flow image against.

Usage:
    tools/ddr3_phy_bringup.py              # write fpga/ddr3_phy_bringup/
    tools/ddr3_phy_bringup.py --check
    tools/ddr3_phy_bringup.py --vendor
"""

import argparse
import os
import shutil
import sys

import cmd_pad_probe as cmd
import ddr3_pad_set_probe as pads
import dqs_port_probe as base

SRC = os.path.join(base.ROOT, "fpga/ddr3_phy_bringup")
VENDOR = os.path.join(base.ROOT, "build/ddr3_phy_bringup/vendor")

#: bank-7 command balls and the level each holds while the device is in reset
#: (`ddr_cs`, `ddr_ras`, `ddr_cas` and `ddr_we` are active low)
LEVELS = {"ddr_cs": 1, "ddr_ras": 1, "ddr_cas": 1, "ddr_we": 1, "ddr_odt": 0, "ddr_cke": 0}

PLL = """\
    wire mclk, pll_lock;
    PLL #(
        .FCLKIN("50"), .IDIV_SEL(1), .FBDIV_SEL(1), .MDIV_SEL(16), .ODIV0_SEL(2),
        .CLKOUT0_EN("TRUE")
    ) ddr_pll (
        .CLKIN(sys_clk), .CLKFB(1'b0), .RESET(1'b0), .PLLPWD(1'b0),
        .RESET_I(1'b0), .RESET_O(1'b0),
        .FBDSEL(6'b0), .IDSEL(6'b0), .MDSEL(7'b0), .MDSEL_FRAC(3'b0),
        .ODSEL0(7'b0), .ODSEL0_FRAC(3'b0), .ODSEL1(7'b0), .ODSEL2(7'b0),
        .ODSEL3(7'b0), .ODSEL4(7'b0), .ODSEL5(7'b0), .ODSEL6(7'b0),
        .DT0(4'b0), .DT1(4'b0), .DT2(4'b0), .DT3(4'b0),
        .ICPSEL(6'b0), .LPFRES(3'b0), .LPFCAP(2'b0),
        .PSSEL(3'b0), .PSDIR(1'b0), .PSPULSE(1'b0),
        .ENCLK0(1'b1), .ENCLK1(1'b0), .ENCLK2(1'b0), .ENCLK3(1'b0),
        .ENCLK4(1'b0), .ENCLK5(1'b0), .ENCLK6(1'b0),
        .SSCPOL(1'b0), .SSCON(1'b0), .SSCMDSEL(7'b0), .SSCMDSEL_FRAC(3'b0),
        .LOCK(pll_lock), .CLKOUT0(mclk));
"""

CORE = """\
    wire pclk, dll_rst, updncntl, phy_rst, loadn, dll_lock;
    wire [7:0] step;
    CLKDIV #(.DIV_MODE("4")) fdiv (.HCLKIN(mclk), .RESETN(!phy_rst), .CALIB(1'b0), .CLKOUT(pclk));
    DDRDLL #(.DLL_FORCE("FALSE"), .CODESCAL("111"), .SCAL_EN("FALSE"), .DIV_SEL(1'b0)) dll (
        .CLKIN(mclk), .STOP(!pll_lock), .UPDNCNTL(updncntl), .RESET(dll_rst),
        .STEP(step), .LOCK(dll_lock));
    // data for the tristated serializers: moving, so neither synthesizer
    // can fold them, and never seen on a pad
    reg [7:0] sig = 8'h01;
    always @(posedge pclk) sig <= {sig[6:0], sig[7]};
"""

# All four TX inputs high: Q1 high, OEN high, the pad in tristate.
OSER_MEM = """\
    wire {n}_o, {n}_t;
    OSER8_MEM #(.HWL("false"), .TCLK_SOURCE({src}), .TXCLK_POL(1'b0)) {n}_ser (
        .D0(sig[0]), .D1(sig[1]), .D2(sig[2]), .D3(sig[3]),
        .D4(sig[4]), .D5(sig[5]), .D6(sig[6]), .D7(sig[7]),
        .TX0(1'b1), .TX1(1'b1), .TX2(1'b1), .TX3(1'b1),
        .PCLK(pclk), .FCLK(mclk), .TCLK({tclk}), .RESET(phy_rst),
        .Q0({n}_o), .Q1({n}_t));
"""

LANE = """\
    wire dqsi_{l}, r90_{l}, w0_{l}, w270_{l};
    wire [2:0] rp_{l}, wp_{l};
    DQS #(.FIFO_MODE_SEL(1'b0), .RD_PNTR(3'b000), .DQS_MODE("X4"), .HWL("true")) dqs_{l} (
        .DQSIN(dqsi_{l}), .PCLK(pclk), .FCLK(mclk),
        .RESET(phy_rst), .READ(4'b0000), .RCLKSEL(3'b000), .DLLSTEP(step), .WSTEP(8'h00),
        .RLOADN(loadn), .RMOVE(1'b0), .RDIR(1'b0),
        .WLOADN(loadn), .WMOVE(1'b0), .WDIR(1'b0), .HOLD(1'b0),
        .DQSR90(r90_{l}), .DQSW0(w0_{l}), .DQSW270(w270_{l}),
        .RPOINT(rp_{l}), .WPOINT(wp_{l}),
        .RVALID(rvalid[{l}]), .RBURST(rburst[{l}]), .RFLAG(rflag[{l}]), .WFLAG(wflag[{l}]));
    assign rpoint[{l3}+:3] = rp_{l};
    assign wpoint[{l3}+:3] = wp_{l};
"""

DQ = """\
    wire dq{i}_i, dq{i}_d;
    wire [7:0] dq{i}_q;
    IOBUF dq{i}_buf (.I(dq{i}_o), .OEN(dq{i}_t), .IO(ddr_dq[{i}]), .O(dq{i}_i));
    IODELAY #(.C_STATIC_DLY(5), .DYN_DLY_EN("FALSE"), .ADAPT_EN("FALSE")) dq{i}_delay (
        .DI(dq{i}_i), .SDTAP(1'b0), .VALUE(1'b0), .DLYSTEP(8'h00), .DO(dq{i}_d), .DF());
    IDES8_MEM dq{i}_des (.D(dq{i}_d), .ICLK(r90_{l}), .PCLK(pclk), .FCLK(mclk),
        .RESET(phy_rst), .CALIB(1'b0), .WADDR(wp_{l}), .RADDR(rp_{l}),
        .Q0(dq{i}_q[0]), .Q1(dq{i}_q[1]), .Q2(dq{i}_q[2]), .Q3(dq{i}_q[3]),
        .Q4(dq{i}_q[4]), .Q5(dq{i}_q[5]), .Q6(dq{i}_q[6]), .Q7(dq{i}_q[7]));
"""

OSER8 = """\
    wire {n}_o;
    OSER8 #(.HWL("false"), .TXCLK_POL(1'b0)) {n}_ser (
        .D0({v}), .D1({v}), .D2({v}), .D3({v}), .D4({v}), .D5({v}), .D6({v}), .D7({v}),
        .TX0(1'b0), .TX1(1'b0), .TX2(1'b0), .TX3(1'b0),
        .PCLK(pclk), .FCLK(mclk), .RESET(phy_rst), .Q0({n}_o), .Q1());
"""


def render() -> str:
    ports = (["input wire sys_clk", "input wire uart_rx", "output wire uart_tx",
              "inout wire [31:0] ddr_dq"]
             # scalar strobe ports: nextpnr leaves the N half of a bused
             # differential port unconstrained
             + [f"inout wire ddr_dqs{l}_p, inout wire ddr_dqs{l}_n" for l in pads.LANES]
             + ["output wire [3:0] ddr_dm", "output wire ddr_ck_p", "output wire ddr_ck_n",
                "output wire ddr_reset_n"]
             + [f"output wire {p}" for p, _ in cmd.CMD_BALLS])
    out = ["// Generated by tools/ddr3_phy_bringup.py; do not edit.",
           "`default_nettype none",
           "module top (\n    " + ",\n    ".join(ports) + "\n);",
           PLL, CORE,
           "    wire [3:0] rvalid, rburst, rflag, wflag;",
           "    wire [11:0] rpoint, wpoint;",
           "    reg [31:0] ides_parity = 32'd0;"]
    for l in pads.LANES:
        out.append(LANE.format(l=l, l3=3 * l))
        out.append(OSER_MEM.format(n=f"st{l}", src='"DQSW270"', tclk=f"w270_{l}"))
        out.append(f"    ELVDS_IOBUF st{l}_buf (.I(st{l}_o), .OEN(st{l}_t), "
                   f".IO(ddr_dqs{l}_p), .IOB(ddr_dqs{l}_n), .O(dqsi_{l}));")
        dqs = [8 * l + k for k in range(8)]
        for i in dqs:
            out.append(OSER_MEM.format(n=f"dq{i}", src='"DQSW"', tclk=f"w0_{l}"))
            out.append(DQ.format(i=i, l=l))
        out.append(OSER_MEM.format(n=f"dm{l}", src='"DQSW"', tclk=f"w0_{l}"))
        out.append(f"    TBUF dm{l}_buf (.I(dm{l}_o), .OEN(dm{l}_t), .O(ddr_dm[{l}]));")
        out.append(f"    always @(posedge pclk) ides_parity[{8 * l}+:8] <= "
                   + " ^ ".join(f"dq{i}_q" for i in dqs) + ";")
    out.append("    // the device stays in reset: RESET# low from a constant")
    out.append("    OBUF reset_buf (.I(1'b0), .O(ddr_reset_n));")
    out.append(OSER8.format(n="ck", v="1'b0"))
    out.append("    ELVDS_OBUF ck_buf (.I(ck_o), .O(ddr_ck_p), .OB(ddr_ck_n));")
    for p, _ in cmd.CMD_BALLS:
        out.append(OSER8.format(n=p, v=f"1'b{LEVELS.get(p, 0)}"))
        out.append(f"    OBUF {p}_buf (.I({p}_o), .O({p}));")
    out.append("""\
    bringup_core core (
        .sys_clk(sys_clk), .uart_rx(uart_rx), .uart_tx(uart_tx),
        .pll_lock(pll_lock), .dll_lock(dll_lock), .step(step), .pclk(pclk),
        .rvalid(rvalid), .rburst(rburst), .rflag(rflag), .wflag(wflag),
        .rpoint(rpoint), .wpoint(wpoint), .ides_parity(ides_parity),
        .dll_rst(dll_rst), .updncntl(updncntl), .phy_rst(phy_rst), .loadn(loadn));""")
    out.append("endmodule")
    out.append("`default_nettype wire")
    return "\n".join(out) + "\n"


def cst() -> str:
    lines = ["// Generated by tools/ddr3_phy_bringup.py; do not edit.",
             'IO_LOC "sys_clk" V22;', 'IO_PORT "sys_clk" IO_TYPE=LVCMOS33 PULL_MODE=NONE;',
             'IO_LOC "uart_tx" U15;', 'IO_PORT "uart_tx" IO_TYPE=LVCMOS33;',
             'IO_LOC "uart_rx" V14;', 'IO_PORT "uart_rx" IO_TYPE=LVCMOS33 PULL_MODE=UP;',
             'INS_LOC "ddr_pll" PLL_L[0];',
             'INS_LOC "dll" DDRDLLM_BL;',
             'INS_LOC "fdiv" LEFTSIDE[4];']
    lines += [l for l in pads.cst().splitlines()
              if '"clk"' not in l and '"q"' not in l and not l.startswith("INS_LOC")]
    return "\n".join(lines) + "\n"


# nextpnr reads create_clock only; the vendor tool also needs the domains
# declared exclusive, as the proven controller's SDC does.
SDC_OPEN = """\
create_clock -name clk50 -period 20.000 [get_ports {sys_clk}]
create_clock -name clk400 -period 2.500 [get_nets {mclk}]
create_clock -name pclk -period 10.000 [get_nets {pclk}]
"""
SDC_VENDOR = SDC_OPEN + \
    "set_clock_groups -exclusive -group [get_clocks {clk400}] " \
    "-group [get_clocks {clk50}] -group [get_clocks {pclk}]\n"

TCL = """\
set_device GW5AST-LV138PG484AC1/I0 -device_version C
add_file -type verilog top.v
add_file -type verilog bringup_core.v
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

GENERATED = {"top.v": render, "top.cst": cst,
             "open.sdc": lambda: SDC_OPEN, "vendor.sdc": lambda: SDC_VENDOR}


def vendor_build() -> int:
    if not os.path.isdir(os.path.join(base.GOWIN, "IDE")):
        print(f"missing Gowin EDA at {base.GOWIN}", file=sys.stderr)
        return 2
    if os.path.isdir(VENDOR):
        shutil.rmtree(VENDOR)
    os.makedirs(VENDOR)
    for fn in ("top.v", "bringup_core.v", "top.cst"):
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
