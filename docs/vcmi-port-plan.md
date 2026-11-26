# VCMI port plan: the first engine milestone

## Ground rule

The VCMI port runs on the AE350 as a bare-metal program loaded by the boot ROM
into the DDR3, drawn into the frame buffer at `0x7f000000`, and driven by
TinyTang's BLE keyboard and mouse frames. Nothing in this plan changes the
open-flow ground rule: the final image is still built by Yosys,
nextpnr-himbaechel and Apicula, and no script in this repository programs
hardware.

This document is a plan, not evidence. Every number in it is cited to a file,
a reference record or a measurement in `core-log.md`; where a number is missing,
the plan names the measurement that would supply it.

## What the engine demands

The inventory below was read from the pinned source, MiSTer-VCMI's
`work/vcmi-src` at commit `6901839` (VCMI 1.7.5), and from the MiSTer port's
own build with its `scripts/env.sh` and `scripts/build-vcmi.sh`.

### Build shape

C++20 (`CMakeLists.txt:275`), static link, exceptions and RTTI on. MiSTer
builds it with SDL2 2.32.10, SDL2_image 2.8.12, SDL2_mixer 2.8.1, SDL2_ttf
2.24.0, Boost 1.90, zlib, minizip-ng, oneTBB and libsquish, and turns off the
launcher, editor, lobby, tests, ffmpeg video, translations, MMAI, Discord,
InnoExtract, git version, precompiled headers, Lua and ERM. The AE350 runtime
already builds C++20 with libstdc++ and newlib for `rv32imac_zicsr_zifencei`
(ilp32, soft float) from `firmware/rt/rt.mk`, so the language and library shape
match; what does not match is everything below.

### Threads

Fourteen `std::thread` construction sites in thirteen files, of which these
matter to a single-player run: the start-up loader thread
(`clientapp/EntryPoint.cpp:309`), the local server thread
(`client/ServerRunner.cpp:52`), the client's network handler thread
(`client/CServerHandler.h:112`), the battle AI thread
(`client/battle/BattleInterface.cpp:776`), the in-game console thread
(`client/adventureMap/CInGameConsole.cpp:302`), and the server's progress
tracker (`server/CVCMIServer.cpp:266`). oneTBB appears in 26 files, mostly the
AI, the random map generator and the SDL blitters (`lib/CThreadHelper.cpp`,
`client/renderSDL/SDL_Extensions.cpp`). There are no Boost.Thread or SDL_Thread
uses. One `thread_local`-sensitive site exists in `lib/CRandomGenerator.cpp`,
which hashes `std::thread::id`.

The AE350 system wires no external interrupt source: `fpga/ae350_ddr3/ae350_sys.sv`
drives `GP_INT(16'b0)` and decodes nothing of a PLIC in the external window, and
the firmware writes `mtvec` only to report traps. Whether the hard macro's
internal machine timer can raise an interrupt is untested. A preemptive
scheduler is therefore not available on evidence today; the port must be
cooperative, yielding at mutex, condition-variable and join waits, with
CPU-bound engine threads (AI) as the risk.

### Event loop and networking

Single-player does not use sockets. `NetworkHandler::createInternalConnection`
builds an in-memory `InternalConnection` and the server never opens a port
(`lib/network/NetworkHandler.cpp:99`, `client/ServerRunner.cpp:91`).
`boost::asio::io_context` is still the event loop and timer wheel
(`lib/network/NetworkInterface.h:27`), and TCP is used only for multiplayer and
the lobby, which are out of scope. The port needs a poll-based `io_context`
replacement or a small reactor over the cycle counter, not a TCP stack.

### Filesystem

