    org 0x7C00                                                  ; The BIOS loads the 512-byte boot sector at address 0x7C00.
    bits 16                                                     ; In legacy BIOS boot, we always begin in real mode. Meaning
                                                                ; we are limited to 16-bit operands & addresses (not ideal on a >16-bit machine)
    
_start:
    ;; Setup data segments
    mov ax, 0
    mov es, ax
    mov ds, ax
    mov ss, ax
    
    ;; Setup the stack register.
    mov sp, 0x7C00                                              ; The stack grows downwards, which is why we are able to set
                                                                ; the address to the same address as our boot sector.
    
    mov si, msg_hello_world
    call printr
    
    ;; Now we jump to the MBR gap, which contains our core image (stage 1.5).
    ;; Yes, it is hardcoded. This is because we always expect our core to reside
    ;; from the start of the MBR gap and to end at a specific sector. If it doesn't
    ;; that is on the user.
    
    ;; ES (Extra Segment) should be zero as the buffer address is 16-bits, meaning
    ;; no offset is needed, nor should it have any offset.
    mov ax, 0
    mov es, ax
    
    mov ah, 0x02                                                ; Use the BIOS read sectors from disk function for `int 0x13`
    mov al, 10                                                  ; The amount of sectors to read. **FIXME**: make this set during build (1 Sector = 512 bytes)
    mov ch, 0                                                   ; The specific cylinder to read, we shouldn't expect the core image
                                                                ; to reach cylinder 1.. unless it's **REALLY** bloated---which is more of an issue
                                                                ; than making this dynamic.
    mov cl, 2                                                   ; We want to read from sector 2, as the MBR takes up the first initial sector.
                                                                ; Note: Starts from 1, not 0.
    mov bx, buffer                                              ; Set BX (Base Register) to point to the buffer
    int 0x13                                                    ; Read to buffer
    jmp buffer                                                  ; We have successfully loaded the core image, now we jump to it and get out
                                                                ; of this MBR mess.
.L1:
    cli                                                         ; Clear the interrupt flag, meaning we won't expect a maskable
                                                                ; interrupt to continue execution after halt.
    hlt                                                         ; Halt the CPU, meaning it shouldn't continue executing instructions..
    
    jmp .L1                                                     ; Just in case the CPU continues, we don't want
                                                                ; the CPU trying to execute random memory beyond our boot sector.
    
%include "vgabios.asm"
    
msg_hello_world: db '`Hello, World` from boot!', 0x0A, 0x0D, 0
    
    times 510-($-$$) db 0                                       ; Pad the remaining bytes of the boot sector (if any).
                                                                ; we do this because the BIOS expects a 512-byte boot
                                                                ; sector, nothing more and nothing less.
    dw 0xAA55                                                   ; Boot sector magic number - signifies it's bootable.
    
buffer:                                                         ; Points to the address where the core image should be loaded
