/* SPDX-License-Identifier: GPL-3.0-only
 *
 * G1: SDL2 on the Tang, drawing and flipping a test pattern at 60 Hz.
 *
 * The port plan's G1 gate: "SDL2 plus the tinyvcmi driver draw and flip a
 * test pattern at 60 Hz with the A25 idle, and a second run draws the same
 * pattern from the engine's blitter path.  This measures the driver, not the
 * engine."
 *
 * What this measures is the driver's own cost per frame: the time from the
 * first drawing call to the flip returning, with the CPU otherwise idle.  The
 * engine's drawing is priced separately (vcmi_bench, AE350-006), so a frame
 * here is the driver's floor, not a prediction of VCMI's frame rate.
 *
 * Two passes of FRAMES frames each:
 *
 *   renderer  the bars and box drawn by the renderer itself
 *             (SDL_RenderClear, SDL_RenderFillRect), presented
 *   engine    the second half of G1: the path VCMI 1.7.5 uses
 *             (client/renderSDL/ScreenHandler.cpp, VCMI-004).  A streaming
 *             ARGB8888 texture, its pixels aliased by a screen surface; the
 *             frame drawn into that surface with SDL's blitter (SDL_FillRect
 *             and SDL_BlitSurface, an opaque sprite and an alpha-blended
 *             one); then SDL_RenderCopy of the whole texture, SDL_RenderFlush
 *             and SDL_RenderPresent, timed as three parts.  The texture
 *             must be the page the raster shows, so that the copy is
 *             skipped (sdl2-tinyvcmi-zerocopy.patch, core-log entry 43).
 *   update    the engine path as VCMI mostly draws: the whole frame once,
 *             then per frame only the box's old rectangle restored from a
 *             background copy and the box drawn at its new place, which is
 *             what a single-buffered display tears least on.
 *
 * After every present the page the raster shows is read back and must hold
 * the frame just drawn.
 *
 * Run it with tools/load_ae350.py after the hand-over.
 */
#include <stdint.h>
#include <stdio.h>

#include <SDL.h>

#include "tinyvcmi.h"

#define FRAMES  180u    /* three seconds at 60 Hz */

static uint32_t *const page0 = (uint32_t *)TV_VIDEO_BASE;

/* Defined only by the diagnostic SDL build (SDL_TRACE=1
   tools/build_sdl2.sh, firmware/sdl/SDL_trace_tinyvcmi.c); weak, so against
   the normal library it is absent and trace() does nothing. */
extern volatile int tv_sdl_trace __attribute__((weak));

static void trace(int on)
{
	if (&tv_sdl_trace) {
		fflush(stdout);
		tv_sdl_trace = on;
	}
}

static int fail(const char *what)
{
	printf("BAD %s: %s\n", what, SDL_GetError());
	return 1;
}

#define AMASK 0xff000000u
#define RMASK 0x00ff0000u
#define GMASK 0x0000ff00u
#define BMASK 0x000000ffu

/* The engine path's sprite and where it goes: an opaque 64x64 checker the
   box never crosses in FRAMES frames, and a half-transparent red one. */
#define UPDATE_FRAMES 600u /* the update pass, ten seconds at 60 Hz */
#define SPRITE   64
#define SPRITE_X 1100
#define SPRITE_Y 560
#define ALPHA_X  40
#define ALPHA_Y  420

static uint64_t ns_since(uint64_t t0)
{
	return (tv_cycles64() - t0) * 1000u / (TV_CORE_HZ / 1000000u);
}

/* The frame's checks on the page the raster shows: the box's centre white,
   bar 1 red and, on the engine path, the opaque sprite's first pixel.
   Returns 1 for a wrong frame, printed if fewer than four were before. */
