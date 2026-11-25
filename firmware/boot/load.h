/* SPDX-License-Identifier: GPL-3.0-only
 *
 * The boot ROM's side of the UART load protocol in tinyvcmi.h.
 */
#ifndef TINYVCMI_LOAD_H
#define TINYVCMI_LOAD_H

#include <stdint.h>

/* Forget any partial header and clear the receive error flags. */
void tv_load_reset(void);

/* Watch the UART for up to cycles core cycles. If a header starts, receive
 * the program it describes into the DDR3, then print "TinyVCMI RUN <entry>"
 * and return the entry once the line is sent; the caller must fence.i and
 * jump. Returns 0 if nothing was loaded. */
uint32_t tv_load_poll(uint32_t cycles);

#endif
