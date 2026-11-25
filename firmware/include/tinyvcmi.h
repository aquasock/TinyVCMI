/* SPDX-License-Identifier: GPL-3.0-only
 *
 * From TinyNES f0f8501 firmware/include/tinynes.h, cut to what the TinyVCMI
 * AE350 system has: the UART registers the fabric decodes in the uncached
 * EXTS window (fpga/ae350_ddr3/exts_uart.sv), the memory map, the A25 cache
 * controls and the boot ROM's UART load protocol.
 */
#ifndef TINYVCMI_H
#define TINYVCMI_H

#include <stdint.h>

#define TV_REG(offset) (*(volatile uint32_t *)(0xe8000000u + (offset)))

#define TV_UART_DATA    TV_REG(0x00) /* write: byte to transmit */
#define TV_UART_STATUS  TV_REG(0x04) /* read; write 1s to clear bits 3, 4 */
#define TV_ID           TV_REG(0x08) /* read: TV_ID_VALUE */
#define TV_SCRATCH      TV_REG(0x0c) /* read and write */
#define TV_UART_RX      TV_REG(0x10) /* read: pops the oldest received byte */
#define TV_UART_CTRL    TV_REG(0x14) /* read and write: 0, link mode unused */

#define TV_UART_TX_READY   0x01u /* the transmit holding register is free */
#define TV_UART_TX_IDLE    0x02u /* and the last byte has left the pin */
#define TV_UART_RX_WAITING 0x04u /* a received byte is waiting */
#define TV_UART_RX_OVERRUN 0x08u /* a byte arrived to a full buffer; sticky */
#define TV_UART_RX_FRAME   0x10u /* a byte had no stop bit; sticky */
#define TV_UART_RX_VALID   0x100u /* TV_UART_RX bits 7:0 hold a byte */

#define TV_ID_VALUE        0x54563031u /* "TV01" */

#define TV_UART_BAUD 2000000u
#define TV_CORE_HZ   750000000u

/* The boot ROM at the reset vector, and on the RAM port the DDR3 at
 * 0x40000000 (fpga/ae350_ddr3/ahb_ddr3.v) with the fabric block RAM over
 * its top 64 KiB (ahb_ram.sv). */
#define TV_ROM_BASE   0x80000000u
#define TV_BRAM_BASE  0x7fff0000u
#define TV_BRAM_BYTES (64u << 10)
#define TV_DDR3_BASE  0x40000000u
#define TV_DDR3_BYTES (TV_BRAM_BASE - TV_DDR3_BASE)

/* mcache_ctl bit 0 enables the L1 I-cache, bit 1 the L1 D-cache;
 * mcctlcommand 6 writes back and invalidates the whole L1 D-cache. */
#define CSR_MCACHE_CTL    0x7ca
#define CSR_MCCTLCOMMAND  0x7cc
#define MCCTL_L1D_WBINVAL_ALL 6u

/* The boot ROM loads a program into the DDR3 over the UART (all words
 * little-endian, CRCs IEEE CRC-32 as zlib.crc32):
 *
 *   header: TV_LOAD_MAGIC, load address, length, entry, CRC of the image,
 *           CRC of the first 20 header bytes
 *   then the image in TV_LOAD_BLOCK_BYTES blocks (the last may be shorter),
 *   each followed by its CRC.
 *
 * The ROM answers the header, each block and the whole image with
 * TV_LOAD_ACK, or TV_LOAD_NAK and a reason letter; a NAKed block is sent
 * again. After the last ACK it prints "TinyVCMI RUN <entry>" and jumps.
 * The magic is TinyNES's, so its tools/load_ae350.py speaks to this ROM. */
#define TV_LOAD_MAGIC        0x314c4e54u /* "TNL1" */
#define TV_LOAD_HEADER_BYTES 24u
#define TV_LOAD_BLOCK_BYTES  8192u
#define TV_LOAD_ACK          0x06u
#define TV_LOAD_NAK          0x15u
#define TV_LOAD_TIMEOUT      'T' /* a byte took over 100 ms */
#define TV_LOAD_HEADER_CRC   'H'
#define TV_LOAD_ADDRESS      'A' /* the image is not inside the DDR3 */
#define TV_LOAD_BLOCK_CRC    'C'
#define TV_LOAD_OVERRUN      'O' /* the receive buffer overflowed */
#define TV_LOAD_IMAGE_CRC    'I' /* the image read back from the DDR3 */

#define CSR_STR(x) #x
#define CSR_SET(csr, value) \
	__asm__ volatile("csrs " CSR_STR(csr) ", %0" :: "r"(value) : "memory")
#define CSR_WRITE(csr, value) \
	__asm__ volatile("csrw " CSR_STR(csr) ", %0" :: "r"(value) : "memory")

static inline void tv_dcache_wbinval(void)
{
	CSR_WRITE(CSR_MCCTLCOMMAND, MCCTL_L1D_WBINVAL_ALL);
}

static inline uint32_t tv_cycles(void)
{
	uint32_t value;
	__asm__ volatile("csrr %0, mcycle" : "=r"(value));
	return value;
}

#endif
