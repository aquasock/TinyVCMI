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
  resolves to it through the chipdb's macro table. There is deliberately no
  `LOCK` pin: a design that uses `LOCK` fails placement with "No wire found for
  port LOCK" instead of routing a net that reaches nothing.
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
