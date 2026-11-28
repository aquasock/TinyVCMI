/* SPDX-License-Identifier: Zlib
 *
 * Function-entry trace for a diagnostic build of SDL2 on the AE350.  Licensed
 * under the zlib licence, as SDL2 is; see THIRD_PARTY.md.
 *
 * Built only by `SDL_TRACE=1 tools/build_sdl2.sh OUT_DIR`, which compiles
 * SDL's own sources and the TinyVCMI drivers with -finstrument-functions and
 * adds this file, uninstrumented, to that libSDL2.a.  While a program holds
 * tv_sdl_trace non-zero, every instrumented function entry prints one line on
 * the UART:
 *
 *   E<function> <call site>
 *
 * both in hex, written straight to the UART's registers so the trace calls
 * nothing that is itself traced and needs no stack beyond this frame.  The
 * A25 has no interrupt a hung program can be sampled from (AE350-005), so the
 * last lines before output stops name the loop it is in; resolve them with
 * addr2line against the program's ELF.  At 2 Mbaud a line costs about 90 us,
 * so a trace is slow and is for locating a fault, not for timing.
 */
#include <stdint.h>

#include <tinyvcmi.h>

volatile int tv_sdl_trace;

void __cyg_profile_func_enter(void *fn, void *site)
	__attribute__((no_instrument_function));
void __cyg_profile_func_exit(void *fn, void *site)
	__attribute__((no_instrument_function));

static void put(char c) __attribute__((no_instrument_function));
static void put(char c)
{
	while (!(TV_UART_STATUS & TV_UART_TX_READY))
		;
	TV_UART_DATA = (uint8_t)c;
}

static void hex(uint32_t v) __attribute__((no_instrument_function));
static void hex(uint32_t v)
{
	for (int shift = 28; shift >= 0; shift -= 4) {
		uint32_t d = (v >> shift) & 15;
		put((char)(d < 10 ? '0' + d : 'a' + d - 10));
	}
}

void __cyg_profile_func_enter(void *fn, void *site)
{
	if (!tv_sdl_trace)
		return;
	put('E');
	hex((uint32_t)(uintptr_t)fn);
	put(' ');
	hex((uint32_t)(uintptr_t)site);
	put('\n');
}

void __cyg_profile_func_exit(void *fn, void *site)
{
	(void)fn;
	(void)site;
}
