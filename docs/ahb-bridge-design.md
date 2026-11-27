# The AE350-to-DDR3 bridge: from 100 MB/s to the port's 600

Status: proposed, stages 0 and 1 approved 2026-11-26 (core-log entry 29).

This document is the reference the bridge rewrite is built against. It records
why the A25 reaches its own memory at a sixth of what the port allows, what
the replacement is, and what has to be proven before it is believed.

---

## 1. The gap, measured

The A25's RAM AHB port is 64-bit at 75 MHz, so **600 MB/s is the most the CPU
can ever take from the array**, whatever the fabric does. The DDR3 itself is
not the limit: the controller's 256-bit port moves 2.67 GB/s measured, and a
CPU-limited stream would use 22 per cent of it.

`firmware/apps/write_depth` measured one 8-byte transfer at **59.9 core
cycles**, which is 100 MB/s, or a sixth of the port (AE350-009). The same
figure was charged to an uncached CPU store and to a cache write-back, so the
cost is in the bridge and not in the A25's store pipeline. Nothing amortises it:
four transfers of a line cost 4 x 59.8, and K = 2, 4 and 8 successive lines all
cost the same per line.

In time units, 59.9 core cycles is 8.0 `pclk`, of which `ddr3_ctl` needs 2 for a
command. The other 6 are the crossing.

| element | cost | note |
| --- | --- | --- |
| `ahb_ram` accept | 1 `bus_clk` | address phase registered |
| write into `ahb_ddr3`, PCLK side | 2 `pclk` | `x_tog` through two flops |
| command accept | 1–2 `pclk` | `cmd_valid`/`cmd_ready` |
| `y_tog` back, bus side | 2 `bus_clk` | and `hready` waits for it |
| **per 8-byte beat** | **~6 `bus_clk` / 8 `pclk`** | nothing overlaps |

## 2. Why it serialises

Three structural facts, all in the committed RTL:

1. **`ahb_ram` waits for the DDR3 on every beat.** It clears `hready` on
   accepting an SDRAM transfer and sets it again only when `sd_ack` returns
   (`fpga/ae350_ddr3/ahb_ram.sv`, the `stage[3]` arm). `sd_ack` comes back
   from `ahb_ddr3_pclk` once the write is inside `ddr3_ctl`'s FIFO. So each
   beat pays a full round trip across two unrelated clocks.
2. **One request in flight.** `ahb_ddr3_bus` has a single `busy` flag and
   refuses a new request while it is set. The crossing is a per-request
   toggle, so its synchroniser latency is paid once per beat rather than
   amortised over a queue.
3. **The controller was never the problem.** `ddr3_ctl` already has a 4-entry
   request FIFO, a registered `cmd_ready` that admits three outstanding
   entries, and issues one command per `pclk`. It has been fed one request
   every eight cycles.

This is the shape of a slow I/O peripheral, not of a memory bridge. AHB is
pipelined; the master is ready to stream beats back to back, and the slave
refuses them.

## 3. What the replacement does

**Writes become posted and gathered. Reads stay as they are.**

```
A25 DDR_H ──► ahb_ram (bus_clk)          ahb_ddr3 (pclk)              ddr3_ctl
             │                            │
   write ────┼─► line gather buffer ──► async FIFO ──► line merge ──► one 256-bit
             │   (32 B, byte masks)      (8 B beats)   (4 beats)      masked WRITE
             │       hready high while there is room
             │
   read ─────┼─► drain writes, then one 256-bit read, three hits from
             │   the one-line buffer as today
```

### 3.1 Posted writes

