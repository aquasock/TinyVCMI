#!/usr/bin/env bash
# Unit simulation of the hardware read and write training, ddr3_seq in
# fpga/ddr3_write/wr_core.v, against fpga/ddr3_write/tb_seq.v's model of the
# core and its hidden per-lane answers.  Offline only.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
src="$root/fpga/ddr3_write"
out=${TINYVCMI_SEQ_SIM_DIR:-$root/build/ddr3_seq/sim}
mkdir -p "$out"

iverilog -g2012 -s tb_seq -o "$out/tb_seq.vvp" \
    "$src/tb_seq.v" "$src/wr_core.v" >"$out/iverilog.log" 2>&1 || {
        tail -30 "$out/iverilog.log" >&2
        exit 1
    }
vvp -n "$out/tb_seq.vvp" | tee "$out/sim.log"
grep -q "^PASS" "$out/sim.log"
