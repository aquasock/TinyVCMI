# TINYVCMI TECHNICAL REFERENCE

> **Project:** TinyVCMI
> **Purpose:** The authoritative lookup for externally defined facts this project depends on: the Tang Console 138K hardware, the GW5AST AE350 subsystem, the open FPGA toolchain, the TinyTang host protocol, and the VCMI software being ported.
> **Authority:** Per `.ai/core.md`, consult this file before looking anything up online and open the record behind any hardware fact before acting on it. A record is authoritative only to the extent of its `status` and cited `sources`. When a better or newer source is found online, add or revise a record and notify the user.

This file records what an outside source, sibling project, tool, datasheet, schematic, or direct hardware observation establishes. Project history, build results, and approved work belong in `core-log.md`. Project design choices belong here only when an external fact constrains them.

---

## 1. AI operating rules

```yaml
schema_version: 1

record_kinds:
  - DEVICE      # FPGA silicon and the AE350 hard processor
  - BOARD       # Tang Console 138K wiring and fitted memories
  - MEMORY      # SDR SDRAM and DDR3 interfaces, capacity and behavior
  - PROTOCOL    # TinyTang BL616-to-FPGA frames and AE350 loading
  - EXTERNAL    # VCMI and sibling-project interface contracts
  - TOOLCHAIN   # Open synthesis, place-and-route, packing and firmware tools
  - PROVENANCE  # Source lineage and licensing constraints

statuses:
  VERIFIED:   "A primary or direct source is cited and the fact was confirmed on this project's board family or tools."
  SOURCED:    "A primary or direct source is cited but the fact has not yet been confirmed in TinyVCMI."
  INFERRED:   "Derived from secondary evidence or a project comparison; flag before relying on it."

rules:
  - "One fact or one tightly coupled fact group per record."
  - "Every record cites enough source detail to re-check it: repository and commit, path and symbol, document and section, or tool version and artifact."
  - "Separate what the source establishes (statement) from what it means here (consequence)."
  - "Diagnostic or implementation limits chosen by this project are never described as device, protocol, or standards limits."
  - "A record holds what is true now. Revise a disproved record in place, update verified_date and sources, and append a revision note to verification."
  - "Before acting on a record, confirm that cited paths and symbols still exist."
  - "Never reuse a record_id. Put retired IDs in section 8."
  - "An INFERRED record must explain the inference in verification."
  - "Negative results and unsupported tool features are facts and must be recorded with the same rigor as supported features."
  - "When an online lookup was needed because this file had no answer, add the finding here and notify the user if it supersedes an existing source."
  - "Use technical names such as GW5AST-138, AE350, BL616, SDR SDRAM and DDR3."
```

---

## 2. Topic catalog

Topic IDs are the `record_id` prefix. An entry reserves a namespace; it does not claim complete coverage.

```yaml
- topic_id: DEV
  name: "GW5AST-138 device"
  description: "The FPGA, device revision, hard AE350 processor and bitstream target."

- topic_id: BRD
  name: "Tang Console 138K board"
  description: "Board wiring, clocks, memory devices and physical interfaces."

- topic_id: SDR
  name: "Dock SDR SDRAM"
  description: "The W9825G6KH-6 memory attached through the dock connector and the TinyNES open controller."

- topic_id: DDR3
  name: "Onboard DDR3 and its open-flow boundary"
  description: "The x32 DDR3 array, proven vendor-controller behavior, PHY requirements, and work still required for an open flow."

- topic_id: AE350
  name: "AE350 hard RISC-V processor"
  description: "Reset, address map, caches, clocks and measured memory behavior."

- topic_id: VIDEO
  name: "FPGA video path"
  description: "Framebuffer organization, HDMI output and the resolution VCMI requires."

- topic_id: INPUT
  name: "Keyboard and mouse input"
  description: "The Logitech BLE devices and TinyTang frames that deliver their state to a loaded core."

- topic_id: PROT
  name: "TinyTang core and AE350 protocols"
  description: "BL616-to-FPGA framing, program loading and desktop integration."

- topic_id: VCMI
  name: "VCMI engine"
  description: "The pinned engine, measured MiSTer port, runtime footprint, dependencies and licensing."

- topic_id: TOOL
  name: "Open FPGA and RISC-V toolchains"
  description: "Yosys, nextpnr-himbaechel, Apicula, simulation and compiler behavior that constrains the port."

- topic_id: PROV
  name: "Provenance and attribution"
  description: "Sibling-project lineage, upstream versions and license obligations."
```

---

## 3. Active routing

| Question | Consult first | Fast records |
|---|---|---|
| Which FPGA and revision does TinyVCMI target? | DEV | DEV-001 |
| How much onboard DDR3 exists and how wide is it? | BRD | BRD-001 |
| What SDR SDRAM is already usable by the open flow? | SDR | SDR-001 |
| Is the second 32 MiB SDRAM device already enabled? | SDR | SDR-001 |
| Which DDR3 controller configuration has passed on this board family? | DDR3 | DDR3-001 |
| How is the Gowin DDR3 native port addressed and driven? | DDR3 | DDR3-002 |
| Can the encrypted Gowin DDR3 IP be used as an opaque open-flow block? | DDR3 | DDR3-003 |
| What must an open-flow DDR3 milestone prove? | DDR3 | DDR3-003 |
| Where does the AE350 boot and where is main RAM mapped? | AE350 | AE350-001 |
| What clocks and caches does the AE350 use? | AE350 | AE350-002 |
| What does a DDR3 cache miss cost in the proven implementation? | AE350 | AE350-003 |
| Which video architecture has already worked in the open flow? | VIDEO | VIDEO-001 |
| What resolution does the existing VCMI port require? | VIDEO | VIDEO-002 |
| What do the Logitech keyboard and mouse report? | INPUT | INPUT-001 |
| Can TinyTang already send keyboard and mouse input into a core? | INPUT | INPUT-002 |
| How do TinyNES and TinyGBC load AE350 programs? | PROT | PROT-001 |
| Which VCMI revision did the MiSTer port use? | VCMI | VCMI-001 |
| How much memory did that port consume? | VCMI | VCMI-002 |
| Why is 64 MiB not yet a qualified VCMI capacity? | VCMI | VCMI-002 |
| Which open-flow gaps block DDR3 today? | TOOL | TOOL-001 |
| Which required DDR3 PHY primitives are currently placeable? | TOOL | TOOL-002 |
| What has been measured for the GW5AST DDRDLL? | TOOL | TOOL-003 |
| Does the open-flow DDRDLL produce a tap code on hardware? | TOOL | TOOL-004 |
| How does the working vendor controller drive the DDRDLL? | TOOL | TOOL-005 |
| Are the lane primitives independent sites or one complex? | TOOL | TOOL-006 |
| Which site wires do the DQS ports use? | TOOL | TOOL-007 |
| Which fuses configure a DQS? | TOOL | TOOL-008 |
| How are the DQ serializers wired and configured? | TOOL | TOOL-009 |
| What do lane 0's complete pads add? | TOOL | TOOL-010 |
| Where are DDR3 lanes 1 to 3? | TOOL | TOOL-011 |
| Do lanes 1 to 3 share lane 0's DQS and IOLOGIC encoding? | TOOL | TOOL-012 |
| Does the open packer write the vendor's DDR3-bank IO configuration? | TOOL | TOOL-013 |
| How much IOLOGIC does a plain OSER8 take, and does the whole pad set match? | TOOL | TOOL-014 |
| How does a design declare a DDR3 context, and what does the packer admit in it? | TOOL | TOOL-015 |
| Does a written open-flow DDR3 image equal the vendor's? | TOOL | TOOL-016 |
| Which HCLK lanes can a DDR3 lane serializer use, and how are they encoded? | TOOL | TOOL-017 |
| Does the open-flow DDR3 PHY run on the board, and what does it need beyond the pad set? | TOOL | TOOL-018 |
| How does the proven PHY start up, and how is its memory clock stopped? | TOOL | TOOL-019 |
| Does the open-flow DDR3 read path return the device's data? | TOOL | TOOL-020 |
| Do open-flow DDR3 writes land? | TOOL | TOOL-021 |
| How are live DDR3 reads calibrated and what alignment remains? | TOOL | TOOL-022 |
| Does the read word frame stay put, and what moves it? | TOOL | TOOL-023 |
| Does RBURST mark each read burst, and how does the proven controller use it? | TOOL | TOOL-024, TOOL-033 |
| Can our open flow build upstream LiteDRAM's GW5 DDR3 design? | TOOL | TOOL-025 |
| What sets the read word frame's move at a read gap? | TOOL | TOOL-026 |
| Do single closed-page READs return their burst? | TOOL | TOOL-027 |
| Does a single read burst straddle two captured words? | TOOL | TOOL-029 |
| Do closed-page scatter READs reach the read capture, and is it the open flow? | TOOL | TOOL-030 |
| Can LiteDRAM's control layer be built without its PHY? | TOOL | TOOL-031 |
| Why does the controller not route? | TOOL | TOOL-032 |
| How does the proven controller gate and clock each lane's reads? | TOOL | TOOL-033 |
| Which READ does each lane return, and do per-lane gates fix it? | TOOL | TOOL-034 |
| Does taking a word only on RVALID return isolated READs whole? | TOOL | TOOL-035 |
| How does the proven controller calibrate reads, and what does it accept? | TOOL | TOOL-036 |
| Does training to the vendor's state return isolated READs' data? | TOOL | TOOL-037 |
| Is the vendor state's wrong word a fixed number of READs back? | TOOL | TOOL-038 |
| What is wrong with a trained lane's word, and what puts it right? | TOOL | TOOL-039 |
| How far does the read delay reach, and how often does the vendor's search train a lane? | TOOL | TOOL-040 |
| Where does the proven controller put the read delay before read calibration, and does it help? | TOOL | TOOL-041 |
| Do all four lanes train, and what made them? | TOOL | TOOL-042 |
| Is the read latency fixed, and do isolated READs return address-derived data across banks and rows? | TOOL | TOOL-043 |
| Why did the hardware-training image's heap legalizer stop after 10,001 attempts? | TOOL | TOOL-044 |
| Does the image's own hardware training train all four lanes on the board, and what stopped it? | TOOL | TOOL-045 |
| Does the DDR3 controller image work on the board, unattended, over the whole array? | TOOL | TOOL-046 |
| Can LiteDRAM's controller serve this PHY at 100 MHz? | TOOL | TOOL-047 |
| How much read and write margin do the lanes have under the controller, and what does a cold start do? | TOOL | TOOL-048 |
| Does write leveling cure the cold failures, and what did a new placement do? | TOOL | TOOL-049 |
| Does nextpnr time the paths between the DDR3 I/O cells and the fabric? | TOOL | TOOL-050 |
| Why did the Gowin control miss PCLK timing? | TOOL | TOOL-028 |
| Which sources and licenses constrain reuse? | PROV | PROV-001 |

---

## 4. Fast lookup index

```yaml
DEV-001: "Target is GW5AST-LV138PG484AC1/I0 revision C with the hard AE350/A25 subsystem"
BRD-001: "Two Hynix H5TQ4G63EFR-RDC x16 devices form a 1 GiB x32 onboard DDR3 array"
SDR-001: "TinyNES uses one W9825G6KH-6-compatible 32 MiB x16 SDR SDRAM window; the user reports a second 32 MiB device is fitted but not enabled"
DDR3-001: "Hardware-proven vendor configuration is x32 DDR3-800 with a 256-bit port at 100 MHz"
DDR3-002: "The native-port address counts 32-bit words; BL8 commands advance by eight and span the 1 GiB array"
DDR3-003: "Current Gowin DDR3 output is encrypted RTL plus a post-PnR simulation model; the current open backend cannot import it as a routed black box"
AE350-001: "Reset is 0x80000000; cacheable main memory is on the 64-bit RAM AHB port and EXTS is at 0xe8000000"
AE350-002: "The A25 runs at 750 MHz in the qualified sibling designs, with 32 KiB instruction and data caches and a 75 MHz fabric bus"
AE350-003: "Tang-PSX measured about 570 core cycles for a DDR3 D-cache miss through its proven path"
VIDEO-001: "TinyNES and TinyGBC use SDRAM-backed framebuffers and FPGA HDMI scanout in the open flow"
VIDEO-002: "MiSTer-VCMI supports 800x600 and states that VCMI needs at least 800x600"
INPUT-001: "The Logitech K950 supplies an 8-byte boot-keyboard report and the M750 a 4-byte boot-mouse report"
INPUT-002: "TinyTang sends live mouse frames as command 0x16 and BLE keyboard state as command 0x17"
PROT-001: "TinyNES/TinyGBC load AE350 ELF-derived images through a checked UART protocol and then enter TinyTang link mode"
VCMI-001: "MiSTer-VCMI pins VCMI 1.7.5 at commit 6901839ae9760dfcd1d5ff2c4aa4ef6968fee752"
VCMI-002: "The MiSTer port measured roughly 100-115 MB resident at 800x600, so 64 MiB is not a qualified full-engine target"
TOOL-001: "The current open flow supports the AE350 and SDR SDRAM design but not the complete Gowin DDR3 PHY/controller netlist"
TOOL-002: "Yosys declares all required PHY cells; the GW5AST backend places and routes static IODELAY, CLKDIV, the bottom-left DDRDLL with LOCK, and the DQS, OSER8_MEM and IDES8_MEM of all four lanes, and all of them pack to the vendor's fuses, but only in-process because the DDR3-bank guard refuses any image with a bank 6/7 pad"
TOOL-003: "DDRDLL is a two-cell macro: ports in the column-1 tile, configuration fuses in the corner, LOCK on a dedicated row-99 escape now modelled as a fuse-free node, CLKIN from CLK0 (feature 5) or HCLK lane n (features 21 and 4-n); open flow covers the bottom-left master only"
TOOL-004: "DDRDLL STEP read zero in every isolated image, open-flow and vendor, all of which clocked the DLL from CLK0; clocked from its CLKDIV's HCLK lane inside the PHY it reads 0x2c (TOOL-018)"
TOOL-005: "The hardware-proven vendor controller drives STOP with the inverse of PLL lock, UPDNCNTL from its 50 MHz init FSM, clocks the DLL from its single CLKDIV's HCLK lane 0, and feeds STEP to four DQS blocks with no path back into the DLL"
TOOL-006: "DQS, OSER8_MEM and IDES8_MEM form one lane complex: TCLK, ICLK, WADDR and RADDR take only their lane DQS's outputs, so the internal connections must be modelled, not measured as fabric wires"
TOOL-007: "The DQS control and status side is tile (81,5): 24 inputs and 13 outputs named, three outputs by route inference; FCLK is an HCLK-lane sink selected by table 58 at (72,0), and DQSIN arrives fuse-free from the pad tile"
TOOL-008: "Every DQS configuration fuse, parameters and FCLK lane, is in longfuses table 58 of the byte group's config tile, (72,0) for lane 0; the packer writes it by table key"
TOOL-009: "Lane 0's OSER8_MEM and IDES8_MEM sit on IOLOGIC A/B of cells (68..79,0); their memory-mode pins are hard-wired and their configuration is named IOLOGIC attributes"
TOOL-010: "A complete DQ pad's IOLOGIC is the union of its serializers plus three IODELAY fuses; IO standard touches only IOB and the BANK table"
TOOL-011: "Lanes 1 to 3 have byte groups (99,0), (90,0) and (63,0) and DQS sites (99,0), (90,0) and (81,6); every site moves lane 0's 24 input wires"
TOOL-012: "Lanes 1 to 3 share lane 0's 24-input and 13-output DQS map, table-58 keys, memory-serializer attributes and bit order"
TOOL-013: "Under ddr_context the open packer's bank 6/7 IOB and BANK fuses now equal the vendor's on every measured SSTL lane and bank-7 shape, including unused-pin DRIVE=8 against the fork's D108 rule and an is_mipi call bug corrected; the full bank 7 is unplaced"
TOOL-014: "A plain OSER8 configures only its own IOLOGIC side on this die; with that modelled, the whole controller's pad set packs to the vendor's fuses in DQS, IOLOGIC, IOB and BANK"
TOOL-015: "A DDR3 context is declared only by gowin_pack --ddr3-context with a 72-ball manifest; each bank 6/7 pad must be a listed ball at SSTL15/SSTL15D, BANK_VCCIO=1.5, PULL_MODE=NONE, DRIVE=8 on outputs, nothing else"
TOOL-016: "The open-flow image of the whole DDR3 pad set, written with --ddr3-context, equals the vendor build on all 306 DDR3 tables, the DDRDLL's four unattributed vendor defaults included"
TOOL-017: "DDR3 lane serializers take FCLK from all four HCLK lanes; lanes 1 and 3 are FCLKSEL0/4/5/6/7 sets the open model now writes, with lane-1/3 FCLK pips on the lane cells"
TOOL-018: "An open-flow DDR3 PHY image equal to its vendor build on all 306 tables ran on the board beside the vendor control: PLL lock, DLL LOCK, STEP 0x2c in both, with the device held in reset"
TOOL-019: "The vendor PHY waits 16384 clocks after DLL LOCK, updates the DLL under HOLD, then resets CLKDIV and lanes with the memory clock stopped through the PLL's ENCLK, a routed pin at (27,4) B4/B6 the open flow now models"
TOOL-020: "The open-flow DDR3 PHY initializes the device and reads its MPR pattern on all 32 DQ, every cycle, at every RCLKSEL, with live read-delay edges; its lower edges sit 4 to 10 steps from the vendor build's"
TOOL-021: "The open-flow DDR3 PHY writes a pattern to the device and reads it back on all 32 DQ at almost every WSTEP without write leveling; per-bit word framing can come up misaligned at first start-up"
TOOL-022: "Per-bit CALIB, grouped READ gating and signed read-delay sweeps qualify all lanes across 8 banks, 6 rows and 7 patterns; raw whole-byte rotation still needs controller normalization"
TOOL-023: "With the READ gate at memory-clock offset 0 the read word frame moves once per interruption, uniformly in all four lanes; TOOL-026 shows the move is set by the gate offset"
TOOL-024: "RBURST edges do not mark each burst: over 2^16 PCLK of a stream the edges are 0 to 163 per lane against about 8192 expected; the proven controller samples RBURST as a level (TOOL-033)"
TOOL-025: "Upstream LiteDRAM GW5A DDR3 uses only primitives the fork supports and synthesises cleanly, but nextpnr rejects its generated clocks, its differential CST form and its OSER8 FCLK routing"
TOOL-026: "The READ gate's memory-clock offset k sets the frame move per read gap, 2 beats per clock; at read delay 1 with k = 2 or 3 the stream frame never moves"
TOOL-027: "Single closed-page READs to sixteen pattern rows pass at no gate position; at the stream-stable one the right burst is whole in 12.5% of READs, 7 PCLK after the command"
TOOL-028: "GowinSynthesis packs two-flop setting synchronizers into counter-addressed LUT-RAM shift registers unless syn_srlstyle = registers, which cost the Gowin control PCLK timing"
TOOL-029: "A single read burst straddles two captured words: cycle 11 with slips 0,0,0,4 in a raw capture, and a runtime per-lane beat slip lifts the best-position pass rate from 5.5% to 25.4%"
TOOL-032: "The controller did not route because its build reused the write image's constraints, whose INS_LOC cells and clock nets it does not have; the bank-7 FCLK pip exists"
TOOL-033: "The proven controller drives READ, RCLKSEL and HOLD per lane, gates each READ with the same four-clock window as ours selected by a per-lane read_i, and trains it on an RBURST level; it takes read data only on cycles whose registered RVALID is high"
TOOL-034: "Isolated READs: each lane holds its own READ's burst in at most about 51% of READs at any per-lane gate and RCLKSEL, in both builds, valid on two PCLK of every three"
TOOL-035: "With RVALID-held capture a lane returns 100% of isolated READs' own bursts at its own setting, but the right setting is fixed per FPGA load and changes from load to load"
TOOL-036: "The proven controller accepts a lane only with exactly one RVALID cycle and one RBURST pulse per READ over 29 groups of four READs, sweeping RCLKSEL then the gate per lane"
TOOL-037: "Training reaches the vendor's one-RVALID-and-one-RBURST-per-READ state on two lanes per load, but in it the RVALID word is often an older READ's clean burst"
TOOL-038: "In the vendor's read-calibration state no lane delivers its burst a fixed 1 to 8 READs back; which READs succeed is set by the READ sequence, identically on every trained lane"
TOOL-039: "A trained lane's word has one memory-clock slot copied from the next; two IDES8_MEM CALIB pulses at the trained setting make every trained lane's bursts whole, as the proven controller's CALIB-in-the-search implies"
TOOL-040: "RMOVE stops moving the read delay at the top of its range, 44 to 68 steps above each lane's lower edge; a vendor-style search with CALIB and a data check trains lanes whole, centred they read 100%, but about one lane per load"
TOOL-041: "The proven controller loads the read tap from DLL STEP and moves every lane to tap 4 with STEP - 4 RDIR = 1 pulses before read calibration; RDIR = 1 lowers the tap, so TOOL-040's top is tap 0; the tap-4 start and a READ period of 8 do not train more lanes"
TOOL-042: "With HOLD on every unconfigured lane while its gate and RCLKSEL change, as the proven controller does, all four lanes train in every load to repeatable settings and return 100% of isolated READs' own bursts"
TOOL-043: "Trained lanes hand over each READ's burst at one fixed PCLK on all four lanes; with a trained write alignment every isolated random READ over 8 banks x 16 rows x 128 bursts returns its address's own data"
TOOL-044: "The heap placer's default per-cell attempt budget overflowed signed 32-bit arithmetic above 46,340 cells; 64-bit arithmetic lets the 48,302-cell hardware-training image place and route without relaxing legality"
TOOL-045: "The stream's frame moving during the sequencer's fixed-target per-pin framing split lanes' pins; framed against pin 0 and checked, the image's own training trains all four lanes and passes every READ check in five of five loads"
TOOL-046: "The controller image trains itself, hands over and tests the whole 1 GiB at 111.62 MHz: four of six read loads clean over about 85 GiB each, two failing on lane 1 at up to 3e-6 of words"
TOOL-047: "LiteDRAM's controller logic closes 77.9 MHz in the open flow and 90.0 MHz in Gowin's against this PHY's 100 MHz, and its buffered command mode returns a port's reads out of order"
TOOL-048: "Under the controller's test every lane reads cleanly 20 taps either side of its trained centre; writes run untrained at WSTEP 0, whose upper edges are 16 to 80; failures fall load by load from a cold start, on lane 1 above all"
TOOL-049: "Leveled write strobes still failed cold as before; the image rebuilt with test diagnostics, the PHY and controller unchanged, failed no word in four cold loads, so the failures follow the placement"
TOOL-050: "nextpnr's Gowin timing model has no arcs for IDES8_MEM, OSER8, OSER8_MEM or DQS, so no path between them and the fabric is timed for setup or hold; the controller image now retimes every such crossing on PCLK's falling edge"
TOOL-031: "LiteDRAM's control layer alone generates, synthesises and places in the open flow at ~1% of the LUTs, with none of TOOL-025's three gaps"
TOOL-030: "Closed-page scatter READs do not reach the read capture in the open or the vendor build of the same RTL; no cadence, gate position or shared RCLKSEL recovers them, and failing READs return other rows' patterns"
PROV-001: "Reuse source and interface ideas with their original license boundaries and attribution intact"
```

---

## 5. Established records

