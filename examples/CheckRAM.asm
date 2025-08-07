[BITS 16]
[ORG 0x7C00]

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    sti

    int 0x12

    mov bx, ax
    call print_num

    mov si, msg_ram
    call print_string

hang:
    jmp hang

print_string:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    mov bh, 0
    mov bl, 7
    int 0x10
    jmp print_string
.done:
    ret

print_num:
    push ax
    push bx
    push cx
    push dx

    mov cx, 0
    mov ax, bx
    mov dx, 0

    mov si, numbuf + 5

print_num_loop:
    xor dx, dx
    mov bx, 10
    div bx
    dec si
    add dl, '0'
    mov [si], dl
    inc cx
    test ax, ax
    jnz print_num_loop

print_num_print:
    mov ah, 0x0E
    mov bh, 0
    mov bl, 7
.print_loop:
    lodsb
    int 0x10
    loop .print_loop

    pop dx
    pop cx
    pop bx
    pop ax
    ret

msg_ram db " KB OK",0

numbuf db '00000'

times 510-($-$$) db 0
dw 0xAA55
