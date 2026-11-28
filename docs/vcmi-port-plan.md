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
A recount on 2026-11-27 at the same commit, matching identifiers in every
`.cpp` and `.h`, gave 266 `SDL_` and the same 49, of which 21 are `TTF_` and
only three are `IMG_` (`IMG_Load_RW`, `IMG_SavePNG`, `IMG_GetError`); the
renderer alone, `client/renderSDL`, uses 159 `SDL_` and `TTF_` identifiers.
The presentation path is specific and favourable: VCMI renders into a plain
`SDL_Surface`, creates one streaming `ARGB8888` texture, and — when the
renderer calls itself `"software"` — locks that texture and makes the screen
surface alias its pixels, so a frame is drawn straight into the texture's
memory and no per-frame upload happens (`client/renderSDL/ScreenHandler.cpp`
443-461, 675-726). The port can exploit that hook twice over: the texture's
pixels are the DDR3 frame buffer, and `SDL_RenderCopy` of that texture over a
same-sized window is a page flip rather than a copy.

## What the AE350 runtime needs

1. **Threads.** Built (entry 49): `firmware/rt/pthread.c` is a cooperative
   POSIX thread layer (threads on 1 MiB DDR3 stacks, plain, recursive and
   error-checking mutexes, condition variables, reader-writer locks, keys,
   once routines, sleeps and the monotonic and real-time clocks on the cycle
   counter), and `tools/build_toolchain_threads.sh` builds GCC 15.2.0's
   libgcc and libstdc++ with POSIX threads on it, used by programs that set
   `RT_THREADS := 1`. `firmware/apps/thread_test` passes every facility VCMI
   uses on the board, a create and join costing about 3.4 us. Blocking waits
   yield; a CPU-bound thread that never blocks starves the rest, which the
   AI thread must be measured against, not assumed to survive. The first
   thread keeps crt0's 64 KiB block-RAM stack, so the engine's main should
   run on a thread of its own with a larger one.
2. **A read-only file layer.** Built (entry 47): `firmware/rt/card.c` gives
   `open`/`read`/`lseek`/`fstat`/`stat`/`opendir`/`readdir`/`closedir` for
   paths under `/card`, read from the SD card through TinyTang's card file
   service (PROT-005) with 4 MiB of 64 KiB read cache in the DDR3, so
   Boost.Filesystem and minizip can work unmodified. Writes still need an
   in-RAM writable area for config and saves; the card layer refuses them with
   `EROFS`. Persistence of saves back to the card is a later cycle.
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
7. **Atomics only on resident lines.** On this A25 an atomic completes only
   on a line already in the D-cache (AE350-011, entry 38): an AMO on a line
   that is not there, or any AMO with the D-cache off, never returns, and LR on
   such a line returns its value without bringing the line in, so every SC
   after it fails. `std::atomic`'s read-modify-writes compile to AMOs and
   VCMI uses `std::atomic`, so, by the user's choice (entry 41), everything
   runtime programs link is built without the A extension: `rt.mk` and
   `tools/build_sdl2.sh` default to `rv32imc_zicsr_zifencei`, the toolchain's
   `rv32imc` newlib and libstdc++ are linked, every atomic goes through
   `firmware/rt/atomic.c` as a read-modify-write with interrupts masked, and
   the link fails an image with any AMO, LR or SC in it. `atomic_test`
   verified every `std::atomic` operation VCMI uses on evicted lines, at 20
   to 30 cycles a call, and neither oneTBB 2022.3.0 nor the Boost libraries
   VCMI uses ask whether atomics are lock-free. The engine and its libraries
   must be built the same way.
8. **Fences.** A fence that orders writes costs 1,170 to 1,500 cycles on this
   A25 once there has been a memory access before it (AE350-012), and GCC puts
   one around every `seq_cst` atomic load and store and before every release
   store, with or without the A extension. `atomic.c` needs none, but those
   inline fences will be in the engine, and how often it reaches them must be
   measured before deciding whether to remove them, by building with the
   Ztso extension's mapping or by weakening the engine's memory orders.

