#!/usr/bin/env bash
# Unit simulation of the read-data aligner, fpga/ddr3_write/rd_align.v.
# Offline only: no Gowin libraries, no PHY, no device model.
#
# The testbench drives each lane's pins at a chosen whole-word rotation and
# checks the lock, the derotated burst, drift and err reporting, an
# unidentifiable pattern, and a mis-framed pin.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
src="$root/fpga/ddr3_write"
out=${TINYVCMI_ALIGN_SIM_DIR:-$root/build/rd_align/sim}
mkdir -p "$out"

iverilog -g2012 -s tb_align -o "$out/tb_align.vvp" \
    "$src/tb_align.v" "$src/rd_align.v" >"$out/iverilog.log" 2>&1 || {
        tail -30 "$out/iverilog.log" >&2
        exit 1
    }
vvp -n "$out/tb_align.vvp" | tee "$out/sim.log"
grep -q "^PASS" "$out/sim.log"
