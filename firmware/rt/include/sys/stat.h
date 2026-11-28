/* SPDX-License-Identifier: GPL-3.0-only
 *
 * newlib's <sys/stat.h> for the AE350, with lstat(), which newlib declares
 * only for a few systems; firmware/rt/posix.c provides it.
 */
#ifndef TINYVCMI_SYS_STAT_H
#define TINYVCMI_SYS_STAT_H

#include_next <sys/stat.h>

#ifdef __cplusplus
extern "C" {
#endif

int lstat(const char *__restrict path, struct stat *__restrict buf);

#ifdef __cplusplus
}
#endif

#endif
