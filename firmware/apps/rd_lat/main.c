/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Where a cached DDR3 read's time goes, from the A25 to the PHY and back.
 *
 * Core-log entry 30 measured a cached read at 477 A25 cycles a 32-byte line,
 * about 640 ns and 50 MB/s, against 51.5 cycles a line for the write-back.
 * The read was latency-bound: one line miss at a time, each a round trip.
 * The bridge now reads up to three lines ahead of each lookup (its prefetch
 * depth, exts_perf's PF_DEPTH).  This bench runs each pass at depths 0 to 3,
 * reading the counters of fpga/ae350_ddr3/exts_perf.sv (bus clock) and
 * ddr3_perf.v (PCLK) around it:
 *
 *   port wait     bus clocks the RAM port held HREADY low, per line: the part
 *                 of the line's time the fabric owns; the rest is the A25's
 *                 and the AE350's own
 *   port idle     bus clocks the RAM port had no transfer, per line: the
 *                 AE350's own time between beats
 *   DDR3 wait     bus clocks the bridge waited on a line from the DDR3 to
 *                 answer a beat, per line, and per demand miss
 *   hit beat      bus clocks a beat answered without a demand read waits
 *   prefetch      lines read ahead, and lookups one of them served, per line
 *   PCLK side     per CPU read: the arbiter's wait, then from taken to the
 *                 word back; within that, from ddr3_ctl taking it to its READ
 *                 in the PHY (queueing, ACTIVATE, PRECHARGE, refresh) and
 *                 from the READ to the word back (the fixed read latency).
 *                 Timed one read at a time, so shown at depth 0 only
 *
 * Passes, each over the same 115,200 lines (3.6 MiB):
 *
 *   seq8     every word of every line, in order, as entry 30's read pass
 *   seq1     word 0 of every line, in order: the line's cost without the
 *            CPU's work on its words
 *   scatter  word 0 of every line, 7919 lines apart, so most reads open a
 *            row another closed
 *
 * The video unit is off: ddr3_perf times one read at a time and is right only
 * while the CPU's reads are the only ones. Clock rates are measured against
 * the A25's mcycle, not assumed.  The depth is left at 2, its reset value.
 * Each pass also prints ddr3_perf's video and CPU word counts and its tap
 * (ddr3_arb's state and the bridge's PCLK reads in flight).
 *
 * Run it with: tools/load_ae350.py build/firmware/apps/rd_lat/rd_lat.elf
 */
#include <stdint.h>
#include <stdio.h>

#include "tinyvcmi.h"

#define LINES   115200u
#define WORDS   8u
#define SPAN    ((uintptr_t)LINES * 32u)
#define STRIDE  7919u /* lines; prime, so coprime with LINES */

static uint32_t *const base = (uint32_t *)(TV_VIDEO_BASE + (4u << 20));
static volatile uint32_t checksum;

enum { B_CLK, B_BEATS, B_BEAT_T, B_MISSES, B_MISS_T, B_STALL_T, B_LO };
enum { B_PF = B_LO, B_PFHIT, B_IDLE_T, B_N };
enum { P_RD, P_WR, P_WAIT, P_OPEN, P_ISSUE, P_DATA, P_MAX, P_PCLK,
       P_VRD, P_VRET, P_CRET, P_TAP, P_N };

struct counts {
	uint64_t cyc;
	uint32_t bus[B_N];
	uint32_t pclk[P_N];
};

/* Counters after the next two PCLK snapshots, so the PCLK words cover all
 * that happened before the call; the PCLK and bus words are of one moment to
 * within a snapshot period, about 10 us. */
static void take(struct counts *c)
{
	uint32_t n0 = TV_PERF_NSNAP, n;

	while (TV_PERF_NSNAP - n0 < 2)
		;
	do {
		n = TV_PERF_NSNAP;
		for (int i = 0; i < P_VRD; i++)
			c->pclk[i] = TV_PERF_SNAP(i);
		for (int i = P_VRD; i < P_N; i++)
			c->pclk[i] = TV_PERF_SNAP_HI(i);
		c->cyc = tv_cycles64();
		for (int i = 0; i < B_LO; i++)
			c->bus[i] = TV_PERF_REG(0x04 + 4 * i);
		for (int i = B_LO; i < B_N; i++)
			c->bus[i] = TV_PERF_REG(0x44 + 4 * (i - B_LO));
	} while (TV_PERF_NSNAP != n);
}

static void diff(struct counts *d, const struct counts *a, const struct counts *b)
{
	d->cyc = b->cyc - a->cyc;
	for (int i = 0; i < B_N; i++)
		d->bus[i] = b->bus[i] - a->bus[i];
	for (int i = 0; i < P_N; i++)
		d->pclk[i] = b->pclk[i] - a->pclk[i];
	d->pclk[P_MAX] = b->pclk[P_MAX]; /* not counts */
	d->pclk[P_TAP] = b->pclk[P_TAP];
}

static void x10(uint64_t v)
{
	printf("%6lu.%1lu", (unsigned long)(v / 10), (unsigned long)(v % 10));
}

/* clocks of a domain that ticked dom times while the A25 ticked cyc, over
 * count events, in tenths of ns each */
static uint64_t ns_x10(uint32_t clocks, uint32_t dom, uint64_t cyc, uint32_t count)
{
	if (!dom || !count)
		return 0;
	return (uint64_t)clocks * cyc * 40u / (3u * (uint64_t)dom * count);
}

/* clocks per event, in tenths */
static uint64_t per_x10(uint32_t clocks, uint32_t count)
{
	return count ? (uint64_t)clocks * 10u / count : 0;
}

static void row(const char *name, uint32_t clocks, uint32_t dom, uint64_t cyc,
		uint32_t count, const char *unit)
{
	printf("    %-28s", name);
	x10(per_x10(clocks, count));
	printf(" %-5s", unit);
	x10(ns_x10(clocks, dom, cyc, count));
	printf(" ns\r\n");
}

static void report(const char *name, unsigned depth, const struct counts *d)
{
	const uint32_t *b = d->bus, *p = d->pclk;
	uint32_t hits = b[B_BEATS] - b[B_MISSES];
	uint32_t hit_t = b[B_BEAT_T] > b[B_MISS_T] ? b[B_BEAT_T] - b[B_MISS_T] : 0;

	printf("\r\n%s depth %u: %lu lines, A25", name, depth, (unsigned long)LINES);
	x10(d->cyc * 10u / LINES);
	printf(" cycles/line =");
	x10(d->cyc * 40u / (3u * LINES));
	printf(" ns/line\r\n    bus");
	x10((uint64_t)b[B_CLK] * 7500u / d->cyc);
	printf(" MHz, PCLK");
	x10((uint64_t)p[P_PCLK] * 7500u / d->cyc);
	printf(" MHz; per line: beats");
	x10(per_x10(b[B_BEATS], LINES));
	printf(", misses");
	x10(per_x10(b[B_MISSES], LINES));
	printf(", prefetches");
	x10(per_x10(b[B_PF], LINES));
	printf(", served");
	x10(per_x10(b[B_PFHIT], LINES));
	printf(", CPU reads");
	x10(per_x10(p[P_RD], LINES));
	printf(", writes");
	x10(per_x10(p[P_WR], LINES));
	printf("\r\n");

	row("port wait, per line", b[B_STALL_T], b[B_CLK], d->cyc, LINES, "bus");
	row("port idle, per line", b[B_IDLE_T], b[B_CLK], d->cyc, LINES, "bus");
	row("DDR3 wait, per line", b[B_MISS_T], b[B_CLK], d->cyc, LINES, "bus");
	row("DDR3 wait, per miss", b[B_MISS_T], b[B_CLK], d->cyc, b[B_MISSES], "bus");
	row("hit beat wait, per hit (~)", hit_t, b[B_CLK], d->cyc, hits, "bus");
	printf("    PCLK: video reads %lu, words %lu; CPU words %lu; tap %08lx\r\n",
	       (unsigned long)p[P_VRD], (unsigned long)p[P_VRET],
	       (unsigned long)p[P_CRET], (unsigned long)p[P_TAP]);
	if (depth != 0)
		return;
	row("PCLK arbiter wait, per read", p[P_WAIT], p[P_PCLK], d->cyc, p[P_RD], "pclk");
	row("PCLK taken to word, per read", p[P_OPEN], p[P_PCLK], d->cyc, p[P_RD], "pclk");
	row("  ctl taken to READ", p[P_ISSUE], p[P_PCLK], d->cyc, p[P_RD], "pclk");
	row("  READ to word from ctl", p[P_DATA], p[P_PCLK], d->cyc, p[P_RD], "pclk");
	printf("    longest: taken to word %lu pclk, ctl taken to READ %lu pclk\r\n",
	       (unsigned long)(p[P_MAX] >> 16), (unsigned long)(p[P_MAX] & 0xffffu));
}

static void pass_seq8(void)
{
	uint32_t sum = 0;

	for (uintptr_t off = 0; off < SPAN; off += 32) {
		const volatile uint32_t *q = (const volatile uint32_t *)((uintptr_t)base + off);

		for (unsigned w = 0; w < WORDS; w++)
			sum ^= q[w];
	}
	checksum = sum;
}

static void pass_seq1(void)
{
	uint32_t sum = 0;

	for (uintptr_t off = 0; off < SPAN; off += 32)
		sum ^= *(const volatile uint32_t *)((uintptr_t)base + off);
	checksum = sum;
}

static void pass_scatter(void)
{
	uint32_t sum = 0, line = 0;

	for (uint32_t i = 0; i < LINES; i++) {
		sum ^= *(const volatile uint32_t *)((uintptr_t)base + 32u * line);
		line += STRIDE;
		if (line >= LINES)
			line -= LINES;
	}
	checksum = sum;
}

static void measure(const char *name, void (*pass)(void))
{
	struct counts a, b, d;

	for (unsigned depth = 0; depth < 4; depth++) {
		TV_PERF_PF_DEPTH = depth;
		take(&a);
		pass();
		take(&b);
		/* the wait in take, 20 us at most, is in the pass's time: under 0.1 % */
		diff(&d, &a, &b);
		report(name, depth, &d);
	}
	TV_PERF_PF_DEPTH = 2;
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	printf("\r\nTinyVCMI DDR3 read latency: %lu lines of 32 bytes\r\n",
	       (unsigned long)LINES);
	if (TV_PERF_ID != TV_PERF_ID_VALUE) {
		printf("no read-latency counters (ID %08lx): an image before exts_perf\r\n",
		       (unsigned long)TV_PERF_ID);
		printf("TinyVCMI RD LAT DONE\r\n");
		return 1;
	}
	TV_VID_CTRL = 0;

	/* known data, then a read pass, so the dirty lines are written back
	 * before anything is measured */
	for (uintptr_t off = 0; off < SPAN; off += 4)
		*(volatile uint32_t *)((uintptr_t)base + off) = (uint32_t)off;
	pass_seq8();

	measure("seq8", pass_seq8);
	measure("seq1", pass_seq1);
	measure("scatter", pass_scatter);

	printf("TinyVCMI RD LAT DONE\r\n");
	return 0;
}
