; =============================================================================
; KSDOS - FAT12 Boot Sector (512 bytes)
; 16-bit Real Mode
; Loads KSDOS.SYS from FAT12 filesystem into memory at 0x1000:0x0000
; =============================================================================
BITS 16
ORG 0x7C00

; =============================================================================
; FAT12 BIOS Parameter Block (BPB)
; NOTE: Values here must match mkimage.pl and be consistent
; =============================================================================
    jmp short boot_code
    nop

    ; BPB (offset 0x03)
OEM:            db "KSDOS1.0"   ; 0x03  8 bytes
BPS:            dw 512          ; 0x0B  bytes per sector
SPC:            db 1            ; 0x0D  sectors per cluster
RSC:            dw 1            ; 0x0E  reserved sectors
FATCNT:         db 2            ; 0x10  number of FATs
ROOTENT:        dw 224          ; 0x11  root directory entries
TOTSEC:         dw 2880         ; 0x13  total sectors
MEDIA:          db 0xF0         ; 0x15  media descriptor
SPF:            dw 9            ; 0x16  sectors per FAT
SPT:            dw 18           ; 0x18  sectors per track
HEADS:          dw 2            ; 0x1A  number of heads
HIDSEC:         dd 0            ; 0x1C  hidden sectors
TOTSEC32:       dd 0            ; 0x20  total sectors (32-bit)
DRVNUM:         db 0            ; 0x24  drive number
RSVD:           db 0            ; 0x25
BOOTSIG:        db 0x29         ; 0x26
VOLID:          dd 0x4B534453   ; 0x27
VOLLBL:         db "KSDOS      "; 0x2B  11 bytes
FSTYPE:         db "FAT12   "   ; 0x36  8 bytes

; =============================================================================
; Boot code (starts at offset 0x3E)
; =============================================================================
boot_code:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7BFE
    sti

    mov [DRVNUM], dl        ; save boot drive

    ; Print loading message
    mov si, msg_load
    call prints

    ; --- Load FAT1 into 0x7E00 (sector 1, 9 sectors) ---
    mov ax, 1
    mov cx, 9
    mov bx, 0x7E00
    call rd_sectors

    ; --- Load Root Directory into 0xA400 (sector 19, 14 sectors) ---
    ; Root dir start = reserved(1) + fatcount(2)*spf(9) = 19
    mov ax, 19
    mov cx, 14
    mov bx, 0xA400
    call rd_sectors

    ; --- Search root directory for "KSDOS   SYS" ---
    mov di, 0xA400
    mov cx, 224
.search:
    cmp byte [di], 0x00     ; end of directory
    je .notfound
    cmp byte [di], 0xE5     ; deleted entry
    je .next
    test byte [di+11], 0x08 ; volume label attribute?
    jnz .next
    ; Compare 11-byte name
    push cx
    push di
    push si
    mov si, kern11
    mov cx, 11
    repe cmpsb
    pop si
    pop di
    pop cx
    je .found
.next:
    add di, 32
    dec cx
    jnz .search
.notfound:
    mov si, msg_nf
    call prints
    jmp halt

.found:
    ; DI = start of directory entry
    ; Load starting cluster from offset 26
    mov ax, [di+26]
    mov [clus], ax

    ; Set up ES:BX for loading into 0x1000:0x0000
    mov ax, 0x1000
    mov es, ax
    xor bx, bx
    mov [wptr], bx          ; write offset within segment
    mov [wseg], ax          ; write segment

.loadloop:
    mov ax, [clus]
    cmp ax, 0xFF8           ; end of chain?
    jae .loaded

    ; Cluster to LBA: data_start + (cluster - 2) * spc
    ; data_start = 1 + 2*9 + 14 = 33,  spc = 1
    sub ax, 2
    add ax, 33              ; AX = LBA

    ; Read sector into [wseg]:[wptr]
    push es
    push bx
    mov bx, [wseg]
    mov es, bx
    mov bx, [wptr]
    mov cx, 1
    call rd_sectors         ; reads into ES:BX
    pop bx
    pop es

    ; Advance write pointer by 512
    add word [wptr], 512
    jnc .no_seg_adj
    add word [wseg], 0x1000 ; crossed 64KB boundary
