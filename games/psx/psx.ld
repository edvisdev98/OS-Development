/* PSX linker script - PS1 executable memory layout */
OUTPUT_FORMAT("elf32-littlemips")
OUTPUT_ARCH(mips)
ENTRY(_start)

SECTIONS {
    /* PS1 RAM: user space starts at 0x80010000 */
    . = 0x80010000;

    .text : {
        *(.text.early)
        *(.text)
        *(.text.*)
    }

    .rodata : {
        *(.rodata)
        *(.rodata.*)
    }

    .data : {
        *(.data)
        *(.data.*)
    }

    .bss : {
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        __bss_end = .;
    }

    /* Stack at top of scratch RAM */
    . = 0x801FFF00;
    __stack_top = .;
}
