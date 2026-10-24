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

## DDRDLL reverse-engineering and open-flow implementation

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

### The primitive is a two-cell macro

The configuration cell above is not where the primitive's ports are. They land
in the column-1 tile of the same edge row, which is the vendor's one-based cell
`(109,2)` for the bottom-left master:

- `CLKIN` -> `CLK0`, `STOP` -> `A6`, `RESET` -> `LSR0`, `UPDNCNTL` -> `A5`
- `STEP[0]` .. `STEP[7]` -> `Q0` .. `Q7`

This is measured, not read off a name. Tying `STOP`, `UPDNCNTL` and `RESET` to
constants and diffing the bitstream against the reference removes exactly the
pips into `A6`, `A5` and `LSR0` of that tile and moves nothing in the corner.

`LOCK` is not a configurable connection at all. With `.LOCK()` left open, the
only bits that change are the row-99 track of column 1 (`Q7 -> E820`) and the
sink IO; no bit in the corner or port tile moves. `LOCK` therefore leaves the
primitive on a dedicated path to the row-99 long track, which matches the
recorded tap `(100,2,Q7)`. A bel's pins must be wires of the bel's own tile, so
the current chip database cannot express that pin, and it is not invented.

### Parameter fuses, re-verified bit by bit

For the BL site, changing only `CODESCAL` from `111` to `000` clears tile bits
`(20,17)`, `(20,19)`, and `(20,20)`. Changing only `SCAL_EN` to `TRUE` sets
`(20,18)`; changing only `DIV_SEL` to one sets `(21,14)`; and changing only
`DLL_FORCE` to `TRUE` sets `(20,16)`. These bits correspond to numbered
features 12, 13, 14, and 15 in the existing `DLL0` short-value table.

A re-check of all eight sweep bitstreams confirms those deltas exactly and
corrects one earlier reading: `(21,9)` is set in every build, including
`CODESCAL=000`, so it is not a `CODESCAL` bit and `DLL0` feature 5 is not the
`000` code; `000` emits no fuses at all. The vendor baseline also sets `DLL0`
features 5, 17, 18 and 19 (`(21,7)`, `(21,8)`, `(21,9)`, `(21,15)`) plus
`(1,12)` and `(9,13)`, and no parameter sweep moved any of them. What those six
bits configure is unmeasured, and the open-flow bitstream does not set them.

### Per-corner table coverage

The `DLL0` tables agree with the TL, BL and BR vendor baselines on features 12
to 15. TR's table has no entry for feature 12 or 13, so the `CODESCAL=111`
encoding cannot be emitted at TR from this database at all.

### Open-flow status

- Apicula's `get_DDRDLL_fuses` maps the four parameters onto the measured
  `DLL0` features at the configuration cell. It refuses any site other than the
  measured bottom-left master, refuses `CODESCAL` values other than `111` and
  `000` because their bit weights are unproven, and refuses a feature whose
  table entry is absent at that site.
- The Himbaechel Gowin arch creates one `DDRDLL` bel at the port tile with the
  four control pins and eight `STEP` pins, and `INS_LOC "<cell>" DDRDLLM_BL`
  resolves to it through the chipdb's macro table. `LOCK` was at first left
  without a pin, so that a design using it failed placement instead of
  routing a net that reached nothing; it now has one, described under
  "Open-flow DQS and dedicated links" below.
- `tools/ddr3_openflow_preflight.sh` reports `DDRDLL PASS/PASS`, and packing
  the routed probe writes the measured `CODESCAL=111` bits at the configuration
  cell and none of the three unset parameter bits.
- Nothing above was run on hardware. Whether the six unexplained baseline bits
  are required for the primitive to operate is an open question for the first
  lock-and-step image, not something the offline toolchain can settle.

### Hardware: the open-flow DDRDLL reports no tap code

One image carrying a single `DDRDLL` at the measured bottom-left site, a
2 Mbaud TinyTang responder and a free-running counter was loaded into SRAM on
2026-10-22. There was no scope on the bench, so the readout travels over the
TinyTang link instead of pins: the core answers the core-ID request that
`fpga` uses, and a query request that returns `STEP` with the counter. A reply
whose counter advances proves the clock, fabric and link are alive, which is
what makes a zero `STEP` a measurement rather than a dead link.

`STEP` read `0x00` in every case:

- `STOP` low with `UPDNCNTL` low, the configuration Gowin's model calls "run".
- `STOP` low with `UPDNCNTL` high.
- `STOP` high with either `UPDNCNTL` level.
- `STOP` low, `UPDNCNTL` low, with the six vendor-default corner bits packed
  through `APICULA_DDRDLL_VENDOR_DEFAULTS=1`.

Gowin's model (`IDE/simlib/gw5a/prim_sim.v`) predicts 200 = `0xC8` for a 50 MHz
`CLKIN` with `SCAL_EN="FALSE"`, so the silicon is not following the model in
this context. What that means is genuinely unresolved: either the tap value
only moves with the DDR clock and protocol context the primitive is meant to
serve, or configuration outside everything the vendor parameter sweeps exposed
is required. Neither the control levels nor the six default bits explain it.

### Vendor reference: the same zero

The same RTL was then built by Gowin EDA 1.9.11.03 and loaded from
`build/vendor_liveness` (4,330,802 bytes, sha256 `3a5ac691...`). The core
answers `core 86`, so the vendor image runs the same responder, and its
`STEP` also reads `0x00` while its counter advances:

- `00 00 0b`, `00 cc 78`, `00 4e 22` — step zero, counter moving.

That settles what the open-flow image could not: the zero is not a property of
this project's placement, port mapping or packed fuses. The vendor's own
bitstream, built from the same source, behaves identically at 50 MHz.

It also corrects a note made while planning this test. Gowin's `.bin` is not a
preamble plus a payload: it is exactly the `.fs` data lines packed
eight bits to a byte, verified byte for byte here, and those leading `ff` and
`de` bytes are part of the bitstream that a programmer sends. TinyTang writes
both images raw, so the vendor image needs no conversion at all.

### What the working vendor controller does

Tang-PSX keeps the vendor DDR3 IP's post-PnR netlist at
`build/ddr3-vendor/ip/ddr3_memory_interface/ddr3_memory_interface.vo`, and it
settles how the primitive is meant to be driven:

```verilog
DDRDLL gw3_top/u_ddr_phy_top/u_dll (
    .CLKIN(memory_clk), .STOP(n2457_6), .RESET(dll_rsti),
    .UPDNCNTL(uddcntln), .LOCK(dll_lock), .STEP(dll_step[7:0])
);
// CODESCAL="111" SCAL_EN="FALSE" DIV_SEL=1'b0 DLL_FORCE="FALSE"
```

- The site is `DDRDLLM_BL` (`tang_psx_ddr3.cst`), the master this project
  models, and the four parameters are the ones this project packs.
- `STOP` is a buffer of `pll_lock`, the PLL's active-high lock output, so it
  reads 1 during normal operation.
- `UPDNCNTL` is FSM-driven (`uddcntln`), never a static level.
- `STEP` drives `DLLSTEP` on all four `DQS` blocks and is registered into the
  100 MHz domain, which is the same cross-domain capture this project's readout
  uses.
- `DQS` has no output back to the DLL: the coupling is one way.

The vendored LiteDRAM GW5 PHY (BSD-2-Clause, upstream, never deployed here)
shows the intended order: wait for `LOCK`, freeze, cycle the ECLK domain,
release, then pulse the update.

Tang-PSX's own open-flow DDR3 attempt is also worth knowing about: the ABI 1.9
LiteDRAM PHY failed setup timing in every placement variant and was never
deployed. The only hardware-proven DDR3 in the project family is the vendor IP,
so this milestone has no precedent to copy.

### The primitive at 350 MHz

The last hypothesis worth testing offline was the clock period, so the probe
was rebuilt with an on-die PLL: 50 MHz in, 700 MHz VCO, `CLKOUT0` / 2, for a
350 MHz `CLKIN`. 400 MHz, the DDR3-800 memory clock, was the target, but the
router closes this design at 371 MHz -- the path from the primitive's own pins
dominates and does not improve when the fast-domain counter shrinks -- so the
constraint was set to 350 MHz and met rather than shipping an 8 percent miss.

The reply now also carries PLL lock and a counter in the fast domain, so a
silent primitive cannot be confused with a dead clock. Three reads:

- `aa 00 04 06 00 01 17 8e 93 e2`
- `aa 00 04 06 00 01 75 d4 25 cf`
- `aa 00 04 06 00 01 e3 8c 27 da`

`step = 0x00`, `lock = 1`, and both counters advance. The PLL locks, the
350 MHz domain runs, and the primitive still reports no tap code -- so the
clock-period explanation does not hold at seven times the original clock, in
the vendor's toolchain or in this one.

### 400 MHz with the vendor's control levels

The 350 MHz run still held `STOP` low. Reading the vendor netlist above showed
what a working design does, so the probe was rebuilt with `STOP` and `UPDNCNTL`
both high, and at the true DDR3 memory clock: 50 MHz x16 / 2, 800 MHz VCO,
`CLKOUT0` / 2 = 400 MHz. With `STOP` high the same design closed at 467 MHz, so
400 MHz met timing where the earlier build had stopped at 371.

Three reads at 400 MHz, `STOP=1`, `UPDNCNTL=1`:

- `aa 00 04 06 00 01 cd 01 51 0e`
- `aa 00 04 06 00 01 2d 9b 51 d9`
- `aa 00 04 06 00 01 83 d3 01 9c`

`step = 0x00`, `lock = 1`, both counters advancing. So `STEP` stays zero at the
exact clock and control levels of a working design, with the PLL locked, in
this project's toolchain.

### One DQS lane beside the DLL

The last cheap structural test was whether the primitive needs a `DQS` block
beside it. A vendor build (Gowin EDA 1.9.11.03) carried the same probe, still
at 400 MHz with `STOP` and `UPDNCNTL` high, plus one `DQS` with the proven
controller's parameters (`DQS_MODE="X4"`, `HWL="true"`, `FIFO_MODE_SEL=0`) and
its `DLLSTEP` fed from the DLL. Its outputs are folded into a seventh reply
byte so synthesis cannot trim the block for being unobserved.

