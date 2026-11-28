/* SPDX-License-Identifier: GPL-3.0-only
 *
 * 34 MiB of initialised data, a repeating 32-bit word, so that the ELF's
 * loadable image is that long and ae350run has to send all of it. */
	.section .data.big_pad, "aw"
	.balign 4
	.globl	big_pad
big_pad:
	.rept	(34 * 1024 * 1024) / 4
	.word	0x5aa5c33c
	.endr
	.globl	big_pad_end
big_pad_end:
