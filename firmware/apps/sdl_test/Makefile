# SPDX-License-Identifier: GPL-3.0-only
#
# G1: SDL2 drawing and flipping on the Tang.  Links the SDL2 built for
# rv32imac by tools/build_sdl2.sh.
#
# Run: tools/load_ae350.py build/firmware/apps/sdl_test/sdl_test.elf

APP     := sdl_test
SOURCES := main.c

# rt.mk defines ROOT, so derive the repository root from this file instead.
app_dir := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
# SDL_DIR=build/sdl-trace links the diagnostic build of SDL_TRACE=1
# tools/build_sdl2.sh, whose function trace main.c turns on around window and
# renderer creation.
SDL_DIR ?= $(abspath $(app_dir)/../../../build/sdl)
SDL_INC := $(SDL_DIR)/SDL2-2.32.10/include
SDL_LIB := $(SDL_DIR)/libSDL2.a
SDL_PORT := $(abspath $(app_dir)/../../sdl)

# firmware/sdl first, so SDL_config.h resolves to the TinyVCMI config the
# library was built with and not to SDL's stock one
CPPFLAGS += -I$(SDL_PORT) -I$(SDL_INC)
LIB_CPPFLAGS += -I$(SDL_PORT) -I$(SDL_INC) \
                -include $(SDL_PORT)/SDL_config_tinyvcmi.h
EXTRA_OBJECTS := $(SDL_LIB)

include ../../rt/rt.mk

$(SDL_LIB):
	@echo "missing $@; run tools/build_sdl2.sh first" >&2
	@false
