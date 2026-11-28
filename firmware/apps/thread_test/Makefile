# SPDX-License-Identifier: GPL-3.0-only
#
# C++ threads on the AE350 as VCMI uses them, through the threaded libstdc++
# (tools/build_toolchain_threads.sh) and the cooperative pthreads under it
# (firmware/rt/pthread.c).  Runs under ae350run in 2-wire mode, or with
# tools/load_ae350.py: tools/tang_ae350run.py build/firmware/apps/thread_test/thread_test.elf

APP        := thread_test
SOURCES    := main.cpp
RT_THREADS := 1

include ../../rt/rt.mk