`DQSIN` needs a pad buffer, and every DQS-capable pad on this board belongs to
the DDR3 array, so the input was left unconstrained: the vendor tool placed it
on `K21`, which is not in the DDR3 pin list (`K1` and `M6` are, as controls).
No DDR3 package pin was exposed or driven.

Three reads of `aa 00 04 07 00 01 81 6a 82 e9 02`, `... 03 f3 10 a5 02`,
`... 1f 69 d4 df 02`: `step = 0x00`, `lock = 1`, both counters advancing, and
the lane byte steady at `0x02`, so the DQS block answers. A DQS beside the DLL
changes nothing.

### UPDNCNTL as a pulse

The last stated difference was the one control the working controller never
holds: both the proven init machine and the vendored LiteDRAM PHY pulse
`UPDNCNTL` low rather than leaving it at a level. A build at 400 MHz with
`STOP=1` and `UPDNCNTL` low for 16 fast cycles every 65536 (about 40 ns every
164 us, met at 414.94 MHz) returned the same three readings:

- `aa 00 04 06 00 01 cb 26 4a 36`
- `aa 00 04 06 00 01 bc 30 d2 85`
- `aa 00 04 06 00 01 ac f0 52 85`

`step = 0x00`, `lock = 1`, both counters advancing.

### The STEP question is closed

`STEP` has been read six ways: 50 MHz and 400 MHz, `STOP` low and high,
`UPDNCNTL` low, high and pulsed, with the six vendor-default corner bits
packed, with a `DQS` lane beside it, and through the vendor toolchain. It has
never been anything but zero. Whatever produces a tap code inside the
hardware-proven controller, this project cannot reach it from an isolated
island, and `STEP` is not a usable signal for the first milestone.

That is a negative result, not a dead end: the site, the parameters, the
placement, the routing, the packing and the readout path are all proven to work
by the same images. What is missing is the PHY around the primitive, which is
milestone 3's subject anyway.

 `STEP` has now been read at
50 MHz and 400 MHz, with `STOP` and `UPDNCNTL` in all four static
combinations, with the six vendor-default corner bits packed, and under the
vendor toolchain -- always zero. The one structural difference left between
this probe and the working controller is the PHY around the primitive: the
memory clock as the DDR PHY distributes it, the four DQS blocks, and the init
FSM. `DQS` has no path back into the DLL, so the most likely reading is that
the primitive is not usable as a standalone island, which would also mean
`LOCK` cannot be observed in isolation. That is a hypothesis, not a
measurement, and it has a direct consequence for "Milestones" below.

So Gowin's behavioural model does not describe the silicon at a 20 ns clock
period. The physical reading is that a DDR3-800 delay loop is built to lock
against a 2.5 ns clock and has nothing to report at 20 ns, but that is a
hypothesis, not a measurement: no test has yet clocked the primitive at the
rate it is meant to serve.

Two facts were established along the way and are worth keeping. `RESET` is
active high, from the same model's `reset_sig = RESET | ~GSRO`. And `CLKIN` is
the `CLK0` wire of the port tile: the vendor const-input build routes
`GB10 -> CLK0` in tile `(108,1)`, next to the `A6`, `A5` and `LSR0` pips that
were measured directly.

`LOCK` remains unmodelled, so a lock-based check is not available either. The
probe answers on the link and can be re-run at any time:
`tools/build_ddrdll_liveness.sh` builds it, `tools/tang_console.py` uploads it,
loads it and reads the reply.

The earlier note that Apicula's hard-coded DDRDLL tables are unusable on this
database no longer applies: the fork's `DLL0` tables are already per-tile-type
correct for three of the four corners, and the measured evidence above was read
out of them rather than the old offsets.

## What a lane build can and cannot tell us

A complete vendor lane (`DDRDLL` -> `DQS.DLLSTEP`, `DQS.DQSW0` ->
`OSER8_MEM.TCLK`) now builds, which is the first time all three primitives have
been placed together in this project. The tool put the lane's `DQSIN` on
`Y3`, and this board's DDR3 constraint file names `Y3` as `ddr_dqs[0]`: a real
lane binds DDR3 pads, because the `DQS` block for a byte lane lives with that
lane's pins. That is why the preflight probes can never place these three
primitives -- they are forbidden the very pins the blocks exist at.

Diffing the lane bitstream against a control was the planned way to recover the
`DQS` pin names, and it does not work as hoped, for two separate reasons:

1. The pair has to be *matched*. A control with different ports and different
   IO placement changes hundreds of bits in the IO tiles, and the 424-bit diff
   spread over 43 tiles is mostly that noise. The pad's own tile, `(68,0)`,
   moved only five bits.
2. More fundamentally, a diff only shows what the router *routed*. In this
   design the `DQS` inputs are tied to constants, and a constant does not
   become a pip: it is selected by the site's own configuration. So the 21
   names that are missing -- `DQSIN`, `READ`, `RCLKSEL`, `RLOADN`, `RMOVE`,
   `RDIR`, `WLOADN`, `WMOVE`, `WDIR`, `HOLD` and the status outputs -- would
   not all appear even with a perfectly matched pair.

The method that can work is the one that produced the `DDRDLL` feature table:
vary one port at a time between `VCC` and `GND` in matched builds and read the
site's configuration bits, rather than looking for routing. That is one build
pair per port, which is why it should be done deliberately rather than started
in passing.

## Probing the DQS site one port at a time

`tools/dqs_port_probe.py` is the working version of the method: for each `DQS`
control input it builds a matched pair that differs only in that port's
constant, `VCC` against `GND`, with the pins fixed so placement cannot move.
Two pairs are enough to place the site.

The first attempt returned identical bitstreams for both constants, and the
fault was in the tool, not the silicon: the template substituted every control
port before substituting the target, so both builds tied the same port to
`1'b0`. Fixed, the pairs differ and the diffs are small and local.

The site is **tile `(81, 5)`, tile type 241**:

- `HOLD`: 8 bits, all inside that tile.
- `RESET`: 74 bits over three tiles, 66 of them in `(81, 5)` and the rest in
  its neighbours, which fits a reset that also gates nearby logic.

Type 241 carries no modelled bels in the chipdb, which is the other half of why
`nextpnr` cannot place a `DQS`: there is no site there to hold it. The probe
gives the site and, port by port, the configuration bits that select each
constant.

### Per-port bit sets at the DQS site

All eight single-bit control inputs were probed. Each pair moves exactly eight
bits inside tile `(81,5)`, except `RESET`, which moves 66 there plus a few in
two neighbouring tiles:

- `HOLD`: `(4,0) (4,2) (4,7) (4,74) (4,75) (5,6) (5,80) (5,83)`
- `RLOADN`: `(6,97) (6,99) (7,95) (7,96) (8,2) (8,5) (8,6) (8,9)`
- `RMOVE`: `(8,21) (8,24) (8,80) (9,27) (9,29) (9,74) (9,75) (9,76)`
- `RDIR`: `(6,97) (6,99) (7,95) (7,96) (8,10) (9,2) (9,5) (9,10)`
- `WLOADN`: `(4,22) (4,31) (5,24) (5,28) (6,106) (6,107) (6,111) (7,108)`
- `WMOVE`: `(4,74) (4,75) (5,0) (5,2) (5,7) (5,9) (5,80) (5,83)`
- `WDIR`: `(4,24) (4,28) (4,30) (5,22) (6,106) (6,107) (6,111) (7,108)`

The union is 102 bits, and the site's `alonenode` table explains what they are:
24 entries claim them, and the pattern is a constant-select mux. For example
wire `CE2` has the source list `LB31, VCC, W212, X06` with bit `(3,73)`, and
`WMOVE`/`WDIR` move bits inside exactly that group. That is the mechanism: each
control input's constant level is chosen by a multiplexer whose select bits are
these eight, and the destination wire of the mux is the port's wire.

Three of the pairs share bit groups, which is a caution rather than a shortcut:
`RLOADN` and `RDIR` overlap on `(6,97) (6,99) (7,95) (7,96)`, and `WLOADN` and
`WDIR` match exactly on all eight. Whether that means shared mux select lines or
a common reset path through both, only the per-port mux entries can say, so the
table has to be built entry by entry rather than by grouping.

### What the site model has, and what it needs

Type 241 is close to unmodelled. It carries one short-value table named
`unknown_17`, no `longfuses`, no `longval` and no `const` bits at all, so the
102 measured bits have no existing table to be named against. The
`alonenode` entries do not explain them either: none of the eight ports'
bit sets matches an entry exactly, and none of the entries that overlap a port
even lists `VCC` or `GND` among its sources. The earlier read of `CE2` as a
constant-select mux was an intersection, not a match.

That splits the remaining work in two, and the split matters:

- **Configuration bits.** The per-port bit sets are measured and are enough on
  their own. They are what a packer needs, in the same shape as the `DDRDLL`'s
  `DLL0` features, and they need no wire names.
- **Routed pins.** `DQSIN`, `PCLK`, `FCLK`, `DLLSTEP` and the status outputs are
  real fabric connections, and those do need wire names. They are the ones the
  site model lacks, and they have to come from the routing side, not from the
  constant side.

So the lane bel set is buildable in two layers: the pins that route, named by
measurement, and the configuration bits, already measured. What is missing is
only the routed-pin names, and the probe framework now in `tools` is what
produces them.

**Correction.** The two subsections above are superseded. Decoded by exact mux
state with `tools/fs_attribute.py`, every one of the 102 bits is routing: the
`HOLD` pair's eight bits are the `B3` input mux choosing `VCC` through `W240`
against `GND` through `X04`, and the `RESET` pair's 66 are every site input
re-choosing its constant source. They are not configuration, and tile `(81,5)`
holds no `DQS` configuration at all; that lives in longfuses table 58 of the
byte group's config tile, recorded under "DQS configuration" below.

## Internal paths

The chip database now has a first-class way to state a link the silicon
hard-wires. `create_internal_net()` in the nextpnr Gowin generator creates a
wire with **no pips** and attaches only the bel pins named at creation, so the
router can neither enter nor leave it: the connection is fixed, and there is
nothing for the packer to configure because no fuse exists for it. That is the
model for exactly the links the vendor tool refuses to let a design route --
`DQS` to `OSER8_MEM.TCLK`, and `DDRDLL` to `DQS.DLLSTEP`.

