# TinyVCMI

TinyVCMI is an open-flow port of VCMI to the Sipeed Tang Console 138K. The
target architecture runs the game logic on the hardened AE350 subsystem and
uses FPGA video plus the console's Logitech keyboard and mouse path.

The first engineering milestone is a fully open DDR3 interface. The final
bitstream must be built by Yosys, nextpnr-himbaechel, and Apicula; vendor output
may be used as a measurement oracle, but it is not part of the deliverable.

## Current state

**v0.1.0: the DDR3 milestone is met.** The Tang Console 138K's 1 GiB of DDR3
runs at DDR3-800 (400 MHz memory clock, DLL on) from a bitstream built only by
Yosys, nextpnr-himbaechel and Apicula, with no vendor IP:

- The PHY uses the GW5A's hard DDR3 primitives -- `DDRDLL`, `DQS`,
  `OSER8_MEM` and `IDES8_MEM` -- and the open-flow image matches the vendor
  build on all 306 DDR3 configuration tables.
- The controller (`fpga/ddr3_ctrl/ddr3_ctl.v`) and its training
  (`fpga/ddr3_write/`) are this project's own. At start-up the image trains
  every lane's read gate, delay and write alignment, hands the bus to the
  controller and runs a memory test over the whole array.
- The image meets 100 MHz on its 1:4 fabric clock with every path timed: the
  closed image runs `pclk` at 100.25 MHz, the 50 MHz control clock at 62.84 MHz
  and the 400 MHz memory clock at 798.08 MHz.
- On the board it trains on the first attempt and runs 734 passes of the full
  1 GiB test in 10 minutes with no error, warm and from a cold start.

Closing timing needed two fixes to the timing database that nextpnr's Gowin
generator builds, both inherited from upstream nextpnr: it timed no path
through a LUT1, LUT2 or LUT3, and none into a LUT RAM's data inputs.
`tools/nextpnr_arcs.sh` builds a corrected chipdb beside a copy of the nextpnr
binary from `tools/nextpnr_arcs.patch`, and `tools/ddr3_ctrl_sweep.sh` builds
the controller image with it; the released image reproduces byte for byte.
Only about one placement seed in seventeen closes 100 MHz, so images are
chosen by seed. `.ai/core-log.md` carries the live state and the next
milestone: the AE350 running from DDR3.

The repository also contains two offline checks:

- `tools/build_openflow_smoke.sh` builds a minimal, non-DDR design through the
  complete open toolchain.
- `tools/ddr3_openflow_preflight.sh` synthesizes isolated DDR3 PHY primitives
  and reports the exact nextpnr support boundary. A reported `GAP` is a
  successful characterization, not a usable DDR3 implementation.

Neither script programs or communicates with the Tang. Build products are
written below `build/`.

```sh
tools/build_openflow_smoke.sh
tools/ddr3_openflow_preflight.sh
```

See `docs/ddr3-open-flow.md` for the milestone sequence and current primitive
matrix.

## License

TinyVCMI is free software under the GNU General Public License, version 3
only (GPL-3.0-only); see `LICENSE`. The AE350 system in `fpga/ae350_ddr3` and
the firmware in `firmware/` start from TinyNES's, which is under the same
license. VCMI itself is GPL-2.0-or-later, which permits its use in a
GPL-3.0 work.
