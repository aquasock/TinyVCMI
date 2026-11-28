#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build GCC 15.2.0 for the AE350 with POSIX threads: the compiler, libgcc and
# libstdc++, for rv32imc_zicsr_zifencei / ilp32 only, on newlib 4.5.
#
#   build_toolchain_threads.sh [OUT_DIR]     default build/toolchain
#
# The xPack toolchain the runtime uses (riscv-none-elf-gcc 15.2.0-1) was
# configured --disable-threads, so its libstdc++ has no std::thread,
# std::mutex or std::condition_variable, which VCMI needs, and libgcc's
# emulated TLS keeps one copy of every thread_local.  This builds the same GCC
# release from its signed tarball with --enable-threads=posix, against a
# private copy of the xPack's own newlib (headers and the rv32imc/ilp32
# libraries), so the compiler, libgcc's emutls and libstdc++ all take their
# threads from <pthread.h>, which firmware/rt/pthread.c implements on the A25.
#
# newlib declares the pthread functions only when _POSIX_THREADS is defined,
# and clock_gettime and CLOCK_MONOTONIC only with the POSIX timer options,
# none of which its sys/features.h defines for riscv; the sysroot copy's
# sys/features.h gets one marked block turning on the thread and clock
# options pthread.c provides, so every compile against this sysroot sees them.
#
# Binutils are the xPack's (2.45).  GMP, MPFR, MPC and ISL come from GCC's own
# contrib/download_prerequisites, which checks each one's SHA-512.  Nothing is
# written outside OUT_DIR, which build/ keeps out of the repository.
#
# Tarball: https://ftp.gnu.org/gnu/gcc/gcc-15.2.0/gcc-15.2.0.tar.xz, whose
# GNU signature (RSA key 7F74F97C103468EE5D750B583AB00996FC26A641, Richard
# Biener) verified good on 2026-11-28 against ftp.gnu.org's gnu-keyring.gpg;
# the digest below is that verified tarball's, and a different download stops
# the script.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out=${1:-$root/build/toolchain}
ver=15.2.0
url="https://ftp.gnu.org/gnu/gcc/gcc-$ver/gcc-$ver.tar.xz"
digest=438fd996826b0c82485a29da03a72d71d6e3541a83ec702df4271f6fe025d24e
xpack=${RISCV_XPACK:-$HOME/tools/xpack-riscv-none-elf-gcc-15.2.0-1}
target=riscv-none-elf
march=rv32imc_zicsr_zifencei
mabi=ilp32
jobs=${JOBS:-16}
prefix=$out/gcc-posix
sysroot=$out/sysroot

[[ -x $xpack/bin/$target-as ]] || { echo "missing $xpack/bin/$target-as" >&2; exit 2; }
mkdir -p "$out/dl" "$out/src" || exit 1

# --- the source ----------------------------------------------------------
tarball=$out/dl/gcc-$ver.tar.xz
if [[ ! -f $tarball ]]; then
    echo "fetching gcc-$ver"
    curl -sfL -o "$tarball" "$url" || { echo "download failed" >&2; exit 1; }
fi
got=$(sha256sum "$tarball" | cut -d' ' -f1)
[[ $got == "$digest" ]] || { echo "gcc-$ver.tar.xz digest $got, expected $digest" >&2; exit 1; }
src=$out/src/gcc-$ver
if [[ ! -d $src ]]; then
    tar xJf "$tarball" -C "$out/src" || exit 1
fi
if [[ ! -e $src/gmp || ! -e $src/mpfr || ! -e $src/mpc || ! -e $src/isl ]]; then
    (cd "$src" && ./contrib/download_prerequisites) || { echo "prerequisites failed" >&2; exit 1; }
fi

# --- libstdc++'s time and yield support ----------------------------------
# libstdc++ decides nanosleep, sched_yield and the monotonic and real-time
# clocks by target OS when it cannot run link tests, as in this cross build,
# and bare-metal elf is not in its table, so this_thread::yield() would do
# nothing.  firmware/rt/pthread.c provides all four, so the generated
# configure gets a case for elf saying so.  Applied once; a libstdc++ already
# configured without it is configured again.
lsc=$src/libstdc++-v3/configure
marker="TinyVCMI: the AE350 runtime provides"
if ! grep -qF "$marker" "$lsc"; then
    python3 - "$lsc" "$marker" <<'PY' || exit 1
import sys
path, marker = sys.argv[1], sys.argv[2]
s = open(path).read()
old = """      uclinux*)
        ac_has_nanosleep=yes
        ac_has_sched_yield=yes
    esac"""
new = """      uclinux*)
        ac_has_nanosleep=yes
        ac_has_sched_yield=yes
        ;;
      elf*)
        # """ + marker + """ these (firmware/rt/pthread.c).
        ac_has_clock_monotonic=yes
        ac_has_clock_realtime=yes
        ac_has_nanosleep=yes
        ac_has_sched_yield=yes
    esac"""
