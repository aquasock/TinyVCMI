## 1 COMMIT Unreleased 2026-10-22T22:05:37-07:00

#### Coming From:

Unreleased e1b7e01

#### Purpose:

Establish the initial TinyVCMI reference library and record the approved strict-open-flow DDR3 direction.

#### Outcome:

The new TinyTang-format reference library records the revision-C GW5AST target, the onboard 1 GiB x32 DDR3 array, the qualified 32 MiB SDR SDRAM window and unqualified second device, the hardware-proven Tang-PSX DDR3 behavior, the current inability to import Gowin's encrypted controller as an opaque open-flow block, the AE350 memory and cache contracts, the TinyNES and TinyGBC video and loading architecture, TinyTang's current Logitech keyboard and mouse input commands, and the completed MiSTer-VCMI port's VCMI 1.7.5 baseline and roughly 100 to 115 MB resident footprint. The records distinguish sibling-project hardware evidence from TinyVCMI validation and identify the missing open PHY, packing, placement, routing and calibration evidence without claiming that open DDR3 already works. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this first entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Propose the first engineering cycle as an isolated open-flow DDR3 proof: inventory the required GW5AST memory primitives and bitstream features against the vendor reference, add the smallest open-tool support boundary that can produce a calibration diagnostic, and validate it on hardware before connecting the AE350, video, or VCMI.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 2 COMMIT Unreleased 2026-10-22T22:22:57-07:00

#### Coming From:

Unreleased 63c22ce

#### Purpose:

Establish a reproducible open-flow hardware baseline and isolate the primitive-level boundary blocking DDR3 PHY implementation.

#### Outcome:

Added a deterministic Yosys, nextpnr-himbaechel and Apicula smoke build with a simulated 2 Mbaud TinyTang core-ID responder, plus isolated synthesis and place-and-route probes for the six PHY primitives present in the qualified vendor reference. The preflight passed and proved that static `IODELAY` and `CLKDIV` route while `DDRDLL`, `DQS`, `OSER8_MEM` and `IDES8_MEM` synthesize but have no placeable GW5AST BEL in the current backend. The smoke image, SHA-256 `71371bb38e2e66bf7332fef503198022bf4507688817af9693263c65f48add0c` as `.fs` and `cb1c80b8b97adc7dbd021b7265023b6e6ed7e1c3fec999a953aae1cc8f7cb124` as `.bin`, was loaded into SRAM through TinyTang without exposing or driving any DDR3 pin; the GW5AST reported ID `0001081b` and the design answered core ID `0x56` at 2 Mbaud. The user accepted the hardware result as PASS. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated both active entries' six-section ordering, prose, Status values, sequential numbering and active-log capacity.

#### Next Steps:

Reverse engineer and implement the GW5AST `DDRDLL` BEL, placement, routing, parameters and Apicula packing, then build a lock-and-step diagnostic that continues to leave every DDR3 package pin undriven.

#### Files Modified:

- .gitignore
- README.md
- docs/ddr3-open-flow.md
- fpga/ddr3_phy_probe/ddr3_phy_probe.cst
- fpga/ddr3_phy_probe/ddr3_phy_probe.sdc
- fpga/ddr3_phy_probe/ddr3_phy_probe.sv
- fpga/openflow_smoke/openflow_smoke.cst
- fpga/openflow_smoke/openflow_smoke.sdc
- fpga/openflow_smoke/openflow_smoke.sv
- tests/openflow_smoke_tb.sv
- tools/build_openflow_smoke.sh
- tools/ddr3_openflow_preflight.sh
- tools/openflow_env.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 3 COMMIT Unreleased 2026-10-22T22:38:22-07:00

#### Coming From:

Unreleased d201083

#### Purpose:

Measure the GW5AST-138C DDRDLL placement, configuration and routing boundary needed for the first open-flow DDR3 PHY primitive.

#### Outcome:

Added an offline, measurement-only Gowin EDA 1.9.11.03 DDRDLL oracle and completed eight vendor builds covering all four master placements plus isolated `CODESCAL`, `SCAL_EN`, `DIV_SEL` and `DLL_FORCE` changes. The measurements identified the four corner configuration cells, mapped the BL parameter changes to existing `DLL0` features 12 through 15, and recovered the BL `CLKIN`, `STOP`, `RESET`, `UPDNCNTL`, `STEP[0:7]` and `LOCK` fabric wires from the device database. The detailed handoff is in `docs/ddr3-open-flow.md`; no Apicula or nextpnr source was changed, no open-flow DDRDLL image was built, and the Tang was not accessed because the user stopped the cycle for agent handoff. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated all three active entries' six-section ordering, prose, Status values, sequential numbering and active-log capacity.

#### Next Steps:

Implement the measured DDRDLL sites, port aliases, placement macros and `DLL0` packing in the Apicula and nextpnr forks, rebuild both tools, and route the oracle shape through the strict open flow; coordinate with the user before any Tang access for the later lock-and-step hardware test.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/ddrdll_oracle/run.tcl
- tools/ddrdll_oracle/top.cst
- tools/ddrdll_oracle/top.sdc
- tools/ddrdll_oracle/top.v
- tools/run_ddrdll_oracle.sh

#### Status:

- Build: PASS
- Deployment: NOT RUN
- User Test: NOT RUN

---
## 4 COMMIT Unreleased 2026-10-22T23:39:46-07:00

#### Coming From:

Unreleased 232440b

#### Purpose:

Implement the measured bottom-left DDRDLL master in the open-flow forks so the primitive can be placed, routed and packed without inventing any connection the vendor bitstream did not establish.

#### Outcome:

Implemented `DDRDLL` support in both toolchain forks on branch `epic/gw5ast138c`. Apicula's `get_DDRDLL_fuses` maps the four parameters onto `DLL0` features 12 through 15 in the configuration cell, translating the port tile at column 1 of the bottom edge to the corner cell at column 0, and refuses any other site, any `CODESCAL` value other than `111` and `000`, and any feature whose entry is missing from that site's table; the Himbaechel Gowin arch creates one bel at `X1Y108` with `CLKIN`, `STOP`, `RESET` and `UPDNCNTL` on `CLK0`, `A6`, `LSR0` and `A5` and `STEP[0]` through `STEP[7]` on `Q0` through `Q7`, and resolves `INS_LOC "<cell>" DDRDLLM_BL` through the chipdb macro table. Measurement changed the approved plan in four ways. The primitive is a two-cell macro: its ports are not in the configuration tile. `LOCK` reaches the fabric through a dedicated path with no configurable bit at all, appearing on the row-99 track of column 1 as `Q7 -> E820`, so the arch deliberately exposes no `LOCK` pin and a design that uses one fails placement with `No wire found for port LOCK on source cell ddrdll` instead of routing a dead net. Re-deriving the feature deltas from the raw sweep bitstreams corrected an earlier reading: `(21,9)` is set in every build including `CODESCAL=000`, so `DLL0` feature 5 is not the `000` code and `000` emits no fuses. And TR's `DLL0` table carries no entry for feature 12 or 13, so it cannot encode `CODESCAL=111` at all. Three further offline vendor builds isolated the ports and `LOCK`, and the corner tables agree with the TL, BL and BR baselines on features 12 to 15. Verification was offline only: `tools/ddr3_openflow_preflight.sh` now reports `DDRDLL PASS/PASS` with `DQS`, `OSER8_MEM` and `IDES8_MEM` unchanged at `GAP`, the routed cell carries `NEXTPNR_BEL=X1Y108/DDRDLL_BL`, and packing that routed probe sets exactly `(20,17)`, `(20,19)` and `(20,20)` at tile `(0,108)` plus the tile's four constant bits while setting none of `(20,18)`, `(21,14)` and `(20,16)`, matching all four vendor deltas. `ripgrep` is absent from this machine, so both tool scripts now use POSIX `grep`, and the probe drives `STEP` rather than `LOCK`. No image was built for or loaded onto the Tang. Six corner bits that the vendor baseline sets and no sweep moved remain unexplained, and whether the primitive needs them to operate is untested. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Model the `LOCK` escape so the lock-and-step signal has an honest pin, by giving the chip database a way to express a dedicated tap onto the row-99 track or by modelling that track as a segment the bel can reach. Measure the TL, TR and BR port tiles properly, closing TR's missing `DLL0` entries, and identify the six default corner bits the vendor baseline sets. Commit a deterministic oracle-sweep script, because the three geometry builds and the eight parameter builds behind these records were driven by hand. Then propose the first lock-and-step image for approval before any Tang access.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_phy_probe/ddr3_phy_probe.sv
- tools/ddr3_openflow_preflight.sh
- tools/run_ddrdll_oracle.sh

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---
## 5 COMMIT Unreleased 2026-10-22T23:58:35-07:00

#### Coming From:

Unreleased ce08f43

#### Purpose:

Find out on hardware whether the open-flow DDRDLL produces a tap code with only the fuses this project packs, using a host-readable path because no scope was available.

#### Outcome:

Built a liveness probe that needs no test equipment. One image carries the DDRDLL at the measured bottom-left site, a 2 Mbaud TinyTang responder and a free-running counter: it keeps the core-ID reply so `fpga` still reports `core 0x56`, and adds a query request `AA 00 03 01` answered with `AA 00 04 03 <step> <cnt_lo> <cnt_hi>` through `fpgapipe`. Three deterministic tools came with it: `tools/build_ddrdll_liveness.sh` for the whole flow, `tools/fs2bin.py` to turn Apicula's ASCII stream into the raw image TinyTang loads (checked byte for byte against the recorded smoke `.bin`, 4,330,782 bytes, no difference at any offset), and `tools/tang_console.py` for `tangput`, `tangload` and the query. `STEP` read `0x00` in every case while the counter advanced between queries, which is what makes the zero a measurement of the primitive rather than of the link: the four `STOP`/`UPDNCNTL` combinations all returned zero, and so did a build with the six vendor-default corner bits packed behind the new `APICULA_DDRDLL_VENDOR_DEFAULTS` switch in Apicula. Gowin's model `IDE/simlib/gw5a/prim_sim.v` predicts 200 for this configuration, so the silicon is not following the model here and the cause is unattributed: either the tap value needs the DDR clock and protocol context the primitive serves, or configuration outside everything the vendor sweeps exposed is required. Three things were established and are recorded: `RESET` is active high, `STEP` loads only while `UPDNCNTL` is low (an earlier build held it high and would have read zero on a healthy block), and `CLKIN` is the port tile's `CLK0` wire, confirmed by the vendor const-input build routing `GB10` to `CLK0` beside the `A6`, `A5` and `LSR0` pips measured directly. The SDC was corrected to name `sys_clk`, which the vendor tool refused before the open flow had tolerated it. The board was left as found: the desktop core is loaded again and answers `core 0x54`, the sweep images were removed from the card, and the canonical probe remains at `/root/cores/console138k/ddrdll_liveness.bin`. No DDR3 package pin was driven or exposed, and no pin was probed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Explain the zero before anything else is built on it. The cheapest decisive experiment is the vendor reference: build the same design with Gowin EDA and load it, which needs the vendor `.fs` reconstructed into the raw stream because its `.bin` carries a 32-byte preamble TinyTang does not skip. If the vendor build reports a tap value, the gap is in this project's packing; if it also reports zero, the model's prediction does not hold on silicon and the probe's expectation must change. After that, model the `LOCK` escape so the lock-and-step signal has an honest pin, measure the TL, TR and BR port tiles, and close TR's missing `DLL0` entries. The four sweep builds were hand-driven and belong in `tools` with the other deterministic scripts.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddrdll_liveness/ddrdll_liveness.cst
- fpga/ddrdll_liveness/ddrdll_liveness.sdc
- fpga/ddrdll_liveness/ddrdll_liveness.sv
- tools/build_ddrdll_liveness.sh
- tools/fs2bin.py
- tools/tang_console.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---
## 6 COMMIT Unreleased 2026-10-23T00:00:48-07:00

#### Coming From:

Unreleased c3570fe

#### Purpose:

Settle whether the zero `STEP` reading is caused by this project's packing by running the identical design through the vendor toolchain.

#### Outcome:

Built the identical liveness source with Gowin EDA 1.9.11.03 and loaded it from `build/vendor_liveness`: 4,330,802 bytes, SHA-256 `3a5ac691002c129e50ecf6aedc3a8b941b051fa8d509ed4db28dadc6f2094b6f`, `tangload` reported `core loaded`, and `fpga` reported `core 86`. Its query replies were `STEP` zero with the counter advancing (`00 00 0b`, `00 cc 78`, `00 4e 22`), which is the same reading the open-flow image gives. That decides the question the open-flow run could not: the zero is not this project's placement, port mapping or packed fuses, because the vendor's own bitstream from the same source behaves identically at 50 MHz. Planning this test also corrected a claim made in the previous entry's Next Steps: Gowin's `.bin` has no preamble to strip, it is exactly the `.fs` data lines packed eight bits to a byte, verified here byte for byte, and the leading `ff` and `de` bytes are part of the bitstream a programmer sends, so both images load raw and no conversion was needed. The record now says that Gowin's behavioural model does not describe the silicon at a 20 ns clock period, and that the physical reading -- a DDR3-800 delay loop built to lock against a 2.5 ns clock having nothing to report at 20 ns -- stays a hypothesis, because the primitive has never been clocked at the rate it is meant to serve. No pin was probed, no DDR3 package pin was driven or exposed, and no vendor output entered the open-flow image. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Clock the primitive at the rate it is built for before drawing anything else from STEP: add a PLL-derived 400 MHz clock to the liveness probe and re-run the same query, which either produces a tap code and explains the zero or removes the clock-period hypothesis. Then model the `LOCK` escape so the lock-and-step signal has an honest pin, measure the TL, TR and BR port tiles, and close TR's missing `DLL0` entries. The sweep driver still lives outside `tools` and should be committed with the other deterministic scripts. Hardware stays deferred until the user asks for the next cycle.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---
