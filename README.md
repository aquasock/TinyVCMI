# TinyVCMI

TinyVCMI is an open-flow port of VCMI to the Sipeed Tang Console 138K. The
target architecture runs the game logic on the hardened AE350 subsystem and
uses FPGA video plus the console's Logitech keyboard and mouse path.

Every bitstream is built by Yosys, nextpnr-himbaechel and Apicula; vendor
output may be used as a measurement oracle, but it is not part of the
deliverable.

## Current state

- **v0.1.0, the open-flow DDR3 milestone, is released.** The board's 1 GiB of
  DDR3 runs at DDR3-800 through this project's own PHY wiring, controller and
  training ([below](#the-ddr3-milestone-v010)).
- **The AE350 runs from that DDR3** as its main memory: 1 GiB less 64 KiB at
  `0x40000000`, through an AHB bridge to the controller
  (`fpga/ae350_ddr3/`). The boot ROM tests it at every start and loads
  programs over the UART (`tools/load_ae350.py`).
- **1280x720 at 60 Hz on HDMI** is scanned out of a 32-bit frame buffer in the
  DDR3 at `0x7f000000`, beside the CPU's traffic, with two pages flipped at
  vertical blank.
- **SDL2 2.32.10 draws and flips on the board** through the `tinyvcmi` video
  driver (`firmware/sdl/`), the first half of the port plan's gate G1
  (`firmware/apps/sdl_test`).
- Everything since v0.1.0 is unreleased. `.ai/core-log.md` carries the live
  state and the next steps; `docs/vcmi-port-plan.md` carries the plan for the
  engine itself.

## DDR3 as the A25's memory: latest results

Measured on 2026-11-27 on the current image, seed 8 of `build/ae350/e1`
(`ctrl.fs` SHA-256 `6757c049...c6bc5c6`, `pclk` 102.90 MHz, `bus_clk`
75.64 MHz), warm, with the A25 at 750 MHz, its caches on and the video off
unless stated. One 32-byte line is one A25 cache line. The "first image"
column is the first image that ran the A25 from the DDR3 (core-log entries 17,
23 and 24), before the bridge and read path were redesigned (entries 30, 33
and 35).

| Measurement (program) | First image | Now | Gain |
|---|---:|---:|---:|
| Dependent load miss, 4 MiB (`ddr3_test`) | 503.0 cycles | 437.3 cycles | 1.15x |
| Streamed line read (`ddr3_test`) | 477.2 cycles | 154.4 cycles | 3.1x |
| Line stored and written back (`ddr3_test`) | 662.6 cycles | 180.2 cycles | 3.7x |
| Sequential line read (`write_cost`) | 513.3 cycles | 175.0 cycles (233 ns, 137 MB/s) | 2.9x |
| Full-line store, cached (`write_cost`) | 738.0 cycles | 180.4 cycles (240 ns, 133 MB/s) | 4.1x |
| The same with 720p scanout running | 738.0 cycles | 234.4 cycles | 3.1x |
| 32-bit fill, whole 1280x720 screen (`vcmi_bench`) | 113 ms, 8.8 fps | 36.0 ms, 27.8 fps | 3.2x |
| Full-array test, 1022 MiB, per seed (`ddr3_test`) | 102.95 s | 35.65 s | 2.9x |

Both seeds of the full-array test passed with 0 failures, and the boot ROM's
own lane, address-line and pattern tests pass at every start. What changed:

- **Writes are posted.** The bridge (`fpga/ae350_ddr3/ahb_ddr3.v`) carries
  every access in program order through one 16-entry asynchronous queue, and
  `ahb_ram.sv` acknowledges a write with no wait state while the queue has
  room. A cache line's write-back went from 239.2 to 51.5 cycles, about
  466 MB/s (entry 30).
- **Reads are answered from a line buffer and fetched ahead.** A sequential
  beat in the line just read completes with no wait state (entry 33), and a
  four-way read buffer keeps several reads in flight and fetches the next
  lines ahead (entry 35). The prefetch depth is a register,
  `TV_PERF_PF_DEPTH` (0 to 3, reset 2). Per line, as
  `firmware/apps/rd_lat` measures it:

  | Depth | Sequential, 8 words a line | Sequential, 1 word a line | Scattered |
  |---:|---:|---:|---:|
  | 0 | 549.7 ns | 538.6 ns | 583.4 ns |
  | 1 | 291.8 ns | 269.4 ns | 583.4 ns |
  | 2 (reset) | 233.5 ns | 206.0 ns | 583.4 ns |
  | 3 | 226.9 ns | 200.1 ns | 583.4 ns |

  Before the redesign a line cost about 636 ns whatever the pattern (entry
  32). A miss that no prefetch covers still waits 336 to 397 ns for the
  DDR3; `rd_lat` breaks it down from hardware counters
  (`fpga/ae350_ddr3/ddr3_perf.v`, `exts_perf.sv`).

Limits that are measured but not yet removed:

- **Scattered reads** gain nothing from prefetch and, at 583.4 ns a line, are
  slower than before the four-way buffer (553.1 ns); that is not yet
  explained.
- **Scanout costs stores about 30 per cent:** 234.4 cycles a line with the
  720p raster running against 180.4 without it, while reads are unchanged.
- **A full-screen redraw is still memory-bound.** A 32-bit fill costs 29.2
  cycles a pixel against 3.0 for the same fill served from the L1 cache, a
  copy 118.4, an 8-bit palette expand 59.6, a 2x scale 56.6 and an alpha
  blend 152.4 (`firmware/apps/vcmi_bench`). Through SDL2's software renderer
  a full-screen frame of fills costs 66.5 ms, about 15 fps.
- **Keep the D-cache on.** Turning it off around a store-only pass, which
  paid on the first image, now costs 319.9 cycles a line against 187.1 cached
  (`firmware/apps/pma_probe`, AE350-010).
- **No hardware atomics.** On this A25 an AMO whose line is not in the
  D-cache, or any AMO with the D-cache off, never returns, and LR on such a
  line does not bring the line in, so every SC after it fails (AE350-011 in
  `.ai/core-reference.md`). Programs and SDL2 are therefore built for
  `rv32imc`, without the A extension, and every atomic goes through
  `firmware/rt/atomic.c` at 20 to 30 cycles a call; the link refuses an
  image with an AMO, LR or SC in it.
- **Fences are expensive.** A fence that orders writes costs 1,170 to 1,500
  cycles after any memory access (AE350-012), and GCC puts one around every
  `seq_cst` atomic load and store.
- **The DDR3 array itself is not the limit.** The controller's own test reads
  and writes the whole array at about 2.67 GB/s, 83 per cent of DDR3-800 x32's
  3.2 GB/s peak; the A25 reaches about 137 MB/s of it, because it waits for
  each miss.

The A25 cycle counts are best-of-three runs. `rd_lat` reproduced to 0.1 cycle
across two sessions, and `write_cost` to 1.5 cycles once the video was in the
same state; until entry 40 `write_cost` left the video as it found it, so an
earlier "video off" reading of 233.0 cycles was in fact taken with the raster
running, and it now turns the video off itself.
The alpha blend measured 138.9 cycles in an earlier build of the same source,
a change from the program's placement rather than the memory.

## The DDR3 milestone (v0.1.0)

The Tang Console 138K's 1 GiB of DDR3 runs at DDR3-800 (400 MHz memory clock,
DLL on) from a bitstream built only by Yosys, nextpnr-himbaechel and Apicula,
with no vendor IP:

- The PHY uses the GW5A's hard DDR3 primitives -- `DDRDLL`, `DQS`,
  `OSER8_MEM` and `IDES8_MEM` -- and the open-flow image matches the vendor
  build on all 306 DDR3 configuration tables.
- The controller (`fpga/ddr3_ctrl/ddr3_ctl.v`) and its training
  (`fpga/ddr3_write/`) are this project's own. At start-up the image trains
  every lane's read gate, delay and write alignment, hands the bus to the
  controller and runs a memory test over the whole array.
- The released image meets 100 MHz on its 1:4 fabric clock with every path
  timed: `pclk` at 100.25 MHz, the 50 MHz control clock at 62.84 MHz and the
  400 MHz memory clock at 798.08 MHz.
- On the board it trains on the first attempt and runs 734 passes of the full
  1 GiB test in 10 minutes with no error, warm and from a cold start.

Closing timing needed two fixes to the timing database that nextpnr's Gowin
generator builds, both inherited from upstream nextpnr: it timed no path
through a LUT1, LUT2 or LUT3, and none into a LUT RAM's data inputs.
`tools/nextpnr_arcs.sh` builds a corrected chipdb beside a copy of the nextpnr
binary from `tools/nextpnr_arcs.patch`; the released image reproduces byte for
byte. Images are chosen by placement seed: the current AE350 image's netlist
closes every clock on three seeds of twelve, and a seed must also pass a video
check on the board, because one placement that closed timing never
acknowledged a page flip (entry 35).

## Building and running

- `tools/ddr3_ctrl_sweep.sh` builds the controller-only image, and
  `tools/ae350_ddr3_sweep.sh OUT SEED...` the AE350 image, both through the
  patched nextpnr; `tools/closure_census.py` judges a sweep.
- `tools/sim_ddr3_ctrl.sh`, `tools/sim_ddr3_lockstep.sh` and
  `tools/sim_ae350_ddr3.sh` are the simulation gates, each with mutants that
  must fail.
- On the board (one-wire mode): load the `.fs` with `openFPGALoader -c
  ft2232`, check training with `tools/ddr3_write_probe.py ctrl`, hand the
  memory to the A25 with `tools/ddr3_write_probe.py handover`, then run a
  program with `tools/load_ae350.py`. Programs are under `firmware/apps/` and
  build with `make` against the runtime in `firmware/rt/`.
- `tools/build_sdl2.sh` fetches the pinned SDL2 release and builds it for the
  AE350 with the patches in `firmware/sdl/`; `tools/build_sdl2_addons.sh`
  then builds SDL2_ttf, with FreeType, and SDL2_image beside it.

Two offline checks need no board: `tools/build_openflow_smoke.sh` builds a
minimal design through the whole open toolchain, and
`tools/ddr3_openflow_preflight.sh` reports the open flow's DDR3 primitive
support boundary. `docs/ddr3-open-flow.md` has the DDR3 milestone's sequence
and primitive matrix. Build products are written below `build/`.

## License

TinyVCMI is free software under the GNU General Public License, version 3
only (GPL-3.0-only); see `LICENSE`. The AE350 system in `fpga/ae350_ddr3` and
the firmware in `firmware/` start from TinyNES's, which is under the same
license. VCMI itself is GPL-2.0-or-later, which permits its use in a
GPL-3.0 work. Third-party components, SDL2 among them, are listed in
`THIRD_PARTY.md`.
