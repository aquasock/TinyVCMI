# SPDX-License-Identifier: GPL-3.0-only
#
# A program larger than 32 MiB run by TinyTang's ae350run: 34 MiB of
# initialised data put its image's end, and the card reply buffer in its
# .bss, above 0x42000000, the end of the memory ae350run once allowed every
# core (PROT-004).  Runs in 2-wire mode:
# tools/tang_ae350run.py build/firmware/apps/big_test/big_test.elf

APP     := big_test
SOURCES := main.c pad.S

include ../../rt/rt.mk
