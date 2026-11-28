/* SPDX-License-Identifier: GPL-3.0-only
 *
 * The cooperative scheduler's context switch (firmware/rt/pthread.c).
 *
 *   void tv_thread_switch(uint32_t *save, const uint32_t *load);
 *
 * Saves the callee-saved state of the running thread -- ra, sp and s0..s11,
 * fourteen words -- into save, loads another thread's from load and returns
 * into it.  Everything else is caller-saved by the ABI, the A25 is built soft
 * float so there are no FP registers to keep, and gp and tp are the same in
 * every thread.  A new thread's saved ra is tv_thread_start, with its thread
 * record in s0 and its stack's top in sp.
 */
	.section .text.tv_thread_switch, "ax"
	.globl	tv_thread_switch
	.type	tv_thread_switch, @function
tv_thread_switch:
	sw	ra,  0(a0)
	sw	sp,  4(a0)
	sw	s0,  8(a0)
	sw	s1, 12(a0)
	sw	s2, 16(a0)
	sw	s3, 20(a0)
	sw	s4, 24(a0)
	sw	s5, 28(a0)
	sw	s6, 32(a0)
	sw	s7, 36(a0)
	sw	s8, 40(a0)
	sw	s9, 44(a0)
	sw	s10, 48(a0)
	sw	s11, 52(a0)
	lw	ra,  0(a1)
	lw	sp,  4(a1)
	lw	s0,  8(a1)
	lw	s1, 12(a1)
	lw	s2, 16(a1)
	lw	s3, 20(a1)
	lw	s4, 24(a1)
	lw	s5, 28(a1)
	lw	s6, 32(a1)
	lw	s7, 36(a1)
	lw	s8, 40(a1)
	lw	s9, 44(a1)
	lw	s10, 48(a1)
	lw	s11, 52(a1)
	ret
	.size	tv_thread_switch, . - tv_thread_switch

	/* First return into a new thread: its record is in s0. */
	.globl	tv_thread_start
	.type	tv_thread_start, @function
tv_thread_start:
	mv	a0, s0
	call	tv_thread_main		/* never returns */
1:	j	1b
	.size	tv_thread_start, . - tv_thread_start
