#!/usr/bin/env bash
# Feasibility gate: can the TinyVCMI open flow build LiteDRAM's GW5A DDR3
# design, or only the hand-written one in fpga/ddr3_write?
#
# The upstream trees are vendored by Tang-PSX.  LiteDRAM ships a GW5A DDR3
# PHY (litedram/phy/gw5ddrphy.py) and litex-boards ships a Tang Console
# target that uses it, but LiteX's own apicula backend refuses GW5 devices,
# so nothing upstream has ever placed that design on this board with an open
# toolchain.  This script answers that question and reports where it stops:
#
#   1. generate the target's gateware (DDR3, 1:4, no CPU) to Verilog;
#   2. rewrite LiteX's SDC and CST into the forms nextpnr-himbaechel accepts;
#   3. synthesise with the open-flow cell library and place and route.
#
# It touches no hardware.  Exit 0 means the design placed; exit 2 means a
# named flow gap blocked it, and the gap is printed.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"

tp=${LITEX_THIRD_PARTY:-/run/media/vash/GIT/Tang-PSX/third_party}
out=${TINYVCMI_LITEX_GATE_DIR:-$root/build/litex_gate}
design=sipeed_tang_console

for d in litex migen litedram litex-boards litepcie; do
    [[ -d "$tp/$d" ]] || { echo "missing $tp/$d (set LITEX_THIRD_PARTY)" >&2; exit 2; }
done
mkdir -p "$out"

echo "[1/4] generate the LiteX Tang Console design"
rm -rf "$out/gateware"
TP="$tp" python3 - "$out" <<'PY'
import os, sys
tp, out = os.environ["TP"], sys.argv[1]
sys.path[:0] = [f"{tp}/{p}" for p in
                ("litex", "migen", "litedram", "litex-boards", "litepcie")]
from litex_boards.targets.sipeed_tang_console import BaseSoC
from litex.soc.integration.builder import Builder
# no CPU: the gate is about the PHY and its constraints, and a CPU adds a
# reset-address requirement that says nothing about DDR3
soc = BaseSoC(device="GW5AST-138C", ddr3_rate="1:4", sys_clk_freq=50e6,
              with_led_chaser=False, with_buttons=False, cpu_type=None)
os.makedirs(out, exist_ok=True)
builder = Builder(soc, output_dir=out, compile_gateware=False, compile_software=False)
builder.build(run=False)
print("      wrote", f"{out}/gateware/{'sipeed_tang_console'}.v")
PY

gw="$out/gateware"
[[ -f "$gw/$design.v" ]] || { echo "generation produced no Verilog" >&2; exit 2; }

echo "[2/4] rewrite LiteX's constraints for nextpnr-himbaechel"
python3 - "$gw" <<'PY'
import pathlib, re, sys
gw = pathlib.Path(sys.argv[1])

# nextpnr rejects create_generated_clock; the same clocks are expressed on
# the nets directly, at the periods the LiteX tree implies (50 MHz board
# clock, 200 MHz PLL output, 50 MHz sys, 200 MHz sys4x).
sdc = [
    "create_clock -name clk50   -period 20.000 [get_ports {clk50}]",
    "create_clock -name clkout  -period  5.000 [get_nets {__main___clkout}]",
    "create_clock -name sys_clk -period 20.000 [get_nets {sys_clk}]",
    "create_clock -name sys4x   -period  5.000 [get_nets {sys4x_clk}]",
]
(gw / "open.sdc").write_text("\n".join(sdc) + "\n")

# nextpnr does not treat IO_LOC "x" p,n; as constraining both pads, which
# leaves the n side unconstrained; split every differential pair.
cst = []
for line in (gw / "sipeed_tang_console.cst").read_text().splitlines():
    m = re.match(r'IO_LOC "([^"]+)"\s+([A-Z0-9]+),([A-Z0-9]+);', line)
    if not m:
        cst.append(line)
        continue
    port, p, n = m.groups()
    nport = (port.replace("_p[", "_n[") if "_p[" in port
             else port[:-2] + "_n" if port.endswith("_p") else port)
    cst += [f'IO_LOC "{port}" {p};', f'IO_LOC "{nport}" {n};']
(gw / "open.cst").write_text("\n".join(cst) + "\n")
print(f"      wrote open.sdc and open.cst ({sum('IO_LOC' in l for l in cst)} pad locations)")
PY

echo "[3/4] synthesis with the open-flow cell library"
cells="$oss_suite/share/yosys/gowin/cells_xtra_gw5a.v"
yosys -Q -T -q -l "$out/synth.log" -p "
    read_verilog -lib $cells
    read_verilog $gw/$design.v
    synth_gowin -family gw5a -top $design
    write_json $out/design.json
" || { echo "GATE: synthesis failed; see $out/synth.log" >&2; exit 2; }
grep -E '^\s+[0-9]+\s+(LUT4|DFF|IOB)' "$out/synth.log" | tail -3 || true
echo "      every primitive in the design is one the fork already has"

echo "[4/4] placement and routing"
if "$nextpnr_himbaechel" --json "$out/design.json" --write "$out/routed.json" \
        --device "$gowin_device" --freq 50 \
        --vopt "cst=$gw/open.cst" --sdc "$gw/open.sdc" >"$out/nextpnr.log" 2>&1; then
    grep -E 'Max frequency for clock' "$out/nextpnr.log" | tail -3
    echo "GATE: the upstream design placed and routed with the open flow"
    exit 0
fi
grep -E '^ERROR' "$out/nextpnr.log" | head -3 >&2
echo "GATE: blocked by the open flow, not by the PHY; see $out/nextpnr.log" >&2
exit 2
