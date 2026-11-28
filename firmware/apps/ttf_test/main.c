/* SPDX-License-Identifier: GPL-3.0-only
 *
 * SDL2_ttf and SDL2_image on the Tang, as VCMI 1.7.5 uses them.
 *
 * The screen is set up as VCMI's ScreenHandler does with the software
 * renderer: a streaming ARGB8888 texture aliased by a screen surface, which
 * the tinyvcmi driver shows directly (VCMI-004).  Then:
 *
 *   text    VCMI's TrueType replacement font, NotoSans-Medium.ttf, opened
 *           from memory with TTF_OpenFontRW and mono hinting, as
 *           client/renderSDL/CTrueTypeFont.cpp does; TTF_SizeUTF8, the
 *           metrics and TTF_GlyphIsProvided checked; lines rendered with
 *           TTF_RenderUTF8_Blended and _Solid, plain, bold and italic,
 *           each timed, and blitted to the screen, where their glyph pixels
 *           must land on the page the raster shows.
 *   images  a 64x48 test pattern saved and loaded back through memory as
 *           PNG (IMG_SavePNG_RW, IMG_Load_RW), BMP and JPEG: PNG and BMP
 *           must come back exact, JPEG within a small mean error, and all
 *           three are shown.
 *
 * Run it with tools/load_ae350.py after the hand-over.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include <SDL.h>
#include <SDL_image.h>
#include <SDL_ttf.h>

#include "tinyvcmi.h"

extern const uint8_t _binary_NotoSans_Medium_ttf_start[];
extern const uint8_t _binary_NotoSans_Medium_ttf_end[];

#define AMASK 0xff000000u
#define RMASK 0x00ff0000u
#define GMASK 0x0000ff00u
#define BMASK 0x000000ffu

static int fails;

static void check(const char *what, int ok)
{
	if (!ok) {
		printf("  WRONG %s (%s)\n", what, SDL_GetError());
		fails++;
	}
}

static uint32_t us_since(uint64_t t0)
{
	return (uint32_t)((tv_cycles64() - t0) / (TV_CORE_HZ / 1000000u));
}

/* Pixels on the shown page, in a rectangle, that are not the background. */
static uint32_t lit(const SDL_Rect *r, uint32_t bg)
{
	const uint32_t *shown = (const uint32_t *)(uintptr_t)TV_VID_BASE;
	uint32_t n = 0;

	for (int y = r->y; y < r->y + r->h; y++)
		for (int x = r->x; x < r->x + r->w; x++)
			n += (shown[y * TV_VID_WIDTH + x] & 0xffffffu) != bg;
	return n;
}

static void present(SDL_Renderer *ren, SDL_Texture *tex)
{
	SDL_RenderCopy(ren, tex, NULL, NULL);
	SDL_RenderFlush(ren);
	SDL_RenderPresent(ren);
}

/* One line of text, rendered, blitted and found on the shown page. */
static int text_line(SDL_Renderer *ren, SDL_Texture *tex, SDL_Surface *screen,
		     TTF_Font *font, const char *s, int solid, int style, int y)
{
	SDL_Color white = { 255, 255, 255, 255 }, black = { 0, 0, 0, 255 };
	SDL_Surface *t;
	SDL_Rect at;
	uint64_t t0;
	uint32_t us, n;

	TTF_SetFontStyle(font, style);
	t0 = tv_cycles64();
	t = solid ? TTF_RenderUTF8_Solid(font, s, white)
	          : TTF_RenderUTF8_Blended(font, s, white);
	us = us_since(t0);
	(void)black;
	if (!t) {
		check("render", 0);
		return 1;
	}
	at.x = 40;
	at.y = y;
	at.w = t->w;
	at.h = t->h;
	SDL_BlitSurface(t, NULL, screen, &at);
	present(ren, tex);
	n = lit(&at, 0x202040u);
	printf("  %-8s %-11s %4dx%-3d %6lu us, %5lu pixels lit\n",
	       solid ? "solid" : "blended",
	       style == TTF_STYLE_BOLD ? "bold" :
	       style == TTF_STYLE_ITALIC ? "italic" : "plain",
	       t->w, t->h, (unsigned long)us, (unsigned long)n);
	check("glyphs on the shown page", n > (uint32_t)(t->w * t->h / 20));
	SDL_FreeSurface(t);
	return 0;
}

