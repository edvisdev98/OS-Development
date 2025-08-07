    bits 16
    
    section .data
msg_hello: db 'Hello from stage 1.5!', 0x0A, 0x0D, 0
    	
    section .text
    global _start
_start:
    ;; Print a little message to prove that we have
    ;; in fact loaded into the core.
    mov si, msg_hello
    call printr
.L1:
    hlt
    cli
    
    jmp .L1
    
%include "../boot/vgabios.asm"
    
