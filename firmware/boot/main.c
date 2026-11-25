/* SPDX-License-Identifier: GPL-3.0-only
 *
 * TinyVCMI AE350 boot ROM program, from TinyNES f0f8501 firmware/boot/main.c
 * with the SDRAM's checks made the DDR3's. It checks the fabric registers in
 * the EXTS window and tests the block RAM and the DDR3 on the RAM port with
 * the A25 caches off and then on, leaves the caches on, and then waits for
 * a program on the UART (the load protocol in tinyvcmi.h), reporting once a
 * second until one starts to arrive:
 *
 *   TinyVCMI AE350 C OK UNC=<cycles> CAC=<cycles>
 *   TinyVCMI DDR3 OK 1024M-64K CAC=<cycles>
 *   TinyVCMI LOAD
 *
 * UNC and CAC are the core cycles (hex) each block RAM test took, and the
 * DDR3's CAC the cycles its two cached 64 KiB pattern tests took. The DDR3
 * check covers the byte lanes, cached and not, every address line, and
 * whole cache lines filled and written back at the bottom of the DDR3 and
 * just below the block RAM; the full-array test and the speed measurements
 * belong to a loaded program. A line starting with BAD reports the first
 * test that failed, or any trap, and the ROM then does not load programs.
 */
#include <stddef.h>
#include <stdint.h>

#include "load.h"
#include "memtest.h"
#include "tinyvcmi.h"
#include "uart.h"

extern uint32_t __ram_test_start[], __ram_test_end[];

void trap_report(uint32_t cause, uint32_t epc, uint32_t tval)
	__attribute__((noreturn));
int main(void);

#define DDR3 ((volatile uint32_t *)TV_DDR3_BASE)
#define DDR3_WORDS (TV_DDR3_BYTES / 4)
#define SPAN_WORDS (64u << 10 >> 2)	/* 64 KiB */

static void wait_cycles(uint32_t count)
{
	uint32_t start = tv_cycles();
	while (tv_cycles() - start < count)
		;
}

static void test_registers(struct tv_result *r)
{
	tv_expect(r, (uintptr_t)&TV_ID, TV_ID_VALUE, TV_ID);
	for (int bit = 0; bit < 32; bit++) {
		uint32_t value = 1u << bit;
		TV_SCRATCH = value;
		tv_expect(r, (uintptr_t)&TV_SCRATCH, value, TV_SCRATCH);
		TV_SCRATCH = ~value;
		tv_expect(r, (uintptr_t)&TV_SCRATCH, ~value, TV_SCRATCH);
	}
}

static void report_bad(const char *name, const struct tv_result *r)
{
	if (r->failures == 0)
		return;
	tv_put_str("BAD ");
	tv_put_str(name);
	tv_put_str(" N=");
	tv_put_hex(r->failures);
	tv_put_str(" A=");
	tv_put_hex(r->addr);
	tv_put_str(" E=");
	tv_put_hex(r->expected);
	tv_put_str(" G=");
	tv_put_hex(r->got);
	tv_put_str("\r\n");
}

int main(void)
{
	struct tv_result regs = {0}, uncached = {0}, cached = {0};
	struct tv_result sd_uncached = {0}, sd_cached = {0};
	uint32_t start, uncached_cycles, cached_cycles, ddr3_cycles;
	int bad;

	/* A program that left the UART in link mode restarts the ROM; its
	 * last text is sent before this write completes. */
	TV_UART_CTRL = 0;
	tv_put_str("\r\nTinyVCMI AE350 boot ROM\r\n");
	test_registers(&regs);

	start = tv_cycles();
	tv_test_lanes(&uncached, 0x5au, 0, __ram_test_start);
	tv_test_words(&uncached, 0x01234567u, 0, __ram_test_start,
		      __ram_test_end);
	uncached_cycles = tv_cycles() - start;

	tv_test_lanes(&sd_uncached, 0x3cu, 0, DDR3);
	tv_test_address_lines(&sd_uncached);

	CSR_SET(CSR_MCACHE_CTL, 3u);
	__asm__ volatile("fence.i" ::: "memory");
	start = tv_cycles();
	tv_test_lanes(&cached, 0xa5u, 1, __ram_test_start);
	tv_test_words(&cached, 0x89abcdefu, 1, __ram_test_start,
		      __ram_test_end);
	cached_cycles = tv_cycles() - start;

	tv_test_lanes(&sd_cached, 0xc3u, 1, DDR3 + 4096);
	start = tv_cycles();
	tv_test_words(&sd_cached, 0x5eedf00du, 1, DDR3 + (1u << 18),
		      DDR3 + (1u << 18) + SPAN_WORDS);
	tv_test_words(&sd_cached, 0x0badcafeu, 1, DDR3 + DDR3_WORDS - SPAN_WORDS,
		      DDR3 + DDR3_WORDS);
	ddr3_cycles = tv_cycles() - start;

	bad = regs.failures || uncached.failures || cached.failures ||
	      sd_uncached.failures || sd_cached.failures;
	tv_load_reset();
	for (;;) {
		uint32_t entry;

		report_bad("REG", &regs);
		report_bad("UNC", &uncached);
		report_bad("CAC", &cached);
		report_bad("DDU", &sd_uncached);
		report_bad("DDC", &sd_cached);
		if (bad) {
			wait_cycles(TV_CORE_HZ);
			continue;
		}
		tv_put_str("TinyVCMI AE350 C OK UNC=");
		tv_put_hex(uncached_cycles);
		tv_put_str(" CAC=");
		tv_put_hex(cached_cycles);
		tv_put_str("\r\nTinyVCMI DDR3 OK 1024M-64K CAC=");
		tv_put_hex(ddr3_cycles);
		tv_put_str("\r\nTinyVCMI LOAD\r\n");
		entry = tv_load_poll(TV_CORE_HZ);
		if (entry) {
			__asm__ volatile("fence.i" ::: "memory");
			((void (*)(void))(uintptr_t)entry)();
		}
	}
}

void trap_report(uint32_t cause, uint32_t epc, uint32_t tval)
{
	for (;;) {
		tv_put_str("BAD TRAP C=");
		tv_put_hex(cause);
		tv_put_str(" P=");
		tv_put_hex(epc);
		tv_put_str(" V=");
		tv_put_hex(tval);
		tv_put_str("\r\n");
		wait_cycles(TV_CORE_HZ);
	}
}
