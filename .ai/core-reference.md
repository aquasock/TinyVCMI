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
TOOL-002: "Yosys declares all required PHY cells; the GW5AST backend places and routes static IODELAY, CLKDIV, the bottom-left DDRDLL with LOCK, the one measured DQS and lane 0's OSER8_MEM and IDES8_MEM; all three pack to the vendor's fuses, but only in-process because the DDR3-bank guard refuses any image with a bank 6/7 pad"
TOOL-003: "DDRDLL is a two-cell macro: ports in the column-1 tile, configuration fuses in the corner, LOCK on a dedicated row-99 escape now modelled as a fuse-free node; open flow covers the bottom-left master only"
TOOL-004: "DDRDLL STEP reads zero at 50 and 400 MHz in both the open-flow and the vendor-built image, under every static STOP/UPDNCNTL combination, so the zero is not this toolchain"
TOOL-005: "The hardware-proven vendor controller holds STOP at PLL lock, drives UPDNCNTL from its init FSM, uses DDRDLLM_BL with this project's four parameters, and feeds STEP to four DQS blocks with no path back into the DLL"
TOOL-006: "DQS, OSER8_MEM and IDES8_MEM form one lane complex: TCLK, ICLK, WADDR and RADDR take only their lane DQS's outputs, so the internal connections must be modelled, not measured as fabric wires"
TOOL-007: "The DQS control and status side is tile (81,5): 24 inputs and 13 outputs named, three outputs by route inference; FCLK is an HCLK-lane sink selected by table 58 at (72,0), and DQSIN arrives fuse-free from the pad tile"
TOOL-008: "Every DQS configuration fuse, parameters and FCLK lane, is in longfuses table 58 of the byte group's config tile, (72,0) for this lane"
TOOL-009: "Lane 0's OSER8_MEM and IDES8_MEM sit on IOLOGIC A/B of cells (68..79,0); their memory-mode pins are hard-wired and their configuration is named IOLOGIC attributes"
TOOL-010: "A complete DQ pad's IOLOGIC is the union of its serializers plus three IODELAY fuses; IO standard touches only IOB and the BANK table"
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
  verification: "The deterministic TinyVCMI preflight synthesized all six probes on 2026-10-22, reproduced the four no-BEL failures, and routed IODELAY and CLKDIV. A separate DDR-free open-flow image passed simulation, synthesis, placement, routing and packing, then was SRAM-loaded on the target and answered TinyTang core ID 0x56 at 2 Mbaud. Revised 2026-10-22 after the DDRDLL bel was added: the same preflight now reports DDRDLL PASS/PASS, with DQS, OSER8_MEM and IDES8_MEM unchanged, and the earlier citation of commit 8be8657b is corrected because the binary that produced the evidence self-reports 7d1b131c. DQS and the two memory serializers have not been implemented or tested. Revised 2026-10-23: the DQS site is tile (81,5), type 241, which carries no bels at all, and its control and status wires have since been measured by matched vendor pairs and are recorded in TOOL-007; the 54-pin IOLOGIC map statement above remains true of the chipdb. Revised 2026-10-23 after the DQS bel and dedicated links were added to the generator: the preflight's DQS probe was changed to the smallest lane the vendor accepts, a DDRDLL on DLLSTEP and DQSIN on pin Y3, and now reports DQS PASS beside DDRDLL, IODELAY and CLKDIV, with OSER8_MEM and IDES8_MEM still GAP. Revised again 2026-10-23: Apicula packs the DQS (get_DQS_fuses) and matches the vendor in table 58 when run in-process by tools/dqs_pack_check.py, but no image containing a DQS can be written while the packer's DDR3-bank guard refuses every bank 6/7 pad outside a declared DDR context, and that guard has no switch. Revised again 2026-10-23: the OSER8_MEM and IDES8_MEM probes are now lane-0 designs on Y3 and Y4 and pass, so the preflight reports all six primitives PASS."

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
  verification: "Eight offline vendor builds covered all four master placements and isolated CODESCAL, SCAL_EN, DIV_SEL and DLL_FORCE changes, and the BL deltas were re-derived from the raw bitstreams rather than the tile tables. Revised 2026-10-22: three further offline builds isolated the ports and LOCK (constants on STOP, UPDNCNTL and RESET; LOCK open; STEP open). The corner DLL0 tables agree with the TL, BL and BR baselines on features 12 to 15; TR's table has no entry for feature 12 or 13. The open-flow path reproduces the four measured feature sets and sets none of the three unset bits, which shows the packing is derived from the measurement; it does not show the primitive works. No Tang access occurred. Revised 2026-10-23: LOCK now has a pin on a fuse-free node to Q7 of cell (99,1), and the preflight's DDRDLL probe routes it through X1Y99/E820 <- Q7, the pip the vendor sets when LOCK is routed."

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
  verification: "Four builds of one parameterised design were loaded in turn, each answering over the link; the reply carries a free-running counter that advanced between queries, which separates a silent primitive from a silent link. CLKIN was confirmed to be the port tile's CLK0 wire from the vendor const-input build's GB10 to CLK0 pip. No pin was probed and no DDR3 package pin was driven or exposed. Revised 2026-10-22 after the vendor reference: the identical source built by Gowin EDA reports the same zero, which removes this project's packing from the list of causes, and Gowin's .bin was verified to be the .fs data lines packed eight bits to a byte, so both images load raw with no conversion. Revised again after the PLL run: at 350 MHz with lock asserted and the fast counter proven moving, STEP is still zero, so the clock-period explanation is disproved at that rate and only an untested claim about 400 MHz specifically would survive it."