`boost/filesystem` appears in 92 files under `client` and `lib`; `std::filesystem`
in one. Boost components requested are `date_time filesystem locale
program_options`; `boost::locale` is used in one file
(`lib/texts/TextOperations.cpp`) and `boost::date_time` in one, so both can be
replaced rather than ported. minizip is used for the `.lod`/`.zip` readers and
the zip saver (`lib/filesystem/MinizipExtensions.cpp`, `lib/mapping/CMapService.cpp`).
The runtime in `firmware/rt/syscalls.c` has no files at all: `_open` and `_stat`
return `ENOENT`, `opendir` returns null. VCMI also expects to write a config
file, logs and save games, and it enumerates data directories at start-up.

### Memory and floating point

MiSTer measured about 100 to 115 MB resident at 800x600 on 492 MiB
(VCMI-002). The DDR3 offers about 1008 MiB once the video reserve and the block
RAM are removed, so capacity is not the constraint; latency is.
Floating point is used widely: `double` in 110 client and lib files, `float`
in 91, and seven of the 27 files under `client/renderSDL` using one or the
other. The A25 is built with soft float, so every one of those operations is a
library call at tens of cycles.

### SDL surface

VCMI touches 260 distinct `SDL_` symbols plus 49 `TTF_`/`IMG_`/`Mix_` symbols.
The presentation path is specific and favourable: VCMI renders into a plain
`SDL_Surface`, creates one streaming `ARGB8888` texture, and — when the
renderer calls itself `"software"` — locks that texture and makes the screen
surface alias its pixels, so a frame is drawn straight into the texture's
memory and no per-frame upload happens (`client/renderSDL/ScreenHandler.cpp`
443-461, 675-726). The port can exploit that hook twice over: the texture's
pixels are the DDR3 frame buffer, and `SDL_RenderCopy` of that texture over a
same-sized window is a page flip rather than a copy.

## What the AE350 runtime needs

1. **Threads.** A pthread-compatible shim: create/join, mutex, recursive mutex,
   condition variable, thread-local storage, and a cooperative scheduler with
   per-thread stacks in the DDR3. `std::thread`, `std::mutex` and
   `std::condition_variable` sit on top of it. Blocking waits yield; a
   CPU-bound thread that never blocks starves the rest, which the AI thread
   must be measured against, not assumed to survive.
2. **A read-only file layer.** A packed asset archive in the DDR3 plus
   `open`/`read`/`lseek`/`fstat`/`opendir`/`readdir`/`closedir` over it, so
   Boost.Filesystem and minizip work unmodified. Writes go to an in-RAM
   writable area for config and saves. Persistence of saves back to the card is
   a later cycle.
3. **An event loop.** A replacement for `boost::asio::io_context` backed by the
   cycle counter and the cooperative scheduler, carrying the in-memory
   connection and VCMI's timers. No sockets are needed for single-player.
4. **SDL2 with a `tinyvcmi` video driver.** Build SDL2 for bare metal with the
   software renderer, a window whose framebuffer is a DDR3 page, a streaming
   texture allocated in that same page, `SDL_RenderPresent` as cache write-back
   plus `TV_VID_BASE` write, a dummy audio driver, and no joystick or evdev
   backends. Input events are injected from the link frames (below).
5. **SDL_ttf, SDL_image, SDL_mixer.** FreeType and libpng are portable but add
   third-party code that must be inventoried in `THIRD_PARTY.md` under
   PROV-001. Audio is deferred; `Mix_OpenAudio` is made to fail quietly, as
   VCMI already logs that failure and continues.
6. **Time.** `SDL_GetTicks` and `_gettimeofday` already exist on the cycle
   counter. The main loop needs a sleep that does not busy-wait the whole core
   when there is nothing to draw.

## Video and the redraw budget

G0 has run on the board (`firmware/apps/vcmi_bench`, results in
`core-log.md` entry 23), and it changes what this section should say.

Measured, in 750 MHz A25 cycles per 1280x720 pixel, caches on, best of three
runs and reproducible to 0.1 cycles between runs:

| operation | cycles/pixel | full screen | so alone |
| --- | ---: | ---: | ---: |
| 32-bit fill | 92.3 | 113 ms | 8.8 fps |
| 32-bit copy | 158.3 | 195 ms | 5.1 fps |
| 8-bit indexed expand | 104.3 | 128 ms | 7.8 fps |
| 32-bit alpha blend | 165.9 | 204 ms | 4.9 fps |
| nearest 2x scale | 103.6 | 127 ms | 7.8 fps |
| fill from L1 cache | 3.2 | 4 ms | 250 fps |

The last row is the important one. A fill served from the 32 KiB L1 data cache
costs 3.2 cycles per pixel; the same fill into the DDR3 frame buffer costs
92.3. The drawing work is not arithmetic, it is the DDR3 write path, and that
path is worth 29 times more than any choice of canvas.

The arithmetic behind it: 92.3 cycles per 32-bit word is 738 cycles per
32-byte line, which at 750 MHz is a sustained **32 MB/s** of A25 stores, about
one per cent of the array's 3.2 GB/s peak. Reads through the same bridge come
to 513 cycles per line in the write-path bench, matching AE350-004's 477
closely enough that the video's reads are not measurably slowing the CPU's
stores: with the video on, a full line of stores cost 738.0 cycles and with it
off 738.0.

The follow-up bench (`firmware/apps/write_cost`, entry 24) found where that 738
goes, and the answer is not what a write-combining buffer would fix:

| stores per line | cycles per line |
| ---: | ---: |
| 8 (sequential fill) | 738.0 |
| 4 (every other word) | 739.5 |
| 1 (word 0 only) | 739.7 |
| 1 (word 7 only) | 739.7 |

Writing one word of a line costs exactly what writing all eight costs, so the
price is the line, not the store: each dirty line pays one round trip, 74 bus
clocks at 75 MHz, and the CPU's eight stores are already combined maximally by
the write-back cache. A write-combining stage inside a line therefore cannot
help. What can help is letting successive lines overlap, because today they do
not: the 738 cycles is one full round trip per line with nothing outstanding
behind it.

That makes the write path a pipelining problem, and prices it: two transfers
in flight would halve the cost and eight would divide it by eight, which is a
full-screen fill at 28 ms and 14 ms instead of 113 ms. Nothing in the
measurement promises those factors, since DDR3 refresh, bank conflicts and the
video's own share all take cuts, but the headroom is the largest in this plan.

Entry 25 tried the cheap version of this and it did not pay. A gather that
merges a line's four doublewords into one 256-bit DDR3 write was built, passed
every simulation gate, and ran on the board: writes fell 738.0 to 654.8 cycles
per line and a whole screen went 113 ms to 101 ms, but only 1 seed of 16 closed
and `bus_clk` lost about 11 MHz against the entry-18 image's 86.28. It was
reverted (`AE350-008`). The reason it bought so little is now clear and is the
useful part: a full-line write costs 656 cycles and a read 512, each essentially
one crossing round trip, so the line was never paying four round trips and
command count was never the cost. Combining within a line is a dead end;
overlapping successive lines is the live direction, and any fabric change there
has to be cheaper than 11 MHz of `bus_clk` or it will not close.

The video held up under it: LATE stayed at 1 across every run while the A25
hammered the buffer the unit was scanning out, so `ddr3_arb` gives scanout
service even at maximum CPU write rate.

### What the write path actually charges (entry 27)

`firmware/apps/write_depth` timed the crossing itself rather than the loop
around it. Every figure below is cycles per 32-byte line at 750 MHz, best of
three, and the whole table reproduced to a tenth over four runs on the same
image:

| measurement | cycles/line |
| --- | ---: |
| full line stored, D-cache on (E1) | 683.3 |
| full line read, D-cache on (E1) | 501.7 |
| one dirty line written back, no fill, no CPU stall (E2) | 239.2 |
| one store then a dependent chain of 256 cycles (E3) | 394.4 |
| K = 2, 4, 8 fresh-line stores back to back (E4) | 684.3, 684.5, 684.5 |
| one uncached word, 4 bytes (E5) | 59.9 |
| second word of the buffered line, uncached (E5) | 113.3 |
| one uncached line read (E5) | 374.9 |
| full line stored, D-cache off (E6) | 479.9 |
| half a line, D-cache off (E6) | 239.9 |

