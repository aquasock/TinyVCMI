/* SPDX-License-Identifier: GPL-3.0-only
 *
 * The SD card through TinyTang's card file service (firmware/rt/card.c,
 * PROT-004), the way VCMI 1.7.5 will read the Heroes III data:
 *
 *   directories  opendir/readdir of the service's root and data/Data, with
 *                stat of every entry, against the sizes the card holds
 *   an archive   H3bitmap.lod's header and whole entry table through fopen,
 *                fseek and fread, and two of its entries
 *   throughput   the first MiB read twice, from the card and then from the
 *                read cache, with a CRC-32 of each for the host to check
 *   refusals     a missing file and a path naming a parent directory
 *
 * It prints CRC-32s the host checks against its own copy of the data; it
 * fails on any mismatch it can see itself.
 *
 * Run it with: tools/tang_ae350run.py build/firmware/apps/card_test/card_test.elf
 */
#include <dirent.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "tinyvcmi.h"
#include "tv_card.h"

#define LOD "/card/data/Data/H3bitmap.lod"

static int fails;

static void check(const char *what, int ok)
{
	if (!ok) {
		printf("  WRONG %s (errno %d)\n", what, errno);
		fails++;
	}
}

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

static uint32_t le32(const uint8_t *p)
{
	return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 |
	       (uint32_t)p[3] << 24;
}

static void list(const char *dir)
{
	DIR *d = opendir(dir);
	struct dirent *e;
	int n = 0;

	printf("%s:\n", dir);
	check("opendir", d != NULL);
	if (!d)
		return;
	while ((e = readdir(d)) != NULL) {
		char path[320];
		struct stat st;

		snprintf(path, sizeof path, "%s/%s", dir, e->d_name);
		int rc = stat(path, &st);
		check("stat of a listed entry", rc == 0);
		if (n < 12)
			printf("  %-14s %s %9ld\n", e->d_name,
			       S_ISDIR(st.st_mode) ? "dir " : "file", (long)st.st_size);
		n++;
	}
	closedir(d);
	printf("  %d entries\n", n);
}

/* Read a whole MiB with fread in 64 KiB pieces; its CRC and the time. */
static uint32_t read_mib(FILE *f, uint32_t *us)
{
	static uint8_t buf[64 * 1024];
	uint32_t crc = 0;
	uint64_t t0 = tv_cycles64();

	fseek(f, 0, SEEK_SET);
	for (int i = 0; i < 16; i++) {
		size_t got = fread(buf, 1, sizeof buf, f);
		crc = crc32(crc, buf, got);
		if (got != sizeof buf) {
			check("a full 64 KiB", 0);
			break;
		}
	}
	*us = (uint32_t)((tv_cycles64() - t0) / (TV_CORE_HZ / 1000000u));
	return crc;
}

int main(void)
{
	struct stat st;
	struct tv_card_stats s;
	uint8_t head[92];

	printf("TinyVCMI CARD test\n");
	fflush(stdout);

	list("/card");
	list("/card/data/Data");

	check("stat H3bitmap.lod", stat(LOD, &st) == 0);
	printf("H3bitmap.lod: %ld bytes\n", (long)st.st_size);
	check("H3bitmap.lod's size", st.st_size == 105724954);

	FILE *f = fopen(LOD, "rb");
	check("fopen", f != NULL);
	if (!f)
		goto done;
	check("header", fread(head, 1, sizeof head, f) == sizeof head);
	uint32_t count = le32(head + 8);
	printf("LOD magic %.3s, type %lu, %lu entries\n", head,
	       (unsigned long)le32(head + 4), (unsigned long)count);
	check("LOD magic", memcmp(head, "LOD", 4) == 0);
	check("entry count", count > 100 && count < 20000);

	uint8_t *table = malloc((size_t)count * 32u);
	check("table read",
	      table && fseek(f, 0x5c, SEEK_SET) == 0 &&
	      fread(table, 32, count, f) == count);
	uint32_t table_crc = crc32(0, table, (size_t)count * 32u);
	printf("table CRC %08lx\n", (unsigned long)table_crc);
	for (uint32_t i = 0; i < count && i < 3; i++)
		printf("  %-16.16s offset %8lu size %7lu csize %7lu\n", table + i * 32,
		       (unsigned long)le32(table + i * 32 + 16),
		       (unsigned long)le32(table + i * 32 + 20),
		       (unsigned long)le32(table + i * 32 + 28));
	/* Two entries: the first, and the last in the table. */
	for (int k = 0; k < 2; k++) {
		const uint8_t *e = table + (k ? count - 1 : 0) * 32;
		uint32_t off = le32(e + 16), size = le32(e + 20), csize = le32(e + 28);
		uint32_t n = csize ? csize : size;
		uint8_t *data = malloc(n);
		check("entry read", data && fseek(f, (long)off, SEEK_SET) == 0 &&
		                    fread(data, 1, n, f) == n);
		printf("entry %-16.16s %7lu bytes at %8lu, CRC %08lx\n", e,
		       (unsigned long)n, (unsigned long)off,
		       (unsigned long)crc32(0, data, n));
		free(data);
	}
	free(table);

	uint32_t us1, us2;
	uint32_t c1 = read_mib(f, &us1);
	uint32_t c2 = read_mib(f, &us2);
	printf("first MiB CRC %08lx: from the card %lu ms (%lu KB/s), cached %lu ms\n",
	       (unsigned long)c1, (unsigned long)(us1 / 1000),
	       (unsigned long)(1048576000u / (us1 ? us1 : 1)),
	       (unsigned long)(us2 / 1000));
	check("cached read is the same", c1 == c2);
	fclose(f);

	errno = 0;
	check("a missing file is ENOENT",
	      stat("/card/data/Data/NOSUCH.LOD", &st) != 0 && errno == ENOENT);
	errno = 0;
	check("a parent directory is refused",
	      stat("/card/../tinytang.ini", &st) != 0 && errno == EINVAL);

done:
	tv_card_get_stats(&s);
	printf("service: %lu requests, %lu bytes, %lu retries; cache %lu hits, "
	       "%lu misses; %lu ms waiting\n",
	       (unsigned long)s.requests, (unsigned long)s.bytes,
	       (unsigned long)s.retries, (unsigned long)s.cache_hits,
	       (unsigned long)s.cache_misses,
	       (unsigned long)(s.cycles / (TV_CORE_HZ / 1000u)));
	printf("TinyVCMI CARD %s, %d wrong\n", fails ? "BAD" : "OK", fails);
	return fails ? 1 : 0;
}