- record_id: TOOL-005
  topic_id: TOOL
  title: "How the hardware-proven vendor DDR3 controller drives the DDRDLL"
  status: VERIFIED
  verified_date: 2026-10-23
  statement: "The vendor DDR3 IP netlist kept by Tang-PSX places its DDRDLL at DDRDLLM_BL and instantiates it as CLKIN=memory_clk, STOP=a buffer of pll_lock, RESET=dll_rsti, UPDNCNTL=uddcntln, with STEP driving DLLSTEP on all four DQS blocks and also being registered into the 100 MHz domain, with CODESCAL 111, SCAL_EN FALSE, DIV_SEL 0 and DLL_FORCE FALSE. UPDNCNTL is driven by the init state machine rather than held at a level, and STOP therefore reads 1 during normal operation because pll_lock is active high. The DQS blocks have no output back to the DLL."
  consequence: "This is the reference behaviour for an open-flow PHY: same master site, same four parameters this project packs, and a control sequence rather than static levels. Because the only coupling from DQS to the DLL is one way, an isolated DDRDLL with no PHY around it is not demonstrated to run by this design, which is consistent with this project's STEP readings and means a standalone lock-and-step diagnostic may not be physically meaningful."
  sources:
    - "Tang-PSX build/ddr3-vendor/ip/ddr3_memory_interface/ddr3_memory_interface.vo, DDRDLL instance gw3_top/u_ddr_phy_top/u_dll and the four DQS instances"
    - "Tang-PSX gateware/ddr3_vendor/tang_psx_ddr3.cst, INS_LOC u_dll DDRDLLM_BL"
    - "Tang-PSX gateware/gowin_ddr3.py, PLL_INIT feeding pll_lock"
    - "Tang-PSX third_party/litedram/litedram/phy/gw5ddrphy.py, GW5DDRPHYInit (BSD-2-Clause, upstream, not hardware-proven here)"
  verification: "Read directly from the vendored post-place-and-route netlist and the constraint file on 2026-10-23, cross-checked against TinyVCMI TOOL-002 for the site and TOOL-003 for the parameters. The LiteDRAM PHY's own DDR3 attempt in Tang-PSX never deployed because every placement variant failed setup timing, so its sequence is a design intent, not a hardware result."

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
  consequence: "A packer can write a DQS's whole configuration from this table without naming the table's keys: the presence fuses, the four parameters and the FCLK lane are fuse sets at the byte group's config tile, in the same shape as the DDRDLL's DLL0 features. Lane 0 sets nothing and therefore reads like an unclocked block. Two limits remain: the presence fuses were constant across every design tried, but every design used the same DQS ports, so their dependence on port usage is untested; and the encoding is measured at one byte group only, so the other 23 table-58 cells are not established to share its coordinates. The Apicula fork packs this encoding as get_DQS_fuses."
  sources:
    - "TinyVCMI tools/dqs_param_probe.py (designs, --report, --check) and tools/fs_attribute.py"
    - "TinyVCMI docs/ddr3-open-flow.md: DQS configuration: longfuses table 58"
    - "Gowin EDA 1.9.11.03 IDE/simlib/gw5a/prim_sim.v, module DQS parameter list"
    - "Apicula commit 1d43011, apycula/GW5AST-138C.msgpack.xz: tile type 64 longfuses unknown_58 and hclk_pips at (81,0); apycula/chipdb.py P1.T08d LEFTSIDE convention"
  verification: "Fifteen vendor builds on 2026-10-23 in build/dqs_b1: a base, nine single-parameter variants, a design without the DQS and four pinned-lane designs. tools/fs_attribute.py attributed each variant's full difference from the base with no unattributed fuse, and every change outside routing, global clock and HCLK fell in table 58 at (72,0). tools/dqs_param_probe.py --check asserts the exact table-58 fuse set of all fifteen builds, each lane design's BETA, BUF and ALPHA chain at (81,0), and zero unattributed fuses, and passed. The same attribution showed that the per-port constant bits recorded earlier at (81,5) are routing: the HOLD constant pair's eight bits are the B3 input mux choosing VCC through W240 or GND through X04. No hardware was accessed. Revised 2026-10-23: tools/dqs_pack_check.py ran the Apicula packer in-process on all twelve B1 designs built in the open flow; its table-58 fuses equal this encoding in every case and the vendor build outside the lane field, exactly where the lanes agree, and lanes 1 to 3 were checked through --fclk-lane because the open router always chose lane 0. No image was written, since the packer refuses any bank 6/7 pad outside a declared DDR context. Revised 2026-10-23: with the router keeping the DQS on its CLKDIV's lane, tools/dqs_pack_check.py matched the vendor's lanes 1, 2 and 3 with real routing, without --fclk-lane."

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
