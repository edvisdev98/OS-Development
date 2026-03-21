; =============================================================================
; fat12.asm - FAT12 Filesystem Driver
; 16-bit real mode
; =============================================================================

; Computed at init
fat_lba:        dw 0        ; LBA of FAT1
root_lba:       dw 0        ; LBA of root directory
data_lba:       dw 0        ; LBA of data area
root_secs:      dw 0        ; sectors in root dir

; Buffer addresses (absolute offsets within the 0x1000 segment)
FAT_BUF         equ 0xC000  ; 4608 bytes (9 sectors)
DIR_BUF         equ 0xD200  ; 7168 bytes (14 sectors root dir)
FILE_BUF        equ 0xF000  ; 3072 bytes (read chunk)

; ============================================================
; fat_init: read BPB from sector 0, load FAT, compute offsets
; ============================================================
fat_init:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    ; Read boot sector into FILE_BUF
    mov ax, ds
    mov es, ax
    mov bx, FILE_BUF
    mov ax, 0
    call disk_read_sector
    jc .err

    ; Copy BPB fields from boot sector
    ; BPB starts at offset 0x0B in the sector
    mov si, FILE_BUF + 0x0B
    ; bytes per sector (word) @ 0x0B
    mov ax, [si]
    mov [bpb_bps], ax
    ; sectors per cluster (byte) @ 0x0D
    mov al, [si+2]
    mov [bpb_spc], al
    ; reserved sectors (word) @ 0x0E
    mov ax, [si+3]
    mov [bpb_reserved], ax
    ; FAT count (byte) @ 0x10
    mov al, [si+5]
    mov [bpb_fatcnt], al
    ; root entries (word) @ 0x11
    mov ax, [si+6]
    mov [bpb_rootent], ax
    ; total sectors (word) @ 0x13
    mov ax, [si+8]
    mov [bpb_totsec], ax
    ; media (byte) @ 0x15
    mov al, [si+10]
    mov [bpb_media], al
    ; sectors per FAT (word) @ 0x16
    mov ax, [si+11]
    mov [bpb_spf], ax
    ; sectors per track (word) @ 0x18
    mov ax, [si+13]
    mov [bpb_spt], ax
    ; heads (word) @ 0x1A
    mov ax, [si+15]
    mov [bpb_heads], ax
    ; hidden sectors (dword) @ 0x1C
    mov ax, [si+17]
    mov [bpb_hiddensec], ax
    mov ax, [si+19]
    mov [bpb_hiddensec+2], ax
    ; volume ID @ 0x27
    mov si, FILE_BUF + 0x27
    mov ax, [si]
    mov [bpb_volid], ax
    mov ax, [si+2]
    mov [bpb_volid+2], ax
    ; volume label 11 bytes @ 0x2B
    mov si, FILE_BUF + 0x2B
    mov di, bpb_vollbl
    mov cx, 11
    rep movsb
    ; FS type 8 bytes @ 0x36
    mov cx, 8
    rep movsb

    ; Compute LBA positions
    ; FAT1 start = reserved
    mov ax, [bpb_reserved]
    mov [fat_lba], ax

    ; root dir start = reserved + fatcnt * spf
    movzx ax, byte [bpb_fatcnt]
    mul word [bpb_spf]
    add ax, [bpb_reserved]
    mov [root_lba], ax

    ; root dir sectors = ceil(rootent * 32 / bps)
    mov ax, [bpb_rootent]
    mov cx, 32
    mul cx                  ; DX:AX = rootent * 32
    mov cx, [bpb_bps]
    div cx                  ; AX = sectors (DX = remainder)
    test dx, dx
    jz .no_rnd
    inc ax
.no_rnd:
    mov [root_secs], ax

    ; data start = root_lba + root_secs
    add ax, [root_lba]
    mov [data_lba], ax

    ; Load FAT1 into FAT_BUF
    mov ax, ds
    mov es, ax
    mov bx, FAT_BUF
    mov ax, [fat_lba]
    mov cx, [bpb_spf]
    call disk_read_multi

