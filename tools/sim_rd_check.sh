#!/usr/bin/env bash
# Unit simulation of the single-burst read checker, fpga/ddr3_write/rd_check.v,
# and of its single-READ burst-position classifier.  Offline only: no Gowin
# libraries, no PHY, no device model beyond the testbenches' own.
#
# The testbench answers each READ a fixed delay later with that location's
# pattern and checks the latency histogram, the lock, a frame jump, a
# predicted move per READ and a mis-framed pin.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
src="$root/fpga/ddr3_write"
out=${TINYVCMI_CHECK_SIM_DIR:-$root/build/rd_check/sim}
mkdir -p "$out"

iverilog -g2012 -s tb_check -o "$out/tb_check.vvp" \
    "$src/tb_check.v" "$src/rd_check.v" >"$out/iverilog.log" 2>&1 || {
        tail -30 "$out/iverilog.log" >&2
        exit 1
    }
vvp -n "$out/tb_check.vvp" | tee "$out/sim.log"
grep -q "^PASS" "$out/sim.log"

# the single-READ burst-position classifier, same module under test
iverilog -g2012 -s tb_pos -o "$out/tb_pos.vvp" \
    "$src/tb_pos.v" "$src/rd_check.v" >"$out/iverilog_pos.log" 2>&1 || {
        tail -30 "$out/iverilog_pos.log" >&2
        exit 1
    }
vvp -n "$out/tb_pos.vvp" | tee "$out/sim_pos.log"
grep -q "^PASS" "$out/sim_pos.log"
