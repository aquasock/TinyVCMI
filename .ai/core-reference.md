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
TOOL-002: "Yosys declares all required PHY cells; the GW5AST backend supports static IODELAY, CLKDIV and the bottom-left DDRDLL master, and still lacks BELs for DQS, OSER8_MEM and IDES8_MEM"
TOOL-003: "DDRDLL is a two-cell macro: ports in the column-1 tile, configuration fuses in the corner, LOCK on a dedicated row-99 escape; open flow covers the bottom-left master only"
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
  verified_date: 2026-10-22
  statement: "Yosys 0.52 declares DDRDLL, DQS, OSER8_MEM, IDES8_MEM, IODELAY and CLKDIV for GW5A synthesis. With the aquasock/nextpnr epic/gw5ast138c tree and Apicula commit 8918f14, isolated GW5AST-138C probes place and route static IODELAY, CLKDIV and the bottom-left DDRDLL master, while DQS, OSER8_MEM and IDES8_MEM still fail because the device database exposes no BEL able to implement those cell types. The qualified vendor reference contains one DDRDLL, four DQS, 40 OSER8_MEM, 32 IDES8_MEM, 32 IODELAY and one CLKDIV."
  consequence: "The remaining primitive boundary is DQS and the two memory serializers, whose support follows at one x8 lane before expanding to x32. DDRDLL placement and parameter packing exist for one site only, and the primitive's LOCK output has no modelled fabric path, so no lock-and-step evidence exists yet. Static IODELAY support does not establish dynamic calibration support."
  sources:
    - "Yosys 0.52, share/yosys/gowin/cells_xtra_gw5a.v"
    - "aquasock/nextpnr branch epic/gw5ast138c; binary nextpnr-0.11.1-65-g7d1b131c produced the 2026-10-22 evidence, and 8be8657b is the commit at the tip of that tree (not the binary's own describe)"
    - "Apicula commit 8918f14, apycula/GW5AST-138C.msgpack.xz and apycula/gowin_pack.py"
    - "TinyVCMI docs/ddr3-open-flow.md: DDRDLL reverse-engineering and open-flow implementation"
    - "Tang-PSX Gowin EDA 1.9.11.03 post-PnR simulation model, ddr3_memory_interface.vo"
    - "TinyVCMI tools/ddr3_openflow_preflight.sh and fpga/ddr3_phy_probe/ddr3_phy_probe.sv"
  verification: "The deterministic TinyVCMI preflight synthesized all six probes on 2026-10-22, reproduced the four no-BEL failures, and routed IODELAY and CLKDIV. A separate DDR-free open-flow image passed simulation, synthesis, placement, routing and packing, then was SRAM-loaded on the target and answered TinyTang core ID 0x56 at 2 Mbaud. Revised 2026-10-22 after the DDRDLL bel was added: the same preflight now reports DDRDLL PASS/PASS, with DQS, OSER8_MEM and IDES8_MEM unchanged, and the earlier citation of commit 8be8657b is corrected because the binary that produced the evidence self-reports 7d1b131c. DQS and the two memory serializers have not been implemented or tested."

- record_id: TOOL-003
  topic_id: TOOL
  title: "Measured GW5AST-138C DDRDLL master sites, cells, features and ports"
  status: VERIFIED
  verified_date: 2026-10-22
  statement: "Gowin EDA 1.9.11.03 exposes four DDRDLL master placement macros, DDRDLLM_TL, DDRDLLM_TR, DDRDLLM_BL and DDRDLLM_BR. Vendor bitstreams localize their configuration to cells (0,0), (0,181), (108,0) and (108,181). The primitive is a two-cell macro: at the bottom-left master the port wires land in the column-1 tile, the vendor's one-based cell (109,2), while every configuration fuse sits in the corner cell (108,0). At that site CODESCAL 111 selects DLL0 feature 12 and 000 selects none, SCAL_EN TRUE feature 13, DIV_SEL 1 feature 14 and DLL_FORCE TRUE feature 15. The port map is CLKIN to CLK0, STOP to A6, RESET to LSR0, UPDNCNTL to A5 and STEP[0:7] to Q0 through Q7. LOCK reaches no configurable wire: with LOCK open the bitstream changes only on the row-99 track of column 1, wire Q7 driving E820, which is the recorded tap (100,2,Q7). The vendor baseline also sets DLL0 features 5, 17, 18 and 19 plus corner bits (1,12) and (9,13), none of which any parameter sweep moved."
  consequence: "Open-flow support can be built and has been built from this evidence for the bottom-left master: a bel on the port tile, a symbolic DDRDLLM_BL macro, and packing that writes the measured DLL0 features in the configuration cell, with LOCK deliberately unmapped so a design that uses it fails placement instead of routing a dead net. Three things stay open and are not claims about the silicon: the other three masters' port tiles are unmeasured, LOCK's escape has no modelled fabric path, and the six default corner bits are unexplained. No DDRDLL image has been built for or tested on hardware."
  sources:
    - "TinyVCMI tools/ddrdll_oracle and tools/run_ddrdll_oracle.sh"
    - "TinyVCMI docs/ddr3-open-flow.md: DDRDLL reverse-engineering and open-flow implementation"
    - "Gowin EDA 1.9.11.03 GW5AST-138C.fse and GW5AST-138C.dat"
    - "Apicula commit 8918f14, apycula/attrids.py, apycula/chipdb.py and apycula/dat_parser.py"
    - "aquasock/nextpnr branch epic/gw5ast138c, himbaechel/uarch/gowin/{gowin_arch_gen.py,cst.cc,constids.inc}"
    - "aquasock/apicula branch epic/gw5ast138c, apycula/gowin_pack.py get_DDRDLL_fuses"
  verification: "Eight offline vendor builds covered all four master placements and isolated CODESCAL, SCAL_EN, DIV_SEL and DLL_FORCE changes, and the BL deltas were re-derived from the raw bitstreams rather than the tile tables. Revised 2026-10-22: three further offline builds isolated the ports and LOCK (constants on STOP, UPDNCNTL and RESET; LOCK open; STEP open). The corner DLL0 tables agree with the TL, BL and BR baselines on features 12 to 15; TR's table has no entry for feature 12 or 13. The open-flow path reproduces the four measured feature sets and sets none of the three unset bits, which shows the packing is derived from the measurement; it does not show the primitive works. No Tang access occurred."

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
