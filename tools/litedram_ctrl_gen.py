#!/usr/bin/env python3
"""Generate LiteDRAM's control layer for TinyVCMI's board, with DFI as ports.

The spike (tools/litedram_ctrl_spike.sh) proved the control layer places in the
open flow once the PHY is stubbed.  This tool is the next step: it emits the
same core as a Verilog module whose *top-level* interface is the DFI, so it can
be instantiated beside the hand-written PHY in fpga/ddr3_write and driven by a
DFI adapter, instead of being buried under a stub.

Output, under build/ddr3_ctrl/:
    litedram_core.v     the core as one module, DFI at its ports
    litedram_core.ports the port list, for the adapter and the constraint file

Offline only: generation and, separately, synthesis.  Nothing is packed or
loaded from here.

Usage: tools/litedram_ctrl_gen.py [--out DIR]
"""
import argparse
import os
import sys

TP = os.environ.get("LITEX_THIRD_PARTY", "/run/media/vash/GIT/Tang-PSX/third_party")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build/ddr3_ctrl")
    args = ap.parse_args()

    for pkg in ("litex", "migen", "litedram", "litex-boards", "litepcie"):
        path = f"{TP}/{pkg}"
        if not os.path.isdir(path):
            print(f"missing {path} (set LITEX_THIRD_PARTY)", file=sys.stderr)
            return 2
    sys.path[:0] = [f"{TP}/{p}" for p in
                    ("litex", "migen", "litedram", "litex-boards", "litepcie")]

    from migen import Module, Signal, ClockDomain, ClockSignal, ResetSignal, Cat
    from migen.fhdl import verilog
    from litedram.common import PhySettings
    from litedram.phy.dfi import Interface as DFI
    from litedram.core import LiteDRAMCore
    from litedram.modules import DDR3Module

    # The board's array, as the reference library records it: two x16 devices
    # on one address and command bus, x32 data, 1 GiB, 15 row bits, 10 column
    # bits, 8 banks, DDR3-800 (400 MHz memory clock, 1:4 DFI).
    class BoardDDR3(DDR3Module):
        nbanks = 8
        nrows = 1 << 15
        ncols = 1 << 10
        # ns, DDR3-800 speedgrade; the controller takes the greater of these
        # and the cycle counts the module derives
        tRP = 13.75
        tRCD = 13.75
        tWR = 15.0
        tWTR = 7.5
        tREFI = 7800.0
        tRFC = 160.0
        tFAW = 40.0
        tCCD = 4.0
        tRRD = 7.5
        tRAS = 37.5
        tZQCS = 64.0

    DATABITS = 32
    NPHASES = 4

    module = BoardDDR3(clk_freq=100e6, rate="1:4")
    geom, timing = module.geom_settings, module.timing_settings

    settings = PhySettings(
        phytype="TinyVCMIPhy", memtype="DDR3",
        # LiteDRAM's own GW5 PHY sets dfi_databits = (8 // nphases) * databits,
        # i.e. 2 beats per phase at 1:4, so 64 bits here: four phases then
        # carry the 256 bits of one BL8 burst, which is exactly what the
        # hand-written PHY captures in one PCLK.
        databits=DATABITS, dfi_databits=(8 // NPHASES) * DATABITS, nphases=NPHASES,
        rdphase=0, wrphase=2, cl=6, cwl=5,
        read_latency=7, write_latency=4,
        nranks=1, strobes=DATABITS // 8)

    class DFIPorts(Module):
        """The DFI as this module's top-level interface."""

        def __init__(self):
            self.settings = settings
            self.dfi = DFI(geom.addressbits, geom.bankbits, settings.nranks,
                           settings.dfi_databits, settings.nphases)

    class Top(Module):
        def __init__(self):
            self.clock_domains.cd_sys = ClockDomain("sys")
            self.clock_domains.cd_sys4x = ClockDomain("sys4x")
            self.submodules.phy = phy = DFIPorts()
            self.submodules.core = LiteDRAMCore(phy, geom, timing, 100e6)

            # One user port exposed so the crossbar survives synthesis; the
            # AE350's bridge will replace it.
            port = self.core.crossbar.get_port()
            self.sync += port.cmd.valid.eq(0)   # idle until the bridge drives it
            self.comb += [port.rdata.ready.eq(1), port.wdata.ready.eq(1)]

            ios = {self.cd_sys.clk, self.cd_sys.rst,
                   self.cd_sys4x.clk, self.cd_sys4x.rst}
            ios |= {port.cmd.valid, port.cmd.ready, port.cmd.addr,
                    port.cmd.we, port.cmd.last,
                    port.wdata.valid, port.wdata.ready, port.wdata.data,
                    port.rdata.valid, port.rdata.ready, port.rdata.data}
            for phase in phy.dfi.phases:
                ios |= {phase.address, phase.bank, phase.cas_n, phase.ras_n,
                        phase.we_n, phase.cke, phase.cs_n, phase.odt,
                        phase.wrdata, phase.wrdata_en, phase.wrdata_mask,
                        phase.rddata, phase.rddata_en, phase.rddata_valid}
            self.ios = ios

    out = args.out
    os.makedirs(out, exist_ok=True)
    top = Top()
    text = str(verilog.convert(top, ios=top.ios, name="litedram_core"))
    with open(f"{out}/litedram_core.v", "w") as f:
        f.write(text)

    # the port list, for the adapter and for a constraint file
    ports = sorted(top.ios, key=lambda s: s.backtrace[-1])
    with open(f"{out}/litedram_core.ports", "w") as f:
        for sig in ports:
            name = ".".join(str(n) for n in sig.backtrace[1:])
            f.write(f"{len(sig)} {name}\n")

    print(f"wrote {out}/litedram_core.v ({len(text.splitlines())} lines)")
    print(f"wrote {out}/litedram_core.ports ({len(ports)} top-level signals)")
    print(f"geometry: banks {geom.bankbits}, rows {geom.rowbits}, "
          f"cols {geom.colbits}, dfi {settings.dfi_databits} bits x "
          f"{settings.nphases} phases")
    return 0


if __name__ == "__main__":
    sys.exit(main())
