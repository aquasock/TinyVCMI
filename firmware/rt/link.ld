/* SPDX-License-Identifier: GPL-3.0-only
 *
 * From TinyNES f0f8501 firmware/rt/link.ld, for the TinyVCMI AE350 system.
 * Runtime programs, loaded into the DDR3 by the boot ROM: code, data, .bss
 * and the heap (from _end to __heap_end) in the DDR3 from 0x40000000 up to
 * the 16 MiB kept for frame buffers at 0x7f000000 (TV_VIDEO_BASE), below the
 * fabric block RAM at 0x7fff0000, which holds the stack (the boot ROM's own
 * data and stack, which a program's start-up overwrites).
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
	ddr3 (rwx)  : ORIGIN = 0x40000000, LENGTH = 1024M - 16M
	ram (rw)    : ORIGIN = 0x7fff0000, LENGTH = 64K
}

SECTIONS
{
	.text : {
		KEEP(*(.text.start))
		KEEP(*(SORT_NONE(.init)))
		KEEP(*(SORT_NONE(.fini)))
		*(.text.unlikely .text.unlikely.*)
		*(.text.startup .text.startup.*)
		*(.text .text.*)
	} > ddr3
	.rodata : { *(.rodata .rodata.*) } > ddr3
	.eh_frame : { KEEP(*(.eh_frame)) } > ddr3
	.gcc_except_table : { *(.gcc_except_table .gcc_except_table.*) } > ddr3
	/* The linker's own; a static link leaves it empty. */
	.rela.dyn : { *(.rela.*) } > ddr3
	ASSERT(SIZEOF(.rela.dyn) == 0, "dynamic relocations")
	.preinit_array : {
		PROVIDE_HIDDEN(__preinit_array_start = .);
		KEEP(*(.preinit_array))
		PROVIDE_HIDDEN(__preinit_array_end = .);
	} > ddr3
	.init_array : {
		PROVIDE_HIDDEN(__init_array_start = .);
		KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
		KEEP(*(.init_array))
		PROVIDE_HIDDEN(__init_array_end = .);
	} > ddr3
	.fini_array : {
		PROVIDE_HIDDEN(__fini_array_start = .);
		KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*)))
		KEEP(*(.fini_array))
		PROVIDE_HIDDEN(__fini_array_end = .);
	} > ddr3
	/* .tm_clone_table: crtbegin and crtend of the threaded GCC carry it
	 * (empty); GNU ld's own scripts keep it in .data. */
	.data : { *(.data .data.*) KEEP(*(.tm_clone_table)) } > ddr3
	.sdata : {
		__global_pointer$ = . + 0x800;
		*(.srodata.cst16) *(.srodata.cst8) *(.srodata.cst4)
		*(.srodata.cst2) *(.srodata .srodata.*)
		*(.sdata .sdata.*)
	} > ddr3
	.sbss : {
		__bss_start = .;
		*(.sbss .sbss.*)
	} > ddr3
	.bss : {
		*(.bss .bss.*) *(COMMON)
		. = ALIGN(4);
		__bss_end = .;
	} > ddr3
	_end = ALIGN(16);
	__heap_end = ORIGIN(ddr3) + LENGTH(ddr3);
	__stack_top = ORIGIN(ram) + LENGTH(ram);

	.comment 0 : { *(.comment) }
	.riscv.attributes 0 : { KEEP(*(.riscv.attributes)) }
	.debug_info 0 : { *(.debug_info .gnu.linkonce.wi.*) }
	.debug_abbrev 0 : { *(.debug_abbrev) }
	.debug_line 0 : { *(.debug_line .debug_line.* .debug_line_end) }
	.debug_line_str 0 : { *(.debug_line_str) }
	.debug_str 0 : { *(.debug_str) }
	.debug_str_offsets 0 : { *(.debug_str_offsets) }
	.debug_addr 0 : { *(.debug_addr) }
	.debug_aranges 0 : { *(.debug_aranges) }
	.debug_rnglists 0 : { *(.debug_rnglists) }
	.debug_loclists 0 : { *(.debug_loclists) }
	.debug_frame 0 : { *(.debug_frame) }
	.debug_ranges 0 : { *(.debug_ranges) }
	.debug_loc 0 : { *(.debug_loc) }
	/DISCARD/ : { *(.note.GNU-stack) *(.gnu_debuglink) }
}
