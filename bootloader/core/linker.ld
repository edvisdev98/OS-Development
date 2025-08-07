/* Set the entry point to the `_start` symbol */
ENTRY(_start)

SECTIONS {
    . = 0x7E00; /* We expect the core image to be loaded right after MBR */

	.text : {
		*(.text)
	}

	.rodata : {
		*(.rodata)
	}
	

	.data : {
		*(.data)
	}

	.bss : {
		*(.bss)
		*(COMMON)
	}
}
	
