#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"

src="$root/fpga/openflow_smoke"
out=${TINYVCMI_BUILD_DIR:-$root/build/openflow_smoke}
mkdir -p "$out"

echo "[1/4] RTL simulation"
iverilog -g2012 -s openflow_smoke_tb \
    -o "$out/openflow_smoke_tb" \
    "$src/openflow_smoke.sv" "$root/tests/openflow_smoke_tb.sv"
vvp "$out/openflow_smoke_tb"

echo "[2/4] Yosys synthesis"
yosys -Q -T -q -l "$out/synth.log" -p "
    read_verilog -sv $src/openflow_smoke.sv
    synth_gowin -family gw5a -top openflow_smoke
    write_json $out/openflow_smoke.json
"

echo "[3/4] nextpnr placement and routing"
"$nextpnr_himbaechel" \
    --json "$out/openflow_smoke.json" \
    --write "$out/openflow_smoke-routed.json" \
    --device "$gowin_device" \
    --freq 50 \
    --vopt "cst=$src/openflow_smoke.cst" \
    --sdc "$src/openflow_smoke.sdc" \
    --report "$out/timing.json" \
    >"$out/nextpnr.log" 2>&1 || {
        tail -80 "$out/nextpnr.log" >&2
        exit 1
    }

echo "[4/4] Apicula packing"
"$oss_suite/py3bin/python3" -m apycula.gowin_pack \
    -d "$gowin_family" \
    -o "$out/openflow_smoke.fs" \
    "$out/openflow_smoke-routed.json" \
    >"$out/pack.log" 2>&1 || {
        tail -80 "$out/pack.log" >&2
        exit 1
    }

sha256sum "$out/openflow_smoke.fs"
echo "Offline smoke build PASS: $out/openflow_smoke.fs"
echo "Hardware was not accessed."
