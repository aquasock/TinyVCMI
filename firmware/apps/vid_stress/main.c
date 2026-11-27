/* SPDX-License-Identifier: GPL-3.0-only
 *
 * The video unit's fetches beside heavy CPU traffic through ahb_ddr3. For
 * RUN_S seconds it bounces a filled box between two pages, flipping at the
 * vertical blank, and each frame also writes a 64 KiB block of a pattern at
 * 0x60000000 and checks the block written 128 frames before. A flip that is
 * still pending after 100 ms is counted and reported instead of waited on,
 * so a stuck flip shows apart from a stuck bus. Every ten seconds it prints
 * frames, flips, LATE, blocks, bad words and timeouts; it exits 0 if none of
 * the last three moved.
 */
#include <stdint.h>
#include <stdio.h>
#include "tinyvcmi.h"
#define W TV_VID_WIDTH
#define H TV_VID_HEIGHT
#define BOX 128
#ifndef RUN_S
#define RUN_S 600u
#endif
#define NB 256u
#define BW (16384u)            /* words per 64 KiB block */
static uint32_t *const page[2] = {
	(uint32_t *)TV_VIDEO_BASE, (uint32_t *)(TV_VIDEO_BASE + (4u << 20)) };
static uint32_t *const chk = (uint32_t *)0x60000000u;
static uint32_t gen[NB];
static inline uint32_t pat(uint32_t g, uint32_t b, uint32_t i)
{
	uint32_t x = g * 0x9e3779b9u ^ b * 0x85ebca6bu ^ i * 0xc2b2ae35u;
	return x ^ (x >> 15);
}
static void fill(uint32_t *fb, int bx, int by, uint32_t c)
{
	for (int y = by; y < by + BOX; y++)
		for (int x = bx; x < bx + BOX; x++)
			fb[y * W + x] = c;
}
int main(void)
{
	uint32_t frames0, late0, flips = 0, seconds = 0, errs = 0, tmo = 0, blocks = 0;
	int bx = 100, by = 80, dx = 7, dy = 5, ox[2] = {100, 100}, oy[2] = {80, 80};
	unsigned back = 1, b = 0;
	uint64_t second;
	for (unsigned i = 0; i < W * H; i++) page[0][i] = page[1][i] = 0x202020u;
	tv_dcache_wbinval();
	TV_VID_BASE = (uint32_t)(uintptr_t)page[0];
	TV_VID_CTRL = 1;
	frames0 = TV_VID_FRAMES; late0 = TV_VID_LATE;
	printf("STRESS on, frames %lu\n", (unsigned long)frames0);
	second = tv_cycles64() + TV_CORE_HZ;
	while (seconds < RUN_S) {
		uint32_t *fb = page[back];
		fill(fb, ox[back], oy[back], 0x202020u);
		bx += dx; by += dy;
		if (bx < 1 || bx > (int)W - 1 - BOX) { dx = -dx; bx += 2 * dx; }
		if (by < 1 || by > (int)H - 1 - BOX) { dy = -dy; by += 2 * dy; }
		fill(fb, bx, by, 0x2060c0u + (flips & 0xff) * 0x010000u);
		ox[back] = bx; oy[back] = by;
		/* check traffic: write block b, verify block b+128 */
		{
			uint32_t *p = chk + b * BW, g = ++gen[b];
			for (uint32_t i = 0; i < BW; i++) p[i] = pat(g, b, i);
			unsigned v = (b + NB / 2) % NB;
			if (gen[v]) {
				uint32_t *q = chk + v * BW;
				for (uint32_t i = 0; i < BW; i++)
					if (q[i] != pat(gen[v], v, i)) {
						if (errs < 10)
							printf("BAD blk %u word %lu got %08lx want %08lx\n", v,
							       (unsigned long)i, (unsigned long)q[i],
							       (unsigned long)pat(gen[v], v, i));
						errs++;
					}
			}
			b = (b + 1) % NB; blocks++;
		}
		tv_dcache_wbinval();
		TV_VID_BASE = (uint32_t)(uintptr_t)fb;
		{
			uint64_t end = tv_cycles64() + TV_CORE_HZ / 10;
			while (TV_VID_STATUS & TV_VID_STATUS_PENDING)
				if (tv_cycles64() > end) {
					tmo++;
					printf("PENDING timeout: status %lx frames %lu\n",
					       (unsigned long)TV_VID_STATUS, (unsigned long)TV_VID_FRAMES);
					break;
				}
		}
		back ^= 1u; flips++;
		if (tv_cycles64() >= second) {
			second += TV_CORE_HZ; seconds++;
			if (seconds % 10 == 0 || errs || tmo)
				printf("STRESS %lu s: frames %lu flips %lu late %lu blocks %lu errs %lu tmo %lu\n",
				       (unsigned long)seconds, (unsigned long)(TV_VID_FRAMES - frames0),
				       (unsigned long)flips, (unsigned long)(TV_VID_LATE - late0),
				       (unsigned long)blocks, (unsigned long)errs, (unsigned long)tmo);
		}
	}
	printf("STRESS %s\n", errs || tmo || TV_VID_LATE != late0 ? "BAD" : "OK");
	return errs || tmo;
}
