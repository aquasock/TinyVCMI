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
## 7 COMMIT Unreleased 2026-10-23T00:07:07-07:00

#### Coming From:

Unreleased 4772e9d

#### Purpose:

Test whether the DDRDLL reports a tap code when it is clocked at the rate it is designed for instead of the 50 MHz board input.

#### Outcome:

Clocked the primitive at the rate it is built for, as far as this toolchain can reach. The probe now contains an on-die PLL at 50 MHz in, 700 MHz VCO and `CLKOUT0` divided by two, and its reply carries PLL lock plus a counter in the fast domain so a silent primitive cannot be mistaken for a dead clock. 400 MHz was the target, but the router closes the design at 371 MHz -- the path from the primitive's own pins dominates, and shrinking the fast-domain counter to one 16-bit register did not move it -- so the SDC constraint was set to 350 MHz and met at 350.02 MHz rather than shipping an 8 percent miss. Three reads returned `aa 00 04 06 00 01 17 8e 93 e2`, `aa 00 04 06 00 01 75 d4 25 cf` and `aa 00 04 06 00 01 e3 8c 27 da`: `STEP` zero, `lock` one, and both counters advancing. The PLL locks, the 350 MHz domain is alive, and the primitive still reports no tap code, so the clock-period explanation does not hold at seven times the original rate in either toolchain. What survives is only a claim about 400 MHz specifically, which this flow cannot meet timing for and which is not worth chasing before the `LOCK` model, since `STEP` was never the milestone's signal. The reply format grew to six payload bytes and `tools/tang_console.py` now reads ten bytes per attempt. No pin was probed, no DDR3 package pin was driven or exposed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Stop working on `STEP` and build the `LOCK` model, which is what the first hardware diagnostic actually needs: give the chip database a way to express the dedicated tap onto the row-99 track, or model that track as a segment the bel can reach, then expose `LOCK` as a pin and re-run the same host-side readout against it. Measure the TL, TR and BR port tiles and close TR's missing `DLL0` entries while that work is open. The sweep driver still lives outside `tools` and should be committed with the other deterministic scripts. Touching the Tang again needs the user's approval.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddrdll_liveness/ddrdll_liveness.cst
- fpga/ddrdll_liveness/ddrdll_liveness.sdc
- fpga/ddrdll_liveness/ddrdll_liveness.sv
- tools/tang_console.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---
## 8 COMMIT Unreleased 2026-10-23T00:15:48-07:00

#### Coming From:

Unreleased 0e3f911

#### Purpose:

Test the DDRDLL at the clock and control levels the hardware-proven vendor controller actually uses, found by reading Tang-PSX's vendor netlist.

#### Outcome:

Read the hardware-proven vendor controller's netlist in Tang-PSX and tested what it implied. Tang-PSX keeps the vendor DDR3 IP's post-place-and-route netlist at `build/ddr3-vendor/ip/ddr3_memory_interface/ddr3_memory_interface.vo`, and its `DDRDLL` instance uses `DDRDLLM_BL` with exactly the parameters this project packs, `CLKIN` on the 400 MHz memory clock, `STOP` a buffer of the PLL's active-high lock output, `RESET` from the init path, `UPDNCNTL` driven by the init state machine rather than held, and `STEP` feeding `DLLSTEP` on all four `DQS` blocks while also being registered into the 100 MHz domain; the `DQS` blocks have no output back to the DLL. The probe was therefore rebuilt with `STOP` and `UPDNCNTL` high and the PLL at the true memory clock, 50 MHz x16 / 2 = 400 MHz, which met timing at 467 MHz where the earlier build had closed at only 371. Three reads returned `aa 00 04 06 00 01 cd 01 51 0e`, `aa 00 04 06 00 01 2d 9b 51 d9` and `aa 00 04 06 00 01 83 d3 01 9c`: `STEP` zero, `lock` one, both counters advancing. `STEP` has now been read at 50 MHz and 400 MHz, with `STOP` and `UPDNCNTL` in all four static combinations, with the six vendor-default corner bits packed, and under the vendor toolchain, and it has never been anything but zero. That closes the cheap explanations and leaves one structural difference from a working design -- the PHY around the primitive -- with the one-way `DQS` coupling suggesting the primitive is not usable as a standalone island, which would also make `LOCK` unobservable in isolation. That is recorded as a hypothesis with a consequence for the milestone list, not as a measurement. Tang-PSX's own open-flow DDR3 attempt was also checked: its LiteDRAM PHY failed setup timing in every placement variant and never deployed, so the only hardware-proven DDR3 in the project family is the vendor IP. No pin was probed, no DDR3 package pin was driven or exposed, and the board was returned to the desktop core. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Decide the milestone's shape before writing more toolchain: if the primitive needs its PHY around it, an isolated lock-and-step image cannot produce a meaningful result, so milestone 2's hardware step should fold into the first x8 lane and the `LOCK` model should be built as part of that lane rather than on its own. The immediate implementation work is unchanged either way -- `DQS`, `OSER8_MEM` and `IDES8_MEM` placement, plus a way to express the dedicated `LOCK` escape -- and the cheapest next measurement is a vendor-built lane carrying one `DQS` beside the DLL, which is the only configuration that can still separate "the primitive needs DQS present" from "the primitive needs the whole controller". Touching the Tang again needs the user's approval.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---
## 9 COMMIT Unreleased 2026-10-23T00:19:13-07:00

#### Coming From:

Unreleased d65563e

#### Purpose:

Test whether the DDRDLL produces a tap code when a DQS block is present beside it, the last structural difference from a working controller that could be isolated offline.

#### Outcome:

Ran the one remaining structural test: whether the primitive needs a `DQS` block beside it. The vendor toolchain built the same probe, still at 400 MHz with `STOP` and `UPDNCNTL` high, plus one `DQS` carrying the hardware-proven controller's parameters (`DQS_MODE="X4"`, `HWL="true"`, `FIFO_MODE_SEL=0`) with `DLLSTEP` fed from the DLL and the lane's outputs folded into a seventh reply byte so synthesis could not trim the block. Gowin requires `DQSIN` to come from a pad buffer and every DQS-capable pad on this board belongs to the DDR3 array, so the input was left unconstrained and the tool placed it on `K21`, which was checked against Tang-PSX's DDR3 constraint file and is not a DDR3 pin (`K1` and `M6` are, as positive controls), so no DDR3 package pin was exposed or driven. Three reads returned `aa 00 04 07 00 01 81 6a 82 e9 02`, `aa 00 04 07 00 01 03 f3 10 a5 02` and `aa 00 04 07 00 01 1f 69 d4 df 02`: `STEP` zero, `lock` one, both counters advancing and the lane byte steady at `0x02`, so the DQS block was alive and answering. A DQS beside the DLL changes nothing. That leaves the full controller context as the only remaining difference -- the memory clock as the PHY distributes it and the init state machine driving `UPDNCNTL` dynamically, which has not been tried because every static level has. The conclusion is recorded as a hypothesis with its consequence for the milestone shape rather than as a result: an isolated lock-and-step image may not be physically meaningful, and the DLL work should fold into the first x8 lane. The board was returned to the desktop core. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

One measurement is still outstanding and cheap: drive `UPDNCNTL` as a pulse rather than a level, which is how both the proven controller's init machine and the vendored LiteDRAM PHY use it, and read `STEP` afterwards. If that also returns zero, stop testing `STEP` altogether and re-scope milestone 2 to fold the DLL and `LOCK` work into the first x8 lane, since an isolated island cannot be shown to run. Either way the implementation work is unchanged: `DQS`, `OSER8_MEM` and `IDES8_MEM` placement plus a way to express the dedicated `LOCK` escape. Touching the Tang again needs the user's approval.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---
## 10 COMMIT Unreleased 2026-10-23T00:21:37-07:00

#### Coming From:

Unreleased bde6804

#### Purpose:

Test the last stated difference from a working controller, driving UPDNCNTL as a pulse instead of a level, and settle whether STEP can serve the first milestone.

#### Outcome:

Ran the last outstanding test and closed the `STEP` investigation. A build at 400 MHz with `STOP` high and `UPDNCNTL` driven as a pulse -- low for 16 of every 65536 fast cycles, about 40 ns every 164 us, which is how both the hardware-proven controller's init machine and the vendored LiteDRAM PHY use it -- closed timing at 414.94 MHz and returned `aa 00 04 06 00 01 cb 26 4a 36`, `aa 00 04 06 00 01 bc 30 d2 85` and `aa 00 04 06 00 01 ac f0 52 85`: `STEP` zero, `lock` one, both counters advancing. That is the sixth configuration to return zero, after 50 MHz and 400 MHz, `STOP` low and high, `UPDNCNTL` low and high, the six vendor-default corner bits, a `DQS` lane beside the primitive, and the vendor toolchain itself. The conclusion recorded is deliberately narrow: the site, parameters, placement, routing, packing and readout path are all proven by these same images, and what cannot be reached from an isolated island is the PHY around the primitive, which is milestone 3's subject regardless. `STEP` is therefore struck from the first milestone's signal set and the DLL and `LOCK` work folds into the first x8 lane. Nothing was probed on a pin, no DDR3 package pin was exposed or driven, and the board was returned to the desktop core. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Stop measuring and start building the lane: implement `DQS`, `OSER8_MEM` and `IDES8_MEM` placement in the Apicula and nextpnr forks, and add a way to express the dedicated `LOCK` escape -- either a segment model for the row-99 track or a remote-tap extension to the bel pins -- since `LOCK` is the signal the first lane diagnostic will actually use. Include at least one complete x8 lane in the next hardware image so the DLL has the PHY context these six tests showed it needs. Measure the TL, TR and BR port tiles and close TR's missing `DLL0` entries alongside. Touching the Tang again needs the user's approval.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---
## 11 COMMIT Unreleased 2026-10-23T00:24:37-07:00

#### Coming From:

Unreleased 036cbb3

#### Purpose:

Establish what the lane primitives actually need before writing placement support for DQS, OSER8_MEM and IDES8_MEM.

#### Outcome:

Started the placement cycle by establishing what the three lane primitives actually need, instead of writing BELs for them. In the vendor's placed design `DQS`, `OSER8_MEM` and `IDES8_MEM` all sit at IOLOGIC sites, and the GW5AST-138C chipdb does carry a port map for those sites on tile types 229 to 232 and 243, so the failure was worth re-measuring rather than assuming. Against Gowin's own port lists the 54-pin site map covers 17 of `OSER8_MEM`'s 18 pins and is missing `TCLK`, 13 of `IDES8_MEM`'s 16 and is missing `ICLK`, `WADDR` and `RADDR`, and only 3 of `DQS`'s 24 -- `DQSIN` plus every control and status pin including `DLLSTEP`, `RLOADN`, `RMOVE`, `HOLD` and the `RPOINT`/`WPOINT`/`RVALID` group. That redefines the boundary: it is not a missing BEL type but unnamed wires at the site, and building BELs from the 54-pin map would place and route while inventing 21 `DQS` connections, the same defect as guessing at configuration bits. No BEL was written and no chipdb was changed, because the honest next step is measurement: one primitive constrained to one site in a vendor build, diffed against a control bitstream, the way the DDRDLL's site and features were recovered. The milestone list was also re-scoped in the same commit, which closes the loose end left by entry 10: `STEP` is struck as a first-milestone signal, the `DDRDLL` and `LOCK` work lands with the lane, and measuring the memory-mode site wires becomes the entry point to milestone 3, which is the first milestone where a hardware result would mean anything. No Tang access occurred in this cycle. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Measure the missing site wires, cheapest first. `OSER8_MEM` needs only `TCLK`, so a vendor oracle constrained to one IOLOGIC site and diffed against a control build settles it in one pair of bitstreams. `IDES8_MEM` needs `ICLK`, `WADDR` and `RADDR`; `DQS` needs 21 names and is the most valuable, since `DQSIN` and `DLLSTEP` are what a lane test uses. Only after those names exist should BELs be written, and then the lane RTL follows as the second half of the split cycle. Touching the Tang again needs the user's approval.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---
## 12 COMMIT Unreleased 2026-10-23T00:27:56-07:00

#### Coming From:

Unreleased a2fd135

#### Purpose:

Measure the missing IOLOGIC site wires for the lane primitives, beginning with OSER8_MEM's TCLK.

#### Outcome:

Started measuring the missing site wires and found that the measurement plan was based on a wrong model. A first vendor oracle pair in `build/meas_oser` -- a control design and one carrying a single `OSER8_MEM` -- was stopped by Gowin with `CK2060`, "the connection between instance 'tclk_ibuf' and instance 'oser' is incorrect", because `OSER8_MEM`'s `TCLK_SOURCE` parameter is `"DQSW"` or `"DQSW270"` and the tool will not accept a pin there. Reading the hardware-proven netlist explains it: every one of the 40 serializers takes `TCLK` from its own lane's `DQS` output, `dqsw0` for nine per lane and `dqsw270` for the tenth, 40 of 40 across four lanes, and each lane carries one `DQS`, ten `OSER8_MEM` and eight `IDES8_MEM`, which is exactly where the inventory's 4, 40 and 32 counts come from. `TCLK`, `DLLSTEP` and the `DQSW` group are therefore not fabric wires to be named but dedicated intra-lane connections, so the unit of implementation is the lane complex rather than three independent BELs, in the same way the `DDRDLL`'s `LOCK` output needs a dedicated path. Nothing was written into the chipdb or the forks, the control build was not needed once the parameter check settled the question, and no Tang access or deployment occurred. The next increment is to model a lane site with its internal connections, which is a design decision rather than another measurement. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Model one lane site before writing any lane RTL: decide how the chip database expresses internal connections between a `DQS` block and the ten `OSER8_MEM` and eight `IDES8_MEM` beside it -- the same problem as the `DDRDLL` `LOCK` escape, so one mechanism may cover both -- and confirm the lane's tile span against the vendor placement. That decision, plus the still-missing `DQS` pin names that remain genuine fabric wires, is the rest of the placement cycle. Touching the Tang again needs the user's approval, and it must be asked for before any deployment.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---
## 13 COMMIT Unreleased 2026-10-23T00:36:54-07:00

#### Coming From:

Unreleased d51b3e6

#### Purpose:

Attempt the DQS pin measurement and establish whether the primitive can be isolated at all.

#### Outcome:

Took the DQS measurement one step further and found the constraint that ends the approach. A control design built cleanly, and the DQS variant was refused by Gowin with `PR0015`, "DLLSTEP pin of 'u'(INS_DQS) is not driven by DDRDLL". The vendor tool enforces the dedicated `DDRDLL` -> `DQS.DLLSTEP` link the same way it already enforces `TCLK_SOURCE` on the serializers, so a lone `DQS` cannot be built at all and there is no isolated primitive whose pins could be named. Together with entry 12's finding that every `OSER8_MEM` takes `TCLK` from its own lane's `DQS`, this makes the conclusion firm from both directions: the lane-internal connections are dedicated paths the tool itself refuses to let a design invent, which is why they are absent from the fabric wire model and why three independent BELs could never work. Both findings are recorded in `docs/ddr3-open-flow.md` and in TOOL-006, which now carries both vendor refusals as evidence. No chipdb or fork changes, no Tang access, and no deployment: the board is still running the desktop core. The remaining work in this cycle is a design decision rather than a measurement -- how the chip database expresses internal bel-to-bel paths -- and the measurement path for naming the DQS fabric pins is closed because the primitive cannot be isolated. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Design the internal-path mechanism, since measuring the primitives in isolation is now known to be impossible: the chip database needs a way to state that one bel's pin feeds another bel's pin inside a site, covering `DDRDLL` -> `DQS.DLLSTEP`, `DQS` -> `OSER8_MEM.TCLK` and the `DDRDLL` `LOCK` escape to the row-99 track, and the packer must skip fuses for those paths the way it already does for fuse-less elements. The fabric pins that remain genuinely external -- `DQSIN`, `RLOADN`, `RMOVE`, `RCLKSEL`, `READ`, `HOLD` and the status outputs -- are still unnamed and can only be recovered from a full lane build in the vendor tool, which is the next measurement after the mechanism exists. No deployment until the user asks.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---
## 14 COMMIT Unreleased 2026-10-23T00:42:09-07:00

#### Coming From:

Unreleased da60061

#### Purpose:

Implement the chip-database mechanism that expresses hard-wired bel-to-bel links, the prerequisite for modelling a lane complex.

#### Outcome:

Implemented the internal-path mechanism in the nextpnr Gowin generator. `create_internal_net()` creates a tile wire with no pips and attaches only the bel pins named at creation, so the router can neither enter nor leave the connection and the packer has no fuse to emit for it; that models exactly the links the vendor tool refuses to let a design route. `himbaechel/uarch/gowin/tests/check_internal_net.py` gates the two invariants, that the wire carries the bel pins and that no pip may touch it, and that a duplicate definition raises rather than attaching more pins to the first wire; both checks pass. The generator was rebuilt against the fork's Apicula database, the chipdb and `nextpnr-himbaechel` came out clean, and `tools/ddr3_openflow_preflight.sh` still reports the same boundary -- `DDRDLL`, `IODELAY` and `CLKDIV` pass, `DQS`, `OSER8_MEM` and `IDES8_MEM` remain gaps -- so the change is a silent no-op on today's designs, which is what a mechanism with no consumer should be. There is deliberately no consumer yet: the lane bel set that would use it needs the `DQS` fabric pins, and entries 12 and 13 established that the primitive cannot be isolated, so those pins can only come from a full vendor lane build. The mechanism also does not cover the `DDRDLL` `LOCK` escape, whose endpoint is nine tiles away and needs a cross-tile path rather than a single-site one. The generator and test changes are committed in the nextpnr fork on `epic/gw5ast138c` and not pushed, per the standing instruction that only `aquasock/TinyVCMI` is pushed. No Tang access of any kind: the board is being used by another agent and is off limits until the user says otherwise. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Get the `DQS` fabric pins, which is the one input the lane bel set needs and the only thing this mechanism is waiting on. Isolation cannot produce them, so the route is a complete vendor lane: one `DDRDLL`, one `DQS` and its serializers built together in Gowin EDA exactly as the proven controller does it, then read the pins off the placed netlist and the bitstream. That needs no board access at all -- it is a local build plus the existing netlist-reading method -- which matters while another agent owns the Tang. After that the lane bel set and the cross-tile form of the `LOCK` path are the remaining implementation work.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---
## 15 COMMIT Unreleased 2026-10-23T00:52:31-07:00

#### Coming From:

Unreleased cdad486

#### Purpose:

Run the lane bitstream diff and recover the DQS fabric pin names.

#### Outcome:

Ran the lane diff and established what it can and cannot deliver. A complete vendor lane -- `DDRDLL` feeding `DQS.DLLSTEP` and `DQS.DQSW0` feeding an `OSER8_MEM.TCLK` -- builds, the first time all three primitives have been placed together in this project, and the tool put `DQSIN` on `Y3`, which this board's DDR3 constraints name as `ddr_dqs[0]`. That confirms a real lane binds DDR3 pads and explains why the preflight probes cannot place these primitives at all: they are forbidden the only pins the blocks exist at. The planned diff, lane against control, produced 424 changed bits over 43 tiles, and it is mostly noise for two reasons that are worth writing down rather than working around. The pair has to be matched, because a control with different ports and different IO placement moves hundreds of IO bits on its own -- the pad's own tile, `(68,0)`, moved just five. And more fundamentally a diff only shows what the router routed, while this design ties the `DQS` inputs to constants, and a constant is selected by the site's configuration rather than becoming a pip, so the 21 missing names would not all appear even with a perfect pair. The method that can work is the one that produced the `DDRDLL` feature table: vary one port at a time between `VCC` and `GND` in matched builds and read the site's configuration bits. That is a build pair per port and belongs in its own cycle rather than being started in passing. No repository code changed, no Tang access occurred, and the five probe files remain removed from the card. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Write the per-port probe generator before running it: a small deterministic script that emits matched vendor build pairs varying one `DQS` input between `VCC` and `GND`, runs Gowin on each, and reports which site configuration bits move, then repeat for the status outputs by driving them to pins. That turns 21 unknown names into a table the same way features 12 to 15 were recovered, and it needs no board access. Once the table exists the lane bel set lands on `create_internal_net()` and the remaining implementation is the cross-tile form of the `DDRDLL` `LOCK` path. Touching the Tang needs the user's explicit approval.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---
## 16 COMMIT Unreleased 2026-10-23T00:59:38-07:00

#### Coming From:

Unreleased 22fa420

#### Purpose:

Build and run the deterministic per-port probe that recovers the DQS site's configuration bits one port at a time.

#### Outcome:

Wrote and ran the per-port probe that the lane diff said was needed, `tools/dqs_port_probe.py`, and it now does what it claims. The tool builds a matched pair per `DQS` control input differing only in that port's constant, `VCC` against `GND`, with pins fixed so placement cannot drift, and it needs no board. Its first run produced byte-identical bitstreams for both constants, which was a bug in the tool rather than a result: the template substituted every control port before the target, so both builds tied the same port low. With the substitution order fixed the pairs differ and the diffs are small and local. `HOLD` moves 8 bits and `RESET` moves 74, 66 of them in one tile, and both point at **tile `(81,5)`, tile type 241** -- the `DQS` site. Type 241 carries no modelled bels in the chipdb, which is the other half of why `nextpnr` cannot place a `DQS`: there is no site to hold it. Two pairs were run to establish the method; the remaining control ports have not been probed yet. No repository code other than the new tool changed, no Tang access occurred, and the five probe files remain removed from the card. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Run the remaining six control pairs (`RLOADN`, `RMOVE`, `RDIR`, `WLOADN`, `WMOVE`, `WDIR`) and the three buses a bit at a time, then map each port's moved bits onto the wire names in tile type 241 using the chipdb's `alonenode` tables. That produces the port-to-wire table the lane bel set needs, entirely offline. After it, the remaining work is the lane bel set on `create_internal_net()` and the cross-tile form of the `DDRDLL` `LOCK` path. Touching the Tang needs the user's explicit approval.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/dqs_port_probe.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---
## 17 COMMIT Unreleased 2026-10-23T01:08:37-07:00

#### Coming From:

Unreleased 42cffa2

#### Purpose:

Probe every single-bit DQS control input and read what each one's constant selection changes at the site.

#### Outcome:

Ran the remaining control pairs and read their bit sets. All eight single-bit `DQS` inputs now have a matched `VCC`/`GND` pair: `RESET`, `HOLD`, `RLOADN`, `RMOVE`, `RDIR`, `WLOADN`, `WMOVE` and `WDIR`. Seven move exactly eight bits inside tile `(81,5)`; `RESET` moves 66 there plus a handful in two neighbouring tiles, which fits a reset that also gates nearby logic. The union across ports is 102 bits, and the site's `alonenode` table accounts for them: 24 entries claim those bits and the pattern is a constant-select multiplexer, for example wire `CE2` with sources `LB31, VCC, W212, X06` and bit `(3,73)`, which `WMOVE` and `WDIR` both move. That is the mechanism that was missing: a control input's constant level is chosen by a mux whose select bits are these eight, so the mux's destination wire names the port. A caution was found and recorded rather than smoothed over: `RLOADN` and `RDIR` share four bits and `WLOADN` and `WDIR` share all eight, which could be shared select lines or a common reset path, so the table has to be built mux entry by mux entry instead of by grouping ports. The three buses and the `DQS` status outputs were not probed. No repository code changed, no Tang access occurred, and the probe images remain off the card. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Turn the bit sets into a table: for each port, intersected against the site's `alonenode` entries, take the entry whose source list contains `VCC` or `GND` and whose bits equal that port's eight, and record its destination wire as the port's wire name. Handle the three shared-bit pairs entry by entry, and note where two ports cannot be separated. Then probe the buses bit by bit and the status outputs by driving them to pins, and the resulting table is what the lane bel set needs. Touching the Tang needs the user's explicit approval.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---
## 18 COMMIT Unreleased 2026-10-23T01:17:09-07:00

#### Coming From:

Unreleased 654773e

#### Purpose:

Turn the measured per-port bit sets into a port-to-wire table and see what the chipdb can supply.

#### Outcome:

Tried to turn the measured bit sets into a port-to-wire table through the chipdb and found that the table cannot come from there. Type 241, the `DQS` site, carries only one short-value table named `unknown_17` -- no `longfuses`, no `longval` and no `const` bits -- so the 102 measured bits have no existing table to name them against. The `alonenode` entries do not explain them either: none of the eight ports' bit sets matches an entry exactly, and none of the overlapping entries even lists `VCC` or `GND` among its sources, which also retires the earlier reading of `CE2` as a constant-select mux -- that was an intersection, not a match. The result is a clean split rather than a dead end. The per-port configuration bits are measured and are sufficient on their own for a packer, in the same shape as the `DDRDLL`'s `DLL0` features, and they need no wire names. Only the routed pins -- `DQSIN`, `PCLK`, `FCLK`, `DLLSTEP` and the status outputs -- need wire names, and those must come from the routing side rather than the constant side. So the lane bel set is buildable in two layers and only one of them is still missing data. No repository code changed beyond the documentation, no Tang access occurred, and the probe images remain off the card. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Extend the probe to the routed side, which is the only missing layer. The constants are done; what remains is naming `DQSIN`, `PCLK`, `FCLK`, `DLLSTEP` and the status outputs, and the way to do that is a matched pair where the one routed pin of interest moves while everything else is held, so the diff shows that pin's pips in the site's tile rather than the placement noise the earlier lane diff produced. Then write the lane bel set: routed pins in the site type 241 bel, configuration bits from the measured table, internal nets for `DLLSTEP` and `TCLK` through `create_internal_net()`. Touching the Tang needs the user's explicit approval.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 19 COMMIT Unreleased 2026-10-23T02:32:52-07:00

#### Coming From:

Unreleased ddbce92

#### Purpose:

Name the `DQS` site's routed pins by measuring matched pairs with the vendor tool instead of inferring them from the bitstream shape.

#### Outcome:

Extended `tools/dqs_port_probe.py` with a routed mode and added `tools/fs_site_diff.py` to decode a pair, then measured the site's pins on tile `(81,5)`. The decoder was validated against a landmark before its answers were trusted: on the `DDRDLL` port tile `(108,1)` it returns `A6`, `A5`, `LSR0` and `CLK0` with the documented `Q7 -> E820` lock escape, which are the pins established independently in the DDRDLL work. Ten pins are now measured: `RDIR`, `RLOADN`, `RMOVE` and `READ[0]` on `A0` to `A3`; `WDIR`, `WLOADN`, `WMOVE` and `HOLD` on `B0` to `B3`; `RCLKSEL[0]` on `C0`; and `FCLK` on `CLK0`. Two earlier readings were retired by the same runs. The vendor DDR3 build's absolute decode, which had suggested 84 programmed pips in the tile, is not evidence: the `pips` table's per-source fuse sets are mux select fields, so several sources of one destination read as satisfied at once and only a difference between two builds names anything. And the shape-based guess that `A0` to `A7` was `DLLSTEP[7:0]` is wrong, since `READ[0]` measured on `A3`. `DQSIN` cannot be probed at all, because the vendor tool refuses both a fabric source and a second DQS buffer on it (`PR0014`, `CK3001`), so its wire must come from the pad side or become an internal net like `DLLSTEP`. `PCLK` and `RESET` remain unresolved: tying either to a constant makes the tool demote the block and the pair then differs across the whole tile, 93 and 72 changed fuses against 6 to 10 for every live pair, and a second pair holding both members live with two fabric registers changed only upstream wire choices and left every destination fixed. Twenty-three pairs are built in `build/dqs_routed/` and twelve decoded; the rest are built but unread. Separately, the SD card's `root/cores/` directory was found empty and `desktop.bin` was restored to `/run/media/vash/TINYTANG/root/cores/console138k/` from `TINYTANG_SD` with digest `b9af4f06221e`, the user taking the remaining core files. No hardware was deployed, the FPGA was not reprogrammed, and no probe image is on the card. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Decode the eleven pairs that are built but unread -- `READ[1]` to `READ[3]`, `RCLKSEL[1]`, `RCLKSEL[2]` and `WSTEP[0]` to `WSTEP[5]` -- and finish building `WSTEP[6]` and `WSTEP[7]`, which brings every probeable input bit to a measurement. Then settle `PCLK` and `RESET`, whose constant and swapped pairs both fail to name them, by decoding the vendor `.dat`'s `Dqs` block, which `apycula/dat_parser.py` leaves commented out in `read_something5A` along with the per-side `LeftIO`, `RightIO`, `TopIO` and `BottomIO` tables and the twenty-two `DqsRLoc` and `DqsCLoc` entries. With the portmap closed, write the type 241 bel from the measured wires, the constant-selection bits already recorded, and internal nets for `DLLSTEP` and `DQSIN`. Touching the Tang needs the user's explicit approval.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/dqs_port_probe.py
- tools/fs_site_diff.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 20 COMMIT Unreleased 2026-10-23T15:33:00-07:00

#### Coming From:

Unreleased 1451206

#### Purpose:

Complete the offline DQS port measurements needed for an accurate multi-tile architecture model and preserve the stopped cycle as an agent handoff.

#### Outcome:

Completed the remaining matched vendor probes without accessing the Tang. The input map is now closed: `RDIR`, `RLOADN`, `RMOVE`, and `READ[0:3]` use `A0`, `A1`, `A2`, `A3`, `A4`, `A5`, and `A7`; `WDIR`, `WLOADN`, `WMOVE`, and `HOLD` use `B0` through `B3`; `RCLKSEL[0:2]` use `C0` through `C2`; and `WSTEP[0:7]` use `D3`, `D4`, `D5`, `D7`, `CLK2`, `LSR2`, `CE1`, and `CE2`. A new live-clock probe and cross-tile comparison established `PCLK -> CLK0` and `RESET -> LSR0` in tile `(81,5)`, while `FCLK -> CLK2` is in tile `(81,0)`; this retires entry 19's `FCLK -> CLK0` reading as global-clock allocation noise and proves that `DQS` is a multi-tile macro rather than one type-241 bel. The vendor `.dat` `Dqs` arrays are empty on this device and cannot supply the missing names. `tools/dqs_output_probe.py` built thirteen fixed-placement matched pairs and exposed every status output: `DQSR90 -> E202` through `W800` at `(69,7)`, `DQSW0 -> F1` through `EW10` at `(81,5)`, `DQSW270 -> W814` through `N210` at `(81,1)`, `RBURST -> F6` through `N830`, `RFLAG -> Q6` through `W830`, `RVALID -> W834` through `N250`, `WFLAG -> Q7` through `EW10`, `RPOINT[0:2] -> F2/Q2/F4` through `W810/W810/EW10`, and `WPOINT[0:2] -> F3/Q3/F5` through `N800/N800/N830`; full mux fuse-state equality, rather than the ambiguous satisfied-source subset, selected each source. The final unresolved input is the dedicated differential path: board pin `Y3` is `IOL69A`, its ordinary input-output wire is `F6` in tile `(68,0)`, and the proven vendor netlist connects `ELVDS_IOBUF.O` directly to `DQS.DQSIN`, but the correct fuse-free cross-tile representation has not been implemented. NumPy support was added to `tools/fs_site_diff.py`, the three Python tools compile, and a NumPy-backed `RVALID` decode reproduces `W834 -> N250`. The user stopped the cycle before the DQS architecture bel or deterministic full-output regression decoder was implemented. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

First add a deterministic decoder that checks all thirteen output pairs by exact destination-mux fuse state, then settle how nextpnr should represent the fuse-free `ELVDS_IOBUF.O -> DQS.DQSIN` connection across tiles `(68,0)` and `(81,5)`. Only after that port map is complete should the DQS multi-tile macro be implemented, with configuration and `FCLK` at `(81,0)`, control pins at `(81,5)`, and output taps at `(81,1)`, `(81,5)`, and `(69,7)`; update `docs/ddr3-open-flow.md` and the relevant core-reference records in that implementation cycle. Continue offline and do not touch the Tang unless the user explicitly changes that instruction.

#### Files Modified:

- tools/dqs_output_probe.py
- tools/dqs_port_probe.py
- tools/fs_site_diff.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 21 COMMIT Unreleased 2026-10-23T16:35:35-07:00

#### Coming From:

Unreleased 124c25c

#### Purpose:

Check the recorded DQS port map against its matched vendor pairs with a deterministic tool and bring the documentation and reference library into agreement with the checked result.

#### Outcome:

Added `tools/dqs_map_check.py`, which re-derives every DQS site wire from the pairs in `build/dqs_routed`, `build/dqs_clock` and `build/dqs_outputs` by exact mux state and fails on any disagreement; it passed with all 24 probeable input bits and all 13 outputs agreeing, at 1.43 GB peak memory over about six minutes. The check corrected entry 20 in two places. Every mux's all-zero state is itself the selection of one source, so a route leaving the site through an unprogrammed destination changes no fuse in the site tile: `DQSR90`, `DQSW270` and `RVALID` leave tile `(81,5)` on `Q0`, `Q1` and `Q5` through `N800`, `W810` and `W830` in that state, and the `(69,7)` and `(81,1)` taps entry 20 recorded are downstream hops shared with measured siblings, so all thirteen outputs are in `(81,5)` and those three wires are route inferences rather than fuse measurements. `FCLK -> CLK2` at `(81,0)` was also withdrawn, because the same fabric source selects `CLK1` there in the earlier probe template and `CLK2` in the later one, and neither when `FCLK` is on the board clock, so `FCLK` enters through `(81,0)` on a pin that is still unnamed. `PCLK -> CLK0` and `RESET -> LSR0` in `(81,5)` were confirmed. `docs/ddr3-open-flow.md` now carries the checked map and the zero-state caveat, and core-reference gained TOOL-007 with a revision note on TOOL-002. The first run of the checker cached every decoded bitstream at about 0.5 GB each and exhausted memory, taking the PC down; the tool now holds one pair at a time and was re-run under a 5 GB `ulimit -v` cap. At the user's instruction the nextpnr and Apicula `epic/gw5ast138c` branches were fast-forwarded on the `aquasock` remotes only, `8be8657b..15d96a16` and `8918f14..1d43011`, which supersedes entry 14's reading that only TinyVCMI is pushed; the `origin` remotes, which point at `mathieufro`, were not touched. No vendor build ran and no hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Name `FCLK` before writing the bel: rebuild the routed and clock `FCLK` pairs under the current probe template so both come from one design, and decode tile `(81,0)` by exact mux state to settle whether the pin is `CLK1`, `CLK2` or a clock-network tap. Then design the fuse-free cross-tile connection, extending `create_internal_net()` to cover `ELVDS_IOBUF.O -> DQS.DQSIN` from `(68,0)` and the `DDRDLL` `LOCK` escape, and propose the DQS bel on tile `(81,5)` for approval before implementing it. Continue offline and do not touch the Tang unless the user explicitly changes that instruction.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/dqs_map_check.py

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 22 COMMIT Unreleased 2026-10-23T16:52:54-07:00

#### Coming From:

Unreleased 35fcfcc

#### Purpose:

Name the DQS `FCLK` connection that entry 21 left unresolved by rebuilding its matched pairs from one probe template and decoding the clock side.

#### Outcome:

Rebuilt the routed and clock `FCLK` pairs with `tools/dqs_port_probe.py` into `build/fclk_rebuild/`; the four Gowin EDA 1.9.11.03 builds passed, and the rebuilt clock pair is fuse-for-fuse identical to the earlier one while two members built from identical source differ only in header bytes, so the vendor tool is deterministic and entry 21's `CLK1` versus `CLK2` disagreement came from the template change. `FCLK` turned out to have no fabric pin. Tile `(81,0)` is the left side's HCLK fabric-entry tile, its `CLK1`, `CLK2` and `LSR2` are the lane entries `L2HCLK21` to `L2HCLK23`, and decoding it through the device-level `hclk_pips` table accounts for every changed fuse as one lane's `BETA`, `BUF` and `ALPHA` chain, lane 2 for a register source and lane 3 for the board clock. No `FCLK` fuse changes in `(81,5)`; the lane is selected in longfuses table 58 of tile `(72,0)`, keys 38 and 41 for lane 2 and 39 and 42 for lane 3, a table the chipdb carries at 24 cells, one per byte group. The keys read as two two-bit fields holding the lane number, which predicts lane 1 and makes lane 0 indistinguishable from an unclocked block; lanes 0 and 1 are unmeasured. This also means the `DQS` lane selector is separate from IOLOGIC `FCLKSEL`, which on this device reaches lanes 0 and 2 only, while the vendor placed the `DQS` on lane 3. `tools/dqs_map_check.py` now asserts the lane chain, the absence of an `FCLK` pin in `(81,5)` and the table-58 fuses for both rebuilt pairs in place of the earlier open-question observations, and passed in full at 1.43 GB peak memory under a 5 GB `ulimit -v` cap. `docs/ddr3-open-flow.md` and TOOL-007 record the result. No hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Bring the Cycle B design to the user for approval before writing toolchain code: the `DQS` bel on tile `(81,5)` from the measured wires and constant-selection bits, `FCLK` as HCLK-lane pips carrying table-58 select fuses at the byte group's config tile in the way IOLOGIC `FCLK` already has HCLK pips, and a fuse-free cross-tile extension of `create_internal_net()` covering `ELVDS_IOBUF.O -> DQS.DQSIN` from `(68,0)`, `DDRDLL.STEP -> DQS.DLLSTEP` and the `DDRDLL` `LOCK` escape. Measuring lanes 0 and 1 of table 58 belongs in that cycle if the design offers them to the router. Continue offline and do not touch the Tang unless the user explicitly changes that instruction.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/dqs_map_check.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 23 COMMIT Unreleased 2026-10-23T17:08:35-07:00

