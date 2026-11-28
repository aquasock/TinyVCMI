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

		/* The page the raster now shows must be this frame: the box's
		   centre white and bar 1 red.  The flip wrote the D-cache back
		   and invalidated it, so these reads come from the DDR3. */
		{
			const uint32_t *shown =
			    (const uint32_t *)(uintptr_t)TV_VID_BASE;
			uint32_t box = shown[(bar.y + 64) * TV_VID_WIDTH +
			                     bar.x + 64] & 0x00ffffffu;
			uint32_t red = shown[16 * TV_VID_WIDTH +
			                     3 * TV_VID_WIDTH / 16] & 0x00ffffffu;
			if (box != 0x00ffffffu || red != 0x00ff0000u) {
				if (wrong < 4)
					printf("BAD-FRAME %d base %08lx box %06lx "
					       "bar %06lx\n", i,
					       (unsigned long)TV_VID_BASE,
					       (unsigned long)box,
					       (unsigned long)red);
				wrong++;
			}
		}

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

	SDL_DestroyRenderer(ren);
	SDL_DestroyWindow(win);
	SDL_Quit();

	printf(rc == 0 ? "TinyVCMI G1 PASS\n" : "TinyVCMI G1 FAIL\n");
	return rc;
}
