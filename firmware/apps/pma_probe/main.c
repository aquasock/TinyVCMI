/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Read-only probe of the A25's machine-custom CSRs and of how the core
 * currently treats the frame buffer's address range, to answer one question
 * before any code depends on it: can firmware make a 16 MiB window of the
 * DDR3 non-cacheable, so that a write-only pass stops paying the 501.7-cycle
 * read-allocate fill that AE350-009 measured?
 *
 * Nothing here writes a cache or memory-attribute register and no memory is
 * stored to except by the two timed loops, which store to windows this project
 * already owns. mtvec is repointed so an unimplemented CSR read does not take
 * the core down; see probe.S.
 *
 * Two outputs:
 *
 *   the CSR dump   which machine-custom CSRs this A25 implements and what
 *                  they read at reset, over the windows Andes documents for
 *                  cache control (0x7c0), misc control (0x7d0) and cache
 *                  geometry (0xfc0). This project's reference library has no
 *                  record of the A25's memory attributes, so the dump is the
 *                  evidence that has to come first.
 *   the range test the per-line store and read cost of the frame buffer
 *                  window against ordinary DDR3, using AE350-009's method, so
 *                  it is visible whether the core's attributes are uniform
 *                  across the 1 GiB or already differ somewhere.
 *
 * Run it with: tools/load_ae350.py build/firmware/apps/pma_probe/pma_probe.elf
 */
#include <stdint.h>
#include <stdio.h>

#include "tinyvcmi.h"

/* probe.S sets this to 1 when a CSR read trapped. */
volatile uint32_t probe_fault;

void probe_handler_install(void);

/* CSR numbers this project already knows: TinyNES's DEV-014 and DEV-013. */
#define CSR_MCACHE_CTL   0x7ca
#define CSR_MCCTLCOMMAND 0x7cc
#define CSR_MICM_CFG     0xfc0
#define CSR_MDCM_CFG     0xfc1

#define LINES  8192u
#define SPAN   ((uintptr_t)LINES * 32u)

static uint32_t csr_read(uint32_t csr, int *present)
{
	uint32_t v = 0;

	probe_fault = 0;
	switch (csr) {
	case 0x7c0: __asm__ volatile("csrr %0, 0x7c0" : "=r"(v)); break;
	case 0x7c1: __asm__ volatile("csrr %0, 0x7c1" : "=r"(v)); break;
	case 0x7c2: __asm__ volatile("csrr %0, 0x7c2" : "=r"(v)); break;
	case 0x7c3: __asm__ volatile("csrr %0, 0x7c3" : "=r"(v)); break;
	case 0x7c4: __asm__ volatile("csrr %0, 0x7c4" : "=r"(v)); break;
	case 0x7c5: __asm__ volatile("csrr %0, 0x7c5" : "=r"(v)); break;
	case 0x7c6: __asm__ volatile("csrr %0, 0x7c6" : "=r"(v)); break;
	case 0x7c7: __asm__ volatile("csrr %0, 0x7c7" : "=r"(v)); break;
	case 0x7c8: __asm__ volatile("csrr %0, 0x7c8" : "=r"(v)); break;
	case 0x7c9: __asm__ volatile("csrr %0, 0x7c9" : "=r"(v)); break;
	case 0x7ca: __asm__ volatile("csrr %0, 0x7ca" : "=r"(v)); break;
	case 0x7cb: __asm__ volatile("csrr %0, 0x7cb" : "=r"(v)); break;
	case 0x7cc: __asm__ volatile("csrr %0, 0x7cc" : "=r"(v)); break;
	case 0x7cd: __asm__ volatile("csrr %0, 0x7cd" : "=r"(v)); break;
	case 0x7ce: __asm__ volatile("csrr %0, 0x7ce" : "=r"(v)); break;
	case 0x7cf: __asm__ volatile("csrr %0, 0x7cf" : "=r"(v)); break;
	case 0x7d0: __asm__ volatile("csrr %0, 0x7d0" : "=r"(v)); break;
	case 0x7d1: __asm__ volatile("csrr %0, 0x7d1" : "=r"(v)); break;
	case 0x7d2: __asm__ volatile("csrr %0, 0x7d2" : "=r"(v)); break;
	case 0x7d3: __asm__ volatile("csrr %0, 0x7d3" : "=r"(v)); break;
	case 0xfc0: __asm__ volatile("csrr %0, 0xfc0" : "=r"(v)); break;
	case 0xfc1: __asm__ volatile("csrr %0, 0xfc1" : "=r"(v)); break;
	case 0xfc2: __asm__ volatile("csrr %0, 0xfc2" : "=r"(v)); break;
	case 0xfc3: __asm__ volatile("csrr %0, 0xfc3" : "=r"(v)); break;
	case 0xfc4: __asm__ volatile("csrr %0, 0xfc4" : "=r"(v)); break;
	case 0xfc5: __asm__ volatile("csrr %0, 0xfc5" : "=r"(v)); break;
	case 0xf11: __asm__ volatile("csrr %0, mvendorid" : "=r"(v)); break;
	case 0xf12: __asm__ volatile("csrr %0, marchid" : "=r"(v)); break;
	case 0xf13: __asm__ volatile("csrr %0, mimpid" : "=r"(v)); break;
	case 0xf14: __asm__ volatile("csrr %0, mhartid" : "=r"(v)); break;
	case 0x300: __asm__ volatile("csrr %0, mstatus" : "=r"(v)); break;
	case 0x301: __asm__ volatile("csrr %0, misa" : "=r"(v)); break;
	case 0x305: __asm__ volatile("csrr %0, mtvec" : "=r"(v)); break;
	default:
		*present = -1;
		return 0;
	}
	*present = !probe_fault;
	return v;
}

