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
  from the core and `WLOADN` with `RLOADN`, its `READ` and `RCLKSEL` its own
  lane's, as the proven controller drives them per lane;
* every `IDES8_MEM.CALIB` independently controlled by the core so framing can
  be measured and corrected per DQ bit;
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
    tools/ddr3_write.py            # write fpga/ddr3_write/ and fpga/ddr3_ctrl/
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
#: the controller image's PHY, generated from the same templates so its
#: primitives, instance names and constraints are the write image's
SRC_CTRL = os.path.join(base.ROOT, "fpga/ddr3_ctrl")
VENDOR_CTRL = os.path.join(base.ROOT, "build/ddr3_ctrl/vendor")
#: the controller image's sources beyond its top: wr_core and its checkers
#: from fpga/ddr3_write, the controller and its fabric from fpga/ddr3_ctrl
CTRL_FILES = [(SRC, "wr_core.v"), (SRC, "rd_align.v"), (SRC, "rd_check.v"),
              (SRC_CTRL, "ctrl_glue.v"), (SRC_CTRL, "dfi_phy.v"), (SRC_CTRL, "ddr3_derot.v"),
              (SRC_CTRL, "ddr3_bist.v"), (SRC_CTRL, "ddr3_ctl.v")]

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
    // kept, so the open flow's SDC can name the memory-side clock whatever
    // Yosys does with the submodules' aliases of it
    (* keep *) wire pclk;
    wire dll_rst, updncntl, phy_rst, dll_lock, rloadn, rdir, wloadn;
    wire [3:0] hold;                    // per lane: the start-up update or command 0x35
    wire [3:0] rmove;
    wire [31:0] wstep;
    wire [7:0] dq_pat;
    wire dq_drive, dqs_drive, odt;
    wire [3:0] dq_tx = {4{!dq_drive}};
    wire [3:0] dqs_tx = {4{!dqs_drive}};
    wire [7:0] step;
    wire [11:0] rclksel;
    wire [15:0] read_en;
    wire [31:0] calib;
    wire ddr_rst_n, cke, cs_n, ras_n, cas_n, we_n;
    wire [2:0] ba;
    wire [15:0] addr;
    // RBURST can rise and fall between PCLK edges in X4 mode.  The memory
    // clock sees it, so it toggles one bit per edge there and PCLK does the
    // counting: a counter in this domain would put a wide incrementer on the
    // 400 MHz path.
    wire [3:0] burst_tog;
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
        .RESET(phy_rst), .READ(read_en[{l4}+:4]), .RCLKSEL(rclksel[{l3}+:3]), .DLLSTEP(step),
        .WSTEP(wstep[{w}+:8]), .RLOADN(rloadn), .RMOVE(rmove[{l}]), .RDIR(rdir),
        .WLOADN(wloadn), .WMOVE(1'b0), .WDIR(1'b0), .HOLD(hold[{l}]),
        .DQSR90(r90_{l}), .DQSW0(w0_{l}), .DQSW270(w270_{l}),
        .RPOINT(rp_{l}), .WPOINT(wp_{l}),
        .RVALID(rvalid[{l}]), .RBURST(rburst[{l}]), .RFLAG(rflag[{l}]), .WFLAG(wflag[{l}]));
    assign rpoint[{l3}+:3] = rp_{l};
    assign wpoint[{l3}+:3] = wp_{l};

    reg rb{l}_1, rb{l}_2, rb{l}_3, rb{l}_tog;
    always @(posedge mclk) begin
        rb{l}_1 <= rburst[{l}];
        rb{l}_2 <= rb{l}_1;
        rb{l}_3 <= rb{l}_2;
        if (rb{l}_2 && !rb{l}_3)
            rb{l}_tog <= ~rb{l}_tog;
    end
    assign burst_tog[{l}] = rb{l}_tog;
