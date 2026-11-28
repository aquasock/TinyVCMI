/* SPDX-License-Identifier: GPL-3.0-only
 *
 * The SD card, read through TinyTang's card file service (PROT-004), and the
 * file and directory calls syscalls.c hands it for paths under /card/.
 *
 * A request is one line on the UART,
 *
 *   TinyVCMI FILE READ <address> <room> <offset> <length> <path>
 *   TinyVCMI FILE STAT <address> <room> <path>
 *   TinyVCMI FILE LIST <address> <room> <index> <path>
 *
 * and TinyTang, which runs the program with ae350run and owns the card,
 * answers by pushing a "TVF1" reply to <address> in the boot ROM's load
 * protocol (tinyvcmi.h, firmware/boot/load.c): a 24-byte header, 8 KiB
 * blocks each with its CRC-32, ACK or NAK for each, and a final ACK once the
 * whole image checks.  The receiver here is that protocol's, written again
 * for a running program: it takes the image into a buffer and returns
 * instead of jumping to it, and it checks the reply lands where it asked.
 * The reply: "TVF1", status, size, count, then count bytes (see TinyTang's
 * ports/bl616/tang_fpga_uart.c, ae350_file_service).
 *
 * Reads go through a cache of 64 KiB blocks in the DDR3, because a request
 * costs a round trip and the link moves about 187 KB/s at 2 Mbaud: VCMI
 * reads its archives' tables and then small entries, often from the same
 * blocks.  Nothing is written to the card; opening for writing fails with
 * EROFS.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "tinyvcmi.h"
#include "tv_card.h"
#include "uart.h"

#define TVF1         0x31465654u /* "TVF1" */
#define REPLY_HEADER 16u
#define BYTE_TIMEOUT (TV_CORE_HZ / 10)
#define REPLY_WAIT   ((uint64_t)TV_CORE_HZ * 4u) /* for the reply to start */
#define QUIET_CYCLES (TV_CORE_HZ / 100)
#define TRIES        3

/* ------------------------------------------------------------ the receiver */

static uint32_t crc32_byte(uint32_t crc, uint8_t byte)
{
	crc ^= byte;
	for (int k = 0; k < 8; k++)
		crc = (crc >> 1) ^ (0xedb88320u & -(crc & 1));
	return crc;
}

static int get_byte(uint32_t timeout)
{
	uint32_t start = tv_cycles();

	do {
		uint32_t value = TV_UART_RX;
		if (value & TV_UART_RX_VALID)
			return (int)(value & 0xff);
	} while (tv_cycles() - start < timeout);
	return -1;
}

static int get_bytes(uint8_t *dst, uint32_t count, uint32_t *crc)
{
	while (count--) {
		int byte = get_byte(BYTE_TIMEOUT);
		if (byte < 0)
			return -1;
		*dst++ = (uint8_t)byte;
		*crc = crc32_byte(*crc, (uint8_t)byte);
	}
	return 0;
}

static int get_word(uint32_t *word, uint32_t *crc)
{
	uint8_t b[4];

	if (get_bytes(b, 4, crc))
		return -1;
	*word = (uint32_t)b[0] | (uint32_t)b[1] << 8 | (uint32_t)b[2] << 16 |
		(uint32_t)b[3] << 24;
	return 0;
}

static void rx_clear(void)
{
	TV_UART_STATUS = TV_UART_RX_OVERRUN | TV_UART_RX_FRAME;
}

static void nak(char reason)
{
	uint32_t start = tv_cycles();

	while (tv_cycles() - start < QUIET_CYCLES)
		if (TV_UART_RX & TV_UART_RX_VALID)
			start = tv_cycles();
	rx_clear();
	tv_put_char((char)TV_LOAD_NAK);
	tv_put_char(reason);
}

/* Wait up to REPLY_WAIT for an image addressed to dst of at most room
 * bytes and receive it; its length, or -1.  The sender's text (TinyTang
 * echoes nothing, but a stray line is harmless) is skipped while hunting
 * for the magic. */