#### Coming From:

Unreleased dd1f162

#### Purpose:

Measure every DQS configuration fuse and the FCLK lanes that remained unmeasured, so the open packer has nothing left to guess before the DQS bel is implemented.

#### Outcome:

Added `tools/fs_attribute.py`, which accounts for every fuse that differs between two builds as tile routing, global clock, HCLK, a named `shortval`, `longval` or `longfuses` entry, or unattributed, and validated it on the `FCLK` clock pair, where it attributed all 367 changed fuses. Added `tools/dqs_param_probe.py`, which built fifteen Gowin EDA 1.9.11.03 designs in `build/dqs_b1`: a base with the proven controller's `DQS` parameters, nine single-parameter variants, a design without the `DQS`, and four designs pinning `FCLK` to HCLK lanes 0 to 3. Lane pinning needed a change of approach: `CLKDIV2` and `DHCE` refuse `INS_LOC LEFTSIDE[n]` with `CT2001`, so each lane design pins a `CLKDIV` on the clock net that also drives `FCLK` and feeds `PCLK` from its output, which is the shape of a DDR3 PHY. Every difference from the base attributed with no unattributed fuse, and every change outside routing fell in longfuses table 58 of `(72,0)`: eight presence fuses, two for `FIFO_MODE_SEL`, one per `RD_PNTR` bit, three that encode the five `DQS_MODE` values, one for `HWL`, and the lane field, where lane 1 is keys 37 and 40 and lane 0 sets nothing, confirming the reading in entry 22. The same attribution showed that tile `(81,5)` holds no `DQS` configuration and that the per-port constant bits recorded in entry 18 are input-mux routing, so that reading is withdrawn. `tools/dqs_param_probe.py --check` asserts the whole encoding, the lane chains and the absence of unattributed fuses on all fifteen builds and passed at 1.43 GB peak memory. Separately, the chipdb confirmed that the planned dedicated paths have single drivers: `F6` at `(68,0)` is driven only by `IOBA.O`, `Q0` to `Q7` at `(108,1)` carry no bel pin besides the fork's `DDRDLL`, and the `LOCK` tap `Q7` at `(99,1)` has no bel driver. The encoding is in `docs/ddr3-open-flow.md` and the new TOOL-008, with TOOL-007 revised. Two limits are recorded rather than closed: the presence fuses were tested with one set of connected ports only, and the encoding is measured at one of the 24 byte groups. No hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Propose B2 for approval and then implement it offline: in the nextpnr fork, the dedicated-tap mechanism that joins pip-less wires across tiles into one node with a single fuse-free entry pip where the source already drives a fabric wire, covering `DQSIN` from `F6` at `(68,0)`, `DLLSTEP[0:7]` from `Q0` to `Q7` at `(108,1)` and the `DDRDLL` `LOCK` escape onto `Q7` at `(99,1)`, plus one `DQS` bel at `(81,5)` from TOOL-007 and `FCLK` pips from the four HCLK lanes of block 2; in the Apicula fork, `DQS` packing from TOOL-008 and no fuses for the tap pips. Acceptance is the preflight moving `DQS` from GAP to PASS and the open-flow probe matching the vendor build fuse for fuse in table 58 at `(72,0)`. Continue offline and do not touch the Tang unless the user explicitly changes that instruction.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/dqs_map_check.py
- tools/dqs_param_probe.py
- tools/fs_attribute.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 24 COMMIT Unreleased 2026-10-23T17:21:14-07:00

#### Coming From:

Unreleased 36ce294

#### Purpose:

Make the measured DQS and its hard-wired links placeable and routable in the open flow, which is B2a of the approved DQS implementation.

#### Outcome:

Committed `0bc790a6` to the nextpnr fork's `epic/gw5ast138c` and pushed it to the `aquasock` remote only. The chip-database generator now creates one `DQS` bel at `X5Y81` with the 24 input and 13 output wires of TOOL-007, gives that cell a tile type of its own because its chipdb type occurs eight times, adds `FCLK` pips from the four block-2 HCLK lane wires with each lane node extended to the site, and gives the `DDRDLL` a `LOCK` pin. The approved design changed in one respect, recorded here rather than silently: `DQSIN`, `DLLSTEP[0:7]` and `LOCK` are modelled as fuse-free nodes that join the source's own wire, `F6` at `(68,0)`, `Q0` to `Q7` at `(108,1)` and `Q7` at `(99,1)`, to a pin-only wire, instead of through tap pips, because joining the existing wire needs no pip, leaves the packer nothing to skip, and changes only the `DQS` cell's tile type; the generator refuses a link onto a wire that already belongs to a node. The new `tests/check_dqs_site.py` passes all five checks, `check_internal_net.py` and `check_arch_gen_deterministic.py` pass, and `check_constids_append_only.py` fails identically with and without this change because the earlier `DDRDLL` commit inserted a constid mid-file. Generation takes about 18 s at 2.0 GB and adds exactly one tile shape; the rebuilt chipdb is installed beside the binary, which needed no rebuild, and the previous chipdb is kept in the session scratchpad. The proposed acceptance test was corrected: the preflight's `DQS` probe was the isolated shape the vendor refuses, so it is now the smallest accepted lane, a `DDRDLL` on `DLLSTEP` and `DQSIN` on pin Y3 through its own constraint file, and the `DDRDLL` probe now routes `LOCK`. `tools/ddr3_openflow_preflight.sh` reports `DDRDLL`, `DQS`, `IODELAY` and `CLKDIV` PASS and `OSER8_MEM` and `IDES8_MEM` GAP; the routed probe puts the `DQS` on `X5Y81/DQS` with the pad on `X0Y68/IOBA` and `FCLK` on lane 0, and `LOCK` leaves through `X1Y99/E820 <- Q7`, the pip the vendor bitstream sets for `LOCK`. The B1 `base` lane design also places and routes. No `DQS` is packed yet and no open-flow image containing one exists. No hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Implement B2b in the Apicula fork: accept `DQS` in the packer's bel pattern, refuse a `DQS` at any site other than `X5Y81`, write the table-58 presence, parameter and lane fuses by key at `(72,0)` with the lane taken from the routed `HCLK2<n> -> DQS_FCLK` pip, and treat that pip as fuse-free routing. Accept it only when the open-flow build of `build/dqs_b1/base` matches the vendor build fuse for fuse in table 58 and `tools/fs_attribute.py` shows no configuration difference and no unattributed fuse in `(81,5)`, `(72,0)`, `(81,0)` and `(68,0)`. Continue offline and do not touch the Tang unless the user explicitly changes that instruction.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_phy_probe/ddr3_phy_probe.sv
- fpga/ddr3_phy_probe/ddr3_phy_probe_dqs.cst
- tools/ddr3_openflow_preflight.sh

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 25 COMMIT Unreleased 2026-10-23T17:31:21-07:00

#### Coming From:

Unreleased aeb9b11

#### Purpose:

Pack the measured DQS configuration in the open flow and accept it against the vendor's fuses, which is B2b of the approved DQS implementation.

#### Outcome:

Committed `c85ed79` to the Apicula fork's `epic/gw5ast138c` and pushed it to the `aquasock` remote only. `get_DQS_fuses` writes the TOOL-008 encoding into longfuses table 58 of `X0Y72` and nowhere else, takes the lane from nextpnr's fuse-free `HCLK2<n> -> DQS_FCLK` pip, which the GW5AST-138C device now keeps out of the chipdb pip lookup, and refuses another site, an unmeasured parameter value and a connected `FCLK` with no lane pip; both refusals were exercised. The approved acceptance test could not run as written. `gowin_pack` refuses any design that configures a bank 6/7 pad outside a declared DDR context, a deliberate guard against pull and drive configurations on the DDR3 rail with no switch to set it, and a lane's `DQSIN` must be on pin Y3 in bank 6, so no image containing a real `DQS` can be written. The guard was left untouched, because changing it is the user's decision. Acceptance moved to `tools/dqs_pack_check.py`, which runs the packer's own routing stage and only the `DQS` bel's fuse method in-process and writes no image. All twelve B1 designs were built in the open flow and pass: the packer's table-58 fuses equal the recorded encoding in every case and equal the vendor build outside the lane field, exactly where the lanes agree. The open router put `FCLK` on lane 0 every time, carrying the clock on two lanes where a pinned `CLKDIV` held another, so lanes 1 to 3 were checked with `--fclk-lane`, which rewrites only that pip, against the lane-matched vendor builds and match; that tests the packer's encoding, not the router. No image containing a `DQS` exists and no hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Obtain the user's decision on the DDR3-bank guard before any open-flow lane image is written: either a declared DDR context for designs that legitimately own bank 6 and 7, with the DDR3 IO standard and rail checked, or a different first image that keeps every DQS pad unconfigured. Independently and offline, the lane needs `OSER8_MEM` and `IDES8_MEM` bels, whose missing `TCLK` path from the `DQS` outputs belongs on the same fuse-free link mechanism, and the open router should be taught to keep one clock net on one HCLK lane as the vendor does. Do not touch the Tang unless the user explicitly changes that instruction.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/dqs_pack_check.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 26 COMMIT Unreleased 2026-10-23T17:50:25-07:00

#### Coming From:

Unreleased 3aac7e8

#### Purpose:

Measure how the lane's `OSER8_MEM` and `IDES8_MEM` are wired and configured before any open-flow model is written for them.

#### Outcome:

Added `tools/dq_lane_probe.py`, which builds the B1 `base` lane plus one memory-mode serializer on lane 0's `dq[0]` pad Y4, wired as the hardware-proven vendor netlist wires lane 0, and ran twenty-one Gowin EDA 1.9.11.03 builds into `build/dq_lane` and `build/dq_lane_b`. Lane 0 sits on IOLOGIC A and B of the left-edge cells at rows 68 to 79, beside the `DQS` site and its byte group, from Tang-PSX's proven pin map. Driving `ICLK`, `WADDR`, `RADDR` or `TCLK` from a fabric register instead of its `DQS` output was refused all four times with `CK2060` while the proven wiring built, so all four are hard-wired links like `DLLSTEP`, and TOOL-006 was revised to say so. Both serializers' differences from `base` attribute with no unattributed fuse, and their configuration is named IOLOGIC attributes the packer already uses: `IDES8_MEM` writes `INMODE=MIDDRX4`, `FIFO=ENABLE` and `CLKIMUX=ENABLE`, and `OSER8_MEM` writes `OUTMODE=MODDRX4`, `CLKOMUX=ENABLE` and `WRFCLKSEL` from `TCLK_SOURCE`, with `TXCLK_POL` and `HWL` each isolated by a build. Side A writes in the pad's cell and side B in the cell below, the offset the packer already applies. Pinning a `CLKDIV` to each HCLK lane showed that the vendor clocks IOLOGIC from all four lanes with distinct `FCLKSEL` fields per primitive, while the Apicula fork's IOLOGIC model offers lanes 0 and 2 only; that is recorded as a limit of the model, not of the silicon, and it does not block a lane because the open router already puts the `DQS` on lane 0. `tools/dq_lane_probe.py --check` asserts the refusals, every design's decoded attribute set, the lane chains and the absence of unattributed fuses, and passed on all twenty-one builds. Only `dq[0]` and `dm[0]` were built; the other lane positions come from the proven pin map. The results are in `docs/ddr3-open-flow.md` and the new TOOL-009. No hardware was accessed and the packer's DDR3-bank guard is unchanged. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Propose the C2 implementation for approval: in the nextpnr fork, `TCLK`, `ICLK`, `WADDR` and `RADDR` pins on the eleven lane-0 IOLOGIC positions, joined to the `DQS` outputs by fuse-free links, and packing of `OSER8_MEM` and `IDES8_MEM` alongside `OSER8` and `IDES8`; in the Apicula fork, the measured attribute sets through the existing IOLOGIC path, accepted when the in-process packer output matches the vendor fuses on both sides and on lanes 0 and 2. Do not touch the Tang unless the user explicitly changes that instruction.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/dq_lane_probe.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 27 COMMIT Unreleased 2026-10-23T18:08:43-07:00

#### Coming From:

Unreleased d85885b

#### Purpose:

Make lane 0's `OSER8_MEM` and `IDES8_MEM` placeable and routable in the open flow, which is C2a of the approved serializer implementation.

#### Outcome:

Committed `bc3a07b9` to the nextpnr fork's `epic/gw5ast138c` and pushed it to the `aquasock` remote only; it is the first C++ change of this work, and the binary and chipdb were rebuilt with the previous binary kept in the session scratchpad. The ten lane-0 IOLOGIC positions carry `ICLK`, `WADDR[0:2]`, `RADDR[0:2]`, `TCLK_DQSW0` and `TCLK_DQSW270` on pin-only wires joined to their `DQS` outputs by fuse-free links, and the six lane cells are marked so these pins reach none of the 36 other cells of their type. The proposal said eleven positions; the strobe complement on AA3 carries no serializer, so it is ten. `TCLK` became one pin per source, chosen by renaming the port from `TCLK_SOURCE` in the cell packer, which refuses any other value. The packer takes both primitives like `OSER8` and `IDES8`, with `OUTMODE=MODDRX4` and `INMODE=MIDDRX4` and without the aux cell, after a further sixteen vendor builds measured the bit order: `OSER8_MEM.D<i>` uses IOLOGIC `D<i>` and `IDES8_MEM.Q<i>` uses IOLOGIC `Q<8+i>`, as `OSER8` and `IDES8` do. The C1 vendor designs place and route in the open flow on both sides of `(77,0)`, with the memory-mode pins on the `DQS` nets bit for bit and `FCLK` on lane 0 for the `DQS` and the serializer. The fabric-sourced shapes Gowin refuses fail routing at the link's `DQS` output wire, and an invalid `TCLK_SOURCE` fails in the packer. The preflight's serializer probes are now lane-0 designs with their own constraint files, and the preflight reports all six primitives PASS. `tests/check_dqs_site.py` gained a lane-0 check and passes all six, `check_internal_net.py` and `check_arch_gen_deterministic.py` pass, and `check_constids_append_only.py` shows only its earlier failure, the new constids being appended. No serializer is packed yet and no hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Implement C2b in the Apicula fork: `get_OSER8_MEM_fuses` and `get_IDES8_MEM_fuses` through the existing IOLOGIC attribute path, writing the TOOL-009 attribute sets and refusing any position outside the ten, and accept them with an in-process check like `tools/dqs_pack_check.py` that requires the IOLOGIC fuses to equal the vendor's `ides_lane0` and `oser_lane0` builds on both sides. Do not touch the Tang unless the user explicitly changes that instruction.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_phy_probe/ddr3_phy_probe.sv
- fpga/ddr3_phy_probe/ddr3_phy_probe_ides8_mem.cst
- fpga/ddr3_phy_probe/ddr3_phy_probe_oser8_mem.cst
- tools/ddr3_openflow_preflight.sh
- tools/dq_lane_probe.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 28 COMMIT Unreleased 2026-10-23T18:17:04-07:00

#### Coming From:

Unreleased b9f18bf

#### Purpose:

Pack lane 0's `OSER8_MEM` and `IDES8_MEM` in the open flow and accept them against the vendor's fuses, which is C2b of the approved serializer implementation.

#### Outcome:

Committed `9de5557` to the Apicula fork's `epic/gw5ast138c` and pushed it to the `aquasock` remote only. `get_OSER8_MEM_fuses` and `get_IDES8_MEM_fuses` write the TOOL-009 attributes through the existing IOLOGIC path and refuse any position outside the ten lane-0 sites, which was exercised. The new `tools/dq_pack_check.py` runs the packer in-process, writes no image, and compares the serializer side's IOLOGIC table fuses with the vendor build of the same source. Two corrections came out of that comparison. Both reset multiplexers have to be emitted at `0`, because leaving them out sets each table's absence entry, one fuse apiece the vendor leaves clear. And the input's lane selection had to be written from the measurement, `FCLKSEL5=HCLK0` and `FCLKSEL3=HCLK0` on lane 0 and nothing on lane 2, because the GW5A input handler emits nothing for `MIDDRX4` and its `FCLKSEL7=HCLK0_` has no row on this die. With those, the packer's fuses equal the vendor's on both sides on lane 0. They equal the vendor's on lane 2 when `--fclk-lane` rewrites the serializer's `FCLK` pip and its `IOLOGIC_FCLK` attribute, which is what the packer actually reads. For the `TCLK_SOURCE`, `TXCLK_POL` and `HWL` variants, whose vendor builds rode lane 3, they are equal outside the lane field. A lane-1 rewrite stops at routing because the chipdb has no `FCLKA <- HCLK21` pip. No image containing a serializer exists and the DDR3-bank guard is unchanged. No hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

The lane-0 primitives are now modelled and packed offline: the `DDRDLL`, the `DQS`, and one each of `OSER8_MEM` and `IDES8_MEM` on either side. What remains before a full lane is bidirectional DQ, with an `OSER8_MEM` and an `IDES8_MEM` on one pad through an IOBUF and `Q1` on its tristate, and the strobe pad's differential output, both of which need their own vendor measurements first. After that comes the user's decision on the DDR3-bank guard, which still blocks every lane image, and then the other three lanes. Do not touch the Tang unless the user explicitly changes that instruction.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/dq_pack_check.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 29 COMMIT Unreleased 2026-10-23T18:34:36-07:00

#### Coming From:

Unreleased 7faf17a

#### Purpose:

Measure lane 0's complete pad shapes, the bidirectional DQ, the differential strobe and DM, and bring the open flow into agreement with them.

#### Outcome:

Added `tools/dq_pad_probe.py`, which builds the proven controller's pad shapes on top of the B1 `base`. The DQ pad is an `IOBUF` driven by an `OSER8_MEM` and feeding an `IDES8_MEM` through a static `IODELAY`, the strobe is an `ELVDS_IOBUF` on Y3 and AA3 feeding `DQSIN`, and DM is a `TBUF`. Six Gowin EDA 1.9.11.03 designs built in `build/dq_pad`. Three first attempts were refused for my own constraints, not as findings: `DRIVE` on an input port (`CT1108`) and `LVCMOS33D` on an `ELVDS_IOBUF` (`CT1109`). The bidirectional pad's IOLOGIC fuses are exactly the union of its two serializers plus three for the `IODELAY`, among them the unnamed attribute 133 at value 118. Gowin builds the pad without the `IODELAY` as well. The strobe and DM add only the plain `OSER8_MEM` set, and the IO standard changes no IOLOGIC fuse, only the pads' IOB entries and bank 6's `BANK` table in `(90,0)`. `--check` asserts all of it with no unattributed fuse and passed. The six shapes already place and route in the open flow: the `IODELAY` folds into the `IDES8_MEM` and the strobe becomes a differential IOB pair. `tools/dq_pack_check.py` now compares per IOLOGIC side and found one gap, the attribute 133=118. The Apicula fork's `237b246`, pushed to `aquasock` only, adds it by its `logicinfo` index because `attrids` cannot name it, and with it the packer's IOLOGIC fuses equal the vendor's outside the lane field for every pad. The lane-0 single-serializer checks were rerun and still match exactly. Only side A was built with an `IODELAY`. The SSTL IOB and `BANK` fuses have not been compared against the open packer, because that is the configuration the DDR3-bank guard exists to refuse. The results are in `docs/ddr3-open-flow.md` and the new TOOL-010. No hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Lane 0 is now modelled at IOLOGIC level for every primitive and pad the proven controller uses there. The next step that changes anything is the user's decision on the DDR3-bank guard: comparing the packer's SSTL15 and SSTL15D IOB fuses and bank 6's `BANK` table with the vendor's is the work that decision would open, and it is the last gap before an open-flow lane image. Independently and offline, the router could be taught to keep one clock net on one HCLK lane as the vendor does, and lanes 1 to 3 could be measured the same way lane 0 was. Do not touch the Tang unless the user explicitly changes that instruction.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/dq_pack_check.py
- tools/dq_pad_probe.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 30 COMMIT Unreleased 2026-10-23T18:44:05-07:00

