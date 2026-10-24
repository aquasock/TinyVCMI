#!/usr/bin/env python3
"""Build the DDR3 lane vendor designs in the open flow and check placement.

Every vendor design that `tools/dqs_param_probe.py`, `tools/dq_lane_probe.py`
and `tools/dq_pad_probe.py` built for Gowin EDA keeps its own `top.v`,
`top.cst` and `top.sdc`.  This tool runs the same three files through Yosys
and nextpnr-himbaechel, writes the routed netlist the in-process packer checks
read (`tools/dqs_pack_check.py`, `tools/dq_pack_check.py`), and asserts what
the open model must reproduce:

* a `fab_*` design, which Gowin refuses with `CK2060`, fails in nextpnr too,
  and so does a `bad_*` design, an invalid parameter the cell packer refuses;
* every other design places and routes, and its `DQS` sits on the lane's site
  (TOOL-011), the one `pack_dqs` locks it to through its strobe pad;
* every `OSER8_MEM` and `IDES8_MEM` sits on the IOLOGIC beside a placed pad,
  on that pad's side (the packer disconnects the dedicated pad path, so the
  pad is found by position);
* each memory-mode pin is on its DQS output's net, bit for bit: `TCLK_DQSW0`
  on `DQSW0`, `TCLK_DQSW270` on `DQSW270`, `ICLK` on `DQSR90`, `WADDR` on
  `WPOINT` and `RADDR` on `RPOINT`.

It reports the HCLK lane the router put the DQS's `FCLK` on and any warning
that a net feeding a DQS `FCLK` was split across lanes.  It writes no image,
so the packer's DDR3-bank guard is not involved, and it needs no board.

`--pack` then runs the in-process packer checks on every routed design
against its own vendor bitstream: `tools/dqs_pack_check.py --lane N` for the
`dqs_b1` designs, by table-58 key at the lane's byte group, and
`tools/dq_pack_check.py` for every design with a serializer.  A serializer
design whose clock both routers can carry on one lane -- `*_lane0` and
`*_lane2`, the IOLOGIC lanes the model spells -- must match exactly; any
other is compared outside the lane field, since the vendor carried its clock
on a lane the open model does not offer an IOLOGIC.  Each check holds one
vendor bitstream, about 1.5 GB, so `--pack-jobs` stays small.

Output goes to `build/open/<vendor directory>/<design>/`, for example
`build/open/dqs_b1_l2/base/routed.json`.

Usage:
    tools/lane_open_build.py --lane 1
    tools/lane_open_build.py --lane 0 --lane 1 --lane 2 --lane 3 --jobs 4
    tools/lane_open_build.py --lane 3 --sets dq_lane --only ok_oser,fab_tclk
    tools/lane_open_build.py --lane 2 --pack

Run it with the open-flow environment sourced (`tools/openflow_env.sh`).
"""

import argparse
import concurrent.futures
import json
import os
import re
import subprocess
import sys

import dqs_port_probe as base

#: vendor build sets, each a directory per lane through `base.lane_dir`;
#: `cmd_pad`, bank 7's address and command pads, belongs to no lane and is
#: read as lane 0's
SETS = ("dqs_b1", "dq_lane", "dq_lane_b", "dq_pad", "cmd_pad")

#: memory-mode pin -> the DQS output it is hard-wired from (TOOL-009)
MEM_LINKS = {"TCLK_DQSW0": "DQSW0", "TCLK_DQSW270": "DQSW270", "ICLK": "DQSR90",
             "WADDR": "WPOINT", "RADDR": "RPOINT"}

#: serializer -> the IOLOGIC half it occupies
SERIALIZERS = {"OSER8_MEM": "O", "IDES8_MEM": "I"}


def site_bel(lane: int) -> str:
    """The lane's DQS bel in nextpnr's name; `LANES` holds `(row, col)`."""
    row, col = base.LANES[lane]["site"]
    return f"X{col}Y{row}/DQS"