static int check_shown(int i, const SDL_Rect *box, int sprite, uint32_t before)
{
	const uint32_t *shown = (const uint32_t *)(uintptr_t)TV_VID_BASE;
	const int rx = 3 * TV_VID_WIDTH / 16, ry = 16;
	/* A sample the box covers is the box's, so it is not checked. */
#define UNDER_BOX(px, py) ((px) >= box->x && (px) < box->x + box->w && \
                           (py) >= box->y && (py) < box->y + box->h)
	uint32_t b = shown[(box->y + 64) * TV_VID_WIDTH + box->x + 64] & 0xffffffu;
	uint32_t r = UNDER_BOX(rx, ry) ? 0xff0000u
	           : shown[ry * TV_VID_WIDTH + rx] & 0xffffffu;
	uint32_t s = (!sprite || UNDER_BOX(SPRITE_X, SPRITE_Y)) ? 0x00ffffu
	           : shown[SPRITE_Y * TV_VID_WIDTH + SPRITE_X] & 0xffffffu;
#undef UNDER_BOX

	if (b == 0xffffffu && r == 0xff0000u && s == 0x00ffffu)
		return 0;
	if (before >= 4)
		return 1;
	printf("BAD-FRAME %d base %08lx box %06lx bar %06lx sprite %06lx\n", i,
	       (unsigned long)TV_VID_BASE, (unsigned long)b, (unsigned long)r,
	       (unsigned long)s);
	return 1;
}

/* G1's second half: VCMI's presentation path.  Returns 0 if every frame
   was shown right. */
