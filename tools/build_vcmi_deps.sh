#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build the libraries VCMI 1.7.5 links, for the AE350 with C++ threads.
#
#   build_vcmi_deps.sh [STEP...]     default: every step, in order
#
# Steps: zlib squish minizip boost tbb.  oneTBB is patched for the AE350
# (firmware/deps/onetbb-2022.3.0-ae350.patch); the rest build unmodified,
# leaning on firmware/rt for the POSIX calls newlib lacks.  Each builds with the threaded GCC
# (tools/build_toolchain_threads.sh, which must have run) through
# tools/cmake/ae350-threads.cmake, as static libraries installed into
# build/deps/prefix, and leaves a stamp so that a later run skips it; remove
# build/deps/stamps/<step> to build one again.  Logs go to build/deps/logs.
#
# Versions and options follow MiSTer-VCMI's scripts/env.sh and
# scripts/build-deps.sh, the configuration VCMI 1.7.5 is known to run with.
# Each tarball's SHA-256 is pinned below: fetched from upstream on
# 2026-11-28 and equal to MiSTer-VCMI's independently fetched work/dl copy.
# Nothing is written outside build/deps; nothing fetched is committed.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out=$root/build/deps
dl=$out/dl src=$out/src bld=$out/build prefix=$out/prefix
stamps=$out/stamps logs=$out/logs
toolchain=$root/tools/cmake/ae350-threads.cmake
jobs=${JOBS:-16}
mkdir -p "$dl" "$src" "$bld" "$prefix" "$stamps" "$logs" || exit 1
[[ -x $root/build/toolchain/gcc-posix/bin/riscv-none-elf-g++ ]] ||
    { echo "run tools/build_toolchain_threads.sh first" >&2; exit 2; }
command -v cmake >/dev/null && command -v ninja >/dev/null ||
    { echo "cmake and ninja are needed" >&2; exit 2; }

declare -A url sum
url[zlib]=https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
sum[zlib]=9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
url[squish]=https://deb.debian.org/debian/pool/main/libs/libsquish/libsquish_1.15.orig.tar.gz
sum[squish]=628796eeba608866183a61d080d46967c9dda6723bc0a3ec52324c85d2147269
url[minizip]=https://github.com/zlib-ng/minizip-ng/archive/refs/tags/4.0.10.tar.gz
sum[minizip]=c362e35ee973fa7be58cc5e38a4a6c23cc8f7e652555daf4f115a9eb2d3a6be7
url[boost]=https://github.com/boostorg/boost/releases/download/boost-1.90.0/boost-1.90.0-cmake.tar.xz
sum[boost]=aca59f889f0f32028ad88ba6764582b63c916ce5f77b31289ad19421a96c555f
url[tbb]=https://github.com/uxlfoundation/oneTBB/archive/refs/tags/v2022.3.0.tar.gz
sum[tbb]=01598a46c1162c27253a0de0236f520fd8ee8166e9ebb84a4243574f88e6e50a
declare -A file=(
    [zlib]=zlib-1.3.1.tar.gz [squish]=libsquish_1.15.orig.tar.gz
    [minizip]=minizip-ng-4.0.10.tar.gz [boost]=boost-1.90.0-cmake.tar.xz
    [tbb]=oneTBB-2022.3.0.tar.gz)
declare -A dir=(
    [zlib]=zlib-1.3.1 [squish]=squish-1.15 [minizip]=minizip-ng-4.0.10
    [boost]=boost-1.90.0 [tbb]=oneTBB-2022.3.0)

# fetch <step>: the pinned tarball, checked.
fetch() {
    local f=$dl/${file[$1]}
    [[ -s $f ]] || curl -sfL --retry 3 -o "$f" "${url[$1]}" ||
        { echo "$1: download failed" >&2; return 1; }
    local got; got=$(sha256sum "$f" | cut -d' ' -f1)
    [[ $got == "${sum[$1]}" ]] ||
        { echo "$1: ${file[$1]} digest $got, expected ${sum[$1]}" >&2; return 1; }
}

# unpack <step>: into src/, once.  libsquish's tarball has no top directory.
unpack() {
    local d=$src/${dir[$1]}
    [[ -d $d ]] && return 0
    if [[ $1 == squish ]]; then
        mkdir -p "$d" && tar xf "$dl/${file[$1]}" -C "$d"
    else
        tar xf "$dl/${file[$1]}" -C "$src" || return 1
    fi
    # oneTBB names its OS in four places; firmware/deps carries the patch
    # that lets it accept the AE350 (TINYVCMI_AE350).
    if [[ $1 == tbb ]]; then
        (cd "$d" && patch -p1 --forward < "$root/firmware/deps/onetbb-2022.3.0-ae350.patch")
    fi
}