`himbaechel/uarch/gowin/tests/check_internal_net.py` gates the two invariants
that make it safe: the wire carries bel pins and no pip may ever touch it, and
a duplicate definition raises instead of quietly attaching more pins.

There is no consumer yet, deliberately. The lane bel set is what would use it,
and that needs the `DQS` fabric pins, which the previous sections show cannot
be recovered by isolating the primitive. The mechanism is therefore
infrastructure waiting on one measurement, not a partial lane.

The `DDRDLL` `LOCK` escape is a harder case of the same idea: its endpoint is
nine tiles away, so it needs a path that crosses tiles, not just one inside a
site. That is not covered by this mechanism and remains open.

## Placement boundary for the lane primitives

The three primitives a lane needs sit at IOLOGIC sites in the vendor's design.
The GW5AST-138C chipdb carries a 54-pin port map for those sites on tile types
229 to 232 and 243: enough for the data path, not enough for the memory-mode
control path. Against Gowin's own port lists:

- `OSER8_MEM`: 17 of 18 pins have a wire. Missing: `TCLK`.
- `IDES8_MEM`: 13 of 16. Missing: `ICLK`, `WADDR`, `RADDR`.
- `DQS`: 3 of 24. Missing `DQSIN` and every control and status pin -- `READ`,
  `RCLKSEL`, `DLLSTEP`, `WSTEP`, `RLOADN`, `RMOVE`, `RDIR`, `WLOADN`, `WMOVE`,
  `WDIR`, `HOLD`, `DQSR90`, `DQSW0`, `DQSW270`, `RPOINT`, `WPOINT`, `RVALID`,
  `RBURST`, `RFLAG`, `WFLAG`.

The present failure is therefore not "no BEL exists" in the abstract; the site
model does not name the wires these primitives use for control. Building BELs
from the 54-pin map would place and route and would invent 21 `DQS`
connections, which is the same defect as guessing at corner bits. The missing
names have to be measured the way the DDRDLL's were: one primitive constrained
to one site in a vendor build and diffed against a control bitstream.

### These are not three independent primitives

The plan to measure three wire names is wrong, and the vendor netlist says so.
`Gowin EDA` refuses to drive `OSER8_MEM.TCLK` from a pin -- `TCLK_SOURCE` is
`"DQSW"` or `"DQSW270"` -- and in the hardware-proven design every one of the
40 serializers takes its `TCLK` from its own lane's `DQS` output:
`dqsw0` for nine per lane and `dqsw270` for the tenth, 40 of 40 across the four
lanes.

So `TCLK`, `DLLSTEP` and the `DQSW*` group are not fabric wires to be named;
they are dedicated intra-lane connections between the `DQS` block and the
serializers beside it. Per lane the vendor instantiates one `DQS`, ten
`OSER8_MEM` and eight `IDES8_MEM`, and the four lanes hold the 40, 32 and 4
counts in the primitive inventory.

A second vendor attempt makes the same point from the other end. A lone `DQS`
cannot be built at all: Gowin answers `PR0015`, "DLLSTEP pin of 'u'(INS_DQS) is
not driven by DDRDLL". The tool itself enforces the dedicated
`DDRDLL` -> `DQS.DLLSTEP` and `DQS` -> `OSER8_MEM.TCLK` paths, which is why
neither connection exists as a named wire, and why a probe that isolates one
primitive can never be built.

That makes the unit of work the **lane complex**, not three BELs: the site
model has to carry internal connections between a `DQS` and its serializers,
the same way the `DDRDLL`'s `LOCK` needs a dedicated path rather than a named
wire. Adding BELs for the three types separately would place and route and
would model none of the connections that make them work.



## Milestones

1. Keep a passing non-DDR open-flow smoke build and executable primitive
   preflight as controls.
2. `DDRDLL` placement, routing, parameters and packing are done for the
   bottom-left master, and `STEP` is struck as a first-milestone signal: six
   configurations across two toolchains produced no tap code, so the primitive
   only means something inside its PHY. The `LOCK` escape still needs a model,
   and that work now lands with the lane rather than before it.
3. Measure the memory-mode site wires (`TCLK`, `ICLK`, `WADDR`, `RADDR` and the
   `DQS` control and status pins), then implement one complete x8 lane:
   `DQS`, `OSER8_MEM`, `IDES8_MEM`, the dynamic delay behaviour and `LOCK`.
   Calibrate and margin the lane. This is the first milestone where a hardware
   result would mean anything.
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

## DQS site pin measurement

The `DQS` control and status pins sit in tile `(81,5)`, tile type 241, which
has no bels, so every port's wire had to be measured rather than read off the
chipdb. The method is a matched pair built by the vendor tool, differing only
in the source of one port: `tools/dqs_port_probe.py` builds the input pairs
and `tools/dqs_output_probe.py` the output pairs, and `tools/dqs_map_check.py`
re-derives every entry below from those pairs and fails if any disagrees.

### Reading a mux

A destination's selected source is read by exact mux state: the fuses a
build programs inside that destination's mux must equal one source's fuse
set. The weaker test -- every fuse of a source is set -- lets several sources
of one destination read as selected at once, which is why an absolute decode
of one bitstream is not evidence and why an earlier count of 84 "programmed
pips" in the vendor DDR3 build meant nothing. Only a difference between two
builds names a pin.

Every mux's all-zero state is itself the selection of one source. In tile
`(81,5)` that is `Q1` for `W810`, `Q5` for `W830` and `N830`, and `Q0` for
`N800` and `EW10`. A route that leaves the site through a destination in that
state changes no fuse in the site tile at all, and the first changed hop is
somewhere downstream. That is what misled the first reading of the outputs.

The decoder was validated against a landmark before it was trusted: on the
`DDRDLL` port tile `(108,1)` it returns `A6` (STOP), `A5` (UPDNCNTL), `LSR0`
(RESET), `CLK0` (CLKIN) and the documented `Q7 -> E820` lock escape.

### Inputs

Measured on the GW5AST-138C with Gowin EDA 1.9.11.03, all in tile `(81,5)`.
In every pair exactly one site-input destination changes:

    RDIR    -> A0    WDIR   -> B0    RCLKSEL[0] -> C0    WSTEP[0] -> D3
    RLOADN  -> A1    WLOADN -> B1    RCLKSEL[1] -> C1    WSTEP[1] -> D4
    RMOVE   -> A2    WMOVE  -> B2    RCLKSEL[2] -> C2    WSTEP[2] -> D5
    READ[0] -> A3    HOLD   -> B3    PCLK       -> CLK0  WSTEP[3] -> D7
    READ[1] -> A4                    RESET      -> LSR0  WSTEP[4] -> CLK2
    READ[2] -> A5                                        WSTEP[5] -> LSR2
    READ[3] -> A7                                        WSTEP[6] -> CE1
                                                         WSTEP[7] -> CE2

`PCLK` and `RESET` come from the `clock` pairs, a fabric register against the
live board clock. A constant is not a legal source for either: tied down, the
vendor tool demotes the block and the pair differs across the whole tile (93
changed fuses for `PCLK`, 72 for `RESET`), and two live fabric registers
(`swap` mode) changed only upstream wire choices. The board clock does not
demote the block and selects a different source at the destination, which
names the pin.

