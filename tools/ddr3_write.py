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
SRC_SOC = os.path.join(base.ROOT, "fpga/ae350_ddr3")
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

    // the rising edge registered before it enables the toggle, so neither
    // path has a LUT between two routes: as one, the 400 MHz memory clock
    // missed by 0.25 ns fully timed (TOOL-065)
    reg rb{l}_1, rb{l}_2, rb{l}_e, rb{l}_tog;
    always @(posedge mclk) begin
        rb{l}_1 <= rburst[{l}];
        rb{l}_2 <= rb{l}_1;
        rb{l}_e <= rb{l}_1 && !rb{l}_2;
        if (rb{l}_e)
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
    wire [31:0]  dm;                    // lane l, beat b at 8l + b: 1 suppresses the byte
    wire [3:0] p_cs_n, p_ras_n, p_cas_n, p_we_n;
    wire [11:0] p_ba;                   // phase p at 3p +: 3
    wire [63:0] p_addr;                 // phase p at 16p +: 16
    wire p_odt, p_dq_drive, p_dqs_drive;
    wire ctrl_rd, ctrl_accept, ctrl_own, ctrl_trained, ext_tog;
    wire [6:0] ctrl_own_x;
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
    ("dm_b", 32, "dm", False),
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


#: The AE350 image's CPU clocks: PLL_R[0], the only PLL whose CLKOUT1 runs
#: the A25 (TinyNES DEV-008), 750 MHz on CLKOUT1 and the 75 MHz bus on
#: CLKOUT0, as TinyNES makes them.
CPU_PLL = bringup.PLL.replace("wire mclk, pll_lock;", "wire bus_clk, core_clk, cpu_lock;") \
    .replace(".MDIV_SEL(16), .ODIV0_SEL(2),", ".MDIV_SEL(15), .ODIV0_SEL(10), .ODIV1_SEL(1),") \
    .replace('.CLKOUT0_EN("TRUE")', '.CLKOUT0_EN("TRUE"), .CLKOUT1_EN("TRUE")') \
    .replace(") ddr_pll (", ") cpu_pll (") \
    .replace(".ENCLK1(1'b0)", ".ENCLK1(1'b1)") \
    .replace(".LOCK(pll_lock), .CLKOUT0(mclk));", ".LOCK(cpu_lock), .CLKOUT0(bus_clk), .CLKOUT1(core_clk));")

#: The HDMI clocks: 50 MHz to 27 MHz (hdmi_pll27, 1350 MHz VCO / 50), then
#: 27 MHz to the 74.25 MHz pixel clock on CLKOUT0 (hdmi_pll, 1485 MHz VCO /
#: 20) and the 371.25 MHz serial clock on CLKOUT1 (VCO / 4), phase-locked to
#: it.  The pixel clock is on CLKOUT0 because only a PLL's CLKOUT0 reached the
#: global network here: on CLKOUT1 the global router gave it none of its 632
#: sinks, as it gives the CPU PLL's CLKOUT1 (core_clk) no dedicated route;
#: the serial clock goes to the OSER10s' HCLK lane by general routing either
#: way, as in TinyNES.  TinyNES divides the serial
#: clock by five in a CLKDIV instead, but this image's DDR3 PHY already has
#: the one CLKDIV clock the global network can carry: the Apicula fork lets
#: CLKDIV clocks enter the centre clock mux only at (54,88) SPINE18 (TinyNES
#: DEV-017), and with two the global router gave the other none of its
#: sinks.  The serial-clock PLL must sit at PLL_R[3], beside the HDMI bank
#: (TinyNES DEV-018): from PLL_L[3] the serial clock crossed the die and the
#: picture failed when warm.
HDMI_PLL27 = bringup.PLL.replace("wire mclk, pll_lock;", "wire clk27;") \
    .replace(".MDIV_SEL(16), .ODIV0_SEL(2),", ".MDIV_SEL(27), .ODIV0_SEL(50),") \
    .replace(") ddr_pll (", ") hdmi_pll27 (") \
    .replace(".LOCK(pll_lock), .CLKOUT0(mclk));", ".LOCK(), .CLKOUT0(clk27));")
