#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build the AE350 image, fpga/ae350_ddr3: the DDR3 controller image of
# tools/ddr3_ctrl_sweep.sh with the AE350 system as the controller's second
# client.  Builds the boot ROM firmware, synthesises once, checks the DDR3
# I/O boundary, and places and routes each seed in parallel with every path
# timed, reporting each seed's four clocks.
#
#   ae350_ddr3_sweep.sh OUT_DIR SEED...
#
# Synthesis and placement are tools/ddr3_ctrl_sweep.sh's (delay-driven
# abc9, --placer-heap-beta 0.7, the patched chipdb of tools/nextpnr_arcs.sh
# as $NEXTPNR_HIMBAECHEL).  The A25's bus clock must reach the AE350 through
# global branch GB10, which nextpnr gives it when it routes bus_clk first
# (TinyNES DEV-016), so NPNR_GOWIN_CLK_FIRST is bus_clk and a seed whose log
# does not say so is failed.  tools/ae350_place.py keeps the AE350 system's
# fabric beside the AE350 macro.  Nothing here touches the board.  Run
# tools/sim_ae350_ddr3.sh and tools/sim_ddr3_ctrl.sh first.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"
out=$(mkdir -p "$1" && cd "$1" && pwd); shift
src="$root/fpga/ddr3_ctrl"; wsrc="$root/fpga/ddr3_write"; ssrc="$root/fpga/ae350_ddr3"
cells="$oss_suite/share/yosys/gowin/cells_xtra_gw5a.v"
[[ -f $(dirname "$nextpnr_himbaechel")/share/himbaechel/gowin/chipdb-GW5AST-138C.bin &&
   -f $(dirname "$nextpnr_himbaechel")/genfix/chipdb.bba ]] ||
    echo "warning: $nextpnr_himbaechel is not a tools/nextpnr_arcs.sh build; its timing may miss paths" >&2
(cd "$root/tools" && python3 ddr3_write.py --check) || exit 1
make -s -C "$root/firmware/boot" BUILD="$out/firmware" >"$out/firmware.log" 2>&1 ||
    { cat "$out/firmware.log"; exit 1; }
# the ROM's INIT_FILE is read at synthesis, relative to the directory yosys runs in
cd "$out" && mkdir -p build/firmware/boot && cp firmware/boot.hex build/firmware/boot/boot.hex
yosys -Q -T -q -l "$out/synth.log" -p "
    read_verilog -lib $cells
    read_verilog $ssrc/top.v $wsrc/wr_core.v $wsrc/rd_align.v $wsrc/rd_check.v
    read_verilog $src/ctrl_glue.v $src/dfi_phy.v $src/ddr3_derot.v $src/ddr3_bist.v
    read_verilog $src/ddr3_ctl.v $ssrc/ahb_ddr3.v
    read_verilog -sv $ssrc/ahb_boot_rom.sv $ssrc/ahb_ram.sv $ssrc/exts_uart.sv $ssrc/ae350_sys.sv
    synth_gowin -family gw5a -top top -run :map_luts
    sort
    read_verilog -icells -lib -specify +/abc9_model.v
    abc9 -maxlut 8 -W ${ABCW:-3000} -D ${ABCD:-9000}
    clean
    synth_gowin -family gw5a -top top -run map_cells:
    write_json $out/ctrl.json
" || exit 1
python3 "$root/tools/ddr3_boundary_check.py" "$out/ctrl.json" || exit 1
export NPNR_GOWIN_CLK_FIRST=bus_clk
for s in "$@"; do
    (TINYVCMI_CTRL_JSON=$out/ctrl.json TINYVCMI_CST=$ssrc/top.cst TINYVCMI_SDC=$ssrc/open.sdc \
     TINYVCMI_PNR_EXTRA="--timing-allow-fail --placer-heap-beta 0.7 --pre-place $root/tools/ae350_place.py" \
     "$root/tools/ddr3_pin_seed.sh" "$s" "$out/s$s" >"$out/s$s.out" 2>&1) &
done
wait
for s in "$@"; do
    log=$out/s$s/nextpnr.log
    if grep -q "Program finished normally" "$log" 2>/dev/null && [[ -f $out/s$s/ctrl.fs ]]; then
        grep -q "routing 'bus_clk' first" "$log" ||
            { echo "seed $s: FAIL nextpnr did not route bus_clk first"; continue; }
        echo "seed $s: $(grep -hE "Max frequency for clock" "$log" | tail -4 | sed 's/.*clock *//' | tr -s ' ' | tr '\n' ' ')"
    else
        echo "seed $s: refused ($(grep -h ERROR "$log" 2>/dev/null | head -1)$(cat "$out/s$s/FAILED" 2>/dev/null))"
    fi
done
