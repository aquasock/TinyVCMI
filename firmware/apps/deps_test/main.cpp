// SPDX-License-Identifier: GPL-3.0-only
//
// The libraries VCMI 1.7.5 links, as tools/build_vcmi_deps.sh builds them for
// the AE350, each made to do real work and checked: zlib, minizip-ng,
// libsquish, Boost.Filesystem over the SD card (firmware/rt/card.c),
// Boost.ProgramOptions, Boost.DateTime, and oneTBB's algorithms, task groups,
// arenas and concurrent containers on the cooperative threads.
#include <atomic>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include <boost/date_time/gregorian/gregorian.hpp>
#include <boost/filesystem.hpp>
#include <boost/program_options.hpp>
#include <tbb/concurrent_hash_map.h>
#include <tbb/concurrent_queue.h>
#include <tbb/concurrent_unordered_set.h>
#include <tbb/concurrent_vector.h>
#include <tbb/global_control.h>
#include <tbb/parallel_for.h>
#include <tbb/parallel_reduce.h>
#include <tbb/task_arena.h>
#include <tbb/task_group.h>

#include <squish.h>
#include <zlib.h>
extern "C" {
#include <minizip/mz.h>
#include <minizip/mz_strm.h>
#include <minizip/mz_strm_mem.h>
#include <minizip/mz_zip.h>
#include <minizip/mz_zip_rw.h>
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

static std::vector<uint8_t> pattern(size_t n)
{
	std::vector<uint8_t> v(n);
	uint32_t x = 12345;
	for (size_t i = 0; i < n; i++) {
		x = x * 1103515245u + 12345u;
		v[i] = (uint8_t)((i / 64) ^ (x >> 28));	// compressible, not trivial
	}
	return v;
}

static void test_zlib()
{
	auto in = pattern(64 * 1024);
	uLongf clen = compressBound(in.size());
	std::vector<uint8_t> c(clen), out(in.size());
	int rc = compress2(c.data(), &clen, in.data(), in.size(), 6);
	uLongf olen = out.size();
	int rc2 = uncompress(out.data(), &olen, c.data(), clen);
	check("zlib round trip", rc == Z_OK && rc2 == Z_OK && olen == in.size() && out == in);
	std::printf("zlib %s: 65536 -> %lu bytes and back\n", zlibVersion(), (unsigned long)clen);
}

static void test_minizip()
{
	auto data = pattern(20000);
	void *mem = mz_stream_mem_create();
	mz_stream_mem_set_grow_size(mem, 64 * 1024);
	mz_stream_open(mem, nullptr, MZ_OPEN_MODE_CREATE);
	void *writer = mz_zip_writer_create();
	int rc = mz_zip_writer_open(writer, mem, 0);
	mz_zip_file info = {};
	info.filename = "test/pattern.bin";
	info.compression_method = MZ_COMPRESS_METHOD_DEFLATE;
	info.modified_date = 1700000000;
	rc |= mz_zip_writer_add_buffer(writer, data.data(), (int32_t)data.size(), &info);
	rc |= mz_zip_writer_close(writer);
	mz_zip_writer_delete(&writer);

	const void *zbuf = nullptr;
	int32_t zlen = 0;
	mz_stream_mem_get_buffer(mem, &zbuf);
	mz_stream_mem_get_buffer_length(mem, &zlen);
	std::vector<uint8_t> zip((const uint8_t *)zbuf, (const uint8_t *)zbuf + zlen);
	mz_stream_close(mem);
	mz_stream_mem_delete(&mem);

	void *reader = mz_zip_reader_create();
	rc |= mz_zip_reader_open_buffer(reader, zip.data(), (int32_t)zip.size(), 0);
	rc |= mz_zip_reader_locate_entry(reader, "test/pattern.bin", 0);
	int32_t n = mz_zip_reader_entry_save_buffer_length(reader);
	std::vector<uint8_t> out(n > 0 ? n : 0);
	if (n > 0)
		rc |= mz_zip_reader_entry_save_buffer(reader, out.data(), n);
	mz_zip_reader_close(reader);
	mz_zip_reader_delete(&reader);
	check("minizip round trip", rc == MZ_OK && out == data);
	std::printf("minizip-ng: 20000-byte entry in a %ld-byte zip, read back %s\n",
		    (long)zlen, out == data ? "equal" : "DIFFERENT");
}

static void test_squish()
{
	uint8_t rgba[16 * 4], back[16 * 4];
	for (int i = 0; i < 16; i++) {
		rgba[i * 4 + 0] = (uint8_t)(i * 16);
		rgba[i * 4 + 1] = (uint8_t)(255 - i * 16);
		rgba[i * 4 + 2] = 128;
		rgba[i * 4 + 3] = 255;
	}
	uint8_t block[8];
	squish::Compress(rgba, block, squish::kDxt1);
	squish::Decompress(back, block, squish::kDxt1);
	int worst = 0;
	for (int i = 0; i < 64; i++) {
		int d = rgba[i] > back[i] ? rgba[i] - back[i] : back[i] - rgba[i];
		if (d > worst)
			worst = d;
	}
	// The same code built for the host gives this block and error 26.
	static const uint8_t host[8] = {0x50, 0xd1, 0x30, 0x1f, 0x55, 0xff, 0xaa, 0x00};
	check("squish DXT1 block equals the host's", std::memcmp(block, host, 8) == 0 && worst == 26);
	std::printf("libsquish: DXT1 block %02x%02x%02x%02x%02x%02x%02x%02x, worst channel error %d\n",
		    block[0], block[1], block[2], block[3], block[4], block[5], block[6], block[7], worst);
}

static void test_filesystem()
{
	namespace fs = boost::filesystem;
	boost::system::error_code it_ec, ec;
	int files = 0, dirs = 0, stat_errors = 0;
	uintmax_t bytes = 0;
	bool lod = false;
	for (fs::directory_iterator it("/card/data/Data", it_ec), end; !it_ec && it != end;
	     it.increment(it_ec)) {
		const fs::path &p = it->path();
		if (fs::is_directory(p, ec)) {
			dirs++;
			continue;
		}
		stat_errors += ec ? 1 : 0;
		files++;
		bytes += fs::file_size(p, ec);
		stat_errors += ec ? 1 : 0;
		lod |= p.filename() == "H3bitmap.lod";
	}
	bool exists = fs::exists("/card/data/config", ec);
	bool missing = !fs::exists("/card/data/no-such-thing", ec);
	if (it_ec)
		std::printf("  iterator: %s\n", it_ec.message().c_str());
	check("filesystem listing", !it_ec && files == 7 && lod && stat_errors == 0 &&
					    bytes == 273733593u);
	check("filesystem exists", exists && missing);
	std::printf("Boost.Filesystem: /card/data/Data has %d files, %llu bytes; config %s\n",
		    files, (unsigned long long)bytes, exists ? "found" : "MISSING");
}

static void test_program_options()
{
	namespace po = boost::program_options;
	po::options_description desc("opts");
	desc.add_options()("help", "help")("width", po::value<int>()->default_value(800), "w")(
		"map", po::value<std::string>(), "map");
	const char *argv[] = {"vcmi", "--width", "1280", "--map", "Arrogance.h3m"};
	po::variables_map vm;
	po::store(po::parse_command_line(5, argv, desc), vm);
	po::notify(vm);
	check("program_options",
	      vm["width"].as<int>() == 1280 && vm["map"].as<std::string>() == "Arrogance.h3m" &&
		      !vm.count("help"));
	std::printf("Boost.ProgramOptions: width %d, map %s\n", vm["width"].as<int>(),
		    vm["map"].as<std::string>().c_str());
}

static void test_date_time()
{
	using namespace boost::gregorian;
	date d(1999, Feb, 28);	// Heroes III's release
	date later = d + days(10000);
	check("date_time", later == date(2026, Jul, 16) && later.day_of_week() == Thursday);
	std::printf("Boost.DateTime: 10000 days after %s is %s\n", to_iso_extended_string(d).c_str(),
		    to_iso_extended_string(later).c_str());
}

static void test_tbb()
{
	uint64_t t0 = tv_cycles64();
	std::vector<int> v(100000);
	tbb::parallel_for(tbb::blocked_range<size_t>(0, v.size()),
			  [&](const tbb::blocked_range<size_t> &r) {
				  for (size_t i = r.begin(); i != r.end(); i++)
					  v[i] = (int)(i % 1000);
			  });
	long sum = tbb::parallel_reduce(
		tbb::blocked_range<size_t>(0, v.size()), 0L,
		[&](const tbb::blocked_range<size_t> &r, long acc) {
			for (size_t i = r.begin(); i != r.end(); i++)
				acc += v[i];
			return acc;
		},
		[](long a, long b) { return a + b; });
	check("parallel_for and reduce", sum == 49950000L);

	std::atomic<int> ran{0};
	tbb::task_group g;
	for (int i = 0; i < 50; i++)
		g.run([&] { ran++; });
	g.wait();
	check("task_group", ran.load() == 50);

	int conc = tbb::this_task_arena::max_concurrency();
	tbb::task_arena arena(2);
	int inside = 0;
	arena.execute([&] { inside = 7; });
	{
		tbb::global_control gc(tbb::global_control::max_allowed_parallelism, 1);
		tbb::parallel_for(0, 10, [&](int) { inside++; });
	}
	check("arena and global_control", inside == 17);

	tbb::concurrent_vector<int> cv;
	tbb::concurrent_hash_map<int, std::string> hm;
	tbb::concurrent_unordered_set<int> us;
	tbb::concurrent_queue<int> q;
	tbb::parallel_for(0, 1000, [&](int i) {
		cv.push_back(i);
		tbb::concurrent_hash_map<int, std::string>::accessor a;
		hm.insert(a, i % 100);
		a->second = std::to_string(i % 100);
		us.insert(i % 37);
		q.push(i);
	});
	long qsum = 0;
	for (int x; q.try_pop(x);)
		qsum += x;
	tbb::concurrent_hash_map<int, std::string>::const_accessor ca;
	bool found = hm.find(ca, 42) && ca->second == "42";
	check("concurrent containers", cv.size() == 1000 && hm.size() == 100 && us.size() == 37 &&
						qsum == 499500 && found);
	double ms = (double)(tv_cycles64() - t0) / (TV_CORE_HZ / 1000.0);
	std::printf("oneTBB: max_concurrency %d, sum %ld, 50 tasks, containers %zu/%zu/%zu, %.1f ms\n",
		    conc, sum, cv.size(), hm.size(), us.size(), ms);
}

int main()
{
	std::printf("TinyVCMI DEPS test\n");
	std::fflush(stdout);
	test_zlib();
	test_minizip();
	test_squish();
	test_filesystem();
	test_program_options();
	test_date_time();
	test_tbb();
	std::printf("TinyVCMI DEPS %s, %d wrong\n", fails ? "BAD" : "OK", fails);
	return fails ? 1 : 0;
}
