/* SPDX-License-Identifier: GPL-3.0-only
 *
 * How many dirty-line writebacks the A25 can keep in flight, which decides
 * whether a buffered drain in ahb_ddr3 can pay or whether the write path is
 * capped by the CPU side.
 *
 * Entry 24 (firmware/apps/write_cost) settled that a 32-byte line costs 738.0
 * cycles to write whatever the number of stores inside it, so the price is one
 * serialized round trip per line -- 74 bus clocks at 75 MHz -- with nothing
 * outstanding behind it. Entry 25 built the obvious fix, gathering a line's
 * four doublewords into one 256-bit DDR3 write, and it bought 11 per cent for
 * about 11 MHz of bus_clk. What entry 26 left open is whether the serialization
 * is the A25's or the bridge's, and this bench separates them:
 *
 *   E1  anchor        full-line store and read per line, to reproduce 738.0
 *                     and 513.3 and prove the board is in entry 24's state
 *   E2  evict         dirty a whole 32 KiB D-cache, or half or a quarter of it,
 *                     then time one write-back-and-invalidate: this is pure
 *                     eviction traffic with no fills mixed in, so the cost per
 *                     written-back line says whether writebacks stream
 *   E3  overlap       one store to a fresh line, then a dependent ALU chain of
 *                     N cycles, N swept: if the store retires and the core
 *                     computes while the writeback drains, the per-line cost
 *                     stays flat until N passes the drain window; if the store
 *                     stalls the pipeline, it is flat nowhere
 *   E4  back-to-back  K fresh-line stores with no work between them: a cost per
 *                     line that falls with K means several are overlapped
 *   E5  uncached      with the D-cache off, one crossing round trip per read,
 *                     then the bridge's one-line buffer hit measured as the
 *                     difference between two reads of a line and one, which
 *                     separates the crossing from the per-transfer handshake
 *
 * E3 and E5 use the D-cache to make the two sides visible: E3 needs the store
 * to go through the cache as VCMI's stores do, and E5 needs it not to, so the
 * bench can time a single transfer.
 *
 * The video unit is read and left as it was found; the usual run has it off,
 * as in write_cost. The span is write_cost's 3.6 MiB, so the numbers compare
 * directly.
 *
 * Run it with: tools/load_ae350.py build/firmware/apps/write_depth/write_depth.elf
 */
#include <stdint.h>
#include <stdio.h>

#include "tinyvcmi.h"

/* 115,200 lines of 32 bytes is one 1280x720 XRGB8888 screen, write_cost's
 * span, so every figure here is in the same units as entries 23 to 25. */
#define LINES   115200u
#define WORDS   8u
#define SPAN    ((uint64_t)LINES * 32u)

#define LINE_BYTES 32u
#define CACHE_BYTES (32u << 10)
#define CACHE_LINES (CACHE_BYTES / LINE_BYTES)

#define RUNS 3

/* Inside the 16 MiB the runtime keeps below the block RAM, as write_cost. */
static uint32_t *const base = (uint32_t *)(TV_VIDEO_BASE + (4u << 20));
static volatile uint32_t checksum;

/* mcache_ctl bit 1 is the L1 D-cache; there is no helper for turning it off
 * in tinyvcmi.h because nothing but a diagnostic should. */
#define MCACHE_CTL_L1D 0x2u

static inline uint32_t tv_mcache_ctl_read(void)
{
	uint32_t value;

	__asm__ volatile("csrr %0, 0x7ca" : "=r"(value));
	return value;
}

static inline void tv_mcache_ctl_write(uint32_t value)
{
	__asm__ volatile("csrw 0x7ca, %0" :: "r"(value) : "memory");
	/* The CSR write takes effect at the pipeline, so every access after it
	 * is ordered behind the change. */
	__asm__ volatile("fence" ::: "memory");
}

static void dcache_off(void)
{
	tv_dcache_wbinval();
	tv_mcache_ctl_write(tv_mcache_ctl_read() & ~MCACHE_CTL_L1D);
}