The unit is the transfer, not the line and not the byte. One uncached 32-bit
store costs 59.9 cycles, half a line costs 4 x 60, a full line costs 8 x 60,
and a dirty line's write-back costs 4 x 60 even though the CPU never touched
the bus for it. The same 60 appears whether the request comes from an uncached
CPU store or from the cache's write-back, so the charge is on the bridge side
of the boundary and not in the A25's store pipeline. RV32 has no 64-bit store,
so a line cannot be written in fewer than eight transfers from firmware, and
`E7` confirmed it: four `uint64_t` stores compiled to eight 32-bit ones and
cost exactly what eight 32-bit stores cost.

Nothing is ever in flight. A line's four write-backs cost 239.2 cycles, which
is 4 x 59.8 -- the bare transfer cost, not a pipelined fraction of it -- so the
answer to the question entry 26 left open is that the A25 keeps no write-back
outstanding at all, and successive lines do not amortise either (`E4`, flat
from K = 2 to K = 8). Each transfer waits for the toggle to come back before
the next is accepted, which is what `ahb_ddr3`'s one-outstanding-request
handshake does by construction.

The cached path pays one more thing: a fill. A line's stores miss, so the
cache reads the line from the DDR3 first, and that read costs 501.7 cycles of
stall. That is why entry 25's gather bought only 11 per cent -- it halved the
transfers in the write-back half of a 738-cycle line and left the 500-cycle
fill untouched. A full line stored with the cache bypassed costs 479.9 cycles
and no fill at all, which makes the cache itself a 203.4-cycle tax on a
write-only pass like a fill or a page clear.

What the numbers do buy is a ceiling and a target. Draw the crossing right and
a full-screen fill goes from 105 ms to 18 ms, which is 54 fps rather than 9.5;
leave it alone and the only lever is to stop paying the fill, worth 1.42 times
on its own. Compute can already hide 261 cycles of a miss (`E3`), so the
remaining cost is bandwidth-shaped and a deeper crossing is the way at it.

### The write-around path, and why it is a cache-off window (entry 28)

Stopping the fill looked like a memory-map question: mark the 16 MiB video
window non-cacheable and the fill disappears. It is not, and
`firmware/apps/pma_probe` settled that on the board (AE350-010). The A25's
machine-custom CSR window was dumped under a trap-catching handler: it holds
`mxstatus`, `mhcr`, `mhint`, `mcache_ctl`, `mcctlbgnaddr`, `mcctlcommand`,
`mcctldata`, `mmisc_ctl` and the geometry registers, and not one of them is a
memory-region or attribute control. The Zicboz and Zicbom instructions
`cbo.zero`, `cbo.clean`, `cbo.flush` and `cbo.inval` are all illegal
instructions, so a line cannot be zeroed without a fill either. The frame
buffer's range is cached exactly as ordinary DDR3 is, 661.8 and 523.4 cycles a
line to store and read against 661.7 and 523.4 at `0x40400000`, so no window of
the array is already uncached. The AE350 hard macro exposes no attribute or
region port, and neither U-Boot's AX25 cache driver nor its Andes CSR header
defines one.

What does work is turning the D-cache off around the pass. Write back and
invalidate the cache, clear its enable bit, fill a whole screen, re-enable: 480.0
and then 479.9 cycles a line against 683.1 cached, 0 bad words on every read-back,
104 ms to 73 ms a screen. The boundary is as sharp as AE350-009 predicted: a
32-byte copy under the same switch costs 1,614.9 cycles a line against 1,210.9
cached, 33 per cent worse, because an uncached read is 375 cycles a line. With
the video scanning the buffer being filled, the same pass costs 563.2 cycles a
line and `LATE` did not move, so the arbiter stays ahead of it.

