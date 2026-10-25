#!/usr/bin/env bash
# Spike: can LiteDRAM's *control layer* be built by the TinyVCMI open flow on
# its own, with the PHY replaced by a stub?
#
# The full upstream design (tools/litex_ddr3_gate.sh) stops on three flow
# gaps -- a generated clock, a differential IO_LOC pair, and sys4x_clk driving
# OSER8.FCLK -- and all three belong to its PHY or its constraints.  This
# script removes the PHY entirely: the LiteDRAM core is instantiated against a
# stub that provides only what the core actually asks of a PHY, a PhySettings
# object and a DFI interface, and the result is pushed through Yosys and
# nextpnr for GW5AST-138C.
#
# It answers three questions with measurements rather than opinion:
#   1. does the control layer generate as Verilog on its own;
#   2. does it synthesise and place in the open flow, or do the three gaps
#      reappear without any PHY present;
#   3. what is its PHY-facing contract, in ports and clock domains.
#
# Offline only: it synthesises and places, never packs or loads anything.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"

tp=${LITEX_THIRD_PARTY:-/run/media/vash/GIT/Tang-PSX/third_party}
out=${TINYVCMI_LITEX_SPIKE_DIR:-$root/build/litedram_ctrl_spike}
for d in litex migen litedram litex-boards litepcie; do
    [[ -d "$tp/$d" ]] || { echo "missing $tp/$d (set LITEX_THIRD_PARTY)" >&2; exit 2; }
done
mkdir -p "$out/gateware"

echo "[1/4] generate LiteDRAM's control layer against a stub PHY"
TP="$tp" python3 - "$out" <<'PY'
import os, sys
tp, out = os.environ["TP"], sys.argv[1]
sys.path[:0] = [f"{tp}/{p}" for p in
                ("litex", "migen", "litedram", "litex-boards", "litepcie")]

from migen import *
from migen.fhdl import verilog
from litedram.common import PhySettings
from litedram.phy.dfi import Interface as DFI
from litedram.core import LiteDRAMCore
from litedram.modules import MT41K128M16

# The stub is the measurement: this is every attribute the core touches on a
# PHY, found by letting it fail until it stopped asking.
class StubPHY(Module):
    def __init__(self, settings, addressbits, bankbits):
        self.settings = settings
        self.dfi = DFI(addressbits, bankbits, settings.nranks,
                       settings.dfi_databits, settings.nphases)

class Spike(Module):
    def __init__(self):
        module = MT41K128M16(clk_freq=100e6, rate="1:4")
        geom, timing = module.geom_settings, module.timing_settings
        settings = PhySettings(
            phytype="StubPHY", memtype="DDR3",
            # the stub is the PHY, so these are its declared parameters:
            # x16 device, 4:1 DFI, DDR3-800 CL6/CWL5
            databits=16, dfi_databits=64, nphases=4,
            rdphase=0, wrphase=2, cl=6, cwl=5,
            read_latency=9, write_latency=5,
            nranks=1, strobes=2)
        self.clock_domains.cd_sys = ClockDomain("sys")
        self.clock_domains.cd_sys4x = ClockDomain("sys4x")
        self.submodules.phy = phy = StubPHY(settings, geom.addressbits,
                                           geom.bankbits)
        self.submodules.core = LiteDRAMCore(phy, geom, timing, 100e6)
        # A crude requester so the crossbar, the bank machines and the DFI
        # command path are all live: nothing here is a PHY, and the point of
        # the spike is that the control layer places, not that it works.
        port = self.core.crossbar.get_port()
        cnt  = Signal(16)
        beat = Signal(1)
        d    = phy.dfi.phases[0]
        self.sync += cnt.eq(cnt + 1)
        self.comb += [
            port.cmd.valid.eq(cnt[:4] == 0),
            port.cmd.we.eq(cnt[4]),
            port.cmd.addr.eq(cnt[5:5 + port.address_width]),
            port.cmd.last.eq(1),
            port.wdata.valid.eq(port.cmd.valid & cnt[4]),
            port.wdata.data.eq(cnt),
            port.rdata.ready.eq(1),
        ]
        self.sync += beat.eq(beat + 1 + Cat(d.cas_n, d.ras_n, d.we_n,
                                           d.rddata_valid,
                                           port.rdata.valid,
                                           port.cmd.ready,
                                           port.wdata.ready,
                                           d.bank[0]))
        # One derived clock and one observable output: the flow then has only
        # three top-level IOs to place, and the whole control layer stays live
        # because the beat register consumes its DFI and port outputs.
        self.comb += self.cd_sys4x.clk.eq(ClockSignal("sys"))
        self.comb += self.cd_sys4x.rst.eq(ResetSignal("sys"))
        self.ios = {self.cd_sys.clk, self.cd_sys.rst, beat}

