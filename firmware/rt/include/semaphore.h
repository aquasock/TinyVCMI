/* SPDX-License-Identifier: GPL-3.0-only
 *
 * POSIX unnamed semaphores, which newlib lacks, for oneTBB's thread pool:
 * firmware/rt/pthread.c implements them on its cooperative threads, a wait
 * polling the count and yielding between polls.
 */
#ifndef TINYVCMI_SEMAPHORE_H
#define TINYVCMI_SEMAPHORE_H

#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
	volatile int count;
} sem_t;

#define SEM_FAILED ((sem_t *)0)

int sem_init(sem_t *sem, int pshared, unsigned value);
int sem_destroy(sem_t *sem);
int sem_wait(sem_t *sem);
int sem_trywait(sem_t *sem);
int sem_timedwait(sem_t *__restrict sem, const struct timespec *__restrict until);
int sem_post(sem_t *sem);
int sem_getvalue(sem_t *__restrict sem, int *__restrict value);

#ifdef __cplusplus
}
#endif

#endif