That makes the lever a driver discipline rather than a memory-map choice, and a
dangerous one if done casually: the invalidation before the disable is
mandatory, since a dirty line of the buffer left in the cache would be written
back over the new data, and the pass has to be a leaf loop holding its state in
registers, because every stack access becomes a DDR3 transfer. `tinyvcmi.h`
now carries `tv_dcache_save_off` and `tv_dcache_restore` with those rules
written down.

Consequences for the port, in order of leverage:

1. **The write path is the lever, not the canvas, and combining is a dead end.**
   29 times separates cache-resident drawing from DDR3 drawing, while 1280x720
   against 800x600 separates only 2.6 times. The unit of cost is one 8-byte AHB
   transfer, 59.9 cycles, and `ahb_ddr3` allows exactly one outstanding, so a
   line costs four transfers on a write-back and eight stores uncached. The
   cached path adds a 501.7-cycle fill, which is why combining a line's
   doublewords bought only 11 per cent. Allowing more than one transfer
   outstanding is the one direction with real headroom, and it must be cheap
   enough to close against the 11 MHz the last crossing change cost.
2. **A write-only pass should bypass the cache, by turning it off.** A full line
   stored with the D-cache off costs 479.9 cycles against 683.3 with it on,
   because a write-allocate cache reads a line it is about to overwrite, and
   nothing in the A25 lets that be set per window (AE350-010). The sequence is
   write-back-and-invalidate, disable, run a leaf loop, re-enable; it is worth
   104 ms to 73 ms a screen and it is 33 per cent worse the moment the pass
   reads. Fills, page clears and opaque blits are the shapes that benefit.
3. **Draw inside the cache where possible.** Tiles, fonts and the regions an
   incremental redraw touches are nearly free when they fit in L1. VCMI's own
   dirty-rectangle discipline is what makes this usable, and it should be
   measured before it is trusted.
4. **A smaller canvas helps, but only proportionally.** At 30 fps the A25 can
   touch about 271,000 DDR3-bound pixels per frame, 29 per cent of a 1280x720
   screen. A full-screen fill at 800x600 is 59 ms and at 640x360 is 28 ms, so
   even a small canvas cannot be redrawn whole every frame.
5. **Full-screen redraws above about 9 fps are not available** at any canvas
   large enough to be worth showing, until the write path improves. Map
   scrolling that redraws the whole screen will be slow; this is the reason it
   is slow, and it is a fabric problem rather than an engine one.

So the canvas question is no longer the first question. The first question is
whether the write path can be improved, because that is what decides whether
VCMI on this board is interactive or a slideshow.

The video reserve is 16 MiB at `0x7f000000`, which holds four 1280x720
`XRGB8888` frames of 3,686,400 bytes; a double buffer costs 7.4 MiB and leaves
room for two more. A page flip is cheap: the D-cache write-back at the flip is
298 us, because only the still-dirty part of the 32 KiB cache is flushed, and
the rest of the cost is the blank wait, 11 to 15 ms, which is the display's and
not the CPU's.

## Assets

The Heroes III data now sits on the Tang's SD card, extracted from the GOG
"Heroes of Might and Magic 3 - Complete" 4.0 (3.2) installer with
`innoextract` at `/run/media/vash/TINYTANG/root/media/vcmi/data`, holding
`Data`, `Maps` and `Mp3` in the same shape MiSTer's `/media/fat/vcmi/data`
uses, so the file layer's paths carry over. `root/media` is the card's own
convention, beside `gb`, `nes`, `snes`, `ti89` and the rest. It is 224 files and
345 MiB: seven `Data` files (260 MiB, the two `.lod` bitmap and sprite archives,
the two adventure-map `.lod`s, and the three sound archives), 160 maps and 57
music tracks. Every one of the 224 files was checked against the installer's
own MD5, with no mismatch, before and again after the data was moved there.
`VIDEO.VID` (599 MiB) was deliberately left out, as MiSTer leaves it out,
because video playback is not built. The `Mp3` tracks are staged but unused
until audio lands. Nothing here is committed to the repository.

