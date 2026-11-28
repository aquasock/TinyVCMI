# SPDX-License-Identifier: GPL-3.0-only
#
# The SD card through TinyTang's card file service, as VCMI will read it:
# the Heroes III data's directory, H3bitmap.lod's table and entries through
# fopen and fread, and the service's throughput.  Runs under ae350run in
# 2-wire mode: tools/tang_ae350run.py build/firmware/apps/card_test/card_test.elf

APP     := card_test
SOURCES := main.c

include ../../rt/rt.mk
