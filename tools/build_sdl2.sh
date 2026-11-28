#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build SDL2 2.32.10 for the AE350: rv32imac, bare metal, newlib, no OS.
#
#   build_sdl2.sh [OUT_DIR]        default build/sdl
#
# Fetches the release tarball if it is not already there, applies the two
# patches in firmware/sdl (RISC-V atomics, dynamic API off for bare metal),
# compiles SDL's own source list with the TinyVCMI SDL_config, and archives
# libSDL2.a.  Nothing is written outside OUT_DIR; the tarball is not committed
# (build/ is ignored) and the fetch is pinned to one release.
#
# The video and timer drivers live in firmware/sdl, not in SDL's tree: they
# are compiled separately and this script only checks that they build.
#
# Tarball digest measured locally from the upstream release on 2026-11-27
# (GitHub publishes no .sha256 asset for 2.32.10); if the download has changed,
# the script stops rather than building something else.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out=${1:-$root/build/sdl}
ver=2.32.10
url="https://github.com/libsdl-org/SDL/releases/download/release-$ver/SDL2-$ver.tar.gz"
digest=5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165

source "$root/tools/openflow_env.sh" >/dev/null 2>&1 || true
cross=${RISCV_BIN:-$HOME/tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin}/riscv-none-elf-
cc=${cross}gcc
ar=${cross}ar
[[ -x $cc ]] || { echo "missing $cc" >&2; exit 2; }

mkdir -p "$out" || exit 1
cd "$out" || exit 1
if [[ ! -f SDL2-$ver.tar.gz ]]; then
    echo "fetching SDL2-$ver"
    curl -sL -o SDL2-$ver.tar.gz "$url" || { echo "download failed" >&2; exit 1; }
fi
got=$(sha256sum SDL2-$ver.tar.gz | cut -d' ' -f1)
[[ $got == "$digest" ]] || {
    echo "SDL2-$ver.tar.gz digest $got, expected $digest" >&2; exit 1; }
[[ -d SDL2-$ver ]] || tar xzf SDL2-$ver.tar.gz || exit 1

# The patches are idempotent: each is skipped if its marker is already in the
# file, so re-running the script rebuilds without touching SDL's source again.
sdl=SDL2-$ver
(cd "$sdl" || exit 1
 apply_once() {    # patch-file marker-text target-file (relative to $sdl)
     local f=$1 marker=$2 target=$3
     if grep -qF "$marker" "$target"; then
         return 0
     fi
     patch -p1 -s <"$f" || { echo "$(basename "$f") did not apply" >&2; exit 1; }
 }
 apply_once "$root/firmware/sdl/sdl2-riscv-atomics.patch" \
            'amoswap.w.aq' src/atomic/SDL_spinlock.c
 apply_once "$root/firmware/sdl/sdl2-baremetal-dynapi.patch" \
            'bare-metal RISC-V, statically linked' src/dynapi/SDL_dynapi.h
 apply_once "$root/firmware/sdl/sdl2-tinyvcmi-bootstrap.patch" \
            'TINYVCMI_bootstrap' src/video/SDL_video.c) || exit 1

port=$root/firmware/sdl
arch="-march=rv32imac_zicsr_zifencei -mabi=ilp32 -O2 -g"
inc="-I$sdl/include -I$sdl/src -I$port -include $port/SDL_config_tinyvcmi.h"
defs="-DSDL_BUILD_MAJOR_VERSION=2 -DSDL_BUILD_MINOR_VERSION=32 \
      -DSDL_BUILD_MICRO_VERSION=10 -DHAVE_MALLOC=1"
rm -rf obj && mkdir -p obj logs

# SDL's own list (CMakeLists.txt:529) without the libm fallbacks it only needs
# when the C library has no maths, and without the platform render backends.
srcs=$( { ls $sdl/src/*.c
          ls $sdl/src/{atomic,audio,cpuinfo,events,file,joystick,haptic,hidapi,locale,misc,power,sensor,stdlib,thread,timer,video}/*.c 2>/dev/null
          ls $sdl/src/render/*.c $sdl/src/render/software/*.c 2>/dev/null
          ls $sdl/src/video/yuv2rgb/*.c $sdl/src/video/dummy/*.c 2>/dev/null
          ls $sdl/src/thread/generic/*.c 2>/dev/null
        } | grep -v 'src/libm/' | grep -v 'dynapi/' | sort -u )
[[ -n $srcs ]] || { echo "no sources found" >&2; exit 1; }

fail=0
for f in $srcs; do
    o=obj/$(echo "$f" | sed "s|$sdl/src/||; s|/|_|g; s|\.c$|.o|")
    if ! $cc $arch $defs $inc -w -c -o "$o" "$f" 2>"logs/$(basename "$f").log"; then
        echo "FAILED: $f"; sed -n '1,5p' "logs/$(basename "$f").log"; fail=1
    fi
done

# The two TinyVCMI drivers, so a broken port is caught here rather than at a
# program's link.
for f in $port/SDL_tinyvcmivideo.c $port/SDL_systimer_tinyvcmi.c; do
    o=obj/port_$(basename "$f" .c).o
    if ! $cc $arch $defs $inc -I"$root/firmware/include" -w -c -o "$o" "$f" \
            2>"logs/$(basename "$f").log"; then
        echo "FAILED: $f"; sed -n '1,5p' "logs/$(basename "$f").log"; fail=1
    fi
done

[[ $fail == 0 ]] || { echo "SDL2 build failed" >&2; exit 1; }
$ar rcs libSDL2.a obj/*.o || exit 1
echo "libSDL2.a $(stat -c%s libSDL2.a) bytes, $(ls obj/*.o | wc -l) objects"