```yaml
- record_id: DEV-001
  topic_id: DEV
  title: "TinyVCMI target device"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "The project target is GW5AST-LV138PG484AC1/I0, device revision C. The GW5AST contains the hard AE350 subsystem used by the sibling TinyNES, TinyGBC and Tang-PSX designs."
  consequence: "Every bitstream, primitive model, constraint and timing result used by TinyVCMI must name the 138K PG484 revision-C target; results for a GW5AST-138B or another package are reference evidence, not an interchangeable artifact."
  sources:
    - "TinyVCMI commit e1b7e01, .ai/core.md: Build Environment"
    - "TinyNES commit 0a1ba9e, fpga/ae350_soc/ae350_soc.sv and tools/build_ae350_soc.sh"
    - "Tang-PSX commit 61974ca, .ai/core-reference.md DEV-001 and DEV-002"
  verification: "The target is the active project directive and is the same device named by the hardware-proven sibling images."

- record_id: BRD-001
  topic_id: BRD
  title: "The onboard DDR3 array is 1 GiB with a 32-bit data bus"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "The Tang Console 138K SOM fits two Hynix H5TQ4G63EFR-RDC 4-Gbit x16 DDR3 devices on one address and command bus with separate data lanes, forming DQ[31:0], DQS[3:0] and DM[3:0] for 1 GiB total capacity."
  consequence: "The board has enough physical capacity for the measured VCMI working set. Capacity is not the blocking question; an open controller, PHY integration, timing model, placement, routing and hardware qualification are."
  sources:
    - "Tang-PSX commit 61974ca, .ai/core-reference.md BRD-001 and BRD-002"
    - "Tang-PSX commit 61974ca, gateware/gowin_ddr3.py: ddram32_io"
    - "Hynix H5TQ4G63EFR datasheet: organization and x16 interface"
  verification: "Tang-PSX records 232 full-array passes with zero errors and an AE350 walking-address test across 1 GiB. TinyVCMI has not yet reproduced that result."

- record_id: SDR-001
  topic_id: SDR
  title: "The qualified open-flow SDR SDRAM window is 32 MiB; a second 32 MiB device is not enabled"
  status: INFERRED
  verified_date: 2026-10-22
  statement: "TinyNES drives one 16-bit W9825G6KH-6-compatible SDR SDRAM window at 0x40000000 through the dock connector and addresses 32 MiB. The user reports that the fitted hardware contains two 32 MiB devices, for 64 MiB physical capacity, but the second device has never been enabled."
  consequence: "Only 32 MiB may be treated as qualified until the second device's select, mapping, refresh behavior and full address range pass on hardware. Even a proven 64 MiB total would remain below the measured MiSTer-VCMI resident footprint in VCMI-002."
  sources:
    - "TinyNES commit 0a1ba9e, README.md: AE350 system: boot ROM, RAM and C firmware"
    - "TinyNES commit 0a1ba9e, fpga/ae350_soc/ahb_sdram.sv and ae350_soc.cst"
    - "User hardware statement, 2026-10-22: two 32 MiB devices are fitted and the second has not been enabled"
  verification: "The 32 MiB controller and map are hardware-proven in TinyNES. The physical 64 MiB statement and the unqualified second device have not been independently inspected in this cycle, so this combined record remains INFERRED."

- record_id: DDR3-001
  topic_id: DDR3
  title: "Hardware-proven x32 DDR3 controller configuration"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "Tang-PSX qualified a Gowin DDR3 controller at a 400 MHz memory clock (800 MT/s), 1:4 ratio, x32 bus, x16 DRAM devices, one rank, 15 row bits, 10 column bits, BL8, CL6 and CWL5. Its user port is 256 bits wide at 100 MHz."
  consequence: "These settings and the corresponding board pin map are the behavioral reference for an open-flow implementation. They do not make the encrypted Gowin implementation usable by the open flow and are not a substitute for independently checking every DDR3 timing parameter."
  sources:
    - "Tang-PSX commit 61974ca, .ai/core-reference.md DDR3-001"
    - "Tang-PSX commit 61974ca, gateware/ddr3_vendor/ddr3_ip.tcl and ddr3_memory_interface.ipc"
    - "Sipeed TangMega-138K-example commit 06e7d8b118d345915ab6f257b7c22226f81575cd, ddr_memory design"
  verification: "The sibling record reports 232 full-array passes and subsequent AE350 tests. This verifies the board and configuration, not an open controller."

- record_id: DDR3-002
  topic_id: DDR3
  title: "Gowin DDR3 native-port protocol and address units"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "The proven controller uses command 000 for writes and 001 for reads; a write command and its data are accepted in the same cycle, wr_data_mask bit 1 suppresses the corresponding byte, and read data has no back-pressure input. addr[28:0] counts 32-bit words, one BL8 command covers eight consecutive words, addr[2:0] is zero at command issue, and addr[27:0] spans the 1 GiB single-rank array."
  consequence: "A compatibility wrapper or replacement open controller must preserve the contract expected by the proven AE350 and video arbiters, or define and verify a deliberately different internal contract. It must always accept returned read data at the PHY boundary."
  sources:
    - "Tang-PSX commit 61974ca, .ai/core-reference.md DDR3-002 and DDR3-003"
    - "Tang-PSX commit 61974ca, gateware/ddr3_vendor/gowin_ddr3_native.sv"
  verification: "Tang-PSX's full-array test established command encoding, address units, ordering and mask polarity on hardware."

- record_id: DDR3-003
  topic_id: DDR3
  title: "The current Gowin DDR3 IP cannot be imported as an opaque open-flow block"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "Gowin EDA 1.9.11.03 generates the DDR3 controller as RSA/AES protected Verilog that Yosys cannot elaborate. Its additional .vo identifies itself as a post-place-and-route Verilog simulation model and contains thousands of flattened primitives, including DQS, DDRDLL, OSER8_MEM, IDES8_MEM and IODELAY, without a supported placed-partition handoff. At nextpnr-himbaechel commit 8be8657, the local GW5AST backend has IODELAY and general IO support but does not expose complete pack, placement, routing and bitstream support for the generated DDR3 PHY as an importable block."
  consequence: "Strict open flow cannot black-box the existing Gowin controller and merge it into a final bitstream. The approved TinyVCMI direction therefore requires open DDR3 gateware plus the missing GW5AST PHY primitive, placement, routing, timing and packing support, proven incrementally on hardware. This is an engineering objective, not a claim that open DDR3 already works."
  sources:
    - "Gowin EDA 1.9.11.03 generated ddr3_memory_interface.v: pragma-protect envelope"
    - "Gowin EDA 1.9.11.03 generated ddr3_memory_interface.vo: Post-PnR Verilog Simulation Model header and primitive inventory"
    - "nextpnr-himbaechel commit 8be8657, himbaechel/uarch/gowin/{constids.inc,pack_iologic.cc,cst.cc}"
    - "Tang-PSX commit 61974ca, scripts/gen-ddr3-ip.sh and scripts/build-gate1.sh"
  verification: "The generated files and current open backend were inspected directly on 2026-10-22. No EDIF, routed design checkpoint, partial bitstream, or supported opaque-IP merge path was emitted."

- record_id: AE350-001
  topic_id: AE350
  title: "AE350 reset and fabric address windows"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "The AE350 A25 resets at 0x80000000 on its ROM AHB port. Its 64-bit RAM AHB port carries cacheable main-memory traffic, and its CPU-master extended slave window is 0xe8000000 through 0xefffffff. TinyNES maps SDR SDRAM at 0x40000000; Tang-PSX maps DDR3 at the same base."
  consequence: "TinyVCMI can retain the sibling projects' boot ROM and 0x40000000 main-memory convention while changing the memory backend. Device registers and the TinyTang link belong in the uncached EXTS window."
  sources:
    - "Tang-PSX commit 61974ca, .ai/core-reference.md AE350-001 and AE350-003"
    - "TinyNES commit 0a1ba9e, README.md and fpga/ae350_soc/ahb_ram.sv"
  verification: "Both sibling designs boot the AE350 from 0x80000000 and reach their respective memory at 0x40000000 on hardware."

- record_id: AE350-002
  topic_id: AE350
  title: "AE350 clocks and L1 caches in the qualified sibling designs"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "The board's A25 has 32 KiB four-way instruction and data caches with 32-byte lines, inferred from its configuration CSRs and confirmed present on hardware. TinyNES and Tang-PSX run the core at 750 MHz from PLL_R[0] CLKOUT1 and the fabric bus at 75 MHz. The caches reset disabled and are enabled through mcache_ctl; the data cache is write-back."
  consequence: "Memory and application benchmarks must run with caches enabled. DMA or FPGA masters sharing buffers with the AE350 require explicit cache maintenance, and the core clock must remain on the dedicated PLL_R[0] route."
  sources:
    - "Tang-PSX commit 61974ca, .ai/core-reference.md AE350-002, AE350-004 and AE350-007"
    - "TinyNES commit 0a1ba9e, .ai/core-reference.md DEV-008, DEV-012 and DEV-013"
  verification: "The CSR values, cache operations and 750 MHz core clock were measured in the sibling projects on this board family."

- record_id: AE350-003
  topic_id: AE350
  title: "Measured DDR3 cache-miss cost in Tang-PSX"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "Tang-PSX measured a dependent-load D-cache miss to DDR3 at about 570 A25 core cycles, about 760 ns at 750 MHz, through its registered AE350 bridge, clock crossing, arbiters and Gowin controller. Its optional 128 KiB direct-mapped fabric L2 reduced an L2 hit to about 240 core cycles but did not reduce an L2 miss."
  consequence: "Capacity alone will not make VCMI viable. The open DDR3 path must be benchmarked for latency and bandwidth, and software locality or a better cache may be required after functional bring-up. Tang-PSX's figures are comparison points, not TinyVCMI acceptance limits."
  sources:
    - "Tang-PSX commit 61974ca, .ai/core-reference.md AE350-009 and AE350-010"
    - "Tang-PSX commit 61974ca, software/programs/memlat and gateware/l2_cache.py"
  verification: "The values are hardware measurements from the sibling design and have not been reproduced by TinyVCMI."

- record_id: VIDEO-001
  topic_id: VIDEO
  title: "Open-flow AE350 video uses memory-backed framebuffers and FPGA HDMI scanout"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "TinyNES and TinyGBC run the game or emulator on the AE350, write framebuffers in SDR SDRAM, and let FPGA logic fetch scanlines and transmit HDMI. TinyNES uses two 256x240 8-bit indexed buffers; TinyGBC uses two 160x144 15-bit buffers. Both arbitrate video reads ahead of ordinary CPU traffic so scanout does not underrun."
  consequence: "TinyVCMI should keep presentation out of the AE350's copy loop where possible and give video deterministic memory service. Its required 800x600 format is much larger and must be budgeted against the open DDR3 interface rather than copied from either console layout."
  sources:
    - "TinyNES commit 0a1ba9e, README.md: HDMI video and fpga/ae350_soc/video.sv"
    - "TinyGBC commit 745f1ad, README.md: fpga/ae350_soc and fpga/ae350_soc/video.sv"
  verification: "TinyNES's architecture is hardware-proven; TinyGBC's current README states its retargeted video path is built but not yet screen-proven. The common memory-backed architecture is therefore verified through TinyNES."

- record_id: VIDEO-002
  topic_id: VIDEO
  title: "The existing VCMI port requires 800x600"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "MiSTer-VCMI runs VCMI at 800x600 and states that VCMI needs at least 800x600. Its software renderer uses a 32-bit streaming texture and the port's FPGA/display path presents that image at 60 Hz."
  consequence: "The first TinyVCMI video target must represent an 800x600 desktop. One packed RGB565 framebuffer is 960,000 bytes and one 32-bit framebuffer is 1,920,000 bytes; buffering count and pixel format are project choices, not VCMI standards."
  sources:
    - "MiSTer-VCMI commit 76e1e1c, README.md: Current limitations and sdl-driver/sdl_bench.c"
    - "MiSTer-VCMI commit 76e1e1c, docs/release-notes/0.2.0.md"
  verification: "The user states that this MiSTer port was completed previously; its repository records hardware operation at 800x600."

- record_id: INPUT-001
  topic_id: INPUT
  title: "Logitech K950 and M750 BLE HID reports"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "In Bluetooth mode, the Logitech K950 exposes HID over GATT and supports the standard eight-byte boot-keyboard input report. The Logitech M750 exposes HID over GATT and supports a four-byte boot-mouse report containing buttons, signed X, signed Y and signed wheel."
  consequence: "TinyVCMI can consume stable HID boot layouts rather than device-specific report maps. Keyboard repeat remains an application responsibility because the K950 reports state changes rather than a periodic held-key heartbeat."
  sources:
    - "TinyTang commit 5877729, .ai/core-reference.md BLE-006, BLE-008 and BLE-009"
    - "TinyTang commit 5877729, ports/bl616/tang_ble.c and tang_ble.h"
  verification: "TinyTang records paired-device discovery and hundreds of decoded reports on the user's board."

- record_id: INPUT-002
  topic_id: INPUT
  title: "TinyTang already sends BLE mouse and keyboard state into a loaded core"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "TinyTang command 0x16 carries six bytes: a 16-bit frame number, mouse buttons, signed dx, signed dy and signed wheel; live input uses frame 0xffff. Command 0x17 carries seven bytes: keyboard modifiers followed by six HID usage codes. TinyTang sends these only while it owns the link; the keyboard frame is emitted on state change."
  consequence: "TinyVCMI needs core-side receivers and AE350-visible registers or queues for commands 0x16 and 0x17, but it does not require a new BL616 protocol for the Logitech K950 and M750. Earlier project-family evidence saying no input command existed is obsolete."
  sources:
    - "TinyTang commit 5877729, ports/bl616/tang_fpga_link.h: FPGA_CMD_INPUT and FPGA_CMD_KEYBOARD"
    - "TinyTang commit 5877729, ports/bl616/tang_osd_desk.c: pointer_frame and keyboard_frame"
    - "TinyTang commit 5877729, .ai/core-reference.md BLE-017 revision dated 2026-10-16"
  verification: "The current source defines and sends both commands. TinyVCMI has no receiver yet, so only the TinyTang side is verified."

- record_id: PROT-001
  topic_id: PROT
  title: "TinyNES and TinyGBC AE350 program loading and link handoff"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "The sibling SoCs boot a small ROM at 0x80000000, accept a CRC-checked program over the 2 Mbaud FPGA UART, write it to main memory, verify it, and jump to its entry. A loaded program can enter TinyTang link mode so the BL616 resumes framed desktop, text and input traffic over the same UART."
  consequence: "TinyVCMI can reuse the proven loader and link-state architecture while changing program size, storage service and memory backend. Large engine and asset loads will require measured throughput and may need a resident runtime or file service rather than one monolithic image."
  sources:
    - "TinyNES commit 0a1ba9e, README.md: Loading and running programs"
    - "TinyNES commit 0a1ba9e, firmware/boot/load.c, firmware/include/tinynes.h and fpga/ae350_soc/desk_link.sv"
    - "TinyGBC commit 745f1ad, README.md: Building and running"
  verification: "TinyNES records successful TinyTang loading, game execution and desktop overlay operation on hardware."

- record_id: VCMI-001
  topic_id: VCMI
  title: "MiSTer-VCMI source baseline"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "MiSTer-VCMI pins VCMI release 1.7.5 at commit 6901839ae9760dfcd1d5ff2c4aa4ef6968fee752. It cross-builds the client and server for 32-bit ARM Linux with SDL2, SDL2_image, SDL2_mixer, SDL2_ttf, Boost, zlib, minizip-ng, oneTBB and libsquish, while disabling components not needed by that target."
  consequence: "VCMI 1.7.5 and the MiSTer port's feature cuts are the initial software reference, not an automatic AE350 build recipe. Every OS, threading, filesystem, dynamic-loading and library dependency must be classified before the engine can run in the TinyNES-style bare-metal environment."
  sources:
    - "MiSTer-VCMI commit 76e1e1c, scripts/env.sh, scripts/build-deps.sh and scripts/build-vcmi.sh"
    - "MiSTer-VCMI commit 76e1e1c, ATTRIBUTIONS.md: VCMI"
  verification: "The pinned source, dependency versions and disabled features were read from the completed MiSTer port."

- record_id: VCMI-002
  topic_id: VCMI
  title: "Measured MiSTer-VCMI memory footprint"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "MiSTer-VCMI reports roughly 100 to 115 MB resident at 800x600 on a dual Cortex-A9 Linux system with about 492 MiB visible RAM. This is an observed port footprint, not an upstream VCMI minimum-memory specification."
  consequence: "The existing 32 MiB SDR SDRAM is insufficient and the user-reported 64 MiB physical SDR SDRAM capacity is not a qualified full-VCMI target. A bare-metal AE350 port may remove Linux and shared-library overhead, but no evidence yet shows that it can reduce the engine below 64 MiB; open DDR3 is therefore the approved capacity path."
  sources:
    - "MiSTer-VCMI commit 76e1e1c, README.md: Performance"
    - "MiSTer-VCMI commit 76e1e1c, .ai/core.md: Target Environment"
  verification: "The figure was measured by the prior completed project and reported in its user-facing README. TinyVCMI must add its own allocation and high-water measurements once any engine subset runs."

- record_id: TOOL-001
  topic_id: TOOL
  title: "Current open flow supports the AE350 SoC but not a complete DDR3 PHY"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "The aquasock GW5AST open flow used by TinyNES combines Yosys, nextpnr-himbaechel and Apicula support for the revision-C device, AE350 timing, clocks, SDR SDRAM, HDMI and packing. The current local nextpnr fork has GW5A IODELAY work but lacks a qualified complete implementation of the generated x32 DDR3 PHY's DQS, DDRDLL and memory serializer/deserializer placement and bitstream behavior."
  consequence: "The first TinyVCMI engineering milestone is not application porting. It is an isolated open-flow DDR3 proof that adds or verifies the missing primitive and routing support, calibrates, tests increasing address ranges, and produces deterministic diagnostics before the AE350 or video shares the port."
  sources:
    - "TinyNES commit 0a1ba9e, tools/build_ae350_soc.sh and .ai/core-reference.md TOOL-020 through TOOL-023"
    - "nextpnr-himbaechel commit 8be8657, himbaechel/uarch/gowin"
    - "OSS CAD Suite local Yosys Gowin cell declarations, cells_xtra_gw5a.v"
  verification: "TinyNES proves the stated open-flow features on hardware. Direct inspection of the current backend and the Gowin post-PnR primitive list establishes the DDR3 support gap; no open DDR3 image has been built or tested."

- record_id: TOOL-002
  topic_id: TOOL
  title: "Primitive-level boundary of the current GW5AST DDR3 open flow"
  status: VERIFIED
  verified_date: 2026-10-23
  statement: "Yosys 0.52 declares DDRDLL, DQS, OSER8_MEM, IDES8_MEM, IODELAY and CLKDIV for GW5A synthesis. With the aquasock/nextpnr epic/gw5ast138c tree and Apicula commit 8918f14, isolated GW5AST-138C probes place and route static IODELAY, CLKDIV and the bottom-left DDRDLL master, while DQS, OSER8_MEM and IDES8_MEM still fail. Those three are placed at IOLOGIC sites, and the GW5AST-138C chipdb port map for those sites (tile types 229 to 232 and 243, 54 pins) covers 17 of OSER8_MEM's 18 pins (missing TCLK), 13 of IDES8_MEM's 16 (missing ICLK, WADDR, RADDR) and only 3 of DQS's 24 (missing DQSIN and every control and status pin), so the boundary is unnamed wires at the site rather than a missing BEL type. The qualified vendor reference contains one DDRDLL, four DQS, 40 OSER8_MEM, 32 IDES8_MEM, 32 IODELAY and one CLKDIV."
  consequence: "The remaining primitive boundary is DQS and the two memory serializers, whose missing site wires must be measured before any BEL is written for them, since a BEL built on the 54-pin map would invent the control connections. Support follows at one x8 lane before expanding to x32. DDRDLL placement and parameter packing exist for one site only; LOCK and the DQS are placeable and routable as of 2026-10-23, but no open-flow image containing either has been packed, so no lock-and-step evidence exists yet. Static IODELAY support does not establish dynamic calibration support."
  sources:
    - "Yosys 0.52, share/yosys/gowin/cells_xtra_gw5a.v"
    - "aquasock/nextpnr branch epic/gw5ast138c; binary nextpnr-0.11.1-65-g7d1b131c produced the 2026-10-22 evidence, and 8be8657b is the commit at the tip of that tree (not the binary's own describe)"
    - "Apicula commit 8918f14, apycula/GW5AST-138C.msgpack.xz and apycula/gowin_pack.py"
    - "TinyVCMI docs/ddr3-open-flow.md: DDRDLL reverse-engineering and open-flow implementation"
    - "Tang-PSX Gowin EDA 1.9.11.03 post-PnR simulation model, ddr3_memory_interface.vo"
    - "TinyVCMI tools/ddr3_openflow_preflight.sh and fpga/ddr3_phy_probe/ddr3_phy_probe.sv"
  verification: "The deterministic TinyVCMI preflight synthesized all six probes on 2026-10-22, reproduced the four no-BEL failures, and routed IODELAY and CLKDIV. A separate DDR-free open-flow image passed simulation, synthesis, placement, routing and packing, then was SRAM-loaded on the target and answered TinyTang core ID 0x56 at 2 Mbaud. Revised 2026-10-22 after the DDRDLL bel was added: the same preflight now reports DDRDLL PASS/PASS, with DQS, OSER8_MEM and IDES8_MEM unchanged, and the earlier citation of commit 8be8657b is corrected because the binary that produced the evidence self-reports 7d1b131c. DQS and the two memory serializers have not been implemented or tested. Revised 2026-10-23: the DQS site is tile (81,5), type 241, which carries no bels at all, and its control and status wires have since been measured by matched vendor pairs and are recorded in TOOL-007; the 54-pin IOLOGIC map statement above remains true of the chipdb. Revised 2026-10-23 after the DQS bel and dedicated links were added to the generator: the preflight's DQS probe was changed to the smallest lane the vendor accepts, a DDRDLL on DLLSTEP and DQSIN on pin Y3, and now reports DQS PASS beside DDRDLL, IODELAY and CLKDIV, with OSER8_MEM and IDES8_MEM still GAP. Revised again 2026-10-23: Apicula packs the DQS (get_DQS_fuses) and matches the vendor in table 58 when run in-process by tools/dqs_pack_check.py, but no image containing a DQS can be written while the packer's DDR3-bank guard refuses every bank 6/7 pad outside a declared DDR context, and that guard has no switch. Revised again 2026-10-23: the OSER8_MEM and IDES8_MEM probes are now lane-0 designs on Y3 and Y4 and pass, so the preflight reports all six primitives PASS. Revised 2026-10-23: the nextpnr fork models the DQS sites, dedicated links and serializer positions of all four lanes, locks each DQS to its strobe pad's site in pack_dqs, and tools/lane_open_build.py places and routes all 210 lane vendor designs as expected. Revised again 2026-10-23: Apicula packs the DQS of all four sites by table-58 key and the forty serializer positions, and tools/lane_open_build.py --pack passes 188 in-process packer checks against the vendor across the four lanes."

- record_id: TOOL-003
  topic_id: TOOL
  title: "Measured GW5AST-138C DDRDLL master sites, cells, features and ports"
  status: VERIFIED
  verified_date: 2026-10-23
  statement: "Gowin EDA 1.9.11.03 exposes four DDRDLL master placement macros, DDRDLLM_TL, DDRDLLM_TR, DDRDLLM_BL and DDRDLLM_BR. Vendor bitstreams localize their configuration to cells (0,0), (0,181), (108,0) and (108,181). The primitive is a two-cell macro: at the bottom-left master the port wires land in the column-1 tile, the vendor's one-based cell (109,2), while every configuration fuse sits in the corner cell (108,0). At that site CODESCAL 111 selects DLL0 feature 12 and 000 selects none, SCAL_EN TRUE feature 13, DIV_SEL 1 feature 14 and DLL_FORCE TRUE feature 15. The port map is CLKIN to CLK0, STOP to A6, RESET to LSR0, UPDNCNTL to A5 and STEP[0:7] to Q0 through Q7. LOCK reaches no configurable wire: with LOCK open the bitstream changes only on the row-99 track of column 1, wire Q7 driving E820, which is the recorded tap (100,2,Q7). The vendor baseline also sets DLL0 features 5, 17, 18 and 19 plus corner bits (1,12) and (9,13), none of which any parameter sweep moved."
  consequence: "Open-flow support can be built and has been built from this evidence for the bottom-left master: a bel on the port tile, a symbolic DDRDLLM_BL macro, and packing that writes the measured DLL0 features in the configuration cell, and, since 2026-10-23, a LOCK pin on a fuse-free node joined to Q7 of cell (99,1). Two things stay open and are not claims about the silicon: the other three masters' port tiles are unmeasured, and the six default corner bits are unexplained. No DDRDLL image has been built for or tested on hardware."
  sources:
    - "TinyVCMI tools/ddrdll_oracle and tools/run_ddrdll_oracle.sh"
    - "TinyVCMI docs/ddr3-open-flow.md: DDRDLL reverse-engineering and open-flow implementation"
    - "Gowin EDA 1.9.11.03 GW5AST-138C.fse and GW5AST-138C.dat"
    - "Apicula commit 8918f14, apycula/attrids.py, apycula/chipdb.py and apycula/dat_parser.py"
    - "aquasock/nextpnr branch epic/gw5ast138c, himbaechel/uarch/gowin/{gowin_arch_gen.py,cst.cc,constids.inc}"
    - "aquasock/apicula branch epic/gw5ast138c, apycula/gowin_pack.py get_DDRDLL_fuses"
  verification: "Eight offline vendor builds covered all four master placements and isolated CODESCAL, SCAL_EN, DIV_SEL and DLL_FORCE changes, and the BL deltas were re-derived from the raw bitstreams rather than the tile tables. Revised 2026-10-22: three further offline builds isolated the ports and LOCK (constants on STOP, UPDNCNTL and RESET; LOCK open; STEP open). The corner DLL0 tables agree with the TL, BL and BR baselines on features 12 to 15; TR's table has no entry for feature 12 or 13. The open-flow path reproduces the four measured feature sets and sets none of the three unset bits, which shows the packing is derived from the measurement; it does not show the primitive works. No Tang access occurred. Revised 2026-10-23: LOCK now has a pin on a fuse-free node to Q7 of cell (99,1), and the preflight's DDRDLL probe routes it through X1Y99/E820 <- Q7, the pip the vendor sets when LOCK is routed. Revised 2026-10-24: the corner bits (1,12) and (9,13) are the unused-pin DRIVE and DRIVE_LEVEL of the corner cell's bank-6 pad (TOOL-013), not DDRDLL configuration; DLL0 features 5, 17, 18 and 19 remain unattributed and are written under a declared DDR3 context because the vendor sets them in every build with a DDRDLL (TOOL-016). Revised again 2026-10-24: tools/ddrdll_port_probe.py --check asserts 19 vendor builds. Feature 5 is CLKIN from the port tile's CLK0: when the DLL's clock also drives a CLKDIV at LEFTSIDE[4+n], the vendor drops the GB10 -> CLK0 pip and sets features 21 and 4-n instead, at any frequency and from a pin or a PLL, so the port map's CLKIN has two sources. STOP, UPDNCNTL and RESET as constants, signals or inverted signals, clock constraints from 20 to 2.5 ns and a PLL clock at 50 to 400 MHz move no feature, except that an inverted RESET clears feature 19. Features 17, 18 and 19 remain unattributed. The open flow models both sources (TOOL-018)."

- record_id: TOOL-004
  topic_id: TOOL
  title: "The open-flow DDRDLL produces no tap code on hardware"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "An open-flow image carrying one DDRDLL at the measured bottom-left site, a 2 Mbaud TinyTang responder and a free-running counter was loaded into SRAM on 2026-10-22. The core answered core ID 0x56 and a query frame returning STEP with the counter. The counter advanced on every query while STEP read 0x00 in all of: STOP low with UPDNCNTL low, STOP low with UPDNCNTL high, STOP high with either UPDNCNTL level, and STOP low with UPDNCNTL low with the six vendor-default corner bits packed. The same source built by Gowin EDA 1.9.11.03 behaves identically: loaded at 4,330,802 bytes it answers core ID 0x56 and also reports STEP 0x00 with its counter advancing. Clocking the descriptor from an on-die PLL at 350 MHz -- 700 MHz VCO, CLKOUT0 divided by two, timing met at 350.02 MHz and PLL lock read as 1 -- still reports STEP 0x00 while both the 50 MHz and the 350 MHz domain counters advance. A further build moved STOP and UPDNCNTL both high, matching a working controller, and ran the PLL at the DDR3 memory clock, 50 MHz x16 / 2 = 400 MHz with timing met at 467 MHz reported; three reads again returned STEP 0x00 with lock 1 and both counters advancing. A vendor-built image adding one DQS block with DLLSTEP fed from the DLL, its DQSIN on non-DDR3 pin K21, also returned STEP 0x00 in three reads while the lane's own outputs were live. Driving UPDNCNTL as a pulse -- low for 16 of every 65536 fast cycles, the usage both the proven controller and the vendored LiteDRAM PHY follow -- returned STEP 0x00 as well. Gowin's own model of the primitive, IDE/simlib/gw5a/prim_sim.v, predicts 200 (0xC8) for a 50 MHz CLKIN with SCAL_EN FALSE, and that prediction does not hold on the silicon."
  consequence: "The tap value is a property of the primitive at this clock period, not of this project's toolchain: placement, port mapping and packed fuses produce the same observable as the vendor's own bitstream. A lock-and-step diagnostic still cannot be scheduled from STEP, and the plausible physical explanation -- that a DDR3-800 delay loop has nothing to report against a 20 ns clock -- is a hypothesis no test has yet checked, because the primitive has never been clocked at the rate it is meant to serve. The remaining structural difference from a working controller is the PHY around the primitive -- the distributed memory clock, the four DQS blocks and the init FSM -- and and a DQS beside the DLL does not change the reading either, and neither does pulsing UPDNCNTL. Six configurations across two toolchains have produced no tap code, so STEP is not a usable milestone signal and the primitive is evidently only meaningful inside the PHY that surrounds it, which also means LOCK cannot be observed in isolation. No DDR3 capacity or timing conclusion follows from this result."
  sources:
    - "TinyVCMI fpga/ddrdll_liveness/ddrdll_liveness.sv, tools/build_ddrdll_liveness.sh, tools/tang_console.py"
    - "TinyVCMI docs/ddr3-open-flow.md: hardware observation"
    - "Gowin EDA 1.9.11.03, IDE/simlib/gw5a/prim_sim.v, module DDRDLL"
  verification: "Four builds of one parameterised design were loaded in turn, each answering over the link; the reply carries a free-running counter that advanced between queries, which separates a silent primitive from a silent link. CLKIN was confirmed to be the port tile's CLK0 wire from the vendor const-input build's GB10 to CLK0 pip. No pin was probed and no DDR3 package pin was driven or exposed. Revised 2026-10-22 after the vendor reference: the identical source built by Gowin EDA reports the same zero, which removes this project's packing from the list of causes, and Gowin's .bin was verified to be the .fs data lines packed eight bits to a byte, so both images load raw with no conversion. Revised again after the PLL run: at 350 MHz with lock asserted and the fast counter proven moving, STEP is still zero, so the clock-period explanation is disproved at that rate and only an untested claim about 400 MHz specifically would survive it. Revised 2026-10-24: every image above, open-flow and vendor, clocked the DLL from the port tile's CLK0, DLL0 feature 5, because none had a CLKDIV on the DLL's clock; the proven controller clocks it from its CLKDIV's HCLK lane 0, features 21 and 4 (TOOL-003). The PHY bring-up image, clocked that way, reads STEP 0x2c in both its vendor and its open-flow build (TOOL-018). The zero above therefore stands as a measurement of the CLK0-clocked DLL only, and the hypothesis that the DLL needs the PHY around it is narrowed to its clock source, which an isolated DLL with a CLKDIV on its clock could test."

- record_id: TOOL-005
  topic_id: TOOL
  title: "How the hardware-proven vendor DDR3 controller drives the DDRDLL"
  status: VERIFIED
  verified_date: 2026-10-23
  statement: "The vendor DDR3 IP netlist kept by Tang-PSX places its DDRDLL at DDRDLLM_BL and instantiates it as CLKIN=memory_clk, STOP=the inverse of pll_lock, RESET=dll_rsti, UPDNCNTL=uddcntln, with STEP driving DLLSTEP on all four DQS blocks and also being registered into the 100 MHz domain, with CODESCAL 111, SCAL_EN FALSE, DIV_SEL 0 and DLL_FORCE FALSE. UPDNCNTL is driven by the init state machine rather than held at a level, and STOP reads 0 during normal operation because the LUT1 driving it, n2457_s2 with INIT=2'h1, inverts the active-high pll_lock. dll_rsti and uddcntln are flops on the IP's 50 MHz clk, preset by its reset. The same memory_clk drives the PHY's single CLKDIV, fclkdiv at LEFTSIDE[4] with DIV_MODE 4, whose output is every lane's PCLK, and the bitstream clocks the DLL from that CLKDIV's HCLK lane 0 (DLL0 features 21 and 4) with all four DQS on lane 0. The DQS blocks have no output back to the DLL. Its start-up order, including the memory-clock stop through the PLL's ENCLK2, is TOOL-019."
  consequence: "This is the reference behaviour for an open-flow PHY: same master site, same four parameters this project packs, and a control sequence rather than static levels. Because the only coupling from DQS to the DLL is one way, an isolated DDRDLL with no PHY around it is not demonstrated to run by this design, which is consistent with this project's STEP readings and means a standalone lock-and-step diagnostic may not be physically meaningful."
  sources:
    - "Tang-PSX build/ddr3-vendor/ip/ddr3_memory_interface/ddr3_memory_interface.vo, DDRDLL instance gw3_top/u_ddr_phy_top/u_dll and the four DQS instances"
    - "Tang-PSX gateware/ddr3_vendor/tang_psx_ddr3.cst, INS_LOC u_dll DDRDLLM_BL"
    - "Tang-PSX gateware/gowin_ddr3.py, PLL_INIT feeding pll_lock"
    - "Tang-PSX third_party/litedram/litedram/phy/gw5ddrphy.py, GW5DDRPHYInit (BSD-2-Clause, upstream, not hardware-proven here)"
  verification: "Read directly from the vendored post-place-and-route netlist and the constraint file on 2026-10-23, cross-checked against TinyVCMI TOOL-002 for the site and TOOL-003 for the parameters. The LiteDRAM PHY's own DDR3 attempt in Tang-PSX never deployed because every placement variant failed setup timing, so its sequence is a design intent, not a hardware result. Revised 2026-10-24: the STOP driver was re-read as LUT1 n2457_s2, INIT=2'h1, an inverter, which corrects the earlier reading of a buffer that held STOP at 1; the CLKDIV, its LEFTSIDE[4] placement and the 50 MHz control flops were read from build/gate1-ip/ddr3_memory_interface/ddr3_memory_interface.vo and tang_psx_ddr3.cst, and the DLL0 features and the empty DQS lane fields were decoded from build/ddr3-vendor/place1/impl/pnr/tang_psx_ddr3.fs."

- record_id: TOOL-006
  topic_id: TOOL
  title: "The memory-mode IOLOGIC primitives are one lane complex"
  status: VERIFIED
  verified_date: 2026-10-23
  statement: "In the hardware-proven vendor DDR3 netlist every one of the 40 OSER8_MEM instances takes TCLK from its own lane's DQS output, dqsw0 for nine per lane and dqsw270 for the tenth, and Gowin EDA rejects driving TCLK from an ordinary pin because TCLK_SOURCE is DQSW or DQSW270, and it refuses to build a DQS at all unless its DLLSTEP pin is driven by a DDRDLL instance, answering PR0015. Per lane the vendor instantiates one DQS, ten OSER8_MEM and eight IDES8_MEM, which is where the inventory's 4, 40 and 32 counts come from."
  consequence: "TCLK, DLLSTEP and the DQSW group are not fabric wires to be named; they are dedicated connections inside a lane between the DQS block and the serializers beside it. The unit of implementation is therefore the lane complex, and the chip database has to express those internal connections rather than three independent BELs, exactly as the DDRDLL LOCK output needs a dedicated path. Measuring three separate wire names would be measuring something that does not exist."
  sources:
    - "Tang-PSX build/ddr3-vendor/ip/ddr3_memory_interface/ddr3_memory_interface.vo, the 40 OSER8_MEM TCLK connections and per-lane instance counts"
    - "Gowin EDA 1.9.11.03 IDE/simlib/gw5a/prim_sim.v, module OSER8_MEM TCLK_SOURCE parameter"
    - "Gowin EDA 1.9.11.03 error CK2060 observed when TCLK was driven from a pin in TinyVCMI build/meas_oser/oser"
  verification: "Read from the vendored post-place-and-route netlist and confirmed against two vendor build attempts: one that Gowin refused for driving TCLK from a pin, and one it refused for a DQS without a DDRDLL on DLLSTEP. The four-lane split was checked by counting instances per data_lane_gen index. Revised 2026-10-23: tools/dq_lane_probe.py drove ICLK, WADDR, RADDR and TCLK each from a fabric register in otherwise proven lane designs and Gowin refused all four with CK2060, while the proven wiring built; the hard-wired set is therefore TCLK, ICLK, WADDR and RADDR from the DQS plus DLLSTEP from the DDRDLL."

- record_id: TOOL-007
  topic_id: TOOL
  title: "Measured GW5AST-138C DQS site wires"
  status: VERIFIED
  verified_date: 2026-10-23
  statement: "With DQS at the site Gowin EDA 1.9.11.03 assigns beside board pin Y3, the control and status pins are in tile (81,5), type 241, which has no bels. Inputs: RDIR A0, RLOADN A1, RMOVE A2, READ[0:3] A3 A4 A5 A7, WDIR B0, WLOADN B1, WMOVE B2, HOLD B3, RCLKSEL[0:2] C0 C1 C2, WSTEP[0:7] D3 D4 D5 D7 CLK2 LSR2 CE1 CE2, PCLK CLK0 and RESET LSR0. Outputs: DQSR90 Q0, DQSW270 Q1, RPOINT[1] Q2, WPOINT[1] Q3, RVALID Q5, RFLAG Q6, WFLAG Q7, DQSW0 F1, RPOINT[0] F2, WPOINT[0] F3, RPOINT[2] F4, WPOINT[2] F5 and RBURST F6. DLLSTEP accepts only a DDRDLL STEP (PR0015). DQSIN accepts only a DQS pad buffer (PR0014, CK3001); in the proven vendor netlist ELVDS_IOBUF.O drives it directly, and Y3 is IOL69A, whose ordinary input wire is F6 in tile (68,0). FCLK has no fabric pin. It is a sink of the left HCLK block whose fabric-entry tile is (81,0), where CLK1, CLK2 and LSR2 are the lane entries L2HCLK21, L2HCLK22 and L2HCLK23; a register source routed lane 2 (HCLK_MUX_BETA22 <- L2HCLK22, HCLK_BUF_BI22 <- HCLK_MUX_BETA22, HCLK_MUX_ALPHA22 <- HCLK_BUF_BO22) and the board clock lane 3, and the DQS selects the lane in longfuses table 58 of tile (72,0), type 64: keys 38 and 41, fuses (20,108) and (20,107), for lane 2, and keys 39 and 42, adding (20,56) and (20,53), for lane 3. No FCLK fuse changes in (81,5). Table 58 exists at 24 cells, eight on each long edge and eight on the bottom, one per byte group."
  consequence: "The DQS bel's control and status pins can be written for tile (81,5) from measured wires, and the tile holds no DQS configuration; that is recorded in TOOL-008. Three connections are not ordinary portmap entries and must be modelled before the bel is complete: DLLSTEP as an internal net from the DDRDLL, DQSIN as a fuse-free path from the pad tile (68,0), and FCLK, which needs pips from the HCLK lanes carrying table-58 select fuses at the byte group's config tile, in the way IOLOGIC FCLK already has HCLK pips. The keys form two identical two-bit fields holding the lane number; all four lanes are measured in TOOL-008, and lane 0 sets no fuse, so it cannot be told apart from an unclocked block by fuses. This selector is separate from IOLOGIC FCLKSEL, which on this device reaches lanes 0 and 2 only. The macro is multi-tile because of those three, not because of its outputs."
  sources:
    - "TinyVCMI tools/dqs_map_check.py, tools/dqs_port_probe.py, tools/dqs_output_probe.py and tools/fs_site_diff.py"
    - "TinyVCMI docs/ddr3-open-flow.md: DQS site pin measurement"
    - "Apicula commit 1d43011, apycula/GW5AST-138C.msgpack.xz: tile type 241 pips, hclk_pips at (81,0), nodes HCLK2_L2HCLK21 to 23, and tile type 64 longfuses unknown_58"
    - "Tang-PSX build/ddr3-vendor/ip/ddr3_memory_interface/ddr3_memory_interface.vo, ELVDS_IOBUF to DQS.DQSIN"
  verification: "tools/dqs_map_check.py re-derived every entry on 2026-10-23 from the matched pairs in build/dqs_routed, build/dqs_clock and build/dqs_outputs by exact mux state and passed: each input pair changes exactly one site-input destination, and each of ten outputs changes exactly one destination in (81,5), selecting the listed wire. DQSR90, DQSW270 and RVALID change no fuse in (81,5); their wires are inferred because the first hop's mux is in its zero state, which itself selects Q0, Q1 and Q5, and their next hops match those of measured siblings through the same destinations. That inference relies on the chipdb's zero-state encoding and is not a direct measurement. The same check corrected an earlier reading that placed those three outputs at (69,7) and (81,1), which are downstream hops, and withdrew FCLK -> CLK2 at (81,0) as a measurement. No hardware was accessed. Revised 2026-10-23: both FCLK pairs were rebuilt from the current probe template in build/fclk_rebuild and are fuse-identical to the earlier clock pair, which shows the vendor tool is deterministic and that the earlier CLK1 reading came from a template change; decoding (81,0) through hclk_pips accounts for every changed fuse there as one lane's chain, (72,0)'s only changed fuses are the table-58 entries above, and tools/dqs_map_check.py asserts all three for both pairs. Revised again 2026-10-23: lanes 0 and 1 were measured with pinned CLKDIV designs and match the field reading, and the per-port constant bits of docs/ddr3-open-flow.md were shown to be routing, which removed them from the consequence."

- record_id: TOOL-008
  topic_id: TOOL
  title: "Measured GW5AST-138C DQS configuration encoding"
  status: VERIFIED
  verified_date: 2026-10-23
  statement: "For the DQS beside board pin Y3, Gowin EDA 1.9.11.03 writes every configuration fuse into longfuses table 58 of tile (72,0), type 64, and none into the DQS site tile (81,5). In that tile's coordinates: presence (20,57) (20,58) (20,59) (20,62) (20,63) (20,68) (20,73) (20,91); FIFO_MODE_SEL 1 = (20,36) (20,67); RD_PNTR bit 0 = (20,64), bit 1 = (20,49), bit 2 = (20,52); DQS_MODE X1 = none, X2_DDR2 = (20,79), X2_DDR3 = (20,78), X4 = (20,78) (20,79), X2_DDR3_EXT = (20,78) (20,90); HWL true = (20,103); FCLK on HCLK lane 0 = none, lane 1 = (20,53) (20,56), lane 2 = (20,107) (20,108), lane 3 = all four. Table 58 exists at 24 cells: rows 9, 18, 36, 45, 63, 72, 90 and 99 of both long edges and eight on the bottom edge. Only CLKDIV accepts INS_LOC LEFTSIDE[n] for lane pinning; CLKDIV2 and DHCE are refused with CT2001."
  consequence: "A packer can write a DQS's whole configuration from this table without naming physical fuse coordinates: the presence fuses, the four parameters and the FCLK lane are selected by table key at the byte group's config tile, in the same shape as the DDRDLL's DLL0 features. Lane 0 sets nothing and therefore reads like an unclocked block. The presence fuses were constant across every design tried, but every design used the same DQS ports, so their dependence on port usage is untested. TOOL-012 verifies the same semantic keys at all four onboard DDR3 byte groups; the other twenty table-58 cells remain unmeasured. The Apicula fork packs the encoding as get_DQS_fuses at all four byte groups, holding it as the table-58 keys presence 11 12 17 18 21 22 23 29, FIFO_MODE_SEL 10 19, RD_PNTR 13 14 15, DQS_MODE X2_DDR2 31 35, X2_DDR3 32, X4 36, X2_DDR3_EXT 33 34, HWL 30 and FCLK lanes 1 to 3 as 37 40, 38 41 and 39 42."
  sources:
    - "TinyVCMI tools/dqs_param_probe.py (designs, --report, --check) and tools/fs_attribute.py"
    - "TinyVCMI docs/ddr3-open-flow.md: DQS configuration: longfuses table 58"
    - "Gowin EDA 1.9.11.03 IDE/simlib/gw5a/prim_sim.v, module DQS parameter list"
    - "Apicula commit 1d43011, apycula/GW5AST-138C.msgpack.xz: tile type 64 longfuses unknown_58 and hclk_pips at (81,0); apycula/chipdb.py P1.T08d LEFTSIDE convention"
  verification: "Fifteen vendor builds on 2026-10-23 in build/dqs_b1: a base, nine single-parameter variants, a design without the DQS and four pinned-lane designs. tools/fs_attribute.py attributed each variant's full difference from the base with no unattributed fuse, and every change outside routing, global clock and HCLK fell in table 58 at (72,0). tools/dqs_param_probe.py --check asserts the exact table-58 fuse set of all fifteen builds, each lane design's BETA, BUF and ALPHA chain at (81,0), and zero unattributed fuses, and passed. The same attribution showed that the per-port constant bits recorded earlier at (81,5) are routing: the HOLD constant pair's eight bits are the B3 input mux choosing VCC through W240 or GND through X04. No hardware was accessed. Revised 2026-10-23: tools/dqs_pack_check.py ran the Apicula packer in-process on all twelve B1 designs built in the open flow; its table-58 fuses equal this encoding in every case and the vendor build outside the lane field, exactly where the lanes agree, and lanes 1 to 3 were checked through --fclk-lane because the open router always chose lane 0. No image was written, since the packer refuses any bank 6/7 pad outside a declared DDR context. Revised 2026-10-23: with the router keeping the DQS on its CLKDIV's lane, tools/dqs_pack_check.py matched the vendor's lanes 1, 2 and 3 with real routing, without --fclk-lane. Revised again 2026-10-23: TOOL-012 normalized all fifteen designs by table key at byte groups (99,0), (90,0) and (63,0); every target tile reconstructed exactly with the same keys, its HCLK chain and zero unattributed fuses."

- record_id: TOOL-009
  topic_id: TOOL
  title: "Measured GW5AST-138C lane-0 DQ serializers"
  status: VERIFIED
  verified_date: 2026-10-23
  statement: "Lane 0 of the proven controller puts the strobe pair on Y3/AA3 and dq[7:0] and dm[0] on IOLOGIC A and B of the left-edge cells at rows 68, 70, 73, 75, 77 and 79. Every OSER8_MEM takes TCLK from the lane DQS's DQSW0, except the strobe serializer, which takes DQSW270 with TCLK_SOURCE=DQSW270. Every IDES8_MEM takes ICLK from DQSR90, WADDR from WPOINT and RADDR from RPOINT, and Gowin EDA 1.9.11.03 refuses any of the four from a fabric register with CK2060. The configuration is named IOLOGIC attributes in the serializer side's short-value table, side A in the pad's cell and side B in the cell below: IDES8_MEM writes INMODE=MIDDRX4, FIFO=ENABLE and CLKIMUX=ENABLE; OSER8_MEM writes OUTMODE=MODDRX4, CLKOMUX=ENABLE and WRFCLKSEL equal to TCLK_SOURCE, plus TXCLK_POL=1 and HWL=TRUE when those parameters are set. The FCLK lane is chosen by FCLKSEL attributes that differ between the two primitives, and the vendor uses all four HCLK lanes for IOLOGIC FCLK."
  consequence: "The open model needs the four memory-mode pins as fuse-free links from the DQS outputs, as DLLSTEP already is, at the ten lane-0 IOLOGIC positions the proven pin map uses, and a packer that writes the attribute sets above through the existing IOLOGIC attribute path, which already offsets side B by one cell. Several attribute names share one fuse set, so acceptance must compare fuses, not names. The Apicula fork's IOLOGIC FCLK model reaches lanes 0 and 2 only; that is a limit of its FCLKSEL1/FCLKSEL2 encoding, not of the silicon, and it suffices while the DQS and its serializers share a lane the model can spell."
  sources:
    - "TinyVCMI tools/dq_lane_probe.py (designs and --check) and tools/fs_attribute.py"
    - "TinyVCMI docs/ddr3-open-flow.md: DQ serializers: OSER8_MEM and IDES8_MEM"
    - "Tang-PSX build/ddr3-vendor/ip/ddr3_memory_interface/ddr3_memory_interface.vo, data_lane_gen[0] OSER8_MEM and IDES8_MEM instances"
    - "Tang-PSX gateware/ddr3_vendor/tang_psx_ddr3.cst, ddr_dq, ddr_dm and ddr_dqs pins"
    - "Gowin EDA 1.9.11.03 IDE/simlib/gw5a/prim_sim.v, modules OSER8_MEM and IDES8_MEM"
    - "Apicula commit c85ed79, apycula/attrids.py iologic_attrids/attrvals and GW5AST-138C.msgpack.xz IOLOGIC logicinfo"
  verification: "Twenty-one Gowin EDA builds on 2026-10-23 in build/dq_lane and build/dq_lane_b: the proven IDES8_MEM and OSER8_MEM on dq[0] (side A) and dm[0] (side B), four fabric-sourced variants that Gowin refused, three OSER8_MEM parameter variants, and both primitives with FCLK pinned to each HCLK lane. tools/dq_lane_probe.py --check asserts the refusals, the exact decoded attribute set of every built design on its side's cell, every lane design's HCLK chain and no unattributed fuse against the B1 base, and passed. Only dq[0] and dm[0] were built; the other nine lane positions come from the proven pin map, not from builds. No hardware was accessed. Revised 2026-10-23: the nextpnr fork models the ten positions with fuse-free links and packs both primitives; the vendor designs place and route in the open flow with the memory-mode pins on the DQS nets bit for bit, the fabric-sourced shapes fail routing as Gowin refuses them, and per-bit builds confirmed OSER8_MEM.D<i> on IOLOGIC D<i> and IDES8_MEM.Q<i> on IOLOGIC Q<8+i>. Revised again 2026-10-23: the Apicula fork packs both primitives, and tools/dq_pack_check.py finds its IOLOGIC fuses equal to the vendor's on both sides on lane 0, on lane 2 through --fclk-lane, and outside the lane field for every parameter variant; the input's lane-0 selection is FCLKSEL5=HCLK0 and FCLKSEL3=HCLK0 and its lane-2 selection is empty, and both reset muxes must be written at 0 to keep their absence entries clear. Revised 2026-10-23: the nextpnr fork now keeps a net that feeds a DQS FCLK on its CLKDIV's HCLK lane, as the vendor does, so the serializers' lane-2 encoding was confirmed with real routing rather than a rewrite; a CLKDIV on lane 1 or 3 still splits such a net, with a warning, because IOLOGIC FCLK reaches lanes 0 and 2 only."

- record_id: TOOL-010
  topic_id: TOOL
  title: "Measured GW5AST-138C lane-0 pad shapes"
  status: VERIFIED
  verified_date: 2026-10-23
  statement: "Gowin EDA 1.9.11.03 builds lane 0's proven pad shapes on pin Y4 (dq[0]), Y3/AA3 (strobe) and AA4 (dm[0]). A bidirectional DQ pad, an IOBUF driven by OSER8_MEM Q0/Q1 with its O reaching IDES8_MEM through a static IODELAY, has IOLOGIC fuses equal to the union of the two serializers' plus three for the IODELAY: C_STATIC_DLY and the unnamed attribute 133 at value 118, fuse (11,15) of side A. Gowin also builds the pad without the IODELAY. The ELVDS_IOBUF strobe's IOLOGIC is the plain OSER8_MEM set with WRFCLKSEL=DQSW270 and its complement side is empty; the TBUF DM's is the plain set on side B. LVCMOS33 against SSTL15 changes no IOLOGIC fuse, only the pads' IOB entries and bank 6's longval BANK table in cell (90,0)."
  consequence: "Nothing beyond the single-serializer model is needed at IOLOGIC level except the IODELAY's unnamed attribute, which the packer now writes by its logicinfo index. The remaining difference between an open-flow lane and the vendor's is IOB and bank configuration for SSTL15 and SSTL15D on bank 6, which is exactly what the packer's DDR3-bank guard refuses; comparing it is part of deciding that guard."
  sources:
    - "TinyVCMI tools/dq_pad_probe.py (designs and --check), tools/dq_pack_check.py and tools/fs_attribute.py"
    - "TinyVCMI docs/ddr3-open-flow.md: Lane 0's complete pads"
    - "Tang-PSX build/ddr3-vendor/ip/ddr3_memory_interface/ddr3_memory_interface.vo, dq_iobuf_gen, dq_iodelay, dqs_iobuf_gen and dm_obuf_gen instances"
    - "Tang-PSX gateware/ddr3_vendor/tang_psx_ddr3.cst, SSTL15 and SSTL15D IO_PORT lines"
  verification: "Six vendor builds on 2026-10-23 in build/dq_pad; tools/dq_pad_probe.py --check asserts every pad's IOLOGIC attributes, the fuse-level union, that SSTL configures only the pad cells and (90,0), and no unattributed fuse against the B1 base, and passed. The open flow places and routes all six, and tools/dq_pack_check.py finds the open packer's IOLOGIC fuses equal to the vendor's outside the lane field for each. Only side A was built with an IODELAY, and the IOB and BANK fuses have not been compared against the open packer. No hardware was accessed."

- record_id: TOOL-011
  topic_id: TOOL
  title: "Located GW5AST-138C DDR3 lanes 1 to 3"
  status: VERIFIED
  verified_date: 2026-10-23
  statement: "The proven controller's four lanes are all on the left edge: lane 0 on IO rows 68 to 79, lane 1 on 95 to 106, lane 2 on 82 to 93 and lane 3 on 55 to 66, with DQS pads Y3, V9, W6 and R3. With the strobe pad moved to each lane, Gowin EDA 1.9.11.03 adds configuration only in table 58 of one cell inside the lane's rows -- (72,0) type 64, (99,0) type 257, (90,0) type 259 and (63,0) type 270 -- and the DQS's inputs land at sites (81,5) and (81,6), both type 241, for lanes 0 and 3, and in the byte-group cells (99,0) and (90,0) themselves for lanes 1 and 2. In every lane the DQS moves exactly lane 0's 24 input destinations at its site tile, and each site tile has all 24 as pip destinations."
  consequence: "Lane 3 can reuse lane 0's site shape in the twin tile (81,6), while lanes 1 and 2 need a DQS bel in their IO-column byte-group cells. TOOL-012 closes the per-port, table-58 and representative IOLOGIC measurements that this location record originally left open. The nextpnr fork carries all four sites as of 2026-10-23."
  sources:
    - "TinyVCMI tools/dq_lane_locate.py and tools/fs_attribute.py"
    - "TinyVCMI docs/ddr3-open-flow.md: Lanes 1 to 3: where they are"
    - "Tang-PSX gateware/ddr3_vendor/tang_psx_ddr3.cst, ddr_dqs, ddr_dq and ddr_dm pins"
  verification: "Six vendor builds on 2026-10-23 in build/dq_lanes, a base and a no-DQS control per lane, attributed with no unattributed fuse; the site and byte group of each lane were read from that attribution and the site tiles' input destinations compared with lane 0's. Revised 2026-10-23 after the per-port and IOLOGIC measurements in TOOL-012 closed the remaining qualification work. No hardware was accessed."

- record_id: TOOL-012
  topic_id: TOOL
  title: "Measured DQS and IOLOGIC equivalence of DDR3 lanes 1 to 3"
  status: VERIFIED
  verified_date: 2026-10-23
  statement: "Gowin EDA 1.9.11.03 gives lanes 1 to 3 the same DQS port wires as lane 0: 24 inputs on A0-A5, A7, B0-B3, C0-C2, D3-D5, D7, CLK0, CLK2, LSR0, LSR2, CE1 and CE2, and thirteen outputs on Q0, F1, Q1, Q5, F6, Q6, Q7, F2, Q2, F4, F3, Q3 and F5. Lane 2 RESET reaches LSR0 through the already-selected W212 source, so changing its upstream source moves no site fuse. The table-58 cells of types 257, 259 and 270 use the same semantic keys as lane 0's type 64 for presence, FIFO_MODE_SEL, RD_PNTR, DQS_MODE, HWL and all four FCLK lanes, with different physical coordinates. Representative A/B DQ pads AA8/AB8, R4/T4 and W2/Y2 use the same OSER8_MEM and IDES8_MEM attributes, hard-wired pins and data-bit order as lane 0, including the side-B one-cell configuration offset."
  consequence: "The nextpnr and Apicula models can extend one measured DQS port map, one table-58 key encoding and one memory-serializer encoding across all four byte lanes, changing only each lane's site, byte-group cell, pad positions and dedicated-link endpoints. This does not qualify SSTL15 or SSTL15D IOB and BANK packing, remove the DDR3-bank guard, produce a packable lane image or establish DDR3 operation on hardware."
  sources:
    - "TinyVCMI tools/dqs_map_check.py, tools/dqs_param_probe.py, tools/dq_lane_probe.py and tools/lane_open_build.py"
    - "TinyVCMI docs/ddr3-open-flow.md: Lanes 1 to 3: where they are, and Four lanes in the open flow"
    - "aquasock/nextpnr branch epic/gw5ast138c, himbaechel/uarch/gowin/gowin_arch_gen.py DQS_LANES and pack_iologic.cc pack_dqs"
    - "Tang-PSX commit 61974ca, gateware/ddr3_vendor/tang_psx_ddr3.cst"
    - "Gowin EDA 1.9.11.03 vendor builds under build/dqs_routed_l1 through build/dqs_b1_l3 and build/dq_lane_l1 through build/dq_lane_b_l3"
  verification: "For each of lanes 1 to 3, tools/dqs_map_check.py --lane N passed all 24 inputs and thirteen outputs; outputs were traced backward from the fixed probe pad through the exact configured route, removing the earlier zero-state and shared-hop ambiguity. tools/dqs_param_probe.py --check --lane N passed all fifteen designs with exact target-tile fuse reconstruction, the expected HCLK chain and zero unattributed fuses. The A-side serializer suite passed 33 of 33 outcomes per lane, including four expected CK2060 refusals, and the two accepted B-side designs per lane also passed with zero unattributed fuses. No hardware was accessed. Revised 2026-10-23: the nextpnr fork applies the shared port map and serializer pins to all four lanes from one lane table, and every lane-1-to-3 vendor design places and routes in the open flow with the DQS on its lane's site and every memory-mode pin on its DQS output's net (tools/lane_open_build.py). Revised again 2026-10-23: Apicula's get_DQS_fuses writes the encoding by table-58 key at each lane's byte group and its serializer handlers accept all forty positions; tools/lane_open_build.py --pack found the packer equal to the vendor by key for all 56 DQS designs and by IOLOGIC fuse state, exactly or outside the lane field, for all 132 serializer designs."

- record_id: TOOL-013
  topic_id: TOOL
  title: "Open-packer DDR3-bank IO configuration against the vendor"
  status: VERIFIED
  verified_date: 2026-10-23
  statement: "Banks 6 and 7 of the GW5AST-138C hold every DDR3 ball: bank 6 the 44 data-lane balls on left-edge rows 55 to 108, with its BANK longval table at cell (90,0); bank 7 the 28 address, command and clock balls on rows 0 to 54, with its BANK table at (18,0). Side A's IOB configuration is longval IOBA in the pad's cell and side B's is IOBB in the cell below. This die's IOB tables key IO_TYPE on SSTL15 and SSTL15D themselves, and the family codes SSTL and SSTL_D have no logicinfo entry. Packed in memory against Gowin EDA 1.9.11.03 builds of lane 0's four SSTL pad designs, the open packer's fuses equal the vendor's for the SSTL15 input strobe on Y3 and for bank 7's BANK table. They differ elsewhere. The DQ IOBUF on Y4 lacks TRI_MUX=TMDDR and SLEWRATE=FAST, (8,4) and (10,14). The DM TBUF lacks (1,12) and (5,2). The SSTL15D strobe pair lacks four fuses on each side. Every unused pad lacks two fuses the vendor sets, (1,12) and (9,13) on side A and (1,14) and (4,1) on side B. Unused bank-6 pads beside a single-ended SSTL15 pad carry (2,3) and (2,6), or (3,1) and (3,10), which the vendor leaves clear. Bank 6's BANK table lacks (20,20), (20,50) and (20,52) under SSTL15 and has (20,44) where the vendor has (20,43) under SSTL15D."
  consequence: "Before the 2026-10-23 corrections, lifting the DDR3-bank refusal would have written configuration the vendor does not write on every pad of the DDR3 rail; with them, the measured lane and bank-7 shapes match, but the full bank 7 and a whole-controller pad set are still uncompared, so no declared DDR context may yet admit an image. The unused-pad difference also appears on ordinary banks 2 and 3, 99 of 100 pads, so it is how the packer treats an unused pad on this die for every core; correcting it inside a declared DDR context for banks 6 and 7 only leaves every other core's bitstream unchanged."
  sources:
    - "TinyVCMI tools/ddr_bank_check.py"
    - "TinyVCMI docs/ddr3-open-flow.md: DDR3 banks: IO configuration against the vendor"
    - "TinyVCMI build/dq_pad/{dq_sstl,dq_nodelay_sstl,dm_sstl,dqs_sstl} vendor builds and build/open/dq_pad routed netlists"
    - "aquasock/apicula branch epic/gw5ast138c, apycula/gowin_pack.py GW5AST_138C io_type_alias, add_io_to_bank and BankDesc"
    - "Tang-PSX commit 61974ca, gateware/ddr3_vendor/tang_psx_ddr3.cst, bank and IO_TYPE of every DDR3 ball"
    - "Tang-PSX build/ddr3-vendor/ip/ddr3_memory_interface/ddr3_memory_interface.vo, OSER8, OBUF and ELVDS_OBUF instances of u_ddr_phy_cmd_lane"
    - "TinyVCMI tools/dq_pad_probe.py --lane N, tools/cmd_pad_probe.py and tools/unused_pin_probe.py"
    - "aquasock/apicula branch epic/gw5ast138c, apycula/gowin_pack.py BankDesc.add_io_bel and GW5AST_138C.get_unused_io_attrvals, get_unused_io_type, set_io_attrvals, check_io_banks and _ddr_n_half_io_type"
    - "aquasock/nextpnr branch epic/gw5ast138c, himbaechel/uarch/gowin/pack_iologic.cc check_iologic_placement"
  verification: "tools/ddr_bank_check.py ran gowin_pack's stages in memory with ddr_context set on one device instance and no bitstream object, and compared all 100 bank 6/7 pad tables and both BANK tables restricted to each table's own fuses on all four designs. The ordinary-bank comparison used the same packed result on banks 2 and 3. Bank 7's used pads and the SSTL pads of lanes 1 to 3 have no vendor builds yet. No image was written and no hardware was accessed. Revised 2026-10-23: lanes 1 to 3 (tools/dq_pad_probe.py --lane N) show exactly lane 0's signatures, and the used-pad pair TRI_MUX=TMDDR and SLEWRATE=FAST follows the pad's side. Bank 7 (tools/cmd_pad_probe.py) exposed two further gaps. The open flow's plain OSER8 takes both IOLOGIC halves of a cell, so the full 28-ball bank cannot be placed. BankDesc.add_io_bel tests bel.is_mipi without calling it, so a differential output's N half with no IO_TYPE sets the bank's LVDS VCCIO to 2.5 V, which programs bank 6 for 2.5 V under an SSTL15D strobe and is the (20,44)/(20,43) difference; the line is on upstream master. The unused-pin difference is DRIVE=8 and DRIVE_LEVEL=8: tools/unused_pin_probe.py found the GW5A base set equal to Gowin EDA 1.9.11.03 on Linux on 199 of 199 unused left- and right-edge pins and the fork's no-drive rule on none, under both this project's and the fork harness's build recipe and constraint conventions. That contradicts the fork's P3.T26/D108 corpus, which is on another host and was built with the harness's macOS default install; the platform and the corpus remain untested explanations. The user chose to follow these measurements for banks 6 and 7 inside a declared DDR context only. Revised again 2026-10-23: the Apicula fork now writes the vendor's configuration with ddr_context set and only on banks 6 and 7. Unused pins carry DRIVE=8 and DRIVE_LEVEL=8 under the unused default standard. A differential N half takes its P half's IO_TYPE and IOLOGIC_IOB. Outputs are SLEWRATE=FAST, serializer-tristated pads TRI_MUX=TMDDR, the SSTL15D clock drops DRIVE_LEVEL and PADDI, and the strobe is IOB_UNKNOWN51=TRIMUX with the design's PULLMODE. A bank with a single-ended SSTL15 input, a DQ IOBUF alone included, is VREF=INTERNAL, and a bank with only SSTL15D pairs is IO_TYPE=SSTL15D. tools/ddr_bank_check.py then finds all 102 tables equal on all 21 SSTL designs that place: four lanes of lane_sstl, dq_sstl, dq_nodelay_sstl, dqs_sstl and dm_sstl, plus cmd_min_sstl. With ddr_context off, seven non-DDR netlists pack to unchanged fuses. The nextpnr fork's check_iologic_placement no longer makes OSER8_MEM and IDES8_MEM claim their cell's other IOB, which lane 0's shared dq[0]/dm[0] cell needs; plain OSER8 still does, so the full 28-ball bank 7 remains unplaced and uncompared."

- record_id: TOOL-014
  topic_id: TOOL
  title: "Plain OSER8 side use and the whole DDR3 pad set"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "On the GW5AST-138C, Gowin EDA 1.9.11.03 configures a plain OSER8 on its own IOLOGIC side only: on bank-7 cell IOL35 (M1/L1) a serializer on side A sets six IOLOGIC fuses at (34,0) and none at (35,0), one on side B six at (35,0) and none at (34,0), and one on each side exactly the union. The proven controller places OSER8s on both sides of bank-7 cells. One design carrying the controller's whole pad set on its proven pins -- one DDRDLL, four DQS with SSTL15D strobe pairs, 32 DQ IOBUFs with OSER8_MEM, IODELAY and IDES8_MEM, four DM TBUFs, and bank 7's 25 address and command OSER8s, OSER8-driven SSTL15D clock pair and reset_n -- builds in the vendor tool."
  consequence: "The open model gives a plain OSER8 on this die neither the other side's IOB nor an aux cell, which wrote no fuse, so the full bank 7 places and existing designs' bitstreams do not change. With that and the lane and bank corrections of TOOL-012 and TOOL-013, the whole pad set places, routes and packs in-process to the vendor's fuses: four DQS by table key, 130 serializers' IOLOGIC outside the HCLK lane field, and all 102 bank 6/7 IOB and BANK tables. The lane fields remain compared apart because the probe clocks everything from the board pin and the IOLOGIC model offers lanes 0 and 2 only. This is fuse equivalence for the pad set, not a written image, a declared DDR context or a hardware result."
  sources:
    - "TinyVCMI tools/cmd_pad_probe.py (cmd_m1_sstl, cmd_l1_sstl, cmd_pair_sstl, cmd_full_sstl) and tools/ddr3_pad_set_probe.py"
    - "TinyVCMI tools/dq_pack_check.py, tools/dqs_pack_check.py, tools/ddr_bank_check.py and tools/lane_open_build.py"
    - "TinyVCMI docs/ddr3-open-flow.md: Bank 7 in full, and the whole controller's pad set"
    - "aquasock/nextpnr branch epic/gw5ast138c, himbaechel/uarch/gowin/pack_iologic.cc oser8_one_side"
    - "Tang-PSX build/ddr3-vendor/ip/ddr3_memory_interface/ddr3_memory_interface.vo, u_ddr_phy_cmd_lane OSER8 instances; gateware/ddr3_vendor/tang_psx_ddr3.cst"
  verification: "Three single-cell vendor builds decoded at both IOLOGIC configuration cells, and the open flow's single-side builds compared fuse for fuse, equal outside the lane field with nothing on the other side. After the nextpnr change all five bank-7 designs and the pad set place and route; tools/dq_pack_check.py, tools/dqs_pack_check.py and tools/ddr_bank_check.py pass on each against its vendor build. No image was written and no hardware was accessed."

- record_id: TOOL-015
  topic_id: TOOL
  title: "The declared DDR3 context"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "The aquasock/apicula fork admits a pad on GW5AST-138C banks 6 and 7 only when the design is packed with gowin_pack --ddr3-context MANIFEST, a flag no other device accepts. The manifest is checked against the die on load: every ball a bank 6/7 pad at its claimed IO site, SSTL15 on a single ball, SSTL15D on both halves of a pair that name each other in one IO cell, and settings exactly BANK_VCCIO=1.5, PULL_MODE=NONE, DRIVE=8. Inside the context each bank 6/7 pad must be a listed ball at exactly its listed standard and pair half, carry BANK_VCCIO=1.5 and PULL_MODE=NONE, DRIVE=8 on an output and no drive on an input, and no other IO attribute, and a used DDR3 bank must resolve to 1.5 V; anything else is refused by name. TinyVCMI's manifest, fpga/ddr3/ddr3_balls.json, lists the board's 72 DDR3 balls, 44 on bank 6 and 28 on bank 7 with five SSTL15D pairs, generated from the proven pin map."
  consequence: "A design that owns the DDR3 banks can now be packed through the packer's own entry point with the proven controller's pad configuration, and the measured vendor fuses of TOOL-013 and TOOL-014 apply to it; every other configuration of those banks, and every design without the flag, is still refused. This makes an image technically possible; writing one, and any hardware use of it, are separate decisions."
  sources:
    - "aquasock/apicula branch epic/gw5ast138c, apycula/gowin_pack.py CliArgs --ddr3-context, GW5AST_138C._load_ddr3_manifest, _admit_ddr3_pad and check_io_banks; tests/test_ddr3_context_138c.py and tests/test_ddr_bank_refusal_138c.py"
    - "TinyVCMI tools/ddr3_ball_manifest.py, fpga/ddr3/ddr3_balls.json and tools/ddr_bank_check.py"
    - "Tang-PSX commit 61974ca, gateware/ddr3_vendor/tang_psx_ddr3.cst"
  verification: "The fork's 26 context tests pass, covering each admission rule and each manifest refusal, the manifest tests against the built chipdb. Through the flag, tools/ddr_bank_check.py finds all 102 bank tables equal to the vendor on dqs_sstl and lane_sstl on four lanes, the five bank-7 designs and the whole pad set, and refuses the single-ended strobe probes and the LVCMOS probe by name. Without the flag, seven non-DDR netlists pack to unchanged fuse digests, both DDR designs are refused, and the full fork suite fails the same 58 pre-existing tests. No image was written and no hardware was accessed."

- record_id: TOOL-016
  topic_id: TOOL
  title: "The first written open-flow DDR3 image"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "tools/build_ddr3_pad_image.sh synthesizes, places, routes and packs the whole DDR3 pad set of tools/ddr3_pad_set_probe.py with gowin_pack --ddr3-context fpga/ddr3/ddr3_balls.json into build/ddr3_image/full_sstl.fs, SHA-256 4c24096e1666c7606b2147a6e8e71d741a21cb25442ec13e6fe947d5154df81f, reproducible across rebuilds. Decoded from the files, it equals the Gowin EDA 1.9.11.03 build of the same source on all 306 DDR3 tables: 102 IOB and BANK tables, 199 IOLOGIC tables outside FCLKSEL, four DQS table-58 configurations outside the lane field, and the DDRDLL corner cell's DLL0 table. The DLL0 equality depends on features 5, 17, 18 and 19, which the vendor sets in every build with a DDRDLL and the Apicula fork writes under a declared DDR3 context since commit c8b9622; what they configure is unattributed."
  consequence: "The open flow can write a DDR3 image whose pad, IOLOGIC, strobe and DLL configuration is the vendor's, through the packer's own entry point. This image is a measurement artifact -- its serializers run from the board clock with no memory PLL, controller or calibration -- so it establishes configuration equivalence only, and loading it onto the board would test nothing about DDR3 operation. A hardware-meaningful image still needs the memory clock through CLKDIVs, IOLOGIC FCLK on all four HCLK lanes, and controller logic."
  sources:
    - "TinyVCMI tools/build_ddr3_pad_image.sh, tools/ddr3_image_check.py and tools/ddr3_pad_set_probe.py"
    - "TinyVCMI docs/ddr3-open-flow.md: The first written DDR3 image"
    - "aquasock/apicula branch epic/gw5ast138c, apycula/gowin_pack.py get_DDRDLL_fuses"
  verification: "The image was written twice into different directories with the same digest, and tools/ddr3_image_check.py found every compared table equal; before the DDRDLL change the DLL0 table was the only difference. Without the flag the two DDRDLL probe designs pack to unchanged fuse digests, and the fork's full suite fails the same 58 pre-existing tests. The image was not converted to a loadable .bin and no hardware was accessed. Revised 2026-10-24: feature 5 is attributed, CLKIN from CLK0, which this image's DLL uses because it has no CLKDIV on its clock (TOOL-003); the packer now writes it from the route instead of as a default."

- record_id: TOOL-017
  topic_id: TOOL
  title: "DDR3 lane serializer FCLK on all four HCLK lanes"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "Gowin EDA 1.9.11.03 clocks an OSER8_MEM or IDES8_MEM at a DDR3 lane position from any of the four HCLK lanes of block 2, selecting the lane by IOLOGIC FCLKSEL fuses that are the same on every lane. OSER8_MEM side A: lane 0 (3,4) (7,3) (8,14), lane 1 (7,1) (8,13), lane 2 (3,4), lane 3 (7,1); side B (5,1) (6,13) (10,2), (5,3) (6,14), (10,2), (6,14). IDES8_MEM side A: lane 0 (0,1) (8,14), lane 1 (0,3) (5,13) (8,13), lane 2 none, lane 3 (0,3) (5,13); side B (5,1) (11,1), (5,3) (8,10) (11,7), none, (8,10) (11,7). In attribute form, fuse-equal on both sides: lane 1 OSER8_MEM FCLKSEL0=HCLK1 and FCLKSEL4=HCLK1, lane 3 FCLKSEL0=HCLK1; lane 1 IDES8_MEM FCLKSEL4, FCLKSEL5 and FCLKSEL6 =HCLK1 with FCLKSEL7=HCLK1_, lane 3 the same without FCLKSEL4. The Apicula chipdb offers IOLOGIC FCLK pips from lanes 0 and 2 only, because its FCLKSEL1/FCLKSEL2 spelling has no odd-lane rows."
  consequence: "A DDR3 lane's serializers can follow their DQS and CLKDIV onto any HCLK lane, which a controller clocking each lane through its own CLKDIV needs. The nextpnr fork models this for the 40 DDR3 lane positions only, with fuse-free lane-1/3 FCLK pips and lane-node membership, and the Apicula fork writes the measured sets; every other IO cell keeps lanes 0 and 2, and the Apicula database itself is unchanged, so its own lane-count test still fails as before."
  sources:
    - "TinyVCMI tools/dq_lane_probe.py oser_lane0..3 and ides_lane0..3 in build/dq_lane, build/dq_lane_l1..l3, build/dq_lane_b and build/dq_lane_b_l2"
    - "TinyVCMI docs/ddr3-open-flow.md: IOLOGIC clock lanes 1 and 3"
    - "aquasock/nextpnr branch epic/gw5ast138c, himbaechel/uarch/gowin/gowin_arch_gen.py extend_dq_lane_fclk and tests/check_dqs_site.py"
    - "aquasock/apicula branch epic/gw5ast138c, apycula/gowin_pack.py _DQ_IN_FCLK, _DQ_OUT_FCLK and get_all_pips_fuses; apycula/chipdb.py _gw5a_iologic_fclk_lanes"
  verification: "Vendor fuses were decoded per lane on side A of all four DDR3 lanes and side B of lanes 0 and 2, and an exhaustive search over the IOLOGIC table's FCLKSEL attributes found the sets above to reproduce each exactly. After the change all 48 per-lane serializer designs route with no lane-split warning and tools/dq_pack_check.py finds them equal to the vendor including the lane field; check_dqs_site.py passes eight of eight. Side B of lanes 1 and 3 is inferred from the lane-independent encoding, not built. No hardware was accessed."

- record_id: TOOL-018
  topic_id: TOOL
  title: "The open-flow DDR3 PHY bring-up on the board"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "fpga/ddr3_phy_bringup carries the proven controller's PHY clocked as it is: a 400 MHz PLL on PLL_L[0], one CLKDIV at LEFTSIDE[4] giving every lane's PCLK with every FCLK on HCLK lane 0, the DDRDLL on DDRDLLM_BL with STOP the inverse of PLL lock and its clock from that lane, the four DQS lanes and bank 7's command serializers, sequenced from the 50 MHz board clock and read over TinyTang. The DDR3 device is held in reset with ddr_reset_n and ddr_cke low from constants and every lane serializer's TX high. Built by tools/build_ddr3_phy_bringup.sh with --ddr3-context, the image equals the Gowin EDA 1.9.11.03 build of the same source on all 306 tables, bank-6 FCLKSEL and DQS lane fields exactly; bank 7's 26 serializers sit on HCLK block 0, lane 0 in the open image and lane 3 in the vendor's. On 2026-10-24 the vendor control (4,330,802 bytes, SHA-256 3c011b871a8d5ebbb02166a83d107689ebfcfdf2a780a72abad81e02781e6da3) and the open-flow image (4,330,782 bytes, SHA-256 e1f4ecbf22b13cbbc1863e53519f187544a74a369b29101875c0440a3544d3e5) both answered core ID 0x56 and returned, in every read before and after a sequence restart, state RUN, PLL lock 1, DLL LOCK 1, STEP 0x2c and both counters advancing, with every lane status byte 0. Two model gaps had to close for the comparison to pass: a serializer on a routed RESET has no reset multiplexer on its own half (LSROMUX_0 for an output, LSRIMUX_0 for an input), and the DDRDLL's CLKIN takes the CLKDIV's HCLK lane (TOOL-003). Gowin's DQS simulation model is an empty module."
  consequence: "The open flow can build a DDR3 PHY that loads and runs on this board with the DLL locked and reporting a tap code, identical in every read to the vendor's build of the same source. It says nothing yet about data: no command reached the device, no strobe or DQ toggled, and the lane status bytes are zero because nothing was read, not because a read succeeded. Gowin's OSER8_MEM model drives the lane pads low from configuration until the lanes leave reset, as the proven controller does by its netlist, never high. The next step can drive the device out of reset."
  sources:
    - "TinyVCMI fpga/ddr3_phy_bringup, tools/ddr3_phy_bringup.py, tools/build_ddr3_phy_bringup.sh, tools/sim_ddr3_phy_bringup.sh, tools/ddr3_image_check.py --exact-lanes and tools/ddrdll_port_probe.py"
    - "TinyVCMI docs/ddr3-open-flow.md: The PHY bring-up image"
    - "aquasock/nextpnr branch epic/gw5ast138c, himbaechel/uarch/gowin/gowin_arch_gen.py create_ddrdll_bel and DDRDLL_CLKIN_LANES, globals.cc ddrdll_clkin_pip_ok and the per-block lane check"
    - "aquasock/apicula branch epic/gw5ast138c, apycula/gowin_pack.py _lsr_attrs and get_DDRDLL_fuses; tests/test_ddr3_phy_138c.py"
    - "Gowin EDA 1.9.11.03, IDE/simlib/gw5a/prim_sim.v, modules OSER8_MEM and DQS"
  verification: "The vendor build met timing on all three clocks with no negative slack. The simulation passed against Gowin's primitive models with a stand-in for the empty DQS model. The image check passed every table after the two fixes and failed 67 tables before them. Both images were loaded with tangload and read with three status queries, a restart and two more queries each; the desktop core was reloaded afterwards and answered 0x54. Non-DDR images rebuild to their earlier digests, the DDRDLL liveness image among them, the Apicula suite fails the same 58 pre-existing tests by name, the fork's twelve new packer tests pass and ten of them fail on the previous packer, check_dqs_site.py passes nine of nine and the preflight passes six of six. tools/lane_open_build.py --pack over all four lanes found 246 of 246 designs as expected and 224 of 224 packer checks equal, 55 of them on a rerun after the first run packed against a temporarily stashed packer. No pin was probed and the device was never released from reset."

- record_id: TOOL-019
  topic_id: TOOL
  title: "The proven PHY's start-up order and the PLL output enables"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "The vendor DDR3 IP sequences its PHY in ddr_sync on the 50 MHz board clock. Simulated from the post-route netlist with Gowin's primitive models, it releases the DLL reset at the IP reset's release and the CLKDIV and lane reset (ddr_rst) three clocks later, then waits for DLL LOCK and 16392 clocks more, raises every DQS's HOLD, drives UPDNCNTL low for 4 clocks from +4, drops HOLD at +12, stops the memory clock at +27 (pll_stop low, the PLL's ENCLK2), holds ddr_rst high from +31 to +35 with the clock stopped, restarts the clock at +39 and is ready at +48; the wait counts from LOCK. On the GW5AST-138C PLL at PLL_L[0], ENCLK0 and ENCLK2 are ordinary routed inputs on wires B6 and B4 of tile (27,4): a register or VCC reaches them through a pip and no PLL fuse moves. They are rows 183 and 185 of the vendor .dat's PllIn table, whose rows 183 to 189 run B6 down to B0 in port order."
  consequence: "An open-flow PHY can follow the proven order exactly, including the clock stop that aligns the CLKDIV with every serializer's gearbox. The Apicula fork builds ENCLK0 to ENCLK6 from the .dat rows for this device and nextpnr routes them when a signal or a low tie on a used output drives them; a high tie, or a low one on an unused output, is still dropped, as every earlier open-flow PLL image ran with the pin undriven. ENCLK1 and ENCLK3 to ENCLK6 are placed from the table, not measured."
  sources:
    - "TinyVCMI tools/vendor_memsync_trace.py, tools/pll_enclk_probe.py"
    - "Tang-PSX build/gate1-ip/ddr3_memory_interface/ddr3_memory_interface.vo, u_ddr_phy_top/ddr_sync, stop_reg and ddr_rsti_reg"
    - "Gowin EDA 1.9.11.03 IDE/share/device/GW5AST-138C/GW5AST-138C.dat, PllIn rows 183 to 189"
    - "aquasock/apicula branch epic/gw5ast138c, apycula/chipdb.py _gw5a_pll_extra_inputs; aquasock/nextpnr branch epic/gw5ast138c, himbaechel/uarch/gowin/pack.cc drop_idle_output_enables"
  verification: "The netlist cut has 106 cells and five inputs; its trace is the same with LOCK 20 us or 100 us after the DLL reset, shifted by the lock time. Four vendor builds in build/pll_enclk were diffed tile by tile. With the ports modelled, the DDRDLL liveness and open-flow smoke images rebuild to their earlier digests and the PHY bring-up image to equal tables, its ground net breaking one routing tie differently at X93Y27."

- record_id: TOOL-020
  topic_id: TOOL
  title: "The open-flow DDR3 read path on the board"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "fpga/ddr3_mpr brings the PHY up in the order of TOOL-019, runs the JEDEC power-up at DDR3-800 (RESET# 200 us after ready, CKE 500 us later, MR2 0x0000, MR3 0x0000, MR1 0x0044, MR0 0x0520, ZQCL), enables MPR with MR3 0x0004 and streams READs to bank 0, never writing. Built by tools/build_ddr3_mpr.sh it equals its Gowin EDA 1.9.11.03 build on all 306 tables with bank-6 lanes exact, and both meet timing. On 2026-10-24 the vendor control (SHA-256 cfa1705832ca47d4f2006a9afbadfc42d72cf3fca5e448327672f148d9712b59) and the open-flow image (SHA-256 bfced70834f9f7dbf59435c1b732b43487216fb5aaa69c6bb67ab76f036d9a5a) each initialized the device and read 0xAA on all 32 DQ in 65535 of 65535 PCLK cycles on every lane at every RCLKSEL from 0 to 7, with RVALID high. Moving each lane's read delay down from its default with RMOVE, capture first failed at -8 to -9, -13, -18 to -19 and -22 to -23 steps in the vendor image and at -17 to -18, -23, -23 and -27 to -28 in the open-flow image, repeatable within one step; up to +140 only lane 3 failed, at +43 in both, on one DQ bit."
  consequence: "The open flow's DDR3 read path works on this board: the device obeys the open-flow PHY's commands and every DQ is captured live through the open-flow DQS and IDES8_MEM. The default read delay sits close to the lower edge in both builds, so a controller must calibrate it per lane. TOOL-021 subsequently established writes and refresh, and TOOL-022 added live read gating, calibration, write leveling and broad bank/row/pattern coverage; TOOL-022 also identifies the differing bank-7 HCLK00 route that correlates with the phase offset."
  sources:
    - "TinyVCMI fpga/ddr3_mpr, tools/ddr3_mpr.py, tools/build_ddr3_mpr.sh, tools/sim_ddr3_mpr.sh, tools/ddr3_mpr_probe.py"
    - "TinyVCMI docs/ddr3-open-flow.md: MPR read-back"
  verification: "The simulation decoded every command at every CK edge against Gowin's models and passed, and a separate testbench checks the pattern counter, which on the first load read 0 on every lane because a fully matching 65536-cycle window overflowed it; the window is 65535 cycles since. With reads off the strobes stop and the deserializers hold their last word, so liveness rests on the read-delay edges, not on the count. The desktop core was reloaded afterwards and answered 0x54. tools/lane_open_build.py --pack over all four lanes passed after the PLL change. Revised 2026-10-24: TOOL-022 records the later route comparison and calibrated data tests."

- record_id: TOOL-021
  topic_id: TOOL
  title: "Open-flow DDR3 writes on the board"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "fpga/ddr3_write streams WRITEs of an 8-beat pattern P (even DQ) and ~P (odd DQ) across row 0 of bank 0 with the strobes and DQ driven continuously, ODT high and refresh every 7 us, then streams READs back and counts per lane the cycles in which all eight DQ words are one rotation of P and its inverse. Built by tools/build_ddr3_write.sh it equals its Gowin EDA 1.9.11.03 build on all 306 tables and meets timing. On 2026-10-24 the open-flow image (SHA-256 58ceeb3d9a3738a29700ef4679122ba518b503a6576a4c276174c9d5b73db3af) matched on all four lanes in every eligible cycle at every WSTEP from 0 to 248 in steps of 8 except single settings 104, 112 and 248, and the vendor control (SHA-256 447b41ad5ce197df254dcfa6fe22111e0fc241a3bbe67caa3d5f15a787397887) except 72, 80 and 248, with no write leveling. Changing P without writing read 0 on every lane, and writing 0x6B and then 0xC5 read back the full count each time. On the vendor control's first start-up, lanes 0 and 2 read individual bits one or two clocks out of frame at every WSTEP, RCLKSEL and read delay; a restart of the core's start-up sequence aligned all lanes in four of four tries, and the open-flow image was aligned from its first start. The write-leveling count read 0 throughout because the core holds READ low outside read mode, so the read FIFO never clocks."
  consequence: "Data can be written to and read from the DDR3 array through the open flow on all 32 DQ, and the board's strobe-to-clock skew is small enough that writes land without leveling. TOOL-022 supersedes this image's calibration limits: the later image adds the settled-PLL wait, per-bit CALIB, read gating, delay sweeps, measurable write leveling and wider bank/row/pattern coverage, while raw whole-byte rotation still requires controller normalization."
  sources:
    - "TinyVCMI fpga/ddr3_write, tools/ddr3_write.py, tools/build_ddr3_write.sh, tools/sim_ddr3_write.sh, tools/ddr3_write_probe.py"
    - "TinyVCMI docs/ddr3-open-flow.md: Writes"
    - "Tang-PSX build/gate1-ip/ddr3_memory_interface/ddr3_memory_interface.vo, the four DQS instances' WSTEP, WLOADN, WMOVE and WDIR"
    - "Gowin EDA 1.9.11.03 IDE/simlib/gw5a/prim_sim.v, module IDES8_MEM, CALIB"
  verification: "The simulation passed after the bus-release fix; the board session ran the write-delay sweep on both images, the pattern-change controls and repeated re-reads of stored data on the open-flow image, four restarts of the vendor control and three of the open-flow image. The desktop core was reloaded afterwards and answered 0x54. No fork changed in this cycle. Revised 2026-10-24: TOOL-022 records the completed calibration cycle and replaces the open limitations named here."

- record_id: TOOL-022
  topic_id: TOOL
  title: "Open-flow DDR3 read calibration and broad data test"
  status: VERIFIED
  verified_date: 2026-10-25
  statement: "The calibrated fpga/ddr3_write image waits for 16384 stable system clocks of PLL lock before releasing the DLL reset, exposes all 32 IDES8_MEM CALIB inputs independently, asserts DQS READ during write leveling, gates normal reads in configurable groups with a configurable command-to-READ delay, and selects all eight banks and 15-bit rows. Its host calibration alternates patterns with disjoint rotation sets while sweeping each lane from -128 through +127 RMOVE steps, rejecting held data. On the Tang, the vendor image's longest observed live pass intervals began at -4, -10, -14 and -16; two open-image runs began at -14/-16, -20/-22, -22/-24 and -26/-28, with every interval still passing at +127. The open image passed all 336 combinations of eight banks, six rows and seven patterns, about 25100 eligible cycles per case on all four lanes, and ten complete controller restarts returned per-bit-aligned live data. CALIB aligns outlier DQ framing, but the raw whole-byte rotation changes between snapshots and read epochs independently by lane. Write leveling now returns a circular high/low transition on every lane."
  consequence: "The open-flow PHY has a repeatable per-bit framing operation, observable write leveling and broad live read/write coverage, but an eventual controller must normalize each lane's byte rotation at a trained read-valid boundary; raw IDES8_MEM words do not yet form a fixed-order controller interface. The signed sweep only finds the lower eye edge because every lane still passes at +127; TOOL-040 found that the read delay stops moving at the top of its range well before +127, so that midpoint sat at the top of the range, at the eye's edge, and calibration now centres between the lower edge and the top. The open lower edges are 8 to 12 steps later than the vendor's. The data-bank HCLK20 route is identical, while the bank-7 CK/command route differs at HCLK00: the open flow reaches HCLK_MUX_ALPHA00 through L2HCLK00, HCLK_MUX_BETA00 and HCLK_BUF_BO00, and the vendor selects CLKDIV2_O00. That route difference is the likely cause of the phase offset, but is a correlation rather than a direct propagation-delay measurement."
  sources:
    - "TinyVCMI fpga/ddr3_write, tools/ddr3_write.py, tools/build_ddr3_write.sh, tools/sim_ddr3_write.sh and tools/ddr3_write_probe.py"
    - "TinyVCMI tools/ddr3_image_check.py --exact-lanes"
    - "TinyVCMI docs/ddr3-open-flow.md: Read calibration"
    - "Gowin EDA 1.9.11.03 IDE/simlib/gw5a/prim_sim.v, module IDES8_MEM CALIB behavior"
  verification: "The final simulation passed with 4876 writes, 3922 reads, 29 refreshes and a maximum refresh interval of 7.6 us. Vendor and open builds met timing and all 306 DDR3 configuration tables compare equal; the open .fs SHA-256 is e203be212469830d4bd3316a797a912be73ad1f7dd576793bed6b55b5d5b9535, its .bin is 89f917f6ec0d684331563e51246665473bd3a96fa930066a1f016a2d882dac6f, and the vendor .bin is d594feb2f923d65f4b53049f88eb07ff79e504e1cd708d0b86e3f1296b29fda2. The board run exercised CALIB, two complete open-image eye sweeps, a coarse write-level sweep, five aligned read sessions, 336 bank/row/pattern cases and ten restarts. tools/ddr3_image_check.py decoded the four differing HCLK mux selections at block (27,0). The desktop tinytang.bin was restored and answered 0x54. No fork changed in this cycle. Revised 2026-10-25: the consequence read the passing +127 end of the sweep as the eye still open there; TOOL-040 showed the delay stops moving at the top of its range, so the sentence was rewritten."

- record_id: TOOL-023
  topic_id: TOOL
  title: "Read word framing moves at every read interruption with the gate at offset 0"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "With every READ's DQS gate opened at the first memory clock of its delayed PCLK -- the only gate the image had until TOOL-026 -- the open-flow DDR3 read capture does not hold one word frame. In fpga/ddr3_write with the DQS READ gating in use, the whole-word rotation is constant while the read stream is continuously live and moves exactly once per interruption, first being observed at the first live cycle after a gated gap. The move is the same in all four lanes and preserves their relative offsets. Its size is a fixed function of the IDES8_MEM read delay and does not depend on the gap length: -2 at delays 2 to 7 and +4 at delays 0 and 1 for the measured image, with ten consecutive samples at delay 3 reporting -2 every time. Moves were measured 510, 319 and 40 PCLK apart at read-run/gap 255/255, 255/64 and 32/8, each equal to the group period, and about 700 PCLK apart (the refresh period) at 255/1, where a one-cycle gap is too short to re-frame. RBURST reads low on every lane at every PCLK sample; its true edge rate was measured later and is far below the burst rate (TOOL-024), so it offers no per-burst framing here. A pattern whose eight rotations are not distinct cannot identify a frame and never trains."
  consequence: "TOOL-026 supersedes the cause: the move is set by the gate's memory-clock offset, and at read delay 1 with offset 2 or 3 the stream frame holds. For the gate at offset 0: a fixed rotation lock is invalid across interruptions, and a per-burst marker is unnecessary: a move all four lanes make together, held for eight live cycles, can be followed by moving the locks with it. A lane that leaves its lock while the others do not is a fault, not a slip. Byte order within a burst is recoverable this way; the association of a burst with the READ command that requested it, and the read latency, are still the controller's to establish. Any change to the read delay changes the slip size, so a controller must retrain after changing it. Interruptions shorter than a few cycles do not re-frame, which is why only refreshes matter when the gating gap is one cycle."
  sources:
    - "TinyVCMI fpga/ddr3_write/rd_align.v, wr_core.v and tools/ddr3_write_probe.py (phase, align and alignsweep)"
    - "TinyVCMI docs/ddr3-open-flow.md: Read-data alignment"
    - "Direct observation on the Tang Console 138K, GW5AST-LV138PG484AC1/I0 revision C, 2026-10-24"
  verification: "The phase monitor counted moves in the core over 15 to 20 ms host samples: at read-run/gap 255/255 the PCLK delta between the last two moves was 510 with step [6,6,6,6]; at 255/64 it was 319 and at 32/8 it was 40, with the same step; at 255/1 it was about 757 while the move count advanced about once per 700 PCLK; at 32/8 with read delay 0 and 1 the step was [4,4,4,4] and with delays 2 to 7 it was [6,6,6,6]. The at-gap counter equalled the total move count in every configuration, so no move was first seen mid-stream. A sticky skew flag reads one because the first move is compared against a zeroed previous phase; the recorded steps are equal, so this is instrumentation, not a lane difference. Revised 2026-10-24: the RBURST claim was narrowed after ip/ddr3_write began detecting its edges in the memory-clock domain -- the signal is not dead, but its edges are too rare to mark bursts (TOOL-024). rd_align following these moves gave six of six read sessions with err and drift clear and every presented burst in pattern order (26151 to 26391 bursts each; the 'about 48800 moves followed' first recorded here was read four bits off a 1020-bit status frame truncated to 1016 bits and is known only modulo 4096, about 3050), a 240-case bank/row/pattern sweep passed twice with no failures, and training at 255/255 followed by 32/8 without leaving read mode stayed at 100 percent (10309 of 10309). The open .bin deployed was 40ddf0256d7a03d38678528c07ada37bf8ea02adf9ea312c0211ce66a4f51d79 and the image equalled its Gowin build on all 306 DDR3 tables. The desktop tinytang.bin was restored and answered 0x54. Revised again 2026-10-24: the gate-offset sweep of TOOL-026 found the move per interruption is 6, 4, 2 and nearly 0 beats at gate offsets 0 to 3 for delays 2 to 7, and none at delay 1 with offset 2 or 3, so the move belongs to the gate's alignment, not to the PHY; the relock count above was corrected; the phase-monitor bytes 110 to 119 it rests on were below the misdecoded region and stand."

- record_id: TOOL-024
  topic_id: TOOL
  title: "RBURST edges do not mark each read burst; the proven controller samples RBURST as a level"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "The DQS block's RBURST output is generated in a domain faster than the memory clock: the upstream LiteDRAM GW5 PHY samples it in the fast domain and notes that in X4 mode it can rise and fall between system clock edges. fpga/ddr3_write detects its edges in the memory-clock domain, toggles one bit per edge there and counts the toggles in PCLK. The per-RCLKSEL edge rates first recorded here are invalid: the image's status concatenation was 1020 bits in a 1016-bit wire, so the four per-lane counters were read four bits off, each reported byte holding nibbles of two lanes (lane 0's rates were always multiples of 64 per second), and the 8-bit counters also wrapped within the 250 ms host-timed window, so a rate near one edge per burst could not have been told from a low one. RVALID per RCLKSEL, read from a byte below the misdecoded region, stands: RCLKSEL 3 and 4 held RVALID high on all four lanes. The image now counts for exactly 2^n PCLK per command 0x24 n, saturating at 255, with the status field fixed."
  consequence: "RBURST edges do not frame a burst, so a controller cannot count them to bind read data to the READ command that asked for it. That does not make RBURST useless: the hardware-proven vendor controller samples it per lane as a level and steers its per-lane READ gate and RCLKSEL by it (TOOL-033), so it is a calibration signal whose meaning in isolated reads has not been measured here; every count above was taken on streams with one READ gate and one RCLKSEL shared by all lanes. Changing RCLKSEL while the read stream runs leaves RVALID low at several settings, so any sweep of RCLKSEL must re-enter read mode per setting."
  sources:
    - "TinyVCMI fpga/ddr3_write/top.v (RBURST edge detection in the memory-clock domain), fpga/ddr3_write/wr_core.v (windowed count, status byte 119) and tools/ddr3_write_probe.py burst"
    - "Tang-PSX third_party/litedram/litedram/phy/gw5ddrphy.py, RBURST fast-domain capture comment"
    - "Verilator --lint-only WIDTHTRUNC on the committed wr_core.v status assignment, and an iverilog $bits check reporting 1020 bits"
  verification: "The first measurement deployed SHA-256 24ed798874de9ee4d5a781e601b788701b09d2f1d622d2d82ad88bb88066a707 and read the counters twice 250 ms apart per RCLKSEL. Revised 2026-10-24: the status width was confirmed by two tools, the decoding of bytes 120 to 126 was reworked from the concatenation, and the rates were withdrawn. Settled 2026-10-24 on the board with the fixed counting: over exactly 2^16 PCLK per lane the edges were 0,0,0,0 at RCLKSEL 0, 161,0,161,0 at 1, 0,0,0,0 at 2 and 3, 162 on all four lanes at 4, 0,163,0,163 at 5, 0,1,0,0 at 6 and 0,0,0,0 at 7 where lane 0's RVALID was low, against about 8,192 expected in that window if every READ marked its burst; each sweep step re-entered read mode. The desktop core was restored afterwards and answered 0x54. Revised 2026-10-24: the vendor netlist trace of TOOL-033 found the proven controller's per-lane calibration taking RBURST as a level, high at a PCLK rising edge and at two consecutive falling edges, so the consequence was narrowed from RBURST not framing a burst to its edges not doing so."

- record_id: TOOL-025
  topic_id: TOOL
  title: "Upstream LiteDRAM's GW5A DDR3 design is primitive-compatible but not flow-compatible"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "LiteX's own apicula backend refuses GW5 devices by name, so the upstream Tang Console DDR3 design has never been placed by an open toolchain. Generating that design for GW5AST-138C with DDR3 at 1:4 and no CPU produces Verilog using only primitives this project already places and packs: 26 IODELAY, 20 OSER8_MEM, 16 IDES8_MEM, 16 IOBUF, 2 DQS, 2 ELVDS_IOBUF, 1 DDRDLL, 1 CLKDIV, 1 PLL and 1 ELVDS_OBUF. Yosys synthesises the whole design with the open-flow cell library. Placement then stops at three constraint and clock-routing gaps: nextpnr rejects create_generated_clock, it does not treat a differential IO_LOC pair as constraining both pads, and it rejects the PLL's sys4x_clk driving OSER8.FCLK as an invalid sink. The same netlist also fails the vendor flow, but on an unrelated platform pin conflict in bank 5. The upstream platform also wires only one of the board's two x16 DDR3 devices, 16 of the 32 DQ pins this project uses."
  consequence: "Adopting LiteDRAM's PHY and controller is not a drop-in step: it needs a constraint translator, nextpnr support for generated clocks or equivalent SDC rewriting, a clock-routing rule for OSER8 FCLK, and a platform for the full x32 array. The PHY itself is not the obstacle, since every primitive it instantiates is already supported. Until those gaps close, fpga/ddr3_write remains the only hardware-proven DDR3 path on this board."
  sources:
    - "Tang-PSX third_party: litex, litedram, litex-boards and migen"
    - "Tang-PSX third_party/litex/litex/build/gowin/apicula.py, GW5 refusal"
    - "Tang-PSX third_party/litex-boards/litex_boards/targets/sipeed_tang_console.py and platforms/sipeed_tang_console.py"
    - "TinyVCMI tools/litex_ddr3_gate.sh and docs/ddr3-open-flow.md"
  verification: "tools/litex_ddr3_gate.sh regenerates the design, rewrites the SDC and CST, synthesises and places, and reproduces the same verdict from a clean output directory: generation succeeds, synthesis succeeds, and nextpnr exits 2 with 'Net sys4x_clk has an invalid sink port OSER8_1.FCLK'. The vendor flow was run on the same netlist with Gowin EDA 1.9.11.03 and stopped at CT1136, a bank-5 VCCIO conflict from the platform's fan_en pin. The primitive counts above are from the generated Verilog. No hardware was accessed for this record."

- record_id: TOOL-026
  topic_id: TOOL
  title: "The READ gate's memory-clock offset sets the frame move at a read gap"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "fpga/ddr3_write opens each READ's DQS gate k memory clocks into its delayed PCLK: READ[i] follows the delayed READ of this PCLK for i >= k and of the previous one for i < k, bit 0 being the earliest clock, as upstream LiteDRAM's GW5 PHY uses the four bits. Streaming pattern 1d at read-run 32, gap 8, the word-frame move per read interruption, the same on all four lanes, was, in beats modulo 8: at read delays 2 to 7, 6, 4 and 2 at every gap for k = 0, 1 and 2, and 2 at only 77 to 461 of about 25,000 gaps in 5 ms for k = 3; at delay 1, 4 and 6 at every gap for k = 0 and 1 and no move at all for k = 2 and 3; at delay 0, 4, 6, 2 at 77 gaps, and 2 at every gap. Every lane matched in every eligible cycle at delays 0 to 5 and lost about 3 to 11 percent at delays 6 and 7."
  consequence: "The move TOOL-023 recorded is the gate opening at the wrong memory clock, not a property of the PHY: the step changes by 2 beats, one memory clock, per unit of k, and whole PCLK of delay only change which offsets are clean. At delay 1 with k = 2 or 3 a stream keeps one frame across interruptions, so a controller can fix byte order once instead of following slips. This is measured on streams of one pattern; single READs are TOOL-027."
  sources:
    - "TinyVCMI fpga/ddr3_write/wr_core.v (gate_win, command 0x25) and tools/ddr3_write_probe.py gate"
    - "Tang-PSX third_party/litedram/litedram/phy/gw5ddrphy.py, dqs_read = Cat(dqs_re_d, Replicate(dqs_re, 3)) for X4 DLL-on (BSD-2-Clause)"
    - "Direct observation on the Tang Console 138K, 2026-10-24"
  verification: "The open-flow image (SHA-256 466979d693fba0c147af379ca17ccb010ae4b4d6d167d1b080c4fc5eda18a0cd), equal on all 306 DDR3 tables to its Gowin build, was loaded with tangload and answered core ID 0x56; the in-core phase monitor counted moves for each of the 32 positions after a re-arm, every move being first seen at a gap. The single move counted at delay 1, k = 2 and 3 is the monitor's first comparison against a zeroed phase. The desktop tinytang.bin was restored afterwards and answered 0x54."

- record_id: TOOL-027
  topic_id: TOOL
  title: "Single closed-page READs do not yet return their burst whole"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "In fpga/ddr3_write's random mode, an ACTIVATE of one of sixteen rows -- banks 0 to 7, rows 0 and 1, each written across the whole row with its own aperiodic pattern -- then a READ with auto-precharge three PCLK later, one access every 8 PCLK, was checked by rd_check.v, which tests whether all four lanes hold the READ's pattern in any rotation with consistent even/odd pins, at each of 32 offsets after the READ. After every DQ bit was aligned with CALIB in a stream, no offset held the right pattern in at least 98 percent of READs at any of the 32 gate positions, about 2.4 million READs each. At delay 1, k = 2, the stream-stable position of TOOL-026, the right pattern was on all lanes at offset 10 -- the burst on the IDES8_MEM outputs 7 PCLK after the READ left the core -- in 12.5 percent of READs and at no more than 0.8 percent elsewhere. Failing captures kept each lane's pin consistency but carried other patterns, differing between lanes."
  consequence: "The open-flow PHY is still not usable by a controller issuing single READs, but the straddle is now measured rather than inferred and its fix is in the image: with the two-word reassembler of TOOL-029 the best position reconstructs 25.4% of READs at the expected rotation against 5.5% without it, so a burst genuinely does cross two captured words. What remains is not, as first read, a choice between two positions: TOOL-030 shows that closed-page scatter reads reach the capture at all only in a small and session-dependent minority, so the two-position split describes that minority and binding a burst to its command cannot repair the rest."
  sources:
    - "TinyVCMI fpga/ddr3_write/rd_check.v, tb_check.v and tools/sim_rd_check.sh"
    - "TinyVCMI fpga/ddr3_write/wr_core.v (R_RAND) and tools/ddr3_write_probe.py prewrite and random"
    - "Tang-PSX third_party/litedram/litedram/phy/gw5ddrphy.py, BitSlip on each IDES8_MEM output"
    - "Direct observation on the Tang Console 138K, 2026-10-24"
  verification: "The checker's unit simulation passes latency, lock, frame-jump, predicted-move and mis-framed-pin cases; the image simulation checks every random READ's bank timing. On the board the same image ran random --prewrite --sweep-gate, and a direct run at delay 1, k = 2 recorded the histogram. Revised 2026-10-24: the straddle was measured by a raw capture around a single READ (TOOL-029), the reassembler was built and its unit test passes, and the shipped image was measured at the stream-stable position with slips 1,526,697 of 6,013,517 READs, 25.4%, every reconstruction at the expected rotation, against 328,494 of 6,013,518 with the reassembler disabled; offset 19 passes 9.7% and the other 30 positions no more than 8%. The remaining two-position split is a measurement from the same histogram, not yet closed. Revised 2026-10-24: TOOL-030 swept the cadence and every gate position and found the scatter path captures a burst in under 2% of READs at any setting, so the split describes a small survivor population; the single-READ question is open as a capture failure, not as a framing choice."

- record_id: TOOL-028
  topic_id: TOOL
  title: "GowinSynthesis packs setting synchronizers into LUT-RAM shift registers"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "Gowin EDA 1.9.11.03 synthesis maps fpga/ddr3_write's two-flop synchronizers of link settings into the PCLK domain (x_p1 <= x; x_p2 <= x_p1) to counter-addressed LUT-RAM shift registers, whose read and routing put about 3 ns on PCLK paths whose timing report names the address counter's flop, pclk_cnt_0, as source. The Gowin build of the committed write image of 2026-10-24 (de5d085) misses PCLK at 89.9 MHz against 100 MHz with 14 failing endpoints and -8.6 ns total negative slack, which tools/build_ddr3_write.sh did not check. With (* syn_srlstyle = \"registers\" *) on wr_core, kept copies of the captured DQ words for rd_align and rd_check, and shorter single cycles in rd_align, the Gowin control of this cycle closes PCLK at 100.51 MHz with no negative slack; the open flow closes it at 126.29 MHz."
  consequence: "A Gowin control can miss timing silently, so build_ddr3_write.sh now fails when the Gowin report shows any negative slack. Earlier claims that the write image's Gowin build met timing were not checked by the build and should not be relied on for builds after the aligner was added."
  sources:
    - "TinyVCMI tools/build_ddr3_write.sh step 6 and build/ddr3_write/vendor/impl/pnr/probe_tr_content.html"
    - "TinyVCMI fpga/ddr3_write/wr_core.v, rd_align.v and rd_check.v"
  verification: "The committed source was rebuilt with Gowin in a scratch directory for the baseline; each change was followed by a Gowin rebuild and its timing report, and the final control passed the new gate inside tools/build_ddr3_write.sh."

- record_id: TOOL-029
  topic_id: TOOL
  title: "A single read burst straddles two captured words, and a per-lane beat slip reassembles it"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "A raw capture of all four lanes' DQ words for 24 PCLK after one isolated closed-page READ shows the burst not falling inside one IDES8_MEM word: for the first random READ, pattern 0x0d, the earliest capture cycle at which all four lanes reconstruct the pattern is cycle 11, lanes 0 to 2 needing beat slip 0 and lane 3 beat slip 4, which joins the last 8-s beats of the older word to the first s beats of the newer one exactly as upstream LiteDRAM's GW5 PHY BitSlip does. fpga/ddr3_write/rd_check.v implements that as runtime state: it registers the previous DQ word, forms {current, previous} per pin and shifts by a 3-bit per-lane slip, and command 0x2A v sets lane v[4:3] to v[2:0] with v[7] enabling the reassembler; it is disabled out of reset so nothing earlier changes, and tools/ddr3_write_probe.py random defaults to slips 0,0,0,4."
  consequence: "Single READs can be checked against the pattern their own READ asked for, which a stream could not show because neighbouring bursts carried the same pattern and a straddled word was still one of its rotations. The reassembler is a diagnostic path, not the controller interface: it raises the best-position pass rate by a factor of 4.6 but does not remove the second burst position, so a controller still has to bind a burst to the READ command that asked for it."
  sources:
    - "TinyVCMI fpga/ddr3_write/rd_check.v (dq_prev, dq_slipped, slip_enable, slip), fpga/ddr3_write/tb_check.v case 7 and fpga/ddr3_write/wr_core.v command 0x2A"
    - "TinyVCMI tools/ddr3_write_probe.py (set_slips, --slips) and docs/ddr3-open-flow.md: Reassembling a burst from two words"
    - "Tang-PSX third_party/litedram/litedram/phy/gw5ddrphy.py, per-IDES8_MEM BitSlip"
  verification: "The capture that established the cycle-11 and slip-4 result was a temporary 768-bit buffer whose 24-way enable drove the vendor control to 91.772 MHz with 768 failing endpoints; it was removed once read and is not committed, so those numbers stand as a measurement rather than a reproducible tool. The committed reassembler passes tb_check's seven cases, including slips 0,2,4,7 at 300 of 300 simulated READs, and the shipped image passes the image simulation. On the board at delay 1, k = 2, offset 11, 1,526,697 of 6,013,517 READs reconstructed at the expected rotation with slips 0,0,0,4 against 328,494 of 6,013,518 with the reassembler disabled; offset 19 passes 9.7%. The same image trains the read aligner in five of five sessions at read-run 255 and gap 255, presenting 26,000 to 26,201 bursts each in pattern order with err and drift clear, and does not train at read-run 32 and gap 8 while the vendor build of the same source does, which is the CK route difference of TOOL-022."

- record_id: TOOL-030
  topic_id: TOOL
  title: "Closed-page scatter reads do not reach the read capture, in the open and the vendor build alike"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "In fpga/ddr3_write's closed-page random mode -- ACTIVATE, then a READ with auto-precharge, one access every read_gap PCLK -- almost no READ's burst is captured at any point in the read window. With all sixteen pattern rows freshly written and every DQ bit calibrated, 4,820,348 READs at delay 1 and gate 2 classified as 0.07% at both known positions, 1.6% at 11 only, 0.47% at 19 only and 97.9% at neither, and every class's refresh phase spanned 0 to 1023. Sweeping the cadence through the existing read_gap moves nothing: 1.17% at gap 8, 1.14% at 16, 1.05% at 32, 0.95% at 128 and 0.64% at 255. Sweeping all 32 (delay, gate) positions at gap 255 peaks at 0.40%. The device and the address path are not at fault: memtest passes 12 of 12 cases over banks 0 to 3 and rows 0 to 2 on every lane, and a continuous stream through the same lanes at the same calibration matches 24,989 of 24,988 cycles. The sub-population that does arrive arrives at whole-word offsets -- 975 at 11, 438 at 19 and 80 at 27 in an unsaturated 0.04 s window -- so the failures are not a burst in the wrong position. The Gowin build of the identical source fails the same way: at delay 1 and gate 2 it classified 0 of 59,705,132 READs at either position, and over all 32 (delay, gate) positions at gap 255 no histogram offset held the READ's pattern in more than 39 of 189,708 READs, while the open build loaded in the same session classified 5.6% at delay 1 and gate 2. RCLKSEL, which every earlier scatter run left at 0, does not recover them either: over all 256 shared RCLKSEL, delay and gate settings of the open build the best pass rate was 3.0%, and the per-lane RVALID and RBURST levels sampled in random mode did not follow the pass rate. Failing READs mostly return clean patterns of other rows rather than mixtures -- 0x57, the last row prewrite writes, more than any other, and 0x35, 0x2d and 0x3b -- sometimes a different row's pattern on each lane of one READ, with lanes 0 and 1 and lanes 2 and 3 moving in pairs as the two x16 devices do."
  consequence: "The failure is in the RTL both flows build from, not in the open flow: TOOL-022's CK-route difference cannot be its cause. Neither a trained fixed latency, the two-word reassembler of TOOL-029 nor a shared RCLKSEL addresses it. Streams of one repeated pattern cannot show which READ a burst came from, so the stream results that pass prove only that bits arrive, and the controller work of TOOL-031 and TOOL-032 has no proven read path under it until isolated READs return their own data. The two structural differences from the proven controller are the per-lane READ gate and RCLKSEL with RBURST-level training of TOOL-033; the clean other-row patterns are consistent with lanes delivering an earlier READ's burst, which is a hypothesis to be measured by checking each capture against the last few READs' patterns. The session-to-session rate at identical settings has ranged from 0.4% to 25%, so it is not a stable marginal case that a retrain could absorb."
  sources:
    - "TinyVCMI fpga/ddr3_write/rd_check.v (burst-position classifier, frame 0x2B), fpga/ddr3_write/wr_core.v (rand_wait from read_gap) and tools/ddr3_write_probe.py (pos, random --sweep-gate)"
    - "TinyVCMI fpga/ddr3_write/tb_pos.v and tools/sim_rd_check.sh"
    - "TinyVCMI docs/ddr3-open-flow.md: Which position a lone burst lands in; Scatter reads fail in the vendor build too"
    - "TinyVCMI tools/ddr3_scatter_sweep.py"
  verification: "Measured on the Tang Console 138K on 2026-10-24 with the image whose .bin is c15996cbcd87b4c42e6939fdc7f1d6b5150ee70fbe36f9dc8953d062e8d7816d, equal on all 306 DDR3 tables to its Gowin build. calibrate aligned all 32 DQ bits on every lane at 24,957 of 24,958 eligible cycles before the classifier ran. The cadence sweep used the core's own rand_wait derivation rather than a new register, so it needed no rebuild. One sweep was discarded: a memtest over banks 0 to 3, rows 0 to 2 overwrote three of the sixteen pattern rows the classifier compares against, and the gate sweep taken next read 2.03%; it was repeated after prewrite, and only the clean 0.40% figure is recorded. The desktop core was restored afterwards and answered 0x54. Revised 2026-10-24: in one board session the Gowin build of the same source, .bin SHA-256 4de328a1b9c4d4f11fffe89bfa5617fb246134b01cda44f64c2fa7a6e7c71cf6, whose build/ddr3_write/vendor copies of rd_check.v and rd_align.v are identical to the committed files, and the open image c15996cb were each loaded with tangload, answered core 0x56, calibrated every lane to within one cycle of all eligible cycles, and ran pos and random --sweep-gate; tools/ddr3_scatter_sweep.py then swept the open image over RCLKSEL 0 to 7, delays 0 to 7 and gates 0 to 3 at 0.1 s each. The failing words were classified against the sixteen row patterns by rotation. The desktop core was restored and answered 0x54. Revised 2026-10-24: the lag classifier of TOOL-034 measured the earlier-READ hypothesis directly; lanes do hold recent READs' bursts, but at any per-lane gate and RCLKSEL a lane holds its own in at most about half of READs, because the deserializer word is valid only on some cycles, which TOOL-033's RVALID-written FIFO selects."

- record_id: TOOL-031
  topic_id: TOOL
  title: "LiteDRAM's control layer builds in the open flow without its PHY"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "Instantiated against a stub PHY that provides only a PhySettings object and a DFI interface, LiteDRAM's control layer -- DFI injector, controller, crossbar, bank machines and refresher -- generates as one Verilog module, synthesises for GW5AST-138C with the open-flow cell library and places and routes with nextpnr-himbaechel at 1,958 LUT4, 883 DFF and 308 ALU cells. None of TOOL-025's three gaps reappears: no generated clock, no differential IO_LOC pair and no OSER8.FCLK sink exists in the control layer, so all three belong to the upstream PHY and its constraints. Generated at this board's geometry the core has 8 banks, 15 row bits, 10 column bits and a DFI of 64 bits over 4 phases, because LiteDRAM's own GW5 PHY sets dfi_databits to (8 // nphases) * databits; four phases then carry the 256 bits of one BL8 burst, which is what the hand-written PHY captures per PCLK."
  consequence: "Porting the control layer is a flow-viable path and does not require the three constraint gaps to be closed first, which makes it a candidate for the controller in place of a hand-written one. The cost moves to the PHY boundary: the hand-written PHY writes a single eight-bit pattern broadcast to all 32 DQ pins, has no write-mask path, and its read calibration locks rotations of a known pattern rather than arbitrary data. A controller therefore needs a per-pin write burst, a DM mask, and a start-up calibration whose frozen result is applied statically to later traffic."
  sources:
    - "TinyVCMI tools/litedram_ctrl_spike.sh and tools/litedram_ctrl_gen.py"
    - "TinyVCMI fpga/ddr3_ctrl/{dfi_adapter,ddr3_phy,ddr3_init,ddr3_sync,ddr3_wdata,ddr3_derot,ddr3_cmdmux}.v with their testbenches"
    - "Tang-PSX third_party/litedram, litex, migen and litex-boards"
    - "TinyVCMI docs/ddr3-open-flow.md: The controller path"
  verification: "The spike generated the core against a stub, synthesised it and placed it with nextpnr-himbaechel for GW5AST-LV138PG484AC1/I0. The generator then emitted the core at board geometry with the DFI at its ports and synthesised it clean. Each hand-written piece has a passing unit simulation: dfi_adapter (commands on any phase, burst slicing, write data, underflow), ddr3_init (power-up order), ddr3_sync (start-up order), ddr3_wdata (all 256 burst bits by one-hot walk), ddr3_derot (every rotation 0 to 7), ddr3_cmdmux (arbitration and op encoding). The extracted PHY synthesises standalone and again with its write path repointed. No image was written and no hardware was accessed."

- record_id: TOOL-032
  topic_id: TOOL
  title: "The controller did not route because its build placed the PHY clocking with unmatched constraints"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "Assembling the controller top level -- the extracted PHY, the start-up and JEDEC sequencers, the three-tier command mux, the boot trainer, rd_align, the rotation latch, the derotator, the write fan-out, the DFI adapter and LiteDRAM's control layer -- synthesises for GW5AST-138C without warnings, but nextpnr did not route it: `Net ddr.sys4x_clk has no route to the FCLK of phy.ck_ser (sink wire X0Y30/FCLKA)`, deterministically at every seed. tools/build_ddr3_ctrl.sh reuses fpga/ddr3_write/top.cst and open.sdc, whose INS_LOC lines name the cells ddr_pll, dll and fdiv and whose clocks name the nets mclk and pclk, while the controller's flattened netlist calls them phy.ddr_pll, phy.dll and phy.fdiv. nextpnr reported `Cell ddr_pll not found`, `Cell dll not found` and `Cell fdiv not found` only as Info lines and `get_nets argument 'mclk' matched no objects` and the same for pclk as warnings, so the PLL was placed at X1Y81 instead of PLL_L[0] at X1Y27, and from there every bank-7 serializer FCLK sink and the DDRDLL's DDRDLL_CLKIN failed dedicated routing from X1Y81/MPLLCLKOUT0. The database does have the bank-7 pip: the hardware-proven write image routes mclk into X0Y30/FCLKA through X0Y30/FCLKA/HCLK00 with the PLL at X1Y27, using global resources only. The fork experiments of the same cycle were still informative as negative results: adding lane membership for every IO tile with FCLK pips makes nextpnr segfault, narrowing it to the bank-7 rows leaves the bba byte-identical because those rows are absent from hclk_pips, and both changes were reverted, the fork regenerating unchanged at 95,407,417 bytes."
  consequence: "No nextpnr fork change is needed for bank-7 FCLK; the controller needs its own constraint files naming the flattened cells and nets, and its build must fail on any INS_LOC cell that is not found as it already fails on an unmatched clock constraint. Whether the controller then routes and meets timing is untested. Every timing figure from the failed builds is meaningless, because PCLK was unconstrained."
  sources:
    - "TinyVCMI fpga/ddr3_ctrl/top.v, tools/build_ddr3_ctrl.sh lines 18 and 19, fpga/ddr3_write/top.cst"
    - "TinyVCMI build/ddr3_ctrl/seed1/nextpnr.log and build/ddr3_ctrl/top.json (cells phy.ddr_pll, phy.dll, phy.fdiv)"
    - "TinyVCMI build/ddr3_write/open/wr-routed.json (net mclk, pip X0Y30/FCLKA/HCLK00; ddr_pll at X1Y27/PLL, fdiv at X0Y81/CLKDIV_0, dll at X1Y108/DDRDLL_BL)"
    - "aquasock/nextpnr branch epic/gw5ast138c, himbaechel/uarch/gowin/gowin_arch_gen.py extend_dq_lane_fclk and hclk_pips"
  verification: "Eight seeds, run eight at a time, all failed on the same named arc; the warning census of one seed was 586 repetitions of `Failed to route net 'adapter.pclk' ... using dedicated routing`, one `mclk feeds a DQS FCLK but is carried on 2 HCLK lanes` warning, and one `get_nets argument 'pclk' matched no objects`, after which tools/build_ddr3_ctrl.sh was made to fail on an unmatched clock constraint. The broad generator change and the narrow one were both reverted, and the fork's check_dqs_site.py passes six of six against the reverted tree. No image was packed and no hardware was accessed. Revised 2026-10-24: the first version of this record concluded that bank 7 had no modelled FCLK pips; reading the same build's log found the three unmatched INS_LOC cells and the PLL at X1Y81, and the routed write image showed the bank-7 pip in use, so the statement and consequence were rewritten. The constraint fix has not been built."

- record_id: TOOL-033
  topic_id: TOOL
  title: "The proven controller gates and clocks each lane's reads separately and trains them on RBURST"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "In the hardware-proven vendor DDR3 controller's post-route netlist each of the four DQS blocks has its own READ[3:0] (u_ddr_phy_top/read [4n+3:4n]), its own RCLKSEL[2:0] (rclk_sel [3n+2:3n]) and its own HOLD, while RLOADN, the inverse of ddr_sync's pause, is shared. A lane's READ is a registered mux over the read-command pipeline -- cmd_rd_q from the command lane, then read_line1, read_line2, read_line3 and later taps -- selected by that lane's 4-bit read_calibration_logic_gen[n].read_i. Simulated with Gowin's primitive models, read_i 0 to 12 open a window of four memory clocks per READ that slides one memory clock per step across PCLK boundaries, 1111 at 0, then 1110 followed by 0001 at 1, 1100 and 0011 at 2, 1000 and 0111 at 3, 1111 one PCLK later at 4, and so on to 12, with 13 to 15 opening nothing, and read_adj does not change the window. Each lane's calibration block holds read_i, read_adj, cal_cnt, ides_calib_cnt and read_cal_done, and it takes RBURST as a level: rburst_t is the AND of RBURST sampled at a PCLK rising edge and at two consecutive falling edges. Read data is not taken from the deserializers on every cycle: each lane registers its IDES8_MEM outputs (iserdes_dq_Z, CE tied high) and its DQS RVALID (rvalid_Z) once on PCLK, and its fabric read FIFO fifo_ctrl_gen[n] advances its write pointer only from rvalid_Z, so a word enters the FIFO only on a cycle whose RVALID was high; the controller's read-data valid, phy_rdbk_data_valid[n], is that FIFO not being empty after initialization."
  consequence: "The window shape and the bit order are the same as fpga/ddr3_write's (delay, k) gate, so the gate's form is not what separates the two designs. What does is that the proven controller trains the gate position and RCLKSEL per lane against an RBURST level, while fpga/ddr3_write and the extracted fpga/ddr3_ctrl PHY drive one READ and one RCLKSEL into all four lanes and have never read RBURST as a level during isolated reads. A read path that is to serve single READs should give each lane its own READ and RCLKSEL and observe RBURST the way the vendor samples it, and it must take a lane's word only where that lane's registered RVALID is high, as the vendor's FIFO does; fpga/ddr3_write ignores RVALID and reads the deserializers on every cycle, which a stream of one pattern cannot distinguish. The vendor's training order and acceptance rule are not yet decoded."
  sources:
    - "Tang-PSX build/gate1-ip/ddr3_memory_interface/ddr3_memory_interface.vo: DQS instances u_ddr_phy_wds/data_lane_gen[0..3]..u_dqs, u_ddr_init/read_calibration_logic_gen[0..3], u_ddr_phy_wds/u_ddr_phy_cmd_lane/read_d_*"
    - "TinyVCMI tools/vendor_read_gate_trace.py"
    - "Gowin EDA 1.9.11.03 IDE/simlib/gw5a/prim_sim.v"
  verification: "tools/vendor_read_gate_trace.py cuts lane 0's READ cone back to the read pipeline taps, read_i and read_adj, 19 cells with no undriven input, and simulates it with iverilog against Gowin's models for both read_adj values and all sixteen read_i. The per-lane READ, RCLKSEL and HOLD buses and the shared RLOADN were read from the four DQS instances' port lists, and the RBURST sampling from the cone of rburst_t, a LUT3 with INIT 8'h80 over rburst_pos on clk_out and rburst_neg and rburst_neg_r on its inverse. No hardware was accessed for this record. Revised 2026-10-24: the cone of phy_rdbk_data_valid[0] leads to fifo_ctrl_gen[0].fifo_ctrl/if_Empty_reg, whose block's only data-side inputs are rvalid_Z[0] (DFFCE on clk_out from the lane's DQS rvalid_wire), if_fifo_rd_flg[0] and the reset, and the lane's iserdes_dq flops are DFFCE on clk_out with CE tied to VCC."

- record_id: TOOL-034
  topic_id: TOOL
  title: "Isolated READs: each lane holds its own READ's burst in at most about half of READs, at any per-lane gate and RCLKSEL"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "fpga/ddr3_write with a per-lane READ gate delay, gate offset and RCLKSEL and rd_check's lag classifier -- which READ's pattern each lane holds at the check offset, its own, one of the three before it, or none, counted only for READs whose four recent patterns are distinct -- was run on closed-page single READs. At an access period of 8 PCLK and the old shared setting (delay 1, gate 2, RCLKSEL 0) the lanes differed sharply: lane 3 held a recent READ's burst in 87 to 97% of READs at most offsets, its answer stepping by exactly one READ every 8 offsets and split about evenly between two adjacent READs, lane 2 in about half, lane 0 in pockets of up to 28% and lane 1 in none at most offsets. At an access period of 40 PCLK, after a reload that changed which lane behaved best, the best lane held its own READ's pattern in 51.2 to 51.5% of READs from offset 14 onwards at two offsets out of every three and in 2.7% at the third, a period of three PCLK locked to the READ, where a captured burst that persisted until the next one would give near 100%. Over all 256 settings of delay 0 to 7, gate 0 to 3 and RCLKSEL 0 to 7, set alike on every lane and read per lane at offsets 12, 16, 20, 24 and 28, each lane's best own-READ share was 51.6, 51.4, 51.5 and 44.6%, reached at different settings per lane and never exceeded; the Gowin build of the same source reached 51.2, 51.2, 51.1 and 50.0% over 48 of those settings with the same three-PCLK pattern. RBURST sampled as the vendor samples it was high for 76.1% of random-mode PCLK at period 8 and 95.2% at period 40 on every lane alike in the open build, about two PCLK low per READ, and 0% in the Gowin build at the same setting."
  consequence: "Per-lane gating and RCLKSEL move where a lane's best share appears but do not lift it, so they are not the missing piece on their own. The deserializer output after an isolated burst is not a held word: it is valid only on some PCLK, in a pattern locked to the READ, which is exactly what the proven controller's RVALID-written read FIFO of TOOL-033 selects and what fpga/ddr3_write never does. The next read path takes a lane's word only on cycles where its registered RVALID is high and checks isolated READs again, before any per-lane training is designed. In the open build RBURST as a level follows the READ gate rather than the data and is no training signal yet; the open/vendor difference in it is unexplained."
  sources:
    - "TinyVCMI fpga/ddr3_write/rd_check.v (lag classifier, lag_eval, lag_cnt), fpga/ddr3_write/wr_core.v (commands 0x2C to 0x2F, rb_lvl, status4), fpga/ddr3_write/tb_check.v cases 8 and 9, fpga/ddr3_write/tb_wr.v"
    - "TinyVCMI tools/ddr3_write_probe.py lag and tools/ddr3_lag_sweep.py"
    - "TinyVCMI docs/ddr3-open-flow.md: Which READ each lane returns"
  verification: "The open image, .bin SHA-256 2360774bc9c45a40f0ef7db3148edd0f6603df33d822c5803bc7dbf15cc73b45, closing PCLK at 126.98 MHz and equal on all 306 DDR3 tables to its Gowin build, and that build, .bin SHA-256 a6822db8e33357a9abcdf1ad450643e7872871219106c7b083d7351cd4dd8bcf, closing PCLK at 109.973 MHz with no negative slack, were loaded on the Tang Console 138K on 2026-10-24, answered core 0x56 and were calibrated, with every lane within one cycle of all eligible cycles, and the sixteen rows prewritten. Mid-session the FPGA was found answering core 0, configuration lost for a reason not determined, and the open image was reloaded, recalibrated and rewritten before the period-40 runs. The unit bench's lag cases pass and a mutant with lags 1 and 2 swapped fails them; the image simulation compares 635 per-lane gates and confirms per-lane RCLKSEL and frame 0x2F. The desktop core was restored and answered 0x54."

- record_id: TOOL-035
  topic_id: TOOL
  title: "RVALID-held capture returns isolated READs whole on a lane, but which settings do so changes from one FPGA load to the next"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "fpga/ddr3_write's rd_check now registers each lane's deserializer word and RVALID before any selection and, with command 0x29 set, checks a word held from that lane's last RVALID-high cycle, as the proven controller's read FIFO takes it (TOOL-033); frame 0x2F reports each lane's share of PCLK with RVALID high. The input register makes the checker's PIPE 4, so every offset is one higher than the same arrival recorded before this record. On the open image, closed-page single READs every 40 PCLK at delay 1, gate 2, RCLKSEL 0 gave lanes 1 and 2 at most 51.5% own-READ without the hold and 100.0% with it at offsets 20 and 26, 98% at 14, none classified as none, while lane 0, whose RVALID was high in 2.4% of cycles against 67.4% on the others, reached 18.8% and lane 3 57%. Over all 256 per-lane delay, gate and RCLKSEL settings with the hold, at offsets 18 to 23, lane 0 reached 100.0% at six settings, among them RCLKSEL 3 delay 1 gate 3, lane 1 at three, among them RCLKSEL 3 delay 1 gate 1, lane 2 at two, among them RCLKSEL 3 delay 1 gate 0, and lane 3 at most 60.4%; every full score came with that lane's RVALID high in two of every three cycles, and the full score falls at one offset in three. Applying those settings together, lane 1 held 100.0% at offsets 17, 20, 23, 26 and 29, lane 2 only at 17 and 29, and lane 0 23%, and lane 2's RVALID share changed between random-mode entries at identical settings, 2.4%, 67.4% and 100%. The Gowin build of the same source with the hold, at the old shared setting, reached at most 17% with RVALID high in 59.4% of cycles on every lane."
  consequence: "Taking a lane's word only where RVALID is high is the missing mechanism: it turns a lane that never exceeded half of isolated READs into one that returns every READ's own burst. What remains is that the RVALID pattern a lane settles into is fixed at the start of a read session and differs from one session to the next, so a per-lane setting found in one session does not hold in the next; the DQS read FIFO's pointer relationship needs to be put into a known state at each session, which the proven controller's init_rmove and rpoint/wpoint logic is the reference for, before per-lane training can produce a stable result. Settings found on one build do not carry to the other."
  sources:
    - "TinyVCMI fpga/ddr3_write/rd_check.v (dq_in, rv_in, dq_held, rv_enable, PIPE 4), fpga/ddr3_write/wr_core.v (command 0x29, rv_cnt, status4), fpga/ddr3_write/tb_check.v case 10"
    - "TinyVCMI tools/ddr3_write_probe.py lag --rvalid and tools/ddr3_lag_sweep.py --rvalid"
    - "TinyVCMI docs/ddr3-open-flow.md: Taking a word only when RVALID says so"
  verification: "The open image, .bin SHA-256 bb809c5b80dc83b3d26c15776e679431c6974c76cad2233baa6cfae7d93e5605, closing PCLK at 110.93 MHz, and its Gowin build, .bin SHA-256 d55b007fb30b598e5fc1400f3f3f2c1627a1600954c5c2b6ef8c5b5febc3c750, closing PCLK at 104.469 MHz with no negative slack, equal on all 306 DDR3 tables, were loaded on the Tang Console 138K on 2026-10-24 and calibrated, every lane within one cycle of all eligible cycles. The first calibration attempt of the open image stopped with no reply to command 0x0f and the FPGA was then found unconfigured; after a reload it held configuration idle for 30 s of status polls and calibrated cleanly. TinyTang's own fpga query gets no answer while the probe holds the fpgapipe link, so it was not used mid-session. The checker bench's case 10 holds a burst valid for one PCLK with RVALID marking it in 300 of 300 READs and fails all 300 without the hold. The desktop core was restored and answered 0x54. Revised 2026-10-24: tools/ddr3_boot_repeat.sh repeated the check over three Tang reboots and four completed loads of the same image. Within each load five random-mode re-entries at one offset gave identical per-lane results, but which lanes reached 100% changed from load to load at identical settings, including between two loads in one boot: at the old shared setting none, lanes 0 and 1, and lane 2; at one per-lane combination lanes 0 and 2, lane 1, and none. The right setting is therefore fixed per FPGA load and PHY start-up, not per read session or Tang boot, and the earlier reading of a per-session change is superseded. In two of the three boots the first load after the reboot stopped answering mid-calibration, no reply to command 0x07 then no core, and a reload recovered; the cause is not determined."

- record_id: TOOL-036
  topic_id: TOOL
  title: "The proven controller's read calibration: one RVALID cycle and one RBURST pulse per READ, found by sweeping RCLKSEL and then the gate per lane"
  status: VERIFIED
  verified_date: 2026-10-24
  statement: "Simulated with Gowin's primitive models, the hardware-proven vendor controller's u_ddr_init block, 1,518 cells cut from Tang-PSX's post-route netlist, runs read calibration after write leveling as follows. A calibration step issues four BL8 READs five PCLK apart, and a batch is 30 steps, read_cmd_cnt ending at 30. During a batch each lane counts, after filtering the first burst, PCLK cycles with its registered RVALID high (rvalid_cnt) and falling edges of its RBURST level, high at a PCLK rising edge and two consecutive falling edges (rburst_cnt), and the lane passes only when both equal 116, which is 29 steps of four READs: exactly one RVALID-high cycle and one RBURST pulse of at least about one and a half PCLK per READ. A model answering every READ with RVALID for one PCLK and RBURST for one PCLK never passes; with RBURST held two PCLK it passes. The block sweeps lane 0's RCLKSEL upward from 0 at read_i 0 and stops at the second passing setting in a row: with every setting passing it finished at RCLKSEL 1, with only 3 to 5 passing at 4, and with only 6 and 7 at 7. With no setting passing it repeated the RCLKSEL sweep about eight times at each gate position before stepping read_i, eight sweeps at read_i 0 and nine at each of 1 to 4. The FIFO pointers are not reset by the fabric: RPOINT and WPOINT go straight to the deserializers, and RMOVE only steps the read delay (init_rmove from the DLL code, eye_calib around the eye)."
  consequence: "The proven controller does not make a read session stable by re-aligning the FIFO; it searches gate position and RCLKSEL per lane until RVALID behaves as exactly one valid cycle per READ and RBURST as one pulse per READ, and only then uses the RVALID-qualified words of TOOL-033. That is the condition fpga/ddr3_write has never selected for: its 100% settings of TOOL-035 had RVALID high two cycles in three, a state the vendor would reject, while the one-in-forty RVALID share seen on some lanes at an access period of 40 is the vendor's accepted state. The next read path counts RVALID cycles and RBURST pulses per READ per lane and trains gate and RCLKSEL to one of each, then checks whether that state holds across read sessions."
  sources:
    - "Tang-PSX build/gate1-ip/ddr3_memory_interface/ddr3_memory_interface.vo: u_ddr_init (read_cal_state, read_cmd_cnt, rvalid_cnt, rburst_cnt, rvalid_cnt_check, rburst_cnt_check, filter_first_burst, read_calibration_logic_gen[n]), u_init_rmove_mod, u_eye_calib_rmove_mod"
    - "TinyVCMI tools/vendor_read_cal_trace.py and tools/vendor_read_cal/tb_read_cal.v"
    - "Gowin EDA 1.9.11.03 IDE/simlib/gw5a/prim_sim.v"
  verification: "The acceptance constants were read from the LUT INITs, rvalid_cnt_check[0] true only at rvalid_cnt 116 and rburst_cnt_check[0] only at rburst_cnt 116, the batch end from read_cal_next_state at read_cmd_cnt 30, and the counting conditions from their cones: rvalid_cnt counts rvalid_Z with filter_first_burst set during calibration, rburst_cnt counts rburst_t low after rburst_t_r high. tools/vendor_read_cal_trace.py reproduces the four windowed runs and the never-passing run, which stops at the bench's 8 ms limit at read_i 5; in each run the block's commands were decoded from phy_cs_n, phy_ras_n, phy_cas_n and phy_we_n of its last command slot. The other modules the block waits on were modelled as answering done 200 PCLK after their start, so their own timing is not part of this record. No hardware was accessed."

- record_id: TOOL-037
  topic_id: TOOL
  title: "The vendor's read-calibration state is reachable on two lanes per load, but in it the RVALID word often carries another READ's burst"
  status: VERIFIED
  verified_date: 2026-10-25
  statement: "fpga/ddr3_write now counts, in random mode since the arm, the READs issued and per lane the PCLK with RVALID high and the RBURST pulses sampled and counted as the proven controller does, returned in frame 0x31, and tools/ddr3_write_probe.py train applies the vendor's search of TOOL-036: gate positions 0 to 31 from earliest, RCLKSEL 0 to 7 on every unlocked lane, a lane passing when both counts equal the READs within two, locked at the second pass in a row. On the open image about 81,000 isolated READs per setting at period 40 gave passing lanes exactly 1.00 RVALID cycle and 1.00 RBURST pulse per READ, so the vendor's accepted state exists on this board; lanes 2 and 3 locked at delay 1, offset 1, RCLKSEL 4 and kept passing at every later setting, while lanes 0 and 1 never passed in 256 settings, often with RBURST at 1.00 per READ and RVALID at 14 to 42 cycles per READ. The counts moved in jumps between a few fixed values at particular setting changes and then held, not following the setting. The Gowin control, rebuilt with place option 3 and route option 1, locked lanes 0 and 1 and never lanes 2 and 3. In the accepted state the lanes did not return their own data: with RVALID-held capture the open image's lanes 2 and 3 held their own READ's pattern in 18.8% and 11.5% of READs and the Gowin control's lanes 0 and 1 in 31.2%, every share a whole number of sixteenths, while a lane left in the two-in-three RVALID state held 100% at its offsets. Moving lanes 2 and 3's read delay over plus and minus 40 steps changed nothing, re-aligning per-bit framing on a stream changed nothing, and the failing words were consistent across all eight pins of a lane at one rotation but were clean bursts of another row's pattern."
  consequence: "Exactly one RVALID cycle and one RBURST pulse per READ is necessary for the vendor but not sufficient here: in that state the word under the RVALID cycle is often another READ's burst. It is not a fixed number of READs back: TOOL-038 deepened the lag classifier to eight READs and found lags 1 to 8 flat at chance level, with which READs succeed set by the READ sequence alike on every trained lane."
  sources:
    - "TinyVCMI fpga/ddr3_write/wr_core.v (rb_fall, tr_reads, status5, command 0x31) and fpga/ddr3_write/tb_wr.v"
    - "TinyVCMI tools/ddr3_write_probe.py train"
    - "TinyVCMI tools/ddr3_write.py --vendor --place-option 3 --route-option 1"
    - "TinyVCMI docs/ddr3-open-flow.md: Eight READs back: no fixed offset (the revision)"
  verification: "The open image, .bin SHA-256 49fc517b642db04d4d5a90da0392fe4b7adec57efba8212931e72b4d499a7e0c, closing PCLK at 113.38 MHz, and its Gowin build, .bin SHA-256 74bf2ed439c5b8d59ed88cdd03471e9a39f5d3507a16a1073ee2e7004cfe644e, closing PCLK at 105.429 MHz with no negative slack after Gowin's default options had missed at 90.883 MHz, equal on all 306 DDR3 tables, were each loaded on the Tang Console 138K on 2026-10-24, calibrated within one cycle of all eligible cycles on every lane and trained. The read-delay sweep moved lanes 2 and 3 together with RMOVE in single steps and returned them to their starting point. The image bench checks that the training counters follow the random READs and that frame 0x31 carries them. The desktop core was restored and answered 0x54. Revised 2026-10-25: the consequence read the failing words as an in-order capture offset by some number of READs; the eight-READ lag classifier of TOOL-038 found no fixed offset on any trained lane, so the consequence was rewritten."

- record_id: TOOL-038
  topic_id: TOOL
  title: "In the vendor's accepted read state there is no fixed READ offset; which READs succeed follows the READ sequence, identically on every trained lane"
  status: VERIFIED
  verified_date: 2026-10-25
  statement: "fpga/ddr3_write's lag classifier now names, per lane at the check offset, the READ's own pattern, those of the eight READs before it, or none, counting only READs whose nine patterns are distinct, about 6% of random READs; frame 0x2F carries the 40 counters in 206 bytes. Trained with tools/ddr3_write_probe.py train and checked at offsets 14 to 25 with about 21,600 classified READs per offset at period 40 and RVALID-held capture, three loads of the open image and two of the Gowin control gave: open load 1, lane 3 in the vendor's state at delay 0, offset 3, RCLKSEL 4, holding its own READ's pattern in 13.6% of READs, 2.5 to 3.1% at each lag 1 to 8 and none in 65%; open loads 2 and 3, no lane in the vendor's state over 256 settings; control load 1, lanes 0 and 2 at RCLKSEL 4 with gate positions 6 and 4, and control load 2, lanes 0, 1 and 3 at gate positions 6, 4 and 6, every one of those five trained lanes at 31.0% own, 2.4 to 2.8% at each lag 1 to 8 and 48.5% none, the same to 0.1% in all ten classes and at every offset. Random mode reseeds its address generator, XS_SEED in wr_core.v, on every entry, so every run issues the same READ sequence. Lanes left untrained at delay 1, offset 2, RCLKSEL 0, with RVALID high in 2.4 to 100% of cycles, held their own READ's pattern in 11 to 31% at their best offset and the READ one before in up to 23.6%."
  consequence: "The offset hypothesis of TOOL-037 is falsified for lags 1 to 8: the lags are flat at chance level, so an in-order read FIFO has no fixed per-lane offset to absorb. The per-READ property shared by every trained lane is the READ's pattern: TOOL-039 found every trained lane's word one memory-clock slot wrong, so a READ looks right only when its pattern's two affected beat pairs are equal. The open image reaches the vendor's state far less often than the control: on one lane in three loads against two or three lanes per load."
  sources:
    - "TinyVCMI fpga/ddr3_write/rd_check.v (LAGS, prev_mask, prev_ok, lag_cnt), fpga/ddr3_write/wr_core.v (status4, frame), fpga/ddr3_write/tb_check.v case 8, fpga/ddr3_write/tb_wr.v (frame 0x2F over the link)"
    - "TinyVCMI tools/ddr3_write_probe.py (LAGS, lag, lag_line, train) and tools/ddr3_boot_repeat.sh"
    - "TinyVCMI docs/ddr3-open-flow.md: Eight READs back: no fixed offset"
  verification: "The open image, .bin SHA-256 ba985ab51c873a9f9ab90f9147951fb84191fab259c68729f9669ee0ea0bc1d7, closing PCLK at 117.00 MHz, and its Gowin build, .bin SHA-256 1dbb6ae84b64a89900a43f2bae02b009331323cc1278ff443fb750da353ba20f, built with place option 3 and route option 1 and closing PCLK at 101.381 MHz with no negative slack, equal on all 306 DDR3 tables with lanes exact, were placed on the card as ddr3_lag8.bin and ddr3_lag8_vendor.bin and loaded on the Tang Console 138K on 2026-10-25 by tools/ddr3_boot_repeat.sh, three times and twice, in one Tang boot; every load calibrated all 32 bits within one cycle of all eligible cycles and none stalled. The checker bench classifies lanes at lags 0 to 3 and 4, 5, 7 and 8 exactly, a lane at lag 9 as none in 70 of 180 READs as chance predicts, and mutants with lags 1 and 2 or 7 and 8 swapped fail it; the image bench receives all 210 bytes of frame 0x2F over the simulated link equal to status4, and the probe's decoder reads that dump back to the bench's per-lane settings. The desktop core was restored after every load and answered 0x54. Revised 2026-10-25: the consequence named location, column, spacing or position as the deciding property; the READ log of TOOL-039 showed it is the READ's pattern under a one-slot slip, so the consequence was rewritten."

- record_id: TOOL-039
  topic_id: TOOL
  title: "A trained lane's word has one memory-clock slot wrong; two IDES8_MEM CALIB pulses at the trained setting make it whole"
  status: VERIFIED
  verified_date: 2026-10-25
  statement: "fpga/ddr3_write's rd_check now logs 1024 READs at the check offset after passing over log_skip x 1024, each with its location, burst, refresh phase and, per lane, the least rotation held, whether its pins agreed and its rotation (commands 0x32 to 0x34). In the vendor's read-calibration state of TOOL-036, one RVALID cycle and one RBURST pulse per READ, a trained lane's held word is fixed per location: 100% or 0% own, every word pin-consistent. One rule fits all sixteen locations: at the lane's framing rotation every held bit equals its own beat except one 2-beat pair, one memory clock, which is a copy of the next pair -- on the control's lane 1 in two loads at different settings, burst beats 2 and 3 replaced by beats 4 and 5, and on the open image's lane 3 beats 0 and 1 replaced by 2 and 3. The locations that read as own are exactly the patterns whose two affected pairs are equal, five of sixteen. In the proven controller's post-route netlist each lane's read_calibration_logic_gen[n].read_adj, registered as u_ddr_phy_wds/data_lane_gen[n].u_ddr_phy_data_lane/u_ddr_phy_data_io/ides_calib_d by ides_calib_d_s0, drives CALIB on all eight of the lane's iserdes_gen[0..7].u_ides8_mem; read_adj pulses once after every RCLKSEL sweep that left the lane unconfigured, a 4-bit ides_calib_cnt counts 0 to 8 and only at 8 lets read_i advance, and a lane's read_cal_done also requires its read-back data to equal a fixed pattern, 64'h55AA33CCACD6E3D9 per 64-bit lane slice, whose bit 8q + p is lane pin p at IDES8_MEM output Qq, so beats 0 to 7 read D9, E3, D6, AC, CC, 33, AA, 55. While start-up owns the PHY, u_ddr_phy_top's write-data mux forces 256'h55555555_AAAAAAAA_33333333_CCCCCCCC_ACACACAC_D6D6D6D6_E3E3E3E3_D9D9D9D9, and in the cut u_ddr_init simulation the calibration writes it as one BL8 burst to bank 0, row 0x1000, column 0 before each RCLKSEL trial, then reads it with 30 groups of four BL8 READs. On the board, CALIB pulses on a trained lane's eight DQ at its trained setting moved the slip and, after exactly two, gave the identity beat map with every READ its own burst and the vendor's state kept: control lane 2 in the sweep load, lane 1 in control load 1, lanes 1 and 2 in control load 2 and lanes 0 and 3 in open load 1, the sweep load's lane by its 256-READ log at 100.0% own and the lag check of the four --calib-fix loads then reading 100.0% own on every trained lane but open lane 3, at 80% own and 20% none at every offset. Training reached the vendor's state on no lane in open load 2. Sweeping a trained lane's gate by up to three memory clocks and RCLKSEL lost the vendor's state, which then did not return at the trained setting, and many points read whole bursts only in the many-RVALID state of TOOL-035."
  consequence: "Isolated READs return their own data on a trained lane once its deserializer framing is corrected after the gate and RCLKSEL are trained: the missing step was CALIB inside the search, with read-back data as a pass condition, which the proven controller has and fpga/ddr3_write's training did not. Two pulses at the trained setting is what this board needed in every case seen, but the vendor's rule is a search over gate, CALIB and RCLKSEL with a data check, and a training that copies it is the robust form. Still open: training reaches the vendor's state on only some lanes per load and on none in some open loads, the state is lost when settings are visited out of order, and open lane 3 needs its read eye centred. The acceptance gate before controller work resumes is now within reach on trained lanes."
  sources:
    - "TinyVCMI fpga/ddr3_write/rd_check.v (log_mem, lw_skip, log_buf), fpga/ddr3_write/wr_core.v (commands 0x32 to 0x34, status6), fpga/ddr3_write/tb_check.v case 11, fpga/ddr3_write/tb_wr.v (frame 0x34 over the link)"
    - "TinyVCMI tools/ddr3_write_probe.py (train --log, --calib-fix, --sweep, logreport, beat_map) and tools/ddr3_boot_repeat.sh (TRAIN_EXTRA)"
    - "Tang-PSX build/gate1-ip/ddr3_memory_interface/ddr3_memory_interface.vo: u_ddr_init/read_calibration_logic_gen[0..3] (read_adj_s0, ides_calib_cnt, read_cal_done), u_ddr_phy_wds/data_lane_gen[0..3].u_ddr_phy_data_lane/u_ddr_phy_data_io (ides_calib_d_s0, iserdes_gen[0..7].u_ides8_mem)"
    - "TinyVCMI docs/ddr3-open-flow.md: The READ log: one memory clock off, and CALIB puts it right"
  verification: "The open image, .bin SHA-256 7864144d88abd4f93561fdbe6faa4525ae93aae1371c705084828e6c89bff681, closing PCLK at 118.95 MHz, and its Gowin build, .bin SHA-256 71ca168124e99909315dc9fa5bf00be61849d1a325ab8ad3dfb4559885022431, with place option 3 and route option 1 and closing PCLK at 103.195 MHz with no negative slack, equal on all 306 DDR3 tables with lanes exact, were placed on the card as ddr3_log.bin and ddr3_log_vendor.bin and loaded on the Tang Console 138K on 2026-10-25 nine times by tools/ddr3_boot_repeat.sh, each calibrating all 32 bits within one cycle of all eligible cycles; the beat maps came from logreport and the --calib-fix and --sweep runs. The checker bench passes over 1024 READs, keeps 1024 and reads two pages back entry by entry, and a log that skips one READ fewer fails it; the image bench receives frame 0x34 over the simulated link equal to status6 with an entry equal to the log RAM. The netlist reading of read_adj, ides_calib_cnt, the CALIB rule and the read-back constant was made by a second agent, Codex, from LUT equations and instance connections; the ides_calib_d drive of all eight u_ides8_mem CALIB pins of a lane and its ides_calib_d_s0 flop were checked here in the netlist, and the rest is that agent's reading. The same agent took the read-back layout and the forced write constant from the netlist, and the write's address and count from tools/vendor_read_cal_trace.py's cut simulation run in its own temporary directory with command observation added, 142,596 KiB peak; that run is not committed. The desktop core was restored after every load and answered 0x54."

- record_id: TOOL-040
  topic_id: TOOL
  title: "The read delay stops at the top of its range; the vendor-style search trains whole lanes, but about one per load"
  status: VERIFIED
  verified_date: 2026-10-25
  statement: "tools/ddr3_write_probe.py train --vendor-search searches as the proven controller does (TOOL-036, TOOL-039): gate positions 0 to 31 outer, nine RCLKSEL 0 to 7 sweeps per position with one CALIB pulse on a lane's eight DQ after each sweep that leaves it unlocked, a lane passing a setting only with one RVALID cycle and one RBURST pulse per READ and whole bursts in its 256-READ log -- the identity beat map and at least 99% own -- and locking at the second pass in a row. Over twelve loads, six of each image, it trained 3, 0, 1, 2, 0, 0, 1, 0, 0, 1, 1 and 1 lanes, 10 of 48 lane-loads: control lanes 1, 2 and 3 in one load and lane 1 or 3 in others, open lane 3 in two loads and lanes 1 and 2 in one. RMOVE stops moving a lane's read delay at the top of its range: a trained lane's delay moved by none of 64 up steps in one load and by 25 of 64 in another, counted by stepping down to the lower edge again. The stream calibration's sweep from -128 to +127 passes up to its last position on all sixteen lane calibrations of four loads, and walking down from the top the lower edge is 44, 50, 54 and 56 steps below it on lanes 0 to 3 of the Gowin control and 58, 64, 66 and 68 on the open image, the same in both loads of each image. A centring that returned to its start by commanded steps after a 64-step upward scan left three trained control lanes at 0%, 26.5% and 55.1% own with the vendor's state kept and a fourth at 0%, while one anchored on the lower edge and centred on the reachable window left every lane it centred whole and the lag check of four trained lanes over four loads at 100.0% own; the old centring had also left two open lanes of one load at 100.0%. Calibration that parks lanes in the middle of the reachable window instead of at the top trained 0, 1, 1 and 1 lanes over four loads, no more than before. Lanes left untrained, with RVALID high in 59 to 67% of cycles, often read 100% own with RVALID-held capture."
  consequence: "The read path is right on every lane that reaches the vendor's state: framing by CALIB, the data check and a read delay centred on the reachable window give 100% of isolated READs their own burst. What stops a four-lane read path is that the vendor's state is reached on about one lane per load, not where the read delay sits; the proven controller's other start-up step, the read delay it sets from the DLL code in u_init_rmove_mod before read calibration (TOOL-036), is the next difference to remove. Any read-delay placement must be anchored on a measured edge, since commanded steps past the top are lost."
  sources:
    - "TinyVCMI tools/ddr3_write_probe.py (vendor_search, lane_pass, center_delay, sweep_and_center, train --vendor-search --center) and tools/ddr3_boot_repeat.sh (TRAIN_EXTRA)"
    - "TinyVCMI docs/ddr3-open-flow.md: The vendor's search, the top of the read delay, and one lane per load"
  verification: "The images of TOOL-039, ddr3_log.bin (.bin SHA-256 7864144d88abd4f93561fdbe6faa4525ae93aae1371c705084828e6c89bff681) and ddr3_log_vendor.bin (71ca168124e99909315dc9fa5bf00be61849d1a325ab8ad3dfb4559885022431), were loaded on the Tang Console 138K on 2026-10-25 twelve times by tools/ddr3_boot_repeat.sh with TRAIN_EXTRA set to --vendor-search --center, the last four after the calibration change; every load calibrated all 32 bits within one cycle of all eligible cycles. The search, both centrings and the calibration were each dry-run first against a scripted fake core with a planted window and a delay that stops moving, and placed lanes as designed. No source in fpga/ changed. The desktop core was restored after every load and answered 0x54. Revised 2026-10-25: TOOL-041 established that RDIR = 1, which this tool sends for its up steps, lowers the read tap, so the top of the range here is tap 0 and the lower edge the largest tap that still reads whole; the measurements are unchanged."

- record_id: TOOL-041
  topic_id: TOOL
  title: "The proven controller starts read calibration at read tap 4; RDIR = 1 lowers the tap; starting there does not train more lanes"
  status: VERIFIED
  verified_date: 2026-10-25
  statement: "In the proven controller's post-route netlist, read by the second agent Codex and simulated in cut form by it: the DDRDLL u_ddr_phy_top/u_dll STEP is captured once as dll_step_base[7:0] at the locked init start, and u_ddr_phy_top/u_init_rmove_mod registers it as dllstep_r and, after write leveling and before read calibration, drives every lane's u_dqs RMOVE with dllstep_r - 4 one-PCLK pulses, each followed by a low PCLK, all with RDIR = 1 (init_rdir[1] preset 1, cleared only at init_rmove_done_rr); for STEP 5 to 255 the cut simulation emitted exactly STEP - 4 pulses, all four lanes alike, and for STEP 0 to 4 it wraps to 252 to 256. RLOADN, the inverse of u_ddr_phy_top/pause in ddr_sync's state 2, loads every lane's read tap with STEP before that, so the lanes start read calibration at tap 4; the order in the cut u_ddr_init is write leveling, the initial read move, read calibration, eye calibration. During init RD_PNTR is the fixed 3'b000, DQS RESET is ddr_rst, WLOADN is held low, WMOVE and WDIR are tied low, and each lane's HOLD, hold_gen[L].hold_i gated by NOT read_rclksel_conf[L], pulses during write leveling and again in read calibration on lanes not yet configured. On this board, with STEP 43, tools/ddr3_write_probe.py train --vendor-delay -- RLOADN, then 39 pulses at RDIR = 1 on every lane -- followed by the vendor-style search and centring trained lane 3 alone in three of four loads, none in the fourth, and each such lane, whole at tap 4, had only 3 or 4 taps of whole bursts on the RDIR = 1 side: one stopped moving after 4 such steps, at tap 0, losing 60, so RDIR = 1 lowers the tap on the board as Gowin's GW2A DQS model labels it. Centring moved those lanes 23 or 24 taps up. With READs every 8 PCLK instead of 40, the same training trained no lane on either image."
  consequence: "Neither the vendor's starting tap nor a faster READ cadence within random mode is what leaves lanes outside the vendor's state. TOOL-040's top of the range is tap 0 and its lower edge the largest whole tap; the reachable whole window runs from tap 0 to about 44 to 68 taps, and the vendor's tap 4 sits near its low edge on this board, so the centre found by measurement, not tap 4, is the place to read. The remaining difference in how the proven controller prepares the DQS blocks is its HOLD pulses on unconfigured lanes during read calibration, which in Gowin's DQS model reset the FIFO control that sets RVALID; lanes that never train show many RVALID cycles per READ (TOOL-037), so a per-lane HOLD, driven as the vendor drives it, is the next change."
  sources:
    - "Tang-PSX build/gate1-ip/ddr3_memory_interface/ddr3_memory_interface.vo: u_ddr_phy_top/u_dll, u_ddr_phy_top/u_init_rmove_mod (dllstep_r, init_rmove, init_rdir), u_ddr_phy_top/pause, u_ddr_init/hold_gen[0..3].hold_i, read_rclksel_conf, data_lane_gen[0..3]...u_dqs (RMOVE, RDIR, RLOADN, HOLD, RD_PNTR)"
    - "Gowin EDA 1.9.11.03 GW2A DQS primitive model (RDIR = 0 plus, RDIR = 1 minus); the GW5A DQS model is a stub"
    - "TinyVCMI tools/ddr3_write_probe.py (train --vendor-delay, Core.move) and tools/ddr3_boot_repeat.sh"
    - "TinyVCMI docs/ddr3-open-flow.md: The vendor's starting tap, and which way RDIR goes"
  verification: "The netlist reading and the cut simulations of u_init_rmove_mod and u_ddr_init were made by Codex in its own temporary directories, 35,492 and 142,452 KiB peak, and are not committed; this side checked the board consequence. The images of TOOL-039 were loaded on the Tang Console 138K on 2026-10-25 six times by tools/ddr3_boot_repeat.sh, four with TRAIN_EXTRA --vendor-delay --vendor-search --center and two adding --gap 8, every one calibrating all 32 bits within one cycle of all eligible cycles; the desktop core was restored after every load and answered 0x54. The exact rule for the read-calibration HOLD pulses is not yet decoded. Revised 2026-10-25: the read-calibration HOLD rule is now decoded and its effect measured in TOOL-042."

- record_id: TOOL-042
  topic_id: TOOL
  title: "HOLD on unconfigured lanes between read-calibration trials makes all four lanes train, every load"
  status: VERIFIED
  verified_date: 2026-10-25
  statement: "In the proven controller's post-route netlist, read and cut-simulated by the second agent Codex: during read calibration u_ddr_init/hold_gen[0..3].hold_i, a common 11-PCLK pulse (hold_reg[0] seeded by the read-cal state-11 boundary, hold_reg_d[6:0], n2528_7), is gated per lane by LUT hold_Z_L_s, HOLD[L] = hold_i AND NOT read_rclksel_conf[L], into each data_lane_gen[L]...u_dqs.HOLD; it rises at every boundary between RCLKSEL trials, after a trial's 120 READs and before the next trial's write burst, with none before the first trial, RCLKSEL changing 3 PCLK into it and read_i one PCLK before it at a gate step, READ low throughout and RLOADN untouched. fpga/ddr3_write's wr_core drives each DQS HOLD separately, the start-up update's HOLD on all lanes ORed with command 0x35, which holds the lanes in v[3:0] for 4 x (v[7:4] + 1) PCLK or, with v[7:4] = 15, until the next 0x35; tools/ddr3_write_probe.py train --hold vendor holds every unlocked lane while the host changes its gate and RCLKSEL between trials, not before the first. With --vendor-delay --vendor-search --hold vendor --center, all four lanes trained in all four loads, two of each image: the Gowin control's lanes at delay 1, offset 2, RCLKSEL 4 after 4 CALIB pulses in 472 settings, the open image's at delay 1, offset 1, RCLKSEL 5 on lanes 0 and 1 and 4 on lanes 2 and 3 after 3 pulses in 392 settings, the same in both loads of each image; each lane's whole window was 44 to 62 taps, centring moved it 18 to 28 taps up, and the lag check then read 100.0% own on all sixteen lane-loads at every check offset from 14 to 25, every lane with RVALID high on 2.4% of cycles, one per READ at a 40-PCLK access period. The Gowin control of this source first missed PCLK at 96.846 MHz on paths from wr_core's pat_rot into rd_align, where GowinSynthesis had merged rd_align's identical rot_pat_r with it; no place or route option cleared it, and keeping rd_align's copy (syn_preserve, keep) closed PCLK at 107.310 MHz."
  consequence: "HOLD is the DQS FIFO reset the read training was missing: with it every lane reaches the vendor's one-RVALID-per-READ state, CALIB inside the search frames its bursts whole, and a centred read delay keeps them so, so isolated random READs return their own data on the whole 32-bit bus in every load seen. The acceptance gate before controller work resumes still needs the same result with address-derived data rather than sixteen row patterns, and read data handed on at a fixed trained latency rather than held from RVALID for a checker; the per-image training settings repeat, which a controller's start-up can rely on being found again rather than stored."
  sources:
    - "Tang-PSX build/gate1-ip/ddr3_memory_interface/ddr3_memory_interface.vo: u_ddr_init/hold_gen[0..3] (hold_reg, hold_reg_d, hold_i_s0), hold_Z_L_s, read_rclksel_conf, data_lane_gen[0..3]...u_dqs.HOLD"
    - "TinyVCMI fpga/ddr3_write/wr_core.v (hold, hold_upd, hold_lanes, command 0x35), tools/ddr3_write.py (per-lane HOLD), fpga/ddr3_write/rd_align.v (rot_pat_r kept), fpga/ddr3_write/tb_wr.v (HOLD checks)"
    - "TinyVCMI tools/ddr3_write_probe.py (Core.hold, train --hold vendor) and tools/ddr3_boot_repeat.sh"
    - "TinyVCMI docs/ddr3-open-flow.md: HOLD, and all four lanes"
  verification: "The open image, .bin SHA-256 9d673e1629d4c8ea0fa9614b2ed680c7fc874b16abbf6427788a542703d63d37, closing PCLK at 109.19 MHz, and its Gowin build, .bin SHA-256 4fa3444c38765d7dafaa0380d5e87ab49f1b3f0431a0dbae007560e9685706b7, place option 3 and route option 1, closing PCLK at 107.310 MHz with no negative slack, equal on all 306 DDR3 tables with lanes exact, were placed on the card as ddr3_hold.bin and ddr3_hold_vendor.bin and loaded on the Tang Console 138K on 2026-10-25 four times by tools/ddr3_boot_repeat.sh, each calibrating all 32 bits within one cycle of all eligible cycles. The image bench checks that command 0x35 holds exactly lanes 0 and 2 for 8 PCLK and leaves 1 and 3, and that its level form holds and releases. The netlist reading and the cut simulations, 142,464 KiB peak, were Codex's in its own temporary directory and are not committed. The desktop core was restored after every load and answered 0x54. Revised 2026-10-25: the two items the consequence left for the acceptance gate, address-derived data and a fixed read latency, are measured in TOOL-043."

- record_id: TOOL-043
  topic_id: TOOL
  title: "A fixed read latency on all four lanes, and address-derived data returned by every isolated READ once the write alignment is trained"
  status: VERIFIED
  verified_date: 2026-10-25
  statement: "After the read training of TOOL-042, rd_check with the RVALID hold off (command 0x29 0) and the two-word reassembler of TOOL-029 off (0x2A with bit 7 clear) found every lane's raw deserializer word to be its READ's own burst on every isolated READ at check offset 11 and at no other offset from 0 to 31, the same on all four lanes, on both images and in every load; with the reassembler on at slip 0 the same arrival reads at offset 12, and its slip of 4 on lane 3 joins two cycles, which first made lane 3 look unaligned. fpga/ddr3_write's fill (mode 5) then writes a region of 8 banks, the 16 rows {row[14:4], 0..15} and 128 bursts each, ACTIVATE, 128 back-to-back WRITEs and PRECHARGE per row, a refresh one row early so the interval stays at 7.17 us at most, each burst carrying one of the thirty aperiodic 8-bit necklaces picked by a fold of its bank, row bits and burst (apat and adata in wr_core.v, AD_PATTERNS and adata_pattern in the probe, equal on all 16,384 addresses), even DQ the pattern and odd DQ its inverse; its data passes a delay line of d = 0..7 PCLK and b = 0..7 beats set by command 0x36, and the WRITE itself leaves a PCLK after its word. Random mode with command 0x37 draws bank, four row bits and the burst from its address source, and rd_check checks each READ against that address's pattern. tools/ddr3_write_probe.py train --write-train fills and reads back at all 64 alignments: with the delay line behind the command the best was 26.6% at its earliest alignment, and with the data moved two PCLK earlier the Gowin control passed at d 1, b 4 and b 5 and the open image at d 1, b 2 and b 3, two beats apart, the same in both loads of each image, with all-lane own shares rising and falling over the neighbouring alignments, 59.6, 99.2, 100, 100, 75.0 on the open image. At the best alignment 725,822 of 725,822 isolated random READs held their address's pattern on all four lanes in each of the four loads, and a 1,024-READ log held all thirty patterns with every lane's word its own and its beat map the identity."
  consequence: "The acceptance gate set before controller work resumes is met on this board in the diagnostic image: after the trained start-up, isolated random READs over many rows and banks return each address's own address-derived data on the whole 32-bit bus, and every lane's burst is available at one fixed PCLK after its READ, so a controller can take read data at a trained latency without the RVALID-held capture. The write side needs its own trained alignment, d and b, and it differs between the open image and the Gowin control, so it is found at start-up as the read settings are, not carried from one build to another. What the test does not yet cover: per-pin and per-byte-lane independent data (every lane carries the same 8-bit pattern on all its pins), the full 1 GiB array and all columns of every row, back-to-back READs, and data masking; the mid-calibration stall seen first after Tang reboots also occurred on a fresh load in mid-session."
  sources:
    - "TinyVCMI fpga/ddr3_write/wr_core.v (R_FILL, apat, adata, wq, wq_all, fill_wr, commands 0x36 and 0x37, the random-mode address-data branch), fpga/ddr3_write/rd_check.v (exp_sel, issue_exp, issue_rhi, fresh_r), fpga/ddr3_write/tb_wr.v (the fill's data, its alignment and the refresh interval), fpga/ddr3_write/tb_check.v case 12"
    - "TinyVCMI tools/ddr3_write_probe.py (train --fixed-latency, --write-train, adata_pattern, exp_pat, Core.read_log adata)"
    - "TinyVCMI docs/ddr3-open-flow.md: A fixed read latency, and address data written and read back"
  verification: "The open image, .bin SHA-256 7485c10f58dce78f85b902f8c4403a5bd8897602162bfcf700f4a6fa55cd53b1, closing PCLK at 117.97 MHz, and its Gowin build, .bin SHA-256 6c2f1677bbaf144eeb96d60274eda314a67d94c7a78d014b2acb52cfaa870b26, place option 3 and route option 1, closing PCLK at 105.537 MHz with no negative slack, equal on all 306 DDR3 tables, were placed on the card as ddr3_fill.bin and ddr3_fill_vendor.bin and loaded on the Tang Console 138K on 2026-10-25 by tools/ddr3_boot_repeat.sh. One control load stopped answering mid-calibration with no reply to command 0x07 and was reloaded; four loads, two of each image, ran the whole sequence. The fixed latency was first measured on the ddr3_hold images of TOOL-042 over five loads. The image bench finds a fill row's 128 patterns back to back in the serializers' beats and the 19-beat move at d 2, b 3, and checks the protocol and a 7.17 us longest refresh interval with the fill. The desktop core was restored after every load and answered 0x54."

- record_id: TOOL-044
  topic_id: TOOL
  title: "The training image's heap-legalizer failure was a signed attempt-budget overflow"
  status: VERIFIED
  verified_date: 2026-10-25
  statement: "nextpnr's PlacerHeapCfg computed the default per-cell legalisation attempt budget as max(10000, int(cell_count) * int(cell_count) / divisor). The 48,302-cell DDR3 hardware-training netlist therefore overflowed its signed 32-bit multiplication because 48,302 squared is 2,333,083,204, and every positive timeout-divisor setting collapsed to the 10,000 floor; legalise_cell then reported failure after 10,001 attempts on a DFF or LUT that varied between runs. Commit 16237b0f in aquasock/nextpnr branch epic/gw5ast138c promotes the count, multiplication and maximum to int64_t without changing any Gowin BEL-validity rule."
  consequence: "Large designs must use a nextpnr build containing commit 16237b0f or set the timeout divisor to zero to take the existing unlimited-search path. With the fix, the hardware-training image receives a finite 356,044,612-attempt budget and places and routes normally, so device density and the Gowin legality rules are not the blocker recorded in TinyVCMI log entry 67."
  sources:
    - "aquasock/nextpnr commit 16237b0f, common/place/placer_heap.cc: PlacerHeapCfg"
    - "TinyVCMI build/ddr3_write/finite_timeout/nextpnr.log and wr-routed.json generated from the entry-67 training image"
    - "TinyVCMI docs/ddr3-open-flow.md: The training image's legalizer failure was an integer overflow"
  verification: "The committed netlist first failed deterministically after 10,001 attempts, and timeout-divisor values 1 and 200000 both printed a 10,000-attempt budget. The unchanged netlist then placed and routed through the pre-existing no-timeout path in 6 minutes 12 seconds, meeting PCLK at 119.80 MHz and the link clock at 63.95 MHz. After rebuilding the fork with commit 16237b0f, the ordinary finite setting logged 356,044,612 attempts and again completed place and route with the same timing results; focused nextpnr Gowin tests for internal nets, DQS sites, deterministic arch generation, HCLK-to-FCLK routing, post-route refusal and GW5A IODELAY all passed. No Tang hardware was accessed."

- record_id: TOOL-045
  topic_id: TOOL
  title: "The image's own DDR3 training trains every lane once its per-pin framing survives the stream's frame moves"
  status: VERIFIED
  verified_date: 2026-10-25
  statement: "The ddr3_seq sequencer of TinyVCMI log entry 67 framed each lane's pins against one target rotation chosen before it pulsed them one at a time, while the read stream's word frame moves now and then by the same amount on every pin (TOOL-023); a move during framing left one or two pins of a lane 2, 4 or 6 beats from the rest, seen on the board after a run and after an abort before any search CALIB, so that lane returned 0 of 344 counted READs as its own in every trial and never locked. Framed against its lane's pin 0 in the same snapshot and required to agree on all eight pins in eight snapshots 50 us apart, with up to three further framing passes, the sequencer trained all four lanes in five of five loads with nothing set from the host, in 2.22 to 2.23 s and 390 trials, at delay 1, offset 1, RCLKSEL 5 on lanes 0 and 1 and 4 on lanes 2 and 3 after 3 CALIB pulses, the settings the host's training finds, centred with 46 to 59 passing taps above tap 4, and found the write alignment at d 1, b 2; then about 725,830 isolated random READs per load over 8 banks x 16 rows x 128 bursts held their address's data on all four lanes, RVALID-held at offset 20 and raw at offset 11, and none raw at offset 12."
  consequence: "The start-up the host proved in TOOL-042 and TOOL-043 runs in hardware unattended, repeatably to the same settings, so controller work can take it over. Per-pin framing must compare pins with each other in one snapshot and check agreement over time, never chase a target chosen earlier. The 99% data rule and the 1 ms wait after a HOLD release now in the sequencer match the host's training but were not shown necessary on the board."
  sources:
    - "TinyVCMI fpga/ddr3_write/wr_core.v: ddr3_seq states S_FR4 to S_FR8, agree, pass_now and diag"
    - "TinyVCMI fpga/ddr3_write/tb_seq.v: the frame-move, rare-wrong-READ and late-restart model"
    - "TinyVCMI tools/ddr3_write_probe.py: hwtrain and Core.seq, frame 0x39 of 72 bytes"
    - "TinyVCMI docs/ddr3-open-flow.md: The hardware training on the board; The hardware training trains every lane"
  verification: "The open image, .bin SHA-256 bd1a556d0b82612ab4bd9947b6795d808d2afd8c1625afe52ab8b991889b8164, closing PCLK at 125.63 MHz and the link clock at 83.08 MHz, and its Gowin build, place option 3 and route option 1, .bin SHA-256 d6417534f85c429579b69df74f8ed24964f68592fdbdc9c139f46ef87bab08c0, closing PCLK at 103.029 MHz and clk50 at 51.833 MHz with no negative slack, equal on all 306 DDR3 tables, after every simulation of the build's gate under Icarus Verilog 14 passed; the open image was loaded as ddr3_hwtrain3.bin on the Tang Console 138K on 2026-10-25 five times for hwtrain followed by a stream of the framing pattern showing every lane's pins in agreement. tb_seq fails with the earlier fixed-target framing, with the 100% data rule and with no wait. The Gowin control was not loaded. Revised 2026-10-25: the record first stated that the sequencer locked 0 to 3 of 4 lanes per load, calibrated first or not, on the entry-68 image, SHA-256 d17425982499c894f9a1f30ed85e25bee6a36a3763f021700b34c0eecd705299, and suspected framing and then the data rule; a rebuild with per-lane diagnostics, SHA-256 8654695481a719391b64eedd72c45f4f1d5a83fce16bd9cb5945558d60ae227b, still trained 2 and 1 lanes in two loads and its diagnostics and pin checks located the framing fault. The desktop core was restored after every load and answered 0x54."

- record_id: TOOL-046
  topic_id: TOOL
  title: "The DDR3 controller image works on the board unattended, with lane 1 failing in two of six loads"
  status: VERIFIED
  verified_date: 2026-10-26
  statement: "fpga/ddr3_ctrl -- wr_core with AUTOTRAIN, dfi_phy with the write alignment built in at d 1, b 2, the in-order open-page controller ddr3_ctl and the memory test ddr3_bist -- built in the open flow at PCLK 111.62 MHz, link clock 89.95 MHz, equal on all 306 DDR3 tables to Gowin's build of the same sources. On the Tang Console 138K, with nothing sent from the host for five seconds after each load, the image initialised the array, trained all four lanes in 405 trials, found d 1, b 2, handed the bus over and ran its test, each pass writing all 2^25 words of the 1 GiB with address-, beat- and pass-derived data, reading them in order and reading 2^20 at random, about 0.74 s a pass. Four loads ran 81 or 82 passes in 60 s, about 2.84 x 10^9 words checked each, with no error; the first two the probe read, loads 2 and 3 after a reboot, failed 4,468 and 1,160 words on lane 1 and 48 and 26 on every lane over 44 and 81 passes, the first failing word 0x8260 on lane 1 in both."
  consequence: "The PHY, its training and an in-order controller run the whole array at speed with no host, so the controller path is sound; the residual failures are a margin on lane 1 that some loads lack, not a logic fault, and must be found and closed before the AE350 depends on the memory. Selecting the write alignment at run time is not affordable in this corner of the die (docs/ddr3-open-flow.md, The PHY's DFI side), so a load that trains another alignment is refused rather than served."
  sources:
    - "TinyVCMI fpga/ddr3_ctrl: ctrl_glue.v, dfi_phy.v, ddr3_ctl.v, ddr3_bist.v; fpga/ddr3_write/wr_core.v: AUTOTRAIN, mode 6"
    - "TinyVCMI tools/build_ddr3_ctrl.sh, tools/sim_ddr3_ctrl.sh, tools/ddr3_write_probe.py ctrl"
    - "TinyVCMI docs/ddr3-open-flow.md: The controller image"
  verification: "The open image, .bin SHA-256 1d5617587da0a38e97b609d8f8a0185b7e08d1361fb0aa5e748e0e9564fed64d, built by tools/build_ddr3_ctrl.sh after every simulation of its gate passed, including tools/sim_ddr3_ctrl.sh's two passes over 2^12 words against a model with DDR3-800 timing checks in memory clocks and its five failing mutants; Gowin's build, place option 3 and route option 1, reached 97.3 MHz and was not loaded. Placed on the card as ddr3_ctrl.bin and loaded seven times on 2026-10-26 after a reboot; the first load's report failed in the probe, which could not name mode 6, and the settings of loads 2 and 3 were not read. The desktop core was restored after every load and answered 0x54. Whether the failing loads were the first after the reboot because the board was still warming is untested, and the read to write turnaround is exercised only between passes."

- record_id: TOOL-047
  topic_id: TOOL
  title: "LiteDRAM's controller does not meet this PHY's 100 MHz, and its buffered mode reorders a port's reads"
  status: VERIFIED
  verified_date: 2026-10-26
  statement: "LiteDRAM's controller, generated by tools/litedram_ctrl_gen.py at the board's geometry with READ and WRITE on DFI phase 0, has a critical path from its ZQCS timer through the bank machines, the tFAW and tCCD controllers and the steerer to a bank machine's state, eleven logic levels and 12.8 ns: the whole image placed and routed at 77.9 MHz in the open flow, 77.2 MHz with placer timing weight 40 and timing-driven rip-up, and 90.0 MHz in Gowin EDA, against 100 MHz. With cmd_buffer_buffered the core issued two random READs of one native port in the opposite order to the requests and returned their data in that order; with with_auto_precharge off the image estimated 47 MHz before routing. Migen also names some signals differently from run to run unless PYTHONHASHSEED is fixed."
  consequence: "A 1:4 DFI at a 400 MHz memory clock needs its controller at 100 MHz, so TinyVCMI uses its own in-order controller, ddr3_ctl, which with a registered decision closes 111.62 MHz in the same image (TOOL-046). LiteDRAM's buffered mode cannot be used where a port relies on its data returning in request order."
  sources:
    - "LiteDRAM at /run/media/vash/GIT/Tang-PSX/third_party/litedram, commit c454a44 (2026-09-24): core/multiplexer.py steerer, core/crossbar.py, core/controller.py ControllerSettings"
    - "TinyVCMI tools/litedram_ctrl_gen.py: --setting and the fixed hash seed"
    - "TinyVCMI docs/ddr3-open-flow.md: Why not LiteDRAM"
  verification: "Measured on the controller image with the built-in write alignment: nextpnr's routed timing for the default core and with timing weight 40 and --tmg-ripup, Gowin's place option 3 and route option 1 report, and tools/sim_ddr3_ctrl.sh's model of the trained PHY, which with the buffered core saw READs at the pads in an order other than the native port's and its test get word 977's data for word 335. Not checked on hardware."

- record_id: TOOL-048
  topic_id: TOOL
  title: "The controller's lanes have wide read margin, untrained write timing, and fail after a cold start"
  status: VERIFIED
  verified_date: 2026-10-26
  statement: "On the TOOL-046 image under its memory test, with the test stopped while a setting changed and about 78 x 10^6 words checked per point: each lane read with no error from 20 taps below to 20 above its trained read delay, lanes 0 and 1 first failing at +24 and lanes 2 and 3 at -28. Every lane wrote at WSTEP 0, the image's start-up doing no write leveling; lane 0 wrote cleanly at WSTEP 0 to 16 and failed from 24, lane 1 at 0 to 24 and from 32, lane 2 at 0 to 56 and from 64, lane 3 at 0 to 80 and from 88, and a lane set back to WSTEP 0 kept failing every word for the rest of the load. After the board was cooled with air, four consecutive loads about 80 s apart failed 13,979, 2,020, 130 and 0 words on lane 1 and 182, 40, 11 and 1 on every lane over about 2.84 x 10^9 words each; in the first, lane 1 trained at RCLKSEL 4 with a 43-tap window instead of RCLKSEL 5 and 58 or 59 taps."
  consequence: "The controller's failures depend on the board's temperature from a cold start, most on lane 1. Write timing is untrained and its lower edges are unmeasured, so start-up needs write leveling before the controller can be relied on cold, and the read training's cold result should be checked for margin. Changing WSTEP live cannot be undone by reloading the old value, so a write sweep must reload or reset the lane between points."
  sources:
    - "TinyVCMI tools/ddr3_write_probe.py: margin, ctrl"
    - "TinyVCMI docs/ddr3-open-flow.md: Margins, and a cold start"
  verification: "Read sweep: one load on 2026-10-26 of ddr3_ctrl.bin (TOOL-046), offsets -28 to +28 in fours, 2 s a point. WSTEP sweep: one load, 0 to 120 in eights, 2 s a point, the lanes in turn; each lane's own window was measured before it was disturbed, and the earlier lanes' failures in later sweeps are the irreversible change. Cold start: the board cooled with air by the user, then four loads with 60 s tests. The desktop core was restored after every load and answered 0x54. Whether the failures are writes or reads is not yet separated, and the lower write edges are unknown."

- record_id: TOOL-049
  topic_id: TOOL
  title: "Write leveling does not cure the controller's cold failures; a new placement did"
  status: VERIFIED
  verified_date: 2026-10-26
  statement: "wr_core's write-leveling feedback, swept from WSTEP 0 to 124, rose to full between 24 and 28, 28 and 32, 16 and 24 and 20 and 24 on lanes 0 to 3 and fell near 115, 118, 106 and 106, half a clock being about 88 steps; at WSTEP 0 each strobe leads the clock by 21 to 30 steps. With each lane's WSTEP set from its own sweep and the training rerun on chip, which found d 1, b 2, four loads of the TOOL-046 image from an air-cooled board failed 21,920, 8,061, 321 and 34 words on lane 1. The image rebuilt with the memory test's per-pin, per-lane-and-beat counts and re-read log, the PHY, training and controller unchanged, closed PCLK at 106.79 MHz and in four loads from an air-cooled board failed no word over about 2.4 x 10^9 each, lane 1 having trained in the first at RCLKSEL 4 with a 43-tap window, as in the TOOL-048 load that failed 13,979."
  consequence: "The cold failures follow the placement, not the DRAM interface's training or the write strobe's alignment. The likeliest cause is a path between the I/O cells and the fabric, which nextpnr does not time at all (TOOL-050), worse in cold faster silicon. Write leveling at start-up is not needed for these failures."
  sources:
    - "TinyVCMI fpga/ddr3_ctrl/ddr3_bist.v: pin_err, beat_err, elog; ctrl_glue.v: frame 0x3D pages"
    - "TinyVCMI tools/ddr3_write_probe.py: level, ctrl --diag"
    - "TinyVCMI docs/ddr3-open-flow.md: Write leveling, the test's diagnostics, and a placement"
  verification: "Leveling sweep and leveled cold loads with ddr3_ctrl.bin of TOOL-046 on 2026-10-26; the rebuilt image, .bin SHA-256 c9081054dfc72699d37a7be8dafe78a5bf257e25965011ed82bbe3483831f922, equal on all 306 DDR3 tables to Gowin's default build of the same sources, loaded four times from an air-cooled board. The desktop core was restored after every load and answered 0x54. That the earlier image's failures came from its placement is an inference from one rebuild; an A/B of the two images from the same cold start would test it. Revised 2026-10-26: the record first said nextpnr's Gowin flow reports no hold analysis; it does analyse hold with routed clock skew and reported no violation, but on fabric paths only, as TOOL-050 records. The image that failed, rebuilt from commit f3b3c87, came out bit for bit SHA-256 1d5617587da0a38e97b609d8f8a0185b7e08d1361fb0aa5e748e0e9564fed64d. The user noted that the clean cold loads followed the longest cool-down, over six hours unplugged."

- record_id: TOOL-050
  topic_id: TOOL
  title: "nextpnr does not time the DDR3 I/O cells' paths to the fabric"
  status: VERIFIED
  verified_date: 2026-10-26
  statement: "In aquasock/nextpnr branch epic/gw5ast138c, himbaechel/uarch/gowin/gowin_arch_gen.py create_timing_info adds cell timing variants for LUT4, MUX2_LUT5 to MUX2_LUT8, ALU, RAM16SDP4, the DFF types, block RAM and AE350_SOC, and none for IDES8_MEM, OSER8, OSER8_MEM or DQS. The final timing analysis (common/kernel/timing.cc timing_analysis) runs setup and hold with routed clock skew and logs hold violations when it finds any, but a path with an untimed cell at one end is not a register-to-register path to it, so the deserializers' outputs, DQS RVALID, the serializers' data, TX and command inputs and the DQS control inputs are checked for neither setup nor hold."
  consequence: "Every open-flow DDR3 image's I/O boundary is untimed, and whether it works can change with placement alone, which fits TOOL-049. fpga/ddr3_ctrl's generated top therefore registers every PCLK signal crossing that boundary on PCLK's falling edge, giving each crossing about half a PCLK of setup and of hold regardless of routing while keeping each consumer's latency; adding I/O-cell timing to the chipdb would let nextpnr check these paths directly. The write image's boundary is still untimed."
  sources:
    - "aquasock/nextpnr epic/gw5ast138c: himbaechel/uarch/gowin/gowin_arch_gen.py create_timing_info; common/kernel/timing.cc, timing_log.cc"
    - "TinyVCMI tools/ddr3_write.py: BOUNDARY, LANE_B, DQ_B"
    - "TinyVCMI docs/ddr3-open-flow.md: The I/O boundary is not timed, so it is retimed"
  verification: "Read from the fork's source. The retimed controller image built in the open flow at PCLK 101.21 MHz with no hold violation reported and compiled against Gowin's primitive models; it has not been run on the board, and its table check has not run, Gowin's default build of it having left 441 nets unrouted."

- record_id: PROV-001
  topic_id: PROV
  title: "Reference-project and license boundaries"
  status: SOURCED
  verified_date: 2026-10-22
  statement: "TinyNES and TinyGBC are MIT-licensed project code with separately attributed third-party components; TinyTang and its modified core family include GPL-3.0 work; Tang-PSX contains its own code plus BSD-2-Clause LiteX integration and vendor-generated Gowin IP that is not committed; VCMI is GPL-2.0-or-later and its project assets are CC-BY-SA-4.0."
  consequence: "Take interfaces, measurements and design lessons freely within their license terms, but do not copy a module merely because it is in a sibling repository. Preserve notices for any reused code, keep generated Gowin IP out of the repository, and document every imported component in THIRD_PARTY.md when implementation begins."
  sources:
    - "TinyNES commit 0a1ba9e, README.md: Licensing"
    - "TinyGBC commit 745f1ad, README.md: Licensing"
    - "Tang-PSX commit 61974ca, LICENSE and THIRD_PARTY.md"
    - "MiSTer-VCMI commit 76e1e1c, ATTRIBUTIONS.md"
  verification: "Repository license and attribution files were consulted. Exact file-level reuse has not begun, so the record remains SOURCED until a TinyVCMI THIRD_PARTY.md inventories actual imports."
```

