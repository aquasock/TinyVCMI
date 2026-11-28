# SPDX-License-Identifier: GPL-3.0-only
#
# Does the A25 execute RV32A atomics on the memories this system gives it?
# Run it with: tools/load_ae350.py --hold-on-bad 3 \
#     build/firmware/apps/amo_probe/amo_probe.elf
# make HANG=1 adds the two cases that never return (AE350-011); the board
# then needs its image reloaded.

APP     := amo_probe
SOURCES := main.c
# This program executes AMOs and LR/SC on purpose, so it keeps the A
# extension whatever the runtime's default arch is.
RT_MARCH := rv32imac_zicsr_zifencei

ifeq ($(HANG),1)
CPPFLAGS += -DAMO_PROBE_HANG
endif

include ../../rt/rt.mk
