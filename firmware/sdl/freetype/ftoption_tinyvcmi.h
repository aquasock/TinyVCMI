/* SPDX-License-Identifier: GPL-3.0-only
 *
 * FreeType's options for TinyVCMI, selected by tools/build_sdl2_addons.sh
 * with -DFT_CONFIG_OPTIONS_H: the stock options without the external
 * libraries, as SDL_ttf's own CMake build of its vendored FreeType sets them
 * (FT_DISABLE_ZLIB, BZIP2, PNG, BROTLI and HARFBUZZ).  Without zlib, sfnt
 * leaves out WOFF; VCMI's fonts are plain TrueType.
 */
#include <freetype/config/ftoption.h>

#undef FT_CONFIG_OPTION_USE_ZLIB
#undef FT_CONFIG_OPTION_USE_BZIP2
#undef FT_CONFIG_OPTION_USE_PNG
#undef FT_CONFIG_OPTION_USE_HARFBUZZ
#undef FT_CONFIG_OPTION_USE_BROTLI
