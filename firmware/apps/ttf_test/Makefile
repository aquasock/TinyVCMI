# SPDX-License-Identifier: GPL-3.0-only
#
# SDL2_ttf and SDL2_image on the Tang, as VCMI 1.7.5 uses them: text in
# VCMI's Noto Sans drawn blended and solid onto the screen surface, and
# images round-tripped through PNG, BMP and JPEG.  Links the libraries
# tools/build_sdl2.sh and tools/build_sdl2_addons.sh build, and embeds the
# font the latter fetches.
#
# Run: tools/load_ae350.py --hold-on-bad 3 build/firmware/apps/ttf_test/ttf_test.elf

APP     := ttf_test
SOURCES := main.c

app_dir := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SDL_DIR ?= $(abspath $(app_dir)/../../../build/sdl)
SDL_INC := $(SDL_DIR)/SDL2-2.32.10/include
SDL_PORT := $(abspath $(app_dir)/../../sdl)
FONT    := $(SDL_DIR)/fonts/NotoSans-Medium.ttf

CPPFLAGS += -I$(SDL_PORT) -I$(SDL_INC) -I$(SDL_DIR)/SDL2_ttf-2.24.0 \
            -I$(SDL_DIR)/SDL2_image-2.8.12/include

# Recursive, so BUILD is rt.mk's when rt.mk's link rule expands them.
FONT_OBJ = $(BUILD)/obj/font.o
EXTRA_OBJECTS = $(SDL_DIR)/libSDL2_ttf.a $(SDL_DIR)/libSDL2_image.a \
                $(SDL_DIR)/libSDL2.a $(FONT_OBJ)

include ../../rt/rt.mk

# The font as read-only data, symbols _binary_NotoSans_Medium_ttf_start and
# _end.
$(FONT_OBJ): $(FONT)
	@mkdir -p $(dir $@)
	cd $(dir $(FONT)) && $(CROSS)objcopy -I binary -O elf32-littleriscv \
	    -B riscv --rename-section .data=.rodata.font,alloc,load,readonly,data,contents \
	    $(notdir $(FONT)) $@

$(FONT) $(SDL_DIR)/libSDL2_ttf.a $(SDL_DIR)/libSDL2_image.a:
	@echo "missing $@; run tools/build_sdl2_addons.sh first" >&2
	@false
