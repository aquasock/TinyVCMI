#!/usr/bin/env bash
# Simulation of the controller's fabric, fpga/ddr3_ctrl/ctrl_glue.v --
# ddr3_ctl, dfi_phy and the memory test -- against fpga/ddr3_ctrl/tb_ctrl.v's
# model of the trained PHY and the array and its DDR3 timing checks, then the
# same with the model's read offset one PCLK later and its write alignment
# one PCLK later, each of which must fail.  Offline only.  It runs on
# Verilator from tools/openflow_env.sh, which LiteDRAM's generated core once
# needed (Icarus 14 looped on Migen's combinational blocks) and which runs
# this bench in a fraction of a second.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
src="$root/fpga/ddr3_ctrl"
out=${TINYVCMI_CTRL_SIM_DIR:-$root/build/ddr3_ctrl/sim}
mkdir -p "$out"

# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"

run() {     # name, defines...
    local name=$1
    shift
    rm -rf "$out/$name"
    verilator --binary --timing -Wno-fatal -Wno-UNOPTFLAT -Wno-WIDTH -Wno-TIMESCALEMOD \
        --top-module tb_ctrl -Mdir "$out/$name" -j 8 "$@" \
        "$src/tb_ctrl.v" "$src/ctrl_glue.v" "$src/dfi_phy.v" "$src/ddr3_derot.v" \
        "$src/ddr3_bist.v" "$src/ddr3_ctl.v" >"$out/$name.build.log" 2>&1 || {
            grep -m 20 '%Error' "$out/$name.build.log" >&2
            return 1
        }
    "$out/$name/Vtb_ctrl" >"$out/$name.log" 2>&1
}

run trained
grep -v '^      t=' "$out/trained.log" | grep -v '^- '
grep -q "^PASS" "$out/trained.log"

# the test's diagnostics against a word written wrong and a word read wrong
run faults +define+MODEL_FAULTS
grep -E '^PASS|^FAIL' "$out/faults.log"
grep -q "^PASS" "$out/faults.log"

# The controller with tRAS short must fail too.  The other shortenings are not
# among these, because nothing here can show them.  ddr3_ctl decides a command
# a PCLK before it goes out and decides nothing while one is pending, so any
# two commands are at least two PCLK (8 memory clocks) apart: more than tRCD
# and tRP (6), whatever T_RCD and T_RP say.  tRC is exceeded by tRAS and tRP.
# READ to WRITE and WRITE to READ: the test turns between them only between
# passes, its last command long out, even with T_WTR = 1.
for m in "late_read +define+MODEL_RDO=8" "late_write +define+MODEL_D=2" \
         "short_ras +define+CTL_T_RAS=2"; do
    set -- $m
    run "$1" "$2"
    if grep -q "^PASS" "$out/$1.log"; then
        echo "FAIL  the $1 mutant passed: the test cannot see it"
        exit 1
    fi
    echo "PASS  the $1 mutant fails: $(grep -m1 '^FAIL' "$out/$1.log")"
done
