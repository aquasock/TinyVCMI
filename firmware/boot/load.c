/* SPDX-License-Identifier: GPL-3.0-only */
#include "load.h"

#include "tinyvcmi.h"
#include "uart.h"

#define DDR3_END (TV_DDR3_BASE + TV_DDR3_BYTES)

#define BYTE_TIMEOUT (TV_CORE_HZ / 10)   /* within a header or block */
#define IDLE_TIMEOUT (2 * TV_CORE_HZ)    /* before a block: give up */
#define QUIET_CYCLES (TV_CORE_HZ / 100)  /* line silent after a NAK */

static uint32_t window;

/* IEEE CRC-32 kept inverted between bytes: start at ~0, finish with ~. */
static uint32_t crc32_byte(uint32_t crc, uint8_t byte)
{
	crc ^= byte;
	for (int k = 0; k < 8; k++)
		crc = (crc >> 1) ^ (0xedb88320u & -(crc & 1));
	return crc;
}

/* The next received byte, or -1 after timeout core cycles without one. */
static int get_byte(uint32_t timeout)
{
	uint32_t start = tv_cycles();

	do {
		uint32_t value = TV_UART_RX;
		if (value & TV_UART_RX_VALID)
			return (int)(value & 0xff);
	} while (tv_cycles() - start < timeout);
	return -1;
}

/* Receive count bytes to dst, adding them to *crc; -1 on a timeout. */
static int get_bytes(uint8_t *dst, uint32_t count, uint32_t *crc)
{
	while (count--) {
		int byte = get_byte(BYTE_TIMEOUT);
		if (byte < 0)
			return -1;
		*dst++ = (uint8_t)byte;
		*crc = crc32_byte(*crc, (uint8_t)byte);
	}
	return 0;
}

static int get_word(uint32_t *word, uint32_t *crc)
{
	uint8_t bytes[4];

	if (get_bytes(bytes, 4, crc))
		return -1;
	*word = (uint32_t)bytes[0] | (uint32_t)bytes[1] << 8 |
		(uint32_t)bytes[2] << 16 | (uint32_t)bytes[3] << 24;
	return 0;
}

static int overrun(void)
{
	return (TV_UART_STATUS & TV_UART_RX_OVERRUN) != 0;
}

void tv_load_reset(void)
{
	window = 0;
	TV_UART_STATUS = TV_UART_RX_OVERRUN | TV_UART_RX_FRAME;
}

/* Wait for the sender to stop, discarding what it sent, so the NAK is
 * read after the rest of a bad header or block. */
static void nak(char reason)
{
	uint32_t start = tv_cycles();

	while (tv_cycles() - start < QUIET_CYCLES)
		if (TV_UART_RX & TV_UART_RX_VALID)
			start = tv_cycles();
	tv_load_reset();
	tv_put_char((char)TV_LOAD_NAK);
	tv_put_char(reason);
}

/* Called once the magic has arrived; the entry, or 0 if the load failed. */
static uint32_t load(void)
{
	uint32_t header[TV_LOAD_HEADER_BYTES / 4];
	uint32_t crc = ~0u, unused = 0, address, length, entry, done;

	for (int i = 0; i < 4; i++)
		crc = crc32_byte(crc, (uint8_t)(TV_LOAD_MAGIC >> (8 * i)));
	for (int i = 1; i < 5; i++)
		if (get_word(&header[i], &crc)) {
			nak(TV_LOAD_TIMEOUT);
			return 0;
		}
	if (get_word(&header[5], &unused)) {
		nak(TV_LOAD_TIMEOUT);
		return 0;
	}
	if (overrun()) {
		nak(TV_LOAD_OVERRUN);
		return 0;
	}
	if (~crc != header[5]) {
		nak(TV_LOAD_HEADER_CRC);
		return 0;
	}
	address = header[1];
	length = header[2];
	entry = header[3];
	if (address < TV_DDR3_BASE || address >= DDR3_END || length == 0 ||
	    length > DDR3_END - address || entry < address ||
	    entry - address >= length || (entry & 1)) {
		nak(TV_LOAD_ADDRESS);
		return 0;
	}
	tv_put_char((char)TV_LOAD_ACK);

	for (done = 0; done < length;) {
		uint32_t count = length - done;
		uint8_t *dst = (uint8_t *)(uintptr_t)(address + done);
		uint32_t block_crc;
		int first;

		if (count > TV_LOAD_BLOCK_BYTES)
			count = TV_LOAD_BLOCK_BYTES;
		first = get_byte(IDLE_TIMEOUT);
		if (first < 0)
			return 0;
		*dst = (uint8_t)first;
		crc = crc32_byte(~0u, (uint8_t)first);
		if (get_bytes(dst + 1, count - 1, &crc) ||
		    get_word(&block_crc, &unused)) {
			nak(TV_LOAD_TIMEOUT);
			continue;
		}
		if (overrun()) {
			nak(TV_LOAD_OVERRUN);
			continue;
		}
		if (~crc != block_crc) {
			nak(TV_LOAD_BLOCK_CRC);
			continue;
		}
		tv_put_char((char)TV_LOAD_ACK);
		done += count;
	}

	/* Check what reached the DDR3, not what is in the D-cache. */
	tv_dcache_wbinval();
	crc = ~0u;
	for (done = 0; done < length; done++)
		crc = crc32_byte(crc,
				 *(volatile uint8_t *)(uintptr_t)(address + done));
	if (~crc != header[4]) {
		nak(TV_LOAD_IMAGE_CRC);
		return 0;
	}
	tv_put_char((char)TV_LOAD_ACK);
	tv_put_str("TinyVCMI RUN ");
	tv_put_hex(entry);
	tv_put_str("\r\n");
	tv_wait_tx_idle();
	return entry;
}

uint32_t tv_load_poll(uint32_t cycles)
{
	uint32_t start = tv_cycles();

	while (tv_cycles() - start < cycles) {
		uint32_t value = TV_UART_RX;
		if (!(value & TV_UART_RX_VALID))
			continue;
		window = window >> 8 | (value & 0xff) << 24;
		if (window == TV_LOAD_MAGIC) {
			uint32_t entry;

			tv_load_reset();
			entry = load();
			tv_load_reset();
			return entry;
		}
	}
	return 0;
}
