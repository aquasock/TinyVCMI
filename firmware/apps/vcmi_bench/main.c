/* SPDX-License-Identifier: GPL-3.0-only
 *
 * G0, the A25's drawing bench: what each of VCMI's screen operations costs
 * in A25 cycles per pixel, measured on the board before any engine code is
 * written. The plan (docs/vcmi-port-plan.md) uses these figures to choose the
 * canvas size and to predict the frame rate, so every operation here is one
 * the engine really performs:
 *
 *   fill32    a 32-bit store per pixel, the cost of clearing or filling
 *   copy32    a 32-bit load and store, the cost of a page copy
 *   expand8   an 8-bit indexed source through a 256-entry palette to 32-bit,
 *             the shape of an H3 sprite, index 0 transparent
 *   alpha32   32-bit source over 32-bit destination with an 8-bit alpha,
 *             the shape of a translucent VCMI surface
 *   scale2x   a nearest-neighbour 2x upscale, the fallback for a smaller
 *             internal canvas
 *   cached    a fill that stays inside the 32 KiB L1 D-cache, repeated until
 *             it has written a whole screen's pixels, so the difference
 *             against fill32 is the price of reaching the DDR3 at all
 *   flip      the D-cache write-back plus the BASE write, what presenting a
 *             frame costs, and how long the vertical blank takes to take it
 *
 * Each operation runs RUNS times into an alternate buffer and the fastest and
 * slowest are reported, because the DDR3 and the video's reads make the
 * worst case as interesting as the best. The video unit is enabled first, so
 * the bench runs with scanout reading the same array, and LATE is reported
 * after every operation: a non-zero LATE means the A25's traffic delayed a
 * line, which is a result, not a fault.
 *
 * The screen shows the last frame drawn, so the numbers arrive over a picture
 * that is being redrawn rather than over a stale one.
 *
 * Run it with: tools/load_ae350.py build/firmware/apps/vcmi_bench/vcmi_bench.elf
 */
#include <stdint.h>
#include <stdio.h>

#include "tinyvcmi.h"

#define W        TV_VID_WIDTH
#define H        TV_VID_HEIGHT
#define PIXELS   ((uint64_t)W * H)
#define RUNS     3

/* 16 KiB, half the 32 KiB L1 D-cache, so a fill of it is served from the
 * cache alone and does not reach the DDR3. */
#define CACHED_PIXELS 4096u

/* Frame buffers, inside the 16 MiB the runtime keeps below the block RAM.
 * 0x7f000000 and 4 MiB above it are the two pages video_test uses, so this
 * bench draws where that test draws. */
static uint32_t *const fb_dest  = (uint32_t *)TV_VIDEO_BASE;
static uint32_t *const fb_src32 = (uint32_t *)(TV_VIDEO_BASE + (4u << 20));
static uint32_t *const fb_scale = (uint32_t *)(TV_VIDEO_BASE + (8u << 20));
static uint8_t  *const fb_idx8  = (uint8_t *)(TV_VIDEO_BASE + (12u << 20));
static uint32_t *const cached_fb = (uint32_t *)(TV_VIDEO_BASE + (14u << 20));

/* A palette with every entry distinct and none of them zero, so a store of
 * the wrong entry shows as a wrong pixel rather than as a skipped one. */
static uint32_t palette[256];
static uint8_t  idx_pattern[W];
static uint32_t scale_src[W / 2];

static uint32_t checksum;

static void build_patterns(void)
{
	for (unsigned i = 0; i < 256; i++)
		palette[i] = 0xff000000u |
			     (uint32_t)((i * 7919u) & 0xff) << 16 |
			     (uint32_t)((i * 104729u) & 0xff) << 8 |
			     (uint32_t)(i & 0xff);
	for (unsigned x = 0; x < W; x++)
		idx_pattern[x] = (uint8_t)((x * 37u + 11u) & 0xff);
	for (unsigned x = 0; x < W / 2; x++)
		scale_src[x] = 0xff000000u | (x * 4099u & 0xffffffu);

	for (unsigned i = 0; i < W * 360u; i++)
		fb_scale[i] = 0xff000000u | (i * 2654435761u & 0xffffffu);
	for (unsigned i = 0; i < W * 360u; i++)
		fb_src32[i] = 0x80000000u | (i * 40503u & 0xffffffu);
}

/* c / PIXELS in cycles per pixel, to two decimals, in tenths of a cycle so
 * the division stays in integers: returns cycles * 10 / pixels. */
static uint32_t cycles_x10_per_pixel(uint64_t cycles)
{
	return (uint32_t)(cycles * 10u / PIXELS);
}

