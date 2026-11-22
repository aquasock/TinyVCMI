# TinyVCMI

TinyVCMI is an open-flow port of VCMI to the Sipeed Tang Console 138K. The
target architecture runs the game logic on the hardened AE350 subsystem and
uses FPGA video plus the console's Logitech keyboard and mouse path.

The first engineering milestone is a fully open DDR3 interface. The final
bitstream must be built by Yosys, nextpnr-himbaechel, and Apicula; vendor output
may be used as a measurement oracle, but it is not part of the deliverable.

## Current state

The DDR3 milestone runs on the board. The open-flow DDR3 image matches the
vendor build on all 306 DDR3 tables, the PHY initialises the device and reads
its MPR pattern on all 32 DQ, and the controller image trains itself at
start-up, hands the bus to `ddr3_ctl` and tests the whole 1 GiB. What blocks the
milestone is the write path: the controller's write alignment is trained rather
than levelled, and a netlist that adds a gap to separate the doubled write from
the mask byte fails its own write-alignment search where the netlist before it
trains. `.ai/core-log.md` carries the live state and the next measurement.

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
