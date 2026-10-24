#!/usr/bin/env bash
# Simulate the DDR3 PHY bring-up image against Gowin EDA's primitive models
# and fail unless fpga/ddr3_phy_bringup/tb_bringup.v passes.  Offline only.
#
# Gowin's DQS model is an empty stub, so a copy of the library is compiled
# with it removed and fpga/ddr3_phy_bringup/tb_dqs_standin.v in its place;
# every other primitive is Gowin's own model.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
gowin=${GOWINHOME:-/home/vash/tools/gowin-1.9.11.03}
src="$root/fpga/ddr3_phy_bringup"
out=${TINYVCMI_SIM_DIR:-$root/build/ddr3_phy_bringup/sim}
mkdir -p "$out"

lib="$out/prim_sim_no_dqs.v"
awk '/^module DQS\(/ { skip = 1 } !skip { print } skip && /^endmodule/ { skip = 0 }' \
    "$gowin/IDE/simlib/gw5a/prim_sim.v" >"$lib"
[[ $(grep -c '^module DQS(' "$lib") == 0 ]] || { echo "DQS stub not removed" >&2; exit 1; }

iverilog -g2012 -s tb -o "$out/tb.vvp" \
    "$src/tb_bringup.v" "$src/tb_dqs_standin.v" "$src/top.v" "$src/bringup_core.v" \
    "$lib" >"$out/iverilog.log" 2>&1 || {
        tail -30 "$out/iverilog.log" >&2
        exit 1
    }
vvp -n "$out/tb.vvp" | tee "$out/sim.log"
grep -q "^PASS" "$out/sim.log"
