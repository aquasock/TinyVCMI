#!/usr/bin/env bash
# Unit simulation of the DFI adapter, fpga/ddr3_ctrl/dfi_adapter.v, against a
# behavioural PHY.  Offline only: no Gowin libraries, no device model.
#
# Checks that a command on any DFI phase becomes exactly one PHY command with
# its bank and address intact, that two phases commanding in one PCLK is
# flagged, that a burst is sliced two beats per phase and presented RD_LATENCY
# after rddata_en, that write data reaches the PHY unchanged, and that a burst
# the PHY never delivers sets rd_underflow rather than returning stale data.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
src="$root/fpga/ddr3_ctrl"
out=${TINYVCMI_DFI_SIM_DIR:-$root/build/dfi_adapter}
mkdir -p "$out"

iverilog -g2012 -s tb_dfi_adapter -o "$out/tb.vvp" \
    "$src/tb_dfi_adapter.v" "$src/dfi_adapter.v" >"$out/iverilog.log" 2>&1 || {
        tail -30 "$out/iverilog.log" >&2
        exit 1
    }
vvp -n "$out/tb.vvp" | tee "$out/sim.log"
grep -q "^PASS" "$out/sim.log"