#### Coming From:

Unreleased 59da608

#### Purpose:

Make the open router keep a DDR3 lane's clock on one HCLK lane, as the vendor does, so the divided `PCLK` and the `FCLK` sinks stay in phase.

#### Outcome:

Committed `40869abe` to the nextpnr fork's `epic/gw5ast138c` and pushed it to the `aquasock` remote only. The cause was that the global router routes each sink of a clock net independently from the source, so the `FCLK` sinks took lane 0, the first equal-length lane, while a `CLKDIV` pinned to another lane held that one, and the block was entered twice. For nets that feed a `DQS` `FCLK`, and only those, `route_direct_net` now routes the `CLKDIV` sinks first and lets each later sink's backward search end at an `HCLK_MUX_ALPHA` lane wire the net already owns. With the `CLKDIV` pinned to each lane, the `DQS` now follows it on lanes 0 to 3 and a serializer joins it on lane 2. The packer checks then match the lane-matched vendor builds with real routing and no rewrite: `tools/dqs_pack_check.py` on lanes 1, 2 and 3, and `tools/dq_pack_check.py` for `OSER8_MEM` and `IDES8_MEM` on lane 2. A `CLKDIV` on lane 1 or 3 still splits a net that also feeds an IOLOGIC `FCLK`, because the database offers IOLOGIC lanes 0 and 2 only, and the router now warns when that happens; the warning was confirmed to fire on that case and not on lane 2. Every other net follows the same code path as before. The preflight passes all six primitives, `check_dqs_site.py`, `check_arch_gen_deterministic.py`, `check_hclk_to_fclk_138c.py` and `check_postroute_refusal.py` pass, and `check_hclk_6block.py` fails only the constid-ordering check it failed before this change. The binary and chipdb were rebuilt, the latter because a `DQS` constid was appended. Nothing was tested against the other cores that use this fork, beyond the argument that their nets do not feed a `DQS`. No hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Continue offline with lanes 1 to 3: measure each lane's `DQS` site, byte-group cell and IOLOGIC positions the way lane 0 was measured, starting by locating their sites and table-58 cells from the proven pin map, and extend the model only where the measurements support it. The DDR3-bank guard decision remains the user's and still blocks any lane image. Do not touch the Tang unless the user explicitly changes that instruction.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 31 COMMIT Unreleased 2026-10-23T18:48:58-07:00

#### Coming From:

Unreleased 8ca0efa

#### Purpose:

Locate the `DQS` site and byte-group cell of DDR3 lanes 1 to 3 cheaply, before any per-port measurement of them.

#### Outcome:

Mapped the proven pin map onto the die: all four lanes are on the left edge, on IO rows 55 to 106. Added `tools/dq_lane_locate.py`, which builds the B1 `base` lane and its no-DQS control with the strobe pad moved to each of lanes 1 to 3, and attributes the difference. All six Gowin EDA 1.9.11.03 builds succeeded and every difference attributed with no unattributed fuse. In each lane the only configuration the `DQS` adds is table 58 of one cell inside that lane's rows, which identifies the byte groups as `(99,0)`, `(90,0)` and `(63,0)` for lanes 1, 2 and 3. Each is of a different type from lane 0's. The sites differ more than expected. Lane 3's is `(81,6)`, the twin of lane 0's type-241 `(81,5)`, but lanes 1 and 2 have their sites in their own byte-group cells on the IO column, `(90,0)` being the bank-6 cell. In every lane the `DQS` moves exactly lane 0's 24 input destinations at its site, and every site tile has all 24 as pip destinations. That supports one port map but is not a per-port measurement, and the outputs, the table-58 coordinates in the three new cell types and the lanes' IOLOGIC are unmeasured. The results are in `docs/ddr3-open-flow.md` and the new TOOL-011. No hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Propose the lane 1 to 3 measurement and model plan for approval. Per lane it covers the input port map by matched pairs and the outputs by the zero-state route method, using `tools/dq_lane_probe.py`-style designs. It also covers the table-58 encoding in each byte group's cell type by the B1 parameter and lane sweep, and the IOLOGIC positions of each lane's pads. Only after those pass checks of the lane-0 kind should the nextpnr and Apicula models be extended from one lane to four. Do not touch the Tang unless the user explicitly changes that instruction.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/dq_lane_locate.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 32 COMMIT Unreleased 2026-10-23T19:43:37-07:00

#### Coming From:

Unreleased b685d40

#### Purpose:

Run lane 0's full DQS measurement set on DDR3 lanes 1 to 3 and hand the results off, stopped by the user for an agent handoff before the IOLOGIC measurements or any model change.

#### Outcome:

Gave the lane-0 tools a `--lane N` option. `tools/dqs_port_probe.py` now holds the lane table of TOOL-011 (`LANES`, `lane_cst`, `lane_dir`), and `tools/dqs_output_probe.py`, `tools/dqs_param_probe.py` and `tools/dq_lane_probe.py` use it, building into `_l<N>` directories with lane 0's unchanged. `tools/dq_lane_probe.py --check` now derives a pad's IOLOGIC cell from the chipdb pinout, and `tools/dqs_map_check.py --lane N` checks a lane against lane 0's map, inferring the zero-state outputs from shared downstream hops instead of recorded ones. All 156 Gowin EDA 1.9.11.03 builds for lanes 1 to 3 succeeded under `build/dqs_{routed,clock,outputs,b1}_l{1,2,3}`: 22 input pairs, 2 clock pairs, 13 output pairs and the 15 B1 designs per lane, three lanes in parallel at about 1.8 GB each. The results are preliminary and are not yet in core-reference. Inputs match lane 0's 24-wire map in lanes 1 and 3; lane 2 matches 23, and `RESET` moved nothing at its site `(90,0)`. Outputs match lane 0's wires for 11 of 13 in lane 1 and 10 of 13 in lane 3; the rest are the zero-state outputs, which the inference left ambiguous because their next hop is shared with several siblings. In lane 2, six outputs move two or three destinations at the bank-6 site, so the one-destination decode cannot read them there. Table 58 sets the same number of fuses as lane 0 in every one of the 15 designs in all three lanes, but at other coordinates. Those coordinates are identical across the byte-group types 257, 259 and 270 and differ only from lane 0's type 64, so the check, which compares lane 0's coordinates, fails 14 of 15 in each lane. The IOLOGIC designs for lanes 1 to 3 were not built, and no nextpnr or Apicula change was made. No hardware was accessed and the DDR3-bank guard is unchanged. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Make `tools/dqs_param_probe.py --check` compare table 58 by key rather than by lane 0's coordinates, and confirm that lanes 1 to 3 light the same keys as lane 0, which would give one encoding with a second coordinate layout for types 257, 259 and 270. Investigate lane 2's `RESET` with a clock-mode pair read at cells around `(90,0)`, and decode lane 2's multi-destination outputs and every lane's ambiguous zero-state outputs by exact first-hop selection, as lane 0's were. Then build each lane's IOLOGIC designs with `tools/dq_lane_probe.py --lane N` on an A and a B pad from TOOL-011's pin map, record TOOL-012 for lanes 1 to 3, and only then propose extending the nextpnr sites, links and lane-0 IOLOGIC list and the Apicula site and position refusals from one lane to four. The DDR3-bank guard decision remains the user's. Do not touch the Tang unless the user explicitly changes that instruction.

#### Files Modified:

- tools/dq_lane_probe.py
- tools/dqs_map_check.py
- tools/dqs_output_probe.py
- tools/dqs_param_probe.py
- tools/dqs_port_probe.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 33 COMMIT Unreleased 2026-10-23T20:48:44-07:00

#### Coming From:

Unreleased 2eef22f

#### Purpose:

Close the offline DQS and IOLOGIC measurements for DDR3 lanes 1 to 3 without changing the open-flow models or accessing hardware.

#### Outcome:

Closed every preliminary result from entry 32. `tools/dqs_param_probe.py --check --lane N` now compares table 58 by semantic key and reconstructs each target tile's exact fuse state; all 45 lane-1-to-3 parameter designs pass with the expected HCLK chain and zero unattributed fuses. `tools/dqs_map_check.py --lane N` traces each output backward from the fixed probe pad through the configured route, proving that all three lanes share lane 0's 24-input and 13-output source-wire map without the earlier zero-state inference; lane 2's previously silent `RESET` pair converges at the exact programmed endpoint `LSR0 <- W212`. Gowin EDA 1.9.11.03 then built 99 A-side serializer outcomes on representative pads `AA8`, `R4` and `W2`: 87 accepted designs match lane 0's attributes, HCLK selection and bit order with no unattributed fuse, and the twelve deliberately invalid fabric-driven memory-pin designs are all refused with `CK2060`; six further B-side builds on `AB8`, `T4` and `Y2` confirm the same attributes and one-cell offset. `tools/dq_lane_probe.py` now defaults each lane to its measured A-side pad and output directory, and its lane-argument shadowing bug is fixed. The reference library adds TOOL-012 and the DDR3 document records the completed four-lane evidence. No nextpnr or Apicula model changed, the DDR3-bank guard is unchanged, no image was written, and no hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated all 33 active entries' six-section ordering, prose, Status values, sequential numbering and active-log capacity.

#### Next Steps:

Propose the four-lane implementation cycle: extend the nextpnr DQS sites, dedicated links and IOLOGIC position lists and the Apicula DQS and serializer site handling from lane 0 to lanes 1 through 3, then accept the change only when all four lane probes place and route and their in-process packer results match the vendor by table key and IOLOGIC fuse state. Keep the DDR3-bank guard, SSTL15 and SSTL15D IOB and BANK comparison, image generation and all Tang access outside that cycle until the user makes the guard decision.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/dq_lane_probe.py
- tools/dqs_map_check.py
- tools/dqs_param_probe.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 34 COMMIT Unreleased 2026-10-23T21:49:09-07:00

#### Coming From:

Unreleased cdc8b2d

#### Purpose:

Make the DQS and memory serializers of DDR3 lanes 1 to 3 placeable and routable in the open flow, which is D2a of the approved four-lane implementation.

#### Outcome:

Committed `ccac5bfb` to the nextpnr fork's `epic/gw5ast138c` and pushed it to the `aquasock` remote only. The generator's lane-0 constants became one table, `DQS_LANES`, holding each lane's site, strobe pad, `DQSIN` source and ten IOLOGIC positions from the proven pin map: sites `X5Y81`, `X0Y99`, `X0Y90` and `X6Y81`, with `DQSIN` from `F6` of pads Y3, V9, W6 and R3. Before any model change the chipdb was checked for the risk named in the plan, and it did not occur: all 37 `DQS` wires are pip destinations or sources in every site cell and none is a bel pin there, lane 1's cell has no bels and lane 2's only `BANK6`, no site lies on a `dq` or `dm` row, every new `DQSIN` source carries only `IOBA.O` and IOLOGIC `D`, and HCLK block 2's lanes 0 and 2 already reach every lane's IOLOGIC rows. Every site cell is marked with its pad so the two type-241 sites and lane 1's type-257 cell keep tile types of their own, each `STEP` bit is one node reaching all four `DLLSTEP` pins, each lane's outputs reach only its own positions, and every site joins the block-2 lane nodes. The plan gained one piece that was not in it: with four bels the placer could put a `DQS` on a site whose `DQSIN` node starts at another lane's pad, so a new `pack_dqs` step locks each `DQS` to the site whose `DQSIN` shares a node with the pin of the placed IOB driving it, and refuses any non-pad source as Gowin does; `DQSIN` was appended as a constid and the binary and chipdb were rebuilt, with the previous pair kept in the session scratchpad. `tests/check_dqs_site.py` now covers all four lanes and passes seven checks, the other generator and router tests pass, and `check_constids_append_only.py` and `check_hclk_6block.py` fail only their earlier constid-ordering checks, reproduced without this change. The preflight still reports all six primitives PASS. The new `tools/lane_open_build.py` reruns every vendor lane design through Yosys and nextpnr from its own sources and asserts refusal of the `fab_*` and `bad_*` designs, the `DQS` on its lane's site, each serializer beside a placed pad on that pad's side, and every memory-mode pin on its `DQS` output's net bit for bit; all 210 designs behaved as expected, the `DQS` followed its pinned `CLKDIV` on lanes 1 to 3 in every lane, and IOLOGIC `FCLK` pinned to lane 1 or 3 kept the known split warning. `tools/openflow_env.sh` now exports the flow paths the tool reads. The lane-0 packer checks were rerun on the new netlists and still match the vendor, the two board-clock serializer designs outside the lane field. Apicula is unchanged, so lanes 1 to 3 are placed and routed but not packed. No image was written and no hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Implement D2b in the Apicula fork: have `get_DQS_fuses` map each of the four sites to its byte-group cell and write table 58 by semantic key resolved through each cell type's own longfuses table, keeping lane 0's output bit-identical, and widen the serializer position set to all four lanes. Add `--lane N` to `tools/dqs_pack_check.py` and `tools/dq_pack_check.py`, and accept the change only when every lane's netlist in `build/open` packs equal to the vendor by table-58 key and IOLOGIC fuse state on both sides. The DDR3-bank guard, SSTL15 and SSTL15D IOB and BANK comparison, image generation and all Tang access stay outside that cycle until the user decides the guard.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/lane_open_build.py
- tools/openflow_env.sh

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 35 COMMIT Unreleased 2026-10-23T22:16:39-07:00

#### Coming From:

Unreleased b2cad29

#### Purpose:

Pack the DQS and memory serializers of all four DDR3 lanes in the open flow and accept them against the vendor's fuses, which is D2b of the approved four-lane implementation.

#### Outcome:

Committed `c54d6ba` to the Apicula fork's `epic/gw5ast138c` and pushed it to the `aquasock` remote only. `get_DQS_fuses` now maps the four sites to their byte-group cells `X0Y72`, `X0Y99`, `X0Y90` and `X0Y63` and holds the TOOL-008 encoding as table-58 keys resolved through each cell's own table, because the four cell types put the same 26 keys at two different coordinate layouts; all 26 exist in every type, a missing key is refused, and lane 0's fuses are unchanged. The `OSER8_MEM` and `IDES8_MEM` position check covers the forty positions of all four lanes. On the TinyVCMI side the key translation moved into `at_byte_group` in `tools/dqs_param_probe.py`, whose `--check` still passes 15 of 15 on lanes 0 and 2 at 1.43 GB peak; `tools/dqs_pack_check.py` gained `--lane N` using the same helper, and a lane-1 design checked against lane 0's byte group fails as it should; `tools/dq_pack_check.py` needed no change because it reads the serializer's cell from its bel. `tools/lane_open_build.py --pack` runs both checks on every routed design against its own vendor bitstream, and across the four lanes 188 checks passed. All 56 `DQS` designs equal the recorded encoding by key, lane field included, and equal the vendor exactly on the 16 lane-pinned designs and outside the lane field on the rest, where the vendor put the board clock on lane 3 and the open router on lane 0. The 18 serializer designs clocked on HCLK lane 0 or 2 match exactly, and the other 114 match outside the lane field. The first full run reported one failure, a crash on `dq_pad`'s `dqs_lvcmos`, which has no vendor bitstream because Gowin refused it with `CT1109`; the tool now skips a design without one and the `dq_pad` rerun passed. The run took about 14 minutes with no more than two vendor bitstreams held at once. Apicula's `tests/test_io_iologic_138c.py` fails only `test_io2hclk_places_the_vendor_oser4_cell_in_block_one`, which asserts four IOLOGIC lanes from the unchanged chipdb that offers two. No image was written, the DDR3-bank guard is unchanged, and no hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

All four lanes are now placed, routed and packed in-process to the vendor's fuses, so the next change that matters is the user's decision on the DDR3-bank guard: either a declared DDR context for designs that legitimately own banks 6 and 7, with the SSTL15 and SSTL15D IOB entries and bank 6 and 7 `BANK` tables then compared against the vendor, or a different first image. Independently and offline, the IOLOGIC `FCLK` model still reaches HCLK lanes 0 and 2 only, and the six unexplained `DDRDLL` corner bits and the other three `DDRDLL` masters remain unmeasured. Do not touch the Tang unless the user explicitly changes that instruction.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/dqs_pack_check.py
- tools/dqs_param_probe.py
- tools/lane_open_build.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 36 COMMIT Unreleased 2026-10-23T22:29:08-07:00

#### Coming From:

Unreleased 9075a40

#### Purpose:

Compare the open packer's DDR3-bank IOB and BANK fuses with the vendor's without writing any image, which is stage 1 of the approved declared-DDR-context plan.

#### Outcome:

Added `tools/ddr_bank_check.py`, which runs `gowin_pack`'s own stages on an open-flow routed netlist with `ddr_context` set on that one in-memory device and never creates the bitstream object, then compares the `IOBA` or `IOBB` table of all 100 bank 6 and 7 pads, used or not, and both `BANK` tables, each restricted to its own fuses, against the vendor build of the same source. Bank 6 holds the 44 data-lane balls with its `BANK` table at `(90,0)` and bank 7 the 28 address, command and clock balls with its table at `(18,0)`. The first run showed that the packer could not handle SSTL on this die at all: the inherited alias folds `SSTL15` and `SSTL15D` into family codes that have no `logicinfo` entry here and loses the 1.5 V the VCCIO check needs, so packing stopped with `KeyError: 'SSTL'`. Committed `b6ca047` to the Apicula fork's `epic/gw5ast138c` and pushed it to the `aquasock` remote only; it keeps those two names whole on the 138C, and the DDR3-bank refusal is unchanged. With it, the four lane-0 SSTL designs in `build/dq_pad` compare unequal. The SSTL15 input strobe on Y3 and bank 7's `BANK` table match. The DQ IOBUF lacks `TRI_MUX=TMDDR` and `SLEWRATE=FAST`, the DM TBUF two fuses, and the SSTL15D strobe pair four fuses on each side. Every unused pad lacks two fuses the vendor sets. Unused bank-6 pads beside a single-ended SSTL15 pad carry two input-side fuses the vendor leaves clear. Bank 6's `BANK` table lacks three SSTL15 fuses and has one SSTL15D fuse different. The unused-pad difference also appears on 99 of 100 pads of ordinary banks 2 and 3, so it is the packer's unused-pad treatment for every core on this die, and the user approved correcting it only for banks 6 and 7 inside a declared DDR context. Apicula's IO and bank tests pass apart from `test_io2hclk_places_the_vendor_oser4_cell_in_block_one`, the known two-lane chipdb limit, and `test_oracle_smoke_cst_defaults_asserted`, which needs a `GOWINHOME` and fails identically without the change. The results are in `docs/ddr3-open-flow.md` and the new TOOL-013. No image was written and no hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Run the approved stage 1b, still writing no image. Build Gowin EDA SSTL designs for bank 7's address, command and differential clock shapes and for one data pad per lane on lanes 1 to 3. Then correct the used-pad IOB entries, bank 6's `BANK` table and the bank 6 and 7 unused-pad configuration in the Apicula fork, applying the DDR-bank corrections only under `ddr_context` so every other bank and core is unchanged, and accept them only when `tools/ddr_bank_check.py` passes all 102 tables on every SSTL design. Stage 2's narrow declared context, any written image and all Tang access each need separate user approval.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/ddr_bank_check.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 37 COMMIT Unreleased 2026-10-23T22:53:28-07:00

