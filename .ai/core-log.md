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