The card is vfat, so the staged names are case-insensitive on the card while
the archive this port will build is not. No two staged files differ only by
case, so the set survives the transfer, but the music mixes conventions
(`AITHEME1.MP3` beside `AITheme0.mp3`) and the archive builder must store the
names exactly as the card holds them rather than assuming VCMI's own lookup
spelling matches. Whether VCMI requests any of these files in a different case
than the GOG names is unmeasured.

The delivery rates available today are: 200 KB/s at 2 Mbaud (the rate
`exts_uart` is built for, `UART_DIV2 = 75`), and 625 KB/s or 1.25 MB/s at the
5 and 10 Mbaud TinyTang negotiates (`tang_fpga_link.h`, `tang_fpga_link_fast`).
A 345 MiB staged set is therefore 30 minutes at 2 Mbaud, 9.6 at 5 Mbaud and
4.8 at 10 Mbaud. The FPGA-side divisor is a build parameter today and would
have to become writable for the two faster rates, which is a fabric change plus
a firmware handshake, not a host-side tweak.

Two delivery options remain:

1. **Load-time images.** The existing boot protocol carries the program and any
   number of data images; the loader sends them at one rate. Simplest, needs no
   new protocol, and the board is normally powered continuously, so the DDR3
   keeps its contents between program loads and only a power cycle costs the
   reload. At 2 Mbaud the staged 260 MiB of `Data` alone is 23 minutes, which
   makes this the slowest option per power cycle but the fastest to build. Sending
   a subset of `Maps` shortens the tail without changing the mechanism.
2. **A BL616 file service.** A new frame command by which the AE350 asks the
   card for a named block and caches it in the DDR3. Best long-term behaviour,
   and it pages the data that is already staged on the card, but it is a
   TinyTang change, so it needs the user's approval and a second repository in
   scope.

## Input

TinyTang already sends both devices, and only the receiving side is missing
(INPUT-002). Command `0x16` carries six bytes (frame number, buttons, signed dx,
signed dy, signed wheel); command `0x17` carries the modifier byte and six HID
usage codes and is sent only when the report changes. The wire format is
`0xAA len_hi len_lo type payload` with the length counting the type byte, up to
2047 bytes.

The AE350 owns the UART in this image: `TV_UART_CTRL` is documented as link
mode unused and the fabric has no frame parser. TinyNES's equivalent is a link
block inside the fabric that the program enables by writing its UART control
register; it answers TinyTang's core-ID request, sends the program's writes as
text frames and hands received frames to registers. There are two ways to get
the same here. Port that behaviour as a small link block beside `exts_uart`:
proven in TinyNES, answers the core ID, and keeps console text and frames on
separate paths. Or parse the frames in firmware, which needs no fabric change
but leaves program text on the same wire and answers no core-ID request. Cycle
B should settle which with the user; the engine needs only the parsed events
either way. Two properties of the devices matter after that. The mouse is
relative and arrives at the poll rate, so the engine integrates it; the
keyboard is edge-triggered, so key repeat is the engine's job.

## Performance, and the gates that bound it

The honest comparison is MiSTer: a dual Cortex-A9 with NEON at 800x600 reaching
about 30 fps in menus and 43 to 59 fps on the map. Against that, the A25 is one
core at 750 MHz, has no vector unit, and executes soft-float. The port should
not promise a frame rate before measuring one. Three gates keep the effort
honest:

- **G0, bench before engine.** Done. `firmware/apps/vcmi_bench` measured fill,
  copy, 8-bit expand, alpha blend, 2x scale, a cache-resident fill and the
  flip, on the board, three runs each. The result is in the redraw-budget
  section above and in `core-log.md` entry 23. It moved the first question
  from the canvas to the DDR3 write path.