#### Coming From:

Unreleased acd9a08

#### Purpose:

Extend the DDR3-bank comparison to every lane and to bank 7, and find out why the vendor's unused-pin drive setting contradicts the Apicula fork's recorded rule, which is the diagnostic part of the approved stage 1b and the user-chosen option (a).

#### Outcome:

`tools/dq_pad_probe.py --lane N` and the new `tools/cmd_pad_probe.py` built lanes 1 to 3's four SSTL pad designs and bank 7's address, command, clock and reset shapes from the proven vendor netlist with Gowin EDA 1.9.11.03, `tools/lane_open_build.py` gained them as sets, and `tools/ddr_bank_check.py --summary` reports one line per distinct difference. Lanes 1 to 3 reproduce lane 0's signatures exactly. Bank 7 exposed two further gaps that change the stage-1b work. The open flow's plain `OSER8` takes both IOLOGIC halves of a cell, so `cmd_full_sstl`, all 28 balls, cannot be placed, while `cmd_min_sstl`, with its two address balls on unpaired cells, routes. And `BankDesc.add_io_bel` tests `bel.is_mipi` without calling it, so the N half of any differential output with no `IO_TYPE` sets the bank's LVDS VCCIO to 2.5 V; that stops `cmd_min_sstl` with a conflict and programs bank 6 for 2.5 V under the SSTL15D strobe, the `(20,44)` against `(20,43)` difference. The line is on upstream `master`, and the desktop core's TMDS N halves take the same path. The unused-pin difference is `DRIVE=8` and `DRIVE_LEVEL=8`, which the fork's 138C class deliberately drops on the strength of its `P3.T26`/`D108` corpus. The new `tools/unused_pin_probe.py` built one plain non-DDR design with this project's and the fork harness's `run.tcl`, option set and `.cst` conventions in all four combinations. Packed in memory and compared fuse for fuse, the GW5A base set with drive equals the vendor on 199 of 199 unused left- and right-edge pins in every build and the fork's rule on none, so the build recipe is ruled out. The fork's corpus is on another host and its harness defaults to the macOS install, so the platform and the corpus itself remain untested. The user chose option (b): follow these measurements for banks 6 and 7 inside a declared DDR context only. The results are in `docs/ddr3-open-flow.md` and a TOOL-013 revision. No packer change was made in this cycle, no image was written and no hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Implement the stage-1b corrections in the Apicula fork, each applied only to banks 6 and 7 under `ddr_context` so every other bank and core is unchanged: unused pins with the vendor's `DRIVE=8` and `DRIVE_LEVEL=8` and without the bank's SSTL15 `IO_TYPE` the vendor does not give them, a differential pair's N half taking its P half's `IO_TYPE` instead of the always-true `is_mipi` default, the used-pad `TRI_MUX=TMDDR` and `SLEWRATE=FAST`, the SSTL15D pair's missing fuses, and bank 6's SSTL15 `BANK` fuses. Accept them only when `tools/ddr_bank_check.py` passes all 102 tables on every lane design and on `cmd_min_sstl`. The `OSER8` IOLOGIC pairing in nextpnr is needed before the full bank 7 can be compared and belongs in its own measured change. Stage 2's narrow declared context, any written image and all Tang access each need separate user approval.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/cmd_pad_probe.py
- tools/ddr_bank_check.py
- tools/dq_pad_probe.py
- tools/lane_open_build.py
- tools/unused_pin_probe.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 38 COMMIT Unreleased 2026-10-23T23:32:30-07:00

#### Coming From:

Unreleased bce6123

#### Purpose:

Make the open packer write the vendor's DDR3-bank IO configuration on banks 6 and 7 under a declared DDR context, which is the corrective part of the approved stage 1b with the user's option (b) for unused pins.

#### Outcome:

Committed `7a82e4a` to the Apicula fork's `epic/gw5ast138c` and `7a77226c` to the nextpnr fork's, both pushed to the `aquasock` remotes only. Every Apicula change applies only to banks 6 and 7 with `ddr_context` set: unused pins get `DRIVE=8` and `DRIVE_LEVEL=8` under the unused default standard instead of the bank's SSTL15, through a new `get_unused_io_type` hook; a differential N half takes its P half's `IO_TYPE` and `IOLOGIC_IOB`, which corrects the 2.5 V VCCIO the uncalled `is_mipi` gave it; outputs are `SLEWRATE=FAST`, serializer-tristated pads `TRI_MUX=TMDDR`, the SSTL15D clock drops the desktop TMDS `DRIVE_LEVEL` and `PADDI`, and the strobe is `IOB_UNKNOWN51=TRIMUX` with the design's `PULLMODE`; and a bank with a single-ended SSTL15 input is `VREF=INTERNAL` while one with only SSTL15D pairs is `IO_TYPE=SSTL15D`. Each rule was found by measurement, not assumed: the `VREF` trigger was settled by a new `lane_sstl` design in `tools/dq_pad_probe.py`, the real lane's strobe pair, DQ and DM pads together, which showed a DQ `IOBUF` alone turns the reference on. That design could not be placed on lane 0, where `dq[0]` and `dm[0]` share cell 77, because nextpnr's `check_iologic_placement` made `OSER8_MEM` and `IDES8_MEM` claim their cell's other IOB; the nextpnr change exempts the two lane serializers, after which `lane_sstl` places on all four lanes and `tools/dq_pack_check.py` finds its IOLOGIC fuses equal to the vendor's on both sides of the shared cell, while plain `OSER8` keeps the check and `cmd_full_sstl` stays unplaced. `tools/ddr_bank_check.py` now finds all 102 bank 6/7 tables equal to the vendor on all 21 SSTL designs that place, five per lane on four lanes plus `cmd_min_sstl`. With `ddr_context` off, seven non-DDR netlists pack to fuse digests identical to the committed `b6ca047` packer's and the guard still refuses a bank-6 design; the full Apicula suite fails the same 58 tests before and after, all predating it; `tools/lane_open_build.py` behaves as expected on 227 of 228 designs, the exception being `cmd_full_sstl`, and its `--pack` passes 22 of 22 pad checks; the preflight passes all six primitives and `check_dqs_site.py` all seven checks. The nextpnr binary was rebuilt with the previous one kept in the session scratchpad. No image was written and no hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Two comparisons remain before stage 2 can be proposed. Make plain `OSER8` occupy only its own IOLOGIC side where the vendor does, measured first by vendor builds of a cell with `OSER8` on one side and on both, so the full 28-ball bank 7 places and `cmd_full_sstl` can be compared; then build and compare one whole-controller pad set, all four lanes and bank 7 in one design. After those pass, propose stage 2's narrow declared DDR context for user approval. Writing any image and all Tang access each need separate approval, and the unused-pin contradiction with the fork's `D108` corpus stays open until that corpus or the macOS install can be compared.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/dq_pad_probe.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 39 COMMIT Unreleased 2026-10-24T00:28:39-07:00

#### Coming From:

Unreleased 58cabdb

#### Purpose:

Make plain `OSER8` occupy only the IOLOGIC side the vendor uses so the full bank 7 can be compared, and compare the whole DDR3 controller's pad set against the vendor, the two comparisons entry 38 left before stage 2.

#### Outcome:

Committed `9ee733c6` to the nextpnr fork's `epic/gw5ast138c` and pushed it to the `aquasock` remote only; the Apicula fork is unchanged. `tools/cmd_pad_probe.py` gained three single-cell designs on bank-7 cell IOL35 (M1/L1), and Gowin EDA 1.9.11.03 configures a plain `OSER8` on its own IOLOGIC side only, six fuses there and none on the other side, with the two-sided design exactly the union. The open flow's aux `IOLOGIC_DUMMY` wrote nothing there and its own side already matched outside the HCLK lane field, so the nextpnr change gives a plain `OSER8` on the GW5AST-138C neither an aux cell nor the other side's IOB, leaving other devices and every existing bitstream unchanged. All five bank-7 designs now place, `cmd_full_sstl` with all 28 balls included, and `tools/dq_pack_check.py`, now covering plain `OSER8`, and `tools/ddr_bank_check.py` find their IOLOGIC equal outside the lane field and all 102 IOB and `BANK` tables equal. The new `tools/ddr3_pad_set_probe.py` builds the whole controller's pad set on the proven pins as one design: one `DDRDLL`, four lanes each with its `DQS`, SSTL15D strobe pair, eight DQ `IOBUF`s with `OSER8_MEM`, `IODELAY` and `IDES8_MEM` and a DM `TBUF`, and bank 7's 28 balls. Its strobe ports are scalar, because nextpnr leaves the N half of a bused differential port unconstrained. In the open flow each `DQS` lands on its own lane site and every memory-mode pin on its lane's `DQS` output. `tools/dqs_pack_check.py`, which now checks every `DQS` of a design at its own lane's byte group, finds all four equal by table key, `tools/dq_pack_check.py` all 130 serializers equal outside the lane field, and `tools/ddr_bank_check.py` all 102 tables equal. `tools/lane_open_build.py --pack` now runs every applicable check per design, which added `DQS` checks to every lane and pad design, and the full run behaved as expected on 232 of 232 designs and passed 210 of 210 packer checks. The preflight passes all six primitives and the fork's `check_dqs_site.py`, `check_postroute_refusal.py`, `check_hclk_to_fclk_138c.py` and `check_iodelay_gw5a.py` pass. The probe clocks every `PCLK` and `FCLK` from the board pin, which the router splits across HCLK lanes because IOLOGIC reaches lanes 0 and 2 only, so the lane fields stay compared apart. The results are in `docs/ddr3-open-flow.md` and the new TOOL-014. No image was written and no hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

The open flow now places, routes and packs the whole DDR3 pad set to the vendor's fuses in-process, so the next step is to propose stage 2 for user approval: a narrow declared DDR context that a design must request explicitly, admitting only the proven DDR3 balls at SSTL15 or SSTL15D with `BANK_VCCIO=1.5`, `PULL_MODE=NONE` and `DRIVE=8` and refusing everything else on banks 6 and 7, so that an image could be written. Writing any image and all Tang access each need separate approval. Open alongside: the IOLOGIC `FCLK` model reaches HCLK lanes 0 and 2 only, the unused-pin contradiction with the fork's `D108` corpus is unresolved, and the `is_mipi` bug outside the DDR context still touches other cores.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/cmd_pad_probe.py
- tools/ddr3_pad_set_probe.py
- tools/dq_pack_check.py
- tools/dqs_pack_check.py
- tools/lane_open_build.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 40 COMMIT Unreleased 2026-10-24T00:55:00-07:00

#### Coming From:

Unreleased b0fbf71

#### Purpose:

Replace the in-memory DDR context with a narrow declared DDR3 context that a design requests explicitly with a ball manifest, which is the approved stage 2.

#### Outcome:

Committed `55b1404` to the Apicula fork's `epic/gw5ast138c` and pushed it to the `aquasock` remote only. `gowin_pack --ddr3-context MANIFEST` is now the one way a design may configure a pad on banks 6 and 7, and only the GW5AST-138C accepts it. The manifest is loaded and checked against the die: every ball a bank 6/7 pad at its claimed IO site, SSTL15 on a single ball, SSTL15D on both halves of a pair that name each other in one IO cell, and settings exactly `BANK_VCCIO=1.5`, `PULL_MODE=NONE`, `DRIVE=8`. Inside the context each bank 6/7 pad must be a listed ball at exactly its listed standard and pair half, carry `BANK_VCCIO=1.5` and `PULL_MODE=NONE`, `DRIVE=8` on an output and no drive on an input, and no other IO attribute, and a used DDR3 bank must resolve to 1.5 V; anything else, LVCMOS included, is refused by name, as is a context set without a manifest. The stage-1b corrections are unchanged and now apply only under that declared context. On the TinyVCMI side the new `tools/ddr3_ball_manifest.py` writes `fpga/ddr3/ddr3_balls.json` from the proven pin map, 72 balls with 44 on bank 6, 28 on bank 7 and five SSTL15D pairs, each bank read from the chipdb, and its `--check` reproduces the committed file byte for byte. `tools/ddr_bank_check.py` now packs through the flag with that manifest. Through it, `dqs_sstl` and `lane_sstl` on all four lanes, the five bank-7 designs and the whole pad set match the vendor on all 102 tables, while `dq_sstl`, `dq_nodelay_sstl` and `dm_sstl` on every lane are refused because they use a strobe ball as a single-ended SSTL15 input, a measurement shape the controller never uses whose fuses were matched in stage 1b, and `dq_lvcmos` is refused for LVCMOS33. That split follows from the approved rules and is recorded rather than worked around. The fork's new `tests/test_ddr3_context_138c.py` pins every admission rule and every manifest refusal, 26 tests with the manifest ones against the built chipdb, and the existing guard test now declares its context with a manifest. The full fork suite fails the same 58 pre-existing tests with and without the change and passes 27 more. Without the flag, seven non-DDR netlists pack to fuse digests identical to the committed `7a82e4a` packer's and both DDR designs are refused. The results are in `docs/ddr3-open-flow.md` and the new TOOL-015. No image was written and no hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Stage 3, writing an image, needs the user's approval before it starts. The first candidate is an open-flow image built with `--ddr3-context` from a design whose pads are exactly the manifest's, checked fuse for fuse against a vendor build of the same source on every bank 6/7 table before it counts as produced; loading it onto the Tang is a further separate approval. A meaningful hardware image also needs what the pad-set probe leaves out, a memory clock from the PLL through `CLKDIV`s, and the IOLOGIC `FCLK` model reaches HCLK lanes 0 and 2 only. The unused-pin contradiction with the fork's `D108` corpus and the `is_mipi` bug outside the DDR context remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3/ddr3_balls.json
- tools/ddr3_ball_manifest.py
- tools/ddr_bank_check.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 41 COMMIT Unreleased 2026-10-24T01:09:41-07:00

#### Coming From:

Unreleased f2bdc35

#### Purpose:

Write the first open-flow DDR3 image through the declared DDR3 context and verify the written file against the vendor's build table by table, which is the approved stage 3 without any board access.

#### Outcome:

Added `tools/build_ddr3_pad_image.sh`, which checks the manifest, synthesizes, places and routes the whole pad set of `tools/ddr3_pad_set_probe.py`, packs it with `gowin_pack --ddr3-context fpga/ddr3/ddr3_balls.json` into `build/ddr3_image/full_sstl.fs` and never writes the loadable `.bin`, and `tools/ddr3_image_check.py`, which decodes the written image and the vendor build and compares every DDR3 table: the IOB table of every bank 6/7 pad and both `BANK` tables exactly, the IOLOGIC of every bank 6/7 cell outside `FCLKSEL`, the four byte groups' table 58 outside the lane field, and the corner cell's `DLL0` exactly. The first image differed only in `DLL0`, where the vendor sets features 5, 17, 18 and 19, fuses `(21,7)`, `(21,8)`, `(21,9)` and `(21,15)`, in every build with a DDRDLL while the packer had left them to a measurement switch because they are unattributed. At the user's choice of option (a), committed `c8b9622` to the Apicula fork's `epic/gw5ast138c`, pushed to the `aquasock` remote only, which writes them under a declared DDR3 context; the image then equals the vendor on all 306 tables, 102 IOB and `BANK`, 199 IOLOGIC, four DQS and the DDRDLL, with SHA-256 `4c24096e1666c7606b2147a6e8e71d741a21cb25442ec13e6fe947d5154df81f`, reproduced by a rebuild into another directory. The two raw corner bits TOOL-003 recorded with those features, `(1,12)` and `(9,13)`, turned out to be the unused-pin drive of the corner cell's bank-6 pad, and TOOL-003 was revised. Without the flag the DDRDLL probe designs and the other non-DDR netlists pack to fuse digests identical to the committed `55b1404` packer's, and the fork's full suite fails the same 58 pre-existing tests. The image is a measurement artifact whose serializers run from the board clock with no memory PLL or controller, so it was not converted for or loaded onto the board, and no hardware was accessed. The results are in `docs/ddr3-open-flow.md` and the new TOOL-016. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

