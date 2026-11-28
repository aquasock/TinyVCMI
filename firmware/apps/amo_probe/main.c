/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Whether the A25 executes RV32A atomics correctly on each memory a program
 * can put a lock word in: a cached DDR3 word whose line is in the D-cache, a
 * block RAM word (the stack), a cached DDR3 word whose line has just been
 * written back and invalidated, and the same word with the D-cache off.  SDL2's spinlock is one
 * amoswap.w.aq (firmware/sdl/sdl2-riscv-atomics.patch), and nothing in this
 * project had executed an AMO before it.
 *
 * The cases run in the order least likely to hang first, because a hang
 * ends the program: an evicted line reloaded by an ordinary load before the
 * AMO, then lr.w/sc.w on an evicted line once, then a bounded LR/SC lock
 * loop on an evicted line without and with the ordinary load that SDL's
 * spinlock makes on every pass (firmware/sdl/sdl2-riscv-atomics.patch).  The two cases that hang, a
 * bare AMO on an evicted line and any AMO with the D-cache off (AE350-011),
 * are built only with `make HANG=1`, so that by default the program exits and
 * the board stays usable.  Each case prints its name before it runs, so a trap
 * or a hang names the case: a trap is reported by the runtime's handler, and an AHB transfer that
 * never completes by the fabric's STALL report.  Each case then prints what
 * the instruction returned and what memory holds, against the values the ISA
 * requires.
 */
#include <stdint.h>
#include <stdio.h>

#include "tinyvcmi.h"

static volatile uint32_t ddr3_word;   /* .bss, in the DDR3 */

static uint32_t amoswap(volatile uint32_t *p, uint32_t v)
{
	uint32_t old;
	__asm__ volatile("amoswap.w %0, %1, (%2)"
	                 : "=&r"(old) : "r"(v), "r"(p) : "memory");
	return old;
}

static uint32_t amoswap_aq(volatile uint32_t *p, uint32_t v)
{
	uint32_t old;
	__asm__ volatile("amoswap.w.aq %0, %1, (%2)"
	                 : "=&r"(old) : "r"(v), "r"(p) : "memory");
	return old;
}

static uint32_t amoadd(volatile uint32_t *p, uint32_t v)
{
	uint32_t old;
	__asm__ volatile("amoadd.w %0, %1, (%2)"
	                 : "=&r"(old) : "r"(v), "r"(p) : "memory");
	return old;
}

/* lr.w then sc.w of v; returns sc's result (0 is success) and the
   reserved value in *seen. */
static uint32_t lrsc(volatile uint32_t *p, uint32_t v, uint32_t *seen)
{
	uint32_t got, rc;
	__asm__ volatile("lr.w %0, (%2)\n\tsc.w %1, %3, (%2)"
	                 : "=&r"(got), "=&r"(rc) : "r"(p), "r"(v) : "memory");
	*seen = got;
	return rc;
}

static int fails;

static void check(const char *what, uint32_t got, uint32_t want)
{
	printf("  %-22s %08lx %s\n", what, (unsigned long)got,
	       got == want ? "ok" : "WRONG");
	if (got != want) {
		printf("    expected %08lx\n", (unsigned long)want);
		fails++;
	}
}

static void run(const char *name, volatile uint32_t *p)
{
	uint32_t seen, rc;

	printf("%s at %08lx\n", name, (unsigned long)(uintptr_t)p);
	fflush(stdout);

	*p = 0;
	check("amoswap.w old", amoswap(p, 1), 0);
	check("  memory", *p, 1);
	check("amoswap.w.aq old", amoswap_aq(p, 7), 1);
	check("  memory", *p, 7);
	check("amoswap.w.aq again", amoswap_aq(p, 7), 7);
	check("amoadd.w old", amoadd(p, 5), 7);
	check("  memory", *p, 12);
	rc = lrsc(p, 0x5a5a5a5a, &seen);
	check("lr.w value", seen, 12);
	check("sc.w result", rc, 0);
	check("  memory", *p, 0x5a5a5a5a);
	fflush(stdout);
}

