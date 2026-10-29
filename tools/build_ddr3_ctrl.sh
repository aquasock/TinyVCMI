#!/usr/bin/env bash
# Build the DDR3 controller image in the open flow, check it against the
# vendor's build of the same sources, and only then write the raw images
# TinyTang loads.
#
# The image is fpga/ddr3_ctrl: tools/ddr3_write.py generates top.v and its
# constraints from the write image's templates, so every primitive, instance
# name and constraint is the write image's; wr_core.v, rd_align.v and
# rd_check.v are fpga/ddr3_write's, with wr_core training itself at start-up
# (AUTOTRAIN) and handing the bus to fpga/ddr3_ctrl/ctrl_glue.v -- the
# controller ddr3_ctl, dfi_phy and the memory test.  The vendor reference, built with `tools/ddr3_write.py --vendor
# --ctrl`, is needed by step 6 only.  Steps:
#
#   1. the manifest and the generated sources are current;
#   2. the write image's unit and image simulations, wr_core being shared,
#      and tools/sim_ddr3_ctrl.sh's simulation of the controller's fabric;
#   3. Yosys, nextpnr -- which fails the build on
#      a clock constraint that matches no net or a constrained cell it cannot
#      find, the failure of TOOL-032 -- and `gowin_pack --ddr3-context`;
#   4. tools/ddr3_image_check.py --exact-lanes against the vendor build of
#      the same sources; the vendor build needs to meet timing only to be a
#      board control, so a miss is a warning and no control is written;
#   5. the open-flow .bin, and the vendor control when it meets timing.
#
# Nothing here touches the board.  Loading is a separate, approved step.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"

src="$root/fpga/ddr3_ctrl"
wsrc="$root/fpga/ddr3_write"
out=${TINYVCMI_CTRL_DIR:-$root/build/ddr3_ctrl/open}
vendor="$root/build/ddr3_ctrl/vendor"
manifest="$root/fpga/ddr3/ddr3_balls.json"
cells="$oss_suite/share/yosys/gowin/cells_xtra_gw5a.v"

mkdir -p "$out"

echo "[1/6] manifest and generated sources"
(cd "$root/tools" && python3 ddr3_ball_manifest.py --check && python3 ddr3_write.py --check)

echo "[2/6] simulation"
if [[ ${TINYVCMI_SKIP_SIM:-0} == 1 ]]; then
    echo "skipped by TINYVCMI_SKIP_SIM=1 (use only after a separate passing run)"
else
    "$root/tools/sim_rd_align.sh"
    "$root/tools/sim_rd_check.sh"
    "$root/tools/sim_ddr3_seq.sh"
    "$root/tools/sim_ddr3_write.sh"
    "$root/tools/sim_ddr3_ctrl.sh"
fi

echo "[3/6] Yosys synthesis"
yosys -Q -T -q -l "$out/synth.log" -p "
    read_verilog -lib $cells
    read_verilog $src/top.v $wsrc/wr_core.v $wsrc/rd_align.v $wsrc/rd_check.v
    read_verilog $src/ctrl_glue.v $src/dfi_phy.v $src/ddr3_derot.v $src/ddr3_bist.v
    read_verilog $src/ddr3_ctl.v
    synth_gowin -family gw5a -top top ${TINYVCMI_SYNTH_OPTS:-}
    write_json $out/ctrl.json
"

# The I/O boundary's falling-edge registers must reach nextpnr as the DFFN and
# DFFNS top.v instantiates, clocked straight from the CLKDIV, and no LUT may
# drive a clock pin anywhere: Yosys once built 25 of them as rising-edge flops
# behind a LUT1 inverting pclk, splitting each DRAM command across two PCLK
# with nothing in either timer to see it (TOOL-051).
python3 - "$out/ctrl.json" <<'PY'
import json, re, sys
m = json.load(open(sys.argv[1]))["modules"]["top"]
# flattened, bnd_ff's register is bnd_lo[i].ff.r.ff or bnd_hi[i].ff.s.ff;
# other cells take bnd_ names from the nets they drive
reg = re.compile(r"^(bnd_lo\[|bnd_hi\[)\d+\]\.ff\.[rs]\.ff$")
drv = {}
for name, c in m["cells"].items():
    for p, d in c.get("port_directions", {}).items():
        if d == "output":
            for b in c["connections"][p]:
                drv[b] = (name, c["type"])
bad, want = [], {"bnd_lo[": ("DFFN", 469), "bnd_hi[": ("DFFNS", 18)}
seen = dict.fromkeys(want, 0)
for name, c in m["cells"].items():
    for p in ("CLK", "PCLK", "FCLK", "ICLK", "TCLK"):
        if p in c["connections"] and drv.get(c["connections"][p][0], ("", ""))[1].startswith("LUT"):
            bad.append(f"{name} ({c['type']}) {p} is driven by a LUT")
    r = reg.match(name)
    for pre, (typ, _) in want.items():
        if r and r.group(1) == pre:
            seen[pre] += 1
            src = drv.get(c["connections"].get("CLK", [None])[0], ("", ""))[1]
            if c["type"] != typ or src != "CLKDIV":
                bad.append(f"{name} is {c['type']} clocked from {src or 'nothing'}, not {typ} on the CLKDIV")
