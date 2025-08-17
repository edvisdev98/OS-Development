OUTPUT_FORMAT("binary") /*
						The MBR partition is way too small to fit an ELF
						loader, so instead the MBR gap will just contain raw bytes
						*/

SECTIONS {
	/*
	CORE FORMAT:
	- setup: 0x7E00, size: 256 bytes
	- start: 0x7F00, size: ..
	*/
    . = 0x7F00;

	/* Where out code sits */
	.text : {
		*(.text.early) /* Mostly to make sure the entry is always at the start */
		*(.text)
	}

	/* Uninitialized data, e.g. STACK */
	.bss : {
		*(.bss)
		*(COMMON)
	}

	/* Read-only data */
	.rodata : {
		*(.rodata)
	}

	/* Read/write data */
	.data : {
		*(.data)
	}
}
