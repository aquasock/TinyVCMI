## 1 COMMIT Unreleased 2026-10-30T18:49:10-07:00

#### Coming From:

Unreleased af0d7a7

#### Purpose:

Open the active log after the project's first rollover, at the user's direction, with the live state of the open DDR3 milestone in one place.

#### Outcome:

Entries 1 to 92 were archived as `archived_logs/core-log-2026-10-30T18-49-00-07-00.tar.gz` (93,954 bytes, 92 entries) and the active log was cleared, which puts the rollover at the user's request rather than at the 100-entry limit; the archive holds the whole history of the project from its first reference library to entry 92, and therefore its detail is behind a file that policy gates behind user approval. At commit `af0d7a7` TinyVCMI is an open-flow port of VCMI to the Tang Console 138K, target GW5AST-LV138PG484AC1/I0 revision C, intending to run the engine on the hard AE350, and the first milestone is a DDR3 interface built only by Yosys, nextpnr-himbaechel and Apicula, with vendor output used as a measurement oracle and never shipped. What is qualified today is the pad set and the primitive model on paper and on silicon: the open-flow DDR3 image equals the vendor build on all 306 DDR3 tables, the PHY initializes the device and reads its MPR pattern on all 32 DQ, and the controller image trains itself at start-up, hands the bus to `ddr3_ctl` and tests the whole 1 GiB, with the qualified I/O boundary registering only the outbound side on PCLK's falling edge (TOOL-052) and the design built as 469 `DFFN` and 18 `DFFNS` on the CLKDIV with no LUT on a clock. What blocks the milestone is the write path: the doubled-write image's test failures belong to the doubled write (TOOL-059) and not to the mask or the address fold, the controller's write alignment is trained rather than leveled, `tools/ddr3_fill_attrib.py` shows the fill is exact at the trained `d 1 b 2` at every pace (TOOL-057), and the gap added to separate the doubling from the mask byte has never been measured because the netlist carrying it fails its own write-alignment search, `error 3` at 390 trials with no alignment, on two independent placements, while the netlist before the gap trains `d 1 b 2` in 422 trials on the same board in the same session (TOOL-060). Also open are the residual of about 1.1 per cent with one write per word, a 106.19 MHz placement that reads nothing at any read offset, the read path's 8 PCLK marginality, the state-4 hang in `S_RDW`, the write image's untimed boundary, the mid-calibration stall, the `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context, with the whole-top simulation on hold and a capped legaliser budget and a PHY-only fuse reference deferred by the user. The board is powered from the host's 5 V over USB-C OTG (BRD-002), its cooldown is a live variable that must be stated as recalled or not on every result, the console is the TinyTang CDC device on `/dev/ttyACM0` with the FPGA UART on `/dev/ttyUSB1`, and the desktop it must be returned to is `tinytang-lora.bin`, 4,447,414 bytes, not `tinytang.bin`, because both answer core ID `0x54` and only the `-lora` build keeps the operator's LoRa working (PROT-002); `tinytang-abi16-open.bin` remains unidentified. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this handoff's six sections, ordering, prose, Status values, numbering and the active-log capacity after the rollover.

#### Next Steps:

Make the gap netlist's write-alignment search pass before anything is measured with the gap: read `R_FILL`'s `S_WG` path beside `wpass_now` and the burst recorder and state which cycle a word's second write occupies at a gap of zero, make zero structurally the old path by holding the second write off inside the existing state rather than through a new state and counter, then gate it on `tools/sim_ddr3_ctrl.sh` with its six mutants, the 469/18 boundary check, the 306-table image check and a seed sweep that refuses anything under 100 MHz. Confirm on the board that the rebuilt image trains `d 1 b 2` in about 422 trials and hands over, and only then run the mode-0 exponent at gaps of 4, 8, 16, 32 and 64 against the no-gap reading of about 31 and 37 per cent on two lanes, with a mode-2 reading beside it for the residual. The first place to look for the mechanism is the seed-5 instrumented image of the mask cycle, which reported the same `error 3`, 390 trials and 3 CALIB pulses and was never explained. Every board result records the supply as the USB-C OTG rail from the host and states the cooldown as recalled or not, and every cycle ends by restoring `tinytang-lora.bin`.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 2 COMMIT Unreleased 2026-10-30T19:36:30-07:00

#### Coming From:

Unreleased 2f215ec

#### Purpose:

Settle whether the gap netlist's failure to train belongs to the gap or to the placement, and correct the attribution the previous cycle committed.

#### Outcome:

The attribution was wrong and the gap is exonerated, on source and on the board. Reading the sources first: `wr_core.v`, which holds `R_FILL` and the write-alignment search, is byte for byte the same file in the passing image and in both failing ones, and everything the gap added -- `S_WG`, `gap_cnt`, `tm_gap` and the two command decodes -- sits inside `ddr3_bist` and `ctrl_glue`, where `ddr3_bist` is held in reset by `ld_rst = !ctrl_own` until hand-over, its outputs are muxed away unless `ctrl_own`, `dm` is forced to zero meanwhile, and `S_WG` is entered only at a non-zero `tm_gap` whose reset value is zero, so that logic is inert during training and an image that fails to train cannot be evidence about it. The board then settled it without a rebuild: seed 18 of the gap netlist failed as seeds 13 and 16 had, `error 3` at 390 trials with no write alignment and 3 CALIB pulses a lane, and the pre-gap images already on hand split -- `a8f043bb` (seed 4) trained `error 0` to `d 1 b 2` in 422 trials with 7 CALIB pulses a lane and handed over, while `f5dbcd51` (seed 6) failed the same way the gap images do, `error 3`, lanes locked `0111`, 2,304 trials and no write alignment, with 3 CALIB pulses on the three lanes that locked. The netlist before the gap therefore fails to train on some of its own placements, so the gap is not needed to explain the post-gap failures: three gap placements failed and two of three pre-gap placements trained, a sample too small to say either netlist trains less often, and 3 CALIB pulses a lane after training marks a failing image while 7 marks a passing one in both netlists. TOOL-060 was revised in place twice, once to withdraw the claim that placement was excluded and once more with this A/B, `docs/ddr3-open-flow.md` carries the corrected section and the result, and entry 92's Outcome stands as settled history with this entry naming what it superseded. At the operator's direction the card was also cleared of its DDR3 experiment images: 47 `ddr3_*` files were deleted, taking it from 77 files to 30, with every desktop and every unrelated core kept, which removed the three images entry 92 had put there. Two behaviours of the board were learned in doing it -- its `tdsh` rejects a glob with `parse error (-28)`, and its working directory is `/root`, so a bare filename under `rm -f` silently deletes nothing and the first two batches did exactly that before the paths were made absolute -- and the CDC link dropped once during the work, the board re-enumerating from USB device 054 to 059 and its console port returning. The board was restored to `tinytang-lora.bin` and answered core ID `0x54`; every load in this cycle was powered from the host's 5 V over USB-C OTG and the cooldown was not recalled. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Stop treating training failure as a gap defect and treat it as a placement lottery in both netlists, with 3 CALIB pulses a lane as the fast board-side marker of a bad placement: an image that trains reports 7 and hands over, one that does not reports 3. Getting back to the gap measurement therefore needs a gap image that trains, which means building further seeds rather than changing the gap's logic, and the question of why one placement trains and another does not is worth its own cycle because it has now cost three images of one netlist and one of the other. Once a gap image trains and hands over, run the mode-0 exponent at gaps of 4, 8, 16, 32 and 64 against the no-gap reading of about 31 and 37 per cent on two lanes, with a mode-2 reading beside it for the residual. The residual with one write per word, the 106.19 MHz placement that reads nothing at any offset, the read path's 8 PCLK marginality, the read stream's frame, the state-4 hang in `S_RDW`, the write image's untimed boundary, the mid-calibration stall, the `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open, `tinytang-abi16-open.bin` is still unidentified, the whole-top simulation stays on hold, and the user has deferred a capped legaliser budget and a PHY-only fuse reference.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: N/A
- Deployment: PASS
- User Test: N/A

---

## 3 COMMIT Unreleased 2026-10-30T21:56:21-07:00

#### Coming From:

Unreleased 1829ef5

#### Purpose:

Find what a placement changes when it turns a training image into one that hands over, so the DDR3 controller stops depending on luck.

#### Outcome:

The question moved twice and neither answer was the one the cycle started from. A hedge sweep of seeds 25 to 30 was launched first: seed 25 closed at `pclk` 100.40 MHz with 469 `DFFN` and 18 `DFFNS`, no LUT on a clock and all 306 tables equal (`.bin` SHA-256 `ddeaaf176f13f4bff44ff7e9d595583074db0713630532b2407463699e4fcffa`), seed 30 was refused at its timing gate, and seeds 26 to 29 were still routing when the cycle closed; seed 25 was loaded on the board and failed to train exactly as the others had, `error 3` at 390 trials with no write alignment and 3 CALIB pulses a lane, so the gap netlist stands at none of four placements while the netlist before it trained on two of three with the same training RTL. The first hypothesis was the untimed I/O boundary (TOOL-050), and `tools/bnd_delay.py` was written to measure it, a `--post-route` hook reporting `getNetinfoRouteDelay` from each DDR3 cell to its fabric sink and back; on four placements whose `pclk` reproduced their images exactly, inbound capture over 512 crossings gave medians of 1.926 and 1.728 ns for the two passing placements, 2.454 for the failing one of the same netlist and 2.163 for the failing gap placement, so the failing placement of one netlist is worse than both passing ones by 27 to 42 per cent at the median while the other failing placement sits between them, and route delay does not separate training from not training (TOOL-061). Reading the trainer then corrected two things this project had misread (TOOL-063): `error 3` is the write-alignment search failing and not framing, since 1 and 2 are the framing errors and every failing image reports 3, and the per-lane CALIB count is `lane_cal`, the index of the search's RCLKSEL sweep where the lane locked, so 3 against 7 is lock latency and not framing effort; the framing header also claims a rule the code does not implement, pin 0 being the unconditional reference and `tgt_w` never read. What the failing placement does instead is readable in the search's own checker: on seed 13 frame 0x27 held its pattern on 11 READs of 6,261, with its first failure at bank 0, row bit 1, burst 44, expecting `0x13` and finding all four lanes holding `6b 94 6b 94 6b 94 6b 94`, pins agreeing and odd pins the inverse of the even, the word a rotation of fill pattern 26, `0x5B`. That makes the failure functional rather than a marginal eye, and the attempt to name the source address ended in the instrument: the fill chooses one of thirty aperiodic necklaces by a fold of the address, so 16,384 locations share 30 patterns, `0x5B` covers 512 of them, and inside bank 0 row 1 alone bursts 28, 37, 95 and 102 all produce it, which means a failing search cannot say where its data came from and a wrong burst matches by accident about one time in thirty (TOOL-062). TOOL-061, TOOL-062 and TOOL-063 were added and `docs/ddr3-open-flow.md` gained the section. The board was restored to `tinytang-lora.bin` and answered core ID `0x54`, the diagnostic and sweep images were removed from the card, and every load was powered from the host's 5 V over USB-C OTG with the cooldown not recalled. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Give the fill's per-burst data enough distinguishing bits to name a location, as the memory test's `gen()` was given in TOOL-054, because until then neither a failing search nor a passing one can be trusted: 512 locations produce the same word and a wrong burst matches about one time in thirty. Then re-read a failing search's frame 0x27 and say which address the data came from, which is the question this cycle could not answer. The gap netlist's none-of-four against the pre-gap netlist's two-of-three is also worth settling, since the RTL that trains is byte-identical and the difference would have to come from synthesis, but three and four placements are too few to claim a rate difference. The gap has still never been measured, the residual with one write per word, the 106.19 MHz placement that reads nothing at any offset, the read path's 8 PCLK marginality, the read stream's frame, the state-4 hang in `S_RDW`, the write image's untimed boundary, the mid-calibration stall, the `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open, `tinytang-abi16-open.bin` is still unidentified, the whole-top simulation stays on hold, and the user has deferred a capped legaliser budget and a PHY-only fuse reference.

#### Files Modified:

- docs/ddr3-open-flow.md
- tools/bnd_delay.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 4 COMMIT Unreleased 2026-10-30T22:01:49-07:00

#### Coming From:

Unreleased 9454209

#### Purpose:

Test the placement reading entry 3 committed by loading the last training candidate the hedge sweep produced, and correct the record if it does not hold.

#### Outcome:

