; =============================================================================
; disk.asm - Disk I/O driver (BIOS INT 13h)
; 16-bit real mode
; =============================================================================

; BPB fields (populated by fat_init from boot sector)
bpb_spt:        dw 18       ; sectors per track
bpb_heads:      dw 2        ; number of heads
bpb_bps:        dw 512      ; bytes per sector
bpb_spc:        db 1        ; sectors per cluster
bpb_reserved:   dw 1        ; reserved sectors
bpb_fatcnt:     db 2        ; FAT count
bpb_rootent:    dw 224      ; root entries
bpb_totsec:     dw 2880     ; total sectors
bpb_media:      db 0xF0     ; media byte
bpb_spf:        dw 9        ; sectors per FAT
bpb_hiddensec:  dd 0
bpb_volid:      dd 0
bpb_vollbl:     db "KSDOS      "   ; 11 bytes
bpb_fstype:     db "FAT12   "      ; 8 bytes

; Boot drive (set from DL in kernel init)
boot_drive:     db 0x80

; Disk temp vars
_dlba:          dw 0        ; current LBA
_dsect:         db 0        ; CHS sector
_dhead:         db 0        ; CHS head
_dcyl:          db 0        ; CHS cylinder
_dretry:        db 0        ; retry counter

; ============================================================
; disk_read_sector: Read 1 sector at LBA AX into ES:BX
; Returns: CF=0 success, CF=1 error
; ============================================================
disk_read_sector:
    push ax
    push bx
    push cx
    push dx

    mov [_dlba], ax

    ; LBA → CHS
    xor dx, dx
    mov cx, [bpb_spt]
    div cx                  ; AX = LBA/spt, DX = LBA%spt
    inc dx
    mov [_dsect], dl        ; sector (1-based)

    xor dx, dx
    mov cx, [bpb_heads]
    div cx                  ; AX = cyl, DX = head
    mov [_dhead], dl
    mov [_dcyl], al

    ; Build INT 13h call
    ; CH = cylinder, CL = sector | (cyl_hi<<6), DH = head, DL = drive
    mov ch, [_dcyl]
    mov cl, [_dsect]
    mov dh, [_dhead]
    mov dl, [boot_drive]
    mov ax, 0x0201          ; AH=2 (read), AL=1 (sector count)

    mov byte [_dretry], 0
.try:
    int 0x13
    jnc .ok
    ; Reset and retry
    push ax
    push bx
    push cx
    push dx
    xor ax, ax
    mov dl, [boot_drive]
    int 0x13
    pop dx
    pop cx
    pop bx
    pop ax
    inc byte [_dretry]
    cmp byte [_dretry], 3
    jb .try
    ; Fail
    stc
    pop dx
    pop cx
    pop bx
    pop ax
    ret
.ok:
    clc
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; disk_write_sector: Write 1 sector at LBA AX from ES:BX
; Returns: CF=0 success, CF=1 error
; ============================================================
disk_write_sector:
    push ax
    push bx
    push cx
    push dx

    mov [_dlba], ax
    xor dx, dx
    mov cx, [bpb_spt]
    div cx
    inc dx
    mov [_dsect], dl

    xor dx, dx
    mov cx, [bpb_heads]
    div cx
    mov [_dhead], dl
    mov [_dcyl], al

    mov ch, [_dcyl]
    mov cl, [_dsect]
    mov dh, [_dhead]
    mov dl, [boot_drive]
    mov ax, 0x0301          ; AH=3 (write), AL=1

    mov byte [_dretry], 0
.try:
    int 0x13
    jnc .ok
    push ax
    push bx
    push cx
    push dx
    xor ax, ax
    mov dl, [boot_drive]
    int 0x13
    pop dx
    pop cx
    pop bx
    pop ax
    inc byte [_dretry]
    cmp byte [_dretry], 3
    jb .try
    stc
    pop dx
    pop cx
    pop bx
    pop ax
    ret
.ok:
    clc
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; disk_read_multi: Read CX sectors at LBA AX into ES:BX
; ============================================================
disk_read_multi:
    push ax
    push bx
    push cx
    push dx
.loop:
    test cx, cx
    jz .done
    call disk_read_sector
    jc .err
    add bx, 512
    inc ax
    dec cx
    jmp .loop
.err:
    stc
    pop dx
    pop cx
    pop bx
    pop ax
    ret
.done:
    clc
    pop dx
    pop cx
    pop bx
    pop ax
    ret
