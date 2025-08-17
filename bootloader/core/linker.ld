OUTPUT_FORMAT("binary")

SECTIONS {
    . = 0x7F00; /* We expect the main core image to be situated right after core entry */

	.text : {
		*(.entry)
		*(.text)
	}
	
	.bss : {
		*(.bss)
		*(COMMON)
	}
	
	.rodata : {
		*(.rodata)
	}
	
	.data : {
		*(.data)
	}
}
