; =============================================================================
; KSDOS - Master Boot Record (MBR)
; 16-bit Real Mode - Loads active partition boot sector
; Assembled with: nasm -f bin mbr.asm -o mbr.bin
; =============================================================================
BITS 16
ORG 0x7C00

MBR_START:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    ; Relocate MBR from 0x7C00 to 0x0600 so we can load PBR at 0x7C00
    mov cx, 256
    mov si, 0x7C00
    mov di, 0x0600
    rep movsw
    jmp 0x0000:0x0630         ; jump to relocated code

relocated:
    ; Save boot drive
    mov [boot_drive], dl

    ; Find active partition
    mov si, 0x061BE           ; partition table at offset 0x1BE
    mov cx, 4
.search_active:
    test byte [si], 0x80
    jnz .found_active
    add si, 16
    loop .search_active

    ; No active partition found
    mov si, msg_no_boot
    call print_str
    jmp halt

.found_active:
    ; Read LBA start of partition
    mov eax, [si + 8]
    mov [lba_start], eax

    ; Convert LBA to CHS
    call lba_to_chs

    ; Load partition boot record to 0x0000:0x7C00
    mov ax, 0x0201            ; read 1 sector
    mov bx, 0x7C00            ; load to 0x7C00
    int 0x13
    jc .read_error

    ; Verify boot signature
    cmp word [0x7DFE], 0xAA55
    jne .bad_signature

    ; Jump to PBR
    mov dl, [boot_drive]
    jmp 0x0000:0x7C00

.read_error:
    mov si, msg_read_err
    call print_str
    jmp halt

.bad_signature:
    mov si, msg_bad_sig
    call print_str

halt:
    cli
    hlt
    jmp halt

; =============================================================================
; LBA to CHS conversion
; Input:  EAX = LBA address
; Output: CH = cylinder, CL = sector, DH = head, DL = drive
; =============================================================================
lba_to_chs:
    ; Use hardcoded geometry (63 sectors/track, 255 heads - modern CHS)
    push eax
    xor edx, edx
    movzx ebx, word [sectors_per_track]
    div ebx
    inc dl
    mov cl, dl                ; sector (1-based)
    xor edx, edx
    movzx ebx, word [heads]
    div ebx
    mov dh, dl                ; head
    mov ch, al                ; cylinder (low 8 bits)
    shl ah, 6
    or cl, ah                 ; cylinder high bits into CL
    mov dl, [boot_drive]
    pop eax
    ret

; =============================================================================
; Print null-terminated string (DS:SI)
; =============================================================================
print_str:
    push ax bx
.loop:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    mov bx, 7
    int 0x10
    jmp .loop
.done:
    pop bx ax
    ret

; =============================================================================
; Data
; =============================================================================
msg_no_boot     db "No active partition found!", 13, 10, 0
msg_read_err    db "Disk read error!", 13, 10, 0
msg_bad_sig     db "Invalid boot signature!", 13, 10, 0

boot_drive      db 0x80
lba_start       dd 0
sectors_per_track dw 63
heads           dw 255

; =============================================================================
; Partition Table (4 entries x 16 bytes = 64 bytes)
; =============================================================================
    times 0x1BE - ($ - MBR_START) db 0

; Partition 1: Active, FAT12, starts at LBA 63
partition_1:
    db 0x80               ; Status: active/bootable
    db 0x01, 0x01, 0x00   ; CHS first sector
    db 0x01               ; Partition type: FAT12
    db 0x01, 0x12, 0x00   ; CHS last sector
    dd 63                 ; LBA start
    dd 2817               ; LBA size (1.44MB - 63)

; Partitions 2-4: empty
    times 48 db 0

; Boot signature
    dw 0xAA55