static void dcache_on(void)
{
	tv_dcache_wbinval();
	tv_mcache_ctl_write(tv_mcache_ctl_read() | MCACHE_CTL_L1D);
}

static uint32_t per_line_x10(uint64_t cycles, uint32_t lines)
{
	return (uint32_t)(cycles * 10u / lines);
}

static void report(const char *name, uint32_t best, uint32_t worst,
		   const char *note)
{
	printf("  %-12s best %6lu.%1lu worst %6lu.%1lu cycles/line  %s\r\n",
	       name, (unsigned long)(best / 10), (unsigned long)(best % 10),
	       (unsigned long)(worst / 10), (unsigned long)(worst % 10), note);
}

/* A dependent ALU chain of n iterations, so the core has real work to do
 * between two stores. The seed is passed in from the caller's accumulator and
 * the result folded back, which keeps it live without a store. */
static uint32_t chain(uint32_t n, uint32_t seed)
{
	uint32_t a = seed;

	for (uint32_t i = 0; i < n; i++)
		__asm__ volatile("addi %0, %0, 1" : "+r"(a) :: "memory");
	return a;
}

/* E1: all eight words of every line, write_cost's seq_full. */
static uint64_t pass_full(void)
{
	uint64_t t0 = tv_cycles64();

	for (uintptr_t off = 0; off < SPAN; off += LINE_BYTES) {
		volatile uint32_t *p = (volatile uint32_t *)((uintptr_t)base + off);

		for (unsigned w = 0; w < WORDS; w++)
			p[w] = 0xa5a50000u + w;
	}
	return tv_cycles64() - t0;
}

/* E1: all eight words of every line, read_cost's read. */
static uint64_t pass_read(void)
{
	uint64_t t0 = tv_cycles64();
	uint32_t sum = 0;

	for (uintptr_t off = 0; off < SPAN; off += LINE_BYTES) {
		const volatile uint32_t *p =
			(const volatile uint32_t *)((uintptr_t)base + off);

		for (unsigned w = 0; w < WORDS; w++)
			sum ^= p[w];
	}
	if (sum == 0xdeadbeefu)
		checksum = sum;
	return tv_cycles64() - t0;
}

/* E2: dirty `lines` lines of the cache's own window, then time the whole
 * D-cache write-back and invalidation. The window starts below the span so
 * the two never share a line. The second timing adds one cold read, which can
 * only complete once every writeback has landed, so the difference says
 * whether the write-back command itself waits. */
static uint64_t pass_evict(uint32_t lines, uint64_t *with_read)
{
	uintptr_t window = (uintptr_t)base - (64u << 10);
	uint64_t t0, t1;

	/* Clean the cache first, so the only dirty lines when the timer starts
	 * are this window's: the earlier passes leave the span's lines dirty,
	 * and a write-back of those would be counted here. */
	tv_dcache_wbinval();
	for (uint32_t i = 0; i < lines; i++) {
		volatile uint32_t *p =
			(volatile uint32_t *)(window + i * LINE_BYTES);

		p[0] = 0xc0ffee00u + i;
	}

	t0 = tv_cycles64();
	tv_dcache_wbinval();
	t1 = tv_cycles64();

	/* One cold line read: 513 cycles of DDR3 latency, and a barrier on the
	 * writebacks if the command above did not wait for them. */
	{
		const volatile uint32_t *p =
			(const volatile uint32_t *)((uintptr_t)base + (uintptr_t)SPAN);

		if (p[0] == 0xdeadbeefu)
			checksum = p[0];
	}
	*with_read = tv_cycles64() - t0;
	return t1 - t0;
}

/* E3: one store to a fresh line, then a dependent chain of n iterations. */
static uint64_t pass_store_chain(uint32_t n)
{
	uint64_t t0 = tv_cycles64();
	uint32_t a = 1;

	for (uintptr_t off = 0; off < SPAN; off += LINE_BYTES) {
		volatile uint32_t *p = (volatile uint32_t *)((uintptr_t)base + off);

		p[0] = 0x51ab0000u + a;
		a = chain(n, a);
	}
	if (a == 0xdeadbeefu)
		checksum = a;
	return tv_cycles64() - t0;
}

