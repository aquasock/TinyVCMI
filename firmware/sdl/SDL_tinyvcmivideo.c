/* SPDX-License-Identifier: Zlib
 *
 * SDL video driver for TinyVCMI.  Licensed under the zlib licence, as SDL2
 * is; see THIRD_PARTY.md.
 *
 * 1280x720 ARGB8888 from one 4 MiB page of the DDR3 at 0x7f000000, shown by
 * the video unit at 0xe8010000 (VIDEO-003).  SDL's own software renderer
 * does all the drawing: this driver only reports the display, hands out the
 * page as the window's framebuffer, and turns UpdateWindowFramebuffer into a
 * D-cache write-back.
 *
 * The display is single-buffered on purpose.  VCMI 1.7.5 draws into one
 * screen surface that it keeps for the whole run and redraws only what
 * changed (WindowHandler::simpleRedraw), and that surface aliases a
 * streaming texture which it copies over the whole window every frame; the
 * copy cost 123.9 of a 183.4 ms frame (core-log entry 42).  With
 * sdl2-tinyvcmi-zerocopy.patch the software renderer makes such a texture
 * over this page and skips copying it onto itself, so VCMI draws straight
 * into the picture and presenting costs only the write-back.  The price is
 * that the raster can show an update half drawn; two pages flipped would
 * not, but VCMI's persistent surface cannot alternate between them (entry
 * 42), and the user chose this over a fabric copy engine or dirty-region
 * copies.
 *
 * A present writes the D-cache back and invalidates it, so the pixels are
 * in the DDR3 the video fetch reads (tv_dcache_wbinval, AE350-004).  It does
 * not wait for vertical blank: nothing flips, so there is nothing to wait
 * for, and pacing is the program's.  The first present starts the raster.
 */
#include "SDL_internal.h"

#if SDL_VIDEO_DRIVER_TINYVCMI

#include "SDL_tinyvcmivideo.h"
#include "video/SDL_sysvideo.h"

#include <tinyvcmi.h>

#define TINYVCMIVID_DRIVER_NAME "tinyvcmi"

/* The page the video unit shows (the runtime reserves 16 MiB for frame
   buffers below the block RAM). */
static uint8_t *const page = (uint8_t *)TV_VIDEO_BASE;
static int shown = 0;   /* the raster has been started on the page */

static int TINYVCMI_Available(void)
{
    return 1;
}

static void TINYVCMI_PumpEvents(_THIS)
{
    /* No input yet: the TinyTang link's keyboard and mouse frames are not
       decoded in this image (INPUT-002).  SDL needs the hook to exist. */
}

static void TINYVCMI_DeleteDevice(SDL_VideoDevice *device)
{
    SDL_free(device);
}

static SDL_VideoDevice *TINYVCMI_CreateDevice(void)
{
    SDL_VideoDevice *device;

    if (!TINYVCMI_Available()) {
        return 0;
    }

    device = (SDL_VideoDevice *)SDL_calloc(1, sizeof(SDL_VideoDevice));
    if (!device) {
        SDL_OutOfMemory();
        return 0;
    }

    device->VideoInit = TINYVCMI_VideoInit;
    device->VideoQuit = TINYVCMI_VideoQuit;
    device->PumpEvents = TINYVCMI_PumpEvents;
    device->CreateWindowFramebuffer = TINYVCMI_CreateWindowFramebuffer;
    device->UpdateWindowFramebuffer = TINYVCMI_UpdateWindowFramebuffer;
    device->DestroyWindowFramebuffer = TINYVCMI_DestroyWindowFramebuffer;
    device->free = TINYVCMI_DeleteDevice;

    return device;
}

VideoBootStrap TINYVCMI_bootstrap = {
    TINYVCMIVID_DRIVER_NAME, "TinyVCMI DDR3 frame buffer",
    TINYVCMI_CreateDevice,
    NULL /* no ShowMessageBox implementation */
};

int TINYVCMI_VideoInit(_THIS)
{
    SDL_DisplayMode mode;

    SDL_Log("tinyvcmi: VideoInit");
    SDL_zero(mode);
    mode.format = SDL_PIXELFORMAT_ARGB8888;
    mode.w = TV_VID_WIDTH;
    mode.h = TV_VID_HEIGHT;
    mode.refresh_rate = 60;
    mode.driverdata = NULL;
    if (SDL_AddBasicVideoDisplay(&mode) < 0) {
        return -1;
    }
    SDL_AddDisplayMode(&_this->displays[0], &mode);

    /* The raster is NOT started here.  Turning it on before a frame has been
       drawn would show whatever the DDR3 happened to hold, and if the program
       then died the junk would stay on screen for good: a program must not be
       able to leave the display showing a half-built frame.  The first
       UpdateWindowFramebuffer enables it, with a finished picture ready. */
    shown = 0;

    return 0;
}

void TINYVCMI_VideoQuit(_THIS)
{
    TV_VID_CTRL = 0;
}

int TINYVCMI_CreateWindowFramebuffer(_THIS, SDL_Window *window, Uint32 *format,
                                     void **pixels, int *pitch)
{
    (void)_this;
    if (window->w != TV_VID_WIDTH || window->h != TV_VID_HEIGHT) {
        return SDL_SetError("TinyVCMI: window must be %dx%d", TV_VID_WIDTH,
                            TV_VID_HEIGHT);
    }
    /* No allocation: the page is the surface's memory, and SDL marks a
       surface over given pixels SDL_PREALLOC, so it never frees them. */
    *format = SDL_PIXELFORMAT_ARGB8888;
    *pixels = (void *)page;
    *pitch = TV_VID_STRIDE;
    return 0;
}

int TINYVCMI_UpdateWindowFramebuffer(_THIS, SDL_Window *window,
                                     const SDL_Rect *rects, int numrects)
{
    (void)_this;
    (void)rects;
    (void)numrects;
    if (!window->surface || window->surface->pixels != page) {
        return SDL_SetError("TinyVCMI: window surface is not the page");
    }

    /* The pixels must be in the DDR3 before the raster reads them. */
    tv_dcache_wbinval();

    if (!shown) {
        TV_VID_BASE = (uint32_t)(uintptr_t)page;
        TV_VID_CTRL = 1;
        shown = 1;
    }
    return 0;
}

void TINYVCMI_DestroyWindowFramebuffer(_THIS, SDL_Window *window)
{
    /* Nothing was allocated: SDL frees its own surface struct and leaves
       the DDR3 page alone. */
    (void)_this;
    (void)window;
}

#endif /* SDL_VIDEO_DRIVER_TINYVCMI */
