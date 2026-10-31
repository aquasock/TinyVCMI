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
