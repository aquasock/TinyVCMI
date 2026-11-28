// SPDX-License-Identifier: GPL-3.0-only
//
// The trial for building without the A extension (AE350-011, core-log entry
// 41).  Built for rv32imc, every atomic operation becomes a call to
// firmware/rt/atomic.c, which does it as a plain read-modify-write with
// interrupts masked.  This program runs every operation VCMI 1.7.5's
// std::atomic uses, at every width it uses and the 1- and 2-byte ones the
// library may, plus a struct too wide for any instruction, each on a line
// just written back and invalidated -- the case that hangs an AMO -- and
// checks the old value returned and the value left in memory.  It also
// checks that no AMO, LR or SC is in the image (the build does that; see the
// Makefile) and reports what is_lock_free says.
//
// Run it with:
//   tools/load_ae350.py --hold-on-bad 3 build/firmware/apps/atomic_test/atomic_test.elf
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <memory>

#include "tinyvcmi.h"

namespace {

int fails, checks;

template <typename T>
void check(const char *what, T got, T want)
{
	checks++;
	if (got != want) {
		fails++;
		std::printf("  WRONG %s: got %llx want %llx\n", what,
		            (unsigned long long)got, (unsigned long long)want);
	}
}

// Put the line out of the D-cache, as the hang needs.
void evict() { tv_dcache_wbinval(); }

template <typename T>
void integral(const char *name, std::atomic<T> &a)
{
	std::printf("%s (%u bytes) at %08lx, lock-free %d\n", name,
	            (unsigned)sizeof(T), (unsigned long)(uintptr_t)&a,
	            (int)a.is_lock_free());
	std::fflush(stdout);
	const T x = (T)0x5a5a5a5a5a5a5a5aull, y = (T)0x0123456789abcdefull;

	a.store(x); evict();
	check("load", a.load(), x);
	evict();
	check("exchange old", a.exchange(y), x);
	check("  memory", a.load(), y);
	a.store(x); evict();
	check("fetch_add old", a.fetch_add((T)3), x);
	check("  memory", a.load(), (T)(x + 3));
	a.store(x); evict();
	check("fetch_sub old", a.fetch_sub((T)5), x);
	check("  memory", a.load(), (T)(x - 5));
	a.store(x); evict();
	check("fetch_and old", a.fetch_and(y), x);
	check("  memory", a.load(), (T)(x & y));
	a.store(x); evict();
	check("fetch_or old", a.fetch_or(y), x);
	check("  memory", a.load(), (T)(x | y));
	a.store(x); evict();
	check("fetch_xor old", a.fetch_xor(y), x);
	check("  memory", a.load(), (T)(x ^ y));
	a.store(x); evict();
	check("++ result", (T)++a, (T)(x + 1));
	evict();
	check("-- result", (T)--a, x);

	// compare_exchange: a hit and a miss, strong and weak
	T expected = x;
	a.store(x); evict();
	check("cas strong hit", (int)a.compare_exchange_strong(expected, y), 1);
	check("  memory", a.load(), y);
	expected = x; evict();
	check("cas strong miss", (int)a.compare_exchange_strong(expected, x), 0);
	check("  expected now", expected, y);
	expected = y; evict();
	int tries = 0;
	while (!a.compare_exchange_weak(expected, x) && tries < 8)
		tries++;
	check("cas weak", a.load(), x);
}

struct Wide {
	uint32_t a, b, c;
	bool operator==(const Wide &o) const { return a == o.a && b == o.b && c == o.c; }
};

std::atomic<int32_t> i32;
std::atomic<int64_t> i64;
std::atomic<uint16_t> u16;
std::atomic<uint8_t> u8;
std::atomic<bool> flag_b;
std::atomic<Wide> wide;
std::atomic_flag aflag = ATOMIC_FLAG_INIT;
enum class State : int { Idle, Busy, Done };
std::atomic<State> state;

} // namespace

