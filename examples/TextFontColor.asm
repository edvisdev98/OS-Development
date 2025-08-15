[BITS 16]
[ORG 0x7C00]

start:
    cli

    mov ah, 0x00
    mov al, 0x03
    int 0x10

    mov ax, 0xB800
    mov es, ax
    xor di, di

    mov cx, 2000

    mov ah, 0x0E
    mov al, ' '

.clear_loop:
    stosw
    loop .clear_loop

    mov ah, 0x02
    mov bh, 0x00
    mov dh, 0x00
    mov dl, 0x00
    int 0x10

hang:
    jmp hang

times 510 - ($ - $$) db 0
dw 0xAA55
