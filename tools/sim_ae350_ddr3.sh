#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# The AE350 system's DDR3 bridge: fpga/ae350_ddr3/tb_ahb_ddr3.v drives
# ahb_ram and ahb_ddr3 with a pipelined AHB master against a behavioural
# ddr3_ctl request port, the bus clock and PCLK at incommensurate periods,
# and must pass; then two mutants of the bridge must fail: a write's mask
# on the doubleword after its own, and a write that hits the line buffer
# left unmerged.  Then the video path (below).  Nothing here touches the
# board.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh" >/dev/null
src=$root/fpga/ae350_ddr3
out=$root/build/sim/ae350_ddr3
mkdir -p "$out"
run() {     # name, defines...
    local name=$1; shift
    iverilog -g2012 -Wall -Wno-timescale -o "$out/$name.vvp" "$@" \
        "$src/tb_ahb_ddr3.v" "$src/ahb_ram.sv" "$src/ahb_ddr3.v" >"$out/$name.build.log" 2>&1 ||
        { cat "$out/$name.build.log"; return 2; }
    vvp -n "$out/$name.vvp" >"$out/$name.log" 2>&1
    grep -E "^(PASS|FAIL)" "$out/$name.log" | tail -1
}
rc=0
line=$(run base); echo "$line"; [[ $line == PASS* ]] || rc=1
grep -E "^      " "$out/base.log"
for m in "mask +define+MUT_MASK" "nomerge +define+MUT_NOMERGE"; do
    set -- $m
    line=$(run "$1" "-D${2#+define+}")
    if [[ $line == FAIL* ]]; then echo "PASS  the $1 mutant fails: $line"
    else echo "FAIL  the $1 mutant passes: $line"; rc=1; fi
done

# The video path: fpga/ae350_ddr3/tb_video.v runs ddr3_arb, vid_fetch,
# vid_pix and the TMDS encoders at their real clocks against the same kind
# of request port, with CPU traffic beside them, checks every pixel of three
# frames, two page flips, LATE and the TMDS symbols, and must pass; then
# three mutants must fail: the arbiter routing a word by the wrong read's
# tag, each pixel pair swapped, and one disparity update's sign wrong.
vrun() {    # name, defines...
    local name=$1; shift
    iverilog -g2012 -Wall -Wno-timescale -s tb_video -o "$out/video_$name.vvp" "$@" \
        "$src/tb_video.v" "$src/ddr3_arb.v" "$src/video_ddr3.v" "$src/dvi_tx.v" \
        >"$out/video_$name.build.log" 2>&1 || { cat "$out/video_$name.build.log"; return 2; }
    vvp -n "$out/video_$name.vvp" >"$out/video_$name.log" 2>&1
    grep -E "^(PASS|FAIL)" "$out/video_$name.log" | tail -1
}
line=$(vrun base); echo "$line"; [[ $line == PASS* ]] || rc=1
grep -E "^      " "$out/video_base.log"
for m in tag:MUT_TAG pair:MUT_PAIR disparity:MUT_DISP; do
    line=$(vrun "${m%%:*}" "-D${m##*:}")
    if [[ $line == FAIL* ]]; then echo "PASS  the ${m%%:*} mutant fails: $line"
    else echo "FAIL  the ${m%%:*} mutant passes: $line"; rc=1; fi
done
exit $rc
