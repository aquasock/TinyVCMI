/* SPDX-License-Identifier: Zlib
 *
 * SDL video driver for TinyVCMI.  Licensed under the zlib licence, as SDL2
 * is; see THIRD_PARTY.md.
 *
 * 1280x720 ARGB8888, from two 4 MiB pages of the DDR3 at 0x7f000000, flipped
 * by the video unit at 0xe8010000 (VIDEO-003).  SDL's own software renderer
 * does all the drawing: this driver only reports the display, hands out the
 * back page as the window's framebuffer, and turns UpdateWindowFramebuffer
 * into a page flip.
 *
 * SDL builds the window surface itself, once, over the pixel pointer
 * CreateWindowFramebuffer returns (SDL_CreateWindowFramebuffer in
 * SDL_video.c), and its renderer draws through that surface.  So a flip
 * repoints window->surface's pixels at the new back page; a surface of the
 * driver's own would be one nothing draws into, which is what the first
 * version did, showing a never-drawn page and the page being drawn by turns.
 * After a flip the back page holds the frame before last, which is SDL's
 * renderer contract (the back buffer is undefined after a present, and every
 * frame is drawn whole); a program that writes the window surface directly,
 * without a renderer, must likewise redraw whole frames.  That is MiSTer's shape (sdl-driver/mister), chosen over
 * a hand-written renderer because SDL's software blitter is the path VCMI
 * 1.7.5 already runs on.
 *
 * A page flip is only legal once the pixels are in memory the video fetch can
 * see, so the A25's D-cache is written back and invalidated before BASE moves
 * (tv_dcache_wbinval, AE350-004).  The flip then waits for STATUS's pending
 * bit to clear, which is the video unit acknowledging BASE at the next
 * vertical blank, so a caller that flips faster than 60 Hz is paced by the
 * raster rather than tearing.
 */
#include "SDL_internal.h"

#if SDL_VIDEO_DRIVER_TINYVCMI

#include "SDL_tinyvcmivideo.h"
#include "video/SDL_sysvideo.h"

#include <tinyvcmi.h>

#define TINYVCMIVID_DRIVER_NAME "tinyvcmi"

/* The two pages the video unit can show, TV_VIDEO_BASE and 4 MiB above it
   (the runtime reserves 16 MiB for frame buffers below the block RAM). */
#define PAGE_BYTES (TV_VID_STRIDE * TV_VID_HEIGHT)
static uint8_t *const page[2] = {
    (uint8_t *)TV_VIDEO_BASE,
    (uint8_t *)(TV_VIDEO_BASE + (4u << 20)),
};
static int front = 0;   /* the page the raster shows; front ^ 1 is drawn */

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
    front = 0;

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
    /* No allocation: the back page of the DDR3 is the surface's memory, and
       SDL marks a surface over given pixels SDL_PREALLOC, so it never frees
       them. */
    *format = SDL_PIXELFORMAT_ARGB8888;
    *pixels = (void *)page[front ^ 1];
    *pitch = TV_VID_STRIDE;
    return 0;
}

int TINYVCMI_UpdateWindowFramebuffer(_THIS, SDL_Window *window,
                                     const SDL_Rect *rects, int numrects)
{
    (void)_this;
    (void)rects;
    (void)numrects;
    if (!window->surface || window->surface->pixels != page[front ^ 1]) {
        return SDL_SetError("TinyVCMI: window surface is not the back page");
    }

    /* The pixels must be in the DDR3 before the raster can be pointed at
       them. */
    tv_dcache_wbinval();

    /* Hand the page that was just drawn to the video unit, then wait for it
       to take it at the next vertical blank so the next frame draws into a
       page the raster is not showing.  The first flip is what starts the
       raster (see VideoInit). */
    TV_VID_BASE = (uint32_t)(uintptr_t)page[front ^ 1];
    TV_VID_CTRL = 1;
    while (TV_VID_STATUS & TV_VID_STATUS_PENDING) {
        /* the video unit acknowledges BASE at the next vertical blank */
    }
    front ^= 1;

    /* The next frame draws into the other page, through the surface SDL's
       renderer holds. */
    window->surface->pixels = (void *)page[front ^ 1];
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
