/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Trap-safe CSR probing for firmware/apps/pma_probe.
 *
 * The A25 implements a large machine-custom CSR window and not all of it is
 * present in this hard macro: a read of an unimplemented CSR raises an
 * illegal-instruction trap. To find out what exists without taking the core
 * down, main() points mtvec here first, and this handler skips the faulting
 * instruction and sets probe_fault so the caller knows the read failed.
 *
 * Only an illegal instruction is skipped. Any other trap is a real fault and
 * goes to tv_rt_trap_entry as the runtime normally does.
 */
	.section .text
	.globl	probe_handler_install
	.type	probe_handler_install, @function
	/* Direct mode, so mtvec holds the address alone. */
probe_handler_install:
	la	t0, probe_handler
	csrw	mtvec, t0
	ret
	.size	probe_handler_install, . - probe_handler_install

	.align	2
	.globl	probe_handler
	.type	probe_handler, @function
probe_handler:
	addi	sp, sp, -16
	sw	t0, 0(sp)
	sw	t1, 4(sp)
	sw	t2, 8(sp)

	csrr	t0, mcause
	li	t1, 2			/* illegal instruction */
	bne	t0, t1, 1f

	/* Step over the CSR instruction: 4 bytes, or 2 if it was compressed. */
	csrr	t0, mepc
	lhu	t1, 0(t0)
	andi	t1, t1, 3
	li	t2, 3
	beq	t1, t2, 2f
	addi	t0, t0, 2
	j	3f
2:	addi	t0, t0, 4
3:	csrw	mepc, t0
	la	t0, probe_fault
	li	t1, 1
	sw	t1, 0(t0)

	lw	t0, 0(sp)
	lw	t1, 4(sp)
	lw	t2, 8(sp)
	addi	sp, sp, 16
	mret

1:	/* Anything else is not this probe's business: report it as usual. */
	lw	t0, 0(sp)
	lw	t1, 4(sp)
	lw	t2, 8(sp)
	addi	sp, sp, 16
	j	tv_rt_trap_entry
	.size	probe_handler, . - probe_handler
