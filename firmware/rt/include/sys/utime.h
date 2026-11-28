/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Stands in for newlib's dummy <sys/utime.h>, which defines struct utimbuf
 * and declares no utime(); firmware/rt/posix.c provides it.
 */
#ifndef TINYVCMI_SYS_UTIME_H
#define TINYVCMI_SYS_UTIME_H

#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

struct utimbuf {
	time_t actime;
	time_t modtime;
};

int utime(const char *path, const struct utimbuf *times);

#ifdef __cplusplus
}
#endif

#endif