/* E3's control: the same chains with no stores, so the store's own cost can
 * be taken out of pass_store_chain exactly. */
static uint64_t pass_chain_only(uint32_t n)
{
	uint64_t t0 = tv_cycles64();
	uint32_t a = 1;

	for (uintptr_t off = 0; off < SPAN; off += LINE_BYTES) {
		(void)off;
		a = chain(n, a);
	}
	if (a == 0xdeadbeefu)
		checksum = a;
	return tv_cycles64() - t0;
}

/* E4: k fresh-line stores with nothing between them. */
static uint64_t pass_group(uint32_t k)
{
	uint64_t t0 = tv_cycles64();

	for (uintptr_t off = 0; off < SPAN; off += (uintptr_t)LINE_BYTES * k) {
		for (uint32_t i = 0; i < k; i++) {
			volatile uint32_t *p = (volatile uint32_t *)
				((uintptr_t)base + off + i * LINE_BYTES);

			p[0] = 0x94000000u + i;
		}
	}
	return tv_cycles64() - t0;
}

/* E5: uncached, one read per line across the span. */
static uint64_t pass_uncached_read(uint32_t per_line)
{
	uint64_t t0 = tv_cycles64();
	uint32_t sum = 0;

	for (uintptr_t off = 0; off < SPAN; off += LINE_BYTES) {
		const volatile uint32_t *p =
			(const volatile uint32_t *)((uintptr_t)base + off);

		sum ^= p[0];
		if (per_line > 1)
			sum ^= p[WORDS - 1];
	}
	if (sum == 0xdeadbeefu)
		checksum = sum;
	return tv_cycles64() - t0;
}

/* E5: uncached, one store per line, so every store is its own crossing and
 * the next one waits for it. */
static uint64_t pass_uncached_write(void)
{
	uint64_t t0 = tv_cycles64();

	for (uintptr_t off = 0; off < SPAN; off += LINE_BYTES) {
		volatile uint32_t *p = (volatile uint32_t *)((uintptr_t)base + off);

		p[0] = 0x0c0ffee0u;
	}
	return tv_cycles64() - t0;
}

/* E6: uncached, all eight words of every line. With no D-cache there is no
 * fill and no writeback, so this is the write-around path: the only cost is
 * the bridge's posted writes, and comparing it with E1's cached full line
 * says how much of E1 is the cache's read-for-ownership fill. */
static uint64_t pass_uncached_full(void)
{
	uint64_t t0 = tv_cycles64();

	for (uintptr_t off = 0; off < SPAN; off += LINE_BYTES) {
		volatile uint32_t *p = (volatile uint32_t *)((uintptr_t)base + off);

		for (unsigned w = 0; w < WORDS; w++)
			p[w] = 0x6b000000u + w;
	}
	return tv_cycles64() - t0;
}

/* E6: half the words, in case the bus pairs two 32-bit stores into one 64-bit
 * AHB beat and the count of DDR3 writes matters. */
static uint64_t pass_uncached_every2(void)
{
	uint64_t t0 = tv_cycles64();

	for (uintptr_t off = 0; off < SPAN; off += LINE_BYTES) {
		volatile uint32_t *p = (volatile uint32_t *)((uintptr_t)base + off);

		p[0] = 0x11110000u;
		p[2] = 0x22220000u;
		p[4] = 0x33330000u;
		p[6] = 0x44440000u;
	}
	return tv_cycles64() - t0;
}

/* E7: uncached, the same line written as four 8-byte stores instead of eight
 * 4-byte ones. One transfer is one AHB beat, so if a 64-bit store costs what a
 * 32-bit store does, a driver that writes a line as four doublewords halves
 * the write path with no fabric change at all. */
