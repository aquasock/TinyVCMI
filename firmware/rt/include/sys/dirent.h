/* SPDX-License-Identifier: GPL-3.0-only
 *
 * From TinyNES f0f8501 firmware/rt/include/sys/dirent.h. Stands in for
 * newlib's <sys/dirent.h>, which refuses to build, so that <dirent.h>
 * declares the directory calls. Runtime programs have no directories:
 * opendir (syscalls.c) fails with ENOENT.
 */
#ifndef TINYVCMI_SYS_DIRENT_H
#define TINYVCMI_SYS_DIRENT_H

#include <sys/types.h>

typedef struct tv_dir DIR;

struct dirent {
	char d_name[256];
};

#endif
