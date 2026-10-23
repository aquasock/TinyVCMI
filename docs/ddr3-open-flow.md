# DDR3 open-flow bring-up

## Ground rule

TinyVCMI's final FPGA image is synthesized, placed, routed, and packed with
Yosys, nextpnr-himbaechel, and Apicula. Gowin EDA output is useful as an oracle
for locations, primitive parameters, routing, and configuration-bit
experiments, but encrypted RTL and post-route simulation netlists are not
linked into the open-flow image.

No script in this repository programs hardware. Loading an image is a separate,
explicitly approved step.

## Proven target

The revision-C Tang Console 138K carries two H5TQ4G63EFR-RDC x16 devices on a
shared command bus, forming a 1 GiB x32 DDR3 array. Tang-PSX qualified that
array with the Gowin controller at DDR3-800, a 1:4 PHY ratio, and a 256-bit
100 MHz user port. Those settings establish the behavioral target, not an
open-flow implementation.

Inspection of the qualified post-route reference gives this PHY inventory:

| Primitive | Count | Current open-flow boundary |
| --- | ---: | --- |
| `DDRDLL` | 1 | Yosys declaration only; no GW5AST placeable BEL/packer path |
| `DQS` | 4 | Yosys declaration only; no GW5AST placeable BEL/packer path |
| `OSER8_MEM` | 40 | Yosys declaration only; memory serializer packing is absent |
| `IDES8_MEM` | 32 | Yosys declaration only; memory deserializer packing is absent |
| `IODELAY` | 32 | Static-delay support exists; dynamic calibration is not qualified |
| `CLKDIV` | 1 | GW5AST placement, routing, and packing support exists |

The `OSER8_MEM` total is 32 DQ serializers, four DQS serializers, and four DM
serializers. The exact support report can be reproduced with
`tools/ddr3_openflow_preflight.sh`.

## DDRDLL reverse-engineering checkpoint

`tools/run_ddrdll_oracle.sh` builds a measurement-only Gowin EDA oracle for a
single `DDRDLL` constrained to `DDRDLLM_BL`. It does not program hardware and
its output is not an open-flow deliverable. The checked-in case uses the
parameters from the qualified Tang-PSX controller:

- `DLL_FORCE="FALSE"`
- `CODESCAL="111"`
- `SCAL_EN="FALSE"`
- `DIV_SEL=0`

Gowin EDA 1.9.11.03 reports four master resources and accepts the symbolic
locations `DDRDLLM_TL`, `DDRDLLM_TR`, `DDRDLLM_BL`, and `DDRDLLM_BR`. A sweep
of all four locations and one parameter at a time completed successfully.
The GW5AST-138C `.fse` configuration tables and the vendor bitstream deltas
localize the four master configuration cells as follows:

| Vendor location | Configuration cell | Tile type |
| --- | ---: | ---: |
| `DDRDLLM_TL` | `(0, 0)` | 50 |
| `DDRDLLM_TR` | `(0, 181)` | 51 |
| `DDRDLLM_BL` | `(108, 0)` | 48 |
| `DDRDLLM_BR` | `(108, 181)` | 49 |

For the BL site, changing only `CODESCAL` from `111` to `000` clears tile bits
`(20,17)`, `(20,19)`, and `(20,20)`. Changing only `SCAL_EN` to `TRUE` sets
`(20,18)`; changing only `DIV_SEL` to one sets `(21,14)`; and changing only
`DLL_FORCE` to `TRUE` sets `(20,16)`. These bits correspond to numbered
features 12, 13, 14, and 15 in the existing `DLL0` short-value table.

The vendor `.dat` also contains the BL fabric-port records. The master inputs
are at one-based cell `(109,2)` on wires `CLK0`, `A6`, `LSR0`, and `A5`, in
`CLKIN`, `STOP`, `RESET`, and `UPDNCNTL` order. Its first eight outputs are
`Q0` through `Q7`, in `STEP[0]` through `STEP[7]` order; `LOCK` is the remote
tap `(100,2,Q7)`. The historical hard-coded DDRDLL offsets in Apicula's
`Datfile.read_5Astuff()` do not point at these records in the installed
GW5AST-138C database, so the next implementation must locate or encode the
measured tables rather than consuming the current misparsed values.

No Apicula or nextpnr source was changed in this checkpoint. The next agent
should add the DDRDLL sites and aliases to the chip database, expose the BEL
and four placement macros in the Himbaechel architecture, encode the measured
`DLL0` features in the packer, rebuild the database and nextpnr, and then run
the checked-in oracle shape through the open flow. Hardware remains deferred;
coordinate with the user before querying, resetting, or programming the Tang.

## Milestones

1. Keep a passing non-DDR open-flow smoke build and executable primitive
   preflight as controls.
2. Reverse engineer and implement `DDRDLL` placement, routing, parameters, and
   packing. First hardware diagnostic: lock and step stability only, with all
   DDR pins undriven.
3. Implement one complete x8 lane: `DQS`, `OSER8_MEM`, `IDES8_MEM`, and the
   required dynamic delay behavior. Calibrate and margin the lane.
4. Expand to four x8 lanes and add the minimum JEDEC initialization, refresh,
   read, and write controller. Test deterministic patterns over progressively
   larger address ranges before exposing a system bus.
5. Connect the AE350's 64-bit RAM AHB path at `0x40000000`, then measure cache
   miss latency and sustained bandwidth.
6. Add 800x600 video arbitration and TinyTang-compatible Logitech keyboard and
   mouse events.
7. Bring up the VCMI 1.7.5 runtime and instrument its actual memory use.

Each hardware milestone needs a diagnostic that distinguishes clock/DLL,
write-leveling, read capture, lane ordering, addressing, refresh, and
arbitration failures. A full controller is not treated as the first test.

## Why SDR SDRAM is not the capacity target

The existing open-flow design has qualified only one 32 MiB SDR SDRAM device.
Enabling the second physical device could provide 64 MiB and remains useful for
early firmware, but the completed MiSTer port observed roughly 100 to 115 MiB
resident use. TinyVCMI therefore treats the 1 GiB DDR3 array as the main-memory
path while retaining SDR SDRAM as a possible boot, staging, or diagnostic
resource.