The configuration path is complete offline, so the next work is what makes an image worth loading. Extend the IOLOGIC `FCLK` model from HCLK lanes 0 and 2 to all four, measured as lanes 0 and 2 were, so a lane's serializers can follow its `DQS` and `CLKDIV` on any lane. Then build a PHY-only image clocked as the proven controller is, the memory PLL at 400 MHz through a `CLKDIV` per lane, with a TinyTang readout of `LOCK` and the lanes' status outputs and the DDR3 device held in reset, and propose it for user approval together with the first Tang load. The `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/build_ddr3_pad_image.sh
- tools/ddr3_image_check.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 42 COMMIT Unreleased 2026-10-24T03:01:52-07:00

#### Coming From:

Unreleased a4eeefe

#### Purpose:

Extend the IOLOGIC fast-clock model from HCLK lanes 0 and 2 to all four so a DDR3 lane's serializers can follow its `DQS` and `CLKDIV` onto any lane, which is step 1 of the approved path to a loadable image.

#### Outcome:

Committed `92836ee4` to the nextpnr fork's `epic/gw5ast138c` and `a7033be` to the Apicula fork's, both pushed to the `aquasock` remotes only. The lanes-0-and-2 limit turned out to be Apicula's own `FCLKSEL1`/`FCLKSEL2` spelling, which has no odd-lane rows, not the silicon. `tools/dq_lane_probe.py`'s per-lane designs were added on side B, on AA4 for lane 0 and T6 for lane 2, beside the side-A sets every lane already had, and decoding the vendor builds gave one `FCLKSEL` encoding per primitive, side and lane, identical on every DDR3 lane. An exhaustive search over the IOLOGIC table's `FCLKSEL` attributes found the spellings that reproduce each exactly on both sides: `OSER8_MEM` lane 1 is `FCLKSEL0` and `FCLKSEL4` at `HCLK1` and lane 3 `FCLKSEL0=HCLK1`, and `IDES8_MEM` lane 1 is `FCLKSEL4`, `FCLKSEL5` and `FCLKSEL6` at `HCLK1` with `FCLKSEL7=HCLK1_`, lane 3 the same without `FCLKSEL4`. The nextpnr generator's new `extend_dq_lane_fclk` gives the 40 DDR3 lane positions' `FCLKA` and `FCLKB` fuse-free pips from `HCLK21` and `HCLK23` and adds those cells to the two lane nodes, leaving every other IO cell at lanes 0 and 2, and the Apicula packer keeps those pips out of its pip lookup and writes the measured sets. All 48 per-lane serializer designs now route with no lane-split warning and pack equal to the vendor including the lane field, so `tools/lane_open_build.py --pack` now requires an exact match for every `*_lane0..3` design, and the full run behaved as expected on 246 of 246 designs and passed 224 of 224 packer checks. `check_dqs_site.py` gained a check for the new pips and passes eight of eight, the generator stays deterministic, the preflight passes all six primitives, six non-DDR netlists pack to unchanged fuse digests, the fork suite fails the same 58 pre-existing tests, and the written pad-set image is unchanged, digest `4c24096e`, equal to the vendor on all 306 tables. Side B of lanes 1 and 3 is inferred from the lane-independent encoding, not built. The results are in `docs/ddr3-open-flow.md` and the new TOOL-017. No hardware was accessed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, and active-log capacity.

#### Next Steps:

Design step 2 and bring it to the user for approval together with the first Tang load since entry 10: a PHY-only image clocked as the proven controller is, the memory PLL at 400 MHz feeding one `CLKDIV` per lane and the four `DQS` blocks, the `DDRDLL` running against that clock, a TinyTang readout of `LOCK` and each lane's status outputs, every DQ, DM and strobe output held in tristate and the DDR3 device held in reset with `ddr_reset_n` low and `ddr_cke` low, built with `--ddr3-context` and checked by `tools/ddr3_image_check.py` against its vendor build before any load. The `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/lane_open_build.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---
## 43 COMMIT Unreleased 2026-10-24T08:57:29-07:00

#### Coming From:

Unreleased 9daad20

#### Purpose:

Build the first DDR3 image meant for the board, a PHY-only image clocked as the hardware-proven controller is with the DDR3 device held in reset, gate it against its vendor build, and load it on the Tang beside a vendor control.

#### Outcome:

Committed with `0a45d6ba` to the nextpnr fork's `epic/gw5ast138c` and `b556b89` to the Apicula fork's, both pushed to the `aquasock` remotes only. Reading the proven controller's netlist and decoding its bitstream corrected the plan before any build: its PHY has one `CLKDIV`, `fclkdiv` at `LEFTSIDE[4]`, not one per lane, every `DQS` and serializer takes the memory clock on HCLK lane 0, the DLL control flops run on the 50 MHz board clock, and `STOP` is driven through a `LUT1` with `INIT=2'h1`, an inverter, so TOOL-005's buffer reading was wrong and is corrected. `fpga/ddr3_phy_bringup` carries that PHY with a 400 MHz PLL on `PLL_L[0]`, the pad-set lane shapes, bank 7's command serializers and a hand-written sequencer and 2 Mbaud TinyTang responder (`bringup_core.v`), with `ddr_reset_n` and `ddr_cke` low from constants and every lane serializer's `TX` high; `tools/ddr3_phy_bringup.py` generates and vendor-builds it, and `tools/build_ddr3_phy_bringup.sh` writes the two `.bin` files only after the manifest check, a simulation against Gowin's primitive models (`tools/sim_ddr3_phy_bringup.sh`), an open-flow build with no HCLK lane split, and `tools/ddr3_image_check.py --exact-lanes` all pass. Gowin's `DQS` simulation model turned out to be an empty module, so the simulation substitutes `tb_dqs_standin.v`; it shows the lane pads driven low, never high, from configuration until about 20 ns after the lanes leave reset, which is the `OSER8_MEM` model's reset state and a deviation from the approved all-tristate wording that was reported to the user before the load. The first exact comparison failed 67 tables and both causes were model gaps: a serializer on a routed `RESET` has no reset multiplexer on its own half, which Apicula now follows for `OSER8_MEM`, `IDES8_MEM` and DDR-context `OSER8`, and the DLL's clock source is a `DLL0` feature, measured in 19 vendor builds by `tools/ddrdll_port_probe.py --check`: feature 5 is `CLKIN` from the port tile's `CLK0`, and when the clock also drives a `CLKDIV` at `LEFTSIDE[4+n]` the vendor drops `GB10 -> CLK0` and sets features 21 and `4-n`, while port drive, polarity, clock constraint and a PLL source move nothing except an inverted `RESET` clearing feature 19. The nextpnr fork gives the DLL a `DDRDLL_CLKIN` pin wire reached from `CLK0` and from `HCLK20` to `HCLK23`, offers the lane pips exactly when the net also feeds a `CLKDIV`, joins the DLL to the lane its `CLKDIV` holds, and checks HCLK lane splits per block, which removed a false warning for a clock spanning blocks 0 and 2; Apicula writes the source the router took. The image then equalled the vendor build on all 306 tables with bank-6 lanes exact; bank 7's 26 serializers sit on lane 0 of block 0 in the open image and lane 3 in this vendor build, and the proven controller's own bitstream uses lane 0. On the Tang the vendor control, 4,330,802 bytes, SHA-256 `3c011b871a8d5ebbb02166a83d107689ebfcfdf2a780a72abad81e02781e6da3`, and the open-flow image, 4,330,782 bytes, SHA-256 `e1f4ecbf22b13cbbc1863e53519f187544a74a369b29101875c0440a3544d3e5`, were placed on the card and loaded with `tangload` in turn; both answered core ID `0x56` and returned in every read, before and after a sequence restart, state RUN, PLL lock 1, DLL `LOCK` 1 and `STEP` `0x2c` with both counters advancing and every lane status byte 0. That is the first nonzero tap code this project has read, and every earlier image that read zero had clocked its DLL from `CLK0`, which TOOL-004 now records. The desktop core was loaded again and answered `0x54`, and the DDR3 device was never released from reset. `tools/lane_open_build.py --pack` over all four lanes found 246 of 246 designs as expected and 224 of 224 packer checks equal: the first run's 55 packer failures were all `KeyError: 'DDRDLL_CLKIN'` from the agent stashing the Apicula change for a test while the regression was packing, and all 55 passed on a full rerun of lanes 1 and 2 with nothing else running. The DDRDLL liveness and open-flow smoke images rebuild to their earlier digests, the Apicula suite fails the same 58 pre-existing tests by name, its twelve new `tests/test_ddr3_phy_138c.py` tests pass and ten fail on the previous packer, `check_dqs_site.py` passes nine of nine and the preflight six of six. TOOL-003, TOOL-004, TOOL-005 and TOOL-016 were revised and TOOL-018 added. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Step 3, approved by the user: release the DDR3 device from reset and read the MPR pattern back with no write. Before the design, model the PLL's `ENCLK` inputs so the memory clock can be stopped around the `CLKDIV` and lane reset as the vendor does: matched builds already place `ENCLK0` and `ENCLK2` on wires `B6` and `B4` of tile (27,4), `PllIn` rows 183 and 185 of the vendor `.dat`, with rows 183 to 189 running `B6` to `B0`, and the constant-high case routing VCC into the pin, so the model must route `ENCLK` only when a signal drives it to keep every existing PLL image unchanged. Then add the JEDEC initialization, MPR enable, read commands and a UART-driven sweep of each lane's `READ` timing and `RCLKSEL`, gate it as this cycle was, and load it beside a vendor control. Check why the proven bitstream shows 25 bank-7 cells with a lane selection against this image's 26. The `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_phy_bringup/bringup_core.v
- fpga/ddr3_phy_bringup/top.v
- fpga/ddr3_phy_bringup/top.cst
- fpga/ddr3_phy_bringup/open.sdc
- fpga/ddr3_phy_bringup/vendor.sdc
- fpga/ddr3_phy_bringup/tb_bringup.v
- fpga/ddr3_phy_bringup/tb_dqs_standin.v
- tools/ddr3_phy_bringup.py
- tools/build_ddr3_phy_bringup.sh
- tools/sim_ddr3_phy_bringup.sh
- tools/ddr3_image_check.py
- tools/ddrdll_port_probe.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---
## 44 COMMIT Unreleased 2026-10-24T10:03:27-07:00

#### Coming From:

Unreleased 52c6e55

#### Purpose:

Take the DDR3 device out of reset for the first time and read its MPR pattern back through the open-flow PHY, with nothing written, as step 3 of the approved path to working DDR3.

#### Outcome:

Committed with `d69c764` to the Apicula fork's `epic/gw5ast138c` and `a0935e6b` to the nextpnr fork's, both pushed to the `aquasock` remotes only. Two measurements came first. `tools/pll_enclk_probe.py` found the PLL's output enables, which neither fork modelled, on wires `B6` (`ENCLK0`) and `B4` (`ENCLK2`) of tile (27,4), routed inputs that a register or VCC reaches by a pip with no PLL fuse moving, and rows 183 and 185 of the vendor `.dat`'s `PllIn` table, whose rows 183 to 189 run `B6` to `B0`; Apicula now builds `ENCLK0` to `ENCLK6` from those rows for this device, after a rebuild of the untouched database reproduced its recorded digest `4b257561`, and nextpnr still drops a high tie, or a low tie on an unused output, so the DDRDLL liveness and open-flow smoke images rebuild to their earlier digests and the step-2 bring-up image to equal tables with one ground-net tie broken differently at X93Y27. `tools/vendor_memsync_trace.py` cut the vendor IP's 106-cell `ddr_sync` block out of its post-route netlist and simulated it with Gowin's models: the DLL reset releases at the IP reset's release, then 16392 clocks after DLL `LOCK` the PHY raises `HOLD`, pulses `UPDNCNTL`, drops `HOLD`, stops the memory clock through `ENCLK2`, pulses the `CLKDIV` and lane reset with the clock stopped, restarts it and is ready, which step 2 had not done. `fpga/ddr3_mpr` follows that order, runs the JEDEC power-up at DDR3-800, enables MPR and streams reads, with every lane serializer in tristate and ODT low; `tools/build_ddr3_mpr.sh` gated it with a command-decoding simulation, a counter testbench, nextpnr timing (`PCLK` 115 MHz) and the exact-lane table check, all 306 tables equal to its Gowin build. A first `iverilog` failure turned out to be OSS CAD Suite's stricter build rejecting a use-before-declaration the system one accepted, and the build scripts could not overwrite Gowin's read-only `.bin`; both were fixed, the second in the step-2 script too. On the Tang both the vendor control, SHA-256 `cfa1705832ca47d4f2006a9afbadfc42d72cf3fca5e448327672f148d9712b59`, and the open-flow image, SHA-256 `bfced70834f9f7dbf59435c1b732b43487216fb5aaa69c6bb67ab76f036d9a5a`, initialized the device and read `0xAA` on all 32 DQ in 65535 of 65535 cycles on every lane at every `RCLKSEL` with `RVALID` high, after a first load whose counter read 0 because a fully matching 65536-cycle window overflowed it. With reads off the deserializers hold their last word, so liveness was shown by `tools/ddr3_mpr_probe.py` stepping each lane's read delay with `RMOVE`: the lower edges are -8 to -9, -13, -18 to -19 and -22 to -23 steps in the vendor image and -17 to -18, -23, -23 and -27 to -28 in the open-flow image, repeatable within one step, and only lane 3 has an upper edge, at +43 in both. The 4-to-10-step offset is unexplained by any compared table and is recorded as open. The desktop core was reloaded and answered `0x54`. `tools/lane_open_build.py --pack` passed 246 of 246 designs and 224 of 224 packer checks on the new forks, the Apicula suite fails the same 58 pre-existing tests by name with thirteen of its own new tests passing, and the nextpnr generator checks pass. `docs/ddr3-open-flow.md` gained the cycle, TOOL-019 and TOOL-020 were added and TOOL-005 revised. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Step 4, approved by the user: write leveling, writes and read-back. The image `fpga/ddr3_write` and its tools are built and gated offline -- simulation, timing and all 306 tables equal to the vendor build -- but not committed, because the user asked that the Tang not be touched; its board session waits for the user's go-ahead, and it is committed with that session's result. After writes come read calibration for real reads (gating, per-lane centering, word alignment, and the edge offset above), then a controller, likely LiteDRAM's over this PHY, then the AE350 port. The `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_mpr/mpr_core.v
- fpga/ddr3_mpr/top.v
- fpga/ddr3_mpr/top.cst
- fpga/ddr3_mpr/open.sdc
- fpga/ddr3_mpr/vendor.sdc
- fpga/ddr3_mpr/tb_mpr.v
- fpga/ddr3_mpr/tb_mpr_count.v
- tools/ddr3_mpr.py
- tools/build_ddr3_mpr.sh
- tools/sim_ddr3_mpr.sh
- tools/ddr3_mpr_probe.py
- tools/pll_enclk_probe.py
- tools/vendor_memsync_trace.py
- tools/build_ddr3_phy_bringup.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---
## 45 COMMIT Unreleased 2026-10-24T10:12:57-07:00

#### Coming From:

Unreleased 5f0d4be

#### Purpose:

Write data to the DDR3 device through the open-flow PHY and read it back, with write leveling, as step 4 of the approved path to working DDR3.

#### Outcome:

No fork changed in this cycle. The proven controller's netlist shows the write timing driven as one absolute 8-bit `WSTEP` per lane loaded by a shared `WLOADN` with `WMOVE` and `WDIR` low, and `fpga/ddr3_write` follows it, adding to the MPR image's PHY four link-selected modes: idle with refresh every 7 us, write leveling, writes streamed across row 0 of bank 0 with the strobes and DQ toggling continuously so the write latency only rotates the pattern, and reads back with a per-lane check for one rotation of the pattern `P` on even DQ and `~P` on odd DQ. `tools/build_ddr3_write.sh` gated it with a simulation that decodes every command and asserts row discipline, tRCD, tRP, tRFC, refresh within 7.8 us, the leveling entry and exit, ODT and the bus, which caught the core going idle a few nanoseconds before the serializers released the bus, fixed by ordering the release first; the first open-flow build missed `PCLK` by 0.02 percent through the read check, which now runs in two stages, closing at 165.8 MHz in nextpnr and 123.9 MHz in Gowin, and the image equals its Gowin build on all 306 tables. The user asked mid-cycle that the Tang not be touched, and the board session ran only after the user said it was ready. On the Tang the open-flow image, SHA-256 `58ceeb3d9a3738a29700ef4679122ba518b503a6576a4c276174c9d5b73db3af`, wrote and read back the pattern on all four lanes in every eligible cycle at every `WSTEP` from 0 to 248 in steps of 8 except the single settings 104, 112 and 248, and the vendor control, SHA-256 `447b41ad5ce197df254dcfa6fe22111e0fc241a3bbe67caa3d5f15a787397887`, except 72, 80 and 248, with no write leveling; changing the expected pattern without writing read 0 on every lane, and writing `0x6B` and then `0xC5` restored the full count, so the data read is the image's own. On the vendor control's first start-up lanes 0 and 2 read individual bits one or two clocks out of frame at every `WSTEP`, `RCLKSEL` and read delay, which the MPR pattern could never have shown, and a restart of the core's start-up aligned every lane in four of four tries; the open-flow image was aligned from its first start, and each lane's whole-word rotation changes between read sessions. The write-leveling count read 0 throughout because the core holds `READ` low outside read mode, so the read FIFO never clocks; that is recorded as a design limit in `wr_core.v` rather than fixed in this cycle, since writes land without leveling. The desktop core was reloaded afterwards and answered `0x54`. `docs/ddr3-open-flow.md` gained the cycle and TOOL-021 was added. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Bring to the user for approval the read-calibration cycle: make the start-up wait for a settled PLL before the clock-stop sync and add per-bit `IDES8_MEM` `CALIB` control so word framing is aligned and verified at every start; hold each lane's word rotation fixed across read sessions; gate reads with `READ` around each burst instead of streaming, centre each lane's read delay, and explain the 4-to-10-step read-edge offset against the vendor build; assert `READ` during write leveling so it measures; and widen the pattern test from one row to many rows, banks and data patterns. A controller, most likely LiteDRAM's over this PHY, and the AE350 port follow. The `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_write/wr_core.v
- fpga/ddr3_write/top.v
- fpga/ddr3_write/top.cst
- fpga/ddr3_write/open.sdc
- fpga/ddr3_write/vendor.sdc
- fpga/ddr3_write/tb_wr.v
- tools/ddr3_write.py
- tools/build_ddr3_write.sh
- tools/sim_ddr3_write.sh
- tools/ddr3_write_probe.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 46 COMMIT Unreleased 2026-10-24T10:58:40-07:00

#### Coming From:

Unreleased ef690f4

#### Purpose:

Calibrate live DDR3 reads across all four lanes, make write leveling observable, explain the vendor/open read-eye offset, and widen the hardware data test across banks, rows and patterns.

#### Outcome:

`fpga/ddr3_write` now waits for stable PLL lock before the vendor-derived PHY sync, exposes per-bit `IDES8_MEM.CALIB`, asserts `READ` during write leveling, issues configurable grouped reads through a delayed DQS `READ` pipeline, and selects all banks and 15-bit rows; its host tool aligns per-bit framing, alternates disjoint patterns through a signed 256-step live eye sweep, verifies repeated read sessions and tests configurable address/pattern sets. The final simulation passed with 4876 writes, 3922 reads and 29 refreshes, both flows met timing, and the open image equalled its vendor build on all 306 DDR3 tables; `tools/ddr3_image_check.py` now also reports the four non-failing HCLK mux differences. On the Tang, per-bit calibration worked, write leveling produced circular transitions on every lane, two open eye sweeps placed the lower edges 8 to 12 steps after the vendor's with no upper edge by +127, ten complete restarts retained aligned bits, and all 336 combinations of eight banks, six rows and seven patterns passed at about 25100 live cycles per case on every lane. The raw whole-byte rotation still changes by lane and read epoch and must be normalized by a controller. The differing bank-7 HCLK00 selection, direct global/HCLK routing in the open image versus vendor `CLKDIV2_O00`, is the likely source of the eye offset, though not a direct delay measurement. The deployed open image was SHA-256 `89f917f6ec0d684331563e51246665473bd3a96fa930066a1f016a2d882dac6f`; the desktop image was restored and answered `0x54`. `docs/ddr3-open-flow.md` and TOOL-022 record the durable evidence. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Build the controller-facing read-data aligner around a trained read-valid boundary so each lane's changing raw byte rotation becomes fixed logical data, then integrate the PHY with a controller, most likely LiteDRAM's control layer, and qualify sustained random traffic and the full array before beginning the AE350 port; the `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_write/tb_wr.v
- fpga/ddr3_write/top.v
- fpga/ddr3_write/wr_core.v
- tools/build_ddr3_write.sh
- tools/ddr3_image_check.py
- tools/ddr3_write.py
- tools/ddr3_write_probe.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 47 COMMIT Unreleased 2026-10-24T12:55:31-07:00

#### Coming From:

Unreleased 21e3dba

#### Purpose:

Build the controller-facing read-data aligner around a trained read-valid boundary, measure what moves the read word frame, and make the aligned burst hold pattern order under live traffic.

#### Outcome:

`fpga/ddr3_write/rd_align.v` trains each lane's whole-word rotation from the live read stream, derotates and transposes it into one 256-bit burst of eight 32-bit beats with a per-cycle valid, and refuses a pattern whose eight rotations are not distinct; `wr_core.v` arms it on read entry, on every CALIB pulse and on a new command `0x23`, and its status frame grew to 122 payload bytes to carry the aligned snapshot, per-lane locks, err, drift, live phase, phase-move counters and followed slips. Two mechanism defects surfaced on the way: a lock that needed 32 consecutive stream cycles could never complete against the core's gated reads and now counts agreeing observations across gaps, and `open.sdc` had silently stopped constraining `PCLK` after flattening renamed the net to `core.pclk`, so `tools/build_ddr3_write.sh` now fails when a clock constraint matches no net. The in-core phase monitor showed the frame is deterministic rather than drifting: it never moves while the stream is live, moves once per interruption and is first seen at the first live cycle after a gated gap, moves all four lanes by the same amount with their offsets preserved, and its size is fixed by the read delay and not by the gap length, 510, 319 and 40 PCLK apart at read-run/gap 255/255, 255/64 and 32/8 and about 700 PCLK apart at 255/1, with step `-2` at delays 2 to 7 and `+4` at delays 0 and 1 and `RBURST` low throughout. The aligner therefore follows a uniform move held for eight cycles instead of flagging it, withholds valid while the frame is moving, and reserves `drift` for a lane that leaves its lock alone. The unit simulation passes with the gated-stream and slip cases and both the wrong derotation and the wrong transpose trip 29 assertions; the first full build missed `PCLK` at 95.26 MHz, which a wiring transpose plus a three-stage byte rotation and a registered measurement fixed, closing at 128.02 MHz. On the Tang the open image, SHA-256 `40ddf0256d7a03d38678528c07ada37bf8ea02adf9ea312c0211ce66a4f51d79`, passed six of six read sessions with `err` and `drift` clear and every presented burst in pattern order, 26,151 to 26,391 bursts each with roughly 48,800 slips followed, kept 100 percent of 10,309 bursts when trained at 255/255 and dropped to 32/8 without leaving read mode, and passed a 240-case bank/row/pattern sweep twice with no failures; the locked rotations differed between sessions, which is the point of the exercise. The desktop `tinytang.bin` was restored and answered `0x54`. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Train the aligner once at start-up and hold its locks through ordinary traffic, then build the controller that binds a burst to the READ command that asked for it, most likely LiteDRAM's control layer over this PHY, and qualify sustained random traffic across the full array before beginning the AE350 port; the diagnostic still presents nothing below about twenty reads per group, and the `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_write/open.sdc
- fpga/ddr3_write/rd_align.v
- fpga/ddr3_write/tb_align.v
- fpga/ddr3_write/wr_core.v
- tools/build_ddr3_write.sh
- tools/ddr3_write.py
- tools/ddr3_write_probe.py
- tools/sim_ddr3_write.sh
- tools/sim_rd_align.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 48 COMMIT Unreleased 2026-10-24T13:44:36-07:00

#### Coming From:

Unreleased 3dbcba5

#### Purpose:

Settle whether the DQS block's RBURST output frames a read burst, and whether the upstream LiteDRAM GW5A DDR3 design could replace the hand-written open-flow one.

#### Outcome:

`top.v` now detects RBURST edges in the memory-clock domain -- one toggle bit per lane, counted in PCLK, cleared by a new command `0x24` -- because a counter in that domain put a wide incrementer on the 400 MHz path and closed it at 394.94 MHz against a 400 MHz constraint, while the toggle version closes at 476.64 MHz with PCLK at 117.34. A corrected status frame was needed first: the payload had grown past what the seven-bit response index could count, so `7'd130` wrapped and the reply stopped after three bytes, and the index is now eight bits. On the Tang the image, SHA-256 `24ed798874de9ee4d5a781e601b788701b09d2f1d622d2d82ad88bb88066a707` and equal to its Gowin build on all 306 DDR3 tables, counted RBURST edges over 250 ms at each RCLKSEL with read-run/gap 255/255 and delay 3: none at RCLKSEL 0, 2, 3, 6 or 7; 384, 432 and 48 per second on lanes 1 to 3 at 1; 576 to 620 per second on all four lanes at 4; and 384, 12, 0 and 384 at 5, with RCLKSEL 3 and 4 the settings where every lane held RVALID high. Since a burst is issued every PCLK while reading, a per-burst marker would count near 100,000 per second, so RBURST does not frame a burst here and the slip-following aligner stays the mechanism; TOOL-024 records the measurement and the RBURST sentence in TOOL-023 was narrowed to match. The second question was answered by `tools/litex_ddr3_gate.sh`, which regenerates the upstream LiteX Tang Console design for GW5AST-138C with DDR3 at 1:4 and no CPU, rewrites its constraints into forms nextpnr accepts and builds it with the open flow: the design uses only primitives this project already packs (26 IODELAY, 20 OSER8_MEM, 16 IDES8_MEM, 16 IOBUF, 2 DQS, 2 ELVDS_IOBUF, 1 DDRDLL, 1 CLKDIV, 1 PLL, 1 ELVDS_OBUF) and synthesises cleanly, but placement stops at three gaps -- nextpnr rejects `create_generated_clock`, does not treat a differential `IO_LOC` pair as constraining both pads, and rejects `sys4x_clk` driving `OSER8.FCLK` as an invalid sink -- while the same netlist fails the vendor flow on an unrelated bank-5 VCCIO conflict and its platform wires only 16 of this board's 32 DQ pins, so LiteDRAM is not a drop-in and TOOL-025 records the gate. The desktop `tinytang.bin` was restored and answered `0x54`. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Build the controller that binds a burst to the READ command that asked for it and establishes read latency, most likely LiteDRAM's control layer adapted to this PHY rather than its PHY adopted wholesale, then qualify sustained random traffic over the full array and begin the AE350 port; a sweep of RCLKSEL must re-enter read mode per setting, the diagnostic still presents nothing below about twenty reads per group, and the `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_write/top.v
- fpga/ddr3_write/wr_core.v
- tools/ddr3_write.py
- tools/ddr3_write_probe.py
- tools/litex_ddr3_gate.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 49 COMMIT Unreleased 2026-10-24T15:02:25-07:00

#### Coming From:

Unreleased de5d085

#### Purpose:

Make single DDR3 READs measurable through the open-flow PHY, measure their read latency and whether the word frame holds from one READ to the next, and test whether the DQS read gate's alignment explains the frame moves of TOOL-023.

#### Outcome:

`fpga/ddr3_write` gained a READ gate offset of k memory clocks within the delayed PCLK (command `0x25`), a closed-page random mode issuing ACTIVATE then READ with auto-precharge to one of sixteen rows every 8 PCLK (mode 4), `rd_check.v`, a single-burst checker with a 32-offset latency histogram, a rotation lock and first-failure capture behind a second status frame (`0x27`), and an RBURST count over exactly 2^n PCLK (`0x24 n`); `tools/ddr3_write_probe.py` gained `gate`, `prewrite` and `random` and a windowed `burst`. Three faults in the committed image were found and fixed. Its status concatenation was 1020 bits in a 1016-bit wire, confirmed by Verilator and iverilog, so every byte above 119 read four bits off: entry 47's relock count is known only modulo 4096 and entry 48's RBURST rates, whose 8-bit counters also wrapped, are withdrawn, which reopens TOOL-024. The refresh interval stopped during pauses, harmless in the streaming modes but an overrun of tREFI in random mode; the simulation's worst interval is now 7.17 us. And the Gowin control of the committed source misses PCLK at 89.9 MHz, unchecked by the build, because GowinSynthesis packs the setting synchronizers into LUT-RAM shift registers, among other paths in `rd_align` (TOOL-028); with `syn_srlstyle`, kept DQ register copies and three shorter `rd_align` cycles whose unit test still passes, the Gowin control closes PCLK at 100.51 MHz with no negative slack, `tools/build_ddr3_write.sh` now fails on any Gowin negative slack, and `top.v` keeps its `pclk` wire after flattening renamed the net and the existing SDC guard caught it. The checker, aligner and image simulations pass, the last with per-bank tRCD, tRAS, tRP, tRC, tRRD and tFAW checks over 631 random READs. The open image, SHA-256 `466979d693fba0c147af379ca17ccb010ae4b4d6d167d1b080c4fc5eda18a0cd`, closes PCLK at 126.29 MHz and equals its Gowin build, `f2cc60e1240396450fb04e4bd3ef6f91806957aeda91b6ac4faa497c2416aaca`, on all 306 DDR3 tables; only the open image was loaded and it answered `0x56`. On the Tang a stream read back on all lanes, and the gate sweep showed the frame move per read gap set by k alone, 6, 4, 2 and nearly 0 beats for k 0 to 3 at delays 2 to 7, and no move at delay 1 with k 2 or 3 (TOOL-026), so TOOL-023's move was a misaligned gate. Single random READs passed at none of the 32 gate positions: at delay 1, k 2 the right burst was whole on all lanes 7 PCLK after the READ in 12.5 percent of READs, and the failing words carried other patterns (TOOL-027), most likely because a lone burst straddles two captured words, which a stream of one pattern hides; that is a hypothesis. The user approved recording this result and starting the burst reassembly as a new cycle. The desktop `tinytang.bin` was restored and answered `0x54`. TOOL-023 and TOOL-024 were revised and TOOL-026 to TOOL-028 added. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Add a raw capture of all four lanes' words for about 24 PCLK after one isolated READ to see where a single burst lands, then make `rd_check` reassemble each burst from two consecutive words with a per-lane beat slip trained on isolated READs and check latency, slip and data per READ at the stream-stable gate positions; in the same board session run the windowed RBURST count to settle TOOL-024. Framing writes to their WRITE command, then the controller and the AE350 port follow; the `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_write/open.sdc
- fpga/ddr3_write/rd_align.v
- fpga/ddr3_write/rd_check.v
- fpga/ddr3_write/tb_check.v
- fpga/ddr3_write/tb_wr.v
- fpga/ddr3_write/top.v
- fpga/ddr3_write/wr_core.v
- tools/build_ddr3_write.sh
- tools/ddr3_write.py
- tools/ddr3_write_probe.py
- tools/sim_ddr3_write.sh
- tools/sim_rd_check.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 50 COMMIT Unreleased 2026-10-24T17:04:00-07:00

#### Coming From:

Unreleased 64407e9

#### Purpose:

Make a single DDR3 read burst whole by reassembling it from two consecutive captured words with a per-lane beat slip, and land that in an image whose vendor control meets timing.

#### Outcome:

`fpga/ddr3_write/rd_check.v` now reassembles a lone read burst from two consecutive captured words: it registers the previous DQ word, shifts the per-pin 16-bit pair by a 3-bit per-lane beat slip, and takes that slip from command `0x2A`, disabled out of reset so every earlier diagnostic behaves exactly as before; `tools/ddr3_write_probe.py random` defaults to the measured vector `0 0 0 4`, and `fpga/ddr3_write/tb_check.v` case 7 proves slips 0, 2, 4 and 7 reassemble 300 of 300 simulated READs while the six earlier cases stand. The capture that produced that vector, a temporary 768-bit buffer holding 24 PCLK after one isolated READ, was a measurement and not a deliverable: its 24-way enable cost the vendor control 768 failing endpoints at 91.772 MHz, so it was removed once read, and its result is recorded in `docs/ddr3-open-flow.md` rather than kept as a tool. Closing the vendor control then took three structural changes, none of them a relaxed constraint: the adjustable latency's 32-way indexed select was split into registered 4-way and 8-way stages, `rd_align`'s eight pattern compares became a `match` vector with the encode after it instead of an if-chain that serialized through the priority mux, and `rd_check`'s move counter now counts a registered pulse; `meas_ok_r` also lost its reset, which only the lock block's own `rst || arm` branch had consumed, and the measurement keeps its one-cycle latency because a third pipeline stage was rejected by `tb_align`, which asserts training completes in exactly `LOCK_CYCLES`. The vendor control closes PCLK at 103.145 MHz with `0.000` TNS on all three clocks, the open flow closes it at 122.31 MHz after routing, and eight deterministic seeds give 112.13 to 127.65 MHz, so seeding was never the question. The image, SHA-256 `5d3d1ab1c87ce9ea49d11e57c415a2efb57705393b1da58ee5d4b30fd725344c` as `.fs` and `bdb00f24c056072537484b1fa756311e65bffe04e256451a9bf4df4b8340e1c6` as `.bin`, equals its vendor build, `e039cd586cee4ff569d69cf0b1ff589a96c98d87750e1aaec16fab2aa8df01d5`, on all 306 tables with lanes exact, and `tools/ddr3_write_seed_sweep.sh` reproduces the seed spread offline. On the Tang the open image answered core `0x56` with lock and CKE high and `STEP 0x2c`, `calibrate` aligned all 32 DQ bits on every lane at 24,977 of 24,977 eligible cycles, and a stream read-back matched 24,989 of 24,988 cycles on every lane at rotation 6 with even pins `0x47` and odd pins `0xB8`. The aligner does not train at the default read-run 32 and gap 8, where the vendor build of the same source trains five sessions with about 91 relocks, but at 255/255 it trains all four lanes in five of five sessions and presents 26,000 to 26,201 bursts each in pattern order with err and drift clear, which places the 32/8 failure on the CK route and read eye of TOOL-022 rather than on the aligner. At delay 1 and gate 2, checked at offset 11, slips `0 0 0 4` reconstructed 1,526,697 of 6,013,517 READs at the expected rotation against 328,494 of 6,013,518 with the reassembler disabled, 25.4 percent against 5.5, and offset 19 passes 9.7 percent while no other gate position exceeds 8, so the straddle is real and is not the whole cause: the burst lands at one of two positions 8 offsets apart and a fixed offset sees one of them. The windowed `0x24` count settled TOOL-024 negatively, 0 to 163 RBURST edges per lane per 2^16 PCLK against about 8,192 expected if every READ marked its burst, at every RCLKSEL. The desktop `tinytang.bin` was restored afterwards and answered `0x54`. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

What remains is the controller: bind each burst to the READ command that asked for it and establish per-command read latency, since the burst's two positions are exactly what a fixed check offset cannot cover, then qualify sustained random traffic over the full array before beginning the AE350 port; a sweep of RCLKSEL must still re-enter read mode per setting, the slip vector must be retrained whenever the read delay changes, and the `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_write/rd_align.v
- fpga/ddr3_write/rd_check.v
- fpga/ddr3_write/tb_check.v
- fpga/ddr3_write/wr_core.v
- tools/ddr3_write_probe.py
- tools/ddr3_write_seed_sweep.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 51 COMMIT Unreleased 2026-10-24T17:51:00-07:00

#### Coming From:

Unreleased 1e1e6ea

#### Purpose:

Find out what decides which capture position holds an isolated DDR3 read burst, and why most isolated READs reconstruct at no position at all, before committing a controller read path to either a trained latency or a two-word window.

#### Outcome:

`fpga/ddr3_write/rd_check.v` gained a per-READ burst-position classifier with its own frame: at each READ's offset-19 check it decides whether the burst held both 11 and 19, 11 only, 19 only or neither, records the refresh phase at that check as a min/max range per class, and keeps the last eight classes; command `0x2B` returns the 34-byte frame and `tools/ddr3_write_probe.py pos` reads it. `m11` is delayed eight clocks to meet `m19` for the same READ and the decision is registered, because classifying on the check cycle itself put every READ in neither and `fpga/ddr3_write/tb_pos.v`, a new bench that drives one READ's own pattern at exactly one offset, caught it; `tools/sim_rd_check.sh` now runs it beside the existing checker cases. On the Tang with the image whose `.bin` is `c15996cbcd87b4c42e6939fdc7f1d6b5150ee70fbe36f9dc8953d062e8d7816d`, calibrated to 24,957 of 24,958 eligible cycles on every lane, 4,820,348 READs at delay 1 and gate 2 classified as 3,493 both, 76,811 at 11 only, 22,588 at 19 only and 4,717,456 at neither, and every class's refresh phase spanned 0 to 1023, so the position is not a refresh epoch and a retrain per epoch would gain nothing. The survivors sit at whole-word offsets, 975 at 11, 438 at 19 and 80 at 27 in an unsaturated window, so the failures are not a burst in the wrong place. The cadence is not the cause either: `rand_wait` derives from the existing read gap, so it was swept without a rebuild and the rate fell monotonically from 17,247 of 1,478,556 at gap 8 to 297 of 46,675 at 255. Neither is the gate: all 32 (delay, gate) positions at gap 255 peak at 0.40%, while `memtest` passes 12 of 12 cases across banks 0 to 3 and rows 0 to 2 and a stream read still matches 24,989 of 24,988 cycles, so the device, the addressing and the capture all work when the stream is continuous. The conclusion recorded is that closed-page scatter reads do not reach the read capture at any cadence or gate position, that the failure is not framing and so the two-word reassembler of entry 50 does not address it, and that it will matter for the AE350's cache misses; controller work stays on the stream path, which is proven. One sweep was discarded and is recorded as discarded: a `memtest` over banks 0 to 3, rows 0 to 2 overwrote three of the sixteen pattern rows the classifier compares against and the gate sweep taken next read 2.03%, so it was repeated after `prewrite` and only the clean 0.40% stands. The vendor control closes PCLK at 103.249 MHz with `0.000` TNS on all three clocks, the open flow at 113.17 MHz, and the image equals its Gowin build on all 306 tables. The desktop `tinytang.bin` was restored afterwards and answered `0x54`. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Build the controller on the stream-proven read path: a read command interface with a burst tag, the read-data aligner's trained boundary behind it, and a FIFO that returns one tagged burst per completed read, qualified first in simulation and then against sustained traffic over the full array; keep closed-page scatter reads as an open limitation to be explained before the AE350 takes cache misses to scattered addresses, and leave the `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context open.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_write/rd_check.v
- fpga/ddr3_write/tb_check.v
- fpga/ddr3_write/tb_pos.v
- fpga/ddr3_write/wr_core.v
- tools/ddr3_write_probe.py
- tools/sim_rd_check.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 52 COMMIT Unreleased 2026-10-24T18:40:00-07:00