static void report(const char *name, uint64_t best, uint64_t worst)
{
	uint32_t lo = cycles_x10_per_pixel(best);
	uint32_t hi = cycles_x10_per_pixel(worst);

	/* cycles_x10 is tenths; print as x.y */
	printf("  %-9s best %6lu.%1lu worst %6lu.%1lu cycles/pixel"
	       "  %9lu us full screen\r\n",
	       name, (unsigned long)(lo / 10), (unsigned long)(lo % 10),
	       (unsigned long)(hi / 10), (unsigned long)(hi % 10),
	       (unsigned long)(best / (TV_CORE_HZ / 1000000u)));
}

/* ---- the operations ------------------------------------------------ */

static uint64_t op_fill32(void)
{
	uint64_t t0 = tv_cycles64();

	for (unsigned i = 0; i < PIXELS; i++)
		fb_dest[i] = 0xff102030u;
	return tv_cycles64() - t0;
}

static uint64_t op_copy32(void)
{
	uint64_t t0 = tv_cycles64();
	uint32_t sum = 0;

	for (unsigned i = 0; i < PIXELS; i++) {
		uint32_t v = fb_src32[i];
		fb_dest[i] = v;
		sum ^= v;
	}
	checksum ^= sum;
	return tv_cycles64() - t0;
}

/* Index 0 is transparent, as an H3 sprite's is. */
static uint64_t op_expand8(void)
{
	uint64_t t0 = tv_cycles64();

	for (unsigned y = 0; y < H; y++) {
		const uint8_t *s = fb_idx8 + (uint64_t)y * W;
		uint32_t *d = fb_dest + (uint64_t)y * W;

		for (unsigned x = 0; x < W; x++) {
			uint8_t k = s[x];

			if (k)
				d[x] = palette[k];
		}
	}
	return tv_cycles64() - t0;
}

/* A fill the caches serve, repeated to the same pixel count as fill32. */
static uint64_t op_cached(void)
{
	uint64_t t0 = tv_cycles64();
	unsigned done = 0;

	while (done < PIXELS) {
		for (unsigned i = 0; i < CACHED_PIXELS; i++)
			cached_fb[i] = 0xff102030u;
		done += CACHED_PIXELS;
	}
	return tv_cycles64() - t0;
}

/* Blend with the exact divide-by-255 that costs three multiply-adds and a
 * shift per channel. */
static uint64_t op_alpha32(void)
{
	uint64_t t0 = tv_cycles64();
	uint32_t sum = 0;

	for (unsigned i = 0; i < PIXELS; i++) {
		uint32_t s = fb_src32[i];
		uint32_t d = fb_dest[i];
		uint32_t a = s >> 24;
		uint32_t ia = 255u - a;
		uint32_t rb, g, t;

		if (a == 0) {
			sum ^= d;
			continue;
		}
		if (a == 255) {
			fb_dest[i] = s;
			sum ^= s;
			continue;
		}
		rb = (((s >> 16) & 0xffu) * a + ((d >> 16) & 0xffu) * ia);
		g  = (((s >> 8) & 0xffu) * a + ((d >> 8) & 0xffu) * ia);
		t  = ((s & 0xffu) * a + (d & 0xffu) * ia);
		rb = (rb + (rb >> 8)) >> 8;
		g  = (g + (g >> 8)) >> 8;
		t  = (t + (t >> 8)) >> 8;
		fb_dest[i] = 0xff000000u | rb << 16 | g << 8 | t;
		sum ^= fb_dest[i];
	}
	checksum ^= sum;
	return tv_cycles64() - t0;
}

/* 640x360 to 1280x720, nearest neighbour: each source pixel is read four
 * times, which is the cache-friendly shape of the fallback. */
static uint64_t op_scale2x(void)
{
	uint64_t t0 = tv_cycles64();

	for (unsigned y = 0; y < H; y++) {
		const uint32_t *s = fb_scale + (uint64_t)(y / 2) * (W / 2);
		uint32_t *d = fb_dest + (uint64_t)y * W;

		for (unsigned x = 0; x < W / 2; x++) {
			uint32_t v = s[x];

			d[2 * x] = v;
			d[2 * x + 1] = v;
		}
	}
	return tv_cycles64() - t0;
}

/* Present: write the D-cache back, hand the unit the new BASE, and wait for
 * it to take it at the next vertical blank. The two halves are reported
 * apart, because the wait is the display's, not the CPU's. */