It does not hold for the gap netlist, and the correction is the cycle's result. Seed 28 closed at `pclk` 100.37 MHz with 469 `DFFN` and 18 `DFFNS`, no LUT on a clock and all 306 tables equal (`.bin` SHA-256 `d357be25503e1322a953dde3c51f51cc20f6fbed175a68747b7271883bd12630`), and on the board it failed exactly as seeds 13, 16, 18 and 25 had: `error 3` after 390 trials, lanes locked `1111`, 3 CALIB pulses a lane, windows of 53, 57, 46 and 50 taps centred at 28, 30, 25 and 27. Five independent placements giving the same trial count, the same lock state and the same windows to the tap is not a lottery, and the netlist before the gap fails in a different mode when it fails at all, seed 6 taking 2,304 trials and leaving lane 3 unlocked. The cause had to be synthesis, and counting cells in the two netlists shows it: with `wr_core`'s source byte-identical, Yosys moved about 1,400 descriptions between types inside its cone, LUT3 from 6,597 to 5,906, LUT4 from 11,137 to 11,561, MUX2_LUT5 from 2,915 to 2,349 and DFF from 14,388 to 14,390, while the whole design lost 796 cells and gained 1,424 LUT4s, and the netlist closes lower at 100.4 to 102.5 MHz against 106 to 108. The gap's logic is therefore still not the cause, since it is inert during training, but the gap's change is, through a mapping every placement of this netlist inherits. Entry 3's placement framing is right for the pre-gap netlist and wrong for this one, and it is named as superseded here rather than rewritten. TOOL-064 records the determinism and the divergence, TOOL-060 is revised a third time so its capture reading points at TOOL-062 and TOOL-064 instead, and `docs/ddr3-open-flow.md` gained the paragraph. The board was restored to `tinytang-lora.bin` and answered core ID `0x54`, the seed-28 image was removed from the card, and every load was powered from the host's 5 V over USB-C OTG with the cooldown not recalled. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Measure the capture path in full rather than its route half only, since `IDES8_MEM`'s outputs and everything after them are untimed and a flatter mapping costs margin with no warning anywhere in the flow: extend `tools/bnd_delay.py` to add cell delay to the route delay it already reports, then run it on the gap netlist and the pre-gap netlist at the same seeds and see whether the lost margin is on that path. That decides whether the answer is to keep the training logic out of synthesis's reach, for example by making the gap a synthesis-time choice so the fill's mapping does not move, or to accept the slower mapping and buy the margin back. The gap has still never been measured, the residual with one write per word, the 106.19 MHz placement that reads nothing at any offset, the read path's 8 PCLK marginality, the read stream's frame, the state-4 hang in `S_RDW`, the write image's untimed boundary, the mid-calibration stall, the `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open, `tinytang-abi16-open.bin` is still unidentified, the whole-top simulation stays on hold, and the user has deferred a capped legaliser budget and a PHY-only fuse reference.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 5 COMMIT Unreleased 2026-10-30T22:35:57-07:00

#### Coming From:

Unreleased e7b1e7b

#### Purpose:

Settle whether the gap netlist's deterministic training failure comes from the netlist or from the seed, with a matched pair, and hand the live state to the next agent when the session ended.

#### Outcome:

The matched pair was attempted and not obtained, and the cycle was stopped at the operator's direction for the night. The plan was to build the pre-gap netlist at a seed where the gap netlist closes and fails to train, which first had to avoid seed 4, already refused at 99.50 MHz in the earlier sweep, so seed 13 was chosen where the gap netlist closes at 102.48 MHz. That build failed its own gate: `pclk` reached 97.98 MHz against the 100 MHz constraint, nextpnr refused the design and no image was written, so the seed is good only for the gap netlist and the pair has to be made at another. Seeds 18 and 28, where the gap netlist closes at 101.72 and 100.37 MHz, were launched in parallel and were stopped in placement at the operator's direction when the session ended; their directories hold only a `nextpnr.log` each and no routed design. The pre-gap netlist used for this is synthesised from commit `a01b18c` into `/tmp/pre/ctrl.json` by the same Yosys command `tools/build_ddr3_ctrl.sh` runs, and the driver that places, packs with `--ddr3-context`, checks the image and writes the raw file is `build/gap/pre_seed.sh`; both are outside the repository, and `/tmp` will not survive a reboot, so the next session should regenerate the netlist from `a01b18c` rather than rely on them. Nothing in the repository changed in this cycle beyond project control. The board was not left as it is required to be: its FPGA answers core ID `0x02` on `/dev/ttyUSB1` at 2 Mbaud and the TinyTang console is not enumerated, so the desktop is not loaded and `tangload` cannot reach it until the board is power-cycled, after which `tinytang-lora.bin` must be loaded and `0x54` confirmed (PROT-002, BRD-002). The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Power-cycle the Tang first, confirm the TinyTang console enumerates as `ffff:5454` on `/dev/ttyACM0`, load `tinytang-lora.bin` and check it answers `0x54` before anything else, because the board is currently on a core that answers `0x02` and the operator's LoRa is down. Then finish the matched pair: regenerate the pre-gap netlist from commit `a01b18c` with the Yosys command in `tools/build_ddr3_ctrl.sh`, place it at seeds 18 and 28 where the gap netlist closes, pack it with `--ddr3-context`, write the raw image and load it — if the pre-gap netlist trains at a seed where the gap netlist fails, the netlist is conclusively the cause and the fix is to keep the fill's mapping stable, by making the gap a synthesis-time constant instead of a live input; if it also fails, the record needs a third correction and the placement reading returns. The image it produces is not checked against a vendor reference, because the committed vendor `probe.fs` was built from post-gap sources, so say that plainly when it is loaded. The gap has still never been measured, the residual with one write per word, the 106.19 MHz placement that reads nothing at any offset, the read path's 8 PCLK marginality, the read stream's frame, the state-4 hang in `S_RDW`, the write image's untimed boundary, the mid-calibration stall, the `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context remain open, `tinytang-abi16-open.bin` is still unidentified, the whole-top simulation stays on hold, and the user has deferred a capped legaliser budget and a PHY-only fuse reference.

#### Files Modified:

None.

#### Status:

- Build: FAIL
- Deployment: NOT RUN
- User Test: N/A

---

## 6 COMMIT Unreleased 2026-11-22T10:29:23-07:00

#### Coming From:

Unreleased 0a53ff0

#### Purpose:

Bring the README's current state up to the DDR3 milestone recorded in this log, at the operator's request during a documentation pass across the TinyTang ecosystem.

#### Outcome:

The README's current state listed only two offline checks that never touch the Tang, written before the controller ran on the board. It now says, from entry 1's summary of the milestone, that the open-flow DDR3 image matches the vendor build on all 306 DDR3 tables, that the PHY initialises the device and reads its MPR pattern on all 32 DQ, and that the controller image trains at start-up, hands the bus to `ddr3_ctl` and tests the whole 1 GiB, and that the write path blocks the milestone, with the gap netlist failing its own write-alignment search where the netlist before it trains, as entries 2 to 5 record; it points to this log for the live state. The two offline checks are kept below it. Nothing was built or deployed. The core-syntax audit was run: `.ai/core.md` and `.ai/core-syntax.md` were re-read, `.ai/core.md` was confirmed unchanged, the complete `.ai/` diff was inspected and holds only this entry, and this entry was validated as number 6 of 100 with six canonical sections in order, a one-sentence Purpose, prose in Outcome and Next Steps, only eligible paths in Files Modified and allowed Status values.

#### Next Steps:

Entry 5's next steps stand: finish the matched pair that settles whether the gap netlist or the seed causes the training failure.

#### Files Modified:

- README.md

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 7 COMMIT Unreleased 2026-11-22T23:33:28-07:00

#### Coming From:

Unreleased 2dab51e

#### Purpose:

Finish the matched pair entry 5 left unmade, to settle whether the gap netlist's identical training failure belongs to its synthesis or to placement, and hand the result to the next agent.

#### Outcome:

The pair split one seed each way, and the deterministic-synthesis reading of entry 4 is withdrawn. The pre-gap netlist was resynthesised from commit `a01b18c`, whose synthesised sources differ from HEAD only in `fpga/ddr3_ctrl/ctrl_glue.v` and `ddr3_bist.v`, with every other source at HEAD and the Yosys command of `tools/build_ddr3_ctrl.sh`; it reproduced TOOL-064's cell counts exactly and passed the 469 `DFFN` and 18 `DFFNS` boundary check, and was placed at seeds 16, 18, 25 and 28, where the gap netlist closes and fails. Seed 28 was refused at `pclk` 90.50 MHz, and seeds 16, 18 and 25 closed at 100.57, 103.39 and 102.07 MHz with all 306 DDR3 tables equal to the vendor reference. The images were loaded to SRAM in one-wire mode with `openFPGALoader -c ft2232` and read with `tools/ddr3_write_probe.py --port /dev/ttyUSB1 --baud 2000000 ctrl`: seed 25 (`.fs` SHA-256 `9a0f836343cffc99f4b72c585760b465a6845c838b3de322e908a0fe3bc66a44`) trained `error 0` to `d 1 b 2` in 422 trials with 7 CALIB pulses a lane and handed over, on two loads, where the gap netlist fails, while seed 18 (`1251b81c9ef08aa7540d049e5138959b29986d60a9f69ff992576ddc44ad72ee`) failed exactly as the gap netlist does, `error 3` after 390 trials, lanes locked `1111`, 3 CALIB pulses a lane, windows within a tap of the gap netlist's, and its checker holding the pattern on 58 of 6,260 READs with every lane returning `a4 5b` repeated. The identical numbers are therefore what any failed write-alignment search reports and not a fingerprint of one netlist, the remaining difference is a rate of none of five placements against two of four that these samples cannot establish, and the pair could never have isolated the netlist, since placement depends on the netlist and the two differ by 796 cells, so an equal seed is not an equal placement. On seed 25 the memory test after hand-over failed almost every word on every lane at read offset 7, like TOOL-059's 106.19 MHz placement, and was not pursued. TOOL-064 was revised in place, TOOL-060 gained a fourth revision note, and `docs/ddr3-open-flow.md` gained the section The matched pair. Separately, the card's desktop set changed: `/root/cores/console138k` now holds one desktop, `tinytang.bin` at 4,558,518 bytes, answering `0x54`, with `tinytang-lora.bin` and `tinytang-abi16-open.bin` gone, and the operator reports the LoRa split resolved, so PROT-002 was revised and the desktop to restore is `tinytang.bin`. Two driver faults were met and fixed outside the repository: entry 5's `build/gap/pre_seed.sh` passed `-d gw5a` to `gowin_pack`, which refuses a netlist built for `GW5AST-138C`, and it now passes `$gowin_family`, with `build/gap/pre_pack.sh` packing an already routed seed; the netlist and seeds are in `build/gap/pre`, which is not tracked. Every load was powered from the host's 5 V over USB-C OTG and the cooldown was not recalled. The board was not restored: it was left in one-wire mode with the seed-25 pre-gap image in SRAM, because returning to the desktop needs a cold power-up into two-wire mode that the operator had not yet made when the cycle was handed off. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Have the operator cold power-up the Tang into two-wire mode, confirm the TinyTang console enumerates as `ffff:5454` on `/dev/ttyACM0`, and check that the desktop answers `0x54`, loading `tinytang.bin` with `tangload` if it does not. Then give `wr_core`'s fill per-burst data with enough distinguishing bits to name a location, as the memory test's `gen()` was given in TOOL-054, because until a burst can name its address neither a failing search's wrong word nor a passing search can be trusted; re-read a failing search's frame 0x27 on a failing placement of either netlist, seed 18 of the pre-gap netlist being one, and say which address the data came from. Whether the gap netlist trains less often than the pre-gap netlist is a rate question needing many more placements of each, not a matched seed. The gap has still never been measured, seed 25's near-total test failure after hand-over joins the residual with one write per word, the 106.19 MHz placement that reads nothing at any offset, the read path's 8 PCLK marginality, the read stream's frame, the state-4 hang in `S_RDW`, the write image's untimed boundary, the mid-calibration stall, the `D108` unused-pin contradiction and the `is_mipi` bug outside the DDR context as open faults, the whole-top simulation stays on hold, and the user has deferred a capped legaliser budget and a PHY-only fuse reference.

#### Files Modified:

- docs/ddr3-open-flow.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 8 COMMIT Unreleased 2026-11-23T21:19:44-07:00

#### Coming From:

Unreleased aae4515

#### Purpose:

Return to the last controller image known to work, find why the open flow's controller images pass or fail by placement, and fix the cause rather than screen seeds.

#### Outcome:

Entry 7's plan was set aside for this one. The baseline, commit 59443aa, was checked out as a detached worktree in `build/baseline` and rebuilt byte for byte to eb59ee08 (`.fs` SHA-256 `38e6c2430260e66e8c273b0e7d51a26474510b38068b11051452643e535acaad`), which is nextpnr's default seed and not seed 1 as earlier read. It trained `d 1 b 2` in 422 trials and ran the memory test clean warm, and clean again from a cold start, the Tang unplugged at 09:25 and powered at about 10:01. Every baseline placement trains the same way, but after hand-over only 3 of 8 placements ran the test clean, the post-baseline mask path (B1) 0 of 5 and B1 with DM tied low 0 of 1, while boundary pinning, boundary route delays, a bitstream round-trip through Apicula's `gowin_unpack`, building without LUT RAM, a tighter `pclk` constraint and a slower memory clock neither explained nor cured it, as TOOL-067 records. Loading failing images repeatedly showed the failures are deterministic to the bit, and because 59443aa's test data is linear in the address each first error names the faulty DRAM address pins, A5 on baseline seed 2 and A7, A11 and A14 on B1 seed 1 (TOOL-066). The cause is TOOL-065: the nextpnr fork's chipdb has timing for LUT4 and none for LUT1, LUT2 or LUT3, so every path through one of this netlist's 12,404 such cells was never timed, including the D input of every falling-edge boundary register and half of `ddr3_ctl`'s address bits. `tools/lut4ify.py` rewrites each as a LUT4 of the same function, verified on all 16 inputs of every cell, and fully timed the baseline closes `pclk` at 52.70 to 59.76 MHz and `core.rx.clk` at 43.5 to 47.6 MHz instead of the 100 to 108 MHz reported before, with `ddr3_ctl`'s command decision 7.49 ns over, `ddr3_bist`'s checker and log 6.70 ns over, training's slow paths up to 4.43 ns over, and `dfi_phy` and the boundary clean. `tools/ddr3_pin_boundary.py` and `tools/ddr3_pin_seed.sh`, which produced the pinning and seed results, are committed with it. TOOL-065, TOOL-066, TOOL-067 and DDR3-004, the last for the e-karge/gowin-ddr3 open-flow controller the user was told of, were added to `.ai/core-reference.md`, and TOOL-050 and TOOL-061 gained revision notes. Every load was made in one-wire mode with `openFPGALoader -c ft2232` and read with the probe at 2 Mbaud on `/dev/ttyUSB1`, powered from the host's 5 V over USB-C OTG; the first load after a cold power-up came up silent once and stuck in training once, each cured by reloading. The board was left in one-wire mode with the baseline default image in SRAM and the desktop not restored. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

The fix is in progress in the `build/baseline` worktree and is not yet committed: `ddr3_ctl.v` decides each command into a registered plan and updates its banks, timers and request FIFO from that plan, one command per two PCLK; `ddr3_bist.v` checks each word over three registered stages and compares a re-read's difference instead of its data; and `tools/sim_ddr3_ctrl.sh` drops the tRP and WRITE-to-READ mutants, which the two-PCLK command spacing makes invisible. All simulations pass. Build it through `tools/lut4ify.py` at several seeds, fix training's remaining slow paths if the design still does not close `pclk` at 100 MHz and `core.rx.clk` at 50 MHz fully timed, load only images that close, and expect every placement to run the memory test clean; then add LUT1 to LUT3 arcs to the fork's `gowin_arch_gen.py` in a separate build so `lut4ify` is no longer needed, carry the fixes onto main's post-baseline sources, and restore the desktop with a cold power-up into two-wire mode.

#### Files Modified:

- tools/lut4ify.py
- tools/ddr3_pin_boundary.py
- tools/ddr3_pin_seed.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 9 COMMIT Unreleased 2026-11-24T00:04:35-07:00

#### Coming From:

Unreleased b538390

#### Purpose:

Fix the controller logic that entry 8 found untimed and too slow, so that its memory test runs clean on every placement rather than on some.

#### Outcome:

The controller now passes on every placement tried. Main's controller and training sources, their generator, the build and simulation scripts and the probe were set back to the tested 59443aa baseline, withdrawing the B-series changes from `c65f546` onward, which never ran clean on the board and stay in history to be re-applied one at a time, and three fixes were made on that base. `ddr3_ctl.v` decides each command into a registered plan and updates its banks, timers and request FIFO from the plan, keeps its open-row table in registers, streams a same-row READ or WRITE one PCLK behind the last by a same-row bit set as each request is queued, and never issues a READ or WRITE two PCLK after the last, because the PHY returns such a READ as the bus between two bursts (TOOL-068). `ddr3_bist.v` checks each word over three registered stages, compares a re-read's difference in four registered quarters and writes each log entry a PCLK after judging it. `tb_ctrl.v` now fails any controller that issues the two-PCLK spacing, which the simulation's PHY model reads correctly and so missed twice, and `tools/sim_ddr3_ctrl.sh` drops the tRP and WRITE-to-READ mutants, which the plan's spacing makes invisible; every simulation passes. Two intermediate designs failed on the board identically on every placement: one command per two PCLK failed every odd in-order word, and streaming without the spacing rule failed 1,627 words a lane in 45 s, all random READs hitting an open row in another bank. The images were built with `tools/build_ddr3_ctrl.sh`, then `tools/lut4ify.py` on its `ctrl.json`, then `tools/ddr3_pin_seed.sh` at seeds 1 to 5 with `TINYVCMI_CTRL_JSON` set to the rewritten netlist and `TINYVCMI_PNR_EXTRA=--timing-allow-fail`; fully timed they close `pclk` at 74.17, 82.37, 79.74, 78.96 and 73.56 MHz, short of 100 with their worst paths in the training's `wr_core`, `core.rx.clk` at 42.90 to 46.60 MHz and `mclk` short on four, and all 306 DDR3 tables equal the vendor reference (seed 1 `.fs` SHA-256 `56de00d3294dca6886ebb787ce002bcb65c6c16d9f5683bf9d74fc6052cc4399`). Loaded in one-wire mode with `openFPGALoader -c ft2232`, each load confirmed `DONE`, every seed trained `error 0` to `d 1 b 2` in 422 trials and ran 81 passes of the 1 GiB test in 60 s, about 2.82e9 words checked, with no error on any lane, and the user accepted the result. One earlier load had failed with `JTAG init failed` while the previous image kept running and answered the same core ID, so a load is now accepted only when `openFPGALoader` reports `DONE`; every other load whose loader output was kept, all but the repeated-load fingerprints of TOOL-066, did. TOOL-068 was added to `.ai/core-reference.md` and TOOL-065 gained a revision note. The Tang was power-cycled once by the user's relay script during the cycle, about a second off, powered from the host's 5 V over USB-C OTG, and was left in one-wire mode with seed 5 in SRAM and the desktop not restored. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Close timing fully: pipeline the training's slow paths in `fpga/ddr3_write/wr_core.v` and the `mclk` read-burst toggles in the generated top until every clock meets its target with every path timed, then wire `tools/lut4ify.py` into `tools/build_ddr3_ctrl.sh` and drop `--timing-allow-fail`, and add LUT1 to LUT3 arcs to the nextpnr fork's `gowin_arch_gen.py` in a separate build so the rewrite is no longer needed. Confirm the margin on the board with a long soak, a cold start and the frequency sweep the user offered with the SDG1032X, after checking a clock-capable header pin and a safe 3.3 V hook-up. Then re-apply the B-series one change at a time on this base, the write mask path first, building each through the full timing check and testing every image on several placements, and restore the desktop with a cold power-up into two-wire mode.

#### Files Modified:

- fpga/ddr3_ctrl/ctrl_glue.v
- fpga/ddr3_ctrl/ddr3_bist.v
- fpga/ddr3_ctrl/ddr3_ctl.v
- fpga/ddr3_ctrl/dfi_phy.v
- fpga/ddr3_ctrl/tb_ctrl.v
- fpga/ddr3_ctrl/top.v
- fpga/ddr3_write/tb_wr.v
- fpga/ddr3_write/wr_core.v
- tools/build_ddr3_ctrl.sh
- tools/ddr3_write.py
- tools/ddr3_write_probe.py
- tools/sim_ddr3_ctrl.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 10 COMMIT Unreleased 2026-11-24T10:50:00-07:00

#### Coming From:

Unreleased 0d3bce3

#### Purpose:

Close the controller image's timing with every path timed, starting from a full list of failing endpoints, and checkpoint the work at the user's direction before the first image that meets timing exists.

#### Outcome:

The cycle began with entry 9's seed 1 (`.fs` SHA-256 `56de00d3294dca6886ebb787ce002bcb65c6c16d9f5683bf9d74fc6052cc4399`) loaded in one-wire mode as the first configuration after the user's cold power-up at 08:40, powered from the host's 5 V over USB-C OTG with the unpowered time before it not recalled: it trained `error 0` to `d 1 b 2` in 422 trials with 7 CALIB pulses a lane, handed over and ran 741 passes of the 1 GiB test in about 10 minutes with no error on any lane. Each JTAG load now takes about 3 min 50 s at 6 MHz or 2 MHz alike, a USB-latency limit that appeared with the host's reboot at 07:10; three loads were aborted as hangs before that was understood, leaving the FPGA erased and unconfigured, and the fourth completed with `DONE`. Because nextpnr reports one path per clock pair, `tools/ddr3_sta.py` was written to list every failing endpoint from a post-route dump (TOOL-065's revision note), and it showed that entry 9 misplaced the worst `pclk` paths: they were in `ddr3_ctl`'s decision, `hit` and timers, `ddr3_bist`'s `cmd_valid`, `rd_check`, `rd_align` and `wr_core`'s command FSM, while `core.rx.clk` failed almost entirely in `wr_core`'s link decoder. The fixes so far register the link's and sequencer's commands before `exec_cmd`, which the write-image bench shows as 15,308 READs where HEAD issues 15,320 and which a run with only `wr_core.v` at HEAD restores; make `ddr3_seq`'s `pass_now` from its registered parts a clock later; give `ddr3_ctl` registered per-bank zero flags for every timer, a parallel row compare for `hit`, per-bank timer updates and lookup arithmetic in place of carry chains; give `ddr3_bist` registered `a_last` and `r_last` flags, a `rroom` without an adder and one-hot log selects; pipeline `rd_check`'s `pos_range` by a PCLK and look up `ck_older`'s earlier patterns a stage early; register the read-burst edge ahead of the `mclk` toggle in `tools/ddr3_write.py`; and drive ctrl_glue's bus mux from seven `ctrl_own` copies instantiated as `DFF` primitives, because Yosys merged seven behavioural copies into one flop (TOOL-069). A one-stage pipeline of `rd_align`'s measurement was tried, failed `tools/sim_rd_align.sh` because `stream` and `dq_d` are timed against `dq_q`, and was reverted. Every simulation gate passes, `ddr3_ctl` and `ddr3_bist` carry simulation-only invariants that fail on any flag that disagrees with its compare, and the new `tools/sim_ddr3_lockstep.sh` runs both against commit `0d3bce3` for 4 and 3 million PCLK of random stimulus with no output differing, having first been shown to catch a planted timer error and a planted flag error. Built through `tools/lut4ify.py` with `--timing-allow-fail`, the first round of these fixes closed `core.rx.clk` at 62 to 66 MHz and `mclk` at 761 to 798 MHz with no failing endpoint and raised `pclk` from 73.6 to 82.4 MHz to 85.9 to 92.5 MHz on seeds 1, 3 and 5; the second round, with the `DFF` copies, the `ddr3_bist` flags, the timer rewrite and the `pos_range` pipeline, was still in placement when the user asked for this checkpoint, the `ck_older` change is in neither build, and no image of these sources was written for loading. The board was left in one-wire mode with entry 9's seed 1 in SRAM and the desktop not restored. TOOL-069 was added and TOOL-065 gained a revision note. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Read the second round's seeds with `tools/ddr3_sta.py`, then keep fixing the `pclk` endpoints that remain until every clock meets its target fully timed: `wr_core`'s command FSM into the generated top's `addr`, `ba` and command registers, the FIFO advance in `ddr3_ctl` whose 283-bit loads put long routes on `fq_n` and `nxt_v`, `rd_align`'s measurement without added latency, and whatever the second round leaves; check every change with the simulation gates and `tools/sim_ddr3_lockstep.sh`. Then wire `tools/lut4ify.py` into `tools/build_ddr3_ctrl.sh` and drop `--timing-allow-fail`, load only images that close, confirm on several placements with a long soak and a cold start, and only then take the frequency sweep, the LUT1 to LUT3 arcs in the fork's `gowin_arch_gen.py` (whose `ALU` arcs also omit `I2`, not yet checked against this design) and the B-series re-application, and restore the desktop with a cold power-up into two-wire mode.

#### Files Modified:

- fpga/ddr3_ctrl/ctrl_glue.v
- fpga/ddr3_ctrl/ddr3_bist.v
- fpga/ddr3_ctrl/ddr3_ctl.v
- fpga/ddr3_ctrl/tb_ctrl.v
- fpga/ddr3_ctrl/tb_lock_bist.v
- fpga/ddr3_ctrl/tb_lock_ctl.v
- fpga/ddr3_ctrl/top.v
- fpga/ddr3_write/rd_check.v
- fpga/ddr3_write/top.v
- fpga/ddr3_write/wr_core.v
- tools/ddr3_sta.py
- tools/ddr3_write.py
- tools/sim_ddr3_lockstep.sh

#### Status:

- Build: FAIL
- Deployment: NOT RUN
- User Test: NOT RUN

---

## 11 COMMIT Unreleased 2026-11-24T21:37:00-07:00

#### Coming From:

Unreleased d7f9f4a

#### Purpose:

Finish closing the controller image's timing at 100 MHz with every path timed, and confirm the closed image on the board.

#### Outcome:

The controller image now closes every clock with every path timed: round fourteen's seed 1 (`.fs` SHA-256 `56981a03543437999b7a63a7f16034038949a052db74d1eed59fe24bed2a3a0c`) meets `pclk` at 100.25 MHz, `core.rx.clk` at 62.84 MHz and `mclk` at 798.08 MHz with all 306 DDR3 tables equal to the vendor reference, and on the board it trained `error 0` to `d 1 b 2` in 422 trials with 7 CALIB pulses a lane, handed over and ran 734 passes of the 1 GiB test in 600 s with no error on any lane, loaded in one-wire mode with `openFPGALoader -c ft2232` reporting `DONE`, powered from the host's 5 V over USB-C OTG and warm, the board having been on since 08:40. Getting there needed the toolchain corrected as well as the design: the fork's chipdb generator, from upstream commit ccdc2f6f1, writes the LUT RAM's data-input setup arc as `DI[n` with no closing bracket, so nextpnr timed no path into a LUT RAM's data inputs and every earlier figure, the 96 to 99 MHz ones included, left them out (TOOL-070); at the user's direction a chipdb with that bracket and the LUT1 to LUT3 arcs of TOOL-065 was built beside a copy of the binary in `/home/vash/tools/nextpnr-tinyvcmi-arcs` by `tools/nextpnr_arcs.sh` from `tools/nextpnr_arcs.patch`, after the unpatched generator was shown to reproduce the installed chipdb byte for byte, and the installed toolchain and the fork were left untouched. The design changes, each with its source comment, make the training's address and bank a function of its one-hot state and step, since a DDR3 device reads them only with a command, with a simulation shadow of what `issue()` was given checked on every command; give the training's pauses one-hot return states, pipeline the fill data's word select, register its own word tests from `dq_q` a PCLK early, and give `rd_align` early compares (`PRE`), pre-rotation byte flags and registered `uniform`, `moved` and lock-count flags; in `ddr3_ctl` keep the FIFO entries' row and bank in registers and make the next PCLK's row compares from registers with the plan and the advances selecting last; and in `ddr3_bist` put the owed-read FIFO in LUT RAM, narrow `rcnt`, compare `d_same` per byte, mark a re-read's issue a PCLK later in log bit 37 and keep `a_last` and `r_last` without adders. Every simulation gate passes with the write image's counts unchanged at 808 ACTIVATE, 44,699 WRITE, 15,308 READ and 535 REFRESH and the sequencer's at 487 trials in 293,745 cycles, `tools/sim_ddr3_lockstep.sh` shows `ddr3_ctl` and `ddr3_bist` equal to commit `0d3bce3` on every output for millions of PCLK but log bit 37, a PCLK later as intended, `tb_align.v` now checks `rd_align` with `PRE` against itself without, and each new invariant was shown to fail on a planted error. Two tries were withdrawn: registering the memory test's write word put `gen()` behind the address adders, 4.7 ns over, and per-entry head compares in `ddr3_ctl` lowered the median seed. Placement refused up to five seeds of seven at 24 per cent utilisation until `--placer-heap-beta 0.7` (TOOL-071), and a delay-driven mapping, `abc9 -W 3000 -D 9000`, gave the closing seed where the default mapping did not (TOOL-072), with one netlist's seeds spreading about 10 MHz; `tools/ddr3_ctrl_sweep.sh` builds that way and `tools/ddr3_sta.py` now times block RAM outputs. A 96.14 MHz image (`77d2bb48101da99e7931d3dc512e7719f1909ac05d6290215d576fb59bf7cdc2`) had already trained the same way and run 744 passes clean. Two things are open: `tools/ddr3_sta.py` still reports 32 `pclk` endpoints failing on the closed image, the worst `ddr3_ctl`'s `m_n_r` by 1.50 ns, where nextpnr times the same registers inside the period, and the committed sweep script was regenerating the closed image from these sources to confirm it byte for byte when this entry was written. The board was left in one-wire mode with the closed image in SRAM and the desktop not restored. TOOL-070, TOOL-071 and TOOL-072 were added and TOOL-065 gained a revision note. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Confirm that `tools/ddr3_ctrl_sweep.sh` regenerated the closed image byte for byte, and find whether `tools/ddr3_sta.py` or nextpnr is right about `m_n_r`'s 32 endpoints, fixing whichever is wrong. Then qualify the closed image on the board with a cold start, which needs the user to leave the Tang unpowered and bring it up in one-wire mode, and with the frequency sweep the user offered with the SDG1032X after a clock-capable header pin and a safe 3.3 V hook-up are confirmed; build more seeds to learn how often the image closes, and fold the delay-driven mapping, the density setting and the patched nextpnr into `tools/build_ddr3_ctrl.sh` so that it refuses any image that does not close, dropping `--timing-allow-fail`. With the user's approval, commit `tools/nextpnr_arcs.patch` to the aquasock fork and report both generator faults upstream. After that, re-apply the B-series one change at a time on this base, the write mask path first, and restore the desktop with a cold power-up into two-wire mode.

#### Files Modified:

- fpga/ddr3_ctrl/ddr3_bist.v
- fpga/ddr3_ctrl/ddr3_ctl.v
- fpga/ddr3_ctrl/tb_lock_bist.v
- fpga/ddr3_write/rd_align.v
- fpga/ddr3_write/rd_check.v
- fpga/ddr3_write/tb_align.v
- fpga/ddr3_write/wr_core.v
- tools/ddr3_ctrl_sweep.sh
- tools/ddr3_sta.py
- tools/nextpnr_arcs.patch
- tools/nextpnr_arcs.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 12 COMMIT Unreleased 2026-11-24T23:08:00-07:00

#### Coming From:

Unreleased b65d5f8

#### Purpose:

Confirm that the 100 MHz controller image reproduces from the repository, measure how often its netlist closes across seeds, and qualify it from a cold start.

#### Outcome:

The closed image reproduces and runs from cold. `tools/ddr3_ctrl_sweep.sh`, run as committed with the patched nextpnr, regenerated seed 1's netlist and its image byte for byte (`.fs` SHA-256 `56981a03543437999b7a63a7f16034038949a052db74d1eed59fe24bed2a3a0c`). Twelve further seeds of the same netlist and settings, 6 to 17, closed `pclk` at 87.89 to 97.14 MHz and none at 100, so over seventeen seeds the median is 93.11 MHz, the mean 93.60 MHz with a standard deviation of 3.30 MHz, and one seed in seventeen closes; `core.rx.clk` passed on all, and `mclk` on all at as little as 402.74 MHz. Their critical paths were `ddr3_ctl`'s `m_n_r` from the FIFO read pointer on five seeds, `wr_core`'s pause bookkeeping (`wcount`, `wnx`, `we_n`) on four, `rd_check` on two and `ddr3_bist`'s `rcnt` enable on one, and the user chose to leave the closure's robustness, and the frequency sweep, until there is another reason to build. For the cold start the user left the Tang unpowered for over 40 minutes and brought it up in one-wire mode at 22:50:33, powered from the host's 5 V over USB-C OTG; the closed image, the first configuration since power-up, was loaded with `openFPGALoader -c ft2232` reporting `DONE` at 22:54:55, trained `error 0` to `d 1 b 2` in 422 trials with 7 CALIB pulses a lane on the first attempt, handed over and ran 734 passes of the 1 GiB test in 600 s with no error on any lane. Cold, the DLL's STEP read `0x2c` against `0x2b` warm, and lane 0 trained to RCLKSEL 4 with 39 passing taps centred at tap 21 against RCLKSEL 5 with 54 centred at 29 warm, the narrowest window of the four. With this the first milestone's evidence is complete: an open-flow DDR3 controller that meets 100 MHz with every path timed, trains itself and tests the whole array cleanly warm and cold; no release was cut, the user not having asked for one and `.ai/core.md`'s Releasing section being empty. The board was left in one-wire mode with the closed image in SRAM and the desktop not restored. TOOL-072 gained a revision note. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

The next milestone is the AE350 running code from DDR3: re-apply the write mask path (B1) on this base first, one change at a time and checked with the simulation gates and `tools/sim_ddr3_lockstep.sh`, then bridge the AE350's 64-bit RAM AHB port to the controller's 256-bit port so the array is the CPU's main memory at `0x80000000`, and prove it from the CPU side by loading a program over the PROT-001 path and running a memory test and a miss-cost measurement against AE350-003. Images are built with `tools/ddr3_ctrl_sweep.sh` and loaded only if they close; whether `tools/ddr3_sta.py` or nextpnr is right about `m_n_r`, making closure robust across seeds, folding the build settings into `tools/build_ddr3_ctrl.sh`, the frequency sweep and committing `tools/nextpnr_arcs.patch` to the aquasock fork with an upstream report wait for the user, as does any release. Restore the desktop with a cold power-up into two-wire mode when the board is next needed for it.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 13 VERSION v0.1.0 2026-11-24T23:29:32-07:00

#### Coming From:

Unreleased 554aba8

#### Purpose:

Release TinyVCMI 0.1.0, the open-flow DDR3-800 milestone, at the user's direction and on terms the agent chose because `.ai/core.md`'s Releasing section is empty.

#### Outcome:

Version 0.1.0 marks the first milestone: the Tang Console 138K's 1 GiB of DDR3 at DDR3-800 with the DLL on, from a bitstream built only by Yosys, nextpnr-himbaechel and Apicula through the GW5AST-138's hard `DDRDLL`, `DQS`, `OSER8_MEM` and `IDES8_MEM`, with this project's own controller and training, every path timed at 100 MHz and the whole array tested clean warm and cold, as entries 11 and 12 record. The release is the annotated git tag `v0.1.0` on the commit carrying this entry, pushed to aquasock/TinyVCMI, and a GitHub release of the same name whose notes state what is proven and its limits and whose assets are the closed image as `tinyvcmi-ddr3-ctrl-v0.1.0.fs` (SHA-256 `56981a03543437999b7a63a7f16034038949a052db74d1eed59fe24bed2a3a0c`), the same image in TinyTang's packing as `tinyvcmi-ddr3-ctrl-v0.1.0.bin` (`88232771331c8759ab36ca40b6171d928112994dfb00c8e00e590b225603f8bd`) and their `SHA256SUMS`; no vendor output and no chipdb are shipped, the chipdb being reproduced by `tools/nextpnr_arcs.sh`. The README's current state now describes the milestone. Before the release the user asked whether anyone had done this before, and a web search, recorded in DDR3-005 with DDR3-004 revised, found open-flow DDR3 with an open controller on Lattice ECP5 for years and e-karge/gowin-ddr3's DLL-off 200 MT/s design on this board, but no public open-flow Gowin design through the hard DDR3 primitives or at DDR3-800, so the release claims the first known, not the first. `tools/ddr3_ctrl_sweep.sh` now recognises a `tools/nextpnr_arcs.sh` build by the chipdb beside its binary rather than by its path, and the patched toolchain directory was regenerated by that script, reproducing the same chipdb (`ec0b7e93f94bdd93...`). Nothing was rebuilt or loaded; the board stays in one-wire mode with the closed image in SRAM and the desktop not restored. `.ai/core.md` was not changed: the user will write its Releasing section from what was done here. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Entry 12's next steps stand for 0.2.0, the AE350 running code from DDR3: the write mask path first, then the AE350's RAM AHB port bridged to the controller and proven from the CPU side; the user's own work on VCMI proceeds alongside. The user is to fill `.ai/core.md`'s Releasing section.

#### Files Modified:

- README.md
- tools/ddr3_ctrl_sweep.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 14 COMMIT Unreleased 2026-11-25T00:58:51-07:00

#### Coming From:

v0.1.0 88f1e2d

#### Purpose:

Re-apply the write mask path on the 100 MHz controller and prove on the board that masked bytes keep what they held, as the first step toward the AE350 running code from DDR3.

#### Outcome:

The controller now writes under a byte mask, and on the board every masked byte kept its old value and every unmasked byte took the new one. `ddr3_ctl` takes a 32-bit `cmd_wmask` beside `cmd_wdata`, where bit 4b + l suppresses beat b of lane l, and carries it through its FIFO, `nxt`, `cur` and the write holds beside the data to `dfi_wrmask`; `dfi_phy` turns it into each lane's eight DM beats with the same delay line and write-alignment shift as the data, `ctrl_glue` drives the DM pads from it only while the controller owns the bus, the training writing every byte, and `tools/ddr3_write.py` generates `top.v`'s DM boundary from it, so the boundary check in `tools/build_ddr3_ctrl.sh` now expects 469 `DFFN` and 18 `DFFNS`. `ddr3_bist` gains a masked pass, on with its `MASKPASS` parameter: after the full write it rewrites every word with the generator's exact inverse, `gen(a, s ^ 0x5e6cfce7)`, which the generator's linearity makes `~gen(a, s)`, under a mask drawn from the generator at seed `s ^ 0x7f4a7c15`, and the reads expect the merge, so a byte the mask gets wrong fails in all eight bits; its states 7 and 8 are named in `tools/ddr3_write_probe.py`'s report. `tb_ctrl.v`'s memory model now honours DM with the same shift as the data, its write fault moved to after word 100's masked write, and `tools/sim_ddr3_ctrl.sh` passes with 131,072 bytes masked and fails, as it must, the three new mutants that ignore DM, apply it a beat late or apply it on the next lane, beside the three old ones. `tools/sim_ddr3_lockstep.sh` shows `ddr3_ctl` with its mask tied low and `ddr3_bist` with `MASKPASS` 0 equal to commit `0d3bce3` on every output, and a second `ddr3_ctl` given each request's mask as a slice of its own data kept that slice equal to its DFI data over 286,395 WRITEs, a check shown to fail when the hold took its mask from `nxt` instead of `cur`. The write image's sources and generated top level are unchanged, as `tools/ddr3_write.py --check` confirmed, so its gates were not rerun. Sixteen seeds built with `tools/ddr3_ctrl_sweep.sh` and the patched nextpnr, the user making 16 parallel builds the hard limit, and four closed every clock with every path timed against one in seventeen before, a difference within one netlist's seed spread: seed 3 at `pclk` 101.04, `mclk` 761.03 and `core.rx.clk` 59.79 MHz (`.fs` SHA-256 `9add97135331a6589bde503a551807bf36ff86df3bcb027847fa56bb73f7305f`), seed 4 (`b065ff3f17bdce8c84f1216645e8103a50785e07434bbd8be6f89be3a0c660ab`), seed 7 (`44d1b9f8945a710ce948c04cfb8a1183406391c1362fc2e7c43a8bacdac5224d`) and seed 15 (`506e791791bdcdd180f63bbb6bab796d6bbbab2c104a06f128a8886485cba983`), each with all 306 DDR3 tables equal to the vendor reference and the boundary on the CLKDIV. The user gave standing permission to deploy to the Tang and use the relay power cycle at will, warning that an ESP32 shares the tty ports, so the probe now addresses the Tang's UART by `/dev/serial/by-id/usb-SIPEED_USB_Debugger_2025041420-if01-port0`. Seed 3, loaded warm in one-wire mode with `openFPGALoader -c ft2232` reporting `DONE` at 00:45:31, trained `error 0` to `d 1 b 2` in 422 trials with 7 CALIB pulses a lane, handed over and ran 507 passes of the 1 GiB test with its masked pass in 600 s with no error on any lane and no failing word on any DQ; the first status showed 67,108,864 words written before the first read, the full write and the masked write, and the probe's samples found the masked write in 174 of 570, as often as the plain write. The fewer passes than entry 11's 734 are the masked pass's extra write, and the 32-bit written and checked counters saturate within the soak. The user chose not to cut 0.2.0 yet. The board was left in one-wire mode with seed 3's image in SRAM and the desktop not restored. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Bridge the AE350's 64-bit RAM AHB port to the controller's 256-bit port with byte masks, so that the array is the CPU's main memory at `0x80000000`, and prove it from the CPU side by loading a program over the PROT-001 path and running a memory test and a miss-cost measurement against AE350-003. Whether `tools/ddr3_sta.py` or nextpnr is right about `m_n_r`, robust closure, folding the build settings into `tools/build_ddr3_ctrl.sh`, the frequency sweep, committing `tools/nextpnr_arcs.patch` to the aquasock fork with an upstream report, and any release wait for the user. Restore the desktop with a cold power-up into two-wire mode when the board is next needed for it.

#### Files Modified:

- fpga/ddr3_ctrl/ctrl_glue.v
- fpga/ddr3_ctrl/ddr3_bist.v
- fpga/ddr3_ctrl/ddr3_ctl.v
- fpga/ddr3_ctrl/dfi_phy.v
- fpga/ddr3_ctrl/tb_ctrl.v
- fpga/ddr3_ctrl/tb_lock_bist.v
- fpga/ddr3_ctrl/tb_lock_ctl.v
- fpga/ddr3_ctrl/top.v
- tools/build_ddr3_ctrl.sh
- tools/ddr3_write.py
- tools/ddr3_write_probe.py
- tools/sim_ddr3_ctrl.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 15 COMMIT Unreleased 2026-11-25T02:16:48-07:00

#### Coming From:

v0.1.0 83a739a

#### Purpose:

Make the 1 GiB DDR3 the AE350's main memory by bringing TinyNES's AE350 system into this repository behind a new AHB-to-DDR3 bridge, with the UART handed from the DDR3 diagnostics to the AE350, stopping for an agent handoff at the user's direction once the first trial builds had run.

#### Outcome:

The AE350 image's sources are complete and pass simulation, and two trial builds have run, but no image has yet met timing and nothing has been loaded. Entries 12 to 14 put main memory at `0x80000000`, which is the A25's reset vector on the ROM port (AE350-001); main memory is at `0x40000000`, and because the RAM port is proven only from `0x40000000` to `0x7fffffff` (TinyNES DEV-011), the boot ROM's 64 KiB of block RAM sits at `0x7fff0000` and the DDR3 serves `0x40000000` to `0x7ffeffff`, 1 GiB less 64 KiB. New in `fpga/ae350_ddr3`: `ahb_ddr3.v`, the bridge, whose bus half takes `ahb_ram`'s one-at-a-time 64-bit transfers, answers a cache-line fill's other three doublewords from a one-line buffer, sends each write as one masked DDR3 write of its own lanes (mask bit k is the line's byte k) merged into the buffer on a hit, acknowledges writes at once, and crosses to its PCLK half by a toggle handshake, the PCLK half driving `ddr3_ctl`'s request port, which serves requests strictly in order; `ae350_sys.sv`, TinyNES f0f8501's `ae350_soc.sv` with the SDRAM, video, audio, pads and link removed, its NOBOOT report kept, ID `TV01`, held in reset until `run`; `ahb_ram.sv` with the DDR3 window; and TinyNES's `ahb_boot_rom.sv` and `exts_uart.sv` unchanged. `ctrl_glue` gains a `CPU` parameter and a second client port, `x_`, muxed onto `ddr3_ctl`; command `0x3C 0x50` hands the controller to it for good with the test held in reset, raises `cpu_run` 2^20 `sys_clk` later so `wr_core`'s reply leaves the pin first, and shows the hand-over in status bit 0; with `CPU` 0 the mux folds away, so the controller image only gains tied-off ports. `tools/ddr3_write.py` generates `fpga/ae350_ddr3/top.v`, `top.cst` and `open.sdc` as a third variant: the CPU PLL at `PLL_R[0]` (750 MHz core on CLKOUT1, 75 MHz `bus_clk` on CLKOUT0), the system as instance `soc`, the bridge's PCLK half as `xport` beside the controller, a UART mux on `cpu_run`, and `bus_clk` constrained to 13.333 ns. `firmware/` is TinyNES's boot ROM renamed to TinyVCMI (`tv_`, `tinyvcmi.h`): it tests the block RAM and the DDR3's lanes and address lines with the caches off and on, runs cached 64 KiB pattern tests at the bottom of the DDR3 and just below the block RAM, prints `TinyVCMI DDR3 OK 1024M-64K` and `TinyVCMI LOAD`, and keeps TinyNES's loader and magic; it builds with the xpack GCC under `-Werror`. `tools/ddr3_write_probe.py handover [--soak S] [--listen S]` sends the hand-over and prints the AE350's UART. The repository is now GPL-3.0-only (`LICENSE`, README), which the user chose after VCMI was confirmed GPL-2.0-or-later and its bundled FuzzyLite GPL-3.0. Gates: `tools/sim_ae350_ddr3.sh` drives `ahb_ram` and the bridge with a pipelined AHB master against a behavioural request port at 74.99 and 100.14 MHz and passes 33,730 reads and 29,939 writes, 8,063 WRAP4 bursts and 520 refusals, 19,090 of 31,474 DDR3 reads from the line buffer, while a mask on the wrong doubleword and an unmerged buffer each fail with thousands of errors; `tools/sim_ddr3_ctrl.sh` gains a run in which the hand-over gives the CPU port the real controller and PHY, and it wrote 1,280 words, masked and plain, and read 598 back with none wrong, every earlier run and mutant unchanged; `tools/sim_ddr3_lockstep.sh` still matches commit `0d3bce3`; `tools/ddr3_write.py --check` passes for all three images. The boundary check moved into `tools/ddr3_boundary_check.py`, and `tools/ddr3_pin_seed.sh` takes `TINYVCMI_CST`. `tools/ae350_ddr3_sweep.sh` builds the image as `tools/ddr3_ctrl_sweep.sh` builds the controller, with `NPNR_GOWIN_CLK_FIRST=bus_clk` checked in each log (DEV-016). The first trial, seed 1, used 26 per cent of the LUTs, 24 per cent of the flip-flops and 52 block RAMs, with the boundary intact and all 306 DDR3 tables equal to the vendor reference, but reached `bus_clk` 37.43 MHz and `pclk` 91.69 MHz: the placer had pulled `ahb_ram`, the UART registers and the bridge to the left beside `ddr3_ctl`, while the AE350 macro is fixed at X159 Y0, so the EXTS paths, which pass through the macro combinationally from `EXTS_HREADYIN` to `EXTS_HSEL`, spent 23 ns crossing the chip and back. The bridge was then split into its two clock halves, with only the handshake's registers between them, and `tools/ae350_place.py`, a `--pre-place` script, keeps every cell under `soc`, every cell clocked by `bus_clk` and the logic feeding only those within X105 to 181, Y0 to 50 (5,329 cells; block RAM rows at y 9, 27 and 45). The second trial, seed 1 (`.fs` SHA-256 `a84ea7d096f5ae95ecc7ec48e3c3372a054e9f00e439376ef1ffba5d552f11d6`), reached `bus_clk` 68.92 MHz, `pclk` 94.49 MHz, `core.rx.clk` 58.61 MHz and `mclk` 548.55 MHz, all tables again equal. Its `bus_clk` critical path starts at the system's reset register and runs through a register's asynchronous clear-to-Q arc (1.43 ns) before 9.2 ns of `ahb_ram` and bridge logic, now placed beside the macro; measured from that register's clock instead the path would be about 9.5 ns. Its `pclk` path runs from `ddr3_ctl`'s FIFO read pointer to `wr_core`'s status frame. The board still holds entry 14's seed 3 image in one-wire mode, the desktop not restored. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Close the AE350 image's timing, then load it. For `bus_clk`, find whether nextpnr's asynchronous clear-to-Q arc belongs in the path at all, the reset being released once while the bus is idle; if it does, register or synchronously release the resets that reach `ahb_ram` and the bridge, then shorten the remaining `ahb_ram` to bridge logic. For `pclk`, see whether the CPU port's mux in `ctrl_glue` or the new placement lengthened the controller's paths, or whether this is the usual seed spread, which a 16-seed `tools/ae350_ddr3_sweep.sh` run, the user's limit, will show. Load a closing image with `openFPGALoader -c ft2232`, address the UART as `/dev/serial/by-id/usb-SIPEED_USB_Debugger_2025041420-if01-port0` because an ESP32 shares the tty ports, check training and a soak with `tools/ddr3_write_probe.py ctrl`, then `handover --soak 60 --listen 15` and expect the boot ROM's `TinyVCMI DDR3 OK` and `LOAD` lines, or NOBOOT counts if the A25 does not start. The user has given standing permission to deploy and to use the relay power cycle. Then entry 16: load a full-array memory test and the miss-latency measurement over the loader, adapting TinyNES's `tools/load_ae350.py` to the DDR3 window, and compare with AE350-003's 570 cycles. The user is not cutting 0.2.0 yet. Robust closure, the STA disagreement on `m_n_r`, folding the settings into `tools/build_ddr3_ctrl.sh`, the frequency sweep and the nextpnr patch's upstream report still wait for the user.