bad += [f"{n} of {pre}*] found, {cnt} expected" for pre, n in seen.items()
        for cnt in [want[pre][1]] if n != cnt]
if bad:
    print("\n".join(bad[:20]), file=sys.stderr)
    sys.exit("the I/O boundary did not synthesise as instantiated (TOOL-051)")
print("boundary: 469 DFFN and 18 DFFNS on the CLKDIV; no LUT drives a clock")
PY

echo "[4/6] nextpnr placement and routing"
"$nextpnr_himbaechel" \
    --json "$out/ctrl.json" \
    --write "$out/ctrl-routed.json" \
    --device "$gowin_device" \
    --freq 50 \
    --seed "${TINYVCMI_PN_SEED:-1}" \
    --vopt "cst=$src/top.cst" \
    --sdc "$src/open.sdc" \
    >"$out/nextpnr.log" 2>&1 || {
        tail -40 "$out/nextpnr.log" >&2
        exit 1
    }
if grep -q "matched no objects" "$out/nextpnr.log"; then
    grep "matched no objects" "$out/nextpnr.log" >&2
    echo "a clock constraint in open.sdc matched no net; timing would be unconstrained" >&2
    exit 1
fi
if grep -qE "Cell .* not found" "$out/nextpnr.log"; then
    grep -E "Cell .* not found" "$out/nextpnr.log" >&2
    echo "a constraint in top.cst names a cell the netlist does not have (TOOL-032)" >&2
    exit 1
fi
if grep -q "feeds a DQS FCLK but is carried on" "$out/nextpnr.log"; then
    grep "feeds a DQS FCLK" "$out/nextpnr.log" >&2
    echo "the router split an FCLK net across HCLK lanes" >&2
    exit 1
fi
grep -E "Max frequency for clock" "$out/nextpnr.log" | tail -3

echo "[5/6] Apicula packing with the declared DDR3 context"
rm -f "$out/ctrl.fs" "$out/ctrl.bin"
"$oss_suite/py3bin/python3" -m apycula.gowin_pack \
    -d "$gowin_family" \
    --ddr3-context "$manifest" \
    -o "$out/ctrl.fs" \
    "$out/ctrl-routed.json" \
    >"$out/pack.log" 2>&1 || {
        tail -40 "$out/pack.log" >&2
        exit 1
    }

echo "[6/6] image against the vendor build, lanes exact; vendor timing"
[[ -f "$vendor/impl/pnr/probe.fs" ]] || {
    echo "missing $vendor/impl/pnr/probe.fs; run tools/ddr3_write.py --vendor --ctrl first" >&2
    exit 2
}
for f in top.v top.cst ctrl_glue.v dfi_phy.v ddr3_derot.v ddr3_bist.v ddr3_ctl.v; do
    cmp -s "$src/$f" "$vendor/$f" || {
        echo "the vendor build's $f is not the source's; rebuild it with tools/ddr3_write.py --vendor --ctrl" >&2
        exit 1
    }
done
for f in wr_core.v rd_align.v rd_check.v; do
    cmp -s "$wsrc/$f" "$vendor/$f" || {
        echo "the vendor build's $f is not the source's; rebuild it with tools/ddr3_write.py --vendor --ctrl" >&2
        exit 1
    }
done
control=1
python3 - "$vendor/impl/pnr/probe_tr_content.html" <<'PY' || control=0
import html, re, sys
text = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", open(sys.argv[1]).read())))
fmax = text[text.find("Max Frequency Summary"):text.find("Total Negative Slack Summary")]
tns = text[text.find("Total Negative Slack Summary"):text.find("Timing Details")]
rows = re.findall(r"(\S+) (Setup|Hold) (-?\d+\.\d+) (\d+)", tns)
print("vendor " + fmax.strip())
bad = [r for r in rows if float(r[2]) != 0.0]
if not rows or bad:
    print("warning: the vendor build misses timing, so it is a fuse reference only "
          "and no control is written: " + "; ".join(" ".join(r) for r in bad), file=sys.stderr)
    sys.exit(1)
PY
(cd "$root/tools" && python3 ddr3_image_check.py "$out/ctrl.fs" \
    --vendor "$vendor/impl/pnr/probe.fs" --exact-lanes)

"$oss_suite/py3bin/python3" "$root/tools/fs2bin.py" "$out/ctrl.fs" "$out/ctrl.bin"
rm -f "$out/../vendor_control.bin"
if [[ $control == 1 ]]; then
    install -m 0644 "$vendor/impl/pnr/probe.bin" "$out/../vendor_control.bin"
    sha256sum "$out/ctrl.fs" "$out/ctrl.bin" "$out/../vendor_control.bin"
    echo "Controller images written: $out/ctrl.bin (open flow), $out/../vendor_control.bin (vendor)"
else
    sha256sum "$out/ctrl.fs" "$out/ctrl.bin"
    echo "Controller image written: $out/ctrl.bin (open flow); no vendor control"
fi
echo "Hardware was not accessed."
