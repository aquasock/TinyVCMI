/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Atomic operations for a program built without the A extension.
 *
 * On this A25 an AMO whose line is not in the D-cache, or any AMO with the
 * D-cache off, never completes, and LR on such a line does not allocate it,
 * so every SC after it fails (AE350-011).  The compiler emits those
 * instructions for C11 and C++ atomics, so programs are built for rv32imc
 * (rt.mk's RT_MARCH), and GCC then calls the functions below, libatomic's and
 * the __sync builtins' ABI, for every atomic read-modify-write and for loads
 * and stores wider than a word.
 *
 * Each one is a plain read-modify-write with machine interrupts masked
 * around it.  That is atomic because the A25 is the only hart and only an
 * interrupt could run code between the read and the write; today nothing
 * interrupts it at all (AE350-005), and masking keeps these correct if a
 * timer or input interrupt is added later.  Nothing here ever waits, so the
 * operations are lock-free in the C++ sense, and __atomic_is_lock_free says
 * so for naturally aligned objects of 1, 2, 4 and 8 bytes.
 *
 * Every memory order is met by a compiler barrier alone, with no fence
 * instruction: one hart always observes its own accesses in program order,
 * so no thread scheduled on it can see them reordered.  A fence would buy
 * nothing and costs a great deal here: a fence that orders writes, issued
 * after any memory access, takes 1,170 to 1,500 cycles on this A25 against
 * 22 for a whole relaxed fetch_add (firmware/apps/atomic_test, core-log
 * entry 41).  Ordering against the fabric (the video unit reading a frame)
 * is not what C++ atomics promise and is done explicitly, by
 * tv_dcache_wbinval before a flip.  __sync_synchronize, an explicit request
 * for a full barrier, still issues one.
 *
 * The functions take their ABI names through asm labels, so that GCC's
 * built-in declarations of those names do not clash with these C names.
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

static inline uint32_t irq_off(void)
{
	uint32_t s;

	__asm__ volatile("csrrci %0, mstatus, 8" : "=r"(s) :: "memory");
	return s;
}

static inline void irq_restore(uint32_t s)
{
	if (s & 8u)
		__asm__ volatile("csrsi mstatus, 8" ::: "memory");
}

/* A compiler barrier: see above for why no fence instruction is needed. */
static inline void fence_if(int order)
{
	(void)order;
	__asm__ volatile("" ::: "memory");
}

/* ---- sized __atomic_*_N ------------------------------------------------ */

#define LOAD_STORE(N, T)                                                     \
	T tv_atomic_load_##N(const volatile void *p, int m)                  \
		__asm__("__atomic_load_" #N);                                \
	T tv_atomic_load_##N(const volatile void *p, int m)                  \
	{                                                                    \
		uint32_t s = irq_off();                                      \
		fence_if(m);                                                 \
		T v = *(const volatile T *)p;                                \
		fence_if(m);                                                 \
		irq_restore(s);                                              \
		return v;                                                    \
	}                                                                    \
	void tv_atomic_store_##N(volatile void *p, T v, int m)               \
		__asm__("__atomic_store_" #N);                               \
	void tv_atomic_store_##N(volatile void *p, T v, int m)               \
	{                                                                    \
		uint32_t s = irq_off();                                      \
		fence_if(m);                                                 \
		*(volatile T *)p = v;                                        \
		fence_if(m);                                                 \
		irq_restore(s);                                              \
	}                                                                    \
	T tv_atomic_exchange_##N(volatile void *p, T v, int m)               \
		__asm__("__atomic_exchange_" #N);                            \
	T tv_atomic_exchange_##N(volatile void *p, T v, int m)               \
	{                                                                    \
		uint32_t s = irq_off();                                      \
		fence_if(m);                                                 \
		T old = *(volatile T *)p;                                    \
		*(volatile T *)p = v;                                        \
		fence_if(m);                                                 \
		irq_restore(s);                                              \
		return old;                                                  \
	}                                                                    \
	bool tv_atomic_cas_##N(volatile void *p, void *expected, T desired,  \
			       bool weak, int ms, int mf)                    \
		__asm__("__atomic_compare_exchange_" #N);                    \
	bool tv_atomic_cas_##N(volatile void *p, void *expected, T desired,  \
			       bool weak, int ms, int mf)                    \
	{                                                                    \
		(void)weak;                                                  \
		(void)mf;                                                    \
		uint32_t s = irq_off();                                      \
		fence_if(ms);                                                \
		T cur = *(volatile T *)p;                                    \
		bool hit = cur == *(T *)expected;                            \
		if (hit)                                                     \
			*(volatile T *)p = desired;                          \
		else                                                         \
			*(T *)expected = cur;                                \
		fence_if(ms);                                                \
		irq_restore(s);                                              \
		return hit;                                                  \
	}                                                                    \
	T tv_sync_val_cas_##N(volatile void *p, T oldv, T newv)              \
		__asm__("__sync_val_compare_and_swap_" #N);                  \
	T tv_sync_val_cas_##N(volatile void *p, T oldv, T newv)              \
	{                                                                    \
		uint32_t s = irq_off();                                      \
		fence_if(1);                                                 \
		T cur = *(volatile T *)p;                                    \
		if (cur == oldv)                                             \
			*(volatile T *)p = newv;                             \
		fence_if(1);                                                 \
		irq_restore(s);                                              \
		return cur;                                                  \
	}                                                                    \
	bool tv_sync_bool_cas_##N(volatile void *p, T oldv, T newv)          \
		__asm__("__sync_bool_compare_and_swap_" #N);                 \
	bool tv_sync_bool_cas_##N(volatile void *p, T oldv, T newv)          \
	{                                                                    \
		return tv_sync_val_cas_##N(p, oldv, newv) == oldv;           \
	}                                                                    \
	T tv_sync_lock_tas_##N(volatile void *p, T v)                        \
		__asm__("__sync_lock_test_and_set_" #N);                     \
	T tv_sync_lock_tas_##N(volatile void *p, T v)                        \
	{                                                                    \
		return tv_atomic_exchange_##N(p, v, 2 /* acquire */);        \
	}                                                                    \
	void tv_sync_lock_release_##N(volatile void *p)                      \
		__asm__("__sync_lock_release_" #N);                          \
	void tv_sync_lock_release_##N(volatile void *p)                      \
	{                                                                    \
		tv_atomic_store_##N(p, 0, 3 /* release */);                  \
	}

/* fetch_OP returns the old value and OP_fetch the new one; nand is
   ~(old & v), as GCC defines it. */
#define RMW(N, T, NAME, EXPR)                                                \
	T tv_atomic_fetch_##NAME##_##N(volatile void *p, T v, int m)         \
		__asm__("__atomic_fetch_" #NAME "_" #N);                     \
	T tv_atomic_fetch_##NAME##_##N(volatile void *p, T v, int m)         \
	{                                                                    \
		uint32_t s = irq_off();                                      \
		fence_if(m);                                                 \
		T old = *(volatile T *)p;                                    \
		*(volatile T *)p = (T)(EXPR);                                \
		fence_if(m);                                                 \
		irq_restore(s);                                              \
		return old;                                                  \
	}                                                                    \
	T tv_atomic_##NAME##_fetch_##N(volatile void *p, T v, int m)         \
		__asm__("__atomic_" #NAME "_fetch_" #N);                     \
	T tv_atomic_##NAME##_fetch_##N(volatile void *p, T v, int m)         \
	{                                                                    \
		uint32_t s = irq_off();                                      \
		fence_if(m);                                                 \
		T old = *(volatile T *)p;                                    \
		T neu = (T)(EXPR);                                           \
		*(volatile T *)p = neu;                                      \
		fence_if(m);                                                 \
		irq_restore(s);                                              \
		return neu;                                                  \
	}                                                                    \
	T tv_sync_fetch_and_##NAME##_##N(volatile void *p, T v)              \
		__asm__("__sync_fetch_and_" #NAME "_" #N);                   \
	T tv_sync_fetch_and_##NAME##_##N(volatile void *p, T v)              \
	{                                                                    \
		return tv_atomic_fetch_##NAME##_##N(p, v, 5 /* seq_cst */);  \
	}                                                                    \
	T tv_sync_##NAME##_and_fetch_##N(volatile void *p, T v)              \
		__asm__("__sync_" #NAME "_and_fetch_" #N);                   \
	T tv_sync_##NAME##_and_fetch_##N(volatile void *p, T v)              \
	{                                                                    \
		return tv_atomic_##NAME##_fetch_##N(p, v, 5 /* seq_cst */);  \
	}

#define SIZE(N, T)                                                           \
	LOAD_STORE(N, T)                                                     \
	RMW(N, T, add, old + v)                                              \
	RMW(N, T, sub, old - v)                                              \
	RMW(N, T, and, old & v)                                              \
	RMW(N, T, or, old | v)                                               \
	RMW(N, T, xor, old ^ v)                                              \
	RMW(N, T, nand, ~(old & v))

SIZE(1, uint8_t)
SIZE(2, uint16_t)
SIZE(4, uint32_t)
SIZE(8, uint64_t)

/* ---- generic, for objects of any size ---------------------------------- */

void tv_atomic_load(size_t n, const volatile void *src, void *ret, int m)
	__asm__("__atomic_load");
void tv_atomic_load(size_t n, const volatile void *src, void *ret, int m)
{
	uint32_t s = irq_off();
	fence_if(m);
	memcpy(ret, (const void *)src, n);
	fence_if(m);
	irq_restore(s);
}

void tv_atomic_store(size_t n, volatile void *dst, void *val, int m)
	__asm__("__atomic_store");
void tv_atomic_store(size_t n, volatile void *dst, void *val, int m)
{
	uint32_t s = irq_off();
	fence_if(m);
	memcpy((void *)dst, val, n);
	fence_if(m);
	irq_restore(s);
}

void tv_atomic_exchange(size_t n, volatile void *p, void *val, void *ret,
			int m) __asm__("__atomic_exchange");
void tv_atomic_exchange(size_t n, volatile void *p, void *val, void *ret,
			int m)
{
	uint32_t s = irq_off();
	fence_if(m);
	memcpy(ret, (const void *)p, n);
	memcpy((void *)p, val, n);
	fence_if(m);
	irq_restore(s);
}

bool tv_atomic_cas(size_t n, volatile void *p, void *expected, void *desired,
		   int ms, int mf) __asm__("__atomic_compare_exchange");
bool tv_atomic_cas(size_t n, volatile void *p, void *expected, void *desired,
		   int ms, int mf)
{
	(void)mf;
	uint32_t s = irq_off();
	fence_if(ms);
	bool hit = memcmp((const void *)p, expected, n) == 0;
	if (hit)
		memcpy((void *)p, desired, n);
	else
		memcpy(expected, (const void *)p, n);
	fence_if(ms);
	irq_restore(s);
	return hit;
}

/* ---- flags and queries -------------------------------------------------- */

bool tv_atomic_test_and_set(volatile void *p, int m)
	__asm__("__atomic_test_and_set");
bool tv_atomic_test_and_set(volatile void *p, int m)
{
	return tv_atomic_exchange_1(p, 1, m) != 0;
}

void tv_atomic_clear(volatile void *p, int m) __asm__("__atomic_clear");
void tv_atomic_clear(volatile void *p, int m)
{
	tv_atomic_store_1(p, 0, m);
}

bool tv_atomic_is_lock_free(size_t n, const volatile void *p)
	__asm__("__atomic_is_lock_free");
bool tv_atomic_is_lock_free(size_t n, const volatile void *p)
{
	uintptr_t a = (uintptr_t)p;

	return (n == 1 || n == 2 || n == 4 || n == 8) && (a & (n - 1)) == 0;
}

void tv_sync_synchronize(void) __asm__("__sync_synchronize");
void tv_sync_synchronize(void)
{
	__asm__ volatile("fence rw, rw" ::: "memory");
}
