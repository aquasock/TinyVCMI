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

The video reserve is 16 MiB at `0x7f000000`, which holds four 1280x720
`XRGB8888` frames of 3,686,400 bytes; a double buffer costs 7.4 MiB and leaves
room for two more. A whole-screen redraw by the A25 costs about 105 ms, and the
figure is consistent with AE350-004: 115,200 cache lines of stores at 662.6
cycles each is about 102 ms at 750 MHz. So a screen drawn whole cannot exceed
about 9.5 frames a second before any drawing work, and VCMI redraws all active
objects each frame.

Two levers exist and the plan proposes both be measured before choosing:

- **Double-buffered direct drawing.** Draw into the frame buffer through the
  aliased surface and flip at the blank. This removes every copy the MiSTer
  port had to fight; the remaining cost is VCMI's own blitters.
- **A smaller internal canvas.** VCMI at 800x600 draws 52 per cent of the
  pixels. MiSTer measured 1024x600 as about 44 per cent more CPU per frame than
  800x600. If the A25 needs the margin, the engine renders 800x600 or 1024x600
  and the fabric line buffer duplicates rows to the 1280x720 output, which the
  existing `vid_pix` line buffers can do without a new memory path.

No conclusion is drawn here: the number that decides is the A25's own.

## Assets

The Heroes III data is the user's own copy and must be measured, not assumed.
The delivery rates available today are: 200 KB/s at 2 Mbaud (the rate
`exts_uart` is built for, `UART_DIV2 = 75`), and 625 KB/s or 1.25 MB/s at the
5 and 10 Mbaud TinyTang negotiates (`tang_fpga_link.h`, `tang_fpga_link_fast`).
A 300 MB data set is therefore 25 minutes at 2 Mbaud, 8 minutes at 5 Mbaud and
4 minutes at 10 Mbaud. The FPGA-side divisor is a build parameter today and
would have to become writable for the two faster rates, which is a fabric
change plus a firmware handshake, not a host-side tweak.

Options, to be decided by the user:

1. **Load-time images.** The existing boot protocol carries the program and any
   number of data images; the loader sends them at one rate. Simplest, needs no
   new protocol, and the board is normally powered continuously, so the DDR3
   keeps its contents between program loads and only a power cycle costs the
   reload.
2. **A subset first.** One map, its defs, menus and fonts. Directly measures
   GAP-003 and keeps the first milestone's load in the tens of megabytes.
3. **A BL616 file service.** A new frame command by which the AE350 asks the
   card for a named block and caches it in the DDR3. Best long-term behaviour,
   but it is a TinyTang change, so it needs the user's approval and a second
   repository in scope.

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

- **G0, bench before engine.** A firmware app that times a 1280x720 fill, an
  8-bit-to-32-bit blit with alpha, a scaled blit, and a 32-bit alpha blit of
  the size VCMI's frame uses, each in cycles per pixel, cached. This decides
  the canvas size and predicts the frame rate within a small factor.
- **G1, SDL on the board.** SDL2 plus the `tinyvcmi` driver draw and flip a test
  pattern at 60 Hz with the A25 idle, and a second run draws the same pattern
  from the engine's blitter path. This measures the driver, not the engine.
- **G2, main menu.** VCMI boots to its main menu from a minimal data set, on
  HDMI, with measured frame time. The user's acceptance test for this
  milestone is that menu, drawn and driven by the real keyboard and mouse.

## Proposed cycles

Each cycle ends at a hardware gate and a log entry. None begins until the one
before it has a result.

1. **B. Runtime foundation.** Cooperative pthread shim, archive-backed files,
   link-mode input receiver, and the G0 bench. Hardware: G0 numbers.
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

## Decisions for the user

- Canvas: native 1280x720, or a smaller internal canvas upscaled in the fabric.
  Recommended: measure G0 first and decide with the numbers; the engine code is
  identical either way.
- Assets: which copy of the data is authoritative, and which of the three
  delivery options above is wanted for the first milestone.
- Whether TinyTang firmware changes are in scope, which only the link-at-speed
  cycle needs.
- Audio: deferred in this plan; say now if it is not deferrable.
- A frame-rate floor for acceptance, so "visibly running" has a number.
