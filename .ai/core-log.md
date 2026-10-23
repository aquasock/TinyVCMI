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
