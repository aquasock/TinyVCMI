#!/usr/bin/env bash
# Run eight deterministic nextpnr seeds for the DDR3 write/read diagnostic.
# This is offline only: it synthesizes once, routes seeds 1..8 in isolated
# directories, and reports each PCLK result.  It does not pack or touch the
# Tang.  The normal build remains the final simulation/vendor/table gate.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"

src="$root/fpga/ddr3_write"
out=${TINYVCMI_SEED_DIR:-$root/build/ddr3_write/seeds}
jobs=${TINYVCMI_SEED_JOBS:-4}
cells="$oss_suite/share/yosys/gowin/cells_xtra_gw5a.v"
mkdir -p "$out"

python3 "$root/tools/ddr3_write.py" --check
yosys -Q -T -q -l "$out/synth.log" -p "
    read_verilog -lib $cells
    read_verilog $src/top.v $src/wr_core.v $src/rd_align.v $src/rd_check.v
    synth_gowin -family gw5a -top top
    write_json $out/wr.json
"

run_seed() {
    local seed=$1 seed_out="$out/seed$1"
    mkdir -p "$seed_out"
    "$nextpnr_himbaechel" \
        --json "$out/wr.json" \
        --write "$seed_out/wr-routed.json" \
        --device "$gowin_device" \
        --freq 50 \
        --seed "$seed" \
        --vopt "cst=$src/top.cst" \
        --sdc "$src/open.sdc" \
        >"$seed_out/nextpnr.log" 2>&1
}

failed=0
for start in $(seq 1 "$jobs" 8); do
    pids=()
    seeds=()
    for seed in $(seq "$start" "$((start + jobs - 1))"); do
        ((seed <= 8)) || break
        run_seed "$seed" &
        pids+=("$!")
        seeds+=("$seed")
    done
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            echo "seed ${seeds[$i]}: FAIL" >&2
            tail -20 "$out/seed${seeds[$i]}/nextpnr.log" >&2
            failed=1
        fi
    done
done

for seed in $(seq 1 8); do
    line=$(grep "Max frequency for clock         'pclk'" "$out/seed$seed/nextpnr.log" | tail -1 || true)
    [[ -n "$line" ]] || line="no PCLK result"
    echo "seed $seed: $line"
done

((failed == 0))
