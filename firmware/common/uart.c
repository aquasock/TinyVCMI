/* SPDX-License-Identifier: GPL-3.0-only */
#include "uart.h"

#include "tinyvcmi.h"

void tv_put_char(char c)
{
	while (!(TV_UART_STATUS & TV_UART_TX_READY))
		;
	TV_UART_DATA = (uint8_t)c;
}

void tv_put_str(const char *s)
{
	while (*s)
		tv_put_char(*s++);
}

void tv_put_hex(uint32_t value)
{
	for (int shift = 28; shift >= 0; shift -= 4)
		tv_put_char("0123456789abcdef"[(value >> shift) & 15]);
}

void tv_put_dec(uint32_t value)
{
	char digits[10];
	int count = 0;

	do {
		digits[count++] = (char)('0' + value % 10);
		value /= 10;
	} while (value);
	while (count)
		tv_put_char(digits[--count]);
}

void tv_wait_tx_idle(void)
{
	while (!(TV_UART_STATUS & TV_UART_TX_IDLE))
		;
}
