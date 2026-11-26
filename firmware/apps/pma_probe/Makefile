# SPDX-License-Identifier: GPL-3.0-only
#
# Read-only probe of the A25's machine-custom CSRs and of whether the frame
# buffer's range is treated differently from ordinary DDR3.
# Run it with: tools/load_ae350.py build/firmware/apps/pma_probe/pma_probe.elf

APP     := pma_probe
SOURCES := main.c probe.S

include ../../rt/rt.mk