static int receive(uint8_t *dst, uint32_t room)
{
	uint64_t start = tv_cycles64();
	uint32_t window = 0;

	for (;;) {
		uint32_t value = TV_UART_RX;

		if (tv_cycles64() - start > REPLY_WAIT)
			return -1;
		if (!(value & TV_UART_RX_VALID))
			continue;
		window = window >> 8 | (value & 0xff) << 24;
		if (window == TV_LOAD_MAGIC)
			break;
	}
	rx_clear();

	uint32_t header[6], crc = ~0u, unused = 0;
	for (int i = 0; i < 4; i++)
		crc = crc32_byte(crc, (uint8_t)(TV_LOAD_MAGIC >> (8 * i)));
	for (int i = 1; i < 5; i++)
		if (get_word(&header[i], &crc)) {
			nak(TV_LOAD_TIMEOUT);
			return -1;
		}
	if (get_word(&header[5], &unused)) {
		nak(TV_LOAD_TIMEOUT);
		return -1;
	}
	if (~crc != header[5]) {
		nak(TV_LOAD_HEADER_CRC);
		return -1;
	}
	const uint32_t address = header[1], length = header[2];
	if (address != (uint32_t)(uintptr_t)dst || length == 0 || length > room) {
		nak(TV_LOAD_ADDRESS);
		return -1;
	}
	tv_put_char((char)TV_LOAD_ACK);

	for (uint32_t done = 0; done < length;) {
		uint32_t count = length - done, block_crc;
		uint8_t *p = dst + done;
		int first;

		if (count > TV_LOAD_BLOCK_BYTES)
			count = TV_LOAD_BLOCK_BYTES;
		first = get_byte(2u * TV_CORE_HZ);
		if (first < 0)
			return -1;
		*p = (uint8_t)first;
		crc = crc32_byte(~0u, (uint8_t)first);
		if (get_bytes(p + 1, count - 1, &crc) ||
		    get_word(&block_crc, &unused)) {
			nak(TV_LOAD_TIMEOUT);
			continue;
		}
		if (TV_UART_STATUS & TV_UART_RX_OVERRUN) {
			nak(TV_LOAD_OVERRUN);
			continue;
		}
		if (~crc != block_crc) {
			nak(TV_LOAD_BLOCK_CRC);
			continue;
		}
		tv_put_char((char)TV_LOAD_ACK);
		done += count;
	}

	/* The CPU wrote every byte itself, so the cache holds them. */
	crc = ~0u;
	for (uint32_t i = 0; i < length; i++)
		crc = crc32_byte(crc, dst[i]);
	if (~crc != header[4]) {
		nak(TV_LOAD_IMAGE_CRC);
		return -1;
	}
	tv_put_char((char)TV_LOAD_ACK);
	return (int)length;
}

/* ------------------------------------------------------------ the requests */

static uint8_t reply_buf[REPLY_HEADER + TV_CARD_READ_MAX] __attribute__((aligned(64)));
static struct tv_card_stats stats;

static uint32_t le32(const uint8_t *p)
{
	return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 |
	       (uint32_t)p[3] << 24;
}

/* Send "TinyVCMI FILE <op> <address> <room> <nums...> <path>" and take the
 * reply into reply_buf; the reply's status, or -EIO if none came.  READ and
 * LIST replies carry count bytes after the header; a STAT reply is the
 * header alone, its count the entry's kind. */
static int request(const char *op, const uint32_t *nums, int n,
		   const char *path, uint32_t room, uint32_t *size,
		   uint32_t *count)
{
	const int has_body = strcmp(op, "STAT") != 0;

	uint64_t t0 = tv_cycles64();

	fflush(stdout);
	fflush(stderr);
	tv_wait_tx_idle();
	for (int attempt = 0; attempt < TRIES; attempt++) {
		rx_clear();
		/* A retry ends whatever part of the last request arrived, so
		 * that TinyTang reads this one as a line of its own. */
		if (attempt) {
			stats.retries++;
			tv_put_str("\r\n");
		}
		tv_put_str("TinyVCMI FILE ");
		tv_put_str(op);
		tv_put_char(' ');
		tv_put_hex((uint32_t)(uintptr_t)reply_buf);
		tv_put_char(' ');
		tv_put_hex(room);
		for (int i = 0; i < n; i++) {
			tv_put_char(' ');
			tv_put_hex(nums[i]);
		}
		tv_put_char(' ');
		tv_put_str(path);
		tv_put_str("\r\n");
		stats.requests++;
		int got = receive(reply_buf, room);
		if (got < (int)REPLY_HEADER || le32(reply_buf) != TVF1)
			continue;
		int status = (int)le32(reply_buf + 4);
		*size = le32(reply_buf + 8);
		*count = le32(reply_buf + 12);
		if (status == 0 &&
		    (uint32_t)got != REPLY_HEADER + (has_body ? *count : 0u))
			continue;
		stats.bytes += (uint32_t)got;
		stats.cycles += tv_cycles64() - t0;
		return status;
	}
	stats.cycles += tv_cycles64() - t0;
	return -EIO;
}