Three inputs have no wire in this table. `DLLSTEP` has only one legal source,
a `DDRDLL`'s `STEP` (Gowin refuses anything else, `PR0015`), so it is an
internal net. `DQSIN` cannot be probed: driving it from fabric or from a second
DQS buffer is refused (`PR0014` "DQSIN pin of INS_DQS is not driven by
buffer", `CK3001` "one DQS buffer cannot drive two"). In the proven vendor
netlist `ELVDS_IOBUF.O` drives `DQS.DQSIN` directly; board pin `Y3` is
`IOL69A`, whose ordinary input wire is `F6` in tile `(68,0)`, so `DQSIN` is a
fuse-free connection from the pad side and must be modelled as one.

`FCLK` has no fabric pin; it is a sink of the high-speed clock network. Its
pairs move nothing in `(81,5)` except `PCLK`'s global-clock allocation, which
is why an earlier `FCLK -> CLK0` reading was withdrawn. Tile `(81,0)` is the
left side's HCLK fabric-entry tile -- the chipdb's `extra_func` gives it
`hclk_fabric_entry`, `clkdiv`, `clkdiv2` and `dhcen` -- and its `CLK1`, `CLK2`
and `LSR2` are not bel pins but the fabric entries `L2HCLK21`, `L2HCLK22` and
`L2HCLK23` of HCLK lanes 1 to 3. The router enters on whichever is free, which
is why one fabric source landed on `CLK1` under an earlier probe template and
on `CLK2` under the current one, and why the board clock arrived on `LSR2`
over local routing. The rebuilt pairs in `build/fclk_rebuild/` are
fuse-for-fuse identical to the earlier clock pair, so the vendor tool is
deterministic and that difference came from the template.

Decoded through the device-level `hclk_pips` table, every changed fuse in
`(81,0)` is one lane's chain: the register source enters lane 2,
`HCLK_MUX_BETA22 <- L2HCLK22`, `HCLK_BUF_BI22 <- HCLK_MUX_BETA22` and
`HCLK_MUX_ALPHA22 <- HCLK_BUF_BO22`, and the board clock enters lane 3 through
the same three muxes. The `DQS` chooses its lane in neither `(81,5)` nor
`(81,0)` but in longfuses table 58 of tile `(72,0)`, type 64, which the chipdb
places at 24 cells -- rows 9, 18, 36, 45, 63, 72, 90 and 99 of both long edges
and eight on the bottom edge -- so it reads as the per-byte-group
configuration table:

    lane    table 58 keys    fuses in (72,0)
    none    -                -
    2       38, 41           (20,108) (20,107)
    3       39, 42           (20,56) (20,108) (20,53) (20,107)

The keys form two identical two-bit fields, `(37, 38, 39)` over `(20,56)` and
`(20,108)` and `(40, 41, 42)` over `(20,53)` and `(20,107)`, each holding the
lane number in binary. Lanes 0 and 1 were then measured by pinning a `CLKDIV`
on the `FCLK` clock net to `LEFTSIDE[4]` and `LEFTSIDE[5]` (below): lane 1 is
keys 37 and 40, and lane 0 sets no fuse at all, which reads the same as an
unclocked block. This selector is separate from the ordinary IOLOGIC `FCLKSEL`
attributes, whose GW5AST-138C rows can select lanes 0 and 2 only, and the
vendor put the `DQS` on lane 3.

### Outputs

All thirteen status outputs leave the site in tile `(81,5)`:

    output     wire  first hop        how it was read
    DQSR90     Q0    N800             zero state; next hop (73,5) N800 <- N808
    DQSW270    Q1    W810             zero state; next hop (81,1) N210 <- W814
    RPOINT[1]  Q2    W810             selected
    WPOINT[1]  Q3    N800             selected
    RVALID     Q5    W830             zero state; next hop (81,1) N250 <- W834
    RFLAG      Q6    W830             selected
    WFLAG      Q7    EW10             selected
    DQSW0      F1    EW10             selected
    RPOINT[0]  F2    W810             selected
    WPOINT[0]  F3    N800             selected
    RPOINT[2]  F4    EW10             selected
    WPOINT[2]  F5    N830             selected
    RBURST     F6    N830             selected

Ten are measured directly: the target member selects the wire at the first
hop and nothing else in the site tile changes. The other three are route
inferences. Their pairs change no fuse in `(81,5)`, the first hop's mux is in
its zero state selecting the listed wire, and the route's next hop is the
same one that a measured sibling through the same destination takes --
`WPOINT[0]` and `WPOINT[1]` for `DQSR90`, `RPOINT[0]` and `RPOINT[1]` for
`DQSW270`, `RFLAG` for `RVALID`. The thirteen wires are distinct and leave
exactly `Q4`, `F0` and `F7` unused, which is consistent with the inference
but does not prove it.

This corrects the handoff of the previous cycle, which recorded `DQSR90` at
`(69,7)` and `DQSW270` and `RVALID` at `(81,1)`. Those are downstream hops:
`(69,7) W800 <- E202` appears identically in the `RBURST` and `WPOINT` pairs,
and `(81,1) N210 <- W814` in the `RPOINT[0]` and `RPOINT[1]` pairs. No output
tap lives outside the site tile.

### Shape of the macro

The control and status side of `DQS` is one tile, `(81,5)`: 24 input wires,
13 output wires, and no configuration. What makes
it a multi-tile macro is the clock and pad side, and none of the three is an
ordinary portmap entry. `FCLK` is an HCLK-lane sink whose select fuses live in
table 58 of the byte group's config tile `(72,0)`, so it needs pips from the
HCLK lanes carrying those fuses, as IOLOGIC `FCLK` already has. `DQSIN`
arrives fuse-free from the pad tile `(68,0)`. `DLLSTEP` is an internal net
from the `DDRDLL`. Those three are the remaining modelling work before the bel
can be written.

## DQS configuration: longfuses table 58

Every configuration fuse of the `DQS` is in longfuses table 58 of its byte
group's config tile, `(72,0)` for this lane. `tools/dqs_param_probe.py` builds
one design per parameter value against a common `base` (the proven
controller's `FIFO_MODE_SEL=0`, `RD_PNTR=000`, `DQS_MODE="X4"`, `HWL="true"`,
`FCLK` on the board clock), a design without the `DQS`, and four designs with
`FCLK` pinned to each HCLK lane; `tools/fs_attribute.py` accounts for every
changed fuse of each against `base` as routing, global clock, HCLK or a named
table entry. All fourteen differences have no unattributed fuse, and every
change outside routing is in table 58 at `(72,0)`. In tile coordinates:

    presence      (20,57) (20,58) (20,59) (20,62) (20,63) (20,68) (20,73) (20,91)
    FIFO_MODE_SEL 1 = (20,36) (20,67)
    RD_PNTR       bit 0 = (20,64), bit 1 = (20,49), bit 2 = (20,52)
    DQS_MODE      X1 = none, X2_DDR2 = (20,79), X2_DDR3 = (20,78),
                  X4 = (20,78) (20,79), X2_DDR3_EXT = (20,78) (20,90)
    HWL           true = (20,103)
    FCLK lane     0 = none, 1 = (20,53) (20,56), 2 = (20,107) (20,108),
                  3 = all four

The presence fuses are set in every design that has a `DQS` and in none
without one, across every parameter and lane tried. Every design uses the same
`DQS` ports, so whether any of the eight depends on which ports are connected
is not tested. The lane designs pin a `CLKDIV` with
`INS_LOC "fdiv" LEFTSIDE[4+n]` on the clock net that also drives `FCLK`, its
divided output on `PCLK`, which is the shape of a DDR3 PHY; `CLKDIV2` and
`DHCE` refuse that constraint with `CT2001`. Each lane design routes exactly
that lane's `BETA`, `BUF` and `ALPHA` chain at `(81,0)`.

`tools/dqs_param_probe.py --check` asserts this table on all fifteen builds,
the lane chains, and the absence of unattributed fuses.

The encoding is recorded for this one byte group. Table 58 exists at 24 cells
on the die, one per byte group, and its key numbering is shared by every tile
type that carries it, but whether the fuse coordinates are the same at the
other 23 has not been checked.

## Open-flow DQS and dedicated links

The nextpnr fork's chip-database generator now carries the lane pieces that
the measurements above support. This section describes the first, lane-0 form
(aquasock/nextpnr `epic/gw5ast138c`, `gowin_arch_gen.py`, gated by
`tests/check_dqs_site.py`); "Four lanes in the open flow" below extends it to
every byte group:

- One `DQS` bel at `X5Y81`, the site tile `(81,5)`, with the 24 input and 13
  output wires of the pin table above. Its chipdb tile type occurs eight times
  on the die, so the generator gives that one cell an extra-function entry of
  its own before any tile type is built; without it the deduplication would
  copy the bel onto seven unmeasured cells.
- `FCLK` as four pips from the block-2 HCLK lane wires `HCLK20` to `HCLK23`,
  each lane's node extended to the site. The Apicula database already drives
  each lane from its `HCLK_MUX_ALPHA2<n>`, so the router can take any lane and
  the packer has to write that lane into table 58.
- `DQSIN`, `DLLSTEP[0:7]` and the `DDRDLL`'s `LOCK` as dedicated links: each
  is one fuse-free node joining the source's own wire to a pin-only wire --
  `F6` at `(68,0)`, driven only by `IOBA.O` of pin Y3; `Q0` to `Q7` at
  `(108,1)`, the `STEP` pins; and `Q7` at `(99,1)`, where `LOCK` reaches the
  fabric. No pip enters any of them, so the router cannot put another net on
  them and the packer sees nothing to encode. This replaces the tap pips the
  plan proposed: joining the existing source wire needs no pip at all, and
  only the `DQS` cell's tile type had to change.

The preflight's `DQS` probe is now the smallest lane the vendor tool accepts --
a `DDRDLL` on `DLLSTEP` and `DQSIN` on pin Y3 through its own constraint file,
`fpga/ddr3_phy_probe/ddr3_phy_probe_dqs.cst` -- because the isolated shape it
used before is one the vendor refuses (`PR0014`, `PR0015`) and a faithful
model must refuse too. The `DDRDLL` probe now routes `LOCK` as well.
`tools/ddr3_openflow_preflight.sh` reports `DDRDLL`, `DQS`, `IODELAY` and
`CLKDIV` as PASS and `OSER8_MEM` and `IDES8_MEM` as GAP. In the routed `DQS`
probe the `DQS` sits on `X5Y81/DQS`, the pad on `X0Y68/IOBA` and the `DDRDLL`
on `X1Y108/DDRDLL_BL`, and the clock reaches `FCLK` over lane 0. The `LOCK`
net leaves through `X1Y99/E820 <- Q7`, which is the same pip the vendor
bitstream sets when `LOCK` is routed.

### Packing

Apicula's `get_DQS_fuses` (aquasock/apicula `epic/gw5ast138c`) writes the
table-58 encoding above at cell `X0Y72` and nowhere else. It takes the lane
from nextpnr's `HCLK2<n> -> DQS_FCLK` pip, which carries no fuse of its own
and is kept out of the chipdb pip lookup, and it refuses another site, an
unmeasured parameter value, and a connected `FCLK` that reached the site on no
lane.

`tools/dqs_pack_check.py` accepts it without writing an image. It runs
`gowin_pack`'s own routing stage on an open-flow routed netlist and then only
the `DQS` bel's fuse method, and compares the table-58 fuses with the recorded
encoding and with the vendor build of the same source. All twelve B1 designs
were built in the open flow and pass: the packer's fuses equal the recorded
encoding in every case, and equal the vendor's outside the lane field. They
equal the vendor's exactly when the two routers chose the same lane. The open
router put `FCLK` on lane 0 in every build, even when a `CLKDIV` pinned to
another lane held the same net. It carries the net on two lanes where the
vendor uses one, so the lane-1 to lane-3 encodings were checked with
`--fclk-lane`, which rewrites only the `FCLK` pip before packing, against the
lane-matched vendor builds. All three match. That makes them a test of the
packer, not of the router.

No open-flow image containing a `DQS` has been written. The packer refuses
any design that configures a bank 6/7 pad outside a declared DDR context, and
`DQSIN` must be on its lane's own pad, pin Y3 in bank 6, so every real lane is
refused. The guard exists because a pull or drive configuration on the DDR3
rail is a thermal hazard. It has no switch, and adding one is a decision for
the user, not for this work.

## DQ serializers: OSER8_MEM and IDES8_MEM

### Where lane 0 sits

The hardware-proven vendor controller puts lane 0's strobe pair on Y3 and AA3,
`dq[7:0]` on Y4, AB3, AA5, V4, AA1, AB2, AB5 and AB1, and `dm[0]` on AA4
(Tang-PSX `gateware/ddr3_vendor/tang_psx_ddr3.cst`). Those are IOLOGIC A and B
of the left-edge cells at rows 68, 70, 73, 75, 77 and 79, beside the `DQS`
site `(81,5)` and the byte group's config cell `(72,0)`:

    pad   IO       cell    side    role
    Y3    IOL69A   (68,0)  A       DQS (strobe out: OSER8_MEM, TCLK_SOURCE=DQSW270)
    AA3   IOL69B   (68,0)  B       DQS complement
    AA1   IOL71A   (70,0)  A       dq[4]      AB1   IOL71B  (70,0)  B   dq[7]
    AB3   IOL74A   (73,0)  A       dq[1]      AB2   IOL74B  (73,0)  B   dq[5]
    AA5   IOL76A   (75,0)  A       dq[2]      AB5   IOL76B  (75,0)  B   dq[6]
    Y4    IOL78A   (77,0)  A       dq[0]      AA4   IOL78B  (77,0)  B   dm[0]
    V4    IOL80A   (79,0)  A       dq[3]

In the vendor netlist every lane-0 `OSER8_MEM` takes `TCLK` from the lane
`DQS`'s `DQSW0`, except the strobe serializer, which takes `DQSW270` and says
so in `TCLK_SOURCE`. Every `IDES8_MEM` takes `ICLK` from `DQSR90`, `WADDR`
from `WPOINT` and `RADDR` from `RPOINT`.

### The memory-mode pins are hard-wired

`tools/dq_lane_probe.py` builds the B1 `base` lane plus one serializer on
`dq[0]`, wired as the vendor wires it, and then the same design with one
memory-mode pin driven from a fabric register instead. Gowin builds the
proven wiring for both primitives and refuses all four alternatives with
`CK2060`, "the connection between instance ... and instance 'ser' is
incorrect": `ICLK`, `WADDR`, `RADDR` and `TCLK` take only their `DQS` output.
They are dedicated links of the same kind as `DLLSTEP`, which is why they are
missing from the IOLOGIC port map.

### Configuration

Against `base`, both serializers' differences attribute with no unattributed
fuse. Apart from routing and the pad's own IOB settings, everything is in the
IOLOGIC short-value table of the serializer's side, as named IOLOGIC
attributes the packer already uses. Side A writes in the pad's cell,
`(77,0)`; side B writes in the cell below, `(78,0)`, which is the
`fuse_cell_offset` the packer already gives `IOLOGICB`:

    IDES8_MEM  INMODE=MIDDRX4, FIFO=ENABLE, CLKIMUX=ENABLE
    OSER8_MEM  OUTMODE=MODDRX4, CLKOMUX=ENABLE, WRFCLKSEL=DQSW | DQSW270
               TXCLK_POL=1 when TXCLK_POL is 1, HWL=TRUE when HWL is "true"

`TCLK_SOURCE` maps onto `WRFCLKSEL`, `TXCLK_POL` onto `TXCLK_POL` and `HWL`
onto `HWL`, each isolated by its own build. Several attribute names share a
fuse set (`OUTMODE=ODDRX4` reads alongside `MODDRX4`), so a packer has to
match the fuses, not the names.

The serializers' `FCLK` lane is selected by `FCLKSEL` attributes that differ
between the two primitives. The four lane designs pin a `CLKDIV` to each lane,
as for the `DQS`:

    lane  IDES8_MEM                                  OSER8_MEM
    0     FCLKSEL3=HCLK0/HCLK0_, FCLKSEL5=HCLK0      FCLKSEL0=HCLK0, FCLKSEL1/2, FCLKSEL3=HCLK0/HCLK0_
    1     as lane 3, plus FCLKSEL4=HCLK1/HCLK1_      FCLKSEL0=HCLK1/HCLK3, FCLKSEL4=HCLK1/HCLK1_
    2     none                                       FCLKSEL1/2
    3     FCLKSEL5=HCLK1/3, FCLKSEL6/7               FCLKSEL0=HCLK1/HCLK3

The vendor clocks IOLOGIC from all four lanes. The Apicula fork's IOLOGIC
`FCLK` model offers lanes 0 and 2 only, because its `FCLKSEL1`/`FCLKSEL2` rows
cannot spell 1 and 3. That is a limit of the model, not of the silicon. It
does not block a lane, because the `DQS` and every serializer must share one
memory clock lane, and the open router already puts the `DQS` on lane 0.

`tools/dq_lane_probe.py --check` asserts the refusals, the attribute set of
every built design on both sides, the lane chains and the absence of
unattributed fuses, and passes on all 21 builds.

### Open-flow placement and routing

The nextpnr fork (aquasock/nextpnr `epic/gw5ast138c`) now models the lane-0
serializers:

- The ten lane-0 IOLOGIC positions -- the strobe on Y3 and `dq[7:0]` and
  `dm[0]` -- carry `ICLK`, `WADDR[0:2]` and `RADDR[0:2]` on their input bel and
  `TCLK_DQSW0` and `TCLK_DQSW270` on their output bel. Each pin sits on a
  wire of its own, joined to its `DQS` output by the same fuse-free links as
  `DLLSTEP`, so there is no pip and nothing for the packer to encode. The six
  lane cells are marked so these pins reach none of the 36 other cells of
  their chipdb type. The AA3 position, the strobe's complement, carries no
  serializer.
- `TCLK` is one bel pin per source because `TCLK_SOURCE` chooses between
  `DQSW0` and `DQSW270`: the cell packer renames the port onto the pin the
  parameter names and refuses any other value.
- `OSER8_MEM` and `IDES8_MEM` pack like `OSER8` and `IDES8`, with
  `OUTMODE=MODDRX4` and `INMODE=MIDDRX4`, and without the aux cell those get,
  because the vendor puts an independent serializer on each side of a lane
  cell. Per-bit builds confirmed the bit order: `OSER8_MEM.D<i>` uses IOLOGIC
  `D<i>` and `IDES8_MEM.Q<i>` uses IOLOGIC `Q<8+i>`, the same as `OSER8` and
  `IDES8` on this die.

The C1 vendor designs place and route in the open flow on both sides of
`(77,0)`. `ICLK`, `WADDR`, `RADDR` and the chosen `TCLK` pin land on the same
nets as `DQSR90`, `WPOINT`, `RPOINT` and `DQSW0` or `DQSW270`, bit for bit, and
the `DQS` and the serializer share `FCLK` on lane 0. The open flow also
refuses what Gowin refuses: the `fab_*` designs fail routing at the `DQS`
output wire the link starts from, and `TCLK_SOURCE="DQSW90"` fails in the
packer. The preflight's serializer probes are now lane-0 designs with their
own constraint files, and `tools/ddr3_openflow_preflight.sh` reports all six
primitives PASS, with no place-and-route gap.

### Packing

Apicula's `get_OSER8_MEM_fuses` and `get_IDES8_MEM_fuses` (aquasock/apicula
`epic/gw5ast138c`) write the measured attributes through the existing IOLOGIC
path and refuse any position outside the ten. Matching the vendor took two
corrections that only the fuse comparison showed. First, both reset muxes
must be emitted at `0`: the value costs nothing, but leaving it out sets each
table's absence entry, one fuse apiece the vendor leaves clear. Second, the
input's lane selection is its own. The GW5A input handler emits nothing for
`MIDDRX4`, and its four-attribute lane spelling cannot be used here because
`FCLKSEL7` has no `HCLK0_` row on this die. So `IDES8_MEM` writes the
measured fuses: `FCLKSEL5=HCLK0` and `FCLKSEL3=HCLK0` on lane 0, and nothing on
lane 2. The output reuses the lane selection `OSER8` already has.