/* Candidate names, from U-Boot's Andes CSR header as TinyNES cited it in its
 * DEV-014. A name here does not mean the register is implemented: the dump
 * decides that. */
static const char *csr_name(uint32_t csr)
{
	switch (csr) {
	case 0x7c0: return "mxstatus";
	case 0x7c1: return "mhcr";
	case 0x7c5: return "mhint";
	case 0x7ca: return "mcache_ctl";
	case 0x7cb: return "mcctlbgnaddr";
	case 0x7cc: return "mcctlcommand";
	case 0x7cd: return "mcctldata";
	case 0x7d0: return "mmisc_ctl";
	case 0xfc0: return "micm_cfg";
	case 0xfc1: return "mdcm_cfg";
	case 0xfc2: return "mmsc_cfg";
	case 0xfc3: return "mmsc_cfg2";
	case 0xf11: return "mvendorid";
	case 0xf12: return "marchid";
	case 0xf13: return "mimpid";
	case 0xf14: return "mhartid";
	case 0x300: return "mstatus";
	case 0x301: return "misa";
	case 0x305: return "mtvec";
	default:     return "";
	}
}

/* AE350-009's method: store all eight words of each line, one line at a time. */
static uint64_t store_lines(uintptr_t base)
{
	uint64_t t0 = tv_cycles64();

	for (uintptr_t off = 0; off < SPAN; off += 32) {
		volatile uint32_t *p = (volatile uint32_t *)(base + off);

		for (unsigned w = 0; w < 8; w++)
			p[w] = 0xc0de0000u + w;
	}
	return tv_cycles64() - t0;
}

/* And read them back, which pays a fill if the range is cached. */
static uint64_t read_lines(uintptr_t base)
{
	uint64_t t0 = tv_cycles64();
	uint32_t sum = 0;

	for (uintptr_t off = 0; off < SPAN; off += 32) {
		const volatile uint32_t *p =
			(const volatile uint32_t *)(base + off);

		for (unsigned w = 0; w < 8; w++)
			sum ^= p[w];
	}
	if (sum == 0xdeadbeefu)
		printf(" ");        /* keep sum live without a store we would time */
	return tv_cycles64() - t0;
}

