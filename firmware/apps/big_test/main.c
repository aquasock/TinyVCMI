/* SPDX-License-Identifier: GPL-3.0-only
 *
 * A program whose image ends above 0x42000000, run by TinyTang's ae350run
 * (PROT-004): it checks that every word of its 34 MiB pad arrived, that its
 * image and the card service's reply buffer lie above the 32 MiB that
 * ae350run once allowed, and that a card read into that buffer is right --
 * H3bitmap.lod's entry table, CRC-32 11a88b4a (PROT-005).
 *
 * Run it with: tools/tang_ae350run.py build/firmware/apps/big_test/big_test.elf
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "tinyvcmi.h"

extern const uint32_t big_pad[], big_pad_end[];
extern char _end[];

static uint32_t crc32(uint32_t crc, const uint8_t *p, size_t n)
{
	crc = ~crc;
	while (n--) {
		crc ^= *p++;
		for (int k = 0; k < 8; k++)
			crc = (crc >> 1) ^ (0xedb88320u & -(crc & 1));
	}
	return ~crc;
}

int main(void)
{
	int fails = 0;
	size_t words = (size_t)(big_pad_end - big_pad), wrong = 0;

	printf("TinyVCMI BIG test: pad %lu bytes at 0x%08lx, image to 0x%08lx\n",
	       (unsigned long)(words * 4), (unsigned long)(uintptr_t)big_pad,
	       (unsigned long)(uintptr_t)_end);
	for (size_t i = 0; i < words; i++)
		wrong += big_pad[i] != 0x5aa5c33cu;
	printf("pad: %lu of %lu words wrong\n", (unsigned long)wrong,
	       (unsigned long)words);
	fails += wrong != 0;
	if ((uintptr_t)big_pad_end <= 0x42000000u) {
		printf("  WRONG the pad ends below 0x42000000\n");
		fails++;
	}

	/* The reply buffer is card.c's, in .bss after the pad; reading the
	 * table through it proves replies land above 32 MiB. */
	FILE *f = fopen("/card/data/Data/H3bitmap.lod", "rb");
	static uint8_t head[92];
	if (!f || fread(head, 1, sizeof head, f) != sizeof head) {
		printf("  WRONG H3bitmap.lod's header\n");
		fails++;
	} else {
		uint32_t count = (uint32_t)head[8] | (uint32_t)head[9] << 8 |
				 (uint32_t)head[10] << 16 | (uint32_t)head[11] << 24;
		uint8_t *table = malloc((size_t)count * 32u);
		size_t got = table ? fread(table, 32, count, f) : 0;
		uint32_t crc = got == count ? crc32(0, table, (size_t)count * 32u) : 0;
		printf("table: %lu entries, CRC %08lx\n", (unsigned long)count,
		       (unsigned long)crc);
		fails += crc != 0x11a88b4au;
		free(table);
	}
	if (f)
		fclose(f);
	printf("TinyVCMI BIG %s, %d wrong\n", fails ? "BAD" : "OK", fails);
	return fails ? 1 : 0;
}
