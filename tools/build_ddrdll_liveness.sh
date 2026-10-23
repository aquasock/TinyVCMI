#!/usr/bin/env bash
set -euo pipefail

# Build the DDRDLL liveness probe through the strict open flow and convert it
# to the raw image TinyTang loads.  Offline only: nothing here programs
# hardware, and no DDR3 package pin is exposed or driven.
#
# Load with TinyTang's own commands, from its USB console:
#   tangput <size> /root/cores/console138k/ddrdll_liveness.bin
#   tangload /root/cores/console138k/ddrdll_liveness.bin
# tools/tang_console.py drives both.

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"

src="$root/fpga/ddrdll_liveness"
out=${TINYVCMI_LIVENESS_DIR:-$root/build/ddrdll_liveness}
cells="$oss_suite/share/yosys/gowin/cells_xtra_gw5a.v"
mkdir -p "$out"

echo "[1/4] synthesis"
yosys -Q -T -q -l "$out/synth.log" -p "
    read_verilog -lib $cells
    read_verilog -sv $src/ddrdll_liveness.sv
    synth_gowin -family gw5a -top top
    write_json $out/ddrdll_liveness.json
"
grep -q '"type": *"DDRDLL"' "$out/ddrdll_liveness.json" || {
    echo "synthesis dropped the DDRDLL cell" >&2
    exit 1
}

echo "[2/4] placement and routing"
"$nextpnr_himbaechel" \
    --json "$out/ddrdll_liveness.json" \
    --write "$out/ddrdll_liveness-routed.json" \
    --device "$gowin_device" \
    --freq 50 \
    --vopt "cst=$src/ddrdll_liveness.cst" \
    --sdc "$src/ddrdll_liveness.sdc" \
    >"$out/nextpnr.log" 2>&1 || {
        tail -40 "$out/nextpnr.log" >&2
        exit 1
    }
grep -q 'NEXTPNR_BEL": *"X1Y108/DDRDLL_BL' "$out/ddrdll_liveness-routed.json" || {
    echo "DDRDLL did not land on the measured site" >&2
    exit 1
}

echo "[3/4] packing"
"$oss_suite/py3bin/python3" -m apycula.gowin_pack \
    -d "$gowin_family" \
    -o "$out/ddrdll_liveness.fs" \
    "$out/ddrdll_liveness-routed.json" \
    >"$out/pack.log" 2>&1 || {
        tail -40 "$out/pack.log" >&2
        exit 1
    }

echo "[4/4] raw image"
"$oss_suite/py3bin/python3" "$root/tools/fs2bin.py" \
    "$out/ddrdll_liveness.fs" "$out/ddrdll_liveness.bin"

sha256sum "$out/ddrdll_liveness.fs" "$out/ddrdll_liveness.bin"
echo "Liveness image built: $out/ddrdll_liveness.bin"
echo "Hardware was not accessed."
