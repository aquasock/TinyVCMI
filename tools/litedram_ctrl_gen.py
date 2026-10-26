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
    # Migen names signals partly by iterating sets of strings, whose order
    # follows Python's per-process string hashing: two runs can name the same
    # signal differently, and the controller's build checks that its core is
    # byte for byte the one the vendor build used.  A fixed seed makes the
    # output reproducible.
    if os.environ.get("PYTHONHASHSEED") != "0":
        os.environ["PYTHONHASHSEED"] = "0"
        os.execv(sys.executable, [sys.executable] + sys.argv)
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build/ddr3_ctrl")
    ap.add_argument("--setting", action="append", default=[], metavar="KEY=VALUE",
                    help="a LiteDRAM ControllerSettings field, e.g. cmd_buffer_buffered=True")
    args = ap.parse_args()
    import ast
    ctrl_settings = {}
    for s in args.setting:
        k, v = s.split("=", 1)
        ctrl_settings[k] = ast.literal_eval(v)

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
    from litedram.core.controller import ControllerSettings
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
        # READ and WRITE on phase 0, the first memory clock of a PCLK, where
        # the trained PHY of fpga/ddr3_write issues its own: a READ's burst
        # then reaches the deserializers whole in one PCLK, at the trained
        # offset, and a WRITE's data takes the trained alignment unchanged.
        # ACTIVATE and PRECHARGE go on phase 3, the steerer's rdphase - 1.
        # CL 6 and CWL 5 are the MR0 and MR2 the PHY's start-up writes.
        rdphase=0, wrphase=0, cl=6, cwl=5,
        # fpga/ddr3_ctrl/dfi_phy.v: every command three PCLK behind the DFI,
        # write data the PCLK after wrdata_en, and the burst on the DFI
        # fifteen PCLK after rddata_en whatever the trained read offset
        read_latency=15, write_latency=1,
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
            self.submodules.core = LiteDRAMCore(
                phy, geom, timing, 100e6,
                controller_settings=ControllerSettings(**ctrl_settings))

            # One native user port, driven by fpga/ddr3_ctrl/ddr3_bist.v and
            # later by the AE350's bridge.
            port = self.core.crossbar.get_port()

            ios = {self.cd_sys.clk, self.cd_sys.rst,
                   self.cd_sys4x.clk, self.cd_sys4x.rst}
            ios |= {port.cmd.valid, port.cmd.ready, port.cmd.addr,
                    port.cmd.we, port.cmd.last,
                    port.wdata.valid, port.wdata.ready, port.wdata.data, port.wdata.we,
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
