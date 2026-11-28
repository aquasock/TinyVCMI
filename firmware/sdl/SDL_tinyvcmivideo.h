/* SPDX-License-Identifier: Zlib
 *
 * SDL video driver for TinyVCMI: the frame buffer is DDR3 and the page flip
 * is the video unit's BASE register.
 *
 * Licensed under the zlib licence, as SDL2 is: this file is a driver added to
 * SDL2, so it carries SDL's licence rather than the project's GPL-3.0-only,
 * following PROV-001 (see THIRD_PARTY.md).
 */
#include "SDL_internal.h"

#ifndef SDL_tinyvcmivideo_h_
#define SDL_tinyvcmivideo_h_

#include "video/SDL_sysvideo.h"

/* The SDL_Surface over the DDR3 page, held as window data. */
#define TINYVCMI_SURFACE "_SDL_TinyVCMISurface"

int TINYVCMI_VideoInit(_THIS);
void TINYVCMI_VideoQuit(_THIS);
int TINYVCMI_CreateWindowFramebuffer(_THIS, SDL_Window *window, Uint32 *format,
                                     void **pixels, int *pitch);
int TINYVCMI_UpdateWindowFramebuffer(_THIS, SDL_Window *window,
                                     const SDL_Rect *rects, int numrects);
void TINYVCMI_DestroyWindowFramebuffer(_THIS, SDL_Window *window);

#endif /* SDL_tinyvcmivideo_h_ */