/* One operation on p's line just written back and invalidated, with an
   ordinary load first when touch is set. */
static void evicted(const char *name, volatile uint32_t *p, int touch)
{
	uint32_t old;

	printf("%s at %08lx\n", name, (unsigned long)(uintptr_t)p);
	fflush(stdout);
	*p = 3;
	tv_dcache_wbinval();
	if (touch)
		(void)*p;
	old = amoswap_aq(p, 9);
	check("amoswap.w.aq old", old, 3);
	check("  memory", *p, 9);
	fflush(stdout);
}

static void evicted_lrsc(volatile uint32_t *p)
{
	uint32_t seen, rc;

	printf("DDR3 evicted, lr.w/sc.w at %08lx\n", (unsigned long)(uintptr_t)p);
	fflush(stdout);
	*p = 4;
	tv_dcache_wbinval();
	rc = lrsc(p, 0x11, &seen);
	check("lr.w value", seen, 4);
	check("sc.w result", rc, 0);
	check("  memory", *p, 0x11);
	fflush(stdout);
}

/* An LR/SC lock attempt that retries a failed SC, bounded at 1000 passes,
   with SDL's ordinary load of the lock word on each pass when touch is set.
   Returns the passes taken, 0 if the lock was found held, or 1000 if no SC
   succeeded. */
static uint32_t lrsc_lock(volatile uint32_t *p, int touch)
{
	uint32_t held, failed, passes = 0;

	do {
		passes++;
		if (touch)
			(void)*p;
		__asm__ volatile("lr.w.aq %0, (%2)\n\t"
		                 "bnez %0, 1f\n\t"
		                 "sc.w %1, %3, (%2)\n"
		                 "1:"
		                 : "=&r"(held), "=&r"(failed)
		                 : "r"(p), "r"(1) : "memory");
		if (held)
			return 0;
	} while (failed && passes < 1000);
	return passes;
}

/* touch 0: expected to fail every SC (AE350-011), which is counted as the
   expected result; touch 1: SDL's lock, expected to take one pass. */
static void evicted_lock(volatile uint32_t *p, int touch)
{
	uint32_t passes;

	printf("DDR3 evicted, LR/SC lock %s at %08lx\n",
	       touch ? "with load" : "bare", (unsigned long)(uintptr_t)p);
	fflush(stdout);
	*p = 0;
	tv_dcache_wbinval();
	passes = lrsc_lock(p, touch);
	if (touch) {
		check("passes to acquire", passes, 1);
		check("  memory", *p, 1);
		check("held lock refused", lrsc_lock(p, 1), 0);
	} else {
		check("passes, none succeed", passes, 1000);
		check("  memory", *p, 0);
	}
	fflush(stdout);
}

int main(void)
{
	volatile uint32_t bram_word = 0;   /* on the stack: the block RAM */
	uint32_t saved;

	printf("TinyVCMI AMO probe\n");
	run("DDR3 cached", &ddr3_word);
	run("block RAM", &bram_word);
	evicted("DDR3 evicted, loaded first", &ddr3_word, 1);
	evicted_lrsc(&ddr3_word);
	evicted_lock(&ddr3_word, 0);
	evicted_lock(&ddr3_word, 1);
#ifdef AMO_PROBE_HANG
	evicted("DDR3 evicted, bare AMO", &ddr3_word, 0);

	printf("DDR3 D-cache off\n");
	fflush(stdout);
	saved = tv_dcache_save_off();
	run("DDR3 uncached", &ddr3_word);
	tv_dcache_restore(saved);
#else
	(void)saved;
#endif

	printf("TinyVCMI AMO %s, %d wrong\n", fails ? "BAD" : "OK", fails);
	return fails ? 1 : 0;
}