- **G1, SDL on the board.** SDL2 plus the `tinyvcmi` driver draw and flip a test
  pattern at 60 Hz with the A25 idle, and a second run draws the same pattern
  from the engine's blitter path. This measures the driver, not the engine.
- **G2, main menu.** VCMI boots to its main menu from a minimal data set, on
  HDMI, with measured frame time. The user's acceptance test for this
  milestone is that menu, drawn and driven by the real keyboard and mouse.

## Proposed cycles

Each cycle ends at a hardware gate and a log entry. None begins until the one
before it has a result.

0. **A. The A25's drawing cost.** Done (entries 23 and 24): the G0 bench is on
   the board, and the follow-up found the store cost is per line and serialized
   rather than per store. The DDR3 write path, not the canvas, is the limit,
   and overlapping line writes is the fix.
1. **B. The write path.** Costed, tried and measured. Combining within a line
   gave 11 per cent for 11 MHz of `bus_clk` and was reverted (entry 25); the
   crossing is one 8-byte transfer at 59.9 cycles with only one outstanding, so
   a cached line is a 501.7-cycle fill plus 239.2 of write-back (entry 27);
   and the fill cannot be avoided by memory attributes, only by turning the
   D-cache off around a store-only pass, which is measured and shipped as
   `tv_dcache_save_off` (entry 28, 104 ms to 73 ms a screen). What remains is
   the crossing itself: accepting more than one transfer at a time would change
   the 59.9-cycle charge, at a closure cost of about 11 MHz to stay inside.
2. **C. SDL and the video driver.** SDL2, SDL_image, SDL_ttf and the `tinyvcmi`
   driver; a test program that flips pages and takes injected input. Hardware:
   G1.
3. **D. The engine, to the menu.** VCMI built for `rv32imac` with MiSTer's
   option set, the internal connection over the new event loop, a minimal data
   set, and the menu on screen. Hardware: G2.
4. **E. A map.** Asset loading at scale, save and config writes in RAM, the
   battle AI thread's behaviour under cooperative scheduling, and frame-time
   measurement on the adventure map.
5. **F. The link at speed.** Programmable UART divisor and, if the user wants
   it, the BL616 file service, so a power cycle does not cost minutes of asset
   load.
6. **G. The write path's remaining cost.** Find what of the leftover is the
   controller's own and what is DDR3's share, and whether a small fabric cache
   for the canvas is worth adding on top. A fabric cache is now the more
   promising of the two, since it sidesteps the crossing entirely.

## Decisions for the user

- The write path, now that the crossing and the cache are both measured: build
  the deeper crossing that lets more than one 8-byte transfer be outstanding,
  add a small fabric cache for the canvas, or leave the fabric alone now that
  the write-around window is available. Recommended: the deeper crossing, since
  it is the only lever that changes the 59.9-cycle charge and the write-around
  window has already taken the cheaper 1.42 times; the fabric cache stays the
  fallback if the crossing will not close inside 11 MHz.
- Canvas: native 1280x720, or a smaller internal canvas upscaled in the fabric.
  Recommended: the G0 result makes the write path the first question; the
  canvas is a proportional 2.6 times, so decide it after the write path is
  costed, and keep the engine at 1280x720 until then.
- Assets: the data is staged and verified on the card at
  `root/media/vcmi/data`; what remains open is whether the first milestone loads
  it whole at boot or pages it from the card through a BL616 file service.
  Recommended: load `Data` and the chosen maps at boot first, and add the file
  service when the load time starts to cost real cycles. At the current 2 Mbaud
  a full boot-time send is about 30 minutes, which is the argument for the file
  service sooner rather than later.
- Whether TinyTang firmware changes are in scope, which only the link-at-speed
  cycle needs.
- Audio: deferred in this plan; say now if it is not deferrable.
- A frame-rate floor for acceptance, so "visibly running" has a number.