static int engine_path(SDL_Renderer *ren)
{
	SDL_Texture *tex;
	SDL_Surface *screen, *sprite, *glass;
	void *pixels;
	int pitch, i;
	uint32_t shown_wrong = 0;
	uint64_t t0, draw_ns = 0, copy_ns = 0, present_ns = 0;
	uint32_t blits = 0;

	tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_ARGB8888,
	                        SDL_TEXTUREACCESS_STREAMING, TV_VID_WIDTH,
	                        TV_VID_HEIGHT);
	if (!tex)
		return fail("SDL_CreateTexture");
	SDL_SetTextureBlendMode(tex, SDL_BLENDMODE_NONE);
	/* As ScreenHandler does for the software renderer: lock once, keep the
	   pointer, and let a surface alias the texture's memory. */
	if (SDL_LockTexture(tex, NULL, &pixels, &pitch) != 0)
		return fail("SDL_LockTexture");
	SDL_UnlockTexture(tex);
	screen = SDL_CreateRGBSurfaceFrom(pixels, TV_VID_WIDTH, TV_VID_HEIGHT, 32,
	                                  pitch, RMASK, GMASK, BMASK, AMASK);
	if (!screen)
		return fail("SDL_CreateRGBSurfaceFrom");
	SDL_SetSurfaceBlendMode(screen, SDL_BLENDMODE_NONE);
	printf("engine path: texture pixels %08lx, pitch %d\n",
	       (unsigned long)(uintptr_t)pixels, pitch);
	/* The tinyvcmi driver is single-buffered and the software renderer,
	   patched (sdl2-tinyvcmi-zerocopy.patch), makes a window-sized
	   streaming texture over the shown page, so SDL_RenderCopy has nothing
	   to copy.  Anywhere else, the copy is back. */
	if ((uintptr_t)pixels != TV_VIDEO_BASE) {
		printf("BAD engine path: the texture is not the shown page\n");
		return 1;
	}

	sprite = SDL_CreateRGBSurface(0, SPRITE, SPRITE, 32, RMASK, GMASK, BMASK,
	                              AMASK);
	glass = SDL_CreateRGBSurface(0, SPRITE, SPRITE, 32, RMASK, GMASK, BMASK,
	                             AMASK);
	if (!sprite || !glass)
		return fail("SDL_CreateRGBSurface");
	for (int y = 0; y < SPRITE; y++)
		for (int x = 0; x < SPRITE; x++) {
			((uint32_t *)sprite->pixels)[y * sprite->pitch / 4 + x] =
			    ((x ^ y) & 8) ? 0xff0000ffu : 0xff00ffffu;
			((uint32_t *)glass->pixels)[y * glass->pitch / 4 + x] =
			    0x80ff0000u;
		}
	SDL_SetSurfaceBlendMode(sprite, SDL_BLENDMODE_NONE);
	SDL_SetSurfaceBlendMode(glass, SDL_BLENDMODE_BLEND);

	for (i = 0; i < (int)FRAMES; i++) {
		SDL_Rect bar, at;
		int b;

		t0 = tv_cycles64();
		SDL_FillRect(screen, NULL, SDL_MapRGB(screen->format, 0, 0, 0));
		for (b = 0; b < 8; b++) {
			bar.x = (int)(b * TV_VID_WIDTH / 8);
			bar.y = 0;
			bar.w = (int)(TV_VID_WIDTH / 8);
			bar.h = (int)(TV_VID_HEIGHT / 2);
			SDL_FillRect(screen, &bar,
			             SDL_MapRGB(screen->format, (b & 1) ? 255 : 0,
			                        (b & 2) ? 255 : 0, (b & 4) ? 255 : 0));
		}
		at.x = SPRITE_X;
		at.y = SPRITE_Y;
		if (SDL_BlitSurface(sprite, NULL, screen, &at) != 0)
			return fail("SDL_BlitSurface");
		at.x = ALPHA_X + (i % 64);
		at.y = ALPHA_Y;
		if (SDL_BlitSurface(glass, NULL, screen, &at) != 0)
			return fail("SDL_BlitSurface alpha");
		blits += 2;
		bar.x = (int)((i * 7u) % (TV_VID_WIDTH - 128u));
		bar.y = (int)((i * 5u) % (TV_VID_HEIGHT - 128u));
		bar.w = 128;
		bar.h = 128;
		SDL_FillRect(screen, &bar, SDL_MapRGB(screen->format, 255, 255, 255));
		draw_ns += ns_since(t0);

		/* ScreenHandler::presentScreenTexture */
		t0 = tv_cycles64();
		if (SDL_RenderCopy(ren, tex, NULL, NULL) != 0)
			return fail("SDL_RenderCopy");
		SDL_RenderFlush(ren);
		copy_ns += ns_since(t0);

		t0 = tv_cycles64();
		SDL_RenderPresent(ren);
		present_ns += ns_since(t0);

		shown_wrong += check_shown(i, &bar, 1, shown_wrong);
		if ((i % 30) == 29) {
			printf("engine frame %d\n", i + 1);
			fflush(stdout);
		}
	}

	printf("engine path: %d frames, %lu blits; per frame: draw %lu us, "
	       "RenderCopy+Flush %lu us, present %lu us, total %lu us\n",
	       i, (unsigned long)blits,
	       (unsigned long)(draw_ns / FRAMES / 1000u),
	       (unsigned long)(copy_ns / FRAMES / 1000u),
	       (unsigned long)(present_ns / FRAMES / 1000u),
	       (unsigned long)((draw_ns + copy_ns + present_ns) / FRAMES / 1000u));
	printf("engine path: shown page checked on %d frames, %lu wrong\n", i,
	       (unsigned long)shown_wrong);

	/* The update pass: a background made once, then only what moves. */
	{
		SDL_Surface *bg = SDL_CreateRGBSurface(0, TV_VID_WIDTH,
		                                       TV_VID_HEIGHT, 32, RMASK,
		                                       GMASK, BMASK, AMASK);
		SDL_Rect bar, at, box, old;
		uint32_t up_wrong = 0;
		uint64_t up_ns = 0;
		int b;

		if (!bg)
			return fail("SDL_CreateRGBSurface background");
		SDL_SetSurfaceBlendMode(bg, SDL_BLENDMODE_NONE);
		SDL_FillRect(bg, NULL, SDL_MapRGB(bg->format, 0, 0, 0));
		for (b = 0; b < 8; b++) {
			bar.x = (int)(b * TV_VID_WIDTH / 8);
			bar.y = 0;
			bar.w = (int)(TV_VID_WIDTH / 8);
			bar.h = (int)(TV_VID_HEIGHT / 2);
			SDL_FillRect(bg, &bar,
			             SDL_MapRGB(bg->format, (b & 1) ? 255 : 0,
			                        (b & 2) ? 255 : 0, (b & 4) ? 255 : 0));
		}
		at.x = SPRITE_X;
		at.y = SPRITE_Y;
		SDL_BlitSurface(sprite, NULL, bg, &at);
		at.x = ALPHA_X;
		at.y = ALPHA_Y;
		SDL_BlitSurface(glass, NULL, bg, &at);
		SDL_BlitSurface(bg, NULL, screen, NULL);
		old.w = old.h = 0;
		old.x = old.y = 0;

		/* Ten seconds at the display's 60 Hz, so the picture can be
		   watched: each frame waits for the next raster frame, outside
		   the timed part. */
		for (i = 0; i < (int)UPDATE_FRAMES; i++) {
			uint32_t f = TV_VID_FRAMES;

			while (TV_VID_FRAMES == f)
				;
			t0 = tv_cycles64();
			if (old.w)
				SDL_BlitSurface(bg, &old, screen, &old);
			box.x = (int)((i * 7u) % (TV_VID_WIDTH - 128u));
			box.y = (int)((i * 5u) % (TV_VID_HEIGHT - 128u));
			box.w = box.h = 128;
			SDL_FillRect(screen, &box,
			             SDL_MapRGB(screen->format, 255, 255, 255));
			old = box;
			if (SDL_RenderCopy(ren, tex, NULL, NULL) != 0)
				return fail("SDL_RenderCopy");
			SDL_RenderFlush(ren);
			SDL_RenderPresent(ren);
			up_ns += ns_since(t0);
			up_wrong += check_shown(i, &box, 1, up_wrong);
		}
		printf("update path: %d frames; per frame %lu us; shown page "
		       "checked on %d frames, %lu wrong\n", i,
		       (unsigned long)(up_ns / UPDATE_FRAMES / 1000u), i,
		       (unsigned long)up_wrong);
		SDL_FreeSurface(bg);
		shown_wrong += up_wrong;
	}

	SDL_FreeSurface(glass);
	SDL_FreeSurface(sprite);
	SDL_FreeSurface(screen);
	SDL_DestroyTexture(tex);
	return shown_wrong ? 1 : 0;
}