`ahb_ram` keeps a 32-byte gather buffer for the line being written, plus a
mask of which of its bytes are valid. A store merges into it; `hready` stays
high as long as the buffer is not full. The buffer is handed across as 8-byte
beats when it fills, when the address moves to another line, or when 1024 bus
clocks pass with no store (so a scanout can never see a line held forever,
entry 25's rule).

The A25 therefore streams at bus rate: four beats per line, one per bus clock.

### 3.2 A queue instead of a toggle

`ahb_ddr3_bus` holds N slots (N = 4 to start), each with its line address,
doubleword index, byte lanes and data. A Gray-coded write pointer crosses to
`pclk` and a Gray-coded free count crosses back; neither needs a per-request
synchroniser, so the crossing's latency is paid once per *queue*, not once per
beat.

The important consequence for closure: **all of the wide logic is on `pclk`.**
The v7 gather failed because its 256-bit tag comparators sat on the `bus_clk`
store path and cost 1.67 ns of a 1.74 ns margin (AE350-008). Here the merge,
the mask and the line comparison live in the `pclk` domain, where four beats
are already being gathered and the timing is that of `ddr3_ctl`, not of the
A25's store path.

### 3.3 Line gathering on the PCLK side

Four consecutive beats of one line merge into one 256-bit masked write, exactly
as `ddr3_ctl`'s contract wants (mask bit k suppresses byte k). That is the
change that removes DRAM-side amplification: one command and one burst per
32-byte line instead of four partial writes.

### 3.4 Ordering and the read fence

- Writes are posted, so they complete out of the A25's sight. That is safe only
  because the A25 is the RAM port's only master and its cache does the
  ordering; nothing else reads that window.
- **A read drains every pending write first.** This is both the correctness
  rule (a read must see an earlier write to the same line) and the write fence.
  It is what makes `tv_dcache_wbinval` sufficient before a page flip.
- Partial lines are flushed before a different line is started, and by the
  1024-clock age limit.
- The block-RAM window at `0x7fff0000` is untouched and stays synchronous.

## 4. Expected result

| | now | after | how |
| --- | ---: | ---: | --- |
| one 8-byte beat | 59.9 cycles | ~10 | posted, one per bus clock |
| 32-byte line, cached | 683.3 cycles | ~40 | 4 beats, one 256-bit write, no fill storm |
| 32-byte line, cache off | 479.9 cycles | ~320 | 8 beats, as `sd` does not exist |
| full screen (3.69 MB) | 105 ms | ~6.1 ms | port-limited |

Two predictions to test rather than assume:

- The **cache-off window of `tv_dcache_save_off` stops paying** (AE350-010).
  It wins today only because a cached store pays a 501.7-cycle fill; with
  posted writes the uncached 8-beat line costs more than four full beats, so
  the cache should stay on. Re-measure and revise AE350-010 if so.
- The **600 MB/s ceiling is only reached if the A25 sustains one beat per bus
  clock.** If it cannot, `write_depth` will say so at the first measurement and
  the target drops to whatever the A25's own issue rate allows.

## 5. Staging

**Stage 0, closure robustness.** Prerequisite, not a nicety. The image in use
has 86 ps of slack on `pclk` (100.87 MHz against 100.00), which is why about
one seed in fourteen closes. Adding logic to `pclk` before that is fixed leaves
no way to tell a new failure from the old one. Gate: at least 8 of 16 seeds
close every clock.

**Stage 1, the bridge.** Sections 3.1 to 3.4, one commit, keeping reads
byte-identical until writes are proven.

**Stage 2, read depth.** Deferred. The A25 does not pipeline its own misses
(AE350-004's streamed and dependent costs are within 5 per cent), so
outstanding reads buy little until something above them changes.

## 6. Gates

### Simulation, `tools/sim_ae350_ddr3.sh`

The harness already drives `ahb_ram` and `ahb_ddr3` with a pipelined AHB
master against a byte-exact reference, at incommensurate bus and PCLK periods,
with single transfers of every size, WRAP4 bursts, the block RAM and an ERROR
region. Extend it with a longer randomised run and add these mutants, each of
which must fail:

| mutant | what it proves |
| --- | --- |
| a beat dropped at a FIFO boundary instead of stalling `hready` | flow control |
| beats of two different lines merged into one write | the gather's flush |
| write mask polarity inverted | the existing byte convention |
| a partial line flushed as a full line | mask derivation |
| a read issued with writes still buffered to its line | the read fence |
| Gray occupancy off by one, `hready` stays high when full | never overrun |
| doubleword index off by one inside a line | beat placement |
| posted write acknowledged, never drained | liveness |

### Board

`write_depth` (expect ~40 cycles a line cached), `pma_probe`'s screen fill,
`ddr3_test`'s 1,022 MiB across the array, `video_test`'s frames with `LATE`,
training still `error 0` and `d 1 b 2`, and a randomised load to shake out
ordering.

## 7. Risks

- **Failure is silent corruption, not a hang.** The byte-exact reference and
  the mutants above are the defence; nothing is loaded on the board before
  they all pass.
- **`ddr3_arb` gives video one slot against the CPU port.** CPU writes
  arriving six times faster changes that balance. `LATE` is the instrument,
  and `video_test` is the gate.
- **The boot ROM loader and the block-RAM window share `ahb_ram`.** Their
  simulations must keep passing unchanged.
- **Closure.** The rewrite is judged on a netlist that closes; if stage 0 does
  not get there, stage 1 does not start.
