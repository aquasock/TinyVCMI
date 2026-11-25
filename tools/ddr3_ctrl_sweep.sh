#!/usr/bin/env bash
# Synthesise the DDR3 controller image and place and route it at several
# seeds with every path timed, reporting each seed's clocks and critical path
# and keeping each routed design's endpoint dump for tools/ddr3_sta.py.
#
#   ddr3_ctrl_sweep.sh OUT_DIR SEED...
#
# Synthesis is tools/build_ddr3_ctrl.sh's step 3 with the LUT mapping made
# delay-driven: abc9 -W $ABCW -D $ABCD (defaults 3000 ps per wire and a 9000
# ps target) instead of synth_gowin's abc9 -W 500, which mapped compares and
# selects as long LUT chains.  Placement uses --placer-heap-beta 0.7, without
# which the heap placer's legaliser gave up on up to five seeds of seven
# around the dense 256-bit paths at the DDR3 I/O.  nextpnr is
# $NEXTPNR_HIMBAECHEL, which must carry the chipdb of tools/nextpnr_arcs.sh
# for its timing to cover LUT1 to LUT3 and the LUT RAM's data inputs; the
# netlist then needs no tools/lut4ify.py.  Images are written whether or not
# they meet timing (--timing-allow-fail), and each seed's line says which.
# Nothing here touches the board.  Run the simulation gates first.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"
out=$(mkdir -p "$1" && cd "$1" && pwd); shift
src="$root/fpga/ddr3_ctrl"; wsrc="$root/fpga/ddr3_write"
cells="$oss_suite/share/yosys/gowin/cells_xtra_gw5a.v"
case "$nextpnr_himbaechel" in
    */nextpnr-tinyvcmi-arcs/*) ;;
    *) echo "warning: $nextpnr_himbaechel may lack the arcs of tools/nextpnr_arcs.sh" >&2 ;;
esac
(cd "$root/tools" && python3 ddr3_write.py --check) || exit 1
yosys -Q -T -q -l "$out/synth.log" -p "
    read_verilog -lib $cells
    read_verilog $src/top.v $wsrc/wr_core.v $wsrc/rd_align.v $wsrc/rd_check.v
    read_verilog $src/ctrl_glue.v $src/dfi_phy.v $src/ddr3_derot.v $src/ddr3_bist.v
    read_verilog $src/ddr3_ctl.v
    synth_gowin -family gw5a -top top -run :map_luts
    sort
    read_verilog -icells -lib -specify +/abc9_model.v
    abc9 -maxlut 8 -W ${ABCW:-3000} -D ${ABCD:-9000}
    clean
    synth_gowin -family gw5a -top top -run map_cells:
    write_json $out/ctrl.json
" || exit 1
for s in "$@"; do
    (TINYVCMI_STA_DUMP=$out/s$s/sta.json TINYVCMI_CTRL_JSON=$out/ctrl.json \
     TINYVCMI_PNR_EXTRA="--timing-allow-fail --placer-heap-beta 0.7 --post-route $root/tools/ddr3_sta.py" \
     "$root/tools/ddr3_pin_seed.sh" "$s" "$out/s$s" >"$out/s$s.out" 2>&1) &
done
wait
for s in "$@"; do
    log=$out/s$s/nextpnr.log
    if grep -q "Program finished normally" "$log" 2>/dev/null && [[ -f $out/s$s/ctrl.fs ]]; then
        echo "seed $s: $(grep -hE "Max frequency for clock" "$log" | tail -3 | sed 's/.*clock *//' | tr -s ' ' | tr '\n' ' ')"
        echo "  critical: $(awk "/Critical path report for clock 'pclk'/,/ns logic/" "$log" | grep Source | sed -n '1p;$p' | sed 's/.*Source //' | tr '\n' ' ')"
    else
        echo "seed $s: refused ($(grep -h ERROR "$log" 2>/dev/null | head -1))"
    fi
done