"""

DQ = """\
    wire dq{i}_i, dq{i}_d;
    IOBUF dq{i}_buf (.I(dq{i}_o), .OEN(dq{i}_t), .IO(ddr_dq[{i}]), .O(dq{i}_i));
    IODELAY #(.C_STATIC_DLY(5), .DYN_DLY_EN("FALSE"), .ADAPT_EN("FALSE")) dq{i}_delay (
        .DI(dq{i}_i), .SDTAP(1'b0), .VALUE(1'b0), .DLYSTEP(8'h00), .DO(dq{i}_d), .DF());
    IDES8_MEM dq{i}_des (.D(dq{i}_d), .ICLK(r90_{l}), .PCLK(pclk), .FCLK(mclk),
        .RESET(phy_rst), .CALIB(calib[{i}]), .WADDR(wp_{l}), .RADDR(rp_{l}),
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

#: a command ball in the controller image: phase p of the DFI in memory clock
#: p of the PCLK, D2p and D2p+1
OSER8_PH = """\
    wire {n}_o;
    OSER8 #(.HWL("false"), .TXCLK_POL(1'b0)) {n}_ser (
        .D0({p0}), .D1({p0}), .D2({p1}), .D3({p1}), .D4({p2}), .D5({p2}), .D6({p3}), .D7({p3}),
        .TX0(1'b0), .TX1(1'b0), .TX2(1'b0), .TX3(1'b0),
        .PCLK(pclk), .FCLK(mclk), .RESET(phy_rst), .Q0({n}_o), .Q1());
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


WR_CORE_PORTS = """\
        .sys_clk(sys_clk), .uart_rx(uart_rx), .uart_tx(uart_tx),
        .pll_lock(pll_lock), .pll_en(pll_en), .dll_rst(dll_rst), .updncntl(updncntl),
        .hold(hold), .phy_rst(phy_rst), .dll_lock(dll_lock), .step(step),
        .pclk(pclk), .rclksel(rclksel), .rloadn(rloadn), .rmove(rmove), .rdir(rdir),
        .read_en(read_en), .calib(calib), .wloadn(wloadn), .wstep(wstep),
        .rvalid(rvalid), .rburst(rburst), .rflag(rflag), .wflag(wflag),
        .rpoint(rpoint), .wpoint(wpoint), .dq_q(dq_q),
        .dq_pat(dq_pat), .dq_drive(dq_drive), .dqs_drive(dqs_drive), .odt(odt),
        .ddr_reset_n(ddr_rst_n), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n),
        .we_n(we_n), .ba(ba), .addr(addr),
        .burst_tog(burst_tog),"""

#: the controller image's own wires: the pads' per-phase commands, per-pin
#: write data and drive enables come from fpga/ddr3_ctrl/ctrl_glue.v, which
#: passes the core's through until the controller owns the bus
CTRL_WIRES = """\
    wire [255:0] wdq;                   // lane l, pin p, beat b at 64l + 8p + b
    wire [3:0] p_cs_n, p_ras_n, p_cas_n, p_we_n;
    wire [11:0] p_ba;                   // phase p at 3p +: 3
    wire [63:0] p_addr;                 // phase p at 16p +: 16
    wire p_odt, p_dq_drive, p_dqs_drive;
    wire ctrl_rd, ctrl_accept, ctrl_own, ctrl_trained, ext_tog;
    wire [6:0] ctrl_walign;
    wire [11:0] ctrl_rot;
    wire [7:0] ext_cmd;
    wire [511:0] ext_status;"""


def ctrl_cmd(p: str) -> dict:
    """Each memory clock's value of command ball `p` in the controller image,
    from the boundary's falling-edge registers (BOUNDARY)."""
    v = SIGNALS[p]
    if p in STROBES:
        return {f"p{k}": f"pb_{v}[{k}]" for k in range(4)}
    if v.startswith("ba["):
        i = int(v[3:-1])
        return {f"p{k}": f"pb_ba[{3 * k + i}]" for k in range(4)}
    if v.startswith("addr["):
        i = int(v[5:-1])
        return {f"p{k}": f"pb_addr[{16 * k + i}]" for k in range(4)}
    if v == "odt":
        return {f"p{k}": "pb_odt" for k in range(4)}
    if v == "cke":
        return {f"p{k}": "cke_b" for k in range(4)}
    return {f"p{k}": v for k in range(4)}


#: The controller image's I/O boundary.  nextpnr's Gowin timing model has no
#: arcs for IDES8_MEM, OSER8, OSER8_MEM or DQS, so no path between them and
#: the fabric is timed, for setup or hold, and each placement routes them as
#: it falls: an image whose layout changed with nothing else failed words
#: from a cold start and the next did not (TOOL-049).  Every PCLK signal the
#: serializers and the DQS sample therefore passes a register on PCLK's
#: falling edge here: it leaves half a PCLK before the rising edge it is
#: sampled at, so each such crossing has about half a PCLK of setup and of
#: hold whatever its routing, and the fabric side of each is an ordinary
#: register-to-register path nextpnr times.  The consumers still see each
#: signal at the rising edge they did, so no latency changes.
#:
#: The inbound crossings are not registered.  Entry 75 registered them too, and
#: an image with only them registered trains and then fails 1 to 2% of words on
#: every lane from word 0x1, each re-read returning the same wrong word, while
#: one with only the outbound side registered trains and runs clean (TOOL-052).
#: Why the falling-edge capture of a deserializer's word fails is not known;
#: Gowin's timing of its own placement gives those paths at least 1.8 ns of
#: setup slack.  The deserializers are read straight, as the TOOL-046 image
#: read them, and that is the boundary qualified from two cold starts.
#:
#: Each of those registers is a `bnd_ff` on pclk itself: an instantiated
#: DFFN, or DFFNS where it must start high, for Yosys.  Written as `always
#: @(negedge pclk)`, Yosys folded the enable and set of the core registers
#: feeding 25 of them into the copies and built them as rising-edge flops
#: behind a LUT1 inverting pclk on fabric routing, the command bits among
#: them (TOOL-051); build_ddr3_ctrl.sh now refuses that.  Gowin's GW5A
#: library has no falling-edge primitive, its synthesis setting the edge in
#: the CLS, so Gowin and the simulators get the plain falling-edge register.
#: (output, its width, input, starts high)
BOUNDARY_REGS = [
    ("dq_q", 256, "dq_io", False), ("rvalid", 4, "rvalid_io", False),
    ("read_en_b", 16, "read_en", False), ("rclksel_b", 12, "rclksel", False),
    ("hold_b", 4, "hold", False), ("rmove_b", 4, "rmove", False),
    ("rdir_b", 1, "rdir", False), ("rloadn_b", 1, "rloadn", True),
    ("wloadn_b", 1, "wloadn", True), ("wstep_b", 32, "wstep", False),
    ("calib_b", 32, "calib", False), ("wdq_b", 256, "wdq", False),
    ("dq_drive_b", 1, "p_dq_drive", False), ("dqs_drive_b", 1, "p_dqs_drive", False),
    ("pb_cs_n", 4, "p_cs_n", True), ("pb_ras_n", 4, "p_ras_n", True),
    ("pb_cas_n", 4, "p_cas_n", True), ("pb_we_n", 4, "p_we_n", True),
    ("pb_ba", 12, "p_ba", False), ("pb_addr", 64, "p_addr", False),
    ("pb_odt", 1, "p_odt", False), ("cke_b", 1, "cke", False),
]

#: The crossings from the lanes into the fabric.  They are wired straight
#: through rather than registered; see BOUNDARY_REGISTER_INBOUND and TOOL-052.
BOUNDARY_INBOUND = {"dq_q", "rvalid"}

#: Whether the inbound crossings above pass a falling-edge register too.  False
#: is the qualified design: TOOL-052 measured that registering them breaks the
#: controller's reads.  True is what entry 75 built, kept so that
#: tools/ddr3_ctrl_variant.py still renders either direction for the bisection.
BOUNDARY_REGISTER_INBOUND = False


def boundary() -> str:
    lines = ["    wire [255:0] dq_io;                 // the deserializers' outputs",
             "    wire [3:0] rvalid_io;"]
    for q, w, _, _ in BOUNDARY_REGS:
        lines.append(f"    wire [{w - 1}:0] {q};" if w > 1 else f"    wire {q};")
    regs_all = [r for r in BOUNDARY_REGS
                if BOUNDARY_REGISTER_INBOUND or r[0] not in BOUNDARY_INBOUND]
    for r in BOUNDARY_REGS:
        if r not in regs_all:
            lines.append(f"    assign {r[0]} = {r[2]};"
                         "   // straight through: a falling-edge capture of it fails (TOOL-052)")
    for hi in (False, True):
        regs = [r for r in regs_all if r[3] == hi]
        n = sum(r[1] for r in regs)
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
    return "\n".join(lines)


BOUNDARY = boundary()

#: one falling-edge boundary register; see BOUNDARY_REGS
BOUNDARY_FF = """\
module bnd_ff #(parameter [0:0] INIT = 1'b0) (input wire CLK, input wire D, output wire Q);
`ifdef YOSYS
    generate if (INIT) begin : s
        DFFNS ff (.CLK(CLK), .D(D), .SET(1'b0), .Q(Q));
    end else begin : r
        DFFN ff (.CLK(CLK), .D(D), .Q(Q));
    end endgenerate
`else
    reg q = INIT;
    always @(negedge CLK) q <= D;
    assign Q = q;
`endif
endmodule"""

#: the DQS and deserializer templates' boundary nets in the controller image
LANE_B = (LANE.replace("read_en[", "read_en_b[").replace("rclksel[", "rclksel_b[")
              .replace("(wstep[", "(wstep_b[").replace(".RLOADN(rloadn)", ".RLOADN(rloadn_b)")
              .replace("(rmove[", "(rmove_b[").replace(".RDIR(rdir)", ".RDIR(rdir_b)")
              .replace(".WLOADN(wloadn)", ".WLOADN(wloadn_b)").replace("(hold[", "(hold_b[")
              .replace(".RVALID(rvalid[", ".RVALID(rvalid_io["))
DQ_B = DQ.replace("(calib[", "(calib_b[").replace("(dq_q[", "(dq_io[")
assert LANE_B.count("_b[") == 5 and LANE_B.count("_b)") == 3 and "rvalid_io[" in LANE_B
assert DQ_B.count("dq_io[") == 8 and "calib_b[" in DQ_B


def render(ctrl: bool = False) -> str:
    ports = (["input wire sys_clk", "input wire uart_rx", "output wire uart_tx",
              "inout wire [31:0] ddr_dq"]
             + [f"inout wire ddr_dqs{l}_p, inout wire ddr_dqs{l}_n" for l in pads.LANES]
             + ["output wire [3:0] ddr_dm", "output wire ddr_ck_p", "output wire ddr_ck_n",
                "output wire ddr_reset_n"]
             + [f"output wire {p}" for p, _ in cmd.CMD_BALLS])
    out = ["// Generated by tools/ddr3_write.py; do not edit.",
           "`default_nettype none",
           "module top (\n    " + ",\n    ".join(ports) + "\n);",
           PLL,
           CORE.replace("    wire [3:0] dq_tx = {4{!dq_drive}};\n", "")
               .replace("    wire [3:0] dqs_tx = {4{!dqs_drive}};\n", "") if ctrl else CORE]
    if ctrl:
        out.append(CTRL_WIRES)
        out.append(BOUNDARY)
        out.append("    wire [3:0] dq_tx = {4{!dq_drive_b}};\n"
                   "    wire [3:0] dqs_tx = {4{!dqs_drive_b}};")
    out += ["    wire [3:0] rburst, rflag, wflag;" if ctrl else
            "    wire [3:0] rvalid, rburst, rflag, wflag;",
            "    wire [11:0] rpoint, wpoint;",
            "    // the strobe toggles each half clock; odd DQ carry the inverse",
            "    wire [7:0] dqs_d = 8'b01010101;",
            "    wire [7:0] dq_npat = ~dq_pat;",
            "    wire [7:0] dm_d = 8'h00;    // DM low: every byte written"]
    if not ctrl:
        out += ["    // lane n, DQ 8n+k, IDES8_MEM output b at 64n + 8k + b",
                "    wire [255:0] dq_q;"]
    for l in pads.LANES:
        out.append((LANE_B if ctrl else LANE).format(l=l, l3=3 * l, l4=4 * l, w=8 * l))
        out.append(OSER_MEM.format(n=f"st{l}", src='"DQSW270"', tclk=f"w270_{l}",
                                   d="dqs_d", t="dqs_tx"))
        out.append(f"    ELVDS_IOBUF st{l}_buf (.I(st{l}_o), .OEN(st{l}_t), "
                   f".IO(ddr_dqs{l}_p), .IOB(ddr_dqs{l}_n), .O(dqsi_{l}));")
        for k in range(8):
            i = 8 * l + k
            b = 64 * l + 8 * k
            if ctrl:
                out.append(f"    wire [7:0] wd{i} = wdq_b[{b}+:8];")
                d = f"wd{i}"
            else:
                d = "dq_pat" if k % 2 == 0 else "dq_npat"
            out.append(OSER_MEM.format(n=f"dq{i}", src='"DQSW"', tclk=f"w0_{l}",
                                       d=d, t="dq_tx"))
            out.append((DQ_B if ctrl else DQ).format(i=i, l=l, b=b, b1=b + 1, b2=b + 2,
                                                     b3=b + 3, b4=b + 4, b5=b + 5, b6=b + 6,
                                                     b7=b + 7))
        out.append(OSER_MEM.format(n=f"dm{l}", src='"DQSW"', tclk=f"w0_{l}",
                                   d="dm_d", t="dq_tx"))
        out.append(f"    TBUF dm{l}_buf (.I(dm{l}_o), .OEN(dm{l}_t), .O(ddr_dm[{l}]));")
    out.append("    OBUF reset_buf (.I(ddr_rst_n), .O(ddr_reset_n));")
    out.append(CK)
    for p, _ in cmd.CMD_BALLS:
        if ctrl:
            out.append(OSER8_PH.format(n=p, **ctrl_cmd(p)))
        else:
            v = SIGNALS[p]
            out.append(OSER8.format(n=p, d0=v, d2="1'b1" if p in STROBES else v))
        out.append(f"    OBUF {p}_buf (.I({p}_o), .O({p}));")
    if ctrl:
        out.append("    wr_core #(.AUTOTRAIN(1)) core (\n" + WR_CORE_PORTS + """
        .ctrl_rd(ctrl_rd), .ctrl_accept(ctrl_accept), .ctrl_own(ctrl_own), .ctrl_walign(ctrl_walign),
        .ctrl_rot(ctrl_rot), .ctrl_trained(ctrl_trained),
        .ext_cmd(ext_cmd), .ext_tog(ext_tog), .ext_status(ext_status));
    ctrl_glue glue (
        .sys_clk(sys_clk), .pclk(pclk), .dq_q(dq_q),
        .wc_cs_n(cs_n), .wc_ras_n(ras_n), .wc_cas_n(cas_n), .wc_we_n(we_n),
        .wc_ba(ba), .wc_addr(addr), .wc_odt(odt), .wc_dq_pat(dq_pat),
        .wc_dq_drive(dq_drive), .wc_dqs_drive(dqs_drive),
        .ctrl_own(ctrl_own), .ctrl_trained(ctrl_trained), .ctrl_walign(ctrl_walign),
        .ctrl_rot(ctrl_rot), .ext_cmd(ext_cmd), .ext_tog(ext_tog),
        .p_cs_n(p_cs_n), .p_ras_n(p_ras_n), .p_cas_n(p_cas_n), .p_we_n(p_we_n),
        .p_ba(p_ba), .p_addr(p_addr), .p_odt(p_odt), .p_dq_drive(p_dq_drive),
        .p_dqs_drive(p_dqs_drive), .wdq(wdq), .ctrl_rd(ctrl_rd), .ctrl_accept(ctrl_accept),
        .ext_status(ext_status));""")
    else:
        out.append("    wr_core core (\n" + WR_CORE_PORTS + """
        .ctrl_rd(1'b0), .ctrl_accept(1'b0), .ext_status(512'd0));""")
    out.append("endmodule")
    if ctrl:
        out.append(BOUNDARY_FF)
    out.append("`default_nettype wire")
    return "\n".join(out) + "\n"


TCL = bringup.TCL.replace("bringup_core.v",
                          "wr_core.v\nadd_file -type verilog rd_align.v"
                          "\nadd_file -type verilog rd_check.v")

# Flattening leaves the memory clock's net with whichever submodule alias
# Yosys keeps -- `core.pclk` once, `core.align.pclk` after rd_check was added
# -- so top.v keeps its own `pclk` wire and the open flow names that, as the
# bring-up's SDC does.  build_ddr3_write.sh fails the build when a clock
# constraint matches no net, so a future rename cannot pass unnoticed.
SDC_OPEN = bringup.SDC_OPEN

GENERATED = {"top.v": render, "top.cst": bringup.cst,
             "open.sdc": lambda: SDC_OPEN, "vendor.sdc": lambda: bringup.SDC_VENDOR}
GENERATED_CTRL = {"top.v": lambda: render(ctrl=True), "top.cst": bringup.cst,
                  "open.sdc": lambda: SDC_OPEN, "vendor.sdc": lambda: bringup.SDC_VENDOR}


TCL_CTRL = bringup.TCL.replace(
    "bringup_core.v", "\nadd_file -type verilog ".join(fn for _, fn in CTRL_FILES))


def tcl(place=None, route=None, ctrl=False) -> str:
    """The vendor script, with Gowin's place and route options when given."""
    opts = ""
    if place is not None:
        opts += f"set_option -place_option {place}\n"
    if route is not None:
        opts += f"set_option -route_option {route}\n"
    return (TCL_CTRL if ctrl else TCL).replace("run all", opts + "run all")


def vendor_build(dest=None, place=None, route=None, quiet=False, ctrl=False) -> int:
    if dest is None:
        dest = VENDOR_CTRL if ctrl else VENDOR
    if not os.path.isdir(os.path.join(base.GOWIN, "IDE")):
        print(f"missing Gowin EDA at {base.GOWIN}", file=sys.stderr)
        return 2
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    if ctrl:
        for fn in ("top.v", "top.cst"):
            shutil.copy(os.path.join(SRC_CTRL, fn), dest)
        for d, fn in CTRL_FILES:
            shutil.copy(os.path.join(d, fn), dest)
        shutil.copy(os.path.join(SRC_CTRL, "vendor.sdc"), os.path.join(dest, "top.sdc"))
    else:
        for fn in ("top.v", "wr_core.v", "rd_align.v", "rd_check.v", "top.cst"):
            shutil.copy(os.path.join(SRC, fn), dest)
        shutil.copy(os.path.join(SRC, "vendor.sdc"), os.path.join(dest, "top.sdc"))
    with open(os.path.join(dest, "run.tcl"), "w") as f:
        f.write(tcl(place, route, ctrl))
    ok = base.build(dest)
    rel = os.path.relpath(dest, base.ROOT)
    if not ok:
        with open(os.path.join(dest, "gw_sh.log")) as f:
            errors = [l.strip() for l in f if "ERROR" in l]
        print(f"{rel}: REFUSED -- " + (errors[0] if errors else "no ERROR line in gw_sh.log"))
        return 1
    if not quiet:
        print(f"{rel}: built, impl/pnr/probe.fs")
    return 0


def vendor_timing(d: str):
    """PCLK Fmax in MHz and the summed negative slack of a Gowin build."""
    import html
    import re
    path = os.path.join(d, "impl/pnr/probe_tr_content.html")
    text = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", open(path).read())))
    fmax = text[text.find("Max Frequency Summary"):text.find("Total Negative Slack Summary")]
    tns = text[text.find("Total Negative Slack Summary"):text.find("Timing Details")]
    m = re.search(r"pclk \d+\.\d+\(MHz\) (\d+\.\d+)\(MHz\)", fmax)
    neg = sum(float(r[2]) for r in re.findall(r"(\S+) (Setup|Hold) (-?\d+\.\d+) (\d+)", tns))
    return (float(m.group(1)) if m else 0.0), neg


def vendor_sweep(jobs: int, ctrl: bool = False) -> int:
    """Gowin's analogue of a seed sweep: its defaults, then place_option 0..3 x
    route_option 0..1.

    Each variant builds in its own directory under build/ddr3_write/vendor_sweep,
    or build/ddr3_ctrl/vendor_sweep with ctrl; the best clean one -- no
    negative slack, highest PCLK Fmax -- is installed as the vendor control,
    and its options are printed so --vendor can rebuild it.
    """
    from concurrent.futures import ThreadPoolExecutor
    vendor = VENDOR_CTRL if ctrl else VENDOR
    root = os.path.join(base.ROOT, "build/ddr3_ctrl/vendor_sweep" if ctrl
                        else "build/ddr3_write/vendor_sweep")
    combos = [(None, None)] + [(p, r) for p in range(4) for r in range(2)]
    dirs = {c: os.path.join(root, "default" if c[0] is None else f"p{c[0]}r{c[1]}")
            for c in combos}
    with ThreadPoolExecutor(max_workers=jobs) as ex:
        rcs = dict(zip(combos, ex.map(lambda c: vendor_build(dirs[c], c[0], c[1], True, ctrl),
                                      combos)))
    results = []
    for c in combos:
        name = "defaults" if c[0] is None else f"place {c[0]} route {c[1]}"
        if rcs[c] != 0:
            print(f"{name}: REFUSED")
            continue
        fmax, neg = vendor_timing(dirs[c])
        results.append((neg == 0.0, fmax, c))
        print(f"{name}: PCLK {fmax:.3f} MHz, negative slack {neg:.3f}")
    if not results:
        print("no variant built; the vendor build is left as it was")
        return 1
    clean = [r for r in results if r[0]]
    if not clean:
        # Still the same sources, so still the reference for the DDR3 fuse
        # comparison; build_ddr3_write.sh writes no control from it.
        print("no variant meets timing; installing the fastest as a fuse reference only")
    _, fmax, (pl, rt) = max(clean or results, key=lambda r: r[1])
    if os.path.isdir(vendor):
        shutil.rmtree(vendor)
    shutil.copytree(dirs[(pl, rt)], vendor)
    how = ("--vendor" + (" --ctrl" if ctrl else "") +
           ("" if pl is None else f" --place-option {pl} --route-option {rt}"))
    print(f"installed {'defaults' if pl is None else f'place {pl} route {rt}'} "
          f"({fmax:.3f} MHz) as {os.path.relpath(vendor, base.ROOT)}; rebuild with {how}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true",
                    help="fail unless the committed sources equal fresh ones")
    ap.add_argument("--vendor", action="store_true",
                    help="build the committed sources with Gowin EDA")
    ap.add_argument("--place-option", type=int, choices=range(5), default=None,
                    help="Gowin -place_option for --vendor")
    ap.add_argument("--route-option", type=int, choices=range(3), default=None,
                    help="Gowin -route_option for --vendor")
    ap.add_argument("--vendor-sweep", action="store_true",
                    help="build place_option 0..3 x route_option 0..1 and install the "
                         "best variant that meets timing as the vendor control")
    ap.add_argument("--jobs", type=int, default=4, help="parallel Gowin builds in a sweep")
    ap.add_argument("--ctrl", action="store_true",
                    help="--vendor and --vendor-sweep build the controller image, fpga/ddr3_ctrl, "
                         "into build/ddr3_ctrl")
    args = ap.parse_args()
    if args.vendor_sweep:
        return vendor_sweep(args.jobs, args.ctrl)
    if args.vendor:
        return vendor_build(place=args.place_option, route=args.route_option, ctrl=args.ctrl)
    failed = False
    for src, generated in ((SRC, GENERATED), (SRC_CTRL, GENERATED_CTRL)):
        bad = []
        for fn, make in generated.items():
            path = os.path.join(src, fn)
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
        rel = os.path.relpath(src, base.ROOT)
        if args.check:
            print(f"{'PASS' if not bad else 'FAIL'}  {rel}: "
                  + ("generated sources current" if not bad else "stale: " + ", ".join(bad)))
            failed = failed or bool(bad)
        else:
            print(f"wrote {rel}: " + ", ".join(generated))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
