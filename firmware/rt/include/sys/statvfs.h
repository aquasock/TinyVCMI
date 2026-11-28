/* SPDX-License-Identifier: GPL-3.0-only
 *
 * <sys/statvfs.h>, which newlib lacks, for Boost.Filesystem's space().
 * firmware/rt/posix.c answers ENOSYS: the card's free space is TinyTang's to
 * know, and the card is read-only here.
 */
#ifndef TINYVCMI_SYS_STATVFS_H
#define TINYVCMI_SYS_STATVFS_H

#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/* fsblkcnt_t and fsfilcnt_t are newlib's, from <sys/types.h>. */
struct statvfs {
	unsigned long f_bsize, f_frsize;
	fsblkcnt_t f_blocks, f_bfree, f_bavail;
	fsfilcnt_t f_files, f_ffree, f_favail;
	unsigned long f_fsid, f_flag, f_namemax;
};

#define ST_RDONLY 1
#define ST_NOSUID 2

int statvfs(const char *__restrict path, struct statvfs *__restrict buf);
int fstatvfs(int fd, struct statvfs *buf);

#ifdef __cplusplus
}
#endif

#endif
