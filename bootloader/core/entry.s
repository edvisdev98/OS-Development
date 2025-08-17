.section .bss
stack_bottom:
	.skip 1024
stack_top:

.section .entry
_entry:
    /* Setup the stack */
    movl stack_top, %eax
    movl %eax, %esp

    /* Run the core officially */
    call core_main
.L1:
    cli
    hlt
    jmp .L1
