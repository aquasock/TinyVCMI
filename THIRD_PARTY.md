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
- **Modifications:** four patches, all in `firmware/sdl/`, each carrying a
  TinyVCMI comment at the point of change:
  - `sdl2-riscv-atomics.patch` — `src/atomic/SDL_spinlock.c` gains an RV32A
    branch for `SDL_AtomicTryLock`: an ordinary load of the lock word, then
    `lr.w.aq`/`sc.w`, on every pass, because this A25 completes an atomic
    only on a line already in its D-cache (AE350-011). Entry 37's version, one
    `amoswap.w.aq`, hung on such a miss. The branch is used only by a build
    with the A extension: the default build is `rv32imc`, where
    `SDL_config_tinyvcmi.h` sets `HAVE_GCC_ATOMICS` and SDL's atomics go
    through `firmware/rt/atomic.c`.
  - `sdl2-baremetal-dynapi.patch` — `src/dynapi/SDL_dynapi.h` disables the
    dynamic API for bare-metal RISC-V, as SDL does for PS2, PSP and RISC OS.
  - `sdl2-tinyvcmi-bootstrap.patch` — `src/video/SDL_video.c` declares and
    registers the `tinyvcmi` driver in SDL's bootstrap table.
  - `sdl2-tinyvcmi-zerocopy.patch` — `src/render/software/SDL_render_sw.c`,
    for the `tinyvcmi` driver only, makes a window-sized streaming texture
    over the window surface's own pixels and skips a copy of such a texture
    onto itself, so that VCMI's screen is drawn straight into the shown page.

## SDL2_ttf 2.24.0, with FreeType 2.13.2

- **Use:** VCMI's TrueType fonts (`config/fonts.json`), opened with
  `TTF_OpenFontRW` and drawn solid and blended.
- **Licence:** SDL2_ttf is zlib. FreeType, which the SDL2_ttf release vendors
  under `external/freetype`, is dual-licensed under its FreeType License or
  the GNU GPL version 2 or any later version; TinyVCMI uses it under the
  GPL, which version 3 of satisfies. HarfBuzz, also vendored, is not built.
- **Not committed:** fetched by `tools/build_sdl2_addons.sh` from
  <https://github.com/libsdl-org/SDL_ttf>, release `release-2.24.0`, the
  tarball's SHA-256 pinned in the script, and built under `build/sdl/`.
- **Modifications:** none to either source. FreeType's module list and
  options are TinyVCMI's own headers, `firmware/sdl/freetype/`, selected
  with FreeType's `FT_CONFIG_MODULES_H` and `FT_CONFIG_OPTIONS_H`: the
  TrueType driver, sfnt, psnames, the auto-hinter and the two rasterisers,
  without zlib, bzip2, PNG, Brotli or HarfBuzz.

## SDL2_image 2.8.12

- **Use:** VCMI's `IMG_Load_RW` for every image that is not an H3 PCX, and
  `IMG_SavePNG` for screenshots.
- **Licence:** zlib. Its bundled decoders and encoders keep their own
  licences: `stb_image.h` and `tiny_jpeg.h` public domain, `miniz.h` public
  domain (Unlicense), `nanosvg.h` and `nanosvgrast.h` zlib, `qoi.h` MIT.
- **Not committed:** fetched by `tools/build_sdl2_addons.sh` from
  <https://github.com/libsdl-org/SDL_image>, release `release-2.8.12`, the
  tarball's SHA-256 pinned, and built under `build/sdl/`.
- **Modifications:** none. Built as MiSTer-VCMI builds it: the stb backend
  for PNG and JPEG, CMake's default formats, AVIF, JXL, TIFF and WebP off.

## Noto Sans Medium (test data, not distributed)

`tools/build_sdl2_addons.sh` fetches `NotoSans-Medium.ttf` from VCMI at
commit `6901839`, its SHA-256 pinned, into `build/sdl/fonts/` for
`firmware/apps/ttf_test`, which embeds it in a test program run on the
board. The font is Google's, under the SIL Open Font License 1.1, and is not
committed to this repository.

## SDL2 drivers written for this project

`firmware/sdl/SDL_tinyvcmivideo.c`, `SDL_tinyvcmivideo.h` and
`SDL_systimer_tinyvcmi.c` implement SDL's platform interfaces for the AE350.
`firmware/sdl/SDL_trace_tinyvcmi.c` is a GCC `-finstrument-functions` hook
linked only into the diagnostic build that `SDL_TRACE=1 tools/build_sdl2.sh`
makes.
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