.err:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; fat_load_root: load root directory into DIR_BUF
; ============================================================
fat_load_root:
    push ax
    push bx
    push cx
    push es
    mov ax, ds
    mov es, ax
    mov bx, DIR_BUF
    mov ax, [root_lba]
    mov cx, [root_secs]
    call disk_read_multi
    pop es
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; fat_save_root: write root directory from DIR_BUF back to disk
; ============================================================
fat_save_root:
    push ax
    push bx
    push cx
    push es
    mov ax, ds
    mov es, ax
    mov bx, DIR_BUF
    mov ax, [root_lba]
    mov cx, [root_secs]
.wloop:
    test cx, cx
    jz .done
    call disk_write_sector
    add bx, 512
    inc ax
    dec cx
    jmp .wloop
.done:
    pop es
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; fat_find: find 11-byte name DS:SI in current directory
; Output: DI = DIR_BUF offset of entry, or 0xFFFF if not found
;         CF=0 found, CF=1 not found
; ============================================================
fat_find:
    push cx
    push si
    push dx

    call fat_load_dir

    mov di, DIR_BUF
    call fat_max_entries    ; CX = entry count for current dir
    mov dx, si              ; save original SI

.loop:
    test cx, cx
    jz .nf
    cmp byte [di], 0x00     ; end of dir
    je .nf
    cmp byte [di], 0xE5     ; deleted
    je .skip
    test byte [di+11], 0x08 ; volume label
    jnz .skip

    ; Compare name
    push cx
    push di
    push si
    mov si, dx
    mov cx, 11
    repe cmpsb
    pop si
    pop di
    pop cx
    je .found

.skip:
    add di, 32
    dec cx
    jmp .loop

.nf:
    mov di, 0xFFFF
    pop dx
    pop si
    pop cx
    stc
    ret

.found:
    pop dx
    pop si
    pop cx
    clc
    ret

; ============================================================
; fat_next_cluster: get next cluster in chain
; Input:  AX = current cluster
; Output: AX = next cluster (0xFFF8+ = end of chain)
; ============================================================
fat_next_cluster:
    push bx
    push cx
    mov bx, ax
    shr bx, 1
    add bx, ax              ; BX = cluster * 3 / 2
    add bx, FAT_BUF
    mov cx, [bx]
    test ax, 1
    jz .even
    shr cx, 4
    jmp .done
.even:
    and cx, 0x0FFF
.done:
    mov ax, cx
    pop cx
    pop bx
    ret

; ============================================================
; cluster_to_lba: convert cluster AX to LBA AX
; ============================================================
cluster_to_lba:
    push bx
    sub ax, 2
    movzx bx, byte [bpb_spc]
    mul bx
    add ax, [data_lba]
    pop bx
    ret

; ============================================================
; fat_read_file: read entire file into DS:DI
; Input:  AX = starting cluster, DS:DI = destination buffer
; Output: CX = bytes read (approximate, in full 512-byte blocks)
; ============================================================
fat_read_file:
    push ax
    push bx
    push dx
    push si
    push di
    push es

    mov bx, ds
    mov es, bx
    mov bx, di              ; ES:BX = destination
    xor cx, cx              ; byte count (in sectors)

.loop:
    cmp ax, 0xFF8
    jae .done
    cmp ax, 2
    jb .done

    ; Read one cluster
    push ax
    call cluster_to_lba
    push cx
    call disk_read_sector
    pop cx
    pop ax
    jc .done

    add bx, 512
    inc cx

    call fat_next_cluster
    jmp .loop

.done:
    ; CX = sectors read; multiply by 512 for bytes? (already sectors)
    pop es
    pop di
    pop si
    pop dx
    pop bx
    pop ax
    ret

; ============================================================
; fat_delete: delete file with 11-byte name DS:SI
; Returns: CF=0 ok, CF=1 not found
; ============================================================
fat_delete:
    push di
    push ax
    call fat_find
    jc .nf
    ; Mark as deleted
    mov byte [di], 0xE5
    ; Write directory back
    call fat_save_dir
    clc
    pop ax
    pop di
    ret
.nf:
    stc
    pop ax
    pop di
    ret

; ============================================================
; cur_dir_cluster: 0 = root directory, nonzero = subdir cluster
; ============================================================
cur_dir_cluster: dw 0

