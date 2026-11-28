/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Where the A25's DDR3 store cost comes from: per line or per store.
 *
 * G0 (firmware/apps/vcmi_bench, core-log entry 23) measured a 32-bit fill at
 * 92.3 cycles per pixel into the frame buffer, which is 738 cycles for each
 * 32-byte cache line, and 3.2 cycles a pixel for the same fill served from the
 * L1 data cache. That number decides which fix is worth building, and this
 * bench tells them apart:
 *
 *   seq_full   write all eight words of every line, the sequential fill G0 ran
 *   first      write only word 0 of every line, so the same number of lines is
 *              written with one eighth of the stores
 *   last       write only word 7 of every line, in case the offset matters
 *   every2     write words 0, 2, 4 and 6, half a line per line
 *
 * If first costs what seq_full does per line, the price is the line: each
 * written line pays a round trip however many of its words the CPU stores, so
 * a write-combining buffer inside a line cannot help and only overlapping
 * successive lines can. If first costs an eighth of it, the price is the
 * store, and combining eight stores into one line is worth eight times.
 *
 * Every case writes the same number of lines over the same 3.6 MiB span, so
 * the comparison holds row-buffer and bank behaviour as constant as this
 * firmware can.
 *
 * The video unit is turned off here, unlike G0, so the measurement is the
 * store path alone; the controller and the bridge are otherwise the same.
 * It must be turned off and not merely assumed off: the boot ROM does not
 * reset it, and a program run before this one (vcmi_bench) can leave the
 * raster scanning, which on the current bridge costs stores about 30 per cent
 * (core-log entry 39).
 *
 * Run it with: tools/load_ae350.py build/firmware/apps/write_cost/write_cost.elf
 */
#include <stdint.h>
#include <stdio.h>

#include "tinyvcmi.h"

/* 115,200 lines of 32 bytes is one 1280x720 XRGB8888 screen. */
#define LINES   115200u
#define WORDS   8u
#define SPAN    ((uint64_t)LINES * 32u)

/* Inside the 16 MiB the runtime keeps below the block RAM. */
static uint32_t *const base = (uint32_t *)(TV_VIDEO_BASE + (4u << 20));
static volatile uint32_t checksum;

#define RUNS 3

/* Cycles for the whole pass, in tenths, per line. */
static uint32_t per_line_x10(uint64_t cycles, uint32_t lines)
{
	return (uint32_t)(cycles * 10u / lines);
}

static void report(const char *name, uint64_t best, uint64_t worst,
		   uint32_t stores_per_line)
{
	uint32_t lo = per_line_x10(best, LINES);
	uint32_t hi = per_line_x10(worst, LINES);

	printf("  %-9s best %6lu.%1lu worst %6lu.%1lu cycles/line"
	       "  %s store(s)/line  %7lu ns/line\r\n",
	       name, (unsigned long)(lo / 10), (unsigned long)(lo % 10),
	       (unsigned long)(hi / 10), (unsigned long)(hi % 10),
	       stores_per_line == 8 ? "8" : stores_per_line == 4 ? "4" : "1",
	       (unsigned long)(best * 1000u / (TV_CORE_HZ / 1000000u) / LINES));
}

/* All eight words of each line. */
static uint64_t pass_full(void)
{
	uint64_t t0 = tv_cycles64();

	for (uintptr_t off = 0; off < SPAN; off += 32) {
		volatile uint32_t *p = (volatile uint32_t *)((uintptr_t)base + off);

		for (unsigned w = 0; w < WORDS; w++)
			p[w] = 0xa5a50000u + w;
	}
	return tv_cycles64() - t0;
}

/* One word per line, at the given word offset. */
static uint64_t pass_one(unsigned word)
{
	uint64_t t0 = tv_cycles64();

	for (uintptr_t off = 0; off < SPAN; off += 32) {
		volatile uint32_t *p = (volatile uint32_t *)((uintptr_t)base + off);

		p[word] = 0x5a5a0000u + word;
	}
	return tv_cycles64() - t0;
}