assert s.count(old) == 1, "configure's time table has changed"
open(path, "w").write(s.replace(old, new))
PY
    rm -rf "$out/build-gcc/$target/libstdc++-v3"
fi

# --- the sysroot: the xPack's newlib for rv32imc/ilp32 --------------------
# A sysroot made before its features block named the clocks is made again,
# and the C++ library built on it with it.
marker="TinyVCMI: POSIX threads and clocks"
if [[ -f $sysroot/.done ]] && ! grep -qF "$marker" "$sysroot/include/sys/features.h"; then
    rm -f "$sysroot/.done"
    rm -rf "$out/build-gcc/$target/libstdc++-v3"
fi
if [[ ! -f $sysroot/.done ]]; then
    rm -rf "$sysroot"
    mkdir -p "$sysroot/include" "$sysroot/lib" || exit 1
    # newlib's headers; the xPack's own C++ headers stay out, this build
    # installs its own.
    (cd "$xpack/$target/include" && tar cf - --exclude=./c++ .) |
        (cd "$sysroot/include" && tar xf -) || exit 1
    for f in crt0.o libc.a libm.a libg.a libnosys.a libgloss.a; do
        cp "$xpack/$target/lib/$march/$mabi/$f" "$sysroot/lib/" 2>/dev/null ||
        cp "$xpack/$target/lib/rv32imc/$mabi/$f" "$sysroot/lib/" || exit 1
    done
    features=$sysroot/include/sys/features.h
    grep -qF "$marker" "$features" || python3 - "$features" "$marker" <<'PY' || exit 1
import sys
path, marker = sys.argv[1], sys.argv[2]
s = open(path).read()
block = f"""
/* {marker} (tools/build_toolchain_threads.sh): firmware/rt/pthread.c
 * implements these on the AE350, cooperatively, so newlib's <pthread.h>
 * declares them for every compile against this sysroot. */
#ifndef _POSIX_THREADS
#define _POSIX_THREADS 1
#endif
#ifndef _UNIX98_THREAD_MUTEX_ATTRIBUTES
#define _UNIX98_THREAD_MUTEX_ATTRIBUTES 1
#endif
#ifndef _POSIX_TIMEOUTS
#define _POSIX_TIMEOUTS 1
#endif
#ifndef _POSIX_READER_WRITER_LOCKS
#define _POSIX_READER_WRITER_LOCKS 1
#endif
#ifndef _POSIX_TIMERS
#define _POSIX_TIMERS 1
#endif
#ifndef _POSIX_MONOTONIC_CLOCK
#define _POSIX_MONOTONIC_CLOCK 200112L
#endif
#ifndef _POSIX_CLOCK_SELECTION
#define _POSIX_CLOCK_SELECTION 200112L
#endif
"""
end = s.rindex("#endif")          # the include guard's
s = s[:end] + block + "\n" + s[end:]
open(path, "w").write(s)
PY
    touch "$sysroot/.done"
fi

# --- configure, build, install ---------------------------------------------
export PATH=$xpack/bin:$PATH
bld=$out/build-gcc
mkdir -p "$bld" || exit 1
cd "$bld" || exit 1
if [[ ! -f Makefile ]]; then
    "$src/configure" \
        --target=$target --prefix="$prefix" \
        --with-sysroot="$sysroot" --with-native-system-header-dir=/include \
        --with-newlib --disable-shared --enable-threads=posix --disable-tls \
        --disable-multilib --with-arch=$march --with-abi=$mabi \
        --enable-languages=c,c++ --enable-checking=release --disable-nls \
        --disable-libssp --disable-libquadmath --disable-libgomp \
        --disable-libatomic --disable-libstdcxx-pch \
        --with-gnu-as --with-gnu-ld \
        --with-as="$xpack/bin/$target-as" --with-ld="$xpack/bin/$target-ld" \
        --with-pkgversion="TinyVCMI posix-threads" \
        > configure.log 2>&1 || { tail -20 configure.log >&2; exit 1; }
fi
make -j"$jobs" all-gcc all-target-libgcc all-target-libstdc++-v3 > make.log 2>&1 ||
    { tail -30 make.log >&2; exit 1; }
make install-gcc install-target-libgcc install-target-libstdc++-v3 > install.log 2>&1 ||
    { tail -20 install.log >&2; exit 1; }

"$prefix/bin/$target-g++" -v 2>&1 | grep -E 'Thread model|gcc version'
grep -n '_GLIBCXX_HAS_GTHREADS' "$prefix/$target/include/c++/$ver/$target/bits/c++config.h" | head -1
echo "installed $prefix"
