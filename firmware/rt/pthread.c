/* SPDX-License-Identifier: GPL-3.0-only
 *
 * POSIX threads for the AE350, cooperatively: what libstdc++'s gthr-posix
 * layer, libgcc's emulated TLS and VCMI's engine ask of <pthread.h>, built
 * with the threaded toolchain (tools/build_toolchain_threads.sh) whose
 * newlib sysroot declares them.
 *
 * Nothing interrupts the A25 (AE350-005), so a thread runs until it waits:
 * every wait here -- a held mutex, a condition variable, a join, a sleep, a
 * rwlock, a once routine running elsewhere -- polls its condition and yields
 * to the next thread on the ring between polls, and sched_yield yields
 * outright.  A thread that never waits keeps the A25; that is the cost of no
 * preemption, and VCMI's CPU-bound threads (the AI) must be measured against
 * it.  Nothing yields inside malloc or stdio, so newlib's unlocked heap and
 * streams are safe; errno is newlib's one global, shared by every thread.
 *
 * Threads run on stacks from the heap in the DDR3, DEFAULT_STACK unless the
 * attribute asks for another size; the program's first thread keeps the
 * block-RAM stack crt0 gave it.  A pthread_t, a mutex, a condition variable
 * and a rwlock are each a pointer to their record, which fits the 32-bit
 * handle newlib defines; a handle still holding newlib's static initializer,
 * 0xFFFFFFFF (or zero), is given its record on first use.
 *
 * Times are the cycle counter's: CLOCK_REALTIME and CLOCK_MONOTONIC both
 * count from reset, there being no real-time clock.
 */
#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#include "tinyvcmi.h"

#define DEFAULT_STACK   (1024u * 1024u)
#define MIN_STACK       (16u * 1024u)
#define KEYS_MAX        128
#define DTOR_ROUNDS     4

void tv_thread_switch(uint32_t *save, const uint32_t *load);
void tv_thread_start(void);
void tv_thread_main(void *self) __attribute__((noreturn));
void tv_thread_yield(void);

/* ------------------------------------------------------------- threads */

struct tv_thread {
	uint32_t ctx[14];		/* ra, sp, s0..s11: tv_thread_switch */
	struct tv_thread *next, *prev;	/* the ring of threads that can run */
	void *(*fn)(void *);
	void *arg, *ret;
	uint8_t *stack;			/* ours to free, or NULL */
	int done, detached;
	struct tv_thread *zombie;	/* next finished, detached thread */
	void *keys[KEYS_MAX];
};

static struct tv_thread first = { .next = &first, .prev = &first };
static struct tv_thread *cur = &first;
static struct tv_thread *zombies;	/* finished and detached: to free */

static void release(struct tv_thread *t)
{
	free(t->stack);
	if (t != &first)
		free(t);
}

/* Free the detached threads that have finished.  Never the running one:
 * a finished thread is off the ring and never runs again. */
static void reap(void)
{
	while (zombies) {
		struct tv_thread *t = zombies;
		zombies = t->zombie;
		release(t);
	}
}

void tv_thread_yield(void)
{
	struct tv_thread *from = cur, *to = cur->next;

	reap();
	if (to == from)
		return;
	cur = to;
	tv_thread_switch(from->ctx, to->ctx);
}

int sched_yield(void)
{
	tv_thread_yield();
	return 0;
}

static void run_key_destructors(struct tv_thread *t);

/* Take t off the ring and run another thread; never returns.  The last
 * thread to finish ends the program, as POSIX has it. */
static void __attribute__((noreturn)) finish(struct tv_thread *t, void *ret)
{
	uint32_t scratch[14];

	run_key_destructors(t);
	t->ret = ret;
	t->done = 1;
	if (t->next == t)
		exit(0);
	struct tv_thread *to = t->next;
	t->prev->next = t->next;
	t->next->prev = t->prev;
	t->next = t->prev = t;
	if (t->detached) {
		t->zombie = zombies;
		zombies = t;
	}
	cur = to;
	tv_thread_switch(scratch, to->ctx);
	__builtin_unreachable();
}