`tools/dq_pack_check.py` runs the packer in-process, as `tools/dqs_pack_check.py`
does, so no image is written. It compares the serializer side's IOLOGIC table
fuses with the vendor build of the same source. They are equal on both sides
on lane 0, and on lane 2 when `--fclk-lane` rewrites the serializer's `FCLK`
pip and its `IOLOGIC_FCLK` attribute, which is what the packer reads. For the
`TCLK_SOURCE`, `TXCLK_POL` and `HWL` variants, whose vendor builds rode lane 3,
they are equal outside the lane field. A lane-1 rewrite stops at routing,
because the chipdb has no `FCLKA <- HCLK21` pip, and a serializer moved off the
lane is refused by name.

## Lane 0's complete pads

The proven controller builds each lane-0 pad from several primitives at once
(Tang-PSX `ddr3_memory_interface.vo`). A DQ pad is an `IOBUF` driven by an
`OSER8_MEM`'s `Q0` and `Q1`, whose `O` reaches the `IDES8_MEM` through a
static `IODELAY` (`C_STATIC_DLY=5`). The strobe is an `ELVDS_IOBUF` over Y3
and AA3, driven by the strobe `OSER8_MEM`, whose `O` is `DQS.DQSIN`. DM is a
`TBUF` driven by an `OSER8_MEM`. All of them use `SSTL15` or `SSTL15D` at
`BANK_VCCIO=1.5`. `tools/dq_pad_probe.py` builds those shapes on top of the B1
`base`, the DQ and DM pads in both LVCMOS33 and SSTL15, and checks the result
with `--check`:

- The bidirectional pad's IOLOGIC carries exactly the union of the two
  serializers' fuses, which was checked at fuse level, plus three fuses for
  the `IODELAY`: `C_STATIC_DLY` and the unnamed attribute 133 at value 118.
  Tristate use through `Q1` and `TX0..TX3` adds nothing. Gowin builds the
  pad without the `IODELAY` too, so the delay is the controller's choice, not
  a requirement.
- The strobe's IOLOGIC is the plain `OSER8_MEM` set with
  `WRFCLKSEL=DQSW270`, and the complement side's is empty. DM's is the plain
  set on side B.
- The IO standard never touches IOLOGIC. Moving from LVCMOS33 to SSTL15
  changes only the pads' IOB entries and bank 6's `BANK` table in cell
  `(90,0)`. Every one of those fuses is attributed to a named entry. That is
  the configuration the packer's DDR3-bank guard protects, and it has not yet
  been compared against the open packer.
- Every design's difference from `base` attributes with no unattributed fuse.

In the open flow every shape places and routes with the existing machinery:
the `IODELAY` folds into the `IDES8_MEM` cell (`IODELAY=IN`, `C_STATIC_DLY`),
and the strobe pair becomes two IOBs with `DIFF_TYPE=ELVDS_IOBUF`, the A side
feeding `DQSIN` through its link. `tools/dq_pack_check.py`, now comparing per
IOLOGIC side so that two serializers can share one, finds the packer's
IOLOGIC fuses equal to the vendor's outside the lane field for all of them.
That needed one packer addition: the IODELAY-fed `IDES8_MEM`'s attribute
133=118, which `attrids` cannot name and which is therefore added by its
`logicinfo` index. Only side A was built with an `IODELAY`.

