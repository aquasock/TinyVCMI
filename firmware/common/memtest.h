/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Memory tests shared by the boot ROM and runtime programs. Each records the
 * number of mismatches and the first one in a struct tv_result. A cached test
 * writes back and invalidates the D-cache before reading back, so the data
 * crosses the bus as cache-line bursts.
 */
#ifndef TINYVCMI_MEMTEST_H
#define TINYVCMI_MEMTEST_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct tv_result {
	uint32_t failures;
	uint32_t addr;
	uint32_t expected;
	uint32_t got;
};

void tv_expect(struct tv_result *r, uintptr_t addr, uint32_t expected,
	       uint32_t got);

/* Distinct for every address under one seed, so aliasing shows. */
uint32_t tv_pattern(uint32_t addr, uint32_t seed);

/* Every word from start to end, with the pattern and then its inverse. */
void tv_test_words(struct tv_result *r, uint32_t seed, int cached,
		   volatile uint32_t *start, volatile uint32_t *end);

/* Byte and halfword stores to the 64 bytes at base change only their own
 * lanes, read back as bytes, halfwords and words. */
void tv_test_lanes(struct tv_result *r, uint32_t seed, int cached,
		   volatile uint32_t *base);

/* Each DDR3 address line from bit 2 up: the word at the base and at each
 * one-hot offset hold their own addresses, so a line that is stuck, swapped
 * or unconnected shows. */
void tv_test_address_lines(struct tv_result *r);

#ifdef __cplusplus
}
#endif

#endif
