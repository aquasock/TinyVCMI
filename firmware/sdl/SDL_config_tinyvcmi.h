/* SDL_config for TinyVCMI: RV32IMAC bare metal, newlib, no OS. */
#ifndef SDL_config_h_
#define SDL_config_h_
#include "SDL_platform.h"
#define HAVE_STDARG_H 1
#define HAVE_STDDEF_H 1
#define HAVE_STDINT_H 1
#define HAVE_LIBC 1
/* newlib provides malloc; SDL_malloc.c then shims onto it (no dlmalloc) */
#define HAVE_MALLOC 1
#define HAVE_ASSERT_H 1
#define HAVE_CTYPE_H 1
#define HAVE_FLOAT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_MATH_H 1
#define HAVE_MEMORY_H 1
#define HAVE_SIGNAL_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STRINGS_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_WCHAR_H 1
#define HAVE_ALLOCA_H 1
#define HAVE_M_PI 1
#define HAVE_ACOS 1
#define HAVE_ACOSF 1
#define HAVE_ASIN 1
#define HAVE_ASINF 1
#define HAVE_ATAN 1
#define HAVE_ATANF 1
#define HAVE_ATAN2 1
#define HAVE_ATAN2F 1
#define HAVE_CEIL 1
#define HAVE_CEILF 1
#define HAVE_COPYSIGN 1
#define HAVE_COPYSIGNF 1
#define HAVE_COS 1
#define HAVE_COSF 1
#define HAVE_EXP 1
#define HAVE_EXPF 1
#define HAVE_FABS 1
#define HAVE_FABSF 1
#define HAVE_FLOOR 1
#define HAVE_FLOORF 1
#define HAVE_FMOD 1
#define HAVE_FMODF 1
#define HAVE_LOG 1
#define HAVE_LOGF 1
#define HAVE_POW 1
#define HAVE_POWF 1
#define HAVE_SIN 1
#define HAVE_SINF 1
#define HAVE_SQRT 1
#define HAVE_SQRTF 1
#define HAVE_SCALBN 1
#define HAVE_SCALBNF 1
#define HAVE_LOG10 1
#define HAVE_LOG10F 1
#define HAVE_TAN 1
#define HAVE_TANF 1
#define HAVE_TRUNC 1
#define HAVE_TRUNCF 1
#define HAVE_ICONV 0
#define HAVE_DLOPEN 0
/* Atomics.  Built without the A extension (tools/build_sdl2.sh with
   SDL_MARCH=rv32imc..., as the runtime is), GCC's __sync and __atomic
   builtins become calls into firmware/rt/atomic.c, which is what this tells
   SDL to use; with the A extension SDL keeps its own spinlock, patched to
   load the lock word before LR/SC (sdl2-riscv-atomics.patch, AE350-011). */
#if defined(__riscv) && !defined(__riscv_atomic)
#define HAVE_GCC_ATOMICS 1
#endif
/* subsystems */
#define SDL_VIDEO_DRIVER_TINYVCMI 1
#define SDL_VIDEO_DRIVER_DUMMY 1
/* The timer subsystem without its own thread: there is no preemption here,
   so SDL's timer callbacks cannot fire and a program polls SDL_GetTicks.
   SDL_TIMERS_DISABLED leaves SDL_TimerInit a no-op; the clock itself comes
   from firmware/sdl/SDL_systimer_tinyvcmi.c. */
#define SDL_TIMERS_DISABLED 1
/* No audio yet: audio is deferred in the port plan, and SDL_audio.c
   only compiles without a driver. */
#define SDL_AUDIO_DISABLED 1
#define SDL_JOYSTICK_DISABLED 1
#define SDL_HAPTIC_DISABLED 1
#define SDL_SENSOR_DISABLED 1
#define SDL_POWER_DISABLED 1
#define SDL_FILESYSTEM_DISABLED 1
/* No OS threads.  The generic backend (firmware/sdl, built by
   tools/build_sdl2.sh) supplies mutexes, semaphores, condition variables and
   the thread entry points; SDL_CreateThread then fails cleanly, which is the
   cooperative model the port plan assumes. */
#define SDL_THREADS_DISABLED 1
#define SDL_LOADSO_DISABLED 1
#define SDL_LOCALE_DISABLED 1
#endif
