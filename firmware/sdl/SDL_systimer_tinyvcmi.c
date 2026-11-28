/* SPDX-License-Identifier: Zlib
 *
 * SDL timer driver for TinyVCMI.  Licensed under the zlib licence, as SDL2
 * is; see THIRD_PARTY.md.
 *
 * The clock is the A25's mcycle counter at TV_CORE_HZ, which `rd_lat` and the
 * bench apps independently put at 750 MHz (a millisecond is 750,000 cycles).
 * There are no interrupts on this core in the current image (ae350_sys drives
 * GP_INT low and decodes no PLIC, AE350-005), so SDL_Delay is a spin on the
 * counter and SDL's own timer callbacks cannot fire: a program that waits must
 * poll SDL_GetTicks.  That is the cooperative model the port plan assumes for
 * the engine's threads.
 */
#include "SDL_internal.h"

#if defined(SDL_TIMER_TINYVCMI) || defined(SDL_TIMERS_DISABLED)

#include "SDL_timer.h"

#include <tinyvcmi.h>

static SDL_bool ticks_started = SDL_FALSE;

void SDL_TicksInit(void)
{
    ticks_started = SDL_TRUE;
}

void SDL_TicksQuit(void)
{
    ticks_started = SDL_FALSE;
}

Uint64 SDL_GetTicks64(void)
{
    if (!ticks_started) {
        SDL_TicksInit();
    }
    /* microseconds, so a 60 Hz frame (16,666 us) keeps its resolution */
    return tv_cycles64() / (TV_CORE_HZ / 1000000u);
}

Uint64 SDL_GetPerformanceCounter(void)
{
    return tv_cycles64();
}

Uint64 SDL_GetPerformanceFrequency(void)
{
    return (Uint64)TV_CORE_HZ;
}

void SDL_Delay(Uint32 ms)
{
    uint64_t until;

    if (!ticks_started) {
        SDL_TicksInit();
    }
    until = SDL_GetTicks64() + (uint64_t)ms * 1000u;
    while (SDL_GetTicks64() < until) {
        /* spin: no interrupts to sleep on */
    }
}

#endif /* SDL_TIMER_TINYVCMI */