HDMI_PLL = bringup.PLL.replace("    wire mclk, pll_lock;\n", "    wire hdmi_lock;\n") \
    .replace('.FCLKIN("50")', '.FCLKIN("27")') \
    .replace(".MDIV_SEL(16), .ODIV0_SEL(2),", ".MDIV_SEL(55), .ODIV0_SEL(20), .ODIV1_SEL(4),") \
    .replace('.CLKOUT0_EN("TRUE")', '.CLKOUT0_EN("TRUE"), .CLKOUT1_EN("TRUE")') \
    .replace(") ddr_pll (", ") hdmi_pll (") \
    .replace(".CLKIN(sys_clk)", ".CLKIN(clk27)") \
    .replace(".ENCLK1(1'b0)", ".ENCLK1(1'b1)") \
    .replace(".LOCK(pll_lock), .CLKOUT0(mclk));",
             ".LOCK(hdmi_lock), .CLKOUT0(pix_clk), .CLKOUT1(pix_clk5));")
assert "hdmi_pll27" in HDMI_PLL27 and ".CLKOUT0(pix_clk)" in HDMI_PLL and "ENCLK1(1'b1)" in HDMI_PLL
assert '.CLKOUT1_EN("TRUE")' in HDMI_PLL and ".ODIV0_SEL(20)" in HDMI_PLL
HDMI_CLOCKS = """
    // HDMI clocks.  pix_clk5 and pix_clk are kept by name for the SDC and
    // for tools/ae350_clock_check.py, which finds the pixel clock's route.
    (* keep *) wire pix_clk5;
    (* keep *) wire pix_clk;
""" + HDMI_PLL27 + HDMI_PLL + """
    // the pixel side's reset, released three pixel clocks after the PLL
    // locks, and synchronous (TOOL-073)
    reg [2:0] pix_rs = 3'b111;
    always @(posedge pix_clk)
        pix_rs <= {pix_rs[1:0], !hdmi_lock};
    wire pix_rst = pix_rs[2];"""

#: The AE350 image's own wiring: the AE350 system as the controller's second
#: client, and the UART, which is wr_core's until the hand-over (ctrl_glue's
#: command 0x3C 0x50) raises cpu_run and the AE350's from then on.  Each
#: side's receiver sees an idle line while the UART is the other's.
SOC_WIRES = """\
    wire core_rx, core_tx, soc_tx, cpu_run, x_rst;
    wire q_we;                                  // ahb_ddr3's crossing
    wire [3:0] q_waddr;
    wire [99:0] q_wdata;
    wire [4:0] q_wgray, q_rgray;
    wire [3:0] r_tog;
    wire [1:0] r_way;
    wire [255:0] r_slot;
    wire [2:0] p_open;                          // the bridge's PCLK reads in flight
    wire [27:0] arb_dbg;                        // ddr3_arb's state, for ddr3_perf
    wire x_valid, x_ready, x_we, x_rvalid;
    wire [24:0] x_addr;
    wire [255:0] x_wdata, x_rdata;
    wire [31:0] x_wmask;
    wire c_valid, c_ready, c_we, c_rvalid;      // the CPU's bridge into ddr3_arb
    wire [24:0] c_addr;
    wire [255:0] c_wdata, a_rdata;
    wire [31:0] c_wmask;
    wire v_valid, v_ready, v_rvalid;            // the video fetcher into ddr3_arb
    wire [24:0] v_addr;
    wire vid_enable, vid_base_tog, vid_base_ack, vid_vbl_tog, vid_in_vbl;
    wire [24:0] vid_base;
    wire [15:0] vid_late;
    wire req_tog;
    wire [24:0] req_addr;
    wire [2047:0] f_mem;
    wire [3:0] f_wg, f_rg;
    wire [23:0] vid_rgb;
    wire vid_de, vid_hs, vid_vs;
    wire [383:0] perf_snap;                     // ddr3_perf's counters, for exts_perf
    wire perf_snap_tog;
    assign core_rx = cpu_run ? 1'b1 : uart_rx;
    assign uart_tx = cpu_run ? soc_tx : core_tx;"""