int main(void)
{
	SDL_Window *win;
	SDL_Renderer *ren;
	SDL_RendererInfo info;
	SDL_Event ev;
	SDL_version ver;
	uint64_t t0, draw_ns = 0, flip_ns = 0;
	uint32_t drawn = 0, flipped = 0, wrong = 0;
	int i, rc = 0;

	SDL_GetVersion(&ver);
	printf("TinyVCMI SDL %d.%d.%d\n", ver.major, ver.minor, ver.patch);
	fflush(stdout);

	/* VIDEO only: SDL's timer subsystem starts a thread, which this core
	   cannot do, so it is built disabled (SDL_TIMERS_DISABLED) and
	   SDL_GetTicks comes straight from the cycle counter instead. */
	if (SDL_Init(SDL_INIT_VIDEO) != 0)
		return fail("SDL_Init");
	printf("step A: SDL_Init returned\n"); fflush(stdout);
	printf("step B: %d video driver(s)\n", SDL_GetNumVideoDrivers());
	fflush(stdout);

	trace(1);
	win = SDL_CreateWindow("TinyVCMI G1", SDL_WINDOWPOS_CENTERED,
	                       SDL_WINDOWPOS_CENTERED, TV_VID_WIDTH,
	                       TV_VID_HEIGHT, 0);
	if (!win)
		return fail("SDL_CreateWindow");
	printf("step C: window ok\n"); fflush(stdout);

	/* VCMI asks for the software renderer and reads its name back
	   (VCMI-004), so prove that is what we get. */
	ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_SOFTWARE);
	if (!ren)
		return fail("SDL_CreateRenderer");
	trace(0);
	printf("step D: renderer ok\n"); fflush(stdout);
	if (SDL_GetRendererInfo(ren, &info) != 0)
		return fail("SDL_GetRendererInfo");
	printf("renderer %s, window %dx%d\n", info.name, TV_VID_WIDTH,
	       TV_VID_HEIGHT);

	for (i = 0; i < (int)FRAMES; i++) {
		SDL_Rect bar;
		int b;

		t0 = tv_cycles64();

		/* Colour bars and a moving box: fills and solid rects, the
		   two renderer calls VCMI's software path leans on. */
		SDL_SetRenderDrawColor(ren, 0, 0, 0, 255);
		SDL_RenderClear(ren);
		for (b = 0; b < 8; b++) {
			bar.x = (int)(b * TV_VID_WIDTH / 8);
			bar.y = 0;
			bar.w = (int)(TV_VID_WIDTH / 8);
			bar.h = (int)(TV_VID_HEIGHT / 2);
			SDL_SetRenderDrawColor(ren, (b & 1) ? 255 : 0,
			                       (b & 2) ? 255 : 0,
			                       (b & 4) ? 255 : 0, 255);
			if (SDL_RenderFillRect(ren, &bar) != 0)
				return fail("SDL_RenderFillRect");
			drawn++;
		}
		bar.x = (int)((i * 7u) % (TV_VID_WIDTH - 128u));
		bar.y = (int)((i * 5u) % (TV_VID_HEIGHT - 128u));
		bar.w = 128;
		bar.h = 128;
		SDL_SetRenderDrawColor(ren, 255, 255, 255, 255);
		if (SDL_RenderFillRect(ren, &bar) != 0)
			return fail("SDL_RenderFillRect");
		drawn++;

		draw_ns += (tv_cycles64() - t0) * 1000u / (TV_CORE_HZ / 1000000u);

		t0 = tv_cycles64();
		SDL_RenderPresent(ren);
		flip_ns += (tv_cycles64() - t0) * 1000u / (TV_CORE_HZ / 1000000u);
		flipped++;

		/* The page the raster now shows must be this frame. */
		wrong += check_shown(i, &bar, 0, wrong);

		while (SDL_PollEvent(&ev))
			if (ev.type == SDL_QUIT)
				i = (int)FRAMES;
		if ((i % 30) == 29) {
			printf("frame %d\n", i + 1);
			fflush(stdout);
		}
	}

	printf("drew %lu rects and flipped %lu frames in %lu us\n",
	       (unsigned long)drawn, (unsigned long)flipped,
	       (unsigned long)((draw_ns + flip_ns) / 1000u));
	printf("per frame: draw %lu us, flip %lu us, total %lu us\n",
	       (unsigned long)(draw_ns / flipped / 1000u),
	       (unsigned long)(flip_ns / flipped / 1000u),
	       (unsigned long)((draw_ns + flip_ns) / flipped / 1000u));
	printf("video base %08lx, frames %lu, LATE %lu\n",
	       (unsigned long)TV_VID_BASE, (unsigned long)TV_VID_FRAMES,
	       (unsigned long)TV_VID_LATE);

	printf("shown page checked on %lu frames, %lu wrong\n",
	       (unsigned long)flipped, (unsigned long)wrong);
	if (flipped != FRAMES || wrong)
		rc = 1;
	/* the frame buffer the driver handed out must be one of the two pages */
	if ((uintptr_t)page0 != TV_VIDEO_BASE && TV_VID_BASE == 0)
		rc = 1;

	printf("renderer path done\n");
	if (engine_path(ren) != 0)
		rc = 1;

	SDL_DestroyRenderer(ren);
	SDL_DestroyWindow(win);
	SDL_Quit();

	printf(rc == 0 ? "TinyVCMI G1 PASS\n" : "TinyVCMI G1 FAIL\n");
	return rc;
}