int tv_card_stat(const char *path, uint32_t *size, int *kind)
{
	uint32_t s = 0, c = 0;
	int rc = request("STAT", NULL, 0, path, REPLY_HEADER, &s, &c);

	if (rc == 0) {
		*size = s;
		*kind = (int)c;
	}
	return rc;
}

int tv_card_read(const char *path, uint32_t offset, void *buf, uint32_t length)
{
	uint32_t size = 0, count = 0, nums[2];
	int rc;

	if (length > TV_CARD_READ_MAX)
		length = TV_CARD_READ_MAX;
	nums[0] = offset;
	nums[1] = length;
	rc = request("READ", nums, 2, path, REPLY_HEADER + length, &size, &count);
	if (rc != 0)
		return rc;
	memcpy(buf, reply_buf + REPLY_HEADER, count);
	return (int)count;
}

int tv_card_list(const char *path, uint32_t index, void *buf, uint32_t room,
		 uint32_t *total)
{
	uint32_t size = 0, count = 0;
	int rc;

	if (room > TV_CARD_READ_MAX)
		room = TV_CARD_READ_MAX;
	rc = request("LIST", &index, 1, path, REPLY_HEADER + room, &size, &count);
	if (rc != 0)
		return rc;
	memcpy(buf, reply_buf + REPLY_HEADER, count);
	*total = size;
	return (int)count;
}

/* ------------------------------------------------------------- the cache */

#define BLOCK      TV_CARD_READ_MAX
#define SLOTS      64u		/* 4 MiB of the DDR3 */
#define PATH_MAX_  192

struct file {
	char path[PATH_MAX_];
	uint32_t size, pos, id;
	int used;
};

struct slot {
	uint32_t id, block, length, age;
	uint8_t *data;
};

static struct file files[32];
static struct slot slots[SLOTS];
static uint32_t next_id = 1, clock_;

/* The cached block of a file, read from the card on a miss; NULL on error. */
static struct slot *block_of(const struct file *f, uint32_t block)
{
	struct slot *victim = &slots[0];

	for (uint32_t i = 0; i < SLOTS; i++) {
		struct slot *s = &slots[i];
		if (s->data && s->id == f->id && s->block == block) {
			s->age = ++clock_;
			stats.cache_hits++;
			return s;
		}
		if (!s->data || s->age < victim->age)
			victim = s;
	}
	stats.cache_misses++;
	if (!victim->data) {
		victim->data = malloc(BLOCK);
		if (!victim->data)
			return NULL;
	}
	int got = tv_card_read(f->path, block * BLOCK, victim->data, BLOCK);
	if (got < 0) {
		victim->id = 0;
		return NULL;
	}
	victim->id = f->id;
	victim->block = block;
	victim->length = (uint32_t)got;
	victim->age = ++clock_;
	return victim;
}

/* The service's path for a name under /card, "/card" itself being its root
 * (the empty path); NULL for any other name. */
static const char *card_path(const char *name)
{
	if (strcmp(name, "/card") == 0)
		return "";
	return strncmp(name, "/card/", 6) == 0 ? name + 6 : NULL;
}

/* fds 3 and up are files on the card, files[fd - 3]. */
static struct file *file_of(int fd)
{
	if (fd < 3 || fd >= 3 + (int)(sizeof files / sizeof files[0]) ||
	    !files[fd - 3].used) {
		errno = EBADF;
		return NULL;
	}
	return &files[fd - 3];
}

static int fail(int rc)
{
	errno = rc < 0 ? -rc : EIO;
	return -1;
}

int tv_rt_file_open(const char *name, int flags)
{
	const char *path = card_path(name);
	uint32_t size;
	int kind, rc;

	if (!path) {
		errno = ENOENT;
		return -1;
	}
	if ((flags & O_ACCMODE) != O_RDONLY || (flags & (O_CREAT | O_TRUNC))) {
		errno = EROFS;
		return -1;
	}
	if (strlen(path) >= PATH_MAX_) {
		errno = ENAMETOOLONG;
		return -1;
	}
	rc = tv_card_stat(path, &size, &kind);
	if (rc)
		return fail(rc);
	if (kind != TV_CARD_KIND_FILE) {
		errno = EISDIR;
		return -1;
	}
	for (int i = 0; i < (int)(sizeof files / sizeof files[0]); i++)
		if (!files[i].used) {
			struct file *f = &files[i];
			strcpy(f->path, path);
			f->size = size;
			f->pos = 0;
			f->id = next_id++;
			f->used = 1;
			return 3 + i;
		}
	errno = EMFILE;
	return -1;
}