/* Save a surface through memory in one format and load it back. */
static SDL_Surface *round_trip(SDL_Surface *src, const char *fmt,
			       uint8_t *buf, size_t size, size_t *used)
{
	SDL_RWops *rw = SDL_RWFromMem(buf, (int)size);
	int rc;

	if (fmt[0] == 'P')
		rc = IMG_SavePNG_RW(src, rw, 0);
	else if (fmt[0] == 'B')
		rc = SDL_SaveBMP_RW(src, rw, 0);
	else
		rc = IMG_SaveJPG_RW(src, rw, 0, 90);
	*used = (size_t)SDL_RWtell(rw);
	SDL_RWclose(rw);
	if (rc != 0)
		return NULL;
	SDL_Surface *back = IMG_Load_RW(SDL_RWFromConstMem(buf, (int)*used), 1);
	if (!back)
		return NULL;
	SDL_Surface *conv = SDL_ConvertSurfaceFormat(back, SDL_PIXELFORMAT_ARGB8888, 0);
	SDL_FreeSurface(back);
	return conv;
}

/* Mean absolute channel error in 1/100ths, and exact match. */
static uint32_t diff(SDL_Surface *a, SDL_Surface *b, int *exact)
{
	uint64_t sum = 0;

	*exact = 1;
	for (int y = 0; y < a->h; y++)
		for (int x = 0; x < a->w; x++) {
			uint32_t p = ((uint32_t *)a->pixels)[y * a->pitch / 4 + x];
			uint32_t q = ((uint32_t *)b->pixels)[y * b->pitch / 4 + x];
			for (int c = 0; c < 24; c += 8) {
				int d = (int)((p >> c) & 255) - (int)((q >> c) & 255);
				sum += (uint64_t)(d < 0 ? -d : d);
			}
			if ((p & 0xffffffu) != (q & 0xffffffu))
				*exact = 0;
		}
	return (uint32_t)(sum * 100 / ((uint64_t)a->w * a->h * 3));
}