static void report_range(const char *name, uintptr_t base)
{
	uint64_t s = store_lines(base);
	uint64_t r = read_lines(base);

	printf("  %-10s store %6lu.%lu  read %6lu.%lu cycles/line\r\n", name,
	       (unsigned long)(s * 10u / LINES / 10), (unsigned long)(s * 10u / LINES % 10),
	       (unsigned long)(r * 10u / LINES / 10), (unsigned long)(r * 10u / LINES % 10));
}

/* Zicboz: if cbo.zero exists, a line can be cleared without the read-allocate
 * fill that AE350-009 measured, which is the whole win the write-around path
 * was after. Zicbom's cbo.clean/flush/inval are probed beside it because a core
 * that has one often has the other. Each is attempted under the probe handler,
 * so an illegal instruction is caught and reported rather than fatal. */
static int try_cbo_zero(uintptr_t addr)
{
	probe_fault = 0;
	/* Encoded by hand: the toolchain's -march has no Zicboz, but the core
	 * is being asked whether it implements it. */
	__asm__ volatile(".insn i 0x0f, 4, x0, %0, 0x20" :: "r"(addr) : "memory");
	if (probe_fault)
		return 0;
	__asm__ volatile("fence" ::: "memory");
	return 1;
}

static int try_cbo_clean(uintptr_t addr)
{
	probe_fault = 0;
	__asm__ volatile(".insn i 0x0f, 4, x0, %0, 0x01" :: "r"(addr) : "memory");
	return !probe_fault;
}

static int try_cbo_flush(uintptr_t addr)
{
	probe_fault = 0;
	__asm__ volatile(".insn i 0x0f, 4, x0, %0, 0x02" :: "r"(addr) : "memory");
	return !probe_fault;
}

static int try_cbo_inval(uintptr_t addr)
{
	probe_fault = 0;
	__asm__ volatile(".insn i 0x0f, 4, x0, %0, 0x00" :: "r"(addr) : "memory");
	return !probe_fault;
}

/* Time a whole-screen clear done with cbo.zero, if it exists, against the
 * store loop AE350-009 measured. Both clear the same lines. */
static uint64_t clear_with_cbo(uintptr_t base)
{
	uint64_t t0 = tv_cycles64();

	for (uintptr_t off = 0; off < SPAN; off += 32)
		if (!try_cbo_zero(base + off))
			break;
	return tv_cycles64() - t0;
}

/* The one firmware-only way left to skip the read-allocate fill: clean and
 * invalidate the D-cache, disable it, do the write-only pass with every store
 * going straight to the DDR3, then re-enable. The clean before the disable is
 * what makes it safe -- a dirty framebuffer line left in the cache would
 * otherwise be written back over the new data by the next write-back.
 *
 * The loop is leaf and keeps all its state in registers, because with the
 * cache off every spill to the stack is a 60-cycle transfer too. */
static uint64_t fill_cached(uintptr_t base, uint32_t lines)
{
	uint64_t t0 = tv_cycles64();

	for (uint32_t i = 0; i < lines; i++) {
		volatile uint32_t *p = (volatile uint32_t *)(base + i * 32u);

		for (unsigned w = 0; w < 8; w++)
			p[w] = 0x5eed0000u + w;
	}
	return tv_cycles64() - t0;
}

static uint64_t fill_waround(uintptr_t base, uint32_t lines)
{
	uint32_t saved = tv_dcache_save_off();
	uint64_t t0;

	t0 = tv_cycles64();
	for (uint32_t i = 0; i < lines; i++) {
		volatile uint32_t *p = (volatile uint32_t *)(base + i * 32u);

		for (unsigned w = 0; w < 8; w++)
			p[w] = 0x5eed0000u + w;
	}
	{
		uint64_t t1 = tv_cycles64();

		tv_dcache_restore(saved);
		return t1 - t0;
	}
}

/* Read a filled span back with the cache on, to prove the uncached pass landed
 * what the cached one did. */
static uint32_t fill_check(uintptr_t base, uint32_t lines)
{
	uint32_t bad = 0;

	tv_dcache_wbinval();
	for (uint32_t i = 0; i < lines; i++) {
		const volatile uint32_t *p =
			(const volatile uint32_t *)(base + i * 32u);

		for (unsigned w = 0; w < 8; w++)
			if (p[w] != 0x5eed0000u + w)
				bad++;
	}
	return bad;
}

