#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="$root/tools/ddrdll_oracle"
out=${TINYVCMI_DDRDLL_ORACLE_DIR:-$root/build/ddrdll_oracle}
gowin=${GOWINHOME:-/home/vash/tools/gowin-1.9.11.03}

[[ -x "$gowin/IDE/bin/gw_sh" ]] || {
    echo "missing Gowin EDA oracle: $gowin/IDE/bin/gw_sh" >&2
    exit 2
}

mkdir -p "$out"
cp "$source_dir/top.v" "$source_dir/top.cst" "$source_dir/top.sdc" \
    "$source_dir/run.tcl" "$out/"

cd "$out"
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libfreetype.so.6 \
QT_QPA_PLATFORM=offscreen \
    "$gowin/IDE/bin/gw_sh" run.tcl >gw_sh.log 2>&1 || {
        tail -80 gw_sh.log >&2
        exit 1
    }

if rg -q 'Error|unknown option:|License verification failed' gw_sh.log; then
    rg 'Error|unknown option:|License verification failed' gw_sh.log >&2
    exit 1
fi

for artifact in \
    impl/pnr/ddrdll_oracle.fs \
    impl/pnr/ddrdll_oracle.vo \
    impl/pnr/ddrdll_oracle.sdf \
    impl/pnr/ddrdll_oracle.tr; do
    [[ -s "$artifact" ]] || {
        echo "missing oracle artifact: $out/$artifact" >&2
        exit 1
    }
done

sha256sum impl/pnr/ddrdll_oracle.fs
echo "Vendor oracle PASS: $out/impl/pnr"
echo "Measurement only; this is not an open-flow deliverable."