def build(src: str, out: str) -> tuple:
    """Synthesize and place-and-route one vendor design; (ok, pnr log text)."""
    os.makedirs(out, exist_ok=True)
    cells = os.path.join(os.environ["OSS_CAD_SUITE"], "share/yosys/gowin/cells_xtra_gw5a.v")
    top_json = os.path.join(out, "top.json")
    routed = os.path.join(out, "routed.json")
    if os.path.exists(routed):
        os.remove(routed)
    synth = subprocess.run(
        ["yosys", "-Q", "-T", "-q", "-l", os.path.join(out, "synth.log"), "-p",
         f"read_verilog -lib {cells}; read_verilog {os.path.join(src, 'top.v')}; "
         f"synth_gowin -family gw5a -top top; write_json {top_json}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    if synth.returncode != 0:
        return False, "synthesis failed"
    with open(os.path.join(out, "pnr.log"), "w") as log:
        pnr = subprocess.run(
            [os.environ["NEXTPNR_HIMBAECHEL"], "--json", top_json, "--write", routed,
             "--device", os.environ["GOWIN_DEVICE"], "--freq", "50",
             "--vopt", f"cst={os.path.join(src, 'top.cst')}",
             "--sdc", os.path.join(src, "top.sdc")],
            stdout=log, stderr=subprocess.STDOUT)
    with open(os.path.join(out, "pnr.log")) as log:
        text = log.read()
    return pnr.returncode == 0 and os.path.exists(routed), text


def port_bits(cell: dict) -> dict:
    """`{"WADDR[1]": bit, ...}`: a cell's connections one bit per name."""
    bits = {}
    for port, conn in cell["connections"].items():
        if len(conn) == 1:
            bits[port] = conn[0]
        else:
            for i, b in enumerate(conn):
                bits[f"{port}[{i}]"] = b
    return bits


def check_routed(routed: str, lane: int) -> list:
    """Every placement and link problem in one routed netlist, as text."""
    with open(routed) as f:
        top = json.load(f)["modules"]["top"]
    cells = top["cells"]
    bel = {name: c["attributes"].get("NEXTPNR_BEL", "") for name, c in cells.items()}
    problems = []

    dqs = [n for n, c in cells.items() if c["type"] == "DQS"]
    if len(dqs) > 1:
        problems.append(f"{len(dqs)} DQS cells")
    want = site_bel(lane)
    for n in dqs:
        if bel[n] != want:
            problems.append(f"DQS {n} on {bel[n]!r}, not {want}")
    dqs_bits = port_bits(cells[dqs[0]]) if dqs else {}

    # the packer disconnects a serializer from its pad, whose path is
    # dedicated, so the pad is found by position: the IOB of the same side
    iobs = {bel[n] for n in cells if re.fullmatch(r"X\d+Y\d+/IOB[AB]", bel[n])}

    for n, c in cells.items():
        io = SERIALIZERS.get(c["type"])
        if io is None:
            continue
        bits = port_bits(c)
        m = re.fullmatch(rf"(X\d+Y\d+)/IOLOGIC([AB]){io}", bel[n])
        if m is None or f"{m.group(1)}/IOB{m.group(2)}" not in iobs:
            problems.append(f"{c['type']} {n} on {bel[n]!r}, which is not the IOLOGIC "
                            f"{io} half of a placed pad")
        linked = 0
        for pin, b in bits.items():
            m = re.fullmatch(r"(\w+?)(\[\d\])?", pin)
            src = MEM_LINKS.get(m.group(1))
            if src is None:
                continue
            linked += 1
            want_bit = dqs_bits.get(src + (m.group(2) or ""))
            if want_bit != b:
                problems.append(f"{c['type']} {n}.{pin} is not on DQS.{src}{m.group(2) or ''}")
        if linked == 0:
            problems.append(f"{c['type']} {n} has no memory-mode pin")
    return problems


def fclk_lanes(routed: str) -> list:
    with open(routed) as f:
        return sorted(set(re.findall(r"X\d+Y\d+/DQS_FCLK/HCLK2([0-3])", f.read())))


def run_one(job):
    lane, src, out, name = job
    ok, log = build(src, out)
    split = "carried on" in log and "HCLK lanes" in log
    if name.startswith(("fab_", "bad_")):
        passed = not ok
        detail = "refused, as intended" if passed else "placed and routed; it must be refused"
        return passed, f"{'PASS' if passed else 'FAIL'}  {out}: {detail}"
    if not ok:
        err = next((l for l in log.splitlines() if "ERROR" in l), "no routed netlist")
        return False, f"FAIL  {out}: {err.strip()}"
    routed = os.path.join(out, "routed.json")
    problems = check_routed(routed, lane)
    lanes = fclk_lanes(routed)
    detail = f"FCLK lane {','.join(lanes) or '-'}" + ("; lane split warned" if split else "")
    if problems:
        return False, f"FAIL  {out}: {detail}; " + "; ".join(problems)
    return True, f"PASS  {out}: {detail}"


def pack_one(job):
    """Run the in-process packer check that applies to one routed design."""
    lane, src, out, name = job
    routed = os.path.join(out, "routed.json")
    vendor = os.path.join(src, "impl/pnr/probe.fs")
    with open(routed) as f:
        types = {c["type"] for c in json.load(f)["modules"]["top"]["cells"].values()}
    here = os.path.dirname(os.path.abspath(__file__))
    tag = out.replace(base.ROOT + "/", "")
    if not os.path.exists(vendor):
        # Gowin refused the design, for a reason outside the lane model:
        # dq_pad's dqs_lvcmos asks for LVCMOS33D on an ELVDS_IOBUF (CT1109)
        return True, f"skip  {tag}: no vendor bitstream to compare against"
    if os.path.basename(os.path.dirname(out)).startswith("dqs_b1"):
        if "DQS" not in types:
            return True, f"skip  {tag}: no DQS"
        cmd, mode = [os.path.join(here, "dqs_pack_check.py"), routed, "--vendor", vendor,
                     "--lane", str(lane)], "by table key"
    elif types & set(SERIALIZERS):
        exact = re.search(r"_lane[02]$", name) is not None
        cmd = [os.path.join(here, "dq_pack_check.py"), routed, "--vendor", vendor]
        if not exact:
            cmd.append("--outside-lane")
        mode = "exactly" if exact else "outside the lane field"
    else:
        return True, f"skip  {tag}: nothing to pack"
    r = subprocess.run([sys.executable] + cmd, capture_output=True, text=True)
    if r.returncode == 0:
        return True, f"PASS  {tag}: packer equals vendor {mode}"
    fails = [l.strip() for l in r.stdout.splitlines() if l.strip().startswith("FAIL")]
    return False, f"FAIL  {tag}: {mode}; " + " | ".join(fails or [r.stderr.strip()[-300:]])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lane", type=int, action="append", choices=sorted(base.LANES),
                    required=True)
    ap.add_argument("--sets", default=",".join(SETS),
                    help="comma-separated subset of " + ",".join(SETS))
    ap.add_argument("--only", help="comma-separated design names")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--pack", action="store_true",
                    help="also run the in-process packer checks on every routed design")
    ap.add_argument("--pack-jobs", type=int, default=2)
    args = ap.parse_args()
    for var in ("OSS_CAD_SUITE", "NEXTPNR_HIMBAECHEL", "GOWIN_DEVICE"):
        if var not in os.environ:
            print(f"{var} is not set; source tools/openflow_env.sh", file=sys.stderr)
            return 2
    only = set(args.only.split(",")) if args.only else None

    jobs = []
    for lane in args.lane:
        for s in args.sets.split(","):
            vendor = base.lane_dir(os.path.join(base.ROOT, "build", s), lane)
            if not os.path.isdir(vendor):
                continue
            for name in sorted(os.listdir(vendor)):
                src = os.path.join(vendor, name)
                if not os.path.exists(os.path.join(src, "top.v")):
                    continue
                if only is not None and name not in only:
                    continue
                out = os.path.join(base.ROOT, "build", "open", os.path.basename(vendor), name)
                jobs.append((lane, src, out, name))
    if not jobs:
        print("no vendor designs found", file=sys.stderr)
        return 2

    failures = 0
    routed = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for job, (passed, line) in zip(jobs, pool.map(run_one, jobs)):
            print(line.replace(base.ROOT + "/", ""), flush=True)
            failures += not passed
            if passed and not job[3].startswith(("fab_", "bad_")):
                routed.append(job)
    print(f"\n{len(jobs) - failures} of {len(jobs)} designs as expected")
    if args.pack:
        pack_failures = checked = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.pack_jobs) as pool:
            for passed, line in pool.map(pack_one, routed):
                print(line, flush=True)
                checked += not line.startswith("skip")
                pack_failures += not passed
        print(f"\n{checked - pack_failures} of {checked} packer checks passed; "
              "no bitstream was written")
        failures += pack_failures
    print("Hardware was not accessed.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
