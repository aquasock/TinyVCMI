// SPDX-License-Identifier: GPL-3.0-only
//
// Every C++ thread facility VCMI 1.7.5 uses, on the AE350's cooperative
// pthreads (firmware/rt/pthread.c): threads and joins, mutex contention, a
// condition-variable queue, recursive_mutex, shared_mutex, thread_local with
// per-thread values and destructors, call_once retried after a throw,
// promise and future, sleep_for and wait_for against the cycle counter,
// exceptions thrown and caught in threads, detached threads, and a thousand
// create-join rounds that must not leak.
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <deque>
#include <future>
#include <malloc.h>
#include <mutex>
#include <shared_mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

extern "C" {
#include "tinyvcmi.h"
}

static int fails;

static void check(const char *what, bool ok)
{
	if (!ok) {
		std::printf("  WRONG %s\n", what);
		fails++;
	}
}

static double ms_since(uint64_t t0)
{
	return (double)(tv_cycles64() - t0) / (TV_CORE_HZ / 1000.0);
}

// ---------------------------------------------------------------- tls ----
static int tls_destroyed;
struct Tracked {
	std::string name = "unset";
	~Tracked() { tls_destroyed++; }
};
static thread_local Tracked tracked;
static thread_local int tls_counter = 0;

int main()
{
	std::printf("TinyVCMI THREADS test\n");
	std::fflush(stdout);
	uint64_t t0;

	// 1. Create and join; each thread's result comes back.
	{
		std::vector<int> out(8, -1);
		std::vector<std::thread> ts;
		for (int i = 0; i < 8; i++)
			ts.emplace_back([&out, i] { out[i] = i * i; });
		for (auto &t : ts)
			t.join();
		bool ok = true;
		for (int i = 0; i < 8; i++)
			ok &= out[i] == i * i;
		check("join results", ok);
		std::printf("1. 8 threads joined\n");
	}

	// 2. Mutex contention with yields inside the critical section.
	{
		std::mutex m;
		long counter = 0;
		int inside = 0, overlap = 0;
		std::vector<std::thread> ts;
		for (int i = 0; i < 6; i++)
			ts.emplace_back([&] {
				for (int k = 0; k < 500; k++) {
					std::lock_guard<std::mutex> g(m);
					overlap += inside++ != 0;
					std::this_thread::yield();
					counter++;
					inside--;
				}
			});
		for (auto &t : ts)
			t.join();
		check("mutex counter", counter == 3000);
		check("mutex exclusion", overlap == 0);
		std::printf("2. mutex: %ld increments, %d overlaps\n", counter, overlap);
	}

	// 3. Condition-variable producer and consumers.
	{
		std::mutex m;
		std::condition_variable cv;
		std::deque<int> q;
		bool done = false;
		long sum = 0;
		int got = 0;
		auto consumer = [&] {
			for (;;) {
				std::unique_lock<std::mutex> l(m);
				cv.wait(l, [&] { return !q.empty() || done; });
				if (q.empty())
					return;
				sum += q.front();
				q.pop_front();
				got++;
			}
		};
		std::thread c1(consumer), c2(consumer);
		for (int i = 1; i <= 1000; i++) {
			{
				std::lock_guard<std::mutex> g(m);
				q.push_back(i);
			}
			cv.notify_one();
			if (i % 7 == 0)
				std::this_thread::yield();
		}
		{
			std::lock_guard<std::mutex> g(m);
			done = true;
		}
		cv.notify_all();
		c1.join();
		c2.join();
		check("queue items", got == 1000 && sum == 500500);
		std::printf("3. queue: %d items, sum %ld\n", got, sum);
	}

	// 4. recursive_mutex.
	{
		std::recursive_mutex rm;
		int depth = 0;
		std::function<void(int)> f = [&](int n) {
			std::lock_guard<std::recursive_mutex> g(rm);
			depth++;
			if (n)
				f(n - 1);
		};
		std::thread t([&] { f(5); });
		t.join();
		check("recursive depth", depth == 6);
		check("recursive free after", rm.try_lock());
		rm.unlock();
		std::printf("4. recursive_mutex depth %d\n", depth);
	}

	// 5. shared_mutex: readers share, a writer excludes.
	{
		std::shared_mutex sm;
		int readers = 0, max_readers = 0, writer_saw_readers = 0, value = 0;
		std::vector<std::thread> ts;
		for (int i = 0; i < 4; i++)
			ts.emplace_back([&] {
				for (int k = 0; k < 20; k++) {
					std::shared_lock<std::shared_mutex> l(sm);
					readers++;
					if (readers > max_readers)
						max_readers = readers;
					std::this_thread::yield();
					readers--;
				}
			});
		ts.emplace_back([&] {
			for (int k = 0; k < 20; k++) {
				std::unique_lock<std::shared_mutex> l(sm);
				writer_saw_readers += readers != 0;
				value++;
				std::this_thread::yield();
			}
		});
		for (auto &t : ts)
			t.join();
		check("readers overlapped", max_readers > 1);
		check("writer exclusive", writer_saw_readers == 0 && value == 20);
		std::printf("5. shared_mutex: up to %d readers together\n", max_readers);
	}

	// 6. thread_local: a value per thread, and destructors at thread exit.
	{
		tracked.name = "main";
		tls_counter = 100;
		int before = tls_destroyed;
		std::vector<std::thread> ts;
		std::vector<std::string> names(3);
		std::vector<int> counts(3);
		for (int i = 0; i < 3; i++)
			ts.emplace_back([&, i] {
				names[i] = tracked.name;	// fresh per thread
				tracked.name = "t" + std::to_string(i);
				for (int k = 0; k <= i; k++) {
					tls_counter++;
					std::this_thread::yield();
				}
				counts[i] = tls_counter;
			});
		for (auto &t : ts)
			t.join();
		bool ok = true;
		for (int i = 0; i < 3; i++)
			ok &= names[i] == "unset" && counts[i] == i + 1;
		check("thread_local fresh per thread", ok);
		check("thread_local main untouched", tracked.name == "main" && tls_counter == 100);
		check("thread_local destructors", tls_destroyed - before == 3);
		std::printf("6. thread_local: %d destructors ran\n", tls_destroyed - before);
	}

	// 7. call_once: a throwing first call leaves it to run again.
	{
		std::once_flag flag;
		int calls = 0;
		bool threw = false;
		try {
			std::call_once(flag, [&] {
				calls++;
				throw std::runtime_error("first");
			});
		} catch (const std::runtime_error &) {
			threw = true;
		}
		std::thread t([&] { std::call_once(flag, [&] { calls++; }); });
		t.join();
		std::call_once(flag, [&] { calls++; });
		check("call_once", threw && calls == 2);
		std::printf("7. call_once: %d calls\n", calls);
	}

	// 8. promise and future across threads.
	{
		std::promise<int> p;
		std::future<int> f = p.get_future();
		std::thread t([&] {
			std::this_thread::sleep_for(std::chrono::milliseconds(5));
			p.set_value(42);
		});
		int v = f.get();
		t.join();
		check("future", v == 42);
		std::printf("8. future: %d\n", v);
	}

	// 9. Timed waits against the cycle counter.
	{
		t0 = tv_cycles64();
		std::this_thread::sleep_for(std::chrono::milliseconds(50));
		double slept = ms_since(t0);
		std::mutex m;
		std::condition_variable cv;
		std::unique_lock<std::mutex> l(m);
		t0 = tv_cycles64();
		bool timed_out = cv.wait_for(l, std::chrono::milliseconds(20)) == std::cv_status::timeout;
		double waited = ms_since(t0);
		check("sleep_for", slept >= 50.0 && slept < 55.0);
		check("wait_for", timed_out && waited >= 20.0 && waited < 25.0);
		std::printf("9. sleep_for 50 ms took %.2f ms, wait_for 20 ms %.2f ms\n", slept, waited);
	}

	// 10. Exceptions in threads, each with its own in-flight state.
	{
		int caught[2] = {0, 0};
		auto thrower = [&](int i) {
			try {
				try {
					throw std::runtime_error(i ? "b" : "a");
				} catch (const std::exception &) {
					std::this_thread::yield();	// the other one throws meanwhile
					throw;
				}
			} catch (const std::runtime_error &e) {
				caught[i] = e.what()[0] == (i ? 'b' : 'a');
			}
		};
		std::thread a(thrower, 0), b(thrower, 1);
		a.join();
		b.join();
		check("exceptions per thread", caught[0] && caught[1]);
		std::printf("10. exceptions: %d %d\n", caught[0], caught[1]);
	}

	// 11. Detached threads, then a thousand create-join rounds: no leak.
	{
		std::atomic<int> ran{0};
		for (int i = 0; i < 4; i++)
			std::thread([&] { ran++; }).detach();
		while (ran.load() < 4)
			std::this_thread::yield();
		std::this_thread::yield();	// lets the scheduler free them
		struct mallinfo before = mallinfo();
		t0 = tv_cycles64();
		for (int i = 0; i < 1000; i++) {
			std::thread t([] {});
			t.join();
		}
		double ms = ms_since(t0);
		struct mallinfo after = mallinfo();
		check("detached ran", ran.load() == 4);
		check("no leak", after.uordblks == before.uordblks);
		std::printf("11. 1000 create-join rounds in %.1f ms, %d bytes in use before, %d after\n",
			    ms, before.uordblks, after.uordblks);
	}

	std::printf("hardware_concurrency %u\n", std::thread::hardware_concurrency());
	std::printf("TinyVCMI THREADS %s, %d wrong\n", fails ? "BAD" : "OK", fails);
	return fails ? 1 : 0;
}
