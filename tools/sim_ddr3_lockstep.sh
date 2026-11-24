#!/usr/bin/env bash
# Lockstep simulation of ddr3_ctl and ddr3_bist against a reference version of
# each, by default commit 0d3bce3's, whose controller ran clean on every
# placement on the board (core-log entry 9).  Each bench drives both versions
# with the same random stimulus for millions of PCLK and fails on the first
# output that differs, so a restructuring for timing (TOOL-065) can be shown to
# leave behaviour untouched cycle for cycle.  Offline only, on Verilator from
# tools/openflow_env.sh.
#
#   sim_ddr3_lockstep.sh [REF_COMMIT]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ref=${1:-0d3bce3}
src="$root/fpga/ddr3_ctrl"
out=${TINYVCMI_LOCK_SIM_DIR:-$root/build/ddr3_ctrl/lockstep}
mkdir -p "$out"
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"
git -C "$root" show "$ref:fpga/ddr3_ctrl/ddr3_ctl.v" | sed 's/^module ddr3_ctl /module ddr3_ctl_ref /' >"$out/ctl_ref.v"
git -C "$root" show "$ref:fpga/ddr3_ctrl/ddr3_bist.v" | sed 's/^module ddr3_bist /module ddr3_bist_ref /' >"$out/bist_ref.v"
run() {     # top, files...
    local top=$1
    shift
    rm -rf "$out/$top"
    verilator --binary --timing -Wno-fatal -Wno-UNOPTFLAT -Wno-WIDTH -Wno-TIMESCALEMOD \
        --top-module "$top" -Mdir "$out/$top" -j 8 "$@" >"$out/$top.build.log" 2>&1 || {
            grep -m 20 '%Error' "$out/$top.build.log" >&2
            return 1
        }
    "$out/$top/V$top" >"$out/$top.log" 2>&1 || true
    grep -E '^(PASS|FAIL|MISMATCH)|Fatal' "$out/$top.log" | head -5
    grep -q '^PASS' "$out/$top.log"
}
echo "reference: $ref"
run tb_lock_ctl "$src/tb_lock_ctl.v" "$out/ctl_ref.v" "$src/ddr3_ctl.v"
run tb_lock_bist "$src/tb_lock_bist.v" "$out/bist_ref.v" "$src/ddr3_bist.v"