## Video and the redraw budget

The A25 draws into a 32-bit frame buffer in the DDR3, so what a frame costs is
set by the A25's path to the DDR3, and that path has been rebuilt since G0 first
priced it: writes are posted through an ordered queue (entry 30), sequential
reads are answered from a line buffer at zero wait (entry 33), and a four-way
read buffer fetches ahead (entry 35). `docs/ahb-bridge-design.md` describes the
bridge as built. The figures below are from seed 8 of `build/ae350/e1`,
re-measured on 2026-11-27 (entries 39 and 40), in 750 MHz A25 cycles, caches
on, best of three runs.

### What drawing costs now

Per 1280x720 pixel, `firmware/apps/vcmi_bench`, with the raster scanning the
same array:

| operation | first image (entry 23) | now | full screen now | so alone |
| --- | ---: | ---: | ---: | ---: |
| 32-bit fill | 92.3 | 29.2 | 36.0 ms | 27.8 fps |
| 32-bit copy | 158.3 | 118.4 | 145.6 ms | 6.9 fps |
| 8-bit indexed expand | 104.3 | 59.6 | 73.3 ms | 13.6 fps |
| 32-bit alpha blend | 165.9 | 152.4 | 187.3 ms | 5.3 fps |
| nearest 2x scale | 103.6 | 56.6 | 69.6 ms | 14.4 fps |
| fill from L1 cache | 3.2 | 3.0 | 3.8 ms | 264 fps |

A page flip's D-cache write-back is now about 100 us, against 298 us, and the
rest of a flip is the wait for vertical blank. Through SDL2's software
renderer a full screen of fills costs 66.5 ms a frame (entry 38), because the
renderer rasterises its queued rectangles at present time.

Per 32-byte line, `firmware/apps/write_cost` and `firmware/apps/write_depth`
with the raster off:

| measurement | first image (entries 24, 27) | now |
| --- | ---: | ---: |
| full line stored, D-cache on | 738.0 / 683.3 | 180.4 to 187.1 |
| the same with the raster scanning | 738.0 | 234.4 |
| full line read, D-cache on | 513.3 / 501.7 | 175.0 |
| one store to each of K = 2, 4, 8 fresh lines | 684.5 | 180.0 |
| dirty line written back in an eviction stream | 239.2 | 62.8 |
| one uncached 4-byte store | 59.9 | 39.9 |
| one uncached 4-byte read | 374.9 | 131.2 |
| full line stored, D-cache off | 479.9 | 319.9 |

What changed, and what it means:

1. **A cached line now costs about what its fill costs.** A full-line store,
   180 cycles, is a line read, 175, plus a few cycles: the write-back is
   posted and overlaps (62.8 cycles a line in an eviction stream, 15.7 a
   transfer, so several are in flight), and the fill is answered from the
   read buffer's prefetch. The cost is still per line and not per store: one
   store to a line costs 180.0, eight cost 180.4.
2. **The cache-off write-around window no longer pays; keep the D-cache on.**
   Entry 28's window won only because a cached store paid a 501.7-cycle fill.
   Now a write-only pass costs 187.1 cycles a line cached and 319.9 with the
   D-cache off, 27 ms a screen against 49 ms (`firmware/apps/pma_probe`), and
   a copy is worse uncached too, 1,020.0 against 881.8. `tv_dcache_save_off`
   stays in `tinyvcmi.h` for the probes that measure it, and no driver should
   use it for speed (AE350-010).