.no_seg_adj:

    ; Follow FAT12 chain for current cluster
    mov ax, [clus]
    mov bx, ax
    shr bx, 1
    add bx, ax              ; BX = cluster * 3 / 2
    add bx, 0x7E00          ; FAT buffer start
    mov ax, [bx]            ; read 2 bytes
    test word [clus], 1     ; odd cluster?
    jz .even
    shr ax, 4               ; upper 12 bits
    jmp .store
.even:
    and ax, 0x0FFF          ; lower 12 bits
.store:
    mov [clus], ax
    jmp .loadloop

.loaded:
    ; Jump to kernel
    mov dl, [DRVNUM]
    jmp 0x1000:0x0000

halt:
    cli
    hlt
    jmp halt

; =============================================================================
; rd_sectors: Read CX sectors at LBA AX into ES:BX
;             Trashes DX, DI, SI internally; preserves AX,BX,CX,ES
; =============================================================================
rd_sectors:
    ; Save caller's AX BX CX
    push ax
    push bx
    push cx
    push dx
    push di
    push si

    mov si, 0               ; retry counter (per sector)

.rs_loop:
    test cx, cx
    jz .rs_done

    ; --- LBA to CHS ---
    ; Use DX:AX = 0:AX (LBA is <= 2880 so always fits in AX)
    push ax
    push cx
    push bx

    xor dx, dx
    movzx di, byte [SPT + 1]    ; SPT is a word; load properly
    ; Wait, SPT is 'dw 18' so load it as a word:
    mov di, [SPT]               ; DI = sectors per track = 18
    div di                      ; AX = LBA / spt, DX = LBA mod spt
    inc dx
    mov cl, dl                  ; sector (1-based)

    xor dx, dx
    mov di, [HEADS]             ; number of heads = 2
    div di                      ; AX = cylinder, DX = head
    mov dh, dl                  ; head
    mov ch, al                  ; cylinder low 8 bits
    shl ah, 6
    or cl, ah                   ; cylinder high 2 bits

    pop bx                      ; BX = buffer offset (ES:BX is buffer)
    ; CX still holds CHS (cylinder/sector) — do NOT pop cx before INT 13h

    ; Read 1 sector
    mov ax, 0x0201              ; AH=02 (read), AL=01 (sectors)
    mov dl, [DRVNUM]
    int 0x13

    pop cx                      ; restore sector count
    pop ax                      ; restore LBA

    jc .rs_err

    ; Advance buffer and LBA
    add bx, 512
    inc ax
    dec cx
    mov si, 0                   ; reset retry count
    jmp .rs_loop

.rs_err:
    ; Reset disk controller and retry
    push ax
    push cx
    push bx
    xor ax, ax
    mov dl, [DRVNUM]
    int 0x13
    pop bx
    pop cx
    pop ax
    inc si
    cmp si, 4
    jb .rs_loop
    mov si, msg_err
    call prints
    jmp halt

.rs_done:
    pop si
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; =============================================================================
; prints: Print null-terminated string at DS:SI via INT 10h TTY
; =============================================================================
prints:
    push ax
    push bx
.ps_lp:
    lodsb
    test al, al
    jz .ps_done
    mov ah, 0x0E
    mov bx, 7
    int 0x10
    jmp .ps_lp
.ps_done:
    pop bx
    pop ax
    ret

; =============================================================================
; Data
; =============================================================================
kern11:     db "KSDOS   SYS"   ; 8+3 name as stored in FAT12 directory
clus:       dw 0               ; current cluster being loaded
wptr:       dw 0               ; write pointer (offset)
wseg:       dw 0x1000          ; write segment

msg_load:   db "KSDOS Boot Loader v2.0", 13, 10, 0
msg_nf:     db "KSDOS.SYS not found!", 13, 10, 0
msg_err:    db "Disk read error!", 13, 10, 0

; =============================================================================
; Padding + Boot signature (must be last 2 bytes at offset 510/511)
; =============================================================================
    times 510 - ($ - $$) db 0
    dw 0xAA55
