# The AE350-to-DDR3 bridge

Status: describes the bridge as built and measured, core-log entries 30, 33,
35 and 40, on seed 8 of `build/ae350/e1`. It replaces this document's
2026-11-26 proposal (entry 29), a gather buffer in front of a serialised
crossing, which was superseded by entry 30 before it was built; section 2
keeps what that proposal measured and predicted.

The bridge carries the AE350's 64-bit RAM AHB port (`DDR_H*`, `bus_clk`,
75 MHz) to `ddr3_ctl`'s 256-bit request port (`pclk`, 100 MHz) for the DDR3
window, `0x40000000` to `0x7ffeffff`. The two clocks come from different PLLs.
The port's own ceiling is 64 bits at 75 MHz, **600 MB/s**; the controller's
256-bit port moves 2.67 GB/s, so the bridge, not the DDR3, decides what the
A25 gets.

---

## 1. The path

```
A25 DDR_H* ──► ahb_ram ──► ahb_ddr3_bus ══ queue ══► ahb_ddr3_pclk ──► ddr3_arb ──► ctrl_glue ──► ddr3_ctl
  bus_clk      (bus_clk)    ways, cl,       16 x     queue read,      video first,   CPU port
                            prefetch     Gray ptrs   slots, request   tag FIFO       after hand-over
                                       ◄── r_tog ── lines back ◄──────────────────── words back
```

| file | module | clock | job |
| --- | --- | --- | --- |
| `fpga/ae350_ddr3/ahb_ram.sv` | `ahb_ram` | `bus_clk` | AHB slave: block RAM at `0x7fff0000`, the DDR3 window, ERROR elsewhere |
| `fpga/ae350_ddr3/ahb_ddr3.v` | `ahb_ddr3_bus` | `bus_clk` | the ways, the current line `cl`, prefetch, the queue's write side |
| | `xfifo_w`, `xfifo_r` | both | the ordered queue |
| | `ahb_ddr3_pclk` | `pclk` | the queue's read side, the request, the ways' line slots |
| `fpga/ae350_ddr3/ddr3_arb.v` | `ddr3_arb` | `pclk` | video and CPU onto the controller's CPU port |

`tools/ae350_place.py` keeps the bus half beside the AE350 macro and the
`pclk` half and the queue's RAM beside `ddr3_ctl`, with only registers
between them.

## 2. Where it started

The first bridge (entry 15) took one 64-bit transfer at a time across a
toggle handshake: `ahb_ram` held `hready` low on every DDR3 beat until the
`pclk` side acknowledged it, and `ahb_ddr3_bus` had one busy flag.
`firmware/apps/write_depth` measured the result (entry 27): one 8-byte
transfer cost 59.9 core cycles with none ever outstanding, a cached line cost
a 501.7-cycle read-allocate fill plus 4 x 59.8 of write-back, and a
whole-screen fill took 105 ms. A gather that merged a line's doublewords into
one DDR3 write bought 11 per cent and cost 11 MHz of `bus_clk` (entry 25,
AE350-008).

The 2026-11-26 proposal (entry 29) was a gather buffer with posted writes and
reads left as they were. Entry 29 built and withdrew a first posted-write
bridge, and entry 30 built the ordered queue below instead, carrying reads
and writes together so that a read can never overtake a write.

## 3. As built

### 3.1 `ahb_ram`: posted writes, zero-wait sequential reads

