/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Polled output on the fabric UART, for the boot ROM and the runtime.
 */
#ifndef TINYVCMI_UART_H
#define TINYVCMI_UART_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void tv_put_char(char c);
void tv_put_str(const char *s);
void tv_put_hex(uint32_t value); /* eight digits */
void tv_put_dec(uint32_t value);
void tv_wait_tx_idle(void); /* until the last byte has left the pin */

#ifdef __cplusplus
}
#endif

#endif
