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
	la	t0, trap_entry
	csrw	mtvec, t0
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

	/* Report the trap and go back to the boot ROM; see tv_rt_trap. */
	.text
	.align	2
trap_entry:
	la	sp, __stack_top
	csrr	a0, mcause
	csrr	a1, mepc
	csrr	a2, mtval
	call	tv_rt_trap
4:	j	4b

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