#### Files Modified:

- LICENSE
- README.md
- firmware/boot/Makefile
- firmware/boot/crt0.S
- firmware/boot/link.ld
- firmware/boot/load.c
- firmware/boot/load.h
- firmware/boot/main.c
- firmware/common/memtest.c
- firmware/common/memtest.h
- firmware/common/uart.c
- firmware/common/uart.h
- firmware/include/tinyvcmi.h
- fpga/ae350_ddr3/ae350_sys.sv
- fpga/ae350_ddr3/ahb_boot_rom.sv
- fpga/ae350_ddr3/ahb_ddr3.v
- fpga/ae350_ddr3/ahb_ram.sv
- fpga/ae350_ddr3/exts_uart.sv
- fpga/ae350_ddr3/open.sdc
- fpga/ae350_ddr3/tb_ahb_ddr3.v
- fpga/ae350_ddr3/top.cst
- fpga/ae350_ddr3/top.v
- fpga/ddr3_ctrl/ctrl_glue.v
- fpga/ddr3_ctrl/tb_ctrl.v
- fpga/ddr3_ctrl/top.v
- tools/ae350_ddr3_sweep.sh
- tools/ae350_place.py
- tools/build_ddr3_ctrl.sh
- tools/ddr3_boundary_check.py
- tools/ddr3_pin_seed.sh
- tools/ddr3_write.py
- tools/ddr3_write_probe.py
- tools/sim_ae350_ddr3.sh
- tools/sim_ddr3_ctrl.sh

#### Status:

- Build: FAIL
- Deployment: NOT RUN
- User Test: NOT RUN

---

## 16 COMMIT Unreleased 2026-11-25T11:13:34-07:00

#### Coming From:

v0.1.0 8a8f647

#### Purpose:

Close the AE350 image's timing on every clock and load it, so that the A25 boots and tests the DDR3 as its main memory on the board.

#### Outcome:

The AE350 image closes every clock with every path timed and the A25 runs from the DDR3, first configuration after a cold power-up. Entry 15's `bus_clk` critical path began at `ae350_sys`'s reset flop and ran through the asynchronous CLEAR of `ahb_ram`'s `sd_addr` and its 1.43 ns clear-to-Q arc before the bridge's line-buffer compare (TOOL-073), so every fabric register on `bus_clk` in `ae350_sys`, `ahb_ram`, the bridge's bus half, `ahb_boot_rom` and `exts_uart` now takes `resetn` synchronously, the reset generator keeping its asynchronous assert and synchronous release; under `soc` the netlist's 975 `DFFCE` and 13 `DFFPE` became `DFFRE` and `DFFSE`. Fifteen seeds of that netlist, built with `tools/ae350_ddr3_sweep.sh` and the patched nextpnr, closed `bus_clk` at 84.18 to 94.12 MHz against 75, but `pclk` at 84.90 to 97.68 MHz, median 92.22, with nine failing on `ddr3_ctl`'s `m_n_r` from the FIFO read pointer `fq_r` and three on `cmd_ready` decoded from `fq_n` into the requesters' enables, none on the bridge or the CPU port; seed 14 was stopped after about 70 minutes of routing once its netlist was superseded. At the user's choice the path was fixed rather than screened: `ddr3_ctl` now keeps the FIFO head's `{row, bank}` in a register, `head_br`, loaded at every edge with the entry `fq_r` will point to or the request written there at that edge, and registers `cmd_ready` from `fq_n`'s next value, each with a simulation invariant that failed on a planted mutant, the bypass removed and the ready made from the current count, the latter also as a lockstep mismatch on `ready`. Every gate passed: `tools/sim_ae350_ddr3.sh` with the counts and mutant failures of entry 15, `tools/sim_ddr3_ctrl.sh` with every mutant and the CPU port's 1,280 WRITEs and 598 READs with none wrong, `tools/sim_ddr3_lockstep.sh` equal to commit `0d3bce3` on every output, and `tools/ddr3_write.py --check`. Thirty-two seeds of the new netlist closed `pclk` at 87.56 to 100.28 MHz, median 96.41 (TOOL-072's revision note), with no single path dominating the failures, and `bus_clk` at 82.73 to 95.22 MHz; seed 25 closed every clock, `pclk` 100.28, `bus_clk` 84.72, `core.rx.clk` 62.54 and `mclk` 798.08 MHz, with all 306 DDR3 tables equal to the vendor reference, the boundary at 469 `DFFN` and 18 `DFFNS` on the CLKDIV and `bus_clk` routed first (`.fs` SHA-256 `eb66c7aa2cfc6be19621407dc991073747f46b5933b9c9f43207f4ff748bb861`). The Tang had been off overnight; the user powered it on in one-wire mode at about 11:02, from the host's 5 V over USB-C OTG, because the relay script does not work on the first power-up from fully off, and seed 25 was loaded with `openFPGALoader -c ft2232` from 11:02:56 to 11:07:02 as the first configuration. The loader's closing line, where `DONE` is printed, was dropped by the agent's output filter, so the load was not confirmed by `DONE`; it was not repeated so as to keep the cold result, and the image's identity rests on the trained controller and the TinyVCMI boot ROM answering. It trained `error 0` to `d 1 b 2` in 422 trials with 7 CALIB pulses a lane, STEP `0x2b`, and its memory test ran with no lane error; `tools/ddr3_write_probe.py handover --soak 60 --listen 15`, which refuses to hand over unless the 60 s soak is clean, handed over, its soak summary line lost to the same filter, and the A25 printed `TinyVCMI AE350 C OK UNC=0491d418 CAC=001f6cbc`, `TinyVCMI DDR3 OK 1024M-64K CAC=0097997e` and `TinyVCMI LOAD` once a second, the boot ROM's block RAM, lane, address-line and cached pattern tests of the DDR3 all passing. The probe's `handover` asked for a status frame after listening, which the AE350's UART cannot answer, and now returns instead. The user did not test the board, accepted the agent's report, and set VCMI on HDMI as the proof that counts. The `ddr3_ctl` change also reaches the controller image of `fpga/ddr3_ctrl`, whose simulations pass but which was not rebuilt. The board was left in one-wire mode with seed 25 in SRAM and the boot ROM waiting for a program, the desktop not restored. TOOL-073 was added and TOOL-072 gained a revision note. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Load a full-array memory test and the miss-latency measurement over the boot ROM's loader, adapting TinyNES's `tools/load_ae350.py` to the DDR3 window, and compare the miss cost with AE350-003's 570 cycles; and confirm every load by `DONE` in the loader's unfiltered output. Then move toward the user's acceptance test, VCMI visibly running on HDMI, which needs a video path from the DDR3 (VIDEO-001, VIDEO-002) and the TinyTang link. If a later netlist closes `pclk` on too few seeds, the most frequent remaining paths are `ddr3_bist`'s retry and log decisions, then `rd_check`. Robust closure, the STA disagreement on `m_n_r`, folding the settings into `tools/build_ddr3_ctrl.sh`, rebuilding the controller image with the new `ddr3_ctl`, the frequency sweep, the nextpnr patch's upstream report and any 0.2.0 release wait for the user.

#### Files Modified:

- fpga/ae350_ddr3/ae350_sys.sv
- fpga/ae350_ddr3/ahb_boot_rom.sv
- fpga/ae350_ddr3/ahb_ddr3.v
- fpga/ae350_ddr3/ahb_ram.sv
- fpga/ae350_ddr3/exts_uart.sv
- fpga/ddr3_ctrl/ddr3_ctl.v
- tools/ddr3_write_probe.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 17 COMMIT Unreleased 2026-11-25T11:27:09-07:00

#### Coming From:

v0.1.0 c049c6c

#### Purpose:

Prove the DDR3 from the A25's side with a loaded program that tests the whole array and measures what a cache miss costs, for comparison with AE350-003.

#### Outcome:

Every word of the array the A25 can be given passed and a miss costs 503 cycles. TinyNES's runtime came across as `firmware/rt` (`crt0.S`, `syscalls.c`, `link.ld`, `rt.mk`, `include/sys/dirent.h`, renamed to `tv_` and linked for the DDR3 from `0x40000000` to the block RAM at `0x7fff0000`, which holds the stack), `tinyvcmi.h` gained `tv_cycles64`, and TinyNES's `tools/load_ae350.py` became TinyVCMI's without its file service and link mode, defaulting to the Tang's UART by its `/dev/serial/by-id` path and discarding what arrives in its first second, because the boot ROM's text from while the port was closed arrives behind the open and the first run printed about 70 stale banners between `loaded` and `RUN`, where a stale `BAD` line would have failed a good run. `firmware/apps/ddr3_test` measures by Tang-PSX's memlat method, dependent loads along a random cycle of 32-byte lines (Sattolo), streamed loads and stored lines, then runs `tv_test_words` from the first MiB after the program to `0x7fff0000`, 1,022 MiB, a hashed address pattern and its inverse under two seeds, cached, with the D-cache written back and invalidated before each read; it builds under `-Werror`. On the board, entry 16's seed 25 image still in SRAM and the boot ROM at `LOAD`, it loaded 48,188 bytes in 0.35 s and reported, in core cycles, 3.2 for dependent loads within 16 KiB, 499.8, 503.0 and 503.1 over 256 KiB, 4 MiB and 64 MiB, 477.2 per streamed line and 662.6 per stored line with write-back, against Tang-PSX's 3.2, 568 and 570, 552 and 637 (AE350-004), then both seeds' passes with 0 failures in 102,950 ms each, `TinyVCMI DDR3 FULL OK 1022 MiB` and exit 0. Run again from the rebooted ROM with the loader's fix, it gave no stale text and the same figures to the tenth of a cycle with 0 failures. AE350-004 was added and BRD-001 gained a revision note. The board was left in one-wire mode with seed 25 in SRAM and the boot ROM waiting for a program, the desktop not restored; the user takes the agent's word for this result, VCMI on HDMI being their test. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Work toward the user's acceptance test, VCMI visibly running on HDMI. That needs an 800x600 video path scanning a framebuffer out of the DDR3 beside the CPU's traffic (VIDEO-001, VIDEO-002), which means a second client on `ddr3_ctl` with priority for scanout and an HDMI encoder in this open flow, the TinyTang link and input for keyboard and mouse (INPUT-002), and the VCMI port itself, starting from the source inventory GAP-004 asks for and the runtime's file and thread needs, with GAP-003's memory budget measured as subsets run. A first cycle should propose the video path's design and its memory bandwidth budget for the user's approval. Rebuilding the controller image with entry 16's `ddr3_ctl`, robust closure, the STA disagreement on `m_n_r`, the frequency sweep, the nextpnr patch's upstream report and any 0.2.0 release wait for the user.

#### Files Modified:

- firmware/apps/ddr3_test/Makefile
- firmware/apps/ddr3_test/main.c
- firmware/include/tinyvcmi.h
- firmware/rt/crt0.S
- firmware/rt/include/sys/dirent.h
- firmware/rt/link.ld
- firmware/rt/rt.mk
- firmware/rt/syscalls.c
- tools/load_ae350.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 18 COMMIT Unreleased 2026-11-25T18:42:38-07:00

#### Coming From:

v0.1.0 c8fe27e

#### Purpose:

Put a 1280x720 picture on HDMI from a 32-bit frame buffer in the DDR3, drawn by the A25, as the video path VCMI will draw into.

#### Outcome:

The AE350 now shows 1280x720 at 60 Hz on HDMI from the DDR3 and the user saw the picture right (VIDEO-003). The user set 1280x720, TinyTang's resolution, as VCMI's target, an 800x600 Pmod VGA output being left for later, and approved a 32-bit XRGB8888 frame buffer, which is VCMI's own surface format. New in `fpga/ae350_ddr3`: `dvi_tx.v`, a DVI 1.0 transmitter of this project's own, its TMDS encoders in two registered stages feeding four OSER10s, the clock lane one of them as TinyNES DEV-018 requires; `video_ddr3.v`, whose `vid_fetch` on PCLK reads each line's 160 words into an eight-word flip-flop FIFO with Gray pointers, asking no further ahead than the FIFO has room for, and whose `vid_pix` on the pixel clock runs CEA-861 720p, asks for the next line at each line's start, writes two pixels a clock into block-RAM line buffers with both ports on the pixel clock (TinyNES's rule for this chip), takes BASE at the first blank line and counts LATE lines; `ddr3_arb.v`, the video before the CPU onto `ctrl_glue`'s CPU port, with a registered request, a one-entry video slot so the fetcher's ready is a register, and a tag FIFO routing each returning word; and `exts_video.sv`, CTRL, STATUS, FRAMES, BASE, LATE and ID at `0xe8010000`, beside `exts_uart` in `ae350_sys`. `tools/ddr3_write.py` generates the HDMI clocks, pins and wiring, `tinyvcmi.h` gained the registers and the runtime's heap now stops below 16 MiB kept for frame buffers at `0x7f000000`. Gates: `tools/sim_ae350_ddr3.sh` adds `tb_video.v`, which checked every pixel of three frames (2,764,800) across two page flips with CPU traffic beside them, decoded every TMDS symbol back to its pixel or sync with the disparity bounded, saw no late line after the first frame, and fails mutants of the arbiter's tags, the pixel pairs and the disparity's sign; `tools/sim_ddr3_ctrl.sh` adds a run with `ddr3_arb` and `vid_fetch` on the real `ddr3_ctl` and PHY model, 40 lines of 160 words with none wrong beside the CPU port's 1,280 writes and 598 reads with none wrong; every earlier run and mutant passes. Building it took most of the cycle. Every one of 49 placements of the first netlist failed routing, its final error naming the HDMI serial clock into an OSER10 or a ground tie into `hdmi_pll27`'s CLKFB, which led through a clock order, a free column at x 181, the stock nextpnr binary and a pixel-side placement region before the global router's own messages showed the cause: the fork lets only one CLKDIV clock onto the global network (TOOL-074), so the DDR3's `pclk` or a CLKDIV pixel clock lost every sink. The pixel clock now comes from `hdmi_pll`'s CLKOUT0 (VCO / 20) with the serial clock on CLKOUT1, no CLKDIV; it still reaches no global route from PLL_R[3] and runs on general routing (TOOL-075). `tools/ae350_place.py` now keeps the pixel side's 2,897 cells beside the HDMI bank and all other logic out of x 181, and `tools/ae350_clock_check.py`, run on every seed by `tools/ae350_ddr3_sweep.sh`, fails an image whose AE350 clock taps are not on GB10 (TinyNES DEV-016), whose pixel clock uses an unmeasured bridge set, or whose video block RAM is on two clocks or not in a 9-bit width; the empty set of general routing was accepted as measured after the user's test. Of 13 finished seeds of the final netlist, `pclk` reached a median of 94.30 MHz, the video slot having moved the worst path to `wr_core`'s pause bookkeeping, and seed 3 closed every clock, `pclk` 100.87, `bus_clk` 86.28, `core.rx.clk` 61.01, `mclk` 761.03 and `pix_clk` 96.88 MHz, no hold violation reported, all 306 DDR3 tables equal to the vendor reference and the boundary at 469 `DFFN` and 18 `DFFNS` (`.fs` SHA-256 `f9574b4fd4181f41e0dbe5bee59d493dcbf4da3abf76198ed2c57cd8015e48d7`). It was loaded warm in one-wire mode with `openFPGALoader -c ft2232` from 18:35:01 to 18:39:21; the agent's output filter again swallowed the loader's lines, so `DONE` was not seen, and the load is identified by a freshly started controller answering where the last image had been handed over. It trained `error 0` to `d 1 b 2` in 422 trials with 7 CALIB pulses a lane, STEP `0x2a`, soaked 51 passes clean in 60 s and handed over, and the boot ROM's tests passed. `firmware/apps/video_test` measured a full-frame fill at 105,197 us, drew the test screen and flipped a page every frame for 60 s, 3,601 frames and 3,601 flips with LATE 0, and exited 0; the user reported that everything passes and the video looks perfect. VIDEO-003, TOOL-074 and TOOL-075 were added. The board was left in one-wire mode with seed 3 in SRAM, the test screen up and the boot ROM waiting, the desktop not restored. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Start the VCMI port itself: inventory VCMI 1.7.5's dependencies and its threading and filesystem contracts (GAP-004) against the runtime in `firmware/rt`, plan an SDL video driver whose screen surface is the frame buffer at `0x7f000000`, and decide with the user how the Heroes III data files reach the DDR3 and how TinyTang's keyboard and mouse frames (INPUT-002) reach the AE350, which needs a link mode this image does not have yet; propose that plan for approval before building. A whole-screen redraw costs 105 ms of memory traffic, so redraw strategy matters from the start. Confirm every load by `DONE` in the loader's raw output saved to a file. Still open and waiting for the user: closure robustness, now led by `wr_core`'s pause bookkeeping, a heat test of the HDMI picture, rebuilding the controller-only image with entry 16's `ddr3_ctl`, the STA disagreement on `m_n_r`, the frequency sweep, the nextpnr patch's upstream report and any 0.2.0 release.

#### Files Modified:

- firmware/apps/video_test/Makefile
- firmware/apps/video_test/main.c
- firmware/include/tinyvcmi.h
- firmware/rt/link.ld
- fpga/ae350_ddr3/ae350_sys.sv
- fpga/ae350_ddr3/ddr3_arb.v
- fpga/ae350_ddr3/dvi_tx.v
- fpga/ae350_ddr3/exts_video.sv
- fpga/ae350_ddr3/open.sdc
- fpga/ae350_ddr3/tb_video.v
- fpga/ae350_ddr3/top.cst
- fpga/ae350_ddr3/top.v
- fpga/ae350_ddr3/video_ddr3.v
- fpga/ddr3_ctrl/tb_ctrl.v
- tools/ae350_clock_check.py
- tools/ae350_ddr3_sweep.sh
- tools/ae350_place.py
- tools/ddr3_write.py
- tools/sim_ae350_ddr3.sh
- tools/sim_ddr3_ctrl.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 19 COMMIT Unreleased 2026-11-25T19:48:24-07:00

#### Coming From:

v0.1.0 59573a7

#### Purpose:

Hand the project to the next agent at the user's direction, with the live state after entry 18 in one place.

#### Outcome:

No source changed; this entry records the state entry 18 left. TinyVCMI at `59573a7` is an open-flow port of VCMI to the Tang Console 138K whose AE350 runs from the 1 GiB DDR3 through this project's own controller (entries 11 to 17) and now shows 1280x720 at 60 Hz on HDMI from a 32-bit frame buffer at `0x7f000000`, drawn by the A25 and confirmed by the user (VIDEO-003). The image to use is seed 3 of the entry-18 netlist (`.fs` SHA-256 `f9574b4fd4181f41e0dbe5bee59d493dcbf4da3abf76198ed2c57cd8015e48d7`, in the untracked `build/ae350/v6/s3`), rebuilt with `TINYVCMI_PIX_TRIAL` unset and `NEXTPNR_HIMBAECHEL=/home/vash/tools/nextpnr-tinyvcmi-arcs/nextpnr-himbaechel tools/ae350_ddr3_sweep.sh OUT SEED...`, which synthesises, places each seed with `tools/ae350_place.py`'s regions and runs `tools/ae350_clock_check.py`; the last seed of that sweep, 8, finished after entry 18 at `pclk` 99.28 MHz, failing, so one seed of fourteen closes every clock. The board path is one-wire mode: load the `.fs` with `openFPGALoader -c ft2232`, saving its output unfiltered to a file and accepting the load only on `DONE`, check training and soak with `tools/ddr3_write_probe.py --port /dev/serial/by-id/usb-SIPEED_USB_Debugger_2025041420-if01-port0 --baud 2000000 ctrl`, hand over with `handover --soak 60 --listen 5`, then load programs with `tools/load_ae350.py`, of which `firmware/apps/ddr3_test` and `video_test` exist on the runtime in `firmware/rt`. The relay script power-cycles the Tang into one-wire mode, but from fully off the user must switch it on by hand first. The board is in one-wire mode with seed 3 in SRAM, the test screen up and the boot ROM waiting for a program, the desktop not restored. The user judges the port by VCMI running on HDMI and takes the agent's board evidence for intermediate steps. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and active-log capacity.

#### Next Steps:

Entry 18's next steps stand: propose, for the user's approval, the first VCMI port cycle, covering VCMI 1.7.5's dependency, threading and filesystem inventory against `firmware/rt` (GAP-004), an SDL video driver whose screen surface is the frame buffer, how the Heroes III data files reach the DDR3, and how TinyTang's keyboard and mouse frames (INPUT-002) reach the AE350 through a link mode this image does not yet have, keeping in mind that a whole-screen redraw costs the A25 105 ms. Closure robustness, led by `wr_core`'s pause bookkeeping, a heat test of the HDMI picture, rebuilding the controller-only image with entry 16's `ddr3_ctl`, the STA disagreement on `m_n_r`, the frequency sweep, the nextpnr patch's upstream report and any 0.2.0 release wait for the user.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 20 COMMIT Unreleased 2026-11-25T19:58:43-07:00

#### Coming From:

Unreleased 2679953

#### Purpose:

Plan the first VCMI port cycle that the recovery handoff asks for, settling VCMI 1.7.5's dependency, threading and filesystem questions against this project's runtime and fixing the video, asset and input approaches before any engine code is written.

#### Outcome:

No source, firmware or bitstream changed and no hardware ran. The inventory was read from the pinned engine in MiSTer-VCMI's `work/vcmi-src` (VCMI 1.7.5, commit `6901839`) and against `firmware/rt`, and it changes the shape of the port in three places. Single-player needs no network stack: `NetworkHandler::createInternalConnection` carries the client and local server's packets in memory, so TCP exists only for multiplayer and `boost::asio::io_context` is only an event loop. The engine's presentation path cooperates with the frame buffer: when the renderer names itself `software`, VCMI locks its one streaming `ARGB8888` texture and rebuilds the screen surface over that memory, so a driver whose texture lives in the DDR3 page and whose `RenderCopy` of it is a page flip removes both copies the MiSTer port had to fight. The AE350 cannot be preempted: `ae350_sys` drives `GP_INT` all zero and decodes no PLIC, so the 14 `std::thread` sites in 13 files, the oneTBB in 26 files and the `boost::filesystem` in 92 files must run on a cooperative runtime until the hard macro's machine timer is probed. The same read fixes the budget: 260 distinct `SDL_` symbols plus 49 `TTF_`/`IMG_`/`Mix_` symbols, `double` in 110 files and `float` in 91 with soft float on `rv32imac`, `boost::locale` and `boost::date_time` in one file each so they can be replaced rather than ported, and TinyTang's link negotiating 10, then 5, then 2 Mbaud within a 2047-byte frame, which is the only lever on the minutes a power cycle would cost to reload the game data. `docs/vcmi-port-plan.md` records all of it with citations, checks the 105 ms full-screen redraw against AE350-004's 662.6 cycles per stored line (115,200 lines is about 102 ms at 750 MHz), and proposes cycles B to F with three measurement gates: G0 a bench of fill, alpha, scale and 32-bit blits before any engine code, G1 SDL and the `tinyvcmi` driver on the board, G2 the main menu drawn and driven by the real keyboard and mouse. Five questions are left to the user: the canvas size, which data copy and delivery option, whether TinyTang firmware may change, whether audio is deferrable, and a frame-rate acceptance floor. `AE350-005`, `PROT-003`, `VCMI-003`, `VCMI-004` and `VCMI-005` were added, `GAP-004`'s close condition was narrowed to the runtime side, and the reference parses as YAML with 104 unique records. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and the active log's 20 of 100 entries.

#### Next Steps:

Cycle B starts on the user's approval of the plan and its open questions: the cooperative pthread shim, the archive-backed read-only file layer, the link-mode keyboard and mouse receiver, and the G0 bench app, ending with G0 numbers from the board that choose the canvas and predict the frame rate. Nothing in cycles C to F should begin before G0's result, and the still-waiting hardware items are unchanged: closure robustness led by `wr_core`'s pause bookkeeping, the HDMI heat test, rebuilding the controller-only image with entry 16's `ddr3_ctl`, the STA disagreement on `m_n_r`, the frequency sweep, the nextpnr patch's upstream report and any 0.2.0 release.

#### Files Modified:

- docs/vcmi-port-plan.md

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 21 COMMIT Unreleased 2026-11-25T20:05:54-07:00

#### Coming From:

Unreleased 33cf706

#### Purpose:

Stage the Heroes III game data the VCMI port will read onto the Tang's SD card and settle where it lives.

#### Outcome:

No source, firmware or bitstream changed and no hardware ran. `/run/media/vash/USB_HDD/homm3` held only the GOG "Heroes of Might and Magic 3 - Complete" 4.0 (3.2) installer, a `setup` executable, its 1.0 GB `.bin` and a redundant 4.0 (28739) to 4.0 (3.2) patch, so the game data was extracted with `innoextract 1.9` rather than copied. The card is now `/run/media/vash/TINYTANG/root/vcmi/data` holding `Data`, `Maps` and `Mp3`, the shape MiSTer's `/media/fat/vcmi/data` uses so the file layer's paths carry over: seven `Data` files (260 MiB: `H3bitmap.lod`, `H3sprite.lod`, `H3ab_bmp.lod`, `H3ab_spr.lod`, `H3ab_ahd.snd`, `H3ab_ahd.vid`, `Heroes3.snd`), 160 maps and 57 music tracks, 224 files and 345 MiB in all. Every one of the 224 was checked with `md5sum` against the installer's own MD5 with no mismatch. `VIDEO.VID`, 599 MiB, was deliberately left out as MiSTer leaves it out, since video playback is not built, and the `Mp3` tracks are staged but unused until audio lands, audio having been deferred. The card is vfat, so the port's file layer must not depend on case-sensitive names, which matters because the archives mix cases such as `AITHEME1.MP3` and `AITheme0.mp3`. The installers stay on the HDD and the data is not in the repository. `docs/vcmi-port-plan.md`'s Assets section now records the staged path, the counts and the verification, and its delivery options are reduced to two, boot-time images or a BL616 file service, with the arithmetic redone: 345 MiB is 30 minutes at 2 Mbaud, 9.6 at 5 and 4.8 at 10, and the 260 MiB of `Data` alone is 23 minutes at 2 Mbaud, which makes the file service the more attractive of the two. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and the active log's 21 of 100 entries.

#### Next Steps:

The asset-delivery question is the one still open, now narrowed to boot-time send against a BL616 file service, and cycle B should settle it before the file layer's shape is fixed. Cycle B's remaining work is unchanged and awaits the user: the cooperative pthread shim, the archive-backed read-only file layer, the link-mode keyboard and mouse receiver, and the G0 bench, whose result chooses the canvas and predicts the frame rate. The hardware items still waiting are also unchanged: closure robustness led by `wr_core`'s pause bookkeeping, the HDMI heat test, rebuilding the controller-only image with entry 16's `ddr3_ctl`, the STA disagreement on `m_n_r`, the frequency sweep, the nextpnr patch's upstream report and any 0.2.0 release.

#### Files Modified:

- docs/vcmi-port-plan.md

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 22 COMMIT Unreleased 2026-11-25T20:08:05-07:00

#### Coming From:

Unreleased 9dd165a

#### Purpose:

Follow the Heroes III data to the path the user moved it to and confirm the move kept it intact.

#### Outcome:

No source, firmware or bitstream changed and no hardware ran. The user moved the staged data from `root/vcmi/data` in entry 21 to `/run/media/vash/TINYTANG/root/media/vcmi/data`, which is the card's own convention, sitting beside `gb`, `gba`, `gbc`, `music`, `nes`, `reader`, `snes` and `ti89`; the old path no longer exists. All 224 files are present at the new path, `Data` with 7, `Maps` with 160 and `Mp3` with 57, 345 MiB, and every one was rechecked with `md5sum` against the installer's own MD5 from the GOG `.exe` with no mismatch, so the move across vfat lost nothing. No two staged files differ only by case, so nothing collided, but the card is case-insensitive and the archive this port will build is not, and the music already mixes conventions with `AITHEME1.MP3` beside `AITheme0.mp3`, so the plan now says the archive builder must store the card's exact names and that whether VCMI ever asks for one of these files in a different case is unmeasured. `docs/vcmi-port-plan.md`'s Assets section and its open questions name the new path. Entries 20 and 21 had been given timestamps a few minutes ahead of the clock, 20:02:11 against a commit at 19:58:43 and 20:09:37 against one at 20:05:54; both headers were corrected to their real commit times in this commit, and no other part of either entry changed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering, the active log's 22 of 100 entries, and that the three timestamps now ascend.

#### Next Steps:

The asset-delivery choice is still the open decision, boot-time images against a BL616 file service, and the file layer's shape waits on it. Cycle B's other work is unchanged and awaits the user: the cooperative pthread shim, the archive-backed read-only file layer, the link-mode keyboard and mouse receiver, and the G0 bench, whose result chooses the canvas and predicts the frame rate. The hardware items waiting are unchanged too: closure robustness led by `wr_core`'s pause bookkeeping, the HDMI heat test, rebuilding the controller-only image with entry 16's `ddr3_ctl`, the STA disagreement on `m_n_r`, the frequency sweep, the nextpnr patch's upstream report and any 0.2.0 release.

#### Files Modified:

- docs/vcmi-port-plan.md

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 23 COMMIT Unreleased 2026-11-25T20:19:48-07:00

#### Coming From:

Unreleased f105bfb

#### Purpose:

Run G0, the A25's drawing bench, on the board so the canvas and the frame rate are decided by measured costs rather than by estimate.

#### Outcome:

`firmware/apps/vcmi_bench` was written, built under `-Werror` at 54,106 bytes and run three times on the board, and it found that the DDR3 write path, not the canvas, is what limits this port. The board did not start in the state entry 19 left it: the loaded core answered core ID `0x00` rather than the training fabric's `0x56`, so the seed-3 AE350 image (SHA-256 `f9574b4f...`) was loaded over JTAG with `openFPGALoader -c ft2232`, accepting it only on `DONE` in the unfiltered log, and it trained `error 0`, lanes `1111`, 422 trials, `d 1 b 2`, 7 CALIB a lane, then passed the boot ROM's own tests and was handed over. In 750 MHz cycles per 1280x720 pixel, with the video scanning out of the same array, best of three runs and reproducible to 0.1 cycles between the two independent runs: a 32-bit fill 92.3 (113 ms a screen, 8.81 fps alone), a 32-bit copy 158.3 (195 ms), an 8-bit indexed expand through a palette 104.3 (128 ms), a 32-bit alpha blend 165.9 (204 ms), a nearest 2x scale 103.6 (127 ms), the same fill served from the 32 KiB L1 data cache 3.2 (4 ms), and a page flip's write-back 298 us against a blank wait of 11 to 15 ms. So drawing here is not arithmetic but the store path: 92.3 cycles per 32-bit word is 738 per 32-byte line and a sustained 32 MB/s, about one per cent of the array's 3.2 GB/s peak, and cache-resident drawing is 29 times cheaper than the same drawing into the frame buffer while 1280x720 against 800x600 differs only 2.6 times. `LATE` stayed at 1 through every run while the A25 overwrote the buffer the video was scanning, so `ddr3_arb` holds scanout at maximum CPU write rate. The consequence is a reordering: at 30 fps the A25 can touch about 271,000 DDR3-bound pixels a frame, 29 per cent of a 1280x720 screen, so no canvas worth showing can be redrawn whole above about 8 fps until the write path improves, and the port depends on incremental redraws and on cache-resident work. AE350-004's suspicion that the bridge makes the next transfer wait for a write to land is consistent with this and is now priced. `docs/vcmi-port-plan.md` gained the measured table and a new cycle G for the write path, which now outranks the canvas work it used to follow; `AE350-006` records the figures. The board is left showing the bench's last frame with the AE350 image in SRAM and the boot ROM waiting for a program. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and the active log's 23 of 100 entries.

#### Next Steps:

The write path is now the first technical question: cost how much of the 738 cycles per line is `ahb_ddr3`'s toggle handshake waiting for each store to land and how much is `ddr3_ctl`'s own, then decide with the user whether a write-combining stage, a pipelined bridge or a small fabric cache for the canvas is worth building, since G0 prices that lever at 29 times against the canvas's 2.6. Cycle B's runtime work still waits on the user: the cooperative pthread shim, the archive-backed file layer, and the link-mode keyboard and mouse receiver, with the asset-delivery choice between boot-time images and a BL616 file service still open. Also waiting: closure robustness led by `wr_core`'s pause bookkeeping, the HDMI heat test, rebuilding the controller-only image with entry 16's `ddr3_ctl`, the STA disagreement on `m_n_r`, the frequency sweep, the nextpnr patch's upstream report and any 0.2.0 release.

#### Files Modified:

- firmware/apps/vcmi_bench/main.c
- firmware/apps/vcmi_bench/Makefile
- docs/vcmi-port-plan.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 24 COMMIT Unreleased 2026-11-25T20:24:10-07:00

#### Coming From:

Unreleased 7fec9c9

#### Purpose:

Find whether the A25's 738-cycle store cost is paid per cache line or per store, so the next change is aimed at the real cause.

#### Outcome:

`firmware/apps/write_cost` was written, built under `-Werror` at 50,052 bytes, and run on the board, and it answers the question directly: the cost is per line, not per store. Writing 115,200 lines of 32 bytes over a 3.6 MiB span with the video off cost 738.0 cycles per line when storing all eight words, 739.5 when storing four (words 0, 2, 4 and 6), 739.7 when storing only word 0, and 739.7 when storing only word 7, each stable to about 0.2 cycles over three runs. A read of all eight words of a line cost 513.3 cycles. So the A25's write-back cache already combines a line's eight stores into one transfer and the price is that one round trip, 74 bus clocks at the 75 MHz bus: a write-combining stage inside a line would buy nothing, and a sequential fill is already the best case. The lever is overlap, and there is none today, since successive line writes are serialized waiting for each toggle to return. The cross-check is worth recording too: the full-line store cost equals G0's 92.3 cycles per pixel, which G0 measured with the video on and this bench with it off, so scanout's reads do not measurably slow the CPU's stores. `docs/vcmi-port-plan.md` now carries the stores-per-line table, states that the write path is a pipelining problem in `ahb_ddr3`'s bus half rather than a combining problem, and moves the write path to cycle B ahead of the engine work, because a factor there rescales every frame-rate estimate. `AE350-007` records the measurement. The board is left with the AE350 image in SRAM and the boot ROM waiting for a program. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and the active log's 24 of 100 entries.

#### Next Steps:

The plan this cycle was approved against has changed: the measured answer says a bridge change that overlaps line writes is small, well scoped and worth up to the overlap depth, so it should go ahead of cycle C rather than after it, and the user is to decide that. When it is approved the work is to let `ahb_ddr3`'s bus half accept a second transfer before the first toggle returns, re-run `firmware/apps/write_cost` and `firmware/apps/vcmi_bench` to measure the factor actually reached, and check that training and the whole-array test still pass and that closure still holds, since the bridge is on every path the image times. Cycle C's SDL work and cycle D's engine work stand next in the plan, along with the still-open asset delivery choice, and the hardware items also wait: closure robustness led by `wr_core`'s pause bookkeeping, the HDMI heat test, rebuilding the controller-only image with entry 16's `ddr3_ctl`, the STA disagreement on `m_n_r`, the frequency sweep, the nextpnr patch's upstream report and any 0.2.0 release.

#### Files Modified:

- firmware/apps/write_cost/main.c
- firmware/apps/write_cost/Makefile
- docs/vcmi-port-plan.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 25 COMMIT Unreleased 2026-11-25T22:19:02-07:00

#### Coming From:

Unreleased 5d1bb07

#### Purpose:

Build, close, load and measure the cheapest available fix for the A25's DDR3 store cost -- gathering a cache line's four doublewords into one DDR3 write -- to find whether combining commands is the lever.

#### Outcome:

The gather was built, passed every simulation gate, closed on 1 seed of 16, ran on the board and was reverted, and the useful result is why it bought so little. `ahb_ddr3`'s bus half was changed to merge a line's four AHB doublewords into one 256-bit masked request acknowledged from registers, flushed before a read, before a different line and after 1024 bus clocks so the video could never see a held line, with the crossing widened to 256 bits and `tools/ddr3_write.py` regenerated, since `top.v` is generated and the sweep's staleness guard caught a hand edit. Three bugs came out of simulation and none from the board: a deadlock where a partial line could never age out while a request was pending, a mask polarity inversion that broke every byte because `ddr3_ctl` masks a byte it does not write, and the generated-file edit. `tools/sim_ae350_ddr3.sh` then passed in full -- every byte read back correctly across both clocks, both mutants failing, and the video path's 2,764,800 pixels and 11,059,200 TMDS symbols -- and DDR3 write requests fell from 28,259 to 13,421. Of 16 seeds only seed 4 closed every clock, `bus_clk` 75.44 MHz against 75.01 needed, with `pclk` 101.64, `pix_clk` 90.53, `mclk` 798.08 and `core.rx.clk` 64.72, GB10 on all four AE350 taps and all DDR3 tables equal; entry 18's image had `bus_clk` 86.28, so the 256-bit crossing cost about 11 MHz. That image (`.fs` SHA-256 `5a0de338...6fa2ae`) was loaded anyway at the user's direction, and it trained `error 0`, lanes `1111`, 422 trials, `d 1 b 2`, 7 CALIB a lane, passed the boot ROM's array test and ran 425 passes of the memory test with no lane error. On it `firmware/apps/write_cost` gave a full-line write 654.8 and then 657.4 cycles per line against 738.0 before, a read 501.1 and 512.0 against 513.3, and `firmware/apps/vcmi_bench` gave fill32 82.2 cycles per pixel against 92.3, a whole screen 101,030 us against 113,387 and 9.89 fps against 8.81, with LATE still 1. So combining commands bought 11 per cent, not the 4 times four doublewords suggested, because a full-line write and a read each cost about one crossing round trip, 656 and 512, and command count was never what the line paid for. The user chose to revert, the bridge is back to its committed state with its simulation passing and 28,259 writes again, the v8 variant that replaced the second 256-bit merge with a buffer invalidation was cancelled unbuilt in the sweep, and the board was reloaded with entry 18's seed-3 image and confirmed training clean. `AE350-008` records the result. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and the active log's 25 of 100 entries.

#### Next Steps:

Combining within a line is settled as a dead end, so the write path's remaining option is overlapping successive lines across the crossing or a small fabric cache for the canvas, and the user should choose between them before either starts: any crossing change must cost less than the 11 MHz of `bus_clk` the gather lost, while a cache sidesteps the crossing but needs its own memory and coherence argument with the video. If neither is worth it, the port should proceed to cycle C's SDL driver with whole-screen fills at about 9 fps and rely on incremental redraw. The rest of the queue is unchanged: cycle C's SDL2 and `tinyvcmi` driver, cycle D's engine, the still-open asset delivery choice, closure robustness led by `wr_core`'s pause bookkeeping, the HDMI heat test, rebuilding the controller-only image with entry 16's `ddr3_ctl`, the STA disagreement on `m_n_r`, the frequency sweep, the nextpnr patch's upstream report and any 0.2.0 release.

#### Files Modified:

- None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 26 COMMIT Unreleased 2026-11-25T22:27:31-07:00

#### Coming From:

Unreleased ed1e47c

#### Purpose:

Hand the project to the next agent at the user's direction, with the live state after tonight's write-path work and the measurements behind it in one place.

#### Outcome:

No source changed this cycle; this entry records the state `ed1e47c` leaves and the two findings that follow it. TinyVCMI at `ed1e47c` runs the AE350 from the 1 GiB DDR3 through this project's own open-flow controller and shows 1280x720 at 60 Hz on HDMI from a 32-bit frame buffer at `0x7f000000`. The board is in one-wire mode with entry 18's known-good seed-3 image in SRAM (`.fs` SHA-256 `f9574b4fd4181f41e0dbe5bee59d493dcbf4da3abf76198ed2c57cd8015e48d7`, in the untracked `build/ae350/v6/s3`), re-confirmed after tonight's experiments at `error 0`, lanes `1111`, 422 trials, `d 1 b 2`, and it holds the boot ROM waiting for a program with the test screen up. The DDR3 itself is healthy and fast: v0.1.0's own measurement was 734 passes of the whole array in 600 s with no lane error, which is 1,491 GiB at 2.67 GB/s, about 83 per cent of DDR3-800 x32's 3.20 GB/s peak. The A25's path to that array is the whole problem and is now measured twice: `firmware/apps/write_cost` and `firmware/apps/vcmi_bench` show a 32-byte line costing 738 cycles to write (32.5 MB/s) and 513 to read (46.8 MB/s), about 1.2 per cent of what the array sustains, with one store to a line costing what eight cost, so the cost is per-line round-trip latency of about 984 ns with nothing ever in flight behind it, and cache-resident drawing at 3.2 cycles per pixel against 92.3 into the frame buffer. Entry 25 then built the obvious fix and refuted it: gathering a line's four doublewords into one 256-bit DDR3 write passed every simulation gate and ran on the board, buying 11 per cent (738.0 to 654.8 cycles per line, 113 to 101 ms a screen, 8.81 to 9.89 fps) at a cost of about 11 MHz of `bus_clk`, which left 1 seed of 16 closing, so it was reverted at the user's direction and the bridge is back to its committed state with its simulation passing. The reason it bought so little is the finding that matters: a full-line write costs 656 cycles and a read 512, each essentially one crossing round trip, so command count was never what a line paid for, and AE350-004's near-equal streamed and dependent load costs show the A25 is not pipelining its own misses either. So the remaining lever is decoupling acceptance from completion behind a buffered drain rather than combining commands, and whether the A25 can have more than one dirty-line writeback in flight is the unmeasured question that caps it. `AE350-006`, `AE350-007` and `AE350-008` carry these figures, and `docs/vcmi-port-plan.md` carries them with the costs and the proposed cycles. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and the active log's 26 of 100 entries.

#### Next Steps:

Measure whether the A25 can keep more than one dirty-line writeback outstanding, which decides whether a buffered drain in `ahb_ddr3` can pay or whether the buffer belongs in the CPU's path, then put the buffered-drain design and a fabric cache for the canvas to the user and let them choose before either is built, since the one crossing change already tried cost 11 MHz of `bus_clk`. If the write path is left alone, cycle C's SDL2 and `tinyvcmi` driver goes ahead against whole-screen fills at about 9 fps and relies on incremental redraw, then cycle D's engine, with the asset delivery choice between boot-time images and a BL616 file service still open and the staged data at `root/media/vcmi/data`. Also waiting: closure robustness led by `wr_core`'s pause bookkeeping, now the top timing item at 1 seed of 14 on the entry-18 netlist, the HDMI heat test, rebuilding the controller-only image with entry 16's `ddr3_ctl`, the STA disagreement on `m_n_r`, the frequency sweep, the nextpnr patch's upstream report and any 0.2.0 release. Every load should be confirmed by `DONE` in the loader's raw output saved to a file, and the bench binaries are `firmware/apps/vcmi_bench` and `firmware/apps/write_cost`, run with `tools/load_ae350.py` after `handover`.

#### Files Modified:

- None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---
## 27 COMMIT Unreleased 2026-11-26T08:01:30-07:00

#### Coming From:

Unreleased fe0ab0c

#### Purpose:

Measure how many dirty-line writebacks the A25 can keep in flight, to settle whether a buffered drain in `ahb_ddr3` can pay or whether the write buffer belongs on the CPU side.

#### Outcome:

`firmware/apps/write_depth` was written, built under `-Werror` and loaded over the boot ROM's loader in 0.36 s, and run four times on the board, and it replaces entry 26's reading with a finer one: nothing is ever in flight, and the unit of cost is one 8-byte AHB transfer at 59.9 cycles rather than a line. On entry 18's seed-3 image (`.fs` SHA-256 `f9574b4fd4181f41e0dbe5bee59d493dcbf4da3abf76198ed2c57cd8015e48d7`), loaded with `openFPGALoader -c ft2232` and accepted only on `DONE` in its raw output saved to `build/board/load-write-depth.log`, and re-confirmed at `error 0`, lanes `1111`, 422 trials, `d 1 b 2` and 7 CALIB pulses a lane before the bench ran, with the video unit off and `write_cost`'s 3.6 MiB span: a full line stored cost 683.3 cycles and read 501.7; one dirty line written back by a whole-cache write-back-and-invalidate, with no fill and no CPU store inside the timed window, cost 239.2, which is exactly four bare transfers of 59.8; one uncached 4-byte store cost 59.9, a second word of the same line answered from the bridge's one-line buffer 113.3, and an uncached line read 374.9; a full line with the D-cache off cost 479.9 and half a line 239.9, both exactly the transfer count times 60; K = 2, 4 and 8 fresh-line stores back to back cost 684.3, 684.5 and 684.5, so successive lines do not amortise; and a store followed by a dependent chain of 32, 64, 128, 256 and 1024 cycles cost 582.5, 486.5, 417.2, 394.4 and 421.9 against 683.0 with no chain, so compute hides up to 261 cycles of a miss and the rest is throughput. The same 60 cycles a transfer is charged to an uncached CPU store and to a cache write-back, which puts it in the crossing rather than in the A25's store pipeline, and RV32 has no 64-bit store, so a line cannot be written from firmware in fewer than eight transfers: `E7`'s four `uint64_t` stores compiled to eight 32-bit ones and cost what eight 32-bit stores cost. Two consequences matter. A cached store also pays a 501.7-cycle read-allocate fill that no write-side change touches, which is why entry 25's gather bought only 11 per cent. And bypassing the D-cache on a write-only pass costs 479.9 against 683.3, 1.42 times better with no fabric change at all. The four runs reproduced to within 0.1 cycles on every best-of figure except this session's full-line store at 683.3 against entry 24's 738.0, a 7.4 per cent difference the read's 501.7 against 513.3 does not explain, so the ratios rather than the absolute figures are the durable result; `AE350-009` records the measurement, `AE350-007` and `AE350-008` are revised in place for the mechanism they had read as one round trip per line, and `docs/vcmi-port-plan.md` carries the table and the revised consequences. Every load was powered from the host's 5 V over USB-C OTG and warm, no cooldown having been taken. The board is left in one-wire mode with the seed-3 AE350 image in SRAM, its boot ROM printing `TinyVCMI LOAD` and waiting for a program, and the desktop not restored. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, validated both revised records and the new one against the reference schema, and checked this entry's six sections, ordering, prose, Status values, numbering and the active log's 27 of 100 entries.

#### Next Steps:

The write path is now a choice for the user: a crossing that accepts more than one transfer at a time, the only lever that changes the 59.9-cycle charge and worth a ceiling of about 18 ms a screen; a write-around path for write-only passes in the SDL driver, firmware alone and worth 1.42 times now; or a small fabric cache for the canvas, which sidesteps both but needs its own memory and a coherence argument with the video. The recommended order is the write-around path first, because it is firmware, its result tells how much bandwidth the array can actually take, and it costs no closure. If the user leaves the write path alone, cycle C's SDL2 and `tinyvcmi` driver goes ahead against whole-screen fills at about 9.5 fps and relies on incremental redraw, then cycle D's engine. Also waiting: closure robustness led by `wr_core`'s pause bookkeeping, the HDMI heat test, rebuilding the controller-only image with entry 16's `ddr3_ctl`, the STA disagreement on `m_n_r`, the frequency sweep, the nextpnr patch's upstream report and any 0.2.0 release. Every load is confirmed by `DONE` in the loader's raw output saved to a file.

#### Files Modified:

- docs/vcmi-port-plan.md
- firmware/apps/write_depth/Makefile
- firmware/apps/write_depth/main.c

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---
## 28 COMMIT Unreleased 2026-11-26T08:27:30-07:00

#### Coming From:

Unreleased 69f75ff

#### Purpose:

Make a write-only pass stop paying the 501.7-cycle read-allocate fill that entry 27 measured, which the plan expected to be a matter of marking the frame buffer's window non-cacheable.

#### Outcome:

The memory-attribute route does not exist and the win was taken another way, so the plan's recommendation is replaced with something measured. `firmware/apps/pma_probe` was written, built under `-Werror` and run on entry 18's seed-3 image (`.fs` SHA-256 `f9574b4fd4181f41e0dbe5bee59d493dcbf4da3abf76198ed2c57cd8015e48d7`), powered from the host's 5 V over USB-C OTG and warm, with `mtvec` repointed to a handler in `probe.S` that skips an illegal-instruction trap so an unimplemented CSR can be read safely. The machine-custom window holds `mxstatus` 0xa0000001, `mhcr` 0xa0200001, 0x7c2 0x00020000, 0x7c3 0x80000000, 0x7c7 and 0x7c8 0xffffffff, `mcache_ctl` 3, `mcctlbgnaddr` 0, `mcctlcommand` 6, `mmisc_ctl` 0x48, `micm_cfg` and `mdcm_cfg` 0x00439ada, `mmsc_cfg` 0x2007f039, `mvendorid` 0x31e, `marchid` 0x80000a25, `mimpid` 0x160 and `misa` 0x4094312d, while 0xfc3, 0xfc4 and 0xfc5 read as absent, which is what proves the trap path works; none of the present registers is a memory-region or attribute control, and `cbo.zero`, `cbo.clean`, `cbo.flush` and `cbo.inval` are all illegal instructions, so neither Zicboz nor Zicbom exists. The frame buffer is cached exactly as ordinary DDR3 is, 661.8 cycles a line to store and 523.4 to read against 661.7 and 523.4 at `0x40400000`, so no window of the array is already uncached, the AE350 hard macro exposes no attribute or region port, and neither U-Boot's AX25 cache driver nor its Andes CSR header defines such a register. What does work is switching the D-cache off around the pass: write back and invalidate, clear the enable bit, fill 115,200 lines of one screen, re-enable, which cost 480.0 and then 479.9 cycles a line against 683.1 cached, 104 ms a screen to 73, and read back 0 bad words over the whole screen on both builds. The boundary is sharp: a 32-byte copy under the same switch cost 1,614.9 cycles a line against 1,210.9 cached, 33 per cent worse, and the same fill with the video scanning the buffer being filled cost 563.2 cycles a line with `LATE` unchanged. Because a mis-ordered sequence writes stale lines back over fresh data, the procedure is now `tv_dcache_save_off` and `tv_dcache_restore` in `firmware/include/tinyvcmi.h`, with the invalidation, the leaf-loop rule and the read boundary written in the comment, and the probe calls them so the tested sequence is the shipped one. `AE350-010` records it and `docs/vcmi-port-plan.md` replaces the attribute plan with the cache-off window and moves the next write-path cycle to the crossing. The board is left with the seed-3 image in SRAM at its boot ROM prompt, desktop not restored. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was unchanged, validated the new record and its routing and index lines against the reference schema, and checked this entry's six sections, ordering, prose, Status values, numbering and the active log's 28 of 100 entries.

#### Next Steps:

The write path's remaining lever is the crossing, which accepts one 8-byte transfer at a time at 59.9 cycles: a design that keeps more than one outstanding would change that charge, with a whole-screen fill at 73 ms today and about 18 ms if four were in flight, and it must close inside the 11 MHz of `bus_clk` the gather lost. A small fabric cache for the canvas is the fallback. Otherwise cycle C's SDL2 and `tinyvcmi` driver goes ahead, using `tv_dcache_save_off` for fills, clears and opaque blits and leaving copies, alpha blends and 8-bit expands cached, then cycle D's engine. Also waiting: closure robustness led by `wr_core`'s pause bookkeeping, the HDMI heat test, rebuilding the controller-only image with entry 16's `ddr3_ctl`, the STA disagreement on `m_n_r`, the frequency sweep, the nextpnr patch's upstream report and any 0.2.0 release. Every load is confirmed by `DONE` in the loader's raw output saved to a file.

#### Files Modified:

- docs/vcmi-port-plan.md
- firmware/apps/pma_probe/Makefile
- firmware/apps/pma_probe/main.c
- firmware/apps/pma_probe/probe.S
- firmware/include/tinyvcmi.h

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---
## 29 COMMIT Unreleased 2026-11-26T19:23:30-07:00

#### Coming From:

Unreleased f4ed7bc

#### Purpose:

Take the first step of the closure-robustness work that gates the near-term bridge rewrite: find which `pclk` endpoint actually binds across many placements, fix it, and measure whether the closure rate moves.

#### Outcome:

One endpoint named the whole problem and fixing it doubled the closure rate, and a posted-write bridge was then written, measured and withdrawn. A baseline census routed twelve seeds of HEAD with `tools/ddr3_sta.py` dumped per seed through a new `TINYVCMI_SWEEP_STA` hook in `tools/ae350_ddr3_sweep.sh`, read by a new `tools/closure_census.py`: **1 of 12 seeds closed every clock**, and every failure was `pclk` alone, with `glue.bist.a_last` over timing on all nine seeds that routed that far, worst -2.24 ns. The path was the 32-bit xorshift `xs_next` LFSR, its address mux, and a 25-input `== LAST` compare all in the cycle that sets `a_last`. `lfsr_nx` now holds `xs_next(lfsr)` in a register, advancing only when `lfsr` does, so the compare reads a register. The first attempt advanced it every clock from `lfsr`, which desynchronises the pair, and a new simulation invariant caught it before anything else ran; a C model of the correct two-deep pipeline was checked before the RTL was touched again. Both gates then passed: `tools/sim_ddr3_ctrl.sh` with its six mutants and `tools/sim_ae350_ddr3.sh` with every byte across both clocks and the video path's 2,764,800 pixels and three mutants. Re-routing twelve seeds gave **4 of 12 closing**, with `a_last` gone from the failing list and `core.check.hit` (-2.06 ns on 10 seeds) taking its place at nearly the same severity, so the median `pclk` barely moved, 97.32 to 96.03 MHz: this design has several paths near the constraint, not one. The bridge rewrite was then attempted as `docs/ahb-bridge-design.md` sets out, posting writes through an eight-entry Gray-pointer asynchronous FIFO in `ahb_ddr3` so a store is acknowledged as it enters instead of after a clock-domain round trip. It passed both simulation gates and drove 92,115 writes where the old bench made 30,000, and on seed 7 of a routed sweep (103.36 MHz, every clock passing, all 306 tables equal) the board trained `error 0`, lanes `1111`, 422 trials, `d 1 b 2` and measured a write-back at 239.2 to 159.5 cycles a line, a 33 per cent cut, with an eight-word uncached store 479.9 to 439.9. But it was withdrawn: reads regressed 501.7 to 553.0 cycles a line from a six-PCLK read-settle delay added to stop a read overtaking a queued write, and under a heavily stalling controller model the write pointer passes the read pointer with `wfull` still low, which three attempts did not explain. `ahb_ddr3`, `ae350_sys.sv`, the generated `top.v`, `tb_ahb_ddr3.v`, `tools/ddr3_write.py` and `tools/sim_ae350_ddr3.sh` were reverted to HEAD, `tools/ddr3_write.py --check` reports the generated sources current, and both simulation gates pass on the reverted tree. Two limits are recorded rather than papered over: the posted writes only reach the FIFO, since `ahb_ram` still waits `sd_ack` per beat, so that change alone could not have reached the port's 600 MB/s; and the `nopush` mutant was removed because the 75 MHz AHB side cannot outrun the 100 MHz drain in that bench, `full` being unreachable by construction. The board was reloaded with entry 18's seed-3 image (`.fs` SHA-256 `f9574b4fd4181f41e0dbe5bee59d493dcbf4da3abf76198ed2c57cd8015e48d7`), accepted on `DONE`, and trains `error 0` with lanes `1111`; every load was powered from the host's 5 V over USB-C OTG and warm. `.ai/core.md` was not changed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, and validated this entry's six sections, ordering, prose, Status values, numbering and the active log's 29 of 100 entries.

#### Next Steps:

Attack the posted-write FIFO with a directed unit test of its full flag and a written occupancy argument, rather than through the integration bench, since three attempts at the full-flag logic failed to explain how the write pointer passes a synchronised read pointer with `wfull` low; then add the `ahb_ram` half of the posting, without which the port stays near a quarter of its 600 MB/s ceiling. The read-settle delay added to stop a read overtaking a queued write must be measured for its true minimum instead of being left at six PCLK, which cost reads 8 to 10 per cent. Closure stands at 4 of 12 seeds with `core.check.hit` (-2.06 ns on 10 seeds) and `glue.ctl.head_br` (-2.14 ns on 7) next, both in start-up test and controller logic rather than the AE350 store path; the `a_last` fix is verified in simulation only and wants a board run. Also waiting: the HDMI heat test, rebuilding the controller-only image with entry 16's `ddr3_ctl`, the STA disagreement on `m_n_r`, the frequency sweep, the nextpnr patch's upstream report and any 0.2.0 release.

#### Files Modified:

- docs/ahb-bridge-design.md
- fpga/ddr3_ctrl/ddr3_bist.v
- tools/ae350_ddr3_sweep.sh
- tools/closure_census.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---