int main(void)
{
	SDL_Window *win;
	SDL_Renderer *ren;
	SDL_Texture *tex;
	SDL_Surface *screen, *pat;
	TTF_Font *font;
	void *pixels;
	int pitch, w, h, y;
	static uint8_t buf[64 * 1024];

	printf("TinyVCMI TTF %d.%d.%d, IMG %d.%d.%d\n", SDL_TTF_MAJOR_VERSION,
	       SDL_TTF_MINOR_VERSION, SDL_TTF_PATCHLEVEL, SDL_IMAGE_MAJOR_VERSION,
	       SDL_IMAGE_MINOR_VERSION, SDL_IMAGE_PATCHLEVEL);
	if (SDL_Init(SDL_INIT_VIDEO) != 0 || TTF_Init() != 0) {
		printf("BAD init: %s\n", SDL_GetError());
		return 1;
	}
	win = SDL_CreateWindow("TinyVCMI ttf", 0, 0, TV_VID_WIDTH, TV_VID_HEIGHT, 0);
	ren = win ? SDL_CreateRenderer(win, -1, SDL_RENDERER_SOFTWARE) : NULL;
	tex = ren ? SDL_CreateTexture(ren, SDL_PIXELFORMAT_ARGB8888,
	                              SDL_TEXTUREACCESS_STREAMING, TV_VID_WIDTH,
	                              TV_VID_HEIGHT) : NULL;
	if (!tex || SDL_LockTexture(tex, NULL, &pixels, &pitch) != 0) {
		printf("BAD screen: %s\n", SDL_GetError());
		return 1;
	}
	SDL_UnlockTexture(tex);
	SDL_SetTextureBlendMode(tex, SDL_BLENDMODE_NONE);
	screen = SDL_CreateRGBSurfaceFrom(pixels, TV_VID_WIDTH, TV_VID_HEIGHT, 32,
	                                  pitch, RMASK, GMASK, BMASK, AMASK);
	SDL_FillRect(screen, NULL, 0xff202040u);
	present(ren, tex);

	/* Text */
	{
		const size_t size = (size_t)(_binary_NotoSans_Medium_ttf_end -
		                             _binary_NotoSans_Medium_ttf_start);
		uint64_t t0 = tv_cycles64();

		font = TTF_OpenFontRW(SDL_RWFromConstMem(
		    _binary_NotoSans_Medium_ttf_start, (int)size), 1, 28);
		printf("font: %lu bytes, opened in %lu us\n", (unsigned long)size,
		       (unsigned long)us_since(t0));
		if (!font) {
			printf("BAD TTF_OpenFontRW: %s\n", TTF_GetError());
			return 1;
		}
		TTF_SetFontHinting(font, TTF_HINTING_MONO);
		check("TTF_SizeUTF8",
		      TTF_SizeUTF8(font, "Heroes of Might and Magic", &w, &h) == 0 &&
		      w > 200 && h > 20);
		printf("  size %dx%d, height %d, ascent %d, descent %d, line skip %d\n",
		       w, h, TTF_FontHeight(font), TTF_FontAscent(font),
		       TTF_FontDescent(font), TTF_FontLineSkip(font));
		check("glyph A", TTF_GlyphIsProvided(font, 'A'));
		check("glyph e-acute", TTF_GlyphIsProvided32(font, 0xe9));
		y = 40;
		text_line(ren, tex, screen, font, "TinyVCMI: Heroes of Might and Magic III",
		          0, TTF_STYLE_NORMAL, y);
		text_line(ren, tex, screen, font, "Blended, bold: Castle, Rampart, Tower",
		          0, TTF_STYLE_BOLD, y += 50);
		text_line(ren, tex, screen, font, "Blended, italic: Inferno, Necropolis",
		          0, TTF_STYLE_ITALIC, y += 50);
		text_line(ren, tex, screen, font, "Solid: Dungeon, Stronghold, Fortress",
		          1, TTF_STYLE_NORMAL, y += 50);
		text_line(ren, tex, screen, font, "UTF-8: caf\xc3\xa9, Se\xc3\xb1or, Gr\xc3\xb6\xc3\x9f" "e, \xc3\x85land",
		          0, TTF_STYLE_NORMAL, y += 50);
		TTF_CloseFont(font);
	}

	/* Images */
	pat = SDL_CreateRGBSurface(0, 64, 48, 32, RMASK, GMASK, BMASK, AMASK);
	for (int py = 0; py < 48; py++)
		for (int px = 0; px < 64; px++)
			((uint32_t *)pat->pixels)[py * pat->pitch / 4 + px] =
			    0xff000000u | ((uint32_t)(px * 4) << 16) |
			    ((uint32_t)(py * 5) << 8) | (((px ^ py) & 8) ? 0xc0u : 0x20u);
	{
		const char *fmts[3] = { "PNG", "BMP", "JPEG" };

		for (int i = 0; i < 3; i++) {
			size_t used = 0;
			uint64_t t0 = tv_cycles64();
			SDL_Surface *back = round_trip(pat, fmts[i], buf, sizeof buf, &used);
			uint32_t us = us_since(t0);
			int exact = 0;
			uint32_t err;

			if (!back) {
				printf("  %-4s round trip failed: %s\n", fmts[i], IMG_GetError());
				fails++;
				continue;
			}
			err = diff(pat, back, &exact);
			printf("  %-4s %5lu bytes, %6lu us, %s, mean error %lu.%02lu\n",
			       fmts[i], (unsigned long)used, (unsigned long)us,
			       exact ? "exact" : "not exact", (unsigned long)(err / 100),
			       (unsigned long)(err % 100));
			if (i < 2)
				check("lossless round trip", exact);
			else
				check("JPEG close", err < 300);
			SDL_Rect at = { 40 + i * 100, 340, 64, 48 };
			SDL_Rect big = { 40 + i * 100, 400, 64, 48 };
			SDL_BlitSurface(back, NULL, screen, &at);
			SDL_BlitSurface(pat, NULL, screen, &big);
			SDL_FreeSurface(back);
		}
	}
	present(ren, tex);
	SDL_FreeSurface(pat);

	printf("TinyVCMI TTF %s, %d wrong\n", fails ? "BAD" : "OK", fails);
	printf("holding the picture for 15 s\n");
	fflush(stdout);
	/* Counted in raster frames, polling the video unit: a loop that only
	   reads the cycle counter runs from the caches with no bus transfer,
	   and after about 1.8 s of that the fabric's stall watchdog reports a
	   stopped CPU (ae350_sys.sv, core-log entry 44). */
	for (int f = 0; f < 15 * 60; f++) {
		uint32_t n = TV_VID_FRAMES;

		while (TV_VID_FRAMES == n)
			;
	}
	TTF_Quit();
	return fails ? 1 : 0;
}