static uint64_t pass_uncached_dword(void)
{
	uint64_t t0 = tv_cycles64();

	for (uintptr_t off = 0; off < SPAN; off += LINE_BYTES) {
		volatile uint64_t *p = (volatile uint64_t *)
			((uintptr_t)base + off);

		for (unsigned d = 0; d < WORDS / 2; d++)
			p[d] = 0x7d00000000000000ull + d;
	}
	return tv_cycles64() - t0;
}

/* E7: and two 16-byte stores, in case the core issues a pair as one transfer.
 * -march has no vector unit, so this is a memcpy-shaped store of two words. */
static uint64_t pass_uncached_quad(void)
{
	uint64_t t0 = tv_cycles64();

	for (uintptr_t off = 0; off < SPAN; off += LINE_BYTES) {
		volatile uint32_t *p = (volatile uint32_t *)
			((uintptr_t)base + off);

		for (unsigned q = 0; q < WORDS; q += 4) {
			p[q] = 0x7e000000u + q;
			p[q + 1] = 0x7e000000u + q + 1;
			p[q + 2] = 0x7e000000u + q + 2;
			p[q + 3] = 0x7e000000u + q + 3;
		}
	}
	return tv_cycles64() - t0;
}

/* The stores above must have landed: fill the span, drain it, read it back. */
static uint32_t verify(void)
{
	uint32_t bad = 0;

	for (uintptr_t off = 0; off < SPAN; off += LINE_BYTES) {
		volatile uint32_t *p = (volatile uint32_t *)((uintptr_t)base + off);

		for (unsigned w = 0; w < WORDS; w++)
			p[w] = 0x12340000u + (uint32_t)(off >> 5) + w;
	}
	tv_dcache_wbinval();
	for (uintptr_t off = 0; off < SPAN; off += LINE_BYTES) {
		const volatile uint32_t *p =
			(const volatile uint32_t *)((uintptr_t)base + off);

		for (unsigned w = 0; w < WORDS; w++)
			if (p[w] != 0x12340000u + (uint32_t)(off >> 5) + w)
				bad++;
	}
	return bad;
}

#define NSWEEP 6u
static const uint32_t sweep_n[NSWEEP] = { 0, 32, 64, 128, 256, 1024 };