#### Coming From:

Unreleased 35ed882

#### Purpose:

Establish whether LiteDRAM's control layer can carry TinyVCMI's controller in the open flow, and build the boundary pieces that port needs, before committing a cycle to either that path or a hand-written one.

#### Outcome:

The spike `tools/litedram_ctrl_spike.sh` instantiated LiteDRAM's core against a stub PHY providing only a `PhySettings` object and a DFI interface, and it generates, synthesises for GW5AST-138C and places at 1,958 LUT4, 883 DFF and 308 ALU cells, about 1% of the device; none of TOOL-025's three gaps reappears, because all three belong to the upstream PHY and its constraints rather than to the control layer. `tools/litedram_ctrl_gen.py` then emits the same core at this board's geometry, 8 banks, 15 rows and 10 columns, as one module with the DFI at its ports, and correcting one measurement mattered: LiteDRAM's own GW5 PHY sets `dfi_databits` to `(8 // nphases) * databits`, so 64 bits and not 32, and four phases then carry the 256 bits of one BL8 burst, which is what the hand-written PHY captures per PCLK. The PHY extraction is `fpga/ddr3_ctrl/ddr3_phy.v`, 928 body lines lifted unchanged from the hardware-proven `fpga/ddr3_write/top.v` with only the 17 boundary declarations promoted to ports, and it synthesises standalone. Two properties of that PHY shape the port: its write path broadcast one eight-bit pattern to all 32 DQ pins, so it is repointed at `ddr3_wdata`, a burst fan-out whose pattern mode keeps the old behaviour bit-identical and whose permutation a one-hot walk over all 256 bits proves; and its read path locks rotations of a known pattern, so `ddr3_derot` applies that transpose and rotation statically from a frozen vector, letting calibration happen once at start-up through the pattern path that already measures 100% on streams. The remaining pieces are `ddr3_init.v`, the power-up in TOOL-019's order with a passing bench; `ddr3_sync.v`, the PLL wait, DLL release, LOCK, settle, HOLD-wrapped UPDNCNTL pulse and clock-stopped divider reset, also passing; `dfi_adapter.v`, which takes commands from any of the four DFI phases through a two-deep queue, slices a burst two beats per phase and raises `rd_underflow` when a burst never arrives, which is TOOL-030 made countable at a boundary; and `ddr3_cmdmux.v`, which gives the power-up the command pins until it is done and then the adapter, in the proven op encoding. Every bench caught at least one of my own errors before it reached RTL: single-bit command pins declared four bits wide, a ZQCL vector written in the wrong bit order twice, and two testbench assumptions that contradicted the proven design's contract. DM has no mask path yet. No image was written, nothing was packed, and the Tang was not accessed in this cycle; the hardware-proven designs are untouched, since `ddr3_phy.v` is an extracted copy and `fpga/ddr3_write/top.v` still carries its own inline wiring. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Build the controller top level that instantiates the seven verified pieces with the generated core, export the memory clock from the PHY for the core's `sys4x` domain, add the boot training pass that freezes the rotation vector and delays before the write path leaves pattern mode, then gate the whole design with simulation, nextpnr, a clean vendor control and the 306-table image comparison; the DM mask path and TOOL-030's scatter limitation remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_ctrl/ddr3_cmdmux.v
- fpga/ddr3_ctrl/ddr3_derot.v
- fpga/ddr3_ctrl/ddr3_init.v
- fpga/ddr3_ctrl/ddr3_phy.v
- fpga/ddr3_ctrl/ddr3_sync.v
- fpga/ddr3_ctrl/ddr3_wdata.v
- fpga/ddr3_ctrl/dfi_adapter.v
- fpga/ddr3_ctrl/tb_ddr3_cmdmux.v
- fpga/ddr3_ctrl/tb_ddr3_derot.v
- fpga/ddr3_ctrl/tb_ddr3_init.v
- fpga/ddr3_ctrl/tb_ddr3_sync.v
- fpga/ddr3_ctrl/tb_ddr3_wdata.v
- fpga/ddr3_ctrl/tb_dfi_adapter.v
- tools/litedram_ctrl_gen.py
- tools/litedram_ctrl_spike.sh
- tools/sim_dfi_adapter.sh

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 53 COMMIT Unreleased 2026-10-24T19:00:00-07:00

#### Coming From:

Unreleased ffc185a

#### Purpose:

Assemble the controller into a top level that can be placed, and find out what stands between this design and an image.

#### Outcome:

`fpga/ddr3_ctrl/top.v` instantiates the extracted PHY, the start-up sequencer, the JEDEC power-up, the command mux, the boot trainer, `rd_align`, the rotation latch, the static derotator, the write fan-out, the DFI adapter and the generated LiteDRAM core, and it synthesises for GW5AST-138C with no warnings. Three pieces are new under it. `ddr3_rotlatch.v` freezes the four rotations only when every lane has trained, holds pattern mode until then, and clears on rearm; its bench caught a test that contradicted the design's own rule — a rearm that leaves the training mask set is correctly re-frozen at once. `ddr3_train.v` runs the boot pattern pass, one ACTIVATE, the configured WRITEs, then READs with the gate open and `stream` asserted, ending on all-four-trained or on a timeout flag rather than hanging; its bench covers the converging path only, which is stated rather than implied. `ddr3_cmdmux.v` became three-tier: the power-up owns the command pins until it is done, the training pass until the rotations are frozen, and the controller after that; its bench covers all three, and it caught a real defect in my own edit, a `pins` register assigned from both a combinational decode and the clocked block, which silently turned an RD into an ACT on the bus. `tools/build_ddr3_ctrl.sh` generates the core, synthesises, routes eight seeds in parallel, keeps the best and packs with the declared DDR3 context. The gate then produced four findings. An unconstrained `heartbeat` output was removed rather than pinned. Nextpnr failed deterministically on one arc, `Net ddr.sys4x_clk has no route to the FCLK of phy.ck_ser (sink wire X0Y30/FCLKA)`, in all eight seeds. A warning census showed it was one problem counted 586 times on `adapter.pclk`, plus a `mclk` warning and, more seriously, `get_nets argument 'pclk' matched no objects`, which meant PCLK was unconstrained and every timing number from that build was worthless; `tools/build_ddr3_ctrl.sh` now fails on an unmatched clock constraint as the write build already did. Moving the PLL out of the PHY to make the memory clock a top-level net replaced the named arc with a generic routing failure and 586 repeated errors, so it was reverted and the named failure restored. In the nextpnr fork, widening `extend_dq_lane_fclk` to every IO tile with FCLK pips made nextpnr segfault, and narrowing it to the bank-7 rows produced a byte-identical bba because those rows are absent from `hclk_pips` altogether; both changes were reverted and the fork is clean, regenerating 95,407,417 bytes, with `check_dqs_site.py` passing six of six. The conclusion recorded in TOOL-032 is that bank-7 FCLK is a modelling gap rather than an extension. No image was packed, no bitstream was loaded, and the Tang was not accessed in this cycle. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Model bank 7's serializer FCLK in the nextpnr fork by creating the wire and pips for those tile types the way `create_dqs_bel` creates `DQS_FCLK`, rather than widening `hclk_pips`, and gate that change with `check_dqs_site.py`, `check_internal_net.py` and `check_arch_gen_deterministic.py` before any route attempt, since an inconsistent database appears as a segfault and not as a routing error; then re-run the eight seeds, add the training-timeout bench case and the DM mask path, and only then pack an image.

#### Files Modified:

- fpga/ddr3_ctrl/ddr3_cmdmux.v
- fpga/ddr3_ctrl/ddr3_phy.v
- fpga/ddr3_ctrl/ddr3_rotlatch.v
- fpga/ddr3_ctrl/ddr3_train.v
- fpga/ddr3_ctrl/tb_ddr3_cmdmux.v
- fpga/ddr3_ctrl/tb_ddr3_rotlatch.v
- fpga/ddr3_ctrl/tb_ddr3_train.v
- fpga/ddr3_ctrl/top.v
- tools/build_ddr3_ctrl.sh

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 54 COMMIT Unreleased 2026-10-24T19:20:36-07:00

#### Coming From:

Unreleased f54c8f3

#### Purpose:

Re-scope the DDR3 work away from the controller until isolated READs return their own data, by settling whether the scatter-read failure lives in the open flow or in the RTL and by tracing how the proven vendor controller drives each lane's read side.

#### Outcome:

At the user's direction the controller track of entry 53 was paused and its Next Steps superseded, because every passing read test streams one repeated pattern, which cannot show which READ a burst came from, while the only test that can, closed-page scatter (TOOL-030), fails. On the Tang the Gowin build of the classifier source, SHA-256 `4de328a1b9c4d4f11fffe89bfa5617fb246134b01cda44f64c2fa7a6e7c71cf6`, whose `rd_check.v` and `rd_align.v` copies are identical to the committed files and which had never been loaded for a scatter run, and the open image `c15996cbcd87b4c42e6939fdc7f1d6b5150ee70fbe36f9dc8953d062e8d7816d` were placed on the card as `ddr3_pos_vendor.bin` and `ddr3_pos.bin`, loaded with `tangload` in turn, answered core `0x56` and calibrated every lane; the Gowin build classified 0 of 59,705,132 READs at delay 1 and gate 2 and no more than 39 of 189,708 at any of the 32 gate positions, while the open build classified 5.6% in the same session, so the failure is in the RTL both flows share and not in the open flow. The new `tools/ddr3_scatter_sweep.py` then ran the open image over all 256 shared RCLKSEL, delay and gate settings, every earlier scatter run having left RCLKSEL at 0, and the best was 3.0% with the sampled RVALID and RBURST levels not following the pass rate. Failing READs mostly carried clean patterns of other rows, `0x57` most often, sometimes a different row per lane in one READ with lanes 0/1 and 2/3 paired, which is consistent with lanes delivering an earlier READ's burst and is recorded as a hypothesis. Offline, the new `tools/vendor_read_gate_trace.py` cut lane 0's READ cone out of Tang-PSX's vendor netlist and simulated it with Gowin's models: the vendor gate is the same four-clock window with the same bit order as this project's `(delay, k)` gate, but READ, RCLKSEL and HOLD are per lane, selected by a per-lane `read_i` and trained on RBURST sampled as a level, where this project shares one READ and one RCLKSEL across all lanes. Re-reading entry 53's build also overturned TOOL-032: `tools/build_ddr3_ctrl.sh` reuses the write image's constraints, nextpnr reported `Cell ddr_pll not found`, `dll not found` and `fdiv not found` as Info lines, placed the PLL at X1Y81 instead of X1Y27, and the routed write image reaches the same bank-7 sink through `X0Y30/FCLKA/HCLK00`, so no fork change is needed and the constraint fix is untested. TOOL-024, TOOL-030 and TOOL-032 were revised, TOOL-033 added, and `docs/ddr3-open-flow.md` gained the A/B, the trace and the routing correction. No image was built in this cycle, and the desktop core was restored and answered `0x54`. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Make `rd_check` compare each READ's capture per lane against the expected patterns of READs n to n-3, which either shows lanes consistently returning an earlier READ's burst, a read-FIFO pointer question for `RLOADN` and `RPOINT`, or rules it out; split READ and RCLKSEL per lane as the vendor does and add a per-lane RBURST level sampled at a PCLK rising edge and two falling edges; gate both in simulation and against the Gowin build, then bring one board session for approval. The acceptance gate before any controller work resumes is random isolated READs returning each address's own data at a fixed trained latency, measured with address-derived rather than repeated data; after that the controller resumes with its own constraint files and a build that fails on an unmatched `INS_LOC`, then the DM mask path. The `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/ddr3_scatter_sweep.py
- tools/vendor_read_gate_trace.py

#### Status:

- Build: N/A
- Deployment: PASS
- User Test: N/A

---

## 55 COMMIT Unreleased 2026-10-24T20:13:55-07:00

#### Coming From:

Unreleased 5c038ba

#### Purpose:

Measure on hardware which READ each lane returns for isolated READs and whether per-lane READ gates and RCLKSEL, as the proven controller drives them, make isolated READs return their own data.

#### Outcome:

`fpga/ddr3_write/rd_check.v` gained a lag classifier that records, per lane at the check offset, whether the lane holds its own READ's pattern, one of the three before it, or none, counting only READs whose four recent patterns are distinct; `wr_core.v` now drives each DQS block's `READ[3:0]` and `RCLKSEL[2:0]` from per-lane settings (commands `0x2C`, `0x2D`, `0x2E`, the old all-lanes commands unchanged), counts each lane's RBURST as a level sampled at a PCLK rising edge and two falling edges, and returns both in frame `0x2F`; `tools/ddr3_write.py` wires each lane's slices, `tools/ddr3_write_probe.py lag` and the new `tools/ddr3_lag_sweep.py` drive them. The checker bench gained two lag cases that a lags-swapped mutant fails, and the image bench checks 635 per-lane gates, per-lane RCLKSEL and the new frame, after a bench fault where requests sent faster than the core's replies were dropped was fixed by waiting out each reply; a host reboot interrupted one simulation run and it was repeated. The open image, SHA-256 `2360774bc9c45a40f0ef7db3148edd0f6603df33d822c5803bc7dbf15cc73b45`, closes PCLK at 126.98 MHz and equals its Gowin build on all 306 DDR3 tables, and that build, `a6822db8e33357a9abcdf1ad450643e7872871219106c7b083d7351cd4dd8bcf`, closes PCLK at 109.973 MHz with no negative slack. On the Tang both were loaded, answered `0x56` and calibrated. At period 8 and the old shared setting lanes differed sharply, lane 3 holding a recent READ's burst nearly everywhere with its answer stepping one READ per 8 offsets and lane 1 holding none; at period 40 the best lane held its own READ in 51% of READs at two offsets of every three and 3% at the third, and over all 256 per-lane delay, gate and RCLKSEL settings each lane's best own-READ share was 51.6, 51.4, 51.5 and 44.6% at different settings, never more, with the Gowin build reaching 51.2, 51.2, 51.1 and 50.0% in the same three-PCLK pattern. RBURST as a level followed the gate on every lane alike in the open build and read 0% in the Gowin build, so it is not yet a training signal. The FPGA was once found answering core 0 mid-session for an undetermined reason, and the image was reloaded and recalibrated before the period-40 runs. Tracing the proven controller's netlist then found the missing mechanism: each lane registers its deserializer word and its DQS `RVALID` once on PCLK and its read FIFO accepts the word only where that registered `RVALID` is high, while this project reads the deserializers on every cycle. TOOL-033 was revised, TOOL-030 annotated and TOOL-034 added, and `docs/ddr3-open-flow.md` gained the measurements. The desktop core was restored and answered `0x54`. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Bring for approval an RVALID-qualified capture: register each lane's `RVALID` beside its deserializer word as the vendor does, give `rd_check` and the lag classifier a per-lane word that updates only on cycles whose registered `RVALID` is high, behind a switch that leaves today's behaviour as the default, gate it in simulation and against the Gowin build, then repeat the period-40 lag sweep on the board; per-lane training on RBURST waits until that result is in. The acceptance gate before controller work resumes is unchanged: isolated random READs return each address's own data at a fixed trained latency, measured with address-derived data. The `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_write/rd_check.v
- fpga/ddr3_write/tb_check.v
- fpga/ddr3_write/tb_wr.v
- fpga/ddr3_write/top.v
- fpga/ddr3_write/wr_core.v
- tools/ddr3_lag_sweep.py
- tools/ddr3_write.py
- tools/ddr3_write_probe.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 56 COMMIT Unreleased 2026-10-24T21:26:22-07:00

#### Coming From:

Unreleased a634105

#### Purpose:

Make the read checker take each lane's word only on cycles whose RVALID is high, as the proven controller does, and measure on hardware whether isolated READs then return their own data.

#### Outcome:

`fpga/ddr3_write/rd_check.v` now registers each lane's deserializer word and RVALID before any selection and, behind command `0x29`, checks a word held from that lane's last RVALID-high cycle; frame `0x2F` grew to 126 bytes with each lane's RVALID-high count and the switch, and `tools/ddr3_write_probe.py lag --rvalid` and `tools/ddr3_lag_sweep.py --rvalid` drive it. The input register makes the checker's pipeline four deep, so every check offset from this entry on is one higher than the same arrival recorded before it, the classifier's positions formerly at 11 and 19 now at 12 and 20; the benches, the probe's `RC_PIPE` and the source comments follow. The Gowin control first missed PCLK at 99.363 MHz and no place or route option cleared it in the new `tools/ddr3_write.py --vendor-sweep`; registering the inputs first, giving each comparator pair of the rotation search its own copy of the pin-0 word and handing the checker a registered copy of the refresh counter brought the default build to 104.469 MHz with no negative slack. An image-bench failure turned out to be the bench sampling idle state during a refresh's tRFC wait, and the bench now allows 2 us. The checker bench's new case holds a burst valid for one PCLK in 300 of 300 READs and fails all 300 without the hold. The open image, SHA-256 `bb809c5b80dc83b3d26c15776e679431c6974c76cad2233baa6cfae7d93e5605`, closes PCLK at 110.93 MHz and equals its Gowin build, `d55b007fb30b598e5fc1400f3f3f2c1627a1600954c5c2b6ef8c5b5febc3c750`, on all 306 DDR3 tables. On the Tang, after a first calibration that stopped with no reply and left the FPGA unconfigured, a reload held for 30 s idle and calibrated cleanly; at period 40 lanes 1 and 2 went from at most 51.5% own-READ to 100.0% with the hold, and over 256 per-lane settings lanes 0, 1 and 2 each reached 100.0% at their own RCLKSEL 3 settings while lane 3 reached 60.4%, every full score with that lane's RVALID high two cycles in three. Applied together, lane 1 held 100% but lanes 0 and 2 did not, and lane 2's RVALID share changed between read sessions at identical settings, so the right setting is fixed per session rather than per lane. The Gowin control at the old shared setting reached at most 17%. TOOL-035 was added and `docs/ddr3-open-flow.md` gained the measurements. The desktop core was restored and answered `0x54`. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Bring for approval a cycle that puts each lane's DQS read FIFO pointers into a known state at the start of every read session, after tracing the proven controller's `u_init_rmove_mod` and `rpoint`/`wpoint` handling from its netlist, then repeat the RVALID-held per-lane sweep across several sessions to show that one per-lane setting holds; lane 3's 60% ceiling is examined there. Only then does per-lane training get designed, against the unchanged acceptance gate of isolated random READs returning each address's own data at a fixed trained latency with address-derived data. The `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open.

#### Files Modified:

- docs/ddr3-open-flow.md
- fpga/ddr3_write/rd_check.v
- fpga/ddr3_write/tb_check.v
- fpga/ddr3_write/tb_pos.v
- fpga/ddr3_write/tb_wr.v
- fpga/ddr3_write/wr_core.v
- tools/ddr3_lag_sweep.py
- tools/ddr3_write.py
- tools/ddr3_write_probe.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---
