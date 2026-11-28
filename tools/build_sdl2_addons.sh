#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build SDL2_ttf 2.24.0, with its vendored FreeType 2.13.2, and SDL2_image
# 2.8.12 for the AE350: rv32imc, bare metal, newlib, no OS.
#
#   build_sdl2_addons.sh [OUT_DIR]   default build/sdl, after build_sdl2.sh
#   SDL_MARCH=<arch> ...             as build_sdl2.sh (default rv32imc)
#
# VCMI 1.7.5 needs both (VCMI-005): SDL_ttf for its TrueType fonts
# (config/fonts.json, the Noto fonts in Mods/vcmi), SDL_image for
# IMG_Load_RW of every image that is not an H3 PCX and IMG_SavePNG for
# screenshots.  The options follow MiSTer-VCMI's build of the same releases
# (scripts/build-deps.sh): SDL_ttf with the vendored FreeType and no
# HarfBuzz; SDL_image with the stb backend, so PNG and JPEG need no libpng
# or libjpeg, and without AVIF, JXL, TIFF and WebP.  FreeType's module list
# and options are TinyVCMI's (firmware/sdl/freetype), chosen through
# FT_CONFIG_MODULES_H and FT_CONFIG_OPTIONS_H, so its source is not patched.
#
# Also fetches NotoSans-Medium.ttf from VCMI at the pinned commit into
# OUT_DIR/fonts, for firmware/apps/ttf_test; it is not committed.
#
# Digests measured locally on 2026-11-27 and equal to MiSTer-VCMI's
# independent downloads of the same files; if a download has changed, the
# script stops.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out=${1:-$root/build/sdl}
ttf_ver=2.24.0
img_ver=2.8.12
sdl=SDL2-2.32.10
ttf_url="https://github.com/libsdl-org/SDL_ttf/releases/download/release-$ttf_ver/SDL2_ttf-$ttf_ver.tar.gz"
img_url="https://github.com/libsdl-org/SDL_image/releases/download/release-$img_ver/SDL2_image-$img_ver.tar.gz"
font_url="https://raw.githubusercontent.com/vcmi/vcmi/6901839ae9760dfcd1d5ff2c4aa4ef6968fee752/Mods/vcmi/Content/Data/NotoSans-Medium.ttf"
ttf_digest=0b2bf1e7b6568adbdbc9bb924643f79d9dedafe061fa1ed687d1d9ac4e453bfd
img_digest=393f5efb50536ec13ca4f4affb69cc9966d3c3f969e6c5e701faddf9f9785381
font_digest=deacd1a2242fdd248ca7625e0fb96fb5ecea86500af20be431647d8d9bbd3388
source "$root/tools/openflow_env.sh" >/dev/null 2>&1 || true
cross=${RISCV_BIN:-$HOME/tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin}/riscv-none-elf-
cc=${cross}gcc
ar=${cross}ar
[[ -x $cc ]] || { echo "missing $cc" >&2; exit 2; }
[[ -d $out/$sdl/include ]] || {
    echo "no $out/$sdl: run tools/build_sdl2.sh $out first" >&2; exit 2; }
cd "$out" || exit 1

fetch() {    # url file digest
    local url=$1 file=$2 digest=$3 got
    if [[ ! -f $file ]]; then
        echo "fetching $file"
        mkdir -p "$(dirname "$file")"
        curl -sL -o "$file" "$url" || { echo "download of $file failed" >&2; exit 1; }
    fi
    got=$(sha256sum "$file" | cut -d' ' -f1)
    [[ $got == "$digest" ]] || { echo "$file digest $got, expected $digest" >&2; exit 1; }
}
fetch "$ttf_url" "SDL2_ttf-$ttf_ver.tar.gz" "$ttf_digest"
fetch "$img_url" "SDL2_image-$img_ver.tar.gz" "$img_digest"
fetch "$font_url" fonts/NotoSans-Medium.ttf "$font_digest"
[[ -d SDL2_ttf-$ttf_ver ]] || tar xzf "SDL2_ttf-$ttf_ver.tar.gz" || exit 1
[[ -d SDL2_image-$img_ver ]] || tar xzf "SDL2_image-$img_ver.tar.gz" || exit 1

