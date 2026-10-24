#!/usr/bin/env bash
# Build the DDR3 PHY bring-up image in the open flow, check it against the
# vendor's build of the same source, and only then write the raw images
# TinyTang loads.
#
# The source is fpga/ddr3_phy_bringup (tools/ddr3_phy_bringup.py generates
# top.v and its constraints; bringup_core.v is written by hand).  The vendor
# reference is built first with `tools/ddr3_phy_bringup.py --vendor`.  Steps:
#
#   1. the manifest and the generated sources are current;
#   2. the reset-hold simulation passes against Gowin's own primitive models;
#   3. Yosys, nextpnr, and `gowin_pack --ddr3-context`;
#   4. tools/ddr3_image_check.py --exact-lanes against the vendor build;
#   5. both .bin files, the open-flow image and the vendor control.
#
# Nothing here touches the board.  Loading is a separate, approved step.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"

src="$root/fpga/ddr3_phy_bringup"
out=${TINYVCMI_BUILD_DIR:-$root/build/ddr3_phy_bringup/open}
vendor="$root/build/ddr3_phy_bringup/vendor"
manifest="$root/fpga/ddr3/ddr3_balls.json"
cells="$oss_suite/share/yosys/gowin/cells_xtra_gw5a.v"

[[ -f "$vendor/impl/pnr/probe.fs" ]] || {
    echo "missing $vendor/impl/pnr/probe.fs; run tools/ddr3_phy_bringup.py --vendor first" >&2
    exit 2
}
mkdir -p "$out"

echo "[1/6] manifest and generated sources"
(cd "$root/tools" && python3 ddr3_ball_manifest.py --check && python3 ddr3_phy_bringup.py --check)

echo "[2/6] reset-hold simulation"
"$root/tools/sim_ddr3_phy_bringup.sh"

echo "[3/6] Yosys synthesis"
yosys -Q -T -q -l "$out/synth.log" -p "
    read_verilog -lib $cells
    read_verilog $src/top.v $src/bringup_core.v
    synth_gowin -family gw5a -top top
    write_json $out/bringup.json
"

echo "[4/6] nextpnr placement and routing"
"$nextpnr_himbaechel" \
    --json "$out/bringup.json" \
    --write "$out/bringup-routed.json" \
    --device "$gowin_device" \
    --freq 50 \
    --vopt "cst=$src/top.cst" \
    --sdc "$src/open.sdc" \
    >"$out/nextpnr.log" 2>&1 || {
        tail -40 "$out/nextpnr.log" >&2
        exit 1
    }
if grep -q "feeds a DQS FCLK but is carried on" "$out/nextpnr.log"; then
    grep "feeds a DQS FCLK" "$out/nextpnr.log" >&2
    echo "the router split an FCLK net across HCLK lanes" >&2
    exit 1
fi

echo "[5/6] Apicula packing with the declared DDR3 context"
rm -f "$out/bringup.fs" "$out/bringup.bin"
"$oss_suite/py3bin/python3" -m apycula.gowin_pack \
    -d "$gowin_family" \
    --ddr3-context "$manifest" \
    -o "$out/bringup.fs" \
    "$out/bringup-routed.json" \
    >"$out/pack.log" 2>&1 || {
        tail -40 "$out/pack.log" >&2
        exit 1
    }

echo "[6/6] image against the vendor build, lanes exact"
(cd "$root/tools" && python3 ddr3_image_check.py "$out/bringup.fs" \
    --vendor "$vendor/impl/pnr/probe.fs" --exact-lanes)

"$oss_suite/py3bin/python3" "$root/tools/fs2bin.py" "$out/bringup.fs" "$out/bringup.bin"
# Gowin writes the raw image itself (bit_compress 0); it is the .fs packed
# eight bits to a byte, so the vendor control needs no conversion
cp "$vendor/impl/pnr/probe.bin" "$out/../vendor_control.bin"
sha256sum "$out/bringup.fs" "$out/bringup.bin" "$out/../vendor_control.bin"
echo "Bring-up images written: $out/bringup.bin (open flow), $out/../vendor_control.bin (vendor)"
echo "Hardware was not accessed."
