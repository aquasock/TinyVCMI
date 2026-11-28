/* SPDX-License-Identifier: GPL-3.0-only
 *
 * <dlfcn.h>, which newlib lacks: the AE350 runs one statically linked image
 * and loads nothing.  firmware/rt/posix.c's dlopen fails, so code that tries
 * to load an optional library (oneTBB's allocator and RML server) carries on
 * without it.
 */
#ifndef TINYVCMI_DLFCN_H
#define TINYVCMI_DLFCN_H

#ifdef __cplusplus
extern "C" {
#endif

#define RTLD_LAZY     0x0001
#define RTLD_NOW      0x0002
#define RTLD_GLOBAL   0x0100
#define RTLD_LOCAL    0x0000
#define RTLD_NOLOAD   0x0004
#define RTLD_DEFAULT  ((void *)0)
#define RTLD_NEXT     ((void *)-1)

typedef struct {
	const char *dli_fname;
	void *dli_fbase;
	const char *dli_sname;
	void *dli_saddr;
} Dl_info;

void *dlopen(const char *file, int mode);
void *dlsym(void *__restrict handle, const char *__restrict name);
int dlclose(void *handle);
char *dlerror(void);
int dladdr(const void *addr, Dl_info *info);

#ifdef __cplusplus
}
#endif

#endif
