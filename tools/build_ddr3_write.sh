#!/usr/bin/env bash
# Build the DDR3 write image in the open flow, check it against the
# vendor's build of the same source, and only then write the raw images
# TinyTang loads.
#
# The source is fpga/ddr3_write (tools/ddr3_write.py generates top.v and its
# constraints; wr_core.v is written by hand).  The vendor reference is built
# first with `tools/ddr3_write.py --vendor`.  Steps:
#
#   1. the manifest and the generated sources are current;
#   2. the aligner's, the checker's and the training sequencer's unit
#      simulations pass, and the image's simulation
#      passes against Gowin's own primitive models;
#   3. Yosys, nextpnr, and `gowin_pack --ddr3-context`;
#   4. tools/ddr3_image_check.py --exact-lanes against the vendor build, and
#      the vendor build's own timing report clean: a control that misses
#      timing is no control;
#   5. both .bin files, the open-flow image and the vendor control.
#
# Nothing here touches the board.  Loading is a separate, approved step.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"

src="$root/fpga/ddr3_write"
out=${TINYVCMI_BUILD_DIR:-$root/build/ddr3_write/open}
vendor="$root/build/ddr3_write/vendor"
manifest="$root/fpga/ddr3/ddr3_balls.json"
cells="$oss_suite/share/yosys/gowin/cells_xtra_gw5a.v"

[[ -f "$vendor/impl/pnr/probe.fs" ]] || {
    echo "missing $vendor/impl/pnr/probe.fs; run tools/ddr3_write.py --vendor first" >&2
    exit 2
}
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
fi

echo "[3/6] Yosys synthesis"
yosys -Q -T -q -l "$out/synth.log" -p "
    read_verilog -lib $cells
    read_verilog $src/top.v $src/wr_core.v $src/rd_align.v $src/rd_check.v
    synth_gowin -family gw5a -top top
    write_json $out/wr.json
"

echo "[4/6] nextpnr placement and routing"
"$nextpnr_himbaechel" \
    --json "$out/wr.json" \
    --write "$out/wr-routed.json" \
    --device "$gowin_device" \
    --freq 50 \
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
if grep -q "feeds a DQS FCLK but is carried on" "$out/nextpnr.log"; then
    grep "feeds a DQS FCLK" "$out/nextpnr.log" >&2
    echo "the router split an FCLK net across HCLK lanes" >&2
    exit 1
fi

echo "[5/6] Apicula packing with the declared DDR3 context"
rm -f "$out/wr.fs" "$out/wr.bin"
"$oss_suite/py3bin/python3" -m apycula.gowin_pack \
    -d "$gowin_family" \
    --ddr3-context "$manifest" \
    -o "$out/wr.fs" \
    "$out/wr-routed.json" \
    >"$out/pack.log" 2>&1 || {
        tail -40 "$out/pack.log" >&2
        exit 1
    }

echo "[6/6] image against the vendor build, lanes exact; vendor timing"
python3 - "$vendor/impl/pnr/probe_tr_content.html" <<'PY'
import html, re, sys
text = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", open(sys.argv[1]).read())))
fmax = text[text.find("Max Frequency Summary"):text.find("Total Negative Slack Summary")]
tns = text[text.find("Total Negative Slack Summary"):text.find("Timing Details")]
rows = re.findall(r"(\S+) (Setup|Hold) (-?\d+\.\d+) (\d+)", tns)
print("vendor " + fmax.strip())
bad = [r for r in rows if float(r[2]) != 0.0]
if not rows or bad:
    print("the vendor control misses timing: " + "; ".join(" ".join(r) for r in bad), file=sys.stderr)
    sys.exit(1)
PY
(cd "$root/tools" && python3 ddr3_image_check.py "$out/wr.fs" \
    --vendor "$vendor/impl/pnr/probe.fs" --exact-lanes)

"$oss_suite/py3bin/python3" "$root/tools/fs2bin.py" "$out/wr.fs" "$out/wr.bin"
# Gowin writes the raw image itself (bit_compress 0); it is the .fs packed
# eight bits to a byte, so the vendor control needs no conversion
# (Gowin writes it read-only, so it is installed rather than copied)
install -m 0644 "$vendor/impl/pnr/probe.bin" "$out/../vendor_control.bin"
sha256sum "$out/wr.fs" "$out/wr.bin" "$out/../vendor_control.bin"
echo "Write images written: $out/wr.bin (open flow), $out/../vendor_control.bin (vendor)"
echo "Hardware was not accessed."