; ============================================================
; fat_max_entries: returns CX = max entries in current directory
; ============================================================
fat_max_entries:
    cmp word [cur_dir_cluster], 0
    je .root
    mov cx, 16
    ret
.root:
    mov cx, [bpb_rootent]
    ret

; ============================================================
; fat_load_dir: load current directory into DIR_BUF
; ============================================================
fat_load_dir:
    cmp word [cur_dir_cluster], 0
    je fat_load_root
    push ax
    push bx
    push es
    mov ax, [cur_dir_cluster]
    call cluster_to_lba
    push ds
    pop es
    mov bx, DIR_BUF
    call disk_read_sector
    pop es
    pop bx
    pop ax
    ret

; ============================================================
; fat_save_dir: write DIR_BUF back to current directory
; ============================================================
fat_save_dir:
    cmp word [cur_dir_cluster], 0
    je fat_save_root
    push ax
    push bx
    push es
    mov ax, [cur_dir_cluster]
    call cluster_to_lba
    push ds
    pop es
    mov bx, DIR_BUF
    call disk_write_sector
    pop es
    pop bx
    pop ax
    ret

; ============================================================
; fat_find_free_slot: find first free (0x00 or 0xE5) entry in DIR_BUF
; Output: DI = address of free entry, 0xFFFF if none
; ============================================================
fat_find_free_slot:
    push cx
    call fat_max_entries
    mov di, DIR_BUF
.loop:
    test cx, cx
    jz .none
    cmp byte [di], 0x00
    je .found
    cmp byte [di], 0xE5
    je .found
    add di, 32
    dec cx
    jmp .loop
.none:
    mov di, 0xFFFF
.found:
    pop cx
    ret

; ============================================================
; fat_alloc_cluster: find a free cluster (FAT12 entry = 0x000)
; Output: AX = cluster number, 0xFFFF if disk full
; ============================================================
fat_alloc_cluster:
    push bx
    push cx
    mov bx, 2
.loop:
    cmp bx, [bpb_totsec]
    jge .full
    mov ax, bx
    call fat_next_cluster
    test ax, ax
    jz .found
    inc bx
    jmp .loop
.found:
    mov ax, bx
    pop cx
    pop bx
    ret
.full:
    mov ax, 0xFFFF
    pop cx
    pop bx
    ret

; ============================================================
; fat_set_entry: set FAT12 entry for cluster AX to value BX
; ============================================================
_fse_clus: dw 0
fat_set_entry:
    push si
    push cx
    push dx
    push ax
    mov [_fse_clus], ax
    mov cx, 3
    mul cx                  ; AX = cluster * 3
    shr ax, 1               ; AX = cluster * 3 / 2 (byte offset)
    mov si, ax
    add si, FAT_BUF
    pop ax                  ; restore cluster (for odd/even test)
    test ax, 1
    jz .even
    ; odd cluster: upper 12 bits
    mov cx, [si]
    and cx, 0x000F
    mov dx, bx
    shl dx, 4
    or cx, dx
    mov [si], cx
    jmp .fse_done
.even:
    ; even cluster: lower 12 bits
    mov cx, [si]
    and cx, 0xF000
    and bx, 0x0FFF
    or cx, bx
    mov [si], cx
.fse_done:
    pop dx
    pop cx
    pop si
    ret

; ============================================================
; fat_save_fat: write FAT1 and FAT2 back to disk
; ============================================================
fat_save_fat:
    push ax
    push bx
    push cx
    push es
    mov ax, ds
    mov es, ax
    ; Write FAT1
    mov bx, FAT_BUF
    mov ax, [fat_lba]
    mov cx, [bpb_spf]
.wf1:
    test cx, cx
    jz .wf2start
    call disk_write_sector
    add bx, 512
    inc ax
    dec cx
    jmp .wf1
.wf2start:
    ; Write FAT2
    mov bx, FAT_BUF
    mov ax, [fat_lba]
    add ax, [bpb_spf]
    mov cx, [bpb_spf]
.wf2:
    test cx, cx
    jz .wsf_done
    call disk_write_sector
    add bx, 512
    inc ax
    dec cx
    jmp .wf2
.wsf_done:
    pop es
    pop cx
    pop bx
    pop ax
    ret
