[org 0x7C00]          ; BIOS loads bootloader to memory at 0x7C00

start:
    mov si, msg        ; Point SI to the message string

.loop:
    lodsb              ; Load next byte from [SI] into AL, advance SI
    or al, al          ; Check if it's 0 (end of string)
    jz .halt           ; If yes, stop printing
    mov ah, 0x0E       ; Set BIOS teletype function
    int 0x10           ; Print AL to screen
    jmp .loop          ; Repeat for next character

.halt:
    cli                ; Disable interrupts
    hlt                ; Halt the CPU

msg db 'Hello World!', 0      ; Message to print, ending with 0 (null)

times 510-($-$$) db 0  ; Fill rest of sector with 0s (510 bytes total)
dw 0xAA55              ; Boot signature (must be last 2 bytes)