int tv_rt_file_read(int fd, char *buf, int len)
{
	struct file *f = file_of(fd);
	int done = 0;

	if (!f)
		return -1;
	while (len > 0 && f->pos < f->size) {
		uint32_t block = f->pos / BLOCK, at = f->pos % BLOCK;
		struct slot *s = block_of(f, block);
		if (!s)
			return done ? done : fail(-EIO);
		if (at >= s->length)
			break;
		uint32_t n = s->length - at;
		if (n > (uint32_t)len)
			n = (uint32_t)len;
		memcpy(buf + done, s->data + at, n);
		done += (int)n;
		len -= (int)n;
		f->pos += n;
	}
	return done;
}

int tv_rt_file_lseek(int fd, int offset, int whence)
{
	struct file *f = file_of(fd);
	int64_t at;

	if (!f)
		return -1;
	at = whence == SEEK_SET ? offset :
	     whence == SEEK_CUR ? (int64_t)f->pos + offset :
	     whence == SEEK_END ? (int64_t)f->size + offset : -1;
	if (at < 0 || at > 0x7fffffff) {
		errno = EINVAL;
		return -1;
	}
	f->pos = (uint32_t)at;
	return (int)at;
}

int tv_rt_file_close(int fd)
{
	struct file *f = file_of(fd);

	if (!f)
		return -1;
	/* Its blocks stay cached under an id no file will take again. */
	f->used = 0;
	return 0;
}

static void fill_stat(struct stat *st, uint32_t size, int kind)
{
	memset(st, 0, sizeof *st);
	st->st_mode = kind == TV_CARD_KIND_DIR ? (S_IFDIR | 0555) : (S_IFREG | 0444);
	st->st_size = (off_t)size;
	st->st_nlink = 1;
	st->st_blksize = (blksize_t)BLOCK;
}

int tv_rt_file_fstat(int fd, struct stat *st)
{
	struct file *f = file_of(fd);

	if (!f)
		return -1;
	fill_stat(st, f->size, TV_CARD_KIND_FILE);
	return 0;
}

int tv_rt_file_stat(const char *name, struct stat *st)
{
	const char *path = card_path(name);
	uint32_t size;
	int kind, rc;

	if (!path) {
		errno = ENOENT;
		return -1;
	}
	if (!*path) {
		fill_stat(st, 0, TV_CARD_KIND_DIR);
		return 0;
	}
	rc = tv_card_stat(path, &size, &kind);
	if (rc)
		return fail(rc);
	fill_stat(st, size, kind);
	return 0;
}

/* ----------------------------------------------------------- directories */

#include <dirent.h>

struct tv_dir {
	char path[PATH_MAX_];
	uint32_t index, total, at, length;
	uint8_t page[4096];
	struct dirent entry;
};

DIR *tv_rt_opendir(const char *name)
{
	const char *path = card_path(name);
	struct tv_dir *d;
	uint32_t size;
	int kind, rc;

	if (!path) {
		errno = ENOENT;
		return NULL;
	}
	/* "/card/x/" and "/card/x" are the same directory. */
	char clean[PATH_MAX_];
	size_t n = strlen(path);
	if (n >= sizeof clean) {
		errno = ENAMETOOLONG;
		return NULL;
	}
	memcpy(clean, path, n + 1);
	while (n > 0 && clean[n - 1] == '/')
		clean[--n] = '\0';
	if (n > 0) {
		rc = tv_card_stat(clean, &size, &kind);
		if (rc) {
			fail(rc);
			return NULL;
		}
		if (kind != TV_CARD_KIND_DIR) {
			errno = ENOTDIR;
			return NULL;
		}
	}
	d = calloc(1, sizeof *d);
	if (!d) {
		errno = ENOMEM;
		return NULL;
	}
	/* The empty path is the service's root, /root/media/vcmi. */
	strcpy(d->path, clean);
	return d;
}

struct dirent *tv_rt_readdir(DIR *dir)
{
	struct tv_dir *d = dir;

	if (d->at >= d->length) {
		if (d->length && d->index >= d->total)
			return NULL;
		int got = tv_card_list(d->path, d->index, d->page,
				       sizeof d->page, &d->total);
		if (got <= 0)
			return NULL;
		d->length = (uint32_t)got;
		d->at = 0;
	}
	const uint8_t *r = d->page + d->at;
	uint32_t n = r[5];
	memcpy(d->entry.d_name, r + 6, n);
	d->entry.d_name[n] = '\0';
	d->at += 6 + n;
	d->index++;
	return &d->entry;
}

int tv_rt_closedir(DIR *dir)
{
	free(dir);
	return 0;
}

void tv_card_get_stats(struct tv_card_stats *out)
{
	*out = stats;
}
