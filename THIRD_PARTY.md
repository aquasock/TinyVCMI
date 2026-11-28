# Third-party components

What TinyVCMI imports from elsewhere, under what licence, and what is
obliged in return. TinyVCMI itself is GPL-3.0-only (`LICENSE`); components
below keep their own licences, and that is recorded here per PROV-001.

Nothing in this file is copied code unless it says so. Measurements, interfaces
and design lessons taken from sibling projects are recorded in
`.ai/core-reference.md` and carry no licence obligation.

---

## SDL2 2.32.10

- **Use:** the engine's presentation layer. VCMI 1.7.5 draws through SDL2's
  software renderer (VCMI-004), so cycle C of the port plan vendors SDL2
  rather than writing a renderer.
- **Licence:** zlib. SDL2 is not GPL, and linking it does not change this
  project's licence. The files this project adds to SDL's build carry
  `SPDX-License-Identifier: Zlib` in their headers.
- **Not committed:** SDL's source is fetched by `tools/build_sdl2.sh` and
  unpacked under `build/sdl/`, which is ignored. Only this project's own
  additions live in `firmware/sdl/`.
- **Source:** <https://github.com/libsdl-org/SDL>, release
  `release-2.32.10`. The tarball's SHA-256 is pinned in
  `tools/build_sdl2.sh`.
- **Modifications:** three patches, all in `firmware/sdl/`, each carrying a
  TinyVCMI comment at the point of change:
  - `sdl2-riscv-atomics.patch` — `src/atomic/SDL_spinlock.c` gains an RV32A
    `amoswap.w.aq` branch for `SDL_AtomicTryLock`.
  - `sdl2-baremetal-dynapi.patch` — `src/dynapi/SDL_dynapi.h` disables the
    dynamic API for bare-metal RISC-V, as SDL does for PS2, PSP and RISC OS.
  - `sdl2-tinyvcmi-bootstrap.patch` — `src/video/SDL_video.c` declares and
    registers the `tinyvcmi` driver in SDL's bootstrap table.

## SDL2 drivers written for this project

`firmware/sdl/SDL_tinyvcmivideo.c`, `SDL_tinyvcmivideo.h` and
`SDL_systimer_tinyvcmi.c` implement SDL's platform interfaces for the AE350.
They are this project's code, written against SDL's driver contract, and are
released under the zlib licence so that they can be compiled as part of SDL;
they are not derived from any SDL driver's source.

`firmware/sdl/SDL_config_tinyvcmi.h` and `SDL_config.h` configure SDL for
`rv32imac` bare metal. `SDL_config_minimal.h` in SDL's own tree was read as a
starting point for which `HAVE_*` macros matter; the file is otherwise this
project's.

## Prior art consulted, not imported

- **MiSTer-VCMI** (`76e1e1c`, `sdl-driver/mister/SDL_mistervideo.c`) showed
  that the cheap shape is SDL's software renderer plus a window-framebuffer
  driver rather than a hand-written renderer. No code was taken from it; the
  driver here is written against SDL's headers. MiSTer-VCMI is GPL; the
  finding is recorded as a fact in `.ai/core-reference.md` and this log.
- **VCMI 1.7.5** (`6901839`) is read for its interface expectations
  (VCMI-004, VCMI-005) and is not redistributed here.