void tv_thread_main(void *self)
{
	struct tv_thread *t = self;

	finish(t, t->fn(t->arg));
}

int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
		   void *(*fn)(void *), void *arg)
{
	size_t size = DEFAULT_STACK;
	uint8_t *stack = NULL, *own = NULL;
	struct tv_thread *t;

	if (attr && attr->stacksize > 0)
		size = (size_t)attr->stacksize < MIN_STACK ? MIN_STACK
							   : (size_t)attr->stacksize;
	if (attr && attr->stackaddr) {
		stack = attr->stackaddr;
	} else {
		own = stack = malloc(size);
		if (!stack)
			return EAGAIN;
	}
	t = calloc(1, sizeof *t);
	if (!t) {
		free(own);
		return EAGAIN;
	}
	t->fn = fn;
	t->arg = arg;
	t->stack = own;
	t->detached = attr && attr->detachstate == PTHREAD_CREATE_DETACHED;
	t->ctx[0] = (uint32_t)(uintptr_t)tv_thread_start;
	t->ctx[1] = (uint32_t)((uintptr_t)(stack + size) & ~(uintptr_t)15);
	t->ctx[2] = (uint32_t)(uintptr_t)t;
	/* Next on the ring after the creator: it runs at the creator's next
	 * wait. */
	t->next = cur->next;
	t->prev = cur;
	cur->next->prev = t;
	cur->next = t;
	*thread = (pthread_t)(uintptr_t)t;
	return 0;
}

int pthread_join(pthread_t thread, void **ret)
{
	struct tv_thread *t = (struct tv_thread *)(uintptr_t)thread;

	if (t == cur)
		return EDEADLK;
	if (t->detached)
		return EINVAL;
	while (!t->done)
		tv_thread_yield();
	if (ret)
		*ret = t->ret;
	release(t);
	return 0;
}

int pthread_detach(pthread_t thread)
{
	struct tv_thread *t = (struct tv_thread *)(uintptr_t)thread;

	if (t->detached)
		return EINVAL;
	t->detached = 1;
	if (t->done && t != cur) {
		t->zombie = zombies;
		zombies = t;
	}
	return 0;
}

pthread_t pthread_self(void)
{
	return (pthread_t)(uintptr_t)cur;
}

int pthread_equal(pthread_t a, pthread_t b)
{
	return a == b;
}

void pthread_exit(void *ret)
{
	finish(cur, ret);
}

int pthread_attr_init(pthread_attr_t *attr)
{
	memset(attr, 0, sizeof *attr);
	attr->is_initialized = 1;
	attr->stacksize = (int)DEFAULT_STACK;
	attr->detachstate = PTHREAD_CREATE_JOINABLE;
	return 0;
}

int pthread_attr_destroy(pthread_attr_t *attr)
{
	attr->is_initialized = 0;
	return 0;
}

int pthread_attr_setstacksize(pthread_attr_t *attr, size_t size)
{
	if (size < MIN_STACK)
		return EINVAL;
	attr->stacksize = (int)size;
	return 0;
}

int pthread_attr_getstacksize(const pthread_attr_t *attr, size_t *size)
{
	*size = (size_t)attr->stacksize;
	return 0;
}

int pthread_attr_setdetachstate(pthread_attr_t *attr, int state)
{
	if (state != PTHREAD_CREATE_DETACHED && state != PTHREAD_CREATE_JOINABLE)
		return EINVAL;
	attr->detachstate = state;
	return 0;
}

int pthread_attr_getdetachstate(const pthread_attr_t *attr, int *state)
{
	*state = attr->detachstate;
	return 0;
}

/* --------------------------------------------------------------- time */