# cm <step> [cmake args...]: configure, build and install, logged.
cm() {
    local name=$1; shift
    cmake -S "$src/${dir[$name]}" -B "$bld/$name" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$toolchain" \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_PREFIX_PATH="$prefix" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DBUILD_SHARED_LIBS=OFF "$@" &&
    cmake --build "$bld/$name" -j"$jobs" &&
    cmake --install "$bld/$name"
}

step_zlib() {
    cm zlib -DZLIB_BUILD_EXAMPLES=OFF || return 1
    # On a Generic system zlib's CMake names its archives libzlib.a and
    # libzlibstatic.a; FindZLIB takes either, and -lz wants libz.a.
    install -m644 "$prefix/lib/libzlibstatic.a" "$prefix/lib/libz.a"
}

step_squish() {
    # MiSTer compiles its seven sources by hand; so does this.
    local d=$src/${dir[squish]} o=$bld/squish
    mkdir -p "$o" "$prefix/lib" "$prefix/include" || return 1
    local gxx=$root/build/toolchain/gcc-posix/bin/riscv-none-elf-g++
    local ar=$HOME/tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-ar
    for f in "$d"/*.cpp; do
        "$gxx" -march=rv32imc_zicsr_zifencei -mabi=ilp32 -O2 -g \
            -ffunction-sections -fdata-sections -c "$f" \
            -o "$o/$(basename "${f%.cpp}").o" || return 1
    done
    rm -f "$o/libsquish.a"
    "$ar" rcs "$o/libsquish.a" "$o"/*.o &&
    install -m644 "$o/libsquish.a" "$prefix/lib/libsquish.a" &&
    install -m644 "$d/squish.h" "$prefix/include/squish.h"
}

step_minizip() {
    cm minizip \
        -DMZ_BZIP2=OFF -DMZ_LZMA=OFF -DMZ_ZSTD=OFF -DMZ_OPENSSL=OFF -DMZ_ICONV=OFF \
        -DMZ_LIBBSD=OFF -DMZ_PKCRYPT=OFF -DMZ_WZAES=OFF -DMZ_SIGNING=OFF \
        -DMZ_FETCH_LIBS=OFF -DMZ_FORCE_FETCH_LIBS=OFF -DMZ_ZLIB=ON \
        -DZLIB_ROOT="$prefix"
}

# Boost: the three compiled libraries VCMI asks for, then every library's
# headers, as Boost's ordinary distribution installs them, for the many
# header-only ones VCMI includes.  Boost.Locale is left out: VCMI uses it only
# to convert the game's Windows code-page text to UTF-8, which MiSTer gets
# from glibc's iconv and this port does in VCMI itself, and it would bring
# Boost.Thread.  Boost.Container still comes, through lexical_cast; its
# bundled dlmalloc is built with HAVE_MMAP=0, so it grows newlib's heap.
# Boost.Filesystem's feature checks only compile here (nothing links in this
# cross build), so fdopendir, which newlib declares and does not implement,
# would test present; it is set absent, and directories are read with
# opendir as on any POSIX system without it.
step_boost() {
    cm boost \
        -DBOOST_INCLUDE_LIBRARIES="date_time;filesystem;program_options" \
        -DBOOST_ENABLE_MPI=OFF -DBOOST_ENABLE_PYTHON=OFF -DBUILD_TESTING=OFF \
        -DCMAKE_C_FLAGS_RELEASE="-O2 -g -DHAVE_MMAP=0" \
        -DBOOST_FILESYSTEM_HAS_FDOPENDIR_NOFOLLOW=OFF \
        -DZLIB_ROOT="$prefix" || return 1
    local d=$src/${dir[boost]}/libs
    for inc in "$d"/*/include "$d"/numeric/*/include; do
        [[ -d $inc/boost ]] && cp -a "$inc/boost" "$prefix/include/" || true
    done
    [[ -f $prefix/include/boost/asio.hpp && -f $prefix/include/boost/format.hpp ]]
}

step_tbb() {
    cm tbb -DTBB_TEST=OFF -DTBB_STRICT=OFF -DTBB_EXAMPLES=OFF \
        -DTBBMALLOC_BUILD=OFF -DTBB4PY_BUILD=OFF -DTBB_DISABLE_HWLOC_AUTOMATIC_SEARCH=ON \
        -DTBB_ENABLE_IPO=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=OFF
}

steps=("$@")
[[ ${#steps[@]} -gt 0 ]] || steps=(zlib squish minizip boost tbb)
for s in "${steps[@]}"; do
    [[ -n ${url[$s]:-} ]] || { echo "unknown step $s" >&2; exit 2; }
    if [[ -e $stamps/$s ]]; then echo "$s: built"; continue; fi
    echo "$s: building"
    { fetch "$s" && unpack "$s" && "step_$s"; } > "$logs/$s.log" 2>&1 ||
        { echo "$s: FAILED, see $logs/$s.log" >&2; tail -25 "$logs/$s.log" >&2; exit 1; }
    touch "$stamps/$s"
done
echo "installed into $prefix"
