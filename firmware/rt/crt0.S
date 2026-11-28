/* SPDX-License-Identifier: GPL-3.0-only
 *
 * From TinyNES f0f8501 firmware/rt/crt0.S. Entry of a runtime program,
 * jumped to by the boot ROM loader with the caches on and the image in the
 * DDR3. Sets the global and stack pointers and the trap vector, clears .bss,
 * runs the static constructors, then exit(main()).
 */
	.section .text.start, "ax"
	.globl	_start
_start:
	.option push
	.option norelax
	la	gp, __global_pointer$
	.option pop
	la	sp, __stack_top
	la	t0, tv_rt_trap_entry
	csrw	mtvec, t0
	csrw	mscratch, zero	/* no trap report started */
	li	t0, 3
	csrs	0x7ca, t0	/* mcache_ctl: I- and D-cache on */
	fence.i

	la	t1, __bss_start
	la	t2, __bss_end
1:	bgeu	t1, t2, 2f
	sw	zero, 0(t1)
	addi	t1, t1, 4
	j	1b
2:	call	__libc_init_array
	li	a0, 0
	li	a1, 0
	li	a2, 0
	call	main
	call	exit
3:	j	3b

	/* Report a trap on the UART and go back to the boot ROM:
	 *
	 *   BAD TRAP C=<mcause> P=<mepc> V=<mtval> RA=<ra> SP=<sp> GP=<gp>
	 *       MS=<mstatus>
	 *
	 * on one line. The report makes no memory access but the UART's
	 * registers: every character is an immediate and the hex digits are
	 * computed, because the program's .rodata and stack are in the DDR3 or
	 * the block RAM, either of which may be what failed, and a handler
	 * that reads its strings from there can trap or hang mid-line. mscratch
	 * marks the report as started, so a trap taken inside it prints
	 *
	 *   BAD TRAP2 C=<mcause> P=<mepc> V=<mtval>
	 *
	 * and stops there instead of starting over. ra, sp and gp are the
	 * faulting context's, copied before anything else runs; the s and t
	 * registers are used freely, since the program does not resume.
	 * Programs with their own handler jump here for any trap they do not
	 * handle, with the faulting context's registers restored. */
	.equ	UART, 0xe8000000	/* TV_UART_DATA; TV_UART_STATUS at +4 */

	/* Send the byte in \reg (t1 or t2), waiting while the holding
	 * register is full (TV_UART_TX_READY). Uses t0 and t3. */
	.macro	putr reg
1:	lw	t0, 4(t3)
	andi	t0, t0, 1
	beqz	t0, 1b
	sw	\reg, 0(t3)
	.endm

	.macro	putc ch
	li	t1, \ch
	putr	t1
	.endm

	/* " AB=" (or " A=" when b is 0) then \reg in hex. */
	.macro	field reg, a, b=0
	putc	' '
	putc	\a
	.if	\b
	putc	\b
	.endif
	putc	'='
	mv	a0, \reg
	jal	s0, hex32
	.endm

	.text
	.align	2
	.globl	tv_rt_trap_entry
	.type	tv_rt_trap_entry, @function
tv_rt_trap_entry:
	mv	s1, ra
	mv	s2, sp
	mv	s3, gp
	li	t3, UART
	csrr	s4, mcause
	csrr	s5, mepc
	csrr	s6, mtval
	csrrwi	t4, mscratch, 1
	putc	'\r'
	putc	'\n'
	putc	'B'
	putc	'A'
	putc	'D'
	putc	' '
	putc	'T'
	putc	'R'
	putc	'A'
	putc	'P'
	bnez	t4, 5f
	field	s4, 'C'
	field	s5, 'P'
	field	s6, 'V'
	field	s1, 'R', 'A'
	field	s2, 'S', 'P'
	field	s3, 'G', 'P'
	csrr	s7, mstatus
	field	s7, 'M', 'S'
	putc	'\r'
	putc	'\n'
4:	lw	t0, 4(t3)	/* TV_UART_TX_IDLE: the line has left the pin */
	andi	t0, t0, 2
	beqz	t0, 4b
	j	tv_rt_reboot

5:	putc	'2'
	field	s4, 'C'
	field	s5, 'P'
	field	s6, 'V'
	putc	'\r'
	putc	'\n'
6:	j	6b

	/* a0 in eight hex digits; returns through s0. Uses t0, t2 and t5. */
hex32:
	li	t5, 28
7:	srl	t2, a0, t5
	andi	t2, t2, 15
	li	t0, 10
	blt	t2, t0, 8f
	addi	t2, t2, 'a' - 10 - '0'
8:	addi	t2, t2, '0'
	putr	t2
	addi	t5, t5, -4
	bgez	t5, 7b
	jr	s0
	.size	tv_rt_trap_entry, . - tv_rt_trap_entry

	/* Restart the boot ROM as it is after reset: write the D-cache back,
	 * turn both caches off and drop the I-cache, with no memory access
	 * in between. */
	.globl	tv_rt_reboot
	.type	tv_rt_reboot, @function
tv_rt_reboot:
	li	t0, 6
	csrw	0x7cc, t0	/* mcctlcommand: write back and invalidate L1D */
	li	t0, 3
	csrc	0x7ca, t0
	fence.i
	li	t0, 0x80000000
	jr	t0
	.size	tv_rt_reboot, . - tv_rt_reboot