static uint64_t now_ns(void)
{
	uint64_t c = tv_cycles64();

	return c / TV_CORE_HZ * 1000000000ull +
	       c % TV_CORE_HZ * 1000000000ull / TV_CORE_HZ;
}

static uint64_t ts_ns(const struct timespec *ts)
{
	if (ts->tv_sec < 0)
		return 0;
	return (uint64_t)ts->tv_sec * 1000000000ull + (uint64_t)ts->tv_nsec;
}

/* True once the absolute time ts has passed (a NULL ts never does). */
static int past(const struct timespec *ts)
{
	return ts && now_ns() >= ts_ns(ts);
}

int clock_gettime(clockid_t clock, struct timespec *ts)
{
	(void)clock;
	uint64_t ns = now_ns();

	ts->tv_sec = (time_t)(ns / 1000000000ull);
	ts->tv_nsec = (long)(ns % 1000000000ull);
	return 0;
}

int clock_getres(clockid_t clock, struct timespec *res)
{
	(void)clock;
	if (res) {
		res->tv_sec = 0;
		res->tv_nsec = 1 + 1000000000 / (long)TV_CORE_HZ;
	}
	return 0;
}

int nanosleep(const struct timespec *req, struct timespec *rem)
{
	uint64_t until = now_ns() + ts_ns(req);

	while (now_ns() < until)
		tv_thread_yield();
	if (rem)
		rem->tv_sec = rem->tv_nsec = 0;
	return 0;
}

int clock_nanosleep(clockid_t clock, int flags, const struct timespec *req,
		    struct timespec *rem)
{
	(void)clock;
	if (flags & TIMER_ABSTIME) {
		while (!past(req))
			tv_thread_yield();
		return 0;
	}
	nanosleep(req, rem);
	return 0;
}

int usleep(useconds_t us)
{
	struct timespec ts = { (time_t)(us / 1000000u), (long)(us % 1000000u) * 1000 };

	return nanosleep(&ts, NULL);
}

unsigned sleep(unsigned seconds)
{
	struct timespec ts = { (time_t)seconds, 0 };

	nanosleep(&ts, NULL);
	return 0;
}

long sysconf(int name)
{
	switch (name) {
	case _SC_NPROCESSORS_CONF:
	case _SC_NPROCESSORS_ONLN:
		return 1;
	case _SC_PAGESIZE:
		return 4096;
	case _SC_THREAD_KEYS_MAX:
		return KEYS_MAX;
	default:
		errno = EINVAL;
		return -1;
	}
}

/* ------------------------------------------------------------- mutexes */

struct tv_mutex {
	struct tv_thread *owner;
	unsigned count;
	int type;
};

static struct tv_mutex *mutex_of(pthread_mutex_t *m)
{
	if (*m == 0 || *m == _PTHREAD_MUTEX_INITIALIZER) {
		struct tv_mutex *x = calloc(1, sizeof *x);
		if (!x)
			return NULL;
		x->type = PTHREAD_MUTEX_DEFAULT;
		*m = (pthread_mutex_t)(uintptr_t)x;
	}
	return (struct tv_mutex *)(uintptr_t)*m;
}

int pthread_mutexattr_init(pthread_mutexattr_t *attr)
{
	memset(attr, 0, sizeof *attr);
	attr->is_initialized = 1;
	attr->type = PTHREAD_MUTEX_DEFAULT;
	return 0;
}

int pthread_mutexattr_destroy(pthread_mutexattr_t *attr)
{
	attr->is_initialized = 0;
	return 0;
}

int pthread_mutexattr_settype(pthread_mutexattr_t *attr, int type)
{
	if (type != PTHREAD_MUTEX_NORMAL && type != PTHREAD_MUTEX_RECURSIVE &&
	    type != PTHREAD_MUTEX_ERRORCHECK && type != PTHREAD_MUTEX_DEFAULT)
		return EINVAL;
	attr->type = type;
	attr->recursive = type == PTHREAD_MUTEX_RECURSIVE;
	return 0;
}

int pthread_mutexattr_gettype(const pthread_mutexattr_t *attr, int *type)
{
	*type = attr->type;
	return 0;
}

int pthread_mutex_init(pthread_mutex_t *m, const pthread_mutexattr_t *attr)
{
	struct tv_mutex *x = calloc(1, sizeof *x);

	if (!x)
		return ENOMEM;
	x->type = attr ? (attr->recursive ? PTHREAD_MUTEX_RECURSIVE : attr->type)
		       : PTHREAD_MUTEX_DEFAULT;
	*m = (pthread_mutex_t)(uintptr_t)x;
	return 0;
}

int pthread_mutex_destroy(pthread_mutex_t *m)
{
	if (*m != 0 && *m != _PTHREAD_MUTEX_INITIALIZER) {
		struct tv_mutex *x = (struct tv_mutex *)(uintptr_t)*m;
		if (x->owner)
			return EBUSY;
		free(x);
	}
	*m = 0;
	return 0;
}

/* Take x if it is free or ours to take again; else EBUSY, or EDEADLK for
 * an error-checking mutex the caller holds. */
static int take(struct tv_mutex *x)
{
	if (x->owner == cur) {
		if (x->type == PTHREAD_MUTEX_RECURSIVE) {
			x->count++;
			return 0;
		}
		if (x->type == PTHREAD_MUTEX_ERRORCHECK)
			return EDEADLK;
		return EBUSY;
	}
	if (x->owner)
		return EBUSY;
	x->owner = cur;
	x->count = 1;
	return 0;
}

static int lock_until(pthread_mutex_t *m, const struct timespec *until)
{
	struct tv_mutex *x = mutex_of(m);
	int rc;

	if (!x)
		return ENOMEM;
	while ((rc = take(x)) == EBUSY) {
		if (past(until))
			return ETIMEDOUT;
		tv_thread_yield();
	}
	return rc;
}

int pthread_mutex_lock(pthread_mutex_t *m)
{
	return lock_until(m, NULL);
}

int pthread_mutex_timedlock(pthread_mutex_t *m, const struct timespec *until)
{
	return lock_until(m, until);
}

int pthread_mutex_clocklock(pthread_mutex_t *m, clockid_t clock,
			    const struct timespec *until)
{
	(void)clock;
	return lock_until(m, until);
}

int pthread_mutex_trylock(pthread_mutex_t *m)
{
	struct tv_mutex *x = mutex_of(m);
	int rc;

	if (!x)
		return ENOMEM;
	rc = take(x);
	return rc == EDEADLK ? EBUSY : rc;
}

int pthread_mutex_unlock(pthread_mutex_t *m)
{
	struct tv_mutex *x = mutex_of(m);

	if (!x || x->owner != cur)
		return EPERM;
	if (--x->count == 0)
		x->owner = NULL;
	return 0;
}

/* ------------------------------------------------- condition variables */

struct tv_waiter {
	struct tv_waiter *next;
	int signalled;
};

struct tv_cond {
	struct tv_waiter *head, *tail;	/* waiters in arrival order */
};

static struct tv_cond *cond_of(pthread_cond_t *c)
{
	if (*c == 0 || *c == _PTHREAD_COND_INITIALIZER) {
		struct tv_cond *x = calloc(1, sizeof *x);
		if (!x)
			return NULL;
		*c = (pthread_cond_t)(uintptr_t)x;
	}
	return (struct tv_cond *)(uintptr_t)*c;
}

int pthread_condattr_init(pthread_condattr_t *attr)
{
	memset(attr, 0, sizeof *attr);
	attr->is_initialized = 1;
	attr->clock = CLOCK_REALTIME;
	return 0;
}

int pthread_condattr_destroy(pthread_condattr_t *attr)
{
	attr->is_initialized = 0;
	return 0;
}

int pthread_condattr_setclock(pthread_condattr_t *attr, clockid_t clock)
{
	attr->clock = clock;
	return 0;
}

int pthread_condattr_getclock(const pthread_condattr_t *attr, clockid_t *clock)
{
	*clock = attr->clock;
	return 0;
}

int pthread_cond_init(pthread_cond_t *c, const pthread_condattr_t *attr)
{
	(void)attr;
	struct tv_cond *x = calloc(1, sizeof *x);

	if (!x)
		return ENOMEM;
	*c = (pthread_cond_t)(uintptr_t)x;
	return 0;
}

int pthread_cond_destroy(pthread_cond_t *c)
{
	if (*c != 0 && *c != _PTHREAD_COND_INITIALIZER) {
		struct tv_cond *x = (struct tv_cond *)(uintptr_t)*c;
		if (x->head)
			return EBUSY;
		free(x);
	}
	*c = 0;
	return 0;
}

/* Wait on c, its mutex released, until signalled or until has passed.  The
 * waiter's record is on its own stack, which stays put while it waits. */
static int wait_until(pthread_cond_t *c, pthread_mutex_t *m,
		      const struct timespec *until)
{
	struct tv_cond *x = cond_of(c);
	struct tv_mutex *mx = mutex_of(m);
	struct tv_waiter w = { NULL, 0 };
	int rc = 0;

	if (!x || !mx)
		return ENOMEM;
	if (mx->owner != cur)
		return EPERM;
	unsigned count = mx->count;	/* a recursive mutex's whole hold */
	if (x->tail)
		x->tail->next = &w;
	else
		x->head = &w;
	x->tail = &w;
	mx->owner = NULL;
	mx->count = 0;
	while (!w.signalled) {
		if (past(until)) {
			/* Leave the queue: a later signal is for someone else. */
			struct tv_waiter **p = &x->head, *prev = NULL;
			while (*p && *p != &w) {
				prev = *p;
				p = &(*p)->next;
			}
			if (*p) {
				*p = w.next;
				if (x->tail == &w)
					x->tail = prev;
			}
			rc = ETIMEDOUT;
			break;
		}
		tv_thread_yield();
	}
	while (mx->owner)
		tv_thread_yield();
	mx->owner = cur;
	mx->count = count;
	return rc;
}

int pthread_cond_wait(pthread_cond_t *c, pthread_mutex_t *m)
{
	return wait_until(c, m, NULL);
}

int pthread_cond_timedwait(pthread_cond_t *c, pthread_mutex_t *m,
			   const struct timespec *until)
{
	return wait_until(c, m, until);
}

int pthread_cond_clockwait(pthread_cond_t *c, pthread_mutex_t *m,
			   clockid_t clock, const struct timespec *until)
{
	(void)clock;
	return wait_until(c, m, until);
}

int pthread_cond_signal(pthread_cond_t *c)
{
	struct tv_cond *x = cond_of(c);

	if (!x)
		return ENOMEM;
	if (x->head) {
		struct tv_waiter *w = x->head;
		x->head = w->next;
		if (!x->head)
			x->tail = NULL;
		w->signalled = 1;
	}
	return 0;
}

int pthread_cond_broadcast(pthread_cond_t *c)
{
	struct tv_cond *x = cond_of(c);

	if (!x)
		return ENOMEM;
	for (struct tv_waiter *w = x->head; w;) {
		struct tv_waiter *next = w->next;
		w->signalled = 1;
		w = next;
	}
	x->head = x->tail = NULL;
	return 0;
}

/* ------------------------------------------------------- reader-writer */

struct tv_rwlock {
	struct tv_thread *writer;
	unsigned readers, writers_waiting;
};

static struct tv_rwlock *rwlock_of(pthread_rwlock_t *l)
{
	if (*l == 0 || *l == _PTHREAD_RWLOCK_INITIALIZER) {
		struct tv_rwlock *x = calloc(1, sizeof *x);
		if (!x)
			return NULL;
		*l = (pthread_rwlock_t)(uintptr_t)x;
	}
	return (struct tv_rwlock *)(uintptr_t)*l;
}

int pthread_rwlock_init(pthread_rwlock_t *l, const pthread_rwlockattr_t *attr)
{
	(void)attr;
	struct tv_rwlock *x = calloc(1, sizeof *x);

	if (!x)
		return ENOMEM;
	*l = (pthread_rwlock_t)(uintptr_t)x;
	return 0;
}

int pthread_rwlock_destroy(pthread_rwlock_t *l)
{
	if (*l != 0 && *l != _PTHREAD_RWLOCK_INITIALIZER) {
		struct tv_rwlock *x = (struct tv_rwlock *)(uintptr_t)*l;
		if (x->writer || x->readers)
			return EBUSY;
		free(x);
	}
	*l = 0;
	return 0;
}

/* Readers wait while a writer holds or waits, so writers are not starved. */
static int read_until(pthread_rwlock_t *l, const struct timespec *until, int try)
{
	struct tv_rwlock *x = rwlock_of(l);

	if (!x)
		return ENOMEM;
	while (x->writer || x->writers_waiting) {
		if (try)
			return EBUSY;
		if (past(until))
			return ETIMEDOUT;
		tv_thread_yield();
	}
	x->readers++;
	return 0;
}

static int write_until(pthread_rwlock_t *l, const struct timespec *until, int try)
{
	struct tv_rwlock *x = rwlock_of(l);

	if (!x)
		return ENOMEM;
	if (x->writer == cur)
		return EDEADLK;
	if (try)
		return x->writer || x->readers ? EBUSY : (x->writer = cur, 0);
	x->writers_waiting++;
	while (x->writer || x->readers) {
		if (past(until)) {
			x->writers_waiting--;
			return ETIMEDOUT;
		}
		tv_thread_yield();
	}
	x->writers_waiting--;
	x->writer = cur;
	return 0;
}

int pthread_rwlock_rdlock(pthread_rwlock_t *l) { return read_until(l, NULL, 0); }
int pthread_rwlock_tryrdlock(pthread_rwlock_t *l) { return read_until(l, NULL, 1); }
int pthread_rwlock_wrlock(pthread_rwlock_t *l) { return write_until(l, NULL, 0); }
int pthread_rwlock_trywrlock(pthread_rwlock_t *l) { return write_until(l, NULL, 1); }

int pthread_rwlock_timedrdlock(pthread_rwlock_t *l, const struct timespec *until)
{
	return read_until(l, until, 0);
}

int pthread_rwlock_timedwrlock(pthread_rwlock_t *l, const struct timespec *until)
{
	return write_until(l, until, 0);
}

int pthread_rwlock_clockrdlock(pthread_rwlock_t *l, clockid_t clock,
			       const struct timespec *until)
{
	(void)clock;
	return read_until(l, until, 0);
}

int pthread_rwlock_clockwrlock(pthread_rwlock_t *l, clockid_t clock,
			       const struct timespec *until)
{
	(void)clock;
	return write_until(l, until, 0);
}

int pthread_rwlock_unlock(pthread_rwlock_t *l)
{
	struct tv_rwlock *x = rwlock_of(l);

	if (!x)
		return ENOMEM;
	if (x->writer == cur)
		x->writer = NULL;
	else if (x->readers)
		x->readers--;
	else
		return EPERM;
	return 0;
}

/* ----------------------------------------------------------- semaphores */

#include <semaphore.h>

int sem_init(sem_t *sem, int pshared, unsigned value)
{
	(void)pshared;
	sem->count = (int)value;
	return 0;
}

int sem_destroy(sem_t *sem)
{
	(void)sem;
	return 0;
}

static int sem_until(sem_t *sem, const struct timespec *until, int try)
{
	while (sem->count <= 0) {
		if (try || past(until)) {
			errno = try ? EAGAIN : ETIMEDOUT;
			return -1;
		}
		tv_thread_yield();
	}
	sem->count--;
	return 0;
}

int sem_wait(sem_t *sem) { return sem_until(sem, NULL, 0); }
int sem_trywait(sem_t *sem) { return sem_until(sem, NULL, 1); }

int sem_timedwait(sem_t *sem, const struct timespec *until)
{
	return sem_until(sem, until, 0);
}

int sem_post(sem_t *sem)
{
	sem->count++;
	return 0;
}

int sem_getvalue(sem_t *sem, int *value)
{
	*value = sem->count;
	return 0;
}

/* ------------------------------------------------ keys and once routines */

static unsigned char key_used[KEYS_MAX];
static void (*key_dtor[KEYS_MAX])(void *);

int pthread_key_create(pthread_key_t *key, void (*dtor)(void *))
{
	for (unsigned k = 0; k < KEYS_MAX; k++)
		if (!key_used[k]) {
			key_used[k] = 1;
			key_dtor[k] = dtor;
			/* A key used before may have left values behind. */
			struct tv_thread *t = cur;
			do {
				t->keys[k] = NULL;
				t = t->next;
			} while (t != cur);
			*key = (pthread_key_t)k;
			return 0;
		}
	return EAGAIN;
}

int pthread_key_delete(pthread_key_t key)
{
	if (key >= KEYS_MAX || !key_used[key])
		return EINVAL;
	key_used[key] = 0;
	key_dtor[key] = NULL;
	return 0;
}

void *pthread_getspecific(pthread_key_t key)
{
	return key < KEYS_MAX ? cur->keys[key] : NULL;
}

int pthread_setspecific(pthread_key_t key, const void *value)
{
	if (key >= KEYS_MAX || !key_used[key])
		return EINVAL;
	cur->keys[key] = (void *)value;
	return 0;
}

/* Newest key first: libgcc's emulated TLS frees a thread's thread_local
 * storage from the key it creates at the first thread_local access, and
 * libsupc++ runs thread_local destructors from a key created after that
 * storage exists, so the objects are destroyed before their memory goes.
 * POSIX leaves the order open. */
static void run_key_destructors(struct tv_thread *t)
{
	for (int round = 0; round < DTOR_ROUNDS; round++) {
		int ran = 0;
		for (unsigned k = KEYS_MAX; k-- > 0;) {
			void *v = t->keys[k];
			if (v && key_used[k] && key_dtor[k]) {
				t->keys[k] = NULL;
				key_dtor[k](v);
				ran = 1;
			}
		}
		if (!ran)
			break;
	}
}

/* A routine that throws (std::call_once's callable may) leaves the once
 * not run, so the next caller runs it, as C++ requires; this file is built
 * with -fexceptions for the cleanup to run during the unwind. */
static void once_unwound(pthread_once_t **once)
{
	if (*once && (*once)->init_executed == 2)
		(*once)->init_executed = 0;
}

/* init_executed: 0 not run, 2 running in some thread, 1 done.  A routine
 * that waits lets others run, and they wait for it in turn. */
int pthread_once(pthread_once_t *once, void (*fn)(void))
{
	if (once->init_executed == 1)
		return 0;
	if (once->init_executed == 0) {
		pthread_once_t *guard __attribute__((cleanup(once_unwound))) = once;
		once->init_executed = 2;
		fn();
		once->init_executed = 1;
		return 0;
	}
	while (once->init_executed != 1)
		tv_thread_yield();
	return 0;
}

/* libstdc++ and libgcc take a thread routine's cancellation as absent; VCMI
 * never cancels. */
int pthread_cancel(pthread_t thread)
{
	(void)thread;
	return ENOSYS;
}