/* A read-modify-write pass, to find the boundary of the trick: this one has to
 * read, so switching the cache off should hurt it. Same shape as G0's copy32. */
static uint64_t copy_pass(uintptr_t dst, uintptr_t src, uint32_t lines, int waround)
{
	uint32_t saved = 0;
	uint64_t t0;

	if (waround)
		saved = tv_dcache_save_off();
	t0 = tv_cycles64();
	for (uint32_t i = 0; i < lines; i++) {
		volatile uint32_t *d = (volatile uint32_t *)(dst + i * 32u);
		const volatile uint32_t *s =
			(const volatile uint32_t *)(src + i * 32u);

		for (unsigned w = 0; w < 8; w++)
			d[w] = s[w] ^ 0x1u;
	}
	{
		uint64_t t1 = tv_cycles64();

		if (waround)
			tv_dcache_restore(saved);
		return t1 - t0;
	}
}

int main(void)
{
	static const uint32_t csrs[] = {
		0x7c0, 0x7c1, 0x7c2, 0x7c3, 0x7c4, 0x7c5, 0x7c6, 0x7c7,
		0x7c8, 0x7c9, 0x7ca, 0x7cb, 0x7cc, 0x7cd, 0x7ce, 0x7cf,
		0x7d0, 0x7d1, 0x7d2, 0x7d3,
		0xfc0, 0xfc1, 0xfc2, 0xfc3, 0xfc4, 0xfc5,
		0xf11, 0xf12, 0xf13, 0xf14,
		0x300, 0x301, 0x305,
	};
	uint32_t mtvec_before;
	int present;

	setvbuf(stdout, NULL, _IONBF, 0);

	/* mtvec first, so every read below can trap and be skipped. */
	__asm__ volatile("csrr %0, mtvec" : "=r"(mtvec_before));
	probe_handler_install();

	printf("\r\nTinyVCMI A25 attribute probe, read-only\r\n");
	printf("mtvec was %08lx, now the probe handler\r\n",
	       (unsigned long)mtvec_before);

	printf("\nmachine-custom CSRs (candidate names from U-Boot's Andes header):\r\n");
	for (unsigned i = 0; i < sizeof csrs / sizeof csrs[0]; i++) {
		uint32_t v = csr_read(csrs[i], &present);

		if (present == 1)
			printf("  %03lx %-12s %08lx\r\n", (unsigned long)csrs[i],
			       csr_name(csrs[i]), (unsigned long)v);
		else
			printf("  %03lx %-12s absent\r\n", (unsigned long)csrs[i],
			       csr_name(csrs[i]));
	}

	/* A CSR that certainly is not there, to prove the reader can tell. */
	present = 0;
	csr_read(0x555, &present);
	printf("  control: CSR 0x555 reads %s\r\n",
	       present == 0 ? "present or untrapped" : "absent, so the trap path works");

	printf("\nrange test, %lu lines of 32 bytes, AE350-009's method:\r\n",
	       (unsigned long)LINES);
	report_range("frame buf", TV_VIDEO_BASE);
	report_range("plain RAM", TV_DDR3_BASE + (4u << 20));
	report_range("frame buf", TV_VIDEO_BASE);

	printf("\ncache geometry this core reports: micm %08lx mdcm %08lx,"
	       " mcache_ctl %08lx\r\n",
	       (unsigned long)csr_read(CSR_MICM_CFG, &present),
	       (unsigned long)csr_read(CSR_MDCM_CFG, &present),
	       (unsigned long)csr_read(CSR_MCACHE_CTL, &present));

	printf("\nZicboz and Zicbom, attempted under the probe handler:\r\n");
	{
		/* A line this project owns, aligned to a cache block. */
		uintptr_t probe_addr = TV_VIDEO_BASE + (8u << 20);
		int z = try_cbo_zero(probe_addr);

		printf("  cbo.zero   %s\r\n", z ? "accepted" : "illegal instruction");
		printf("  cbo.clean  %s\r\n",
		       try_cbo_clean(probe_addr) ? "accepted" : "illegal instruction");
		printf("  cbo.flush  %s\r\n",
		       try_cbo_flush(probe_addr) ? "accepted" : "illegal instruction");
		printf("  cbo.inval  %s\r\n",
		       try_cbo_inval(probe_addr) ? "accepted" : "illegal instruction");

		if (z) {
			uint64_t c = clear_with_cbo(TV_VIDEO_BASE);
			uint64_t s = store_lines(TV_VIDEO_BASE + SPAN);

			printf("  clear a line: cbo.zero %6lu.%lu, stores %6lu.%lu"
			       " cycles/line\r\n",
			       (unsigned long)(c * 10u / LINES / 10),
			       (unsigned long)(c * 10u / LINES % 10),
			       (unsigned long)(s * 10u / LINES / 10),
			       (unsigned long)(s * 10u / LINES % 10));
		}
	}

	printf("\nwrite-only pass, cached against the D-cache switched off around it\r\n");
	{
		uint32_t lines = 115200u;   /* one 1280x720 screen */
		uintptr_t a = TV_VIDEO_BASE;
		uintptr_t b = TV_VIDEO_BASE + (4u << 20);
		uint64_t c1, c2, w1, w2;
		uint32_t bad;

		c1 = fill_cached(a, lines);
		bad = fill_check(a, lines);
		printf("  cached     %6lu.%lu cycles/line, %lu bad\r\n",
		       (unsigned long)(c1 * 10u / lines / 10),
		       (unsigned long)(c1 * 10u / lines % 10), (unsigned long)bad);

		w1 = fill_waround(b, lines);
		bad = fill_check(b, lines);
		printf("  write-arnd %6lu.%lu cycles/line, %lu bad\r\n",
		       (unsigned long)(w1 * 10u / lines / 10),
		       (unsigned long)(w1 * 10u / lines % 10), (unsigned long)bad);

		/* Second time each, so a first-touch effect cannot explain it. */
		c2 = fill_cached(a, lines);
		w2 = fill_waround(b, lines);
		printf("  again      cached %6lu.%lu, write-around %6lu.%lu"
		       " cycles/line\r\n",
		       (unsigned long)(c2 * 10u / lines / 10),
		       (unsigned long)(c2 * 10u / lines % 10),
		       (unsigned long)(w2 * 10u / lines / 10),
		       (unsigned long)(w2 * 10u / lines % 10));
		printf("  ratio %.2f, and a whole screen %lu ms against %lu ms\r\n",
		       (double)w2 / (double)c2,
		       (unsigned long)(w2 / 750000u), (unsigned long)(c2 / 750000u));

		/* The boundary: a pass that must read is expected to get worse. */
		{
			uint64_t k1 = copy_pass(a, b, lines, 0);
			uint64_t k2 = copy_pass(a, b, lines, 1);

			printf("  copy       cached %6lu.%lu, write-around %6lu.%lu"
			       " cycles/line\r\n",
			       (unsigned long)(k1 * 10u / lines / 10),
			       (unsigned long)(k1 * 10u / lines % 10),
			       (unsigned long)(k2 * 10u / lines / 10),
			       (unsigned long)(k2 * 10u / lines % 10));
		}

		/* And with the video scanning out of the buffer being filled, which is
		 * the case the driver will actually be in. */
		{
			uint32_t late0, late1;
			uint64_t w3;

			TV_VID_BASE = b;
			TV_VID_CTRL = 1;
			late0 = TV_VID_LATE;
			w3 = fill_waround(b, lines);
			late1 = TV_VID_LATE;
			bad = fill_check(b, lines);
			TV_VID_CTRL = 0;
			printf("  scanning   %6lu.%lu cycles/line, %lu bad, LATE %lu -> %lu\r\n",
			       (unsigned long)(w3 * 10u / lines / 10),
			       (unsigned long)(w3 * 10u / lines % 10), (unsigned long)bad,
			       (unsigned long)late0, (unsigned long)late1);
		}
	}

	printf("TinyVCMI ATTR PROBE DONE\r\n");
	return 0;
}
