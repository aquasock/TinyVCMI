#!/usr/bin/env bash
# Write the open-flow image of the whole DDR3 pad set and check it against the
# vendor's build of the same source.
#
# The source is the design tools/ddr3_pad_set_probe.py generates and builds
# with Gowin EDA in build/ddr3_pads/full_sstl: every pad of the proven DDR3
# controller, exactly the balls of fpga/ddr3/ddr3_balls.json.  This script
# synthesizes, places and routes it in the open flow, packs it with
# `gowin_pack --ddr3-context fpga/ddr3/ddr3_balls.json`, and compares the
# written image with the vendor's by tools/ddr3_image_check.py.
#
# The image is a measurement artifact.  Its serializers run from the board
# clock with no memory PLL and no controller, so it must not be loaded onto
# the board; only a .fs is written, never the raw .bin TinyTang loads.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"

src=${DDR3_PAD_SOURCE:-$root/build/ddr3_pads/full_sstl}
out=${TINYVCMI_BUILD_DIR:-$root/build/ddr3_image}
manifest="$root/fpga/ddr3/ddr3_balls.json"
cells="$oss_suite/share/yosys/gowin/cells_xtra_gw5a.v"

for f in top.v top.cst top.sdc impl/pnr/probe.fs; do
    [[ -f "$src/$f" ]] || {
        echo "missing $src/$f; run tools/ddr3_pad_set_probe.py first" >&2
        exit 2
    }
done
mkdir -p "$out"

echo "[1/5] DDR3 ball manifest"
(cd "$root/tools" && python3 ddr3_ball_manifest.py --check)

echo "[2/5] Yosys synthesis"
yosys -Q -T -q -l "$out/synth.log" -p "
    read_verilog -lib $cells
    read_verilog $src/top.v
    synth_gowin -family gw5a -top top
    write_json $out/full_sstl.json
"

echo "[3/5] nextpnr placement and routing"
"$nextpnr_himbaechel" \
    --json "$out/full_sstl.json" \
    --write "$out/full_sstl-routed.json" \
    --device "$gowin_device" \
    --freq 50 \
    --vopt "cst=$src/top.cst" \
    --sdc "$src/top.sdc" \
    >"$out/nextpnr.log" 2>&1 || {
        tail -40 "$out/nextpnr.log" >&2
        exit 1
    }

echo "[4/5] Apicula packing with the declared DDR3 context"
rm -f "$out/full_sstl.fs"
"$oss_suite/py3bin/python3" -m apycula.gowin_pack \
    -d "$gowin_family" \
    --ddr3-context "$manifest" \
    -o "$out/full_sstl.fs" \
    "$out/full_sstl-routed.json" \
    >"$out/pack.log" 2>&1 || {
        tail -40 "$out/pack.log" >&2
        exit 1
    }
sha256sum "$out/full_sstl.fs"

echo "[5/5] image against the vendor build"
(cd "$root/tools" && python3 ddr3_image_check.py "$out/full_sstl.fs" \
    --vendor "$src/impl/pnr/probe.fs")

echo "DDR3 pad-set image written and checked: $out/full_sstl.fs"
echo "Not for the board: no memory clock, no controller. Hardware was not accessed."
