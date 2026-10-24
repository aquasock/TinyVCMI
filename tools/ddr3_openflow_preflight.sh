#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"

src="$root/fpga/ddr3_phy_probe"
out=${TINYVCMI_PREFLIGHT_DIR:-$root/build/ddr3_openflow_preflight}
cells="$oss_suite/share/yosys/gowin/cells_xtra_gw5a.v"
mkdir -p "$out"

probes=(ddrdll dqs oser8_mem ides8_mem iodelay clkdiv)
declare -A cell=(
    [ddrdll]=DDRDLL
    [dqs]=DQS
    [oser8_mem]=OSER8_MEM
    [ides8_mem]=IDES8_MEM
    [iodelay]=IODELAY
    [clkdiv]=CLKDIV
)
# The DQS probe needs its DQSIN on the lane's own pad; every other probe uses
# the shared constraints.
declare -A cst=(
    [dqs]="$src/ddr3_phy_probe_dqs.cst"
)

printf '%-12s %-10s %-12s\n' PRIMITIVE SYNTHESIS NEXTPNR
printf '%-12s %-10s %-12s\n' --------- --------- -------

gap_count=0
for probe in "${probes[@]}"; do
    top="probe_$probe"
    json="$out/$probe.json"
    synth_log="$out/$probe-synth.log"
    pnr_log="$out/$probe-nextpnr.log"

    yosys -Q -T -q -l "$synth_log" -p "
        read_verilog -lib $cells
        read_verilog -sv $src/ddr3_phy_probe.sv
        synth_gowin -family gw5a -top $top
        write_json $json
    "

    if ! grep -Eq "\"type\"[[:space:]]*:[[:space:]]*\"${cell[$probe]}\"" "$json"; then
        printf '%-12s %-10s %-12s\n' "${cell[$probe]}" FAIL NOT-RUN
        echo "synthesis did not retain ${cell[$probe]} in $json" >&2
        exit 1
    fi

    if "$nextpnr_himbaechel" \
        --json "$json" \
        --write "$out/$probe-routed.json" \
        --device "$gowin_device" \
        --freq 50 \
        --vopt "cst=${cst[$probe]:-$src/ddr3_phy_probe.cst}" \
        --sdc "$src/ddr3_phy_probe.sdc" \
        >"$pnr_log" 2>&1; then
        printf '%-12s %-10s %-12s\n' "${cell[$probe]}" PASS PASS
    else
        printf '%-12s %-10s %-12s\n' "${cell[$probe]}" PASS GAP
        gap_count=$((gap_count + 1))
        grep -m1 -E "unconstrained|not supported|not found|no BELs|no valid BEL|unknown|ERROR|Error" \
            "$pnr_log" | sed 's/^/  /' || tail -1 "$pnr_log" | sed 's/^/  /'
    fi
done

echo
echo "Preflight PASS: synthesis and nextpnr boundaries reproduced."
echo "Place-and-route gaps: $gap_count of ${#probes[@]} primitive probes."
echo "A GAP is expected characterization and does not mean DDR3 is usable."
echo "Hardware was not accessed."