## One clock, one HCLK lane

In every vendor lane design the fast clock reaches its `CLKDIV` and every
`FCLK` sink -- the `DQS`'s and the serializers' -- on one HCLK lane, so the
`PCLK` the `CLKDIV` divides off stays in phase with `FCLK`. The open router
did not. Its global router routes each sink independently from the source,
so the `FCLK` sinks took the first equal-length lane, lane 0, while a pinned
`CLKDIV` held another, and the block was entered twice.

The nextpnr fork now treats nets that feed a `DQS` `FCLK` differently, and
only those. It routes their `CLKDIV` sinks first, since a `CLKDIV`'s lane is
fixed by its placement, and it lets each later sink's backward search end at
an `HCLK_MUX_ALPHA` lane wire the net already owns. With the `CLKDIV` pinned to
each lane, the `DQS` follows it on lanes 0 to 3, and a serializer joins it on
lane 2. The DQS and serializer packers then match the lane-matched vendor
builds with real routing, with no `--fclk-lane` rewrite: the `DQS` on lanes 1,
2 and 3, and `OSER8_MEM` and `IDES8_MEM` on lane 2. A `CLKDIV` pinned to lane 1
or 3 cannot be joined by an IOLOGIC `FCLK`, which the database offers lanes 0
and 2 only. The router then still splits the net, and it warns that it has.
Every other net is routed exactly as before, and the preflight still passes
all six primitives.

## Lanes 1 to 3: where they are

All four lanes of the proven controller are on the left edge (Tang-PSX
`tang_psx_ddr3.cst`):

    lane  IO rows   DQS pad         byte group (table 58)   DQS site
    0     68..79    Y3  IOL69A      (72,0) type 64          (81,5) type 241
    1     95..106   V9  IOL96A      (99,0) type 257         (99,0)
    2     82..93    W6  IOL94A      (90,0) type 259         (90,0), the bank-6 cell
    3     55..66    R3  IOL65A      (63,0) type 270         (81,6) type 241

`tools/dq_lane_locate.py` builds the B1 `base` lane and its no-DQS control
with the strobe pad moved to each lane, and attributes the difference. Every
difference has no unattributed fuse, and in every lane the only configuration
the `DQS` adds is table 58 of one cell inside the lane's rows, which is the
byte group. The site was located from the routing: the tile where the
`DQS`'s inputs land. Lanes 0 and 3, the two nearest HCLK block 2's row, have
their sites in the two type-241 tiles of row 81. Lanes 1 and 2 have theirs in
their own byte-group cell on the IO column. In all four lanes the `DQS` moves
exactly lane 0's 24 input destinations at its site tile -- `A0` to `A5`, `A7`,
`B0` to `B3`, `C0` to `C2`, `D3` to `D5`, `D7`, `CLK0`, `CLK2`, `LSR0`,
`LSR2`, `CE1`, `CE2` -- and each site tile has all 24 as pip destinations.
That location result has now been followed by the full lane-0 measurement set
on lanes 1 to 3.

`tools/dqs_map_check.py --lane N` checks the 22 routed input pairs, the two
clock pairs and all thirteen output pairs for each lane. Lanes 1 and 3 move
the same one destination as lane 0 for every input. Lane 2 does too except
for `RESET`: both members of that pair select the same already-programmed
endpoint, `LSR0 <- W212`, so their different upstream routes converge before
the site and no site fuse moves. Every output was decoded by tracing the
configured route backward from its fixed probe pad to the first destination
at the DQS site. That exact route resolves the zero-state outputs and lane
2's pairs in which unrelated muxes also move; all four sites expose the same
thirteen source wires:

    DQSR90 Q0      DQSW0 F1       DQSW270 Q1
    RVALID Q5      RBURST F6      RFLAG Q6       WFLAG Q7
    RPOINT F2 Q2 F4               WPOINT F3 Q3 F5

The first destinations differ with site geometry, but the port map does not.
All 24 inputs and all thirteen outputs now have per-port evidence on every
lane; none of the lane-1-to-3 output names rests on the earlier shared-hop
inference.

`tools/dqs_param_probe.py --check --lane N` normalizes table 58 through its
database keys instead of lane 0's physical fuse coordinates. All fifteen
designs per lane -- base, nine parameter variants, no-DQS and four pinned
HCLK lanes -- select the same keys as lane 0, reconstruct the exact fuse state
of types 257, 259 and 270, carry the expected HCLK chain and attribute with no
unexplained fuse. The three types share one semantic encoding with their own
coordinate layout, so a packer can use the same table keys at all four byte
groups.

The serializer sweep was repeated on representative DQ pads `AA8/AB8` in
lane 1, `R4/T4` in lane 2 and `W2/Y2` in lane 3. The A-side suite contains 33
designs per lane: the two proven serializers, four illegal fabric-source
tests, three `OSER8_MEM` parameter variants, both serializers on all four
HCLK lanes and every data bit separately. All 99 outcomes match lane 0: the
hard-wired `ICLK`, `WADDR`, `RADDR` and `TCLK`
substitutions are refused with `CK2060`, the IOLOGIC attributes and bit order
are identical and every accepted difference attributes with no unexplained
fuse. The six B-side `ok_ides` and `ok_oser` builds match too, including the
one-cell configuration offset. `tools/dq_lane_probe.py --lane N` defaults to
the measured representative A pad and `build/dq_lane_lN`; an explicit B pad
and output directory reproduce the B-side check.

## Four lanes in the open flow

The nextpnr fork now places and routes all four byte lanes. The generator's
lane-0 constants became one table, `DQS_LANES`, with one entry per lane: the
`DQS` site, the strobe pad, the pad's `F6` wire that feeds `DQSIN`, and the ten
IOLOGIC positions of the strobe, `dq` and `dm` pads from the proven pin map.

    lane  site    strobe  DQSIN source  IOLOGIC rows (side A, B)
    0     X5Y81   Y3      X0Y68/F6      68A 70AB 73AB 75AB 77AB 79A
    1     X0Y99   V9      X0Y95/F6      95A 97AB 100AB 102AB 104AB 106A
    2     X0Y90   W6      X0Y93/F6      93A 82AB 84AB 86AB 88AB 91A
    3     X6Y81   R3      X0Y64/F6      64A 55AB 57AB 59A 61AB 66AB

Each of the four site cells gets an extra-function entry naming its strobe
pad. That keeps the two type-241 sites apart from each other and from the six
unmeasured cells of their type, and keeps lane 1's type-257 cell apart from
its two siblings. No site needed a wire it did not already have. Every one of
the 37 `DQS` wires is a pip destination or source in all four site cells, and
none is a bel pin there. Lane 1's cell has no bels, and lane 2's has only
`BANK6`, which uses none of them. No site is on a `dq` or `dm` row, so no
site cell also holds a lane serializer.

The dedicated links grew with the table. Each lane's `DQSIN` is joined to its
own strobe pad's `F6`, which carries only `IOBA.O` and the IOLOGIC input `D`,
exactly as lane 0's does. Each `STEP[i]` of the one `DDRDLL` is now one node
reaching `DLLSTEP[i]` of all four sites, the vendor's own fan-out. Each lane's
`DQS` outputs reach only that lane's ten positions. All four sites are added
to the block-2 HCLK lane nodes, the block TOOL-012 found every lane's `FCLK`
on. Block 2's lanes 0 and 2 already reach every IOLOGIC row of all four
lanes.

A new packer step, `pack_dqs`, runs after `pack_iologic`. With four `DQS` bels
the placer could put a `DQS` on a site whose `DQSIN` node starts at another
lane's pad, and routing would then fail. The step follows `DQSIN` to the IOB
that drives it and locks the `DQS` to the one site whose `DQSIN` pin wire is
that IOB pin's node. It refuses a `DQSIN` driven by anything but an IOB, as
Gowin does (`PR0014`, `CK3001`). It also refuses a strobe pad with no
location and a pad that is no lane's strobe. A `DQS` with `DQSIN` unconnected
is left to the placer.

`tests/check_dqs_site.py` covers all four lanes: unique site tile types, free
pin wires at every site, single drivers for every link source, each strobe pad
matching its `DQSIN` source and first position, every HCLK lane reaching every
site, and 40 distinct lane positions on marked cells only. All seven checks
pass, and so do `check_internal_net.py`, `check_arch_gen_deterministic.py`,
`check_hclk_to_fclk_138c.py`, `check_postroute_refusal.py`,
`check_iodelay_gw5a.py`, `check_io_timing_arcs.py` and
`check_ae350_tap_wire_types.py`. `check_constids_append_only.py` and
`check_hclk_6block.py` fail only their constid-ordering checks, the same way
without this change. `DQSIN` was appended as a constid. The preflight still
reports all six primitives PASS.

`tools/lane_open_build.py` runs every vendor lane design through Yosys and
nextpnr with the design's own `top.v`, `top.cst` and `top.sdc`, and writes
`build/open/<vendor directory>/<design>/routed.json` for the packer checks.
It asserts:

- that the `fab_*` and `bad_*` designs are refused;
- that every other design's `DQS` is on its lane's site;
- that every serializer is on the IOLOGIC half beside a placed pad on that
  pad's side;
- that every memory-mode pin is on its `DQS` output's net, bit for bit.

All 210 designs of `build/dqs_b1*`, `build/dq_lane*`, `build/dq_lane_b*` and
`build/dq_pad` behave as expected, in about 90 s with four jobs. Pinned to
lanes 1, 2 and 3, the `DQS` follows its `CLKDIV` in every lane. As on lane 0,
an IOLOGIC `FCLK` pinned to lane 1 or 3 stays on lane 0 with the router's
split warning, because the database offers IOLOGIC lanes 0 and 2 only. The
lane-0 packer checks were rerun on the new netlists and still match the
vendor.

### Packing four lanes