/* Words 0, 2, 4 and 6 of each line. */
static uint64_t pass_every2(void)
{
	uint64_t t0 = tv_cycles64();

	for (uintptr_t off = 0; off < SPAN; off += 32) {
		volatile uint32_t *p = (volatile uint32_t *)((uintptr_t)base + off);

		p[0] = 0x11110000u;
		p[2] = 0x22220000u;
		p[4] = 0x33330000u;
		p[6] = 0x44440000u;
	}
	return tv_cycles64() - t0;
}

/* Reads, for the same span, to put the write cost beside the read cost. */
static uint64_t pass_read(void)
{
	uint64_t t0 = tv_cycles64();
	uint32_t sum = 0;

	for (uintptr_t off = 0; off < SPAN; off += 32) {
		const volatile uint32_t *p =
			(const volatile uint32_t *)((uintptr_t)base + off);

		for (unsigned w = 0; w < WORDS; w++)
			sum ^= p[w];
	}
	if (sum == 0xdeadbeefu)
		checksum = sum;
	return tv_cycles64() - t0;
}

int main(void)
{
	uint64_t best[5], worst[5];
	const char *names[5] = { "seq_full", "first", "last", "every2", "read" };
	const uint32_t spl[5] = { 8, 1, 1, 4, 8 };
	uint64_t t;

	setvbuf(stdout, NULL, _IONBF, 0);
	TV_VID_CTRL = 0;	/* video off, whatever the last program left */
	printf("\r\nTinyVCMI write-path cost: %lu lines of 32 bytes, %lu KiB span\r\n",
	       (unsigned long)LINES, (unsigned long)(SPAN >> 10));

	for (int r = 0; r < RUNS; r++) {
		t = pass_full();
		best[0] = r ? (t < best[0] ? t : best[0]) : t;
		worst[0] = r ? (t > worst[0] ? t : worst[0]) : t;

		t = pass_one(0);
		best[1] = r ? (t < best[1] ? t : best[1]) : t;
		worst[1] = r ? (t > worst[1] ? t : worst[1]) : t;

		t = pass_one(WORDS - 1);
		best[2] = r ? (t < best[2] ? t : best[2]) : t;
		worst[2] = r ? (t > worst[2] ? t : worst[2]) : t;

		t = pass_every2();
		best[3] = r ? (t < best[3] ? t : best[3]) : t;
		worst[3] = r ? (t > worst[3] ? t : worst[3]) : t;

		t = pass_read();
		best[4] = r ? (t < best[4] ? t : best[4]) : t;
		worst[4] = r ? (t > worst[4] ? t : worst[4]) : t;
	}

	printf("\nthe A25, caches on, video off, %u runs:\r\n", RUNS);
	for (int i = 0; i < 5; i++)
		report(names[i], best[i], worst[i], spl[i]);

	/* The ratio that decides the fix. */
	{
		uint64_t full = best[0], one = best[1];
		uint32_t full_x10 = per_line_x10(full, LINES);
		uint32_t one_x10 = per_line_x10(one, LINES);

		printf("\nfirst/seq_full = %lu.%02lu of the cost"
		       " for one eighth of the stores\r\n",
		       (unsigned long)(one_x10 * 100u / full_x10 / 100u),
		       (unsigned long)(one_x10 * 100u / full_x10 % 100u));
		if (one_x10 * 10u > full_x10 * 7u)
			printf("=> the price is the LINE: combining inside a line"
			       " cannot help, only overlapping lines\r\n");
		else if (one_x10 * 10u < full_x10 * 3u)
			printf("=> the price is the STORE: combining eight stores"
			       " into one line is worth about eight times\r\n");
		else
			printf("=> mixed: both the line and the store cost\r\n");
	}

	printf("TinyVCMI WRITE COST DONE\r\n");
	return 0;
}