- **A DDR3 write** is posted (`sd_post`) in its data phase with no wait state
  while `sd_post_ok` promises room, for that write and for one more in the
  next clock (the queue's `LEAD` of 2), and otherwise waits in its data phase
  until it does.
- **A DDR3 read** raises `sd_req` from the clock after it is accepted and
  completes at the edge `sd_ack` is high, `sd_rdata` registered into `HRDATA`.
- **A SEQ beat after a DDR3 read, in that read's 32-byte line,** is answered
  as it is accepted, with no wait state, if the bridge's current line holds the
  line (`sd_lhit`); `sd_ldata` is registered into `HRDATA` then (entry 33). A
  SEQ beat is in its predecessor's line unless it starts a line in a burst that
  is not a wrapping burst of at most 32 bytes. The decision uses only `HTRANS`,
  `HBURST`, `HSIZE`, `HADDR[4:0]` and registers, so no address compare sits on
  the macro's outputs; the first version, which compared tags on `HADDR`,
  failed `bus_clk` on every seed.
- Every fabric register on `bus_clk` takes `resetn` synchronously (entry 16,
  TOOL-073).

### 3.2 One ordered queue

Every DDR3 access, read or write, goes through one queue in program order:
`xfifo_w` on `bus_clk`, `xfifo_r` on `pclk`, 16 entries in LUT RAM with
Gray-coded pointers. The RAM is written on `bus_clk` from registers and read
asynchronously on `pclk`, which reads an entry only after its write pointer has
come through two flops. `full` and `room` are registered from the pointers and
are never optimistic. `ddr3_arb`, `ctrl_glue` and `ddr3_ctl` keep the order, so
a read queued behind a write to the same line returns the written data.

A write goes to the DDR3 as one masked write of its own doubleword's lanes,
the rest of the line masked (byte k at `cmd_wdata[8k +: 8]`, mask bit k). Up
to 16 can be queued, so the A25 stores at bus pace while `pclk` drains them.

### 3.3 Four read ways, the current line and prefetch

Reads land in four line ways, so up to four are in flight (entry 35). Each
way has a tag and is valid, pending or neither; a pending way may be poisoned.
The ways' 256-bit lines live on the `pclk` side in a LUT RAM, one slot a way,
filled in the order the reads were queued; the bus side reads the RAM
asynchronously at its registered way select, so the select is the RAM's own
read mux and not a 4:1 mux of 1,024 flops.

A read is looked up in the clock after its `req` rises. If the current line
register `cl` holds its line it is answered then; if a way holds the line or
has it pending it waits on that way; otherwise it queues a read into the next
way in round-robin order and waits on it. Answering from a way copies the line
into `cl`, so the burst's further beats are answered at zero wait.

Every lookup also starts a prefetch of the next `pf_depth` lines, set by
`TV_PERF_PF_DEPTH` (`exts_perf.sv`, `0xe8020040`, 0 to 3, reset 2): in clocks
with no lookup, no demand read and no posted write, each next line not
already in a way is queued, one every two clocks, never into the way a read
is waiting on.

A write keeps every way and `cl` right as it reaches the queue's staging
register: `cl` and any valid way holding its line become invalid, and a
pending way holding its line is poisoned, since its read was queued ahead of
the write and will bring the old data, and becomes invalid rather than valid
when that line returns. No way is queued in a clock a write is staged, and a
lookup waits while one is, so a read never sees a line older than a write
ahead of it. The A25 is the RAM port's only master.

### 3.4 `ddr3_arb`

The video fetcher and the CPU's bridge share `ctrl_glue`'s CPU port, video
first. The request to the controller is a register loaded only while it is
empty, so `ddr3_ctl`'s ready reaches one flop and not the register's 314
clock enables (entry 35); a request is accepted every two `pclk`, against the
video's one line read per 145 ns and the CPU's one posted write per 69 ns. The
video's request goes through a one-entry slot whose ready is a register.
`ddr3_ctl` returns reads in order, so a FIFO of one bit per read taken routes
each returning word to its client.

### 3.5 Reset

Both halves are reset together at the hand-over and neither is reset after
it. A reset of one side alone desynchronises the pointers and the ways; that
is a known limit, not a supported operation.

## 4. Measured

On seed 8 of `build/ae350/e1`, `pclk` 102.90 MHz and `bus_clk` 75.64 MHz, the
A25 at 750 MHz with its caches on and the video off unless stated, best of
three (entries 39 and 40):

| | serialised bridge | proposal predicted | as built |
| --- | ---: | ---: | ---: |
| one uncached 4-byte store | 59.9 cycles | ~10 | 39.9 cycles |
| dirty-line write-back, in an eviction stream | 239.2 cycles | -- | 62.8 cycles (15.7 a transfer) |
| 32-byte line stored, cached | 683.3 / 738.0 | ~40 | 180.4 to 187.1 cycles |
| 32-byte line read, cached | 501.7 / 513.3 | unchanged | 175.0 cycles |
| 32-byte line stored, D-cache off | 479.9 cycles | ~320 | 319.9 cycles |
| whole-screen 32-bit fill, video off | 105 ms | ~6.1 ms | 27 ms |
| dependent miss over 4 MiB | 503.0 cycles | -- | 437.3 cycles |

What held and what did not:

- **Posting works.** Write-backs overlap at 15.7 cycles a transfer, and a
  cached line now costs about what its fill costs (180 against 175).
- **The proposal's cache-off prediction held.** A line stored with the D-cache
  off is eight uncached transfers, 319.9 cycles, and now loses to the cache
  1.7 times; the cache-off window of `tv_dcache_save_off` no longer pays
  (AE350-010).
- **The ~40-cycle line was not reached,** because the A25 still waits for a
  store miss's fill: K = 2 to 8 fresh-line stores cost 180.0 a line each, and
  the fill is a read, which prefetch shortens but does not remove. The proposal
  had assumed the fill would vanish with posting.
- **Reads, per line, as `firmware/apps/rd_lat` measures them** (entry 35):
  sequential 549.7 ns at prefetch depth 0, 233.5 ns at depth 2 and 226.9 ns at
  depth 3; scattered 583.4 ns at every depth, slower than stage 1's 553.1 ns,
  which is not yet explained. A miss no prefetch covers waits 336 to 397 ns
  for the DDR3, of which about 140 ns is the PHY's fixed read latency and the
  controller's output register, and about 80 to 140 ns the controller's queue.
- **Scanout costs CPU stores about 30 per cent:** 234.4 cycles a line with the
  720p raster running against 180.4 without it; reads are unchanged. `LATE`
  stays at 0 or 1.

## 5. Gates

`tools/sim_ae350_ddr3.sh`, nothing on the board:

- `fpga/ae350_ddr3/tb_xfifo.v` runs the queue alone with the reader at
  100 MHz and at 40 MHz, both sides stalling, with its own checks left out so
  that the data must catch `MUT_FULL` (room promised one entry late) and
  `MUT_BYPASS` (a read handed out ahead of the write before it).
- `fpga/ae350_ddr3/tb_ahb_ddr3.v` drives `ahb_ram` and the bridge with a
  pipelined AHB master, HBURST, WRAP4 and INCR4 bursts, write storms and a
  controller model that stalls, against a byte-exact reference at
  incommensurate clocks and prefetch depths 0 to 3, and must fail `MUT_MASK`,
  `MUT_NOINVAL`, `MUT_NOPOISON`, `MUT_CLKEEP`, `MUT_SEQLINE`, `MUT_FULL` and
  `MUT_BYPASS`.
- `fpga/ae350_ddr3/tb_video.v` runs `ddr3_arb` with the video path and CPU
  traffic, checks every pixel of three frames and the TMDS symbols, and must
  fail `MUT_TAG`, `MUT_PAIR`, `MUT_DISP` and `MUT_LOAD`.

Then `tools/sim_ddr3_ctrl.sh` and `tools/sim_ddr3_lockstep.sh` for the
controller, `tools/ddr3_write.py --check` for the generated top level, a
twelve-seed sweep judged by `tools/closure_census.py`, and on the board
training at `error 0` and `d 1 b 2`, the boot ROM's tests, `ddr3_test`'s
1,022 MiB, `rd_lat`, `write_depth` and `video_test`'s flips with `LATE`.

## 6. Open

- **A lost DDR3 read** (entry 31): on an earlier image the A25 hung on a read
  whose reply never came back through the `pclk` side, mostly in the first
  hour after a long power-off, with a corrupt picture. It is deferred, not
  fixed; the STALL report and `ddr3_arb`'s `dbg` taps are the instruments.
- **Closure.** The current netlist closes every clock on three seeds of
  twelve, and seed 3, which closed with the most margin, never acknowledged a
  page flip, so a seed also needs a video check on the board (entry 35).
- **Atomics** complete only on lines already in the D-cache; the RAM port
  carries no lock or exclusive signal (AE350-011).
- **Read path stages 3 and 4**, the PHY's fixed padding and the controller's
  queue, then the crossing itself, are the measured levers on a miss, and the
  scattered-read and copy costs should be explained first.
