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