3. **Scanout costs stores about 30 per cent.** The same full-line store is
   180.4 cycles with the raster off and 234.4 with it scanning, and a
   whole-screen fill is 27 ms without it (`pma_probe`, `video_test`'s 27.8 ms)
   against 36.0 ms with it (`vcmi_bench`); reads are not measurably slowed.
   `LATE` stays at 0 or 1 through all of it, so the arbiter keeps scanout
   ahead of the CPU.
4. **Reads are now the expensive half of drawing.** A fill is 29.2 cycles a
   pixel but a copy is 118.4 and an alpha blend 152.4: those passes read a
   source and, for the blend, the destination, and a read that prefetch does
   not cover still waits 336 to 397 ns for the DDR3. Scattered reads gain
   nothing from prefetch (583.4 ns a line at every depth, `rd_lat`), and why a
   copy costs about four fills is not yet explained.
5. **Draw inside the cache where possible.** Cache-resident drawing is still
   ten times cheaper than a fill into the DDR3 and forty times cheaper than a
   copy: tiles, fonts and the regions an incremental redraw touches are nearly
   free when they fit in the 32 KiB L1. VCMI's own dirty-rectangle discipline
   is what makes this usable, and it should be measured before it is trusted.
6. **A smaller canvas helps proportionally, and the full screen is now
   reachable for fills.** At 30 fps the A25 can fill about 856,000 DDR3-bound
   pixels a frame with the raster on, 93 per cent of a 1280x720 screen; a
   full-screen fill is 18.7 ms at 800x600 and 9.0 ms at 640x360. A full-screen
   copy or blend each frame is still out of reach at any canvas worth showing,
   so map scrolling that redraws the whole screen will be slow, and the read
   path is now where that is decided.

So the canvas question is still not the first question, but it is closer: the
write path is no longer the limit, and what bounds an interactive frame now is
how much of it reads the DDR3.

### How the figures got here

G0 (entry 23) first found drawing bound by the write path, at 92.3 cycles a
pixel for a fill. `write_cost` (entry 24) showed the price was per line, not
per store; a gather that merged a line's doublewords into one DDR3 write bought
11 per cent and was reverted (entry 25, AE350-008); `write_depth` (entry 27)
found the unit was one 8-byte AHB transfer at 59.9 cycles with none ever
outstanding, plus a 501.7-cycle read-allocate fill (AE350-009); and with no
memory-attribute register on the A25, turning the D-cache off around a
write-only pass was the only way past the fill, worth 104 ms to 73 ms a screen
at the time (entry 28, AE350-010). The bridge rewrite then removed both the
one-outstanding crossing and most of the fill's cost, which is why item 2 above
reverses entry 28's advice.

The video reserve is 16 MiB at `0x7f000000`, which holds four 1280x720
`XRGB8888` frames of 3,686,400 bytes; a double buffer costs 7.4 MiB and leaves
room for two more.

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

The data is delivered by a card file service, chosen over a whole load at boot
(about 30 minutes at 2 Mbaud) and built in entries 46 and 47. In 2-wire mode a
program run by TinyTang's `ae350run` asks for a stat, a directory page or a
range of up to 64 KiB of a file under `root/media/vcmi` by one text line, and
TinyTang answers in the boot ROM's load protocol (PROT-005). On the board it
reads `H3bitmap.lod`'s header, its 4,908-entry table and two entries
byte-exact against the host's copy, and the first MiB at 240 KB/s from the card
and in 121 ms from the cache (`firmware/apps/card_test`). VCMI 1.7.5's `config` and
`Mods` sit beside the data in `data/config` and `data/Mods`, as MiSTer lays
them out, copied from the pinned source with `tools/tang_put_tree.py` and read
back equal (entry 48). `ae350run` runs a TinyVCMI program anywhere in the DDR3
up to `0x7fff0000` from TinyTang `c46548b` (PROT-004), which
`firmware/apps/big_test`, a 35.7 MB image, proves.

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
  Passed (entries 38 and 42): `firmware/apps/sdl_test` draws and flips with
  the shown page checked on every frame, at 66.5 ms a frame through the
  renderer, rather than 60 Hz because each frame redraws the whole screen, and
  at 183.4 ms through VCMI's own path (a streaming texture aliased by the
  screen surface, SDL's blitter, `SDL_RenderCopy` and `SDL_RenderPresent`):
  58.0 ms of drawing, 123.9 ms of `SDL_RenderCopy` copying the whole texture
  onto the window surface, and 1.5 ms of present. VCMI keeps that screen
  surface and redraws only what changed (`WindowHandler::simpleRedraw`), so
  its frame cannot be a two-page flip. The texture is now the shown page
  itself, single-buffered (entry 43, `sdl2-tinyvcmi-zerocopy.patch`): the copy
  is skipped, a full redraw costs 57.1 ms and an update of one 128-pixel box
  3.05 ms, and the picture tears only while the whole screen is being
  redrawn; the user saw the update pass clean.
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
1. **B. The write path.** Done. Combining within a line was tried and reverted
   (entry 25), the crossing was found to be one 8-byte transfer at 59.9 cycles
   with none outstanding (entry 27), and the bridge was rebuilt as an ordered
   queue with posted writes (entry 30) and a read path with a zero-wait line
   buffer and a four-way prefetching read buffer (entries 33 and 35). A
   full-line store went from 738.0 to 180.4 cycles and a whole-screen fill
   from 113 ms to 36.0 ms; the cache-off window of entry 28 is now slower than
   the cache and is not to be used for speed.
2. **C. SDL and the video driver.** In progress: SDL2 2.32.10 draws and flips
   on the board (entries 37 and 38), and SDL2_ttf 2.24.0 and SDL2_image
   2.8.12 render VCMI's Noto font and round-trip PNG, BMP and JPEG there
   (entry 44, `firmware/apps/ttf_test`); injected input remains. SDL2 first,
   then SDL_ttf and a minimal
   SDL_image, with the `tinyvcmi` driver and a test program that flips pages
   and takes injected input. Hardware: G1. As MiSTer does, SDL2 is the
   upstream library and not a shim: MiSTer vendors SDL2 2.32.10, SDL2_ttf
   2.24.0, SDL2_image 2.8.12 and SDL2_mixer 2.8.1 and patches them
   (`MiSTer-VCMI/work/src`, `sdl-driver/*.patch`), and this port builds the
   same SDL2 release from its pinned tarball with `tools/build_sdl2.sh` and the
   patches in `firmware/sdl` (entry 37). SDL_image need decode only what
   `IMG_Load_RW` is handed. The image size is a budget from the start:
   `sdl_test` is 567 KB of text, mostly `libSDL2.a`, and loads in 3.1 s at
   2 Mbaud (185 KB/s), so the engine's load time over the link scales with
   what it links and belongs to cycle F's question.
3. **D. The engine, to the menu.** VCMI built for `rv32imac` with MiSTer's
   option set, the internal connection over the new event loop, a minimal data
   set, and the menu on screen. Hardware: G2.
4. **E. A map.** Asset loading at scale, save and config writes in RAM, the
   battle AI thread's behaviour under cooperative scheduling, and frame-time
   measurement on the adventure map.
5. **F. The link at speed.** Programmable UART divisor and register `0x1C`, so
   the file service (built in entry 47) and program loads run at 5 or 10 Mbaud
   instead of 2.
6. **G. The read path's remaining cost.** Reads are now the expensive half of
   drawing: a copy costs about four fills and an alpha blend five, a miss that
   prefetch does not cover still waits 336 to 397 ns, and scattered reads gain
   nothing from prefetch and are slower than before the read buffer (583.4
   against 553.1 ns a line). The read path redesign's stages 3 (the PHY's
   fixed padding and the controller's queue) and 4 (the crossing) are the
   measured levers, and a copy's cost should be explained before either is
   built.

## Decisions for the user

- Fences in the engine (AE350-012): leave GCC's inline fences, build with
  the Ztso mapping, or weaken the engine's memory orders. Recommended: decide
  after the engine runs, from a count of the fences it actually executes.
- Read path stages 3 and 4 before or after the engine's first light.
  Recommended: after G1's second half, which measures the texture path VCMI
  uses and so says how much of a real frame is reads.
- Canvas: native 1280x720, or a smaller internal canvas upscaled in the fabric.
  Recommended: keep the engine at 1280x720. A full-screen fill now runs at
  27.8 fps with the raster on, and a smaller canvas buys only its pixel ratio,
  2.6 times at 800x600; decide it from the engine's measured frame time.
- Audio: deferred in this plan; say now if it is not deferrable.
- A frame-rate floor for acceptance, so "visibly running" has a number.
