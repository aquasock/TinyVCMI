# SPDX-License-Identifier: GPL-3.0-only
#
# CMake toolchain for libraries and programs that run on the AE350 with C++
# threads: the threaded GCC 15.2.0 that tools/build_toolchain_threads.sh
# builds (build/toolchain/gcc-posix), rv32imc without the A extension
# (AE350-011), newlib, no OS.  The same flags rt.mk gives a program built with
# RT_THREADS := 1, so a library built here links into one.
#
#   cmake -DCMAKE_TOOLCHAIN_FILE=tools/cmake/ae350-threads.cmake ...
#
# Nothing here links a program: try_compile builds static libraries, since a
# bare-metal image needs the runtime's crt0, syscalls and link script, which
# rt.mk supplies when the program itself is linked.

get_filename_component(TV_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(TV_GCC "${TV_ROOT}/build/toolchain/gcc-posix/bin/riscv-none-elf-")
set(TV_XPACK "$ENV{HOME}/tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-")

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv32)
set(CMAKE_C_COMPILER "${TV_GCC}gcc")
set(CMAKE_CXX_COMPILER "${TV_GCC}g++")
set(CMAKE_ASM_COMPILER "${TV_GCC}gcc")
set(CMAKE_AR "${TV_XPACK}ar" CACHE FILEPATH "")
set(CMAKE_RANLIB "${TV_XPACK}ranlib" CACHE FILEPATH "")
set(CMAKE_OBJCOPY "${TV_XPACK}objcopy" CACHE FILEPATH "")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_SYSROOT "${TV_ROOT}/build/toolchain/sysroot")
set(CMAKE_FIND_ROOT_PATH "${CMAKE_SYSROOT}" "${CMAKE_INSTALL_PREFIX}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# The runtime's own headers (sys/dirent.h, tv_card.h) stand in for newlib's
# missing ones; -isystem so libraries' warnings about them stay quiet.
# tinyvcmi_target.h defines TINYVCMI_AE350 and points Boost.Config at the
# AE350's platform header (firmware/rt/include/tinyvcmi_boost_platform.hpp).
# _FORTIFY_SOURCE is undefined: its checked functions live in libssp, which
# this toolchain does not build.
set(TV_FLAGS "-march=rv32imc_zicsr_zifencei -mabi=ilp32 -ffunction-sections -fdata-sections -isystem ${TV_ROOT}/firmware/rt/include -include ${TV_ROOT}/firmware/rt/include/tinyvcmi_target.h -U_FORTIFY_SOURCE")
# Every __atomic operation on this one-hart A25 is firmware/rt/atomic.c's
# read-modify-write with interrupts masked: no lock, and nothing can come
# between its read and its write.  GCC, seeing no A extension, reports the
# atomic types as only sometimes lock-free (1), which makes Boost.Atomic
# refuse the target; reporting them as always lock-free (2) is true here and
# changes no code -- the operations remain calls into atomic.c, and rt.mk's
# link still rejects any AMO, LR or SC.  rt.mk sets the same for programs
# built with RT_THREADS, so a library and its program agree.
foreach(t BOOL CHAR CHAR16_T CHAR32_T WCHAR_T SHORT INT LONG LLONG POINTER)
  string(APPEND TV_FLAGS " -U__GCC_ATOMIC_${t}_LOCK_FREE -D__GCC_ATOMIC_${t}_LOCK_FREE=2")
endforeach()
set(CMAKE_C_FLAGS_INIT "${TV_FLAGS}")
set(CMAKE_CXX_FLAGS_INIT "${TV_FLAGS}")
set(CMAKE_ASM_FLAGS_INIT "-march=rv32imc_zicsr_zifencei -mabi=ilp32")
set(CMAKE_C_FLAGS_RELEASE_INIT "-O2 -g")
set(CMAKE_CXX_FLAGS_RELEASE_INIT "-O2 -g")
