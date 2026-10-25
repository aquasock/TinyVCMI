#!/usr/bin/env bash
# Build the controller: generate LiteDRAM's core, synthesise, route across eight
# seeds in parallel, keep the best, then pack with the declared DDR3 context.
#
# Offline until the packing step, which writes a bitstream but never loads it.
# The seed spread is reported rather than hidden: this design carries a 400 MHz
# domain and a controller clock that has missed timing before.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"

out=${TINYVCMI_CTRL_DIR:-$root/build/ddr3_ctrl}
seeds=${TINYVCMI_CTRL_SEEDS:-8}
jobs=${TINYVCMI_CTRL_JOBS:-8}
manifest="$root/fpga/ddr3/ddr3_balls.json"
cst=${TINYVCMI_CTRL_CST:-$root/fpga/ddr3_write/top.cst}
sdc=${TINYVCMI_CTRL_SDC:-$root/fpga/ddr3_write/open.sdc}
cells="$oss_suite/share/yosys/gowin/cells_xtra_gw5a.v"
mkdir -p "$out"

echo "[1/4] generate LiteDRAM's core at board geometry"
python3 "$root/tools/litedram_ctrl_gen.py" --out "$out" | tail -3

echo "[2/4] Yosys synthesis"
yosys -Q -T -q -l "$out/top_synth.log" -p "
    read_verilog -lib $cells
    read_verilog -sv $root/fpga/ddr3_ctrl/ddr3_wdata.v $root/fpga/ddr3_ctrl/ddr3_phy.v \
        $root/fpga/ddr3_ctrl/ddr3_sync.v $root/fpga/ddr3_ctrl/ddr3_init.v \
        $root/fpga/ddr3_ctrl/ddr3_derot.v $root/fpga/ddr3_ctrl/dfi_adapter.v \
        $root/fpga/ddr3_ctrl/ddr3_cmdmux.v $root/fpga/ddr3_ctrl/ddr3_rotlatch.v \
        $root/fpga/ddr3_ctrl/ddr3_train.v $root/fpga/ddr3_write/rd_align.v \
        $out/litedram_core.v $root/fpga/ddr3_ctrl/top.v
    synth_gowin -family gw5a -top top
    write_json $out/top.json
" || { tail -20 "$out/top_synth.log" >&2; exit 1; }
[[ -s "$out/top.json" ]] || { echo "synthesis produced no netlist" >&2; exit 1; }

echo "[3/4] nextpnr across $seeds seeds, $jobs at a time"
run_seed() {
    local seed=$1 dir="$out/seed$1"
    mkdir -p "$dir"
    "$nextpnr_himbaechel" --json "$out/top.json" \
        --write "$dir/top-routed.json" --device "$gowin_device" \
        --freq 50 --seed "$seed" \
        --vopt "cst=$cst" --sdc "$sdc" >"$dir/nextpnr.log" 2>&1
}
failed=0
for start in $(seq 1 "$jobs" "$seeds"); do
    pids=(); nums=()
    for seed in $(seq "$start" "$((start + jobs - 1))"); do
        ((seed <= seeds)) || break
        run_seed "$seed" & pids+=("$!"); nums+=("$seed")
    done
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            echo "seed ${nums[$i]}: FAIL" >&2
            tail -12 "$out/seed${nums[$i]}/nextpnr.log" >&2
            failed=$((failed + 1))
        fi
    done
done

best=""; best_f=0
for seed in $(seq 1 "$seeds"); do
    log="$out/seed$seed/nextpnr.log"
    [[ -f "$log" ]] || continue
    f=$(grep -oE "clock +'pclk': [0-9.]+ MHz" "$log" | tail -1 | grep -oE "[0-9.]+" || true)
    [[ -n "$f" ]] || continue
    printf "seed %d: pclk %s MHz\n" "$seed" "$f"
    awk -v a="$f" -v b="$best_f" 'BEGIN{exit !(a+0 > b+0)}' && { best=$seed; best_f=$f; }
done
[[ -n "$best" ]] || { echo "no seed produced a pclk result" >&2; exit 1; }
# a clock constraint that matched nothing leaves that clock unconstrained, and
# every timing number from the build would be meaningless
if grep -q "matched no objects" "$out/seed$best/nextpnr.log"; then
    grep "matched no objects" "$out/seed$best/nextpnr.log" >&2
    echo "a clock constraint matched no net; timing would be unconstrained" >&2
    exit 1
fi
echo "best: seed $best at $best_f MHz"

echo "[4/4] pack the best seed with the declared DDR3 context"
"$oss_suite/py3bin/python3" -m apycula.gowin_pack \
    -d "$gowin_family" --ddr3-context "$manifest" \
    -o "$out/ctrl.fs" "$out/seed$best/top-routed.json" \
    >"$out/pack.log" 2>&1 || { tail -20 "$out/pack.log" >&2; exit 1; }
ls -l "$out/ctrl.fs" | awk '{print "wrote", $9, $5, "bytes"}'
sha256sum "$out/ctrl.fs"
echo "hardware was not accessed"