int main(void)
{
	uint64_t best_full = 0, worst_full = 0;
	uint64_t best_read = 0, worst_read = 0;
	uint64_t ev[3][2], ev_worst[3][2];
	uint64_t sc_best[NSWEEP], sc_worst[NSWEEP], cb_best[NSWEEP];
	uint64_t grp[3], grp_worst[3];
	uint64_t ur_best = 0, ur_worst = 0, ur2_best = 0, ur2_worst = 0;
	uint64_t uw_best = 0, uw_worst = 0;
	uint64_t uf_best = 0, uf_worst = 0, ue_best = 0, ue_worst = 0;
	uint64_t ud_best = 0, ud_worst = 0, uq_best = 0, uq_worst = 0;
	static const uint32_t ev_lines[3] = { CACHE_LINES, CACHE_LINES / 2,
					      CACHE_LINES / 4 };
	static const uint32_t grp_k[3] = { 2, 4, 8 };
	uint32_t video_ctl = TV_VID_CTRL;
	uint32_t bad;

	setvbuf(stdout, NULL, _IONBF, 0);

	TV_VID_CTRL = 0;
	printf("\r\nTinyVCMI write depth: %lu lines of 32 bytes, %lu KiB span,"
	       " video off (was %lu)\r\n",
	       (unsigned long)LINES, (unsigned long)(SPAN >> 10),
	       (unsigned long)video_ctl);
	printf("cache: %lu KiB, %lu lines; mcache_ctl %08lx\r\n",
	       (unsigned long)(CACHE_BYTES >> 10), (unsigned long)CACHE_LINES,
	       (unsigned long)tv_mcache_ctl_read());

	bad = verify();
	printf("verify: %lu bad words of %lu\r\n", (unsigned long)bad,
	       (unsigned long)(LINES * WORDS));
	if (bad) {
		printf("BAD verify failed, the write path is not sound\r\n");
		TV_VID_CTRL = video_ctl;
		printf("TinyVCMI WRITE DEPTH DONE\r\n");
		return 1;
	}

	for (int r = 0; r < RUNS; r++) {
		uint64_t t;

		t = pass_full();
		best_full = r ? (t < best_full ? t : best_full) : t;
		worst_full = r ? (t > worst_full ? t : worst_full) : t;

		t = pass_read();
		best_read = r ? (t < best_read ? t : best_read) : t;
		worst_read = r ? (t > worst_read ? t : worst_read) : t;
	}

	printf("\nE1 anchor, caches on, video off, %u runs:\r\n", RUNS);
	report("E1 seq_full", per_line_x10(best_full, LINES),
	       per_line_x10(worst_full, LINES), "entry 24: 738.0");
	report("E1 read", per_line_x10(best_read, LINES),
	       per_line_x10(worst_read, LINES), "entry 24: 513.3");

	for (int s = 0; s < 3; s++) {
		ev[s][0] = ev[s][1] = 0;
		ev_worst[s][0] = ev_worst[s][1] = 0;
		for (int r = 0; r < RUNS; r++) {
			uint64_t plain, with;

			plain = pass_evict(ev_lines[s], &with);
			if (!r || plain < ev[s][0]) ev[s][0] = plain;
			if (!r || plain > ev_worst[s][0]) ev_worst[s][0] = plain;
			if (!r || with < ev[s][1]) ev[s][1] = with;
			if (!r || with > ev_worst[s][1]) ev_worst[s][1] = with;
		}
	}

	printf("\nE2 eviction of a dirty D-cache, one write-back per dirty line:\r\n");
	for (int s = 0; s < 3; s++) {
		char note[48];

		snprintf(note, sizeof note, "%lu lines, +cold read %lu.%lu",
			 (unsigned long)ev_lines[s],
			 (unsigned long)(per_line_x10(ev[s][1], ev_lines[s]) / 10),
			 (unsigned long)(per_line_x10(ev[s][1], ev_lines[s]) % 10));
		report(s == 0 ? "E2 evict all" :
		       s == 1 ? "E2 evict half" : "E2 evict qtr",
		       per_line_x10(ev[s][0], ev_lines[s]),
		       per_line_x10(ev_worst[s][0], ev_lines[s]), note);
	}

	for (unsigned i = 0; i < NSWEEP; i++) {
		uint64_t sb = 0, sw = 0, cb = 0;

		for (int r = 0; r < RUNS; r++) {
			uint64_t t = pass_store_chain(sweep_n[i]);

			sb = r ? (t < sb ? t : sb) : t;
			sw = r ? (t > sw ? t : sw) : t;

			t = pass_chain_only(sweep_n[i]);
			cb = r ? (t < cb ? t : cb) : t;
		}
		sc_best[i] = sb - cb;
		sc_worst[i] = sw - cb;
		cb_best[i] = cb;
	}

	printf("\nE3 one store to a fresh line, then a dependent chain of N"
	       " cycles:\r\n");
	for (unsigned i = 0; i < NSWEEP; i++) {
		char note[32];

		snprintf(note, sizeof note, "chain %lu cycles",
			 (unsigned long)sweep_n[i]);
		report("E3 overlap", per_line_x10(sc_best[i], LINES),
		       per_line_x10(sc_worst[i], LINES), note);
	}
	for (unsigned i = 0; i < NSWEEP; i++)
		printf("  chain control N=%lu: %lu.%lu cycles per iteration alone\r\n",
		       (unsigned long)sweep_n[i],
		       (unsigned long)(sweep_n[i] ? cb_best[i] / LINES / sweep_n[i] : 0),
		       (unsigned long)(sweep_n[i]
				      ? cb_best[i] / LINES * 10u / sweep_n[i] % 10u
				      : 0));

	for (int s = 0; s < 3; s++) {
		grp[s] = grp_worst[s] = 0;
		for (int r = 0; r < RUNS; r++) {
			uint64_t t = pass_group(grp_k[s]);

			if (!r || t < grp[s]) grp[s] = t;
			if (!r || t > grp_worst[s]) grp_worst[s] = t;
		}
	}

	printf("\nE4 K fresh-line stores back to back:\r\n");
	for (int s = 0; s < 3; s++) {
		char note[24];

		snprintf(note, sizeof note, "K = %lu", (unsigned long)grp_k[s]);
		report("E4 back2back", per_line_x10(grp[s], LINES),
		       per_line_x10(grp_worst[s], LINES), note);
	}

	dcache_off();
	for (int r = 0; r < RUNS; r++) {
		uint64_t t;

		t = pass_uncached_read(1);
		ur_best = r ? (t < ur_best ? t : ur_best) : t;
		ur_worst = r ? (t > ur_worst ? t : ur_worst) : t;

		t = pass_uncached_read(2);
		ur2_best = r ? (t < ur2_best ? t : ur2_best) : t;
		ur2_worst = r ? (t > ur2_worst ? t : ur2_worst) : t;

		t = pass_uncached_write();
		uw_best = r ? (t < uw_best ? t : uw_best) : t;
		uw_worst = r ? (t > uw_worst ? t : uw_worst) : t;

		t = pass_uncached_full();
		uf_best = r ? (t < uf_best ? t : uf_best) : t;
		uf_worst = r ? (t > uf_worst ? t : uf_worst) : t;

		t = pass_uncached_every2();
		ue_best = r ? (t < ue_best ? t : ue_best) : t;
		ue_worst = r ? (t > ue_worst ? t : ue_worst) : t;

		t = pass_uncached_dword();
		ud_best = r ? (t < ud_best ? t : ud_best) : t;
		ud_worst = r ? (t > ud_worst ? t : ud_worst) : t;

		t = pass_uncached_quad();
		uq_best = r ? (t < uq_best ? t : uq_best) : t;
		uq_worst = r ? (t > uq_worst ? t : uq_worst) : t;
	}
	dcache_on();

	printf("\nE5 uncached, one crossing per access (D-cache off):\r\n");
	report("E5 read", per_line_x10(ur_best, LINES),
	       per_line_x10(ur_worst, LINES), "one uncached word read");
	report("E5 read x2", per_line_x10(ur2_best, LINES),
	       per_line_x10(ur2_worst, LINES), "two words of the same line");
	report("E5 write", per_line_x10(uw_best, LINES),
	       per_line_x10(uw_worst, LINES), "one uncached word store");
	report("E6 ufull", per_line_x10(uf_best, LINES),
	       per_line_x10(uf_worst, LINES), "all 8 words, no cache at all");
	report("E6 uhalf", per_line_x10(ue_best, LINES),
	       per_line_x10(ue_worst, LINES), "words 0,2,4,6, no cache");
	report("E7 udword", per_line_x10(ud_best, LINES),
	       per_line_x10(ud_worst, LINES), "4 x 64-bit stores, no cache");
	report("E7 uquad", per_line_x10(uq_best, LINES),
	       per_line_x10(uq_worst, LINES), "8 x 32-bit in 2 groups, no cache");
	{
		uint32_t hit = per_line_x10(ur2_best - ur_best, LINES);
		uint32_t miss = per_line_x10(ur_best, LINES);

		printf("  => the bridge's buffer hit costs %lu.%lu cycles, the"
		       " crossing %lu.%lu\r\n",
		       (unsigned long)(hit / 10), (unsigned long)(hit % 10),
		       (unsigned long)(miss / 10), (unsigned long)(miss % 10));
	}

	/* The decision the design cycle turns on. Any 32-byte line crosses the
	 * bridge as four 8-byte AHB transfers, so the per-transfer cost is what
	 * to compare: E5's single uncached store times one transfer with nothing
	 * else in the way, E2 times a line's four writebacks with no fill and no
	 * CPU stall, and E6 times eight stores the same way. */
	{
		uint32_t anchor = per_line_x10(best_full, LINES);
		uint32_t transfer = per_line_x10(uw_best, LINES);
		uint32_t evict = per_line_x10(ev[0][0], ev_lines[0]);
		uint32_t per_dw = evict / 4u;
		uint32_t k8 = per_line_x10(grp[2], LINES);
		uint32_t flat = per_line_x10(sc_best[NSWEEP - 1], LINES);
		uint32_t ufull = per_line_x10(uf_best, LINES);

		printf("\nverdict, in cycles per 8-byte AHB transfer:\n");
		printf("  one uncached store costs %lu.%lu, so a transfer is the"
		       " unit here\r\n", (unsigned long)(transfer / 10),
		       (unsigned long)(transfer % 10));

		if (per_dw * 10u < transfer * 9u)
			printf("  writeback overlaps: %lu.%lu a transfer in an"
			       " eviction stream, so more than one is in flight\r\n",
			       (unsigned long)(per_dw / 10),
			       (unsigned long)(per_dw % 10));
		else if (per_dw * 10u > transfer * 11u)
			printf("  writeback is worse than a bare transfer: %lu.%lu"
			       " against %lu.%lu\r\n",
			       (unsigned long)(per_dw / 10),
			       (unsigned long)(per_dw % 10),
			       (unsigned long)(transfer / 10),
			       (unsigned long)(transfer % 10));
		else
			printf("  writeback does not overlap: %lu.%lu a transfer in an"
			       " eviction stream is the bare %lu.%lu, four in series\r\n",
			       (unsigned long)(per_dw / 10),
			       (unsigned long)(per_dw % 10),
			       (unsigned long)(transfer / 10),
			       (unsigned long)(transfer % 10));

		if (k8 * 10u < anchor * 9u)
			printf("  back-to-back stores amortise: K = 8 costs %lu.%lu"
			       " a line, so more than one is in flight\r\n",
			       (unsigned long)(k8 / 10),
			       (unsigned long)(k8 % 10));
		else
			printf("  back-to-back stores do not amortise: K = 8 costs"
			       " %lu.%lu a line, the same as one at a time\r\n",
			       (unsigned long)(k8 / 10),
			       (unsigned long)(k8 % 10));

		if (flat * 10u + 200u < anchor * 10u)
			printf("  a chain between stores recovers %lu.%lu cycles,"
			       " so the miss is not a fixed stall\r\n",
			       (unsigned long)((anchor - flat) / 10),
			       (unsigned long)((anchor - flat) % 10));
		else
			printf("  a chain between stores recovers nothing: each miss"
			       " stalls the core for its whole cost\r\n");

		if (ufull * 10u < anchor * 9u)
			printf("  the cached line costs %lu.%lu against %lu.%lu"
			       " uncached, so the cache costs %lu.%lu a line\r\n",
			       (unsigned long)(anchor / 10),
			       (unsigned long)(anchor % 10),
			       (unsigned long)(ufull / 10),
			       (unsigned long)(ufull % 10),
			       (unsigned long)((anchor - ufull) / 10),
			       (unsigned long)((anchor - ufull) % 10));
		else
			printf("  bypassing the D-cache does not help: %lu.%lu"
			       " cycles a line against %lu.%lu\r\n",
			       (unsigned long)(ufull / 10),
			       (unsigned long)(ufull % 10),
			       (unsigned long)(anchor / 10),
			       (unsigned long)(anchor % 10));

		printf("  a fill costs %lu.%lu cached and %lu.%lu uncached,"
		       " which is %lu.%lu transfers\r\n",
		       (unsigned long)(per_line_x10(best_read, LINES) / 10),
		       (unsigned long)(per_line_x10(best_read, LINES) % 10),
		       (unsigned long)(per_line_x10(ur_best, LINES) / 10),
		       (unsigned long)(per_line_x10(ur_best, LINES) % 10),
		       (unsigned long)(per_line_x10(ur_best, LINES) / transfer),
		       (unsigned long)(per_line_x10(ur_best, LINES) * 100u / transfer % 100u));
	}

	TV_VID_CTRL = video_ctl;
	printf("TinyVCMI WRITE DEPTH DONE\r\n");
	return 0;
}
