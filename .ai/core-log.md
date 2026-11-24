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