Apicula (aquasock/apicula `epic/gw5ast138c`) now packs all four lanes.
`get_DQS_fuses` maps each site to its byte group's cell, `X0Y72`, `X0Y99`,
`X0Y90` and `X0Y63`. It holds the encoding as table-58 keys rather than
coordinates:

    presence      11 12 17 18 21 22 23 29
    FIFO_MODE_SEL=1          10 19
    RD_PNTR bits 0, 1, 2     13 14 15
    DQS_MODE  X1 none, X2_DDR2 31 35, X2_DDR3 32, X4 36, X2_DDR3_EXT 33 34
    HWL=true                 30
    FCLK lane 0 none, 1: 37 40, 2: 38 41, 3: 39 42

It resolves each key through the cell's own table. All 26 keys exist in all
four cell types. Type 64 places them on row 20, and 257, 259 and 270 share
one other layout. Lane 0's fuses are unchanged. The serializer position check
covers the forty positions of `DQS_LANES`.

`tools/dqs_pack_check.py --lane N` checks a lane at its byte group. It moves
the recorded lane-0 encoding to that cell by key, with the same helper,
`at_byte_group` in `tools/dqs_param_probe.py`, that
`tools/dqs_param_probe.py --check` now uses (still 15 of 15 per lane). A check
of a lane-1 design against lane 0's byte group fails, as it should.
`tools/dq_pack_check.py` reads the serializer's cell from its bel and needed
no lane option.

`tools/lane_open_build.py --pack` runs both checks on every routed design
against its own vendor bitstream. On all four lanes, 188 packer checks pass:

- 56 `DQS` designs pass by table key at their lane's byte group. The four
  lane-pinned designs per lane match the vendor exactly. The other ten match
  outside the lane field, because the vendor carries the board clock on lane
  3 while the open router takes lane 0. All 56 also equal the recorded
  encoding, lane field included.
- 18 serializer designs match exactly. These are the `*_lane0` and
  `*_lane2` designs of all four DDR3 lanes, whose clock rides HCLK lane 0 or
  2, the IOLOGIC lanes the model spells.
- 114 other serializer and pad designs match outside the lane field.

There is nothing to compare for `no_dqs`. There is also nothing for
`dq_pad`'s `dqs_lvcmos`, which Gowin refused for `LVCMOS33D` on an
`ELVDS_IOBUF` (`CT1109`) and which the open flow places and routes. The full
run takes about 14 minutes and never holds more than two vendor bitstreams.

All four lanes are now modelled at the same level as lane 0: placed, routed
and packed in-process to the vendor's fuses. What remains before an open-flow
lane image is the DDR3-bank guard and the SSTL15 and SSTL15D IOB and BANK
comparison it would open.

## DDR3 banks: IO configuration against the vendor

Banks 6 and 7 hold every DDR3 ball. Bank 6 carries the four data lanes, 44
balls on left-edge rows 55 to 108, with its `BANK` table in cell `(90,0)`.
Bank 7 carries the 28 address, command and clock balls on rows 0 to 54, with
its `BANK` table in `(18,0)`. Apicula refuses any design that configures a
pad there outside a declared DDR context, because a wrong pull or drive
setting on the DDR3 rail is a thermal hazard. Before that refusal is lifted
for a real image, the fuses the packer would write on those banks have to
equal the vendor's.

`tools/ddr_bank_check.py` runs `gowin_pack`'s own stages on an open-flow
routed netlist with `ddr_context` set on that one in-memory device. It never
creates the bitstream object, so no image exists. Against the vendor build of
the same source it compares two kinds of table:

- the IOB table of all 100 bank 6/7 pads, used or not: side A's `IOBA` in the
  pad's cell, side B's `IOBB` in the cell below;
- both `BANK` tables.

Each comparison is restricted to the table's own fuses.

The first run found that the packer could not handle SSTL at all. The
inherited alias folds `SSTL15` and `SSTL15D` into the family codes `SSTL` and
`SSTL_D`. This die's IOB tables have no `logicinfo` entry for those codes:
they key `IO_TYPE` on the full names, in 710 and 843 entries on the bank-6
cells. The fold also lost the 1.5 V the bank VCCIO check needs, so packing
stopped with `KeyError: 'SSTL'`. The Apicula fork now keeps those two names
whole on the 138C.

With that fixed, the four lane-0 SSTL designs of `build/dq_pad` compare as
follows:

| Where | Packer against vendor |
|---|---|
| Strobe Y3 as an SSTL15 input | equal |
| DQ IOBUF Y4 | missing `TRI_MUX=TMDDR` and `SLEWRATE=FAST`, `(8,4)` and `(10,14)` |
| DM TBUF AA4, side B | missing `(1,12)` and `(5,2)` |
| SSTL15D strobe pair Y3/AA3 | missing four fuses on each side |
| every unused pad | the vendor sets two fuses the packer never does: `(1,12)` `(9,13)` on side A, `(1,14)` `(4,1)` on side B, and `(9,12)` `(17,13)` on bank 7's `IOL1A` |
| unused bank-6 pads beside an SSTL15 single-ended pad | the packer also writes `(2,3)` `(2,6)` on side A and `(3,1)` `(3,10)` on side B, input-side entries the vendor leaves clear |
| bank 6 `BANK` | SSTL15: missing `(20,20)`, `(20,50)`, `(20,52)`; SSTL15D: `(20,44)` where the vendor has `(20,43)` |
| bank 7 `BANK` | equal |

The unused-pad difference is not specific to the DDR3 banks. On ordinary
banks 2 and 3 of the same build, 99 of 100 unused pads differ the same way,
two packer fuses against the vendor's four. It is how the packer treats an
unused pad on this die for every core that uses the fork. Changing it
everywhere would change those cores' bitstreams, so the fix belongs inside
the declared DDR context, for banks 6 and 7 only.

No bank-7 address, command or clock shape and no lane-1-to-3 SSTL pad has
been built for the vendor yet, so bank 7's used pads and the other lanes'
pads are unmeasured. The DDR3-bank refusal itself is unchanged.

### All lanes, bank 7, and unused pins

The comparison now covers every lane and bank 7:

- `tools/dq_pad_probe.py --lane N` builds lane N's four SSTL pad designs on
  its own strobe pair, a side-A DQ pad and its DM pad, into `build/dq_pad_lN`.
- `tools/cmd_pad_probe.py` builds bank 7's shapes from the proven vendor
  netlist: a plain `OSER8` into an SSTL15 `OBUF` for each address, bank and
  command ball; an `OSER8` with a constant `0101...` pattern into an SSTL15D
  `ELVDS_OBUF` for the clock pair L3/K3; and a register into an `OBUF` for
  `reset_n` on L6.
- `tools/ddr_bank_check.py --summary` prints one line per distinct
  difference.

Lanes 1 to 3 show exactly lane 0's signatures. The two missing fuses of a
serializer-driven output pad, `TRI_MUX=TMDDR` and `SLEWRATE=FAST`, follow the
pad's side, not its type: lane 1's DM pad sits on side A and lacks the DQ
pad's pair.

Bank 7 exposed two more gaps:

- The open flow cannot place `cmd_full_sstl`, all 28 balls. Its plain `OSER8`
  takes both IOLOGIC halves of a cell, while the vendor builds both halves and
  the proven map uses both (M1/L1, J5/H5 and others). `cmd_min_sstl` uses
  `ddr_addr[0]` on M1 and `ddr_addr[9]` on H5, each with its cell's other half
  unused, and routes.
- Packing `cmd_min_sstl` stops with a VCCIO conflict, and the cause is an
  upstream packer bug. `BankDesc.add_io_bel` tests `if bel.is_mipi:` without
  calling it, so the test is always true. The N half of any differential
  output that carries no `IO_TYPE` is therefore taken as MIPI, `LVDS25`, and
  sets the bank's LVDS VCCIO to 2.5 V. With a single-ended 1.5 V output
  present the bank refuses. Without one, as in `dqs_sstl`, the packer programs
  bank 6 for 2.5 V. That is the `BANK` difference `(20,44)` against `(20,43)`.
  The line is on upstream `master`, and the desktop core's TMDS N halves take
  the same path.

Unused pins contradict the fork's own record. The 138C class drops `DRIVE`
and `DRIVE_LEVEL` from every unused pin, citing 35 vendor pairs (`P3.T26`,
`D108`) in which the vendor programmed no drive strength on a floating pin.
`tools/unused_pin_probe.py` builds a plain non-DDR design four ways:

- this project's non-project `run.tcl` or the fork harness's project-mode
  `run.tcl` and option set;
- this project's `.cst` conventions or the harness's (`PULL_STRENGTH=MEDIUM`,
  a `BANK_VCCIO` on every pin).

Packed in memory and compared fuse for fuse on all 199 unused left- and
right-edge pins:

| Packer setting for unused pins | Pins equal to Gowin EDA 1.9.11.03 on Linux |
|---|---|
| fork rule, no drive | 0 of 199, in all four builds |
| GW5A base set, `DRIVE=8` and `DRIVE_LEVEL=8` | 199 of 199, in all four builds |

So the build recipe does not explain the difference. The fork's corpus lives
on another host and its harness defaults to the macOS Gowin package; neither
can be examined here, so the platform and the corpus itself remain the
untested explanations. The user chose to follow these measurements for banks
6 and 7 inside a declared DDR context only, leaving the fork's rule in place
for every other bank and core.

### The vendor's configuration under a declared DDR context

The Apicula fork now writes the vendor's bank 6/7 IO configuration, but only
with `ddr_context` set. The refusal is unchanged, and with `ddr_context` off,
seven non-DDR netlists pack to the same fuses as before. The corrections:

- **Unused pins** get the GW5A set with `DRIVE=8` and `DRIVE_LEVEL=8`, under
  the device's unused default standard rather than the bank's SSTL15, through
  a new `get_unused_io_type` hook. Every LVCMOS standard from 1.2 V to 3.3 V
  gives the same fuses here.
- **A differential N half** takes its P half's `IO_TYPE` and `IOLOGIC_IOB`
  mark, which corrects the 2.5 V VCCIO from the uncalled `is_mipi` and gives
  both halves `TRI_MUX`.
