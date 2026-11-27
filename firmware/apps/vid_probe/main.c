/* SPDX-License-Identifier: GPL-3.0-only
 *
 * The reproducer for the lost DDR3 read of core-log entry 31: video_test
 * with a 100 ms timeout on every flip, so a flip stuck in the video unit
 * prints the unit's registers and exits 2 while a stuck bus stays silent
 * and leaves the STALL report (fpga/ae350_ddr3/ae350_sys.sv) to say why.
 * The hang, when it comes, comes in the first restore() after the video is
 * switched on, on a cached read of page 1 that is never answered.
 *
 * As video_test: it checks the unit's ID, times a full-frame fill, draws the
 * test screen on both pages, then for RUN_S seconds bounces a 128-pixel box,
 * drawing into the page not shown and flipping at the vertical blank, and
 * once a second prints frames, flips and LATE. It exits 0 if LATE did not
 * move and the flips kept up with the frames.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "tinyvcmi.h"

#define W      TV_VID_WIDTH
#define H      TV_VID_HEIGHT
#define BOX    128
#define RUN_S  60u

static uint32_t *const page[2] = {
	(uint32_t *)TV_VIDEO_BASE,
	(uint32_t *)(TV_VIDEO_BASE + (4u << 20)),
};

static uint32_t background(unsigned x, unsigned y)
{
	static const uint32_t bars[8] = {
		0xffffff, 0xffff00, 0x00ffff, 0x00ff00,
		0xff00ff, 0xff0000, 0x0000ff, 0x000000,
	};
	uint32_t v;

	if (x == 0 || y == 0 || x == W - 1 || y == H - 1)
		return 0xffffff;
	if (y < H / 2)
		return bars[x / (W / 8)];
	v = x * 255u / (W - 1);
	switch ((y - H / 2) / (H / 8)) {
	case 0:  return v << 16;
	case 1:  return v << 8;
	case 2:  return v;
	default: return v * 0x010101u;
	}
}

static void draw_background(uint32_t *fb)
{
	for (unsigned y = 0; y < H; y++)
		for (unsigned x = 0; x < W; x++)
			fb[y * W + x] = background(x, y);
}

static void restore(uint32_t *fb, int bx, int by)
{
	for (int y = by; y < by + BOX; y++)
		for (int x = bx; x < bx + BOX; x++)
			fb[y * W + x] = background((unsigned)x, (unsigned)y);
}

static void box(uint32_t *fb, int bx, int by, uint32_t colour)
{
	for (int y = by; y < by + BOX; y++)
		for (int x = bx; x < bx + BOX; x++)
			fb[y * W + x] = (x - bx < 4 || y - by < 4 || bx + BOX - 1 - x < 4 ||
					 by + BOX - 1 - y < 4) ? 0xffffff : colour;
}

/* Show fb at the next vertical blank, and wait until it is taken. */
static void flip(uint32_t *fb)
{
	tv_dcache_wbinval();
	TV_VID_BASE = (uint32_t)(uintptr_t)fb;
	uint64_t until = tv_cycles64() + TV_CORE_HZ / 10u;
	uint32_t st;

	while ((st = TV_VID_STATUS) & TV_VID_STATUS_PENDING)
		if (tv_cycles64() > until) {
			printf("BAD FLIP STUCK status %08lx frames %lu base %08lx ctrl %08lx late %lu fb %08lx\n",
			       (unsigned long)st, (unsigned long)TV_VID_FRAMES,
			       (unsigned long)TV_VID_BASE, (unsigned long)TV_VID_CTRL,
			       (unsigned long)TV_VID_LATE, (unsigned long)(uintptr_t)fb);
			for (int i = 0; i < 5; i++) {
				uint64_t w = tv_cycles64() + TV_CORE_HZ / 10u;
				while (tv_cycles64() < w)
					;
				printf("  then status %08lx frames %lu\n",
				       (unsigned long)TV_VID_STATUS, (unsigned long)TV_VID_FRAMES);
			}
			exit(2);
		}
}

int main(void)
{
	uint64_t t, second;
	uint32_t frames0, late0, flips = 0, seconds = 0;
	int bx = 100, by = 80, dx = 7, dy = 5;
	int old_x[2] = { bx, bx }, old_y[2] = { by, by };
	unsigned back = 1;

	if (TV_VID_ID != TV_VID_ID_VALUE) {
		printf("BAD VIDEO ID %08lx\n", (unsigned long)TV_VID_ID);
		return 1;
	}
	TV_VID_CTRL = 0;

	t = tv_cycles64();
	for (unsigned i = 0; i < W * H; i++)
		page[0][i] = 0;
	tv_dcache_wbinval();
	t = tv_cycles64() - t;
	printf("TinyVCMI VIDEO full-frame fill %lu us\n",
	       (unsigned long)(t / (TV_CORE_HZ / 1000000u)));

	draw_background(page[0]);
	draw_background(page[1]);
	flip(page[0]);
	TV_VID_CTRL = 1;
	frames0 = TV_VID_FRAMES;
	late0 = TV_VID_LATE;
	printf("TinyVCMI VIDEO on: 1280x720, page 0 at %08lx, frames %lu\n",
	       (unsigned long)(uintptr_t)page[0], (unsigned long)frames0);

	second = tv_cycles64() + TV_CORE_HZ;
	while (seconds < RUN_S) {
		uint32_t *fb = page[back];

		restore(fb, old_x[back], old_y[back]);
		bx += dx;
		by += dy;
		if (bx < 1 || bx > (int)W - 1 - BOX) { dx = -dx; bx += 2 * dx; }
		if (by < 1 || by > (int)H - 1 - BOX) { dy = -dy; by += 2 * dy; }
		box(fb, bx, by, 0x2060c0u + (flips & 0xff) * 0x010000u);
		old_x[back] = bx;
		old_y[back] = by;
		flip(fb);
		back ^= 1u;
		flips++;
		if (tv_cycles64() >= second) {
			second += TV_CORE_HZ;
			seconds++;
			printf("TinyVCMI VIDEO %lu s: frames %lu, flips %lu, LATE %lu\n",
			       (unsigned long)seconds,
			       (unsigned long)(TV_VID_FRAMES - frames0),
			       (unsigned long)flips,
			       (unsigned long)(TV_VID_LATE - late0));
		}
	}
	restore(page[back], old_x[back], old_y[back]);
	restore(page[back ^ 1u], old_x[back ^ 1u], old_y[back ^ 1u]);
	flip(page[0]);

	if (TV_VID_LATE != late0) {
		printf("BAD VIDEO LATE %lu\n", (unsigned long)(TV_VID_LATE - late0));
		return 1;
	}
	if (flips + 120u < (TV_VID_FRAMES - frames0)) {
		printf("BAD VIDEO flips %lu for %lu frames\n", (unsigned long)flips,
		       (unsigned long)(TV_VID_FRAMES - frames0));
		return 1;
	}
	printf("TinyVCMI VIDEO OK\n");
	return 0;
}