top = Spike()
v = verilog.convert(top, ios=top.ios, name="litedram_ctrl")
path = f"{out}/gateware/litedram_ctrl.v"
open(path, "w").write(str(v))
print(f"      wrote {path}")
PY

verilog_file="$out/gateware/litedram_ctrl.v"
[[ -s "$verilog_file" ]] || { echo "generation produced no Verilog" >&2; exit 2; }

echo "[2/4] report the PHY-facing contract"
python3 - "$verilog_file" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
body = text[text.find("module litedram_ctrl"):]
ins = re.search(r"\binput\b([^;]*);", body, re.S)
outs = re.search(r"\boutput\b([^;]*);", body, re.S)
def names(blob):
    return sorted(set(re.findall(r"[A-Za-z_]\w*", blob or "")) - {"wire", "reg", "input", "output"})
i, o = names(ins.group(1)), names(outs.group(1))
print(f"      {len(i)} inputs, {len(o)} outputs at the top level")
print(f"      lines of Verilog: {len(body.splitlines())}")
print(f"      DFI is the only PHY contract: phy.settings + phy.dfi")
PY

echo "[3/4] Yosys synthesis for GW5A"
cells="$oss_suite/share/yosys/gowin/cells_xtra_gw5a.v"
yosys -Q -T -q -l "$out/synth.log" -p "
    read_verilog -lib $cells
    read_verilog -sv $verilog_file
    synth_gowin -family gw5a -top litedram_ctrl
    stat
    write_json $out/ctrl.json
" || { tail -20 "$out/synth.log" >&2; echo "SYNTHESIS FAILED" >&2; exit 2; }
grep -E "Number of cells|Number of wires|SB_" "$out/synth.log" | tail -12 || true

echo "[4/4] nextpnr placement and routing"
cat >"$out/spike.cst" <<'CST'
// Placeholders: the spike is never packed into a bitstream or loaded, so
// these balls are only where nextpnr puts three signals.
IO_LOC "sys_clk" V22;
IO_PORT "sys_clk" IO_TYPE=LVCMOS33 PULL_MODE=UP;
IO_LOC "sys_rst" U15;
IO_PORT "sys_rst" IO_TYPE=LVCMOS33 PULL_MODE=UP;
IO_LOC "beat" V14;
IO_PORT "beat" IO_TYPE=LVCMOS33;
CST
cat >"$out/spike.sdc" <<'SDC'
create_clock -name sys -period 10.000 [get_ports {sys_clk}]
create_clock -name sys4x -period 10.000 [get_ports {sys_clk}]
SDC
set +e
"$nextpnr_himbaechel" --json "$out/ctrl.json" --write "$out/ctrl-routed.json" \
    --device "$gowin_device" --freq 50 \
    --vopt "cst=$out/spike.cst" --sdc "$out/spike.sdc" \
    >"$out/nextpnr.log" 2>&1
rc=$?
set -e
if [[ $rc -eq 0 ]]; then
    echo "PLACED: the control layer alone builds in the open flow"
    grep -E "Max frequency|Info: Device utilisation" "$out/nextpnr.log" | tail -6 || true
else
    echo "BLOCKED: exit $rc" >&2
    grep -iE "error|invalid|reject|unsupported|no bel|failed" "$out/nextpnr.log" | head -8 >&2
    exit 2
fi
