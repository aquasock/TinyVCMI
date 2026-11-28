# SPDX-License-Identifier: GPL-3.0-only
#
# The libraries VCMI links, built by tools/build_vcmi_deps.sh, exercised on
# the AE350: zlib, minizip-ng, libsquish, Boost (filesystem over the card,
# program_options, date_time) and oneTBB's algorithms and containers.
# Runs under ae350run in 2-wire mode, for the card:
# tools/tang_ae350run.py build/firmware/apps/deps_test/deps_test.elf

APP        := deps_test
SOURCES    := main.cpp
RT_THREADS := 1
DEPS       := $(abspath ../../../build/deps/prefix)
CPPFLAGS   += -isystem $(DEPS)/include
# Archives in dependency order: each before what it uses.
EXTRA_OBJECTS := $(DEPS)/lib/libminizip.a $(DEPS)/lib/libz.a \
                 $(DEPS)/lib/libsquish.a \
                 $(DEPS)/lib/libboost_filesystem.a $(DEPS)/lib/libboost_atomic.a \
                 $(DEPS)/lib/libboost_program_options.a $(DEPS)/lib/libboost_date_time.a \
                 $(DEPS)/lib/libboost_container.a \
                 $(DEPS)/lib/libtbb.a

include ../../rt/rt.mk
