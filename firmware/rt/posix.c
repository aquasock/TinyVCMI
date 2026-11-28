/* SPDX-License-Identifier: GPL-3.0-only
 *
 * POSIX calls newlib leaves out on riscv, for the libraries VCMI links
 * (minizip-ng, Boost.Filesystem), declared by the headers in
 * firmware/rt/include that wrap newlib's.  The only files are the SD card's,
 * read-only, through card.c: nothing on it is a link, and nothing on it can
 * be changed.
 */
#include <errno.h>
#include <sys/stat.h>
#include <sys/utime.h>

int lstat(const char *path, struct stat *buf)
{
	return stat(path, buf);
}

int utime(const char *path, const struct utimbuf *times)
{
	(void)path;
	(void)times;
	errno = EROFS;
	return -1;
}

#include <sys/statvfs.h>

int statvfs(const char *path, struct statvfs *buf)
{
	(void)path;
	(void)buf;
	errno = ENOSYS;
	return -1;
}

int fstatvfs(int fd, struct statvfs *buf)
{
	(void)fd;
	(void)buf;
	errno = ENOSYS;
	return -1;
}

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "uart.h"

/* One statically linked image: nothing can be loaded. */
void *dlopen(const char *file, int mode)
{
	(void)file;
	(void)mode;
	return NULL;
}

void *dlsym(void *handle, const char *name)
{
	(void)handle;
	(void)name;
	return NULL;
}

int dlclose(void *handle)
{
	(void)handle;
	return 0;
}

char *dlerror(void)
{
	return (char *)"no dynamic loading on the AE350";
}

int dladdr(const void *addr, Dl_info *info)
{
	(void)addr;
	(void)info;
	return 0;
}

/* -fstack-protector: the canary, and the report when one is found broken.
 * The guard is a fixed word; nothing on the AE350 can read it to forge one. */
uintptr_t __stack_chk_guard = 0x5aa5c33cu;

void __stack_chk_fail(void) __attribute__((noreturn));
void __stack_chk_fail(void)
{
	tv_put_str("TinyVCMI STACK SMASHED\r\n");
	abort();
}
