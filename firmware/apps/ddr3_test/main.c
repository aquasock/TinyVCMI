/* SPDX-License-Identifier: GPL-3.0-only
 *
 * The DDR3 as the A25 sees it, with the caches on: what a miss costs, and
 * whether every word of the array holds what is written to it.
 *
 * The cost, in 750 MHz core cycles per access, measured as Tang-PSX's
 * software/programs/memlat measured it (AE350-003), so the two compare:
 *
 *   L16K ... L64M  dependent loads along a random single cycle (Sattolo)
 *                  through one 32-byte node per cache line, so each load
 *                  waits for the one before; 16 KiB fits the 32 KiB
 *                  D-cache, the rest do not, and 64 MiB spreads the lines
 *                  over every bank and thousands of rows
 *   Q4M            one load per consecutive line, independent of each other
 *   S4M            one store per line, two passes, so each store also
 *                  writes back the dirty line it evicts
 *
 * The D-cache is written back and invalidated before each measurement.
 *
 * Then the array: from the first MiB boundary after the program up to the
 * block RAM at 0x7fff0000, every word is written with a hash of its address
 * and read back, then with its inverse, for each seed (tv_test_words, with
 * the D-cache written back and invalidated before each read), so every bit
 * is seen at 0 and at 1 and every word's data names its address. The first
 * failure, if any, is reported as "BAD DDR3 A=<address> E=<expected>
 * G=<got> N=<failures>". Exits 0 when every word passed.
 */
#include <stdint.h>
#include <stdio.h>

#include "memtest.h"
#include "tinyvcmi.h"

#define LINE_BYTES  32u
#define CHASE_LOADS (1u << 20)
#define MIB         (1u << 20)

struct node {
	struct node *next;
	uint32_t pad[LINE_BYTES / 4u - 1u];
};

extern char _end[];

static struct node *nodes;     /* the measurement region, in the test region */
static uint32_t *order;        /* beside it */

/* A random single cycle through the first count nodes (Sattolo). */
static void build_chain(uint32_t count)
{
	uint32_t seed = 0x12345678u;
	for (uint32_t i = 0; i < count; i++)
		order[i] = i;
	for (uint32_t i = count - 1u; i > 0u; i--) {
		uint32_t j, t;
		seed = seed * 1664525u + 1013904223u;
		j = (uint32_t)(((uint64_t)seed * i) >> 32);   /* 0 .. i-1 */
		t = order[i];
		order[i] = order[j];
		order[j] = t;
	}
	for (uint32_t i = 0; i < count; i++)
		nodes[order[i]].next = &nodes[order[(i + 1u) % count]];
}

/* Cycles per dependent load, in tenths. */
static uint32_t chase(uint32_t bytes)
{
	struct node *p = &nodes[0];
	uint64_t t;
	build_chain(bytes / LINE_BYTES);
	tv_dcache_wbinval();
	t = tv_cycles64();
	for (uint32_t i = 0; i < CHASE_LOADS; i++)
		p = p->next;
	t = tv_cycles64() - t;
	__asm__ volatile("" : : "r"(p));
	return (uint32_t)(t * 10u / CHASE_LOADS);
}

/* Cycles per line for consecutive independent loads, in tenths. */
static uint32_t stream_read(uint32_t lines)
{
	uint32_t sum = 0;
	uint64_t t;
	tv_dcache_wbinval();
	t = tv_cycles64();
	for (uint32_t i = 0; i < lines; i++)
		sum += ((volatile struct node *)nodes)[i].pad[0];
	t = tv_cycles64() - t;
	__asm__ volatile("" : : "r"(sum));
	return (uint32_t)(t * 10u / lines);
}

/* Cycles per line for one store per line, dirty evictions included, in
 * tenths. */
static uint32_t stream_write(uint32_t lines)
{
	volatile struct node *region = nodes;
	uint64_t t;
	tv_dcache_wbinval();
	t = tv_cycles64();
	for (uint32_t pass = 0; pass < 2u; pass++)
		for (uint32_t i = 0; i < lines; i++)
			region[i].pad[0] = i + pass;
	t = tv_cycles64() - t;
	return (uint32_t)(t * 10u / (2u * lines));
}

static void report(const char *label, uint32_t tenths)
{
	printf("%s%lu.%lu", label, (unsigned long)(tenths / 10u),
	       (unsigned long)(tenths % 10u));
}

int main(void)
{
	static const uint32_t seeds[] = { 0x5eedf00du, 0x0badcafeu };
	uintptr_t start = ((uintptr_t)_end + MIB - 1u) & ~(uintptr_t)(MIB - 1u);
	uintptr_t end = TV_BRAM_BASE;
	uint32_t l16k, l256k, l4m, l64m, q4m, s4m;
	struct tv_result r = { 0, 0, 0, 0 };

	nodes = (struct node *)start;
	order = (uint32_t *)(start + (64u * MIB));
	printf("TinyVCMI DDR3 TEST program end %08lx, array %08lx to %08lx\n",
	       (unsigned long)(uintptr_t)_end, (unsigned long)start,
	       (unsigned long)end);

	l16k = chase(16u << 10);
	l256k = chase(256u << 10);
	l4m = chase(4u * MIB);
	l64m = chase(64u * MIB);
	q4m = stream_read(4u * MIB / LINE_BYTES);
	s4m = stream_write(4u * MIB / LINE_BYTES);
	report("TinyVCMI DDR3 LAT L16K ", l16k);
	report(" L256K ", l256k);
	report(" L4M ", l4m);
	report(" L64M ", l64m);
	report(" Q4M ", q4m);
	report(" S4M ", s4m);
	printf("\n");

	for (unsigned s = 0; s < sizeof seeds / sizeof seeds[0]; s++) {
		uint64_t t = tv_cycles64();
		tv_test_words(&r, seeds[s], 1, (volatile uint32_t *)start,
			      (volatile uint32_t *)end);
		t = tv_cycles64() - t;
		printf("TinyVCMI DDR3 PASS %u seed %08lx: %lu MiB written and "
		       "read twice in %lu ms, %lu failures\n", s + 1u,
		       (unsigned long)seeds[s],
		       (unsigned long)((end - start) / MIB),
		       (unsigned long)(t / (TV_CORE_HZ / 1000u)),
		       (unsigned long)r.failures);
	}
	if (r.failures) {
		printf("BAD DDR3 A=%08lx E=%08lx G=%08lx N=%lu\n",
		       (unsigned long)r.addr, (unsigned long)r.expected,
		       (unsigned long)r.got, (unsigned long)r.failures);
		return 1;
	}
	printf("TinyVCMI DDR3 FULL OK %lu MiB\n",
	       (unsigned long)((end - start) / MIB));
	return 0;
}
