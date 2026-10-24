#!/usr/bin/env python3
"""Build the vendor designs that expose lane 0's complete pads.

`tools/dq_lane_probe.py` measured one serializer per pad.  The proven
controller (Tang-PSX `ddr3_memory_interface.vo`) builds each lane-0 pad from
several primitives at once, and this tool reproduces those shapes on top of
the B1 `base` lane of `tools/dqs_param_probe.py`:

`dq_*`
    `dq[0]` on Y4: an `IOBUF` whose `I` and `OEN` come from an `OSER8_MEM`'s
    `Q0` and `Q1`, and whose `O` reaches an `IDES8_MEM` through a static
    `IODELAY` (`C_STATIC_DLY=5`), exactly as `dq_iobuf_gen[0]` does.
    `dq_nodelay_*` drops the `IODELAY` to see whether Gowin requires it.

`dqs_*`
    The strobe: an `ELVDS_IOBUF` over Y3 and AA3 whose `O` is `DQS.DQSIN`,
    driven by the strobe `OSER8_MEM` with `TCLK_SOURCE="DQSW270"`.

`dm_*`
    `dm[0]` on AA4: a `TBUF` driven by an `OSER8_MEM`.

The DQ and DM shapes are built with `LVCMOS33`, comparable with the earlier
lane measurements, and with the proven `SSTL15` at `BANK_VCCIO=1.5`; in the
SSTL designs the DQS pad is SSTL too, because one bank takes one VCCIO.  The
strobe is built in `SSTL15D` only: `LVCMOS33D` is not a differential standard
Gowin accepts on an `ELVDS_IOBUF` (`CT1109`).
The pads are on bank 6.  Nothing here packs an open-flow image or touches the
board.

`--check` builds nothing: it asserts the recorded results on the built
designs -- the IOLOGIC attributes of every pad (the bidirectional pad carries
exactly the union of the two serializers' sets, plus the `IODELAY`'s), that
the IO standard leaves IOLOGIC untouched, that SSTL changes only the pads'
IOB entries and bank 6's `BANK` table, and no unattributed fuse in any
design's difference from the B1 `base`.

Usage:
    tools/dq_pad_probe.py
    tools/dq_pad_probe.py --only dq_sstl,dqs_sstl
    tools/dq_pad_probe.py --check
"""

import argparse
import os
import shutil
import sys

import dqs_param_probe as lane
import dqs_port_probe as base

HEAD = "module top (input wire clk, input wire dqsi, output wire q);"

OSER = """\
    wire @N@_o, @N@_t;
    reg [7:0] @N@_d = 8'h00;
    always @(posedge clk) @N@_d <= {@N@_d[6:0], sig_r};
    OSER8_MEM #(.HWL("false"), .TCLK_SOURCE(@SRC@), .TXCLK_POL(1'b0)) @N@_ser (
        .D0(@N@_d[0]), .D1(@N@_d[1]), .D2(@N@_d[2]), .D3(@N@_d[3]),
        .D4(@N@_d[4]), .D5(@N@_d[5]), .D6(@N@_d[6]), .D7(@N@_d[7]),
        .TX0(sig_s), .TX1(sig_s), .TX2(sig_s), .TX3(sig_s),
        .PCLK(clk), .FCLK(clk), .TCLK(@TCLK@), .RESET(1'b0),
        .Q0(@N@_o), .Q1(@N@_t));
"""

IDES = """\
    wire [7:0] dq_q;
    IDES8_MEM dq_des (.D(@D@), .ICLK(r90), .PCLK(clk), .FCLK(clk),
                      .RESET(1'b0), .CALIB(1'b0), .WADDR(wp), .RADDR(rp),
                      .Q0(dq_q[0]), .Q1(dq_q[1]), .Q2(dq_q[2]), .Q3(dq_q[3]),
                      .Q4(dq_q[4]), .Q5(dq_q[5]), .Q6(dq_q[6]), .Q7(dq_q[7]));
"""

DELAY = """\
    wire dq_dly;
    IODELAY #(.C_STATIC_DLY(5), .DYN_DLY_EN("FALSE"), .ADAPT_EN("FALSE")) dq_delay (
        .DI(dq_i), .SDTAP(1'b0), .VALUE(1'b0), .DLYSTEP(8'h00), .DO(dq_dly), .DF());
"""


def oser(name: str, strobe: bool = False) -> str:
    return (OSER.replace("@N@", name)
            .replace("@SRC@", '"DQSW270"' if strobe else '"DQSW"')
            .replace("@TCLK@", "w270" if strobe else "w0"))


