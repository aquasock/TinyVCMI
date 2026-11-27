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

/* The video unit (fpga/ae350_ddr3/exts_video.sv, video_ddr3.v): 1280x720 at
 * 60 Hz on HDMI from a frame buffer in the DDR3, pixel (x, y) the 32-bit
 * word at BASE + 5120 y + 4 x, 0x00RRGGBB. BASE is taken at the next
 * vertical blank, so a page flip is writing it; write the D-cache back
 * first (tv_dcache_wbinval), since the video reads the DDR3, not the cache.
 * The top 16 MiB of the DDR3 below the block RAM are kept for frame
 * buffers: the runtime's heap stops below TV_VIDEO_BASE. */
#define TV_VID_REG(offset) (*(volatile uint32_t *)(0xe8010000u + (offset)))
#define TV_VID_CTRL    TV_VID_REG(0x00) /* bit 0: show the frame buffer */
#define TV_VID_STATUS  TV_VID_REG(0x04) /* bit 0 vblank, bit 1 BASE pending */
#define TV_VID_FRAMES  TV_VID_REG(0x08) /* vertical blanks since reset */
#define TV_VID_BASE    TV_VID_REG(0x0c) /* frame buffer byte address */
#define TV_VID_LATE    TV_VID_REG(0x10) /* lines shown before they were in */
#define TV_VID_ID      TV_VID_REG(0x14) /* TV_VID_ID_VALUE */
#define TV_VID_ID_VALUE  0x54565631u /* "TVV1" */
#define TV_VID_STATUS_VBLANK  0x01u
#define TV_VID_STATUS_PENDING 0x02u
#define TV_VID_WIDTH   1280u
#define TV_VID_HEIGHT  720u
#define TV_VID_STRIDE  (TV_VID_WIDTH * 4u)
#define TV_VID_FRAME_BYTES (TV_VID_STRIDE * TV_VID_HEIGHT)
#define TV_VIDEO_BASE  0x7f000000u /* 16 MiB below the block RAM */

/* Read-latency counters (fpga/ae350_ddr3/exts_perf.sv, ddr3_perf.v), read
 * only, counting from reset and wrapping; see exts_perf.sv for each word.
 * TV_PERF_SNAP(0..7) is ddr3_perf's PCLK snapshot, renewed about every
 * 10 us; it is one snapshot while TV_PERF_NSNAP holds still. */
#define TV_PERF_REG(offset) (*(volatile uint32_t *)(0xe8020000u + (offset)))
#define TV_PERF_ID      TV_PERF_REG(0x00) /* TV_PERF_ID_VALUE */
#define TV_PERF_BUSCLK  TV_PERF_REG(0x04) /* bus clocks */
#define TV_PERF_BEATS   TV_PERF_REG(0x08) /* DDR3 read beats ahb_ram took */
#define TV_PERF_BEAT_T  TV_PERF_REG(0x0c) /* bus clocks those beats waited */
#define TV_PERF_MISSES  TV_PERF_REG(0x10) /* beats the line buffer missed */
#define TV_PERF_MISS_T  TV_PERF_REG(0x14) /* bus clocks those misses took */
#define TV_PERF_STALL_T TV_PERF_REG(0x18) /* bus clocks the RAM port held HREADY low */
#define TV_PERF_NSNAP   TV_PERF_REG(0x1c) /* PCLK snapshots taken */
#define TV_PERF_SNAP(n) TV_PERF_REG(0x20 + 4 * (n))
#define TV_PERF_ID_VALUE 0x54565031u /* "TVP1" */

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

/* Run a store-only pass without the D-cache, so its stores go straight to the
 * DDR3 instead of allocating lines first. AE350-009 measured a cached 32-byte
 * line at 683.3 cycles against 479.9 uncached, the difference being the
 * read-allocate fill a write-only pass does not need; AE350-010 confirms the
 * A25 offers no memory-attribute register and no cache-block operations, so
 * this pair is the only way to reach that 1.42 times.
 *
 * The sequence is not optional. tv_dcache_save_off writes back and invalidates
 * the whole cache first, because a dirty line of the buffer left behind would
 * be written back over the new data later; and it must be called with the
 * buffer already in the DDR3, so the invalidation discards nothing wanted.
 * With the cache off every data access costs a DDR3 transfer, so the pass
 * belongs in a leaf loop that keeps its state in registers, must not call
 * anything, and must not touch data it needs quickly. A pass that reads gets
 * slower rather than faster: a 32-byte copy measured 1,210.9 cycles a line
 * cached and 1,614.9 uncached. Nothing else may run between the two calls.
 *
 * tv_dcache_restore needs no write-back afterwards: the cache holds nothing
 * valid from the window, so later reads refill from the DDR3. */
static inline uint32_t tv_dcache_save_off(void)
{
	uint32_t saved;

	__asm__ volatile("csrr %0, 0x7ca" : "=r"(saved));
	tv_dcache_wbinval();
	__asm__ volatile("csrw 0x7ca, %0" :: "r"(saved & ~0x2u) : "memory");
	__asm__ volatile("fence" ::: "memory");
	return saved;
}

static inline void tv_dcache_restore(uint32_t saved)
{
	__asm__ volatile("csrw 0x7ca, %0" :: "r"(saved) : "memory");
	__asm__ volatile("fence" ::: "memory");
}

static inline uint32_t tv_cycles(void)
{
	uint32_t value;
	__asm__ volatile("csrr %0, mcycle" : "=r"(value));
	return value;
}

/* The whole 64-bit cycle count, reread if the low half carried between
 * the reads of the high half. */
static inline uint64_t tv_cycles64(void)
{
	uint32_t high, low, check;
	do {
		__asm__ volatile("csrr %0, mcycleh" : "=r"(high));
		__asm__ volatile("csrr %0, mcycle" : "=r"(low));
		__asm__ volatile("csrr %0, mcycleh" : "=r"(check));
	} while (high != check);
	return (uint64_t)high << 32 | low;
}

#endif