int main()
{
	std::printf("TinyVCMI atomics without the A extension\n");

	integral("int32", i32);
	integral("int64", i64);
	integral("uint16", u16);
	integral("uint8", u8);

	std::printf("bool, enum, flag, wide, shared_ptr\n");
	std::fflush(stdout);
	flag_b.store(false); evict();
	check("bool exchange old", (int)flag_b.exchange(true), 0);
	check("  memory", (int)flag_b.load(), 1);

	state.store(State::Busy); evict();
	State e = State::Busy;
	check("enum cas", (int)state.compare_exchange_strong(e, State::Done), 1);
	check("  memory", (int)state.load(), (int)State::Done);

	aflag.clear(); evict();
	check("flag first set", (int)aflag.test_and_set(), 0);
	evict();
	check("flag second set", (int)aflag.test_and_set(), 1);
	aflag.clear();
	check("flag cleared", (int)aflag.test_and_set(), 0);

	const Wide w1{1, 2, 3}, w2{4, 5, 6};
	std::printf("  wide (%u bytes) lock-free %d\n", (unsigned)sizeof(Wide),
	            (int)wide.is_lock_free());
	wide.store(w1); evict();
	check("wide load", (int)(wide.load() == w1), 1);
	Wide we = w1;
	evict();
	check("wide cas", (int)wide.compare_exchange_strong(we, w2), 1);
	check("  memory", (int)(wide.load() == w2), 1);
	evict();
	check("wide exchange", (int)(wide.exchange(w1) == w2), 1);

	// shared_ptr's counts: the single-threaded policy here, but check it
	// copies and releases right across evictions anyway.
	auto p = std::make_shared<int>(41);
	{
		auto q = p;
		evict();
		check("shared_ptr use_count", (long)p.use_count(), 2L);
	}
	evict();
	check("shared_ptr after", (long)p.use_count(), 1L);

	std::atomic_thread_fence(std::memory_order_seq_cst);
	__sync_synchronize();
	{
		volatile int s = 7;
		check("sync fetch_and_add", __sync_fetch_and_add(&s, 2), 7);
		check("sync val cas", __sync_val_compare_and_swap(&s, 9, 11), 9);
		check("sync lock tas", __sync_lock_test_and_set(&s, 1), 11);
		__sync_lock_release(&s);
		check("  released", (int)s, 0);
	}

	// What a call costs, with the line in the cache: 100,000 of each.
	{
		const uint32_t n = 100000;
		uint32_t t = tv_cycles();
		for (uint32_t k = 0; k < n; k++)
			i32.fetch_add(1, std::memory_order_relaxed);
		uint32_t relaxed = tv_cycles() - t;
		t = tv_cycles();
		for (uint32_t k = 0; k < n; k++)
			i32.fetch_add(1);
		uint32_t seq = tv_cycles() - t;
		t = tv_cycles();
		for (uint32_t k = 0; k < n; k++)
			i64.fetch_add(1);
		uint32_t seq64 = tv_cycles() - t;
		t = tv_cycles();
		for (uint32_t k = 0; k < n; k++) {
			int32_t e2 = i32.load(std::memory_order_relaxed);
			i32.compare_exchange_strong(e2, e2 + 1);
		}
		uint32_t cas = tv_cycles() - t;
		std::printf("cost, cycles per call with the line cached: "
		            "fetch_add relaxed %lu.%lu, seq_cst %lu.%lu, "
		            "64-bit %lu.%lu, cas loop %lu.%lu\n",
		            (unsigned long)(relaxed / n), (unsigned long)(relaxed * 10 / n % 10),
		            (unsigned long)(seq / n), (unsigned long)(seq * 10 / n % 10),
		            (unsigned long)(seq64 / n), (unsigned long)(seq64 * 10 / n % 10),
		            (unsigned long)(cas / n), (unsigned long)(cas * 10 / n % 10));
	}

	// What each fence costs alone, 10,000 in a loop with no memory access:
	// GCC puts fences inline around seq_cst and acquire/release loads and
	// stores, whatever the arch.
	{
		const uint32_t n = 10000;
		uint32_t t, c[6];
#define FENCE_LOOP(i, insn)                                              \
		t = tv_cycles();                                         \
		for (uint32_t k = 0; k < n; k++)                         \
			__asm__ volatile(insn ::: "memory");             \
		c[i] = tv_cycles() - t;
		FENCE_LOOP(0, "nop")
		FENCE_LOOP(1, "fence rw, rw")
		FENCE_LOOP(2, "fence r, rw")
		FENCE_LOOP(3, "fence rw, w")
		FENCE_LOOP(4, "fence w, w")
		FENCE_LOOP(5, "fence r, r")
#undef FENCE_LOOP
		std::printf("cost, cycles per loop pass: nop %lu, fence rw,rw %lu, "
		            "r,rw %lu, rw,w %lu, w,w %lu, r,r %lu\n",
		            (unsigned long)(c[0] / n), (unsigned long)(c[1] / n),
		            (unsigned long)(c[2] / n), (unsigned long)(c[3] / n),
		            (unsigned long)(c[4] / n), (unsigned long)(c[5] / n));
	}

	// And a fence after a memory access, which is where the cost is: a store
	// to a cached DDR3 line or to the block RAM (the stack), or a load.
	{
		const uint32_t n = 10000;
		static volatile uint32_t ddr3_word;
		volatile uint32_t bram_word = 0;
		uint32_t t, c[6];
#define ACCESS_LOOP(i, stmt, insn)                                       \
		t = tv_cycles();                                         \
		for (uint32_t k = 0; k < n; k++) {                       \
			stmt;                                            \
			__asm__ volatile(insn ::: "memory");             \
		}                                                        \
		c[i] = tv_cycles() - t;
		ACCESS_LOOP(0, ddr3_word = k, "nop")
		ACCESS_LOOP(1, ddr3_word = k, "fence rw, rw")
		ACCESS_LOOP(2, ddr3_word = k, "fence w, w")
		ACCESS_LOOP(3, bram_word = k, "fence rw, rw")
		ACCESS_LOOP(4, (void)ddr3_word, "fence rw, rw")
		ACCESS_LOOP(5, (void)ddr3_word, "fence r, rw")
#undef ACCESS_LOOP
		(void)bram_word;
		std::printf("cost, cycles per pass: DDR3 store %lu, +fence rw,rw "
		            "%lu, +fence w,w %lu; block RAM store +fence rw,rw %lu; "
		            "DDR3 load +fence rw,rw %lu, +fence r,rw %lu\n",
		            (unsigned long)(c[0] / n), (unsigned long)(c[1] / n),
		            (unsigned long)(c[2] / n), (unsigned long)(c[3] / n),
		            (unsigned long)(c[4] / n), (unsigned long)(c[5] / n));
	}

	std::printf("TinyVCMI ATOMIC %s, %d of %d wrong\n", fails ? "BAD" : "OK",
	            fails, checks);
	return fails ? 1 : 0;
}