def render(shape: str, delay: bool = True) -> str:
    text = lane._source()
    if HEAD not in text:
        raise SystemExit("lane template changed: module header not found")
    body, ports, extra_q = "", "", ""
    if shape == "dq":
        ports = ", inout wire dq_pad"
        body = oser("dq") + "    wire dq_i;\n    IOBUF dq_buf (.I(dq_o), .OEN(dq_t), .IO(dq_pad), .O(dq_i));\n"
        if delay:
            body += DELAY + IDES.replace("@D@", "dq_dly")
        else:
            body += IDES.replace("@D@", "dq_i")
        extra_q = " ^ ^dq_q"
    elif shape == "dqs":
        ports = ", inout wire dqs_p, inout wire dqs_n"
        body = (oser("st", strobe=True)
                + "    ELVDS_IOBUF dqs_buf (.I(st_o), .OEN(st_t), .IO(dqs_p), .IOB(dqs_n), .O(dqsi_buf));\n")
    elif shape == "dm":
        ports = ", output wire dm_pad"
        body = oser("dm") + "    TBUF dm_buf (.I(dm_o), .OEN(dm_t), .O(dm_pad));\n"
    else:
        raise SystemExit(f"unknown shape {shape}")

    if shape == "dqs":
        # the strobe pad replaces the plain DQSIN input of the base lane
        text = text.replace(HEAD, f"module top (input wire clk, output wire q{ports});")
        text = text.replace("    wire [7:0] step;", "    wire [7:0] step;\n    wire dqsi_buf;")
        text = text.replace(".DQSIN(dqsi)", ".DQSIN(dqsi_buf)")
        text = text.replace("assign q = dqsi ^", "assign q = dqsi_buf ^")
    else:
        text = text.replace(HEAD, f"module top (input wire clk, input wire dqsi, output wire q{ports});")
    text = text.replace("    assign unused = 1'b0;", body + "    assign unused = 1'b0;")
    text = text.replace("^ sig_r ^ sig_s ^ ^step;", f"^ sig_r ^ sig_s ^ ^step{extra_q};")
    return text


def cst(shape: str, sstl: bool) -> str:
    single = ('IO_TYPE=SSTL15 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=1.5' if sstl
              else 'IO_TYPE=LVCMOS33 PULL_MODE=NONE')
    # Gowin refuses DRIVE on an input port (CT1108)
    single_in = ('IO_TYPE=SSTL15 PULL_MODE=NONE BANK_VCCIO=1.5' if sstl
                 else 'IO_TYPE=LVCMOS33 PULL_MODE=NONE')
    diff = ('IO_TYPE=SSTL15D PULL_MODE=NONE DRIVE=8 BANK_VCCIO=1.5' if sstl
            else 'IO_TYPE=LVCMOS33D PULL_MODE=NONE')
    lines = ['IO_LOC "clk" V22;', 'IO_PORT "clk" IO_TYPE=LVCMOS33 PULL_MODE=NONE;',
             'IO_LOC "q" F18;', 'IO_PORT "q" IO_TYPE=LVCMOS33 PULL_MODE=NONE;',
             'INS_LOC "dll" DDRDLLM_BL;']
    if shape == "dqs":
        lines += ['IO_LOC "dqs_p" Y3,AA3;', f'IO_PORT "dqs_p" {diff};']
    else:
        lines += ['IO_LOC "dqsi" Y3;', f'IO_PORT "dqsi" {single_in};']
    if shape == "dq":
        lines += ['IO_LOC "dq_pad" Y4;', f'IO_PORT "dq_pad" {single};']
    if shape == "dm":
        lines += ['IO_LOC "dm_pad" AA4;', f'IO_PORT "dm_pad" {single};']
    return "\n".join(lines) + "\n"


#: name -> (shape, IODELAY present, SSTL)
DESIGNS = {
    "dq_lvcmos": ("dq", True, False),
    "dq_sstl": ("dq", True, True),
    "dq_nodelay_sstl": ("dq", False, True),
    "dqs_sstl": ("dqs", True, True),
    "dm_lvcmos": ("dm", True, False),
    "dm_sstl": ("dm", True, True),
}


#: The IODELAY's attributes at the pad's IOLOGIC (`C_STATIC_DLY=5`), as
#: decoded entry names; attribute 133 has no name in `attrids`.
IODELAY_ATTRS = {"133=118", "C_STATIC_DLY=1005"}