static void op_flip(uint64_t *wb, uint64_t *wait)
{
	uint32_t frames = TV_VID_FRAMES;
	uint64_t t0 = tv_cycles64();

	tv_dcache_wbinval();
	TV_VID_BASE = (uint32_t)(uintptr_t)fb_dest;
	*wb = tv_cycles64() - t0;

	t0 = tv_cycles64();
	/* The unit takes BASE at the blank and clears PENDING with it. */
	while ((TV_VID_STATUS & TV_VID_STATUS_PENDING) &&
	       tv_cycles64() - t0 < TV_CORE_HZ / 10u)
		;
	*wait = tv_cycles64() - t0;

	(void)frames;
}

int main(void)
{
	uint64_t best[7], worst[7];
	const char *names[7] = { "fill32", "copy32", "expand8",
				 "alpha32", "scale2x", "flip", "cached" };
	uint64_t wb = 0, wait = 0;
	uint32_t late0, late1;

	setvbuf(stdout, NULL, _IONBF, 0);
	printf("\r\nTinyVCMI G0 bench, %ux%u, %lu cycles per ms\r\n",
	       (unsigned)W, (unsigned)H, (unsigned long)(TV_CORE_HZ / 1000u));
	printf("video id %08lx\r\n", (unsigned long)TV_VID_ID);
	if (TV_VID_ID != TV_VID_ID_VALUE) {
		printf("BAD video unit absent\r\n");
		return 1;
	}

	build_patterns();
	for (unsigned y = 0; y < H; y++)
		for (unsigned x = 0; x < W; x++)
			fb_idx8[(uint64_t)y * W + x] = idx_pattern[x];

	/* Show the buffer the bench draws into, and let one blank pass so LATE
	 * starts from a settled screen. */
	TV_VID_BASE = (uint32_t)(uintptr_t)fb_dest;
	TV_VID_CTRL = 1;
	while (!(TV_VID_STATUS & TV_VID_STATUS_VBLANK))
		;
	while (TV_VID_STATUS & TV_VID_STATUS_VBLANK)
		;
	late0 = TV_VID_LATE;

	for (int r = 0; r < RUNS; r++) {
		uint64_t c;

		c = op_fill32();
		best[0] = r ? (c < best[0] ? c : best[0]) : c;
		worst[0] = r ? (c > worst[0] ? c : worst[0]) : c;

		c = op_copy32();
		best[1] = r ? (c < best[1] ? c : best[1]) : c;
		worst[1] = r ? (c > worst[1] ? c : worst[1]) : c;

		c = op_expand8();
		best[2] = r ? (c < best[2] ? c : best[2]) : c;
		worst[2] = r ? (c > worst[2] ? c : worst[2]) : c;

		c = op_alpha32();
		best[3] = r ? (c < best[3] ? c : best[3]) : c;
		worst[3] = r ? (c > worst[3] ? c : worst[3]) : c;

		c = op_scale2x();
		best[4] = r ? (c < best[4] ? c : best[4]) : c;
		worst[4] = r ? (c > worst[4] ? c : worst[4]) : c;

		op_flip(&wb, &wait);
		best[5] = r ? (wb < best[5] ? wb : best[5]) : wb;
		worst[5] = r ? (wb > worst[5] ? wb : worst[5]) : wb;

		c = op_cached();
		best[6] = r ? (c < best[6] ? c : best[6]) : c;
		worst[6] = r ? (c > worst[6] ? c : worst[6]) : c;
	}

	late1 = TV_VID_LATE;

	printf("\r\nthe A25, caches on, %u runs, best and worst:\r\n", RUNS);
	for (int i = 0; i < 7; i++)
		report(names[i], best[i], worst[i]);

	printf("\r\nflip: write-back %lu us, blank wait %lu us\r\n",
	       (unsigned long)(wb / (TV_CORE_HZ / 1000000u)),
	       (unsigned long)(wait / (TV_CORE_HZ / 1000000u)));

	/* A whole-screen redraw at the best rate, and the frame rate that
	 * implies with nothing else in the frame. */
	{
		uint64_t whole = best[0];
		uint64_t fps_x100 = whole ? PIXELS * 100u * TV_CORE_HZ / whole / PIXELS : 0;

		printf("whole-screen fill %lu us = %lu.%02lu fps alone\r\n",
		       (unsigned long)(whole / (TV_CORE_HZ / 1000000u)),
		       (unsigned long)(TV_CORE_HZ / whole),
		       (unsigned long)((TV_CORE_HZ % whole) * 100u / whole));
		(void)fps_x100;
	}

	printf("LATE %lu -> %lu (lines shown before their pixels were in)\r\n",
	       (unsigned long)late0, (unsigned long)late1);
	printf("checksum %08lx\r\n", (unsigned long)checksum);
	printf("TinyVCMI G0 DONE\r\n");
	return 0;
}