march=${SDL_MARCH:-rv32imc_zicsr_zifencei}
port=$root/firmware/sdl
arch="-march=$march -mabi=ilp32 -O2 -g -ffunction-sections -fdata-sections"
sdl_inc="-I$port -I$sdl/include"
fail=0
compile() {    # object source flags...
    local o=$1 f=$2
    shift 2
    if ! $cc $arch "$@" -w -c -o "$o" "$f" 2>"logs/addons_$(basename "$o").log"; then
        echo "FAILED: $f"; sed -n '1,5p' "logs/addons_$(basename "$o").log"; fail=1
    fi
}
mkdir -p logs

# FreeType: the base, the files SDL_ttf calls into (bitmap, glyph, stroker,
# synthetic bold) and the modules ftmodule_tinyvcmi.h lists.
ft=SDL2_ttf-$ttf_ver/external/freetype
ft_flags="-DFT2_BUILD_LIBRARY -I$port/freetype -I$ft/include
          -DFT_CONFIG_MODULES_H=<ftmodule_tinyvcmi.h>
          -DFT_CONFIG_OPTIONS_H=<ftoption_tinyvcmi.h>"
rm -rf obj_ttf obj_img && mkdir -p obj_ttf obj_img
for f in base/ftsystem base/ftinit base/ftdebug base/ftbase base/ftbbox \
         base/ftbitmap base/ftglyph base/ftstroke base/ftsynth base/ftgasp \
         base/ftmm base/ftfstype autofit/autofit truetype/truetype sfnt/sfnt \
         psnames/psnames smooth/smooth raster/raster; do
    # shellcheck disable=SC2086
    compile "obj_ttf/ft_${f//\//_}.o" "$ft/src/$f.c" $ft_flags
done
# shellcheck disable=SC2086
compile obj_ttf/SDL_ttf.o "SDL2_ttf-$ttf_ver/SDL_ttf.c" $sdl_inc -I"$ft/include" \
    -DFT_CONFIG_MODULES_H='<ftmodule_tinyvcmi.h>' \
    -DFT_CONFIG_OPTIONS_H='<ftoption_tinyvcmi.h>' -I"$port/freetype"

# SDL_image: CMake's default formats with the stb backend, as MiSTer builds it.
img=SDL2_image-$img_ver
img_flags="-DUSE_STBIMAGE -DLOAD_BMP -DLOAD_GIF -DLOAD_JPG -DLOAD_LBM -DLOAD_PCX
           -DLOAD_PNG -DLOAD_PNM -DLOAD_QOI -DLOAD_SVG -DLOAD_TGA -DLOAD_XCF
           -DLOAD_XPM -DLOAD_XV -DSDL_IMAGE_SAVE_JPG=1 -DSDL_IMAGE_SAVE_PNG=1
           -I$img/include -I$img/src"
for f in "$img"/src/IMG*.c; do
    [[ $f == */IMG_WIC.c ]] && continue    # Windows only
    # shellcheck disable=SC2086
    compile "obj_img/$(basename "$f" .c).o" "$f" $sdl_inc $img_flags
done

[[ $fail == 0 ]] || { echo "SDL2 add-ons build failed" >&2; exit 1; }
rm -f libSDL2_ttf.a libSDL2_image.a
$ar rcs libSDL2_ttf.a obj_ttf/*.o || exit 1
$ar rcs libSDL2_image.a obj_img/*.o || exit 1
echo "libSDL2_ttf.a $(stat -c%s libSDL2_ttf.a) bytes, $(ls obj_ttf/*.o | wc -l) objects"
echo "libSDL2_image.a $(stat -c%s libSDL2_image.a) bytes, $(ls obj_img/*.o | wc -l) objects"
