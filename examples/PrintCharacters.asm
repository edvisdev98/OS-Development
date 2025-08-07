[org 0x7C00]

start:
    mov cl, 'A'
.print_upper:
    mov ah, 0x0E
    mov al, cl
    int 0x10
    inc cl
    cmp cl, 'Z'+1 
    jb .print_upper

    mov cl, 'a'
.print_lower:
    mov ah, 0x0E
    mov al, cl
    int 0x10
    inc cl
    cmp cl, 'z'+1
    jb .print_lower

    mov cl, '0'
.print_digits:
    mov ah, 0x0E
    mov al, cl
    int 0x10
    inc cl
    cmp cl, '9'+1
    jb .print_digits

.halt:
    cli
    hlt

times 510 - ($ - $$) db 0
dw 0xAA55