SOC_INST = """
    // The instance's name sorts after bus_clk, which the flattened net keeps
    // for nextpnr's NPNR_GOWIN_CLK_FIRST (TinyNES DEV-016).  Everything
    // under soc is on the bus clock and is placed beside the AE350 macro
    // (tools/ae350_place.py); the bridge's PCLK half, xport, is not under it,
    // nor is its queue RAM, though written on bus_clk.
    ae350_sys soc (
        .bus_clk(bus_clk), .core_clk(core_clk), .pll_locked(cpu_lock), .run(cpu_run),
        .uart_tx(soc_tx), .uart_rx(cpu_run ? uart_rx : 1'b1),
        .q_we(q_we), .q_waddr(q_waddr), .q_wdata(q_wdata), .q_wgray(q_wgray),
        .q_rgray(q_rgray), .r_tog(r_tog), .r_way(r_way), .r_slot(r_slot),
        .vid_enable(vid_enable), .vid_base(vid_base), .vid_base_tog(vid_base_tog),
        .vid_base_ack(vid_base_ack), .vid_vbl_tog(vid_vbl_tog), .vid_in_vbl(vid_in_vbl),
        .vid_late(vid_late), .perf_snap(perf_snap), .perf_snap_tog(perf_snap_tog));
    ahb_ddr3_pclk #(.AW(25)) xport (
        .bus_clk(bus_clk), .pclk(pclk), .prst(x_rst),
        .q_we(q_we), .q_waddr(q_waddr), .q_wdata(q_wdata), .q_wgray(q_wgray),
        .q_rgray(q_rgray), .r_tog(r_tog), .r_way(r_way), .r_slot(r_slot), .p_open(p_open),
        .cmd_valid(c_valid), .cmd_ready(c_ready), .cmd_we(c_we), .cmd_addr(c_addr),
        .cmd_wdata(c_wdata), .cmd_wmask(c_wmask), .rdata_valid(c_rvalid), .rdata_line(a_rdata));
    // the video fetcher before the CPU onto ctrl_glue's CPU port
    ddr3_arb arb (
        .pclk(pclk), .rst(x_rst),
        .v_valid(v_valid), .v_ready(v_ready), .v_addr(v_addr), .v_rvalid(v_rvalid),
        .c_valid(c_valid), .c_ready(c_ready), .c_we(c_we), .c_addr(c_addr),
        .c_wdata(c_wdata), .c_wmask(c_wmask), .c_rvalid(c_rvalid), .rdata(a_rdata),
        .x_valid(x_valid), .x_ready(x_ready), .x_we(x_we), .x_addr(x_addr),
        .x_wdata(x_wdata), .x_wmask(x_wmask), .x_rvalid(x_rvalid), .x_rdata(x_rdata),
        .dbg(arb_dbg));
    // read-latency counters on both sides of the arbiter, for exts_perf
    ddr3_perf perf (
        .pclk(pclk), .rst(x_rst),
        .c_valid(c_valid), .c_ready(c_ready), .c_we(c_we), .c_rvalid(c_rvalid),
        .x_valid(x_valid), .x_ready(x_ready), .x_we(x_we), .x_rvalid(x_rvalid),
        .rd_load(ctrl_rd), .v_valid(v_valid), .v_ready(v_ready), .v_rvalid(v_rvalid),
        .arb_dbg(arb_dbg), .p_open(p_open), .snap(perf_snap), .snap_tog(perf_snap_tog));
    // 1280x720 from the DDR3: the fetcher on PCLK, the raster on pix_clk
    vid_fetch vfetch (
        .pclk(pclk), .rst(x_rst), .req_tog(req_tog), .req_addr(req_addr),
        .v_valid(v_valid), .v_ready(v_ready), .v_addr(v_addr),
        .v_rvalid(v_rvalid), .v_rdata(a_rdata),
        .f_mem(f_mem), .f_wg(f_wg), .f_rg(f_rg));
    vid_pix vpix (
        .pix_clk(pix_clk), .pix_rst(pix_rst),
        .enable(vid_enable), .base_line(vid_base), .base_tog(vid_base_tog),
        .base_ack(vid_base_ack), .vbl_tog(vid_vbl_tog), .in_vbl(vid_in_vbl), .late(vid_late),
        .req_tog(req_tog), .req_addr(req_addr), .f_mem(f_mem), .f_wg(f_wg), .f_rg(f_rg),
        .rgb(vid_rgb), .de(vid_de), .hs(vid_hs), .vs(vid_vs));
    dvi_tx hdmi (
        .pix_clk(pix_clk), .pix_clk5(pix_clk5),
        .rgb(vid_rgb), .de(vid_de), .hs(vid_hs), .vs(vid_vs),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n));"""