- **Every output** is `SLEWRATE=FAST`. **A pad whose tristate a serializer
  drives** is `TRI_MUX=TMDDR`. **The SSTL15D clock's `ELVDS_OBUF`** drops the
  desktop TMDS additions `DRIVE_LEVEL` and `PADDI` but keeps
  `IOB_UNKNOWN51=TRIMUX`. **The strobe's `ELVDS_IOBUF`** is
  `IOB_UNKNOWN51=TRIMUX` with the design's `PULLMODE`.
- **A bank with a single-ended SSTL15 input** has `VREF=INTERNAL`. A DQ
  `IOBUF` alone is enough, as `lane_sstl` showed. **A bank whose only
  standards are SSTL15D pairs** takes `IO_TYPE=SSTL15D`. Bank 7, with outputs
  only, gets neither.

`lane_sstl` (`tools/dq_pad_probe.py`) puts a lane's strobe pair, a DQ pad and
its DM pad in one design, as the proven controller does. On lane 0 the DQ and
DM pads share cell 77, and nextpnr refused to place it. Its
`check_iologic_placement` made `OSER8_MEM` and `IDES8_MEM` claim their cell's
other IOB. The fork now exempts the two lane serializers. The design then
places on all four lanes, and its IOLOGIC fuses equal the vendor's on both
sides of the shared cell. Plain `OSER8` keeps the check, so `cmd_full_sstl`
still cannot be placed.

With the corrections, `tools/ddr_bank_check.py` finds all 102 bank 6/7
tables equal to the vendor on every SSTL design that places: lane 0's five
and lanes 1 to 3's five each, 20 lane designs, plus `cmd_min_sstl`. The
other checks run on this change:

- `tools/lane_open_build.py` behaves as expected on 227 of 228 designs; the
  exception is `cmd_full_sstl`.
- `--pack` passes all 22 pad-design packer checks.
- The preflight passes all six primitives.
- `check_dqs_site.py` passes all seven checks.
- The full Apicula suite fails the same 58 tests with and without the change,
  all predating it.

Not compared yet: the full bank 7, which waits on `OSER8` pairing, and a
whole-controller pad set. This makes the bank fuses match. It is not stage 2:
no declared context exists outside this check, no image has been written,
and nothing has been loaded onto the board.

## Bank 7 in full, and the whole controller's pad set

The open flow's plain `OSER8` took both IOLOGIC halves of a cell: an aux
`IOLOGIC_DUMMY` on the other side, and a check that the other side's IOB was
free. That kept the full 28-ball bank 7 from placing. `tools/cmd_pad_probe.py`
measured one bank-7 cell, IOL35 (M1/L1), three ways: `cmd_m1_sstl` with the
serializer on side A, `cmd_l1_sstl` on side B, and `cmd_pair_sstl` on both.
Gowin EDA 1.9.11.03 configures only the serializer's own side, six IOLOGIC
fuses, and nothing on the other side; the pair is exactly the union. The open
packer's aux cell wrote nothing either. The packer's own side already matched
outside the HCLK lane field, which differed only because the vendor put the
board clock on lane 1 or 3 and the open router on lane 0.

The nextpnr fork therefore stops giving a plain `OSER8` on the GW5AST-138C an
aux cell or the other side's IOB. On other devices nothing changes, and since
the aux cell wrote no fuse here, no existing design's bitstream changes
either.

| Bank-7 design | Places | IOLOGIC | IOB and BANK |
|---|---|---|---|
| `cmd_m1_sstl`, `cmd_l1_sstl`, `cmd_pair_sstl`, `cmd_min_sstl` | yes | equal outside the lane field | 102 of 102 |
| `cmd_full_sstl`, all 28 balls, 26 `OSER8` | yes | equal outside the lane field | 102 of 102 |

`tools/dq_pack_check.py` now checks plain `OSER8` as well as the lane
serializers.

`tools/ddr3_pad_set_probe.py` builds the whole controller's pad set as one
design, on the proven pin map:

- one `DDRDLL`;
- per lane, the `DQS` with its SSTL15D `ELVDS_IOBUF` strobe and strobe
  `OSER8_MEM`, eight SSTL15 DQ `IOBUF`s each with an `OSER8_MEM`, a static
  `IODELAY` and an `IDES8_MEM`, and the DM `TBUF` with its `OSER8_MEM`;
- bank 7's 28 balls in `cmd_full_sstl`'s shapes.

Its strobe ports are scalar, because nextpnr leaves the N half of a bused
differential port unconstrained. In the open flow every `DQS` lands on its
own lane's site and every memory-mode pin on its lane's `DQS` output, and the
in-process packer checks agree with the vendor build:

| Check | Result |
|---|---|
| `tools/dqs_pack_check.py` | all four DQS equal by table-58 key at their byte groups |
| `tools/dq_pack_check.py` | all 130 serializers' IOLOGIC equal outside the lane field |
| `tools/ddr_bank_check.py` | all 102 bank 6/7 IOB and BANK tables equal |

`tools/dqs_pack_check.py` now checks every `DQS` in a design at the byte
group of the lane whose site it occupies, with `--lane` as an assertion.
`tools/lane_open_build.py --pack` runs every check that applies to a design.

The board clock on every `PCLK` and `FCLK` is a probe simplification. The
router warns that it splits that net across HCLK lanes, because the database
offers IOLOGIC lanes 0 and 2 only, and the lane fields are compared apart for
that reason. A real controller clocks the lanes from its memory PLL through
`CLKDIV`s. No image has been written, and nothing has been loaded onto the
board.

## The declared DDR3 context

A design may now configure a pad on banks 6 and 7 in exactly one way:
`gowin_pack --ddr3-context MANIFEST`. The manifest is
`fpga/ddr3/ddr3_balls.json`, written by `tools/ddr3_ball_manifest.py` from
the proven pin map and checked by its `--check` mode. It lists the board's
72 DDR3 balls: 44 on bank 6 and 28 on bank 7, five of them SSTL15D pairs. For
each ball it gives the port, IO site, bank and standard, and for a pair half
which half it is and its partner. It also states the settings every ball
carries: `BANK_VCCIO=1.5`, `PULL_MODE=NONE` and `DRIVE=8`. The manifest is
board knowledge, so it lives here and not in the Apicula fork.

The Apicula fork accepts the flag on the GW5AST-138C only. It checks the
manifest against the die on load and refuses it if any ball fails:

- each ball is a bank 6/7 pad at the IO site it claims;
- a single ball is SSTL15, and both halves of a pair are SSTL15D, name each
  other and share one IO cell;
- the settings are exactly the proven three.

Inside the context, every bank 6/7 pad must meet all of these, or the packer
refuses it by name:

- it is a listed ball;
- it has exactly the listed standard and pair half, so a strobe ball used
  single-ended is refused;
- it carries `BANK_VCCIO=1.5` and `PULL_MODE=NONE`, `DRIVE=8` on an output and
  no drive on an input;
- it carries no other IO attribute.

LVCMOS is refused like any other wrong standard. A used DDR3 bank must also
resolve to 1.5 V, which catches the `is_mipi` class of error however it
arises. A context set without a manifest is refused. Without the flag
nothing changes, and every bank 6/7 pad is refused as before.

`tools/ddr_bank_check.py` now packs through the flag itself, with the
committed manifest, rather than setting the context on an in-memory device.
Through it:

| Designs | Result |
|---|---|
| `dqs_sstl` and `lane_sstl` on all four lanes, the five bank-7 designs, `full_sstl` | all 102 tables equal to the vendor |
| `dq_sstl`, `dq_nodelay_sstl`, `dm_sstl` on every lane | refused: they use the strobe ball Y3, V9, W6 or R3 as a single-ended SSTL15 input, a measurement shape the controller never uses |
| `dq_lvcmos` | refused for LVCMOS33 |

The refused designs' fuses were compared against the vendor in stage 1b.
`tests/test_ddr3_context_138c.py` in the fork pins every admission rule and
every manifest refusal. The fork's full suite fails the same 58 tests with
and without this change. With the flag absent, seven non-DDR netlists pack to
unchanged fuse digests and both DDR designs are refused.

This is stage 2. Writing an image with the context is stage 3 and needs its
own approval, as does any access to the board.

## The first written DDR3 image

`tools/build_ddr3_pad_image.sh` writes the open-flow image of the whole pad
set, `build/ddr3_image/full_sstl.fs`, and checks it in five steps:

1. confirm the manifest matches the pin map (`tools/ddr3_ball_manifest.py --check`);
2. synthesize the source `tools/ddr3_pad_set_probe.py` generated;
3. place and route it;
4. pack it with `gowin_pack --ddr3-context fpga/ddr3/ddr3_balls.json`;
5. compare the written file with the vendor's build of the same source.

It writes only a `.fs`, never the raw `.bin` TinyTang loads. The image is a
measurement artifact: its serializers run from the board clock, with no
memory PLL and no controller, so it is not for the board.

The comparison, `tools/ddr3_image_check.py`, decodes both files and compares
every table the DDR3 interface configures:

| Table | Scope | Compared |
|---|---|---|
| IOB and `BANK` | every bank 6/7 pad, used or not, and both bank tables | exactly |
| IOLOGIC | every bank 6/7 cell | outside the `FCLKSEL` entries |
| DQS | table 58 at the four byte groups | outside the lane field |
| DDRDLL | the corner cell's `DLL0` table | exactly |

The first image differed in one table only. The vendor sets `DLL0` features
5, 17, 18 and 19, fuses `(21,7)`, `(21,8)`, `(21,9)` and `(21,15)`, in every
build with a DDRDLL. No parameter sweep moves them, and the packer had left
them to a measurement switch. At the user's choice the Apicula fork now
writes them under a declared DDR3 context. With them, the image equals the
vendor on all 306 tables:

| Table | Equal |
|---|---|
| IOB and BANK | 102 of 102 |
| IOLOGIC | 199 of 199 |
| DQS | 4 of 4 |
| DDRDLL | 1 of 1 |

The image's SHA-256 is
`4c24096e1666c7606b2147a6e8e71d741a21cb25442ec13e6fe947d5154df81f`, and a
rebuild into another directory reproduces it. What the four features
configure is still unattributed. The two raw corner bits recorded with them
in TOOL-003, `(1,12)` and `(9,13)`, are the unused-pin drive of the corner
cell's own bank-6 pad. Without the flag, the DDRDLL designs pack exactly as
before.