---

## 6. Open reference gaps

These are missing facts, not an implementation plan.

```yaml
- gap_id: GAP-001
  question: "Which GW5AST DDR3 PHY primitives and configuration bits can the open packer emit correctly?"
  close_with: "Primitive-level vendor/open bitstream comparisons followed by isolated hardware tests."

- gap_id: GAP-002
  question: "What open DDR3 training algorithm and timing margins work across all four x8 byte lanes on this revision-C board?"
  close_with: "Cold-start calibration telemetry, repeated full-array tests, and temperature/voltage evidence where available."

- gap_id: GAP-003
  question: "What is TinyVCMI's actual bare-metal high-water memory use?"
  close_with: "Allocator instrumentation on progressively larger VCMI subsets after DDR3 is qualified."

- gap_id: GAP-004
  question: "Which VCMI threading and filesystem contracts must the AE350 runtime implement?"
  close_with: "A source-level dependency inventory pinned to VCMI-001."
```

---

## 7. Source priority for the first milestone

1. TinyVCMI `.ai/core.md` and this reference library.
2. Tang-PSX hardware-verified DDR3 records and diagnostics, used as behavioral evidence only.
3. TinyNES hardware-verified open-flow AE350, SDR SDRAM, video and loading paths.
4. TinyTang's current input and desktop protocol.
5. Gowin device documentation and primitive models, checked against open-tool behavior.
6. Sipeed board constraints and schematics.
7. MiSTer-VCMI and upstream VCMI for application behavior, dependencies and measured footprint.

---

## 8. Retired record IDs

None.

---

## 9. Record template

```yaml
- record_id: <TOPIC>-<NNN>
  topic_id: <TOPIC>
  title: "Short factual title"
  status: SOURCED
  verified_date: YYYY-MM-DD
  statement: "What the source establishes."
  consequence: "What that fact means for TinyVCMI."
  sources:
    - "Repository commit and path, or document and exact section"
  verification: "How the record was checked and what remains unverified."
```