def render(ctrl: bool = False, soc: bool = False) -> str:
    ctrl = ctrl or soc
    ports = (["input wire sys_clk", "input wire uart_rx", "output wire uart_tx",
              "inout wire [31:0] ddr_dq"]
             + [f"inout wire ddr_dqs{l}_p, inout wire ddr_dqs{l}_n" for l in pads.LANES]
             + ["output wire [3:0] ddr_dm", "output wire ddr_ck_p", "output wire ddr_ck_n",
                "output wire ddr_reset_n"]
             + [f"output wire {p}" for p, _ in cmd.CMD_BALLS]
             + (["output wire tmds_clk_p", "output wire tmds_clk_n",
                 "output wire [2:0] tmds_d_p", "output wire [2:0] tmds_d_n"] if soc else []))
    out = ["// Generated by tools/ddr3_write.py; do not edit.",
           "`default_nettype none",
           "module top (\n    " + ",\n    ".join(ports) + "\n);",
           PLL] + ([CPU_PLL, HDMI_CLOCKS, SOC_WIRES] if soc else []) + [
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
            "    wire [7:0] dq_npat = ~dq_pat;"]
    if not ctrl:
        out.append("    wire [7:0] dm_d = 8'h00;    // DM low: every byte written")
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
        if ctrl:    # the controller's write mask, through the boundary
            out.append(f"    wire [7:0] dm{l}_d = dm_b[{8 * l} +: 8];")
        out.append(OSER_MEM.format(n=f"dm{l}", src='"DQSW"', tclk=f"w0_{l}",
                                   d=(f"dm{l}_d" if ctrl else "dm_d"), t="dq_tx"))
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
        ports = WR_CORE_PORTS
        glue_p = "ctrl_glue glue"
        x_ports = """
        .x_valid(1'b0), .x_we(1'b0), .x_addr(25'd0), .x_wdata(256'd0), .x_wmask(32'd0),
        .x_ready(), .x_rvalid(), .x_rdata(), .x_rst(), .cpu_run());"""
        if soc:
            ports = ports.replace(".uart_rx(uart_rx), .uart_tx(uart_tx)",
                                  ".uart_rx(core_rx), .uart_tx(core_tx)")
            glue_p = "ctrl_glue #(.CPU(1)) glue"
            x_ports = """
        .x_valid(x_valid), .x_we(x_we), .x_addr(x_addr), .x_wdata(x_wdata), .x_wmask(x_wmask),
        .x_ready(x_ready), .x_rvalid(x_rvalid), .x_rdata(x_rdata), .x_rst(x_rst),
        .cpu_run(cpu_run));""" + SOC_INST
        out.append("    wr_core #(.AUTOTRAIN(1)) core (\n" + ports + """
        .ctrl_rd(ctrl_rd), .ctrl_accept(ctrl_accept), .ctrl_own(ctrl_own), .ctrl_walign(ctrl_walign),
        .ctrl_own_x(ctrl_own_x), .ctrl_rot(ctrl_rot), .ctrl_trained(ctrl_trained),
        .ext_cmd(ext_cmd), .ext_tog(ext_tog), .ext_status(ext_status));
    """ + glue_p + """ (
        .sys_clk(sys_clk), .pclk(pclk), .dq_q(dq_q),
        .wc_cs_n(cs_n), .wc_ras_n(ras_n), .wc_cas_n(cas_n), .wc_we_n(we_n),
        .wc_ba(ba), .wc_addr(addr), .wc_odt(odt), .wc_dq_pat(dq_pat),
        .wc_dq_drive(dq_drive), .wc_dqs_drive(dqs_drive),
        .ctrl_own(ctrl_own), .ctrl_own_x(ctrl_own_x), .ctrl_trained(ctrl_trained), .ctrl_walign(ctrl_walign),
        .ctrl_rot(ctrl_rot), .ext_cmd(ext_cmd), .ext_tog(ext_tog),
        .p_cs_n(p_cs_n), .p_ras_n(p_ras_n), .p_cas_n(p_cas_n), .p_we_n(p_we_n),
        .p_ba(p_ba), .p_addr(p_addr), .p_odt(p_odt), .p_dq_drive(p_dq_drive),
        .p_dqs_drive(p_dqs_drive), .wdq(wdq), .dm(dm), .ctrl_rd(ctrl_rd), .ctrl_accept(ctrl_accept),
        .ext_status(ext_status),""" + x_ports)
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
#: the AE350 image: PLL_R[0] for the CPU (TinyNES ae350_soc.cst), and the
#: bus clock constrained, which TinyNES's build gave nextpnr as --freq 75
#: and the HDMI port and PLLs where TinyNES has them (DEV-018)
HDMI_CST = """\
INS_LOC "hdmi_pll27" PLL_R[1];
INS_LOC "hdmi_pll" PLL_R[3];
""" + "".join(f'IO_LOC "{n}" {b};\n' for n, b in (
    ("tmds_clk_p", "G15"), ("tmds_clk_n", "G16"), ("tmds_d_p[0]", "J14"), ("tmds_d_n[0]", "H14"),
    ("tmds_d_p[1]", "J15"), ("tmds_d_n[1]", "H15"), ("tmds_d_p[2]", "K17"), ("tmds_d_n[2]", "J17"))) \
    + "".join(f'IO_PORT "{n}" IO_TYPE=LVCMOS33D PULL_MODE=NONE;\n' for n in (
        "tmds_clk_p", "tmds_clk_n", "tmds_d_p[0]", "tmds_d_n[0]", "tmds_d_p[1]", "tmds_d_n[1]",
        "tmds_d_p[2]", "tmds_d_n[2]"))
GENERATED_SOC = {"top.v": lambda: render(soc=True),
                 "top.cst": lambda: bringup.cst() + 'INS_LOC "cpu_pll" PLL_R[0];\n' + HDMI_CST,
                 "open.sdc": lambda: SDC_OPEN
                 + "create_clock -name bus_clk -period 13.333 [get_nets {bus_clk}]\n"
                 + "create_clock -name pix_clk5 -period 2.694 [get_nets {pix_clk5}]\n"
                 + "create_clock -name pix_clk -period 13.468 [get_nets {pix_clk}]\n"}


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
    for src, generated in ((SRC, GENERATED), (SRC_CTRL, GENERATED_CTRL), (SRC_SOC, GENERATED_SOC)):
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