#: (design, pad row, IOLOGIC side) -> the decoded attribute set, built from
#: the single-serializer sets `tools/dq_lane_probe.py` recorded.
def expected():
    import dq_lane_probe as one
    oser, ides = one.expected_attrs("ok_oser"), one.expected_attrs("ok_ides")
    strobe = one.expected_attrs("par_tclk270")
    out = {}
    for name in ("dq_lvcmos", "dq_sstl"):
        out[(name, 77, "A")] = oser | ides | IODELAY_ATTRS
    out[("dq_nodelay_sstl", 77, "A")] = oser | ides
    out[("dqs_sstl", 68, "A")] = strobe
    out[("dqs_sstl", 68, "B")] = set()
    for name in ("dm_lvcmos", "dm_sstl"):
        out[(name, 77, "B")] = oser
    return out


#: SSTL against LVCMOS: the cells allowed to change outside routing.
SSTL_CELLS = {"dq_sstl": {(68, 0), (77, 0), (90, 0)},
              "dm_sstl": {(68, 0), (78, 0), (90, 0)}}


def check(out_dir: str) -> int:
    import fs_attribute as fa
    import fs_site_diff as fsd
    from apycula import attrids

    dev = fsd.chipdb.load_chipdb(fsd.DB)
    grid = fsd.Grid(dev)
    ids = {v: k for k, v in attrids.iologic_attrids.items()}
    vals = {v: k for k, v in attrids.iologic_attrvals.items()}
    rev = {v: k for k, v in dev.logicinfo["IOLOGIC"].items()}

    def decoded(m, row, side):
        cell = (row if side == "A" else row + 1, 0)
        table = dev.shortval[dev.grid[cell[0]][0]][f"IOLOGIC{side}"]
        st = fa.tile_state(dev, grid, m, cell)
        lit = [(k, {tuple(f) for f in v}) for k, v in table.items()
               if v and {tuple(f) for f in v} <= st]
        top = [k for k, f in lit if not any(f < g for _, g in lit)]
        return {" & ".join(f"{ids.get(rev[i][0], rev[i][0])}={vals.get(rev[i][1], rev[i][1])}"
                           for i in k if i) for k in top}

    fs = lambda n: os.path.join(out_dir, n, "impl/pnr/probe.fs")
    base_m = fsd.load_matrix(os.path.join(base.ROOT, "build/dqs_b1/base/impl/pnr/probe.fs"))
    failures = 0

    def report(ok, line):
        nonlocal failures
        print(f"  {'PASS' if ok else 'FAIL'}  {line}", flush=True)
        failures += not ok

    want = expected()
    for name in DESIGNS:
        if not os.path.exists(fs(name)):
            report(False, f"{name}: not built")
            continue
        m = fsd.load_matrix(fs(name))
        for (n, row, side), attrs in want.items():
            if n == name:
                got = decoded(m, row, side)
                report(got == attrs, f"{name:16s} IOLOGIC{side} of row {row}: {len(got)} attributes"
                       + ("" if got == attrs else f"; extra {sorted(got - attrs)} missing {sorted(attrs - got)}"))
        unattr = sum(len(r["unattributed"]) for r in fa.attribute(dev, grid, base_m, m))
        report(unattr == 0, f"{name:16s} {unattr} unattributed against base")
        if name in SSTL_CELLS:
            lv = fsd.load_matrix(fs(name.replace("_sstl", "_lvcmos")))
            reps = fa.attribute(dev, grid, lv, m)
            del lv
            moved = {tuple(r["tile"]) for r in reps if r["config"] or r["unattributed"]}
            report(moved <= SSTL_CELLS[name],
                   f"{name:16s} SSTL against LVCMOS configures only {sorted(moved)}")
        del m
    print(f"\n{'All checks passed' if not failures else f'{failures} check(s) failed'}.  "
          "Hardware was not accessed.")
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", help="comma-separated subset of " + ",".join(DESIGNS))
    ap.add_argument("--out", default=os.path.join(base.ROOT, "build/dq_pad"))
    ap.add_argument("--check", action="store_true",
                    help="assert the recorded results on built designs; build nothing")
    args = ap.parse_args()
    if args.check:
        return check(args.out)
    names = [n for n in (args.only or ",".join(DESIGNS)).split(",") if n]
    unknown = [n for n in names if n not in DESIGNS]
    if unknown:
        print(f"unknown design(s): {unknown}", file=sys.stderr)
        return 2
    if not os.path.isdir(os.path.join(base.GOWIN, "IDE")):
        print(f"missing Gowin EDA at {base.GOWIN}", file=sys.stderr)
        return 2
    for name in names:
        shape, delay, sstl = DESIGNS[name]
        d = os.path.join(args.out, name)
        if os.path.isdir(d):
            shutil.rmtree(d)
        os.makedirs(d)
        for fn, body in (("top.v", render(shape, delay)), ("top.cst", cst(shape, sstl)),
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
