[BITS 16]
[ORG 0x7C00]

start:
    xor ax, ax
    mov ds, ax

    mov ax, 0x0600
    mov bh, 0x07
    mov cx, 0x0000
    mov dx, 0x184F
    int 0x10

    mov ah, 0x02
    mov bh, 0x00
    mov dh, 0x00
    mov dl, 0x00
    int 0x10

hang:
    jmp hang

times 510 - ($ - $$) db 0
dw 0xAA55
