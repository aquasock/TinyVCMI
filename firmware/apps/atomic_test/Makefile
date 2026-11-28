# SPDX-License-Identifier: GPL-3.0-only
#
# The trial for building without the A extension (AE350-011): every atomic
# std::atomic and the __sync builtins offer, on lines just evicted from the
# D-cache, through firmware/rt/atomic.c.
# Run it with: tools/load_ae350.py --hold-on-bad 3 \
#     build/firmware/apps/atomic_test/atomic_test.elf

APP      := atomic_test
SOURCES  := main.cpp

include ../../rt/rt.mk
