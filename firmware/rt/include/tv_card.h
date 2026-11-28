/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Reading the SD card from a runtime program, through TinyTang's card file
 * service (ae350run in 2-wire mode, PROT-004): a request line on the UART,
 * the answer pushed back in the boot ROM's load protocol.  firmware/rt/card.c
 * implements it, and syscalls.c maps paths under /card/ onto it so that
 * open, read, lseek, stat and opendir work; this header is for programs that
 * want the service directly.
 *
 * Paths are relative to /root/media/vcmi on the card ("data/Data/H3bitmap.lod");
 * through the C library they are "/card/data/Data/H3bitmap.lod".  The card is
 * FAT, so names match without regard to case.  Nothing is ever written.
 */
#ifndef TV_CARD_H
#define TV_CARD_H

#include <stdint.h>

/* Status codes: 0, or a negative errno. */
#define TV_CARD_KIND_FILE 1
#define TV_CARD_KIND_DIR  2

/* The size and kind of a path; 0 or a negative errno. */
int tv_card_stat(const char *path, uint32_t *size, int *kind);

/* Up to length bytes of path from offset into buf; the bytes read (0 at the
 * end of the file) or a negative errno. One request reads at most
 * TV_CARD_READ_MAX bytes. */
#define TV_CARD_READ_MAX (64u * 1024u)
int tv_card_read(const char *path, uint32_t offset, void *buf, uint32_t length);

/* The directory's entries from index on, as packed records (a kind byte, the
 * size in 32 bits little-endian, a length byte and the name), at most room
 * bytes of them; the bytes written or a negative errno, and *total the
 * number of entries the directory holds. */
int tv_card_list(const char *path, uint32_t index, void *buf, uint32_t room,
		 uint32_t *total);

/* Requests sent and bytes received since the program started, and the read
 * cache's hits and misses, for measuring. */
struct tv_card_stats {
	uint32_t requests, bytes, retries;
	uint32_t cache_hits, cache_misses;
	uint64_t cycles;	/* spent waiting on the service */
};
void tv_card_get_stats(struct tv_card_stats *stats);

#endif
