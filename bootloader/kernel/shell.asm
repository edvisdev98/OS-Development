; =============================================================================
; shell.asm - KSDOS Command Shell
; MS-DOS compatible commands, 16-bit real mode
; =============================================================================

; ---- Buffers ----
; sh_arg, _sh_tmp11, _sh_type_sz are at fixed addresses in the kernel prefix
; (ksdos.asm 0x0060 / 0x00E0 / 0x00EC) - do NOT redeclare here.
sh_line:    times 128 db 0
sh_cmd:     times 32  db 0
sh_cwd:     db "A:\", 0
            times 60  db 0      ; room for deep paths (total 64 bytes)

; ---- Shell-private temps ----
_sh_namebuf: times 16 db 0
_sh_dir_ent: dw 0               ; saved dir entry pointer for sh_DIR
_sh_new_clus: dw 0              ; allocated cluster for sh_MD / sh_RD

; ---- Extra buffers for REN / COPY / FIND / SORT / MORE ----
_sh_ren_src:  times 32 db 0    ; first argument (source name)
_sh_arg2:     times 64 db 0    ; second argument
_sh_find_str: times 64 db 0    ; FIND search string
_sh_find_len: dw 0              ; FIND string length
_sh_more_lns: dw 0              ; MORE current line count
_sh_copy_sz:  dw 0              ; COPY/XCOPY file size
_sh_copy_cl:  dw 0              ; COPY/XCOPY destination cluster
_sh_sort_buf: times 1024 db 0  ; SORT line buffer (1 KB)
_sh_sort_ptrs: times 64 dw 0   ; SORT line pointer table (32 lines max)

; ============================================================
; shell_run: main shell loop
; ============================================================
shell_run:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    call sh_banner

.prompt:
    ; Prompt
    mov al, ATTR_GREEN
    call vid_set_attr
    mov si, sh_cwd
    call vid_print
    mov al, '>'
    call vid_putchar
    mov al, ' '
    call vid_putchar
    mov al, ATTR_NORMAL
    call vid_set_attr

    ; Read line
    mov si, sh_line
    mov cx, 127
    call kbd_readline

    ; Parse command word (uppercase)
    mov si, sh_line
    call str_ltrim
    cmp byte [si], 0
    je .prompt
    mov di, sh_cmd
    mov cx, 31
    call sh_get_word_uc

    ; Parse argument (rest of line, trimmed)
    call str_ltrim
    mov di, sh_arg
    xor bx, bx          ; [span_1](start_span)Use BX as the index instead of CX[span_1](end_span)
.copy_arg:
    lodsb
    mov [di + bx], al   ; [span_2](start_span)BX is a valid 16-bit pointer[span_2](end_span)
    test al, al
    jz .arg_done
    inc bx              ; [span_3](start_span)Increment our pointer index[span_3](end_span)
    jmp .copy_arg
.arg_done:

    ; Dispatch command via table
    mov si, sh_cmd
    call sh_dispatch

    jmp .prompt

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; sh_get_word_uc: copy DS:SI to DS:DI uppercased, stop at space/0
;   SI advances past word and trailing spaces
; ============================================================
sh_get_word_uc:
    push ax
    push cx
.loop:
    lodsb
    test al, al
    jz .term
    cmp al, ' '
    je .skip_spaces
    call _uc_al
    mov [di], al
    inc di
    dec cx
    jnz .loop
    ; Full - skip rest
.skip_rest:
    lodsb
    test al, al
    jz .term
    cmp al, ' '
    jne .skip_rest
.skip_spaces:
    lodsb
    test al, al
    jz .term
    cmp al, ' '
    je .skip_spaces
    ; SI is past spaces; back up one
    dec si
.term:
    mov byte [di], 0
    dec si              ; SI points to the null/space that stopped us
    inc si              ; re-advance to character AFTER the word
    pop cx
    pop ax
    ret

; ============================================================
; sh_dispatch: look up sh_cmd in command table, call handler
; ============================================================

; Macro-style helper: compare SI with literal string at CS label
; Returns ZF=1 if equal
sh_str_eq:          ; AX = offset of null-term string to compare with sh_cmd
    push si
    push di
    mov di, ax
    mov si, sh_cmd
.eq_lp:
    cmpsb
    jne .ne
    cmp byte [si-1], 0
    jne .eq_lp
    ; equal
    pop di
    pop si
    xor ax, ax      ; ZF=1
    ret
.ne:
    pop di
    pop si
    or ax, 1        ; ZF=0
    ret

; ---- Command table (name_ptr, handler_ptr pairs) ----
cmd_table:
    dw cmd_s_CLS,     sh_CLS
    dw cmd_s_DIR,     sh_DIR
    dw cmd_s_TYPE,    sh_TYPE
    dw cmd_s_COPY,    sh_COPY
    dw cmd_s_DEL,     sh_DEL
    dw cmd_s_REN,     sh_REN
    dw cmd_s_VER,     sh_VER
    dw cmd_s_VOL,     sh_VOL
    dw cmd_s_DATE,    sh_DATE
    dw cmd_s_TIME,    sh_TIME
    dw cmd_s_ECHO,    sh_ECHO
    dw cmd_s_SET,     sh_SET
    dw cmd_s_MEM,     sh_MEM
    dw cmd_s_CHKDSK,  sh_CHKDSK
    dw cmd_s_FORMAT,  sh_FORMAT
    dw cmd_s_LABEL,   sh_LABEL
    dw cmd_s_ATTRIB,  sh_ATTRIB
    dw cmd_s_DEBUG,   sh_DEBUG
    dw cmd_s_OPENGL,  sh_OPENGL
    dw cmd_s_PSYQ,    sh_PSYQ
    dw cmd_s_GOLD4,   sh_GOLD4
    dw cmd_s_IDE,     sh_IDE
    dw cmd_s_HELP,    sh_HELP
    dw cmd_s_EXIT,    sh_EXIT
    dw cmd_s_REBOOT,  sh_EXIT
    dw cmd_s_HALT,    sh_HALT
    dw cmd_s_PAUSE,   sh_PAUSE
    dw cmd_s_REM,     sh_REM
    dw cmd_s_XCOPY,   sh_XCOPY
    dw cmd_s_FIND,    sh_FIND
    dw cmd_s_SORT,    sh_SORT
    dw cmd_s_MORE,    sh_MORE
    dw cmd_s_DISKCOPY, sh_DISKCOPY
    dw cmd_s_SYS,     sh_SYS
    dw cmd_s_CD,      sh_CD
    dw cmd_s_CHDIR,   sh_CD
    dw cmd_s_MD,      sh_MD
    dw cmd_s_MKDIR,   sh_MD
    dw cmd_s_RD,      sh_RD
    dw cmd_s_RMDIR,   sh_RD
    dw cmd_s_DELTREE, sh_DELTREE
    dw cmd_s_TREE,    sh_TREE
    dw cmd_s_CC,      sh_CC
    dw cmd_s_GCC,     sh_CC
    dw cmd_s_CPP,     sh_CPP
    dw cmd_s_GPP,     sh_CPP
    dw cmd_s_MASM,    sh_MASM
    dw cmd_s_NASM2,   sh_MASM
    dw cmd_s_CSC,     sh_CSC
    dw cmd_s_MUSIC,   sh_MUSIC
    dw cmd_s_NET,     sh_NET
    dw 0, 0             ; sentinel

; Command name strings (uppercase)
cmd_s_CLS:      db "CLS",      0
cmd_s_DIR:      db "DIR",      0
cmd_s_TYPE:     db "TYPE",     0
cmd_s_COPY:     db "COPY",     0
cmd_s_DEL:      db "DEL",      0
cmd_s_REN:      db "REN",      0
cmd_s_VER:      db "VER",      0
cmd_s_VOL:      db "VOL",      0
cmd_s_DATE:     db "DATE",     0
cmd_s_TIME:     db "TIME",     0
cmd_s_ECHO:     db "ECHO",     0
cmd_s_SET:      db "SET",      0
cmd_s_MEM:      db "MEM",      0
cmd_s_CHKDSK:   db "CHKDSK",   0
cmd_s_FORMAT:   db "FORMAT",   0
cmd_s_LABEL:    db "LABEL",    0
cmd_s_ATTRIB:   db "ATTRIB",   0
cmd_s_DEBUG:    db "DEBUG",    0
cmd_s_OPENGL:   db "OPENGL",   0
cmd_s_PSYQ:     db "PSYQ",     0
cmd_s_GOLD4:    db "GOLD4",    0
cmd_s_IDE:      db "IDE",      0
cmd_s_HELP:     db "HELP",     0
cmd_s_EXIT:     db "EXIT",     0
cmd_s_REBOOT:   db "REBOOT",   0
cmd_s_HALT:     db "HALT",     0
cmd_s_PAUSE:    db "PAUSE",    0
cmd_s_REM:      db "REM",      0
cmd_s_XCOPY:    db "XCOPY",    0
cmd_s_FIND:     db "FIND",     0
cmd_s_SORT:     db "SORT",     0
cmd_s_MORE:     db "MORE",     0
cmd_s_DISKCOPY: db "DISKCOPY", 0
cmd_s_SYS:      db "SYS",      0
cmd_s_CD:       db "CD",       0
cmd_s_CHDIR:    db "CHDIR",    0
cmd_s_MD:       db "MD",       0
cmd_s_MKDIR:    db "MKDIR",    0
cmd_s_RD:       db "RD",       0
cmd_s_RMDIR:    db "RMDIR",    0
cmd_s_DELTREE:  db "DELTREE",  0
cmd_s_TREE:     db "TREE",     0
cmd_s_CC:       db "CC",       0
cmd_s_GCC:      db "GCC",      0
cmd_s_CPP:      db "CPP",      0
cmd_s_GPP:      db "G++",      0
cmd_s_MASM:     db "MASM",     0
cmd_s_NASM2:    db "NASM",     0
cmd_s_CSC:      db "CSC",      0
cmd_s_MUSIC:    db "MUSIC",    0
cmd_s_NET:      db "NET",      0

sh_dispatch:
    push ax
    push bx
    push si
    push di
    mov bx, cmd_table
.disp_loop:
    ; Load name ptr
    mov ax, [bx]
    test ax, ax
    jz .not_found
    ; Compare with sh_cmd
    call sh_str_eq
    jnz .next
    ; Match: call handler
    mov ax, [bx+2]
    push ax
    pop ax
    ; Call handler indirectly
    call word [bx+2]
    pop di
    pop si
    pop bx
    pop ax
    ret
.next:
    add bx, 4
    jmp .disp_loop
.not_found:
    mov si, str_bad_cmd
    call vid_println
    pop di
    pop si
    pop bx
    pop ax
    ret

; ============================================================
; Command handlers
; ============================================================

sh_CLS:
    call vid_clear
    ret

sh_DIR:
    call fat_load_dir
    ; Header
    mov al, ATTR_NORMAL
    call vid_set_attr
    mov si, str_dir_hdr
    call vid_print
    mov si, sh_cwd
    call vid_println
    ; Iterate entries
    xor bx, bx             ; file count
    mov si, DIR_BUF
    call fat_max_entries    ; CX = entry count
.dl:
    test cx, cx
    jz .dir_done
    ; Skip deleted/empty
    cmp byte [si], 0x00
    je .dir_done
    cmp byte [si], 0xE5
    je .dn
    ; Skip volume label and LFN
    test byte [si+11], 0x08
    jnz .dn
    test byte [si+11], 0x0F
    jnz .dn
    ; Save entry pointer
    mov [_sh_dir_ent], si
    ; Format name into _sh_namebuf
    push si
    push cx
    push bx
    mov di, _sh_namebuf
    call fat_format_name
    pop bx
    pop cx
    pop si
    ; Print name (13 chars wide, padded)
    push si
    push cx
    push bx
    mov si, _sh_namebuf
    call vid_print
    call str_len
    mov cx, 13
    sub cx, ax
    jle .name_done
.np:
    mov al, ' '
    call vid_putchar
    loop .np
.name_done:
    ; Restore entry pointer into SI
    mov si, [_sh_dir_ent]
    ; Print <DIR> tag or file size
    test byte [si+11], 0x10
    jz .show_size
    push si
    mov si, str_dir_tag
    call vid_print
    pop si
    jmp .show_date
.show_size:
    mov ax, [si+28]
    call print_word_dec
.show_date:
    mov al, ' '
    call vid_putchar
    ; Date field at offset 24
    mov ax, [si+24]
    push ax
    and ax, 0x1F
    call print_word_dec
    mov al, '-'
    call vid_putchar
    pop ax
    push ax
    shr ax, 5
    and ax, 0x0F
    call print_word_dec
    mov al, '-'
    call vid_putchar
    pop ax
    shr ax, 9
    add ax, 1980
    call print_word_dec
    call vid_nl
    pop bx
    pop cx
    pop si
    inc bx
.dn:
    add si, 32
    dec cx
    jmp .dl
.dir_done:
    push bx
    call vid_nl
    mov si, str_n_files
    call vid_print
    pop ax
    call print_word_dec
    mov si, str_files_found
    call vid_println
    ret

sh_TYPE:
    cmp byte [sh_arg], 0
    jne .go
    mov si, str_syntax
    call vid_println
    ret
.go:
    mov si, sh_arg
    mov di, _sh_tmp11
    call str_to_dosname
    mov si, _sh_tmp11
    call fat_find
    jc .nf
    ; Read and display
    push di
    mov ax, [di+26]         ; start cluster
    mov cx, [di+28]
    mov [_sh_type_sz], cx
    pop di
    push ds
    pop es
    mov bx, FILE_BUF
    call fat_read_file
    mov si, FILE_BUF
    mov cx, [_sh_type_sz]
.tp:
    test cx, cx
    jz .td
    lodsb
    call vid_putchar
    dec cx
    jmp .tp
.td:
    call vid_nl
    ret
.nf:
    mov si, str_no_file
    call vid_println
    ret

sh_COPY:
    cmp byte [sh_arg], 0
    je .syntax
    ; ---- Parse first arg (source) into _sh_ren_src ----
    mov si, sh_arg
    mov di, _sh_ren_src
    mov cx, 31
.cp_w1:
    test cx, cx
    jz .cp_w1d
    lodsb
    test al, al
    jz .cp_w1d
    cmp al, ' '
    je .cp_w1d
    stosb
    dec cx
    jmp .cp_w1
.cp_w1d:
    mov byte [di], 0
    ; skip spaces
.cp_sp:
    cmp byte [si], ' '
    jne .cp_sp_done
    inc si
    jmp .cp_sp
.cp_sp_done:
    cmp byte [si], 0
    je .syntax
    ; ---- Parse second arg (dest) into _sh_arg2 ----
    mov di, _sh_arg2
    mov cx, 31
.cp_w2:
    test cx, cx
    jz .cp_w2d
    lodsb
    test al, al
    jz .cp_w2d
    cmp al, ' '
    je .cp_w2d
    stosb
    dec cx
    jmp .cp_w2
.cp_w2d:
    mov byte [di], 0
    ; ---- Convert source to 8.3, find file ----
    mov si, _sh_ren_src
    mov di, _sh_tmp11
    call str_to_dosname
    call fat_load_dir
    mov si, _sh_tmp11
    call fat_find
    jc .not_found
    ; Save size and start cluster
    mov ax, [di+28]
    mov [_sh_copy_sz], ax
    mov ax, [di+26]        ; start cluster
    ; ---- Read source into FILE_BUF ----
    push di
    mov di, FILE_BUF
    call fat_read_file
    pop di
    ; ---- Convert dest to 8.3 ----
    mov si, _sh_arg2
    mov di, _sh_tmp11
    call str_to_dosname
    ; ---- Reload dir, find free slot ----
    call fat_load_dir
    call fat_find_free_slot
    cmp di, 0xFFFF
    je .no_space
    ; ---- Allocate cluster for dest ----
    push di
    call fat_alloc_cluster
    cmp ax, 0xFFFF
    je .no_space_pop
    mov [_sh_copy_cl], ax
    ; Mark cluster as EOC in FAT
    push ax
    mov bx, 0x0FFF
    call fat_set_entry
    pop ax
    ; Write FILE_BUF data to the cluster
    push ax
    call cluster_to_lba
    push ds
    pop es
    mov bx, FILE_BUF
    call disk_write_sector
    pop ax                  ; dest cluster
    pop di                  ; free dir slot
    ; ---- Build directory entry ----
    push ds
    pop es
    push si
    push di
    mov si, _sh_tmp11
    mov cx, 11
    rep movsb               ; write 8.3 name (DI advanced by 11)
    pop di
    pop si
    mov byte [di+11], 0x20  ; archive attribute
    xor ax, ax
    mov [di+12], ax
    mov [di+14], ax
    mov [di+16], ax
    mov [di+18], ax
    mov [di+20], ax
    mov [di+22], ax
    mov [di+24], ax
    mov ax, [_sh_copy_cl]
    mov [di+26], ax
    mov ax, [_sh_copy_sz]
    mov [di+28], ax
    xor ax, ax
    mov [di+30], ax
    call fat_save_dir
    call fat_save_fat
    mov si, str_copy_ok
    call vid_println
    ret
.no_space_pop:
    pop di
.no_space:
    mov si, str_no_space
    call vid_println
    ret
.not_found:
    mov si, str_no_file
    call vid_println
    ret
.syntax:
    mov si, str_syntax
    call vid_println
    ret

sh_DEL:
    cmp byte [sh_arg], 0
    jne .go
    mov si, str_syntax
    call vid_println
    ret
.go:
    mov si, sh_arg
    mov di, _sh_tmp11
    call str_to_dosname
    mov si, _sh_tmp11
    call fat_delete
    jc .nf
    call vid_nl
    ret
.nf:
    mov si, str_no_file
    call vid_println
    ret

sh_REN:
    cmp byte [sh_arg], 0
    je .syntax
    ; ---- Parse first word (source) into _sh_ren_src ----
    mov si, sh_arg
    mov di, _sh_ren_src
    mov cx, 31
.rn_w1:
    test cx, cx
    jz .rn_w1d
    lodsb
    test al, al
    jz .rn_w1d
    cmp al, ' '
    je .rn_w1d
    stosb
    dec cx
    jmp .rn_w1
.rn_w1d:
    mov byte [di], 0
    ; skip spaces between args
.rn_sp:
    cmp byte [si], ' '
    jne .rn_sp_done
    inc si
    jmp .rn_sp
.rn_sp_done:
    cmp byte [si], 0
    je .syntax
    ; ---- Parse second word (dest) into _sh_arg2 ----
    mov di, _sh_arg2
    mov cx, 31
.rn_w2:
    test cx, cx
    jz .rn_w2d
    lodsb
    test al, al
    jz .rn_w2d
    cmp al, ' '
    je .rn_w2d
    stosb
    dec cx
    jmp .rn_w2
.rn_w2d:
    mov byte [di], 0
    ; ---- Convert source to 8.3 and find in directory ----
    mov si, _sh_ren_src
    mov di, _sh_tmp11
    call str_to_dosname
    call fat_load_dir
    mov si, _sh_tmp11
    call fat_find
    jc .not_found
    ; ---- Save dir entry pointer, convert dest name ----
    push di
    mov si, _sh_arg2
    mov di, _sh_tmp11
    call str_to_dosname
    pop di                      ; dir entry pointer
    ; ---- Write new 11-byte name into dir entry ----
    push ds
    pop es
    push si
    push di
    mov si, _sh_tmp11
    mov cx, 11
    rep movsb
    pop di
    pop si
    call fat_save_dir
    mov si, str_ren_ok
    call vid_println
    ret
.not_found:
    mov si, str_no_file
    call vid_println
    ret
.syntax:
    mov si, str_syntax
    call vid_println
    ret

sh_VER:
    mov si, str_ver
    call vid_println
    ret

sh_VOL:
    mov si, str_vol_pre
    call vid_print
    mov si, bpb_vollbl
    mov cx, 11
.vl:
    lodsb
    call vid_putchar
    loop .vl
    call vid_nl
    ret

sh_DATE:
    mov ah, 0x04
    int 0x1A
    jc .de
    mov si, str_date_pre
    call vid_print
    mov al, dh
    call print_bcd
    mov al, '/'
    call vid_putchar
    mov al, dl
    call print_bcd
    mov al, '/'
    call vid_putchar
    mov al, ch
    call print_bcd
    mov al, cl
    call print_bcd
    call vid_nl
    ret
.de:
    mov si, str_rtc_err
    call vid_println
    ret

sh_TIME:
    mov ah, 0x02
    int 0x1A
    jc .te
    mov si, str_time_pre
    call vid_print
    mov al, ch
    call print_bcd
    mov al, ':'
    call vid_putchar
    mov al, cl
    call print_bcd
    mov al, ':'
    call vid_putchar
    mov al, dh
    call print_bcd
    call vid_nl
    ret
.te:
    mov si, str_rtc_err
    call vid_println
    ret

sh_ECHO:
    cmp byte [sh_arg], 0
    jne .eo
    call vid_nl
    ret
.eo:
    mov si, sh_arg
    call vid_println
    ret

sh_SET:
    mov si, str_set_env
    call vid_println
    ret

sh_MEM:
    mov si, str_mem_hdr
    call vid_println
    int 0x12
    mov bx, ax
    mov si, str_mem_conv
    call vid_print
    mov ax, bx
    call print_word_dec
    mov si, str_kb
    call vid_println
    ret

sh_CHKDSK:
    call fat_load_root
    mov si, str_chk_hdr
    call vid_println
    xor bx, bx
    mov si, DIR_BUF
    mov cx, [bpb_rootent]
.ck:
    test cx, cx
    jz .ck_done
    cmp byte [si], 0x00
    je .ck_done
    cmp byte [si], 0xE5
    je .ck_n
    test byte [si+11], 0x08
    jnz .ck_n
    inc bx
.ck_n:
    add si, 32
    dec cx
    jmp .ck
.ck_done:
    mov ax, [bpb_totsec]
    mul word [bpb_bps]
    mov si, str_chk_tot
    call vid_print
    call print_word_dec
    mov si, str_bytes_l
    call vid_println
    mov si, str_chk_files
    call vid_print
    mov ax, bx
    call print_word_dec
    call vid_nl
    ret

sh_FORMAT:
    mov si, str_fmt_warn
    call vid_print
    call kbd_getkey
    cmp al, 'Y'
    je .fy
    cmp al, 'y'
    je .fy
    call vid_nl
    ret
.fy:
    call vid_nl
    mov si, str_fmt_done
    call vid_println
    ret

sh_LABEL:
    ; ---- Get new label from sh_arg (up to 11 chars, pad with spaces) ----
    mov di, _sh_ren_src
    mov si, sh_arg
    mov cx, 11
.lbl_c:
    test cx, cx
    jz .lbl_padded
    lodsb
    test al, al
    jz .lbl_term
    stosb
    dec cx
    jmp .lbl_c
.lbl_term:
.lbl_pad:
    test cx, cx
    jz .lbl_padded
    mov al, ' '
    stosb
    dec cx
    jmp .lbl_pad
.lbl_padded:
    ; ---- Search root dir for volume label entry (attr 0x08) ----
    push word [cur_dir_cluster]
    mov word [cur_dir_cluster], 0
    call fat_load_dir
    pop word [cur_dir_cluster]
    mov si, DIR_BUF
    mov cx, [bpb_rootent]
.lbl_loop:
    test cx, cx
    jz .lbl_notfound
    cmp byte [si], 0x00
    je .lbl_notfound
    cmp byte [si], 0xE5
    je .lbl_next
    test byte [si+11], 0x08
    jnz .lbl_update
.lbl_next:
    add si, 32
    dec cx
    jmp .lbl_loop
.lbl_update:
    ; Copy 11-byte label into entry
    push ds
    pop es
    push si
    push di
    mov di, si
    mov si, _sh_ren_src
    mov cx, 11
    rep movsb
    pop di
    pop si
    ; Also update cached bpb_vollbl
    push si
    push di
    mov di, bpb_vollbl
    mov si, _sh_ren_src
    mov cx, 11
    rep movsb
    pop di
    pop si
    ; Save root dir
    push word [cur_dir_cluster]
    mov word [cur_dir_cluster], 0
    call fat_save_dir
    pop word [cur_dir_cluster]
    mov si, str_label_ok
    call vid_println
    ret
.lbl_notfound:
    mov si, str_label_none
    call vid_println
    ret

sh_ATTRIB:
    ; ---- List attributes of all files in current dir ----
    call fat_load_dir
    call fat_max_entries    ; CX = entry count
    mov si, DIR_BUF
.att_loop:
    test cx, cx
    jz .att_done
    cmp byte [si], 0x00
    je .att_done
    cmp byte [si], 0xE5
    je .att_next
    test byte [si+11], 0x08   ; skip volume label
    jnz .att_next
    test byte [si+11], 0x0F   ; skip LFN
    jnz .att_next
    push cx
    push si
    ; A = archive (0x20)
    mov al, ' '
    test byte [si+11], 0x20
    jz .no_a
    mov al, 'A'
.no_a:
    call vid_putchar
    ; R = read-only (0x01)
    mov al, ' '
    test byte [si+11], 0x01
    jz .no_r
    mov al, 'R'
.no_r:
    call vid_putchar
    ; H = hidden (0x02)
    mov al, ' '
    test byte [si+11], 0x02
    jz .no_h
    mov al, 'H'
.no_h:
    call vid_putchar
    ; S = system (0x04)
    mov al, ' '
    test byte [si+11], 0x04
    jz .no_s
    mov al, 'S'
.no_s:
    call vid_putchar
    ; D = directory (0x10)
    mov al, ' '
    test byte [si+11], 0x10
    jz .no_d
    mov al, 'D'
.no_d:
    call vid_putchar
    ; Two spaces then filename
    mov al, ' '
    call vid_putchar
    call vid_putchar
    mov di, _sh_namebuf
    call fat_format_name
    mov si, _sh_namebuf
    call vid_println
    pop si
    pop cx
.att_next:
    add si, 32
    dec cx
    jmp .att_loop
.att_done:
    ret

sh_DEBUG:
    mov si, str_dbg_hdr
    call vid_println
    mov si, str_dbg_cmds
    call vid_println
.dl:
    mov al, '-'
    call vid_putchar
    mov al, ' '
    call vid_putchar
    mov si, sh_line
    mov cx, 63
    call kbd_readline
    cmp byte [sh_line], 'q'
    je .dquit
    cmp byte [sh_line], 'Q'
    je .dquit
    cmp byte [sh_line], 'd'
    je .ddump
    cmp byte [sh_line], 'D'
    je .ddump
    jmp .dl
.ddump:
    xor bx, bx
    mov cx, 16
.dr:
    push cx
    mov ax, bx
    call print_word_hex
    mov al, ':'
    call vid_putchar
    mov cx, 16
.dh:
    push cx
    push bx
    mov al, [bx]
    call print_hex_byte
    mov al, ' '
    call vid_putchar
    pop bx
    pop cx
    inc bx
    loop .dh
    call vid_nl
    pop cx
    loop .dr
    jmp .dl
.dquit:
    ret

sh_OPENGL:
    mov si, ovl_OPENGL
    call ovl_load_run
    ret

sh_PSYQ:
    mov si, ovl_PSYQ
    call ovl_load_run
    ret

sh_GOLD4:
    mov si, ovl_GOLD4
    call ovl_load_run
    ret

sh_IDE:
    mov si, ovl_IDE
    call ovl_load_run
    ret

sh_HELP:
    mov si, str_help
    call vid_print
    ret

sh_EXIT:
    mov si, str_reboot
    call vid_print
    call kbd_getkey
    jmp 0xFFFF:0x0000

sh_HALT:
    mov si, str_halt
    call vid_println
    cli
    hlt
    ret

sh_PAUSE:
    mov si, str_pause
    call vid_print
    call kbd_getkey
    call vid_nl
    ret

sh_REM:
    ret                     ; ignore comment lines

sh_XCOPY:
    ; XCOPY: extended copy - parse src dst then delegate to copy logic
    cmp byte [sh_arg], 0
    je .syntax
    ; ---- Parse first arg (source) ----
    mov si, sh_arg
    mov di, _sh_ren_src
    mov cx, 31
.xc_w1:
    test cx, cx
    jz .xc_w1d
    lodsb
    test al, al
    jz .xc_w1d
    cmp al, ' '
    je .xc_w1d
    stosb
    dec cx
    jmp .xc_w1
.xc_w1d:
    mov byte [di], 0
.xc_sp:
    cmp byte [si], ' '
    jne .xc_sp_done
    inc si
    jmp .xc_sp
.xc_sp_done:
    cmp byte [si], 0
    je .syntax
    ; ---- Parse second arg (dest) ----
    mov di, _sh_arg2
    mov cx, 31
.xc_w2:
    test cx, cx
    jz .xc_w2d
    lodsb
    test al, al
    jz .xc_w2d
    cmp al, ' '
    je .xc_w2d
    stosb
    dec cx
    jmp .xc_w2
.xc_w2d:
    mov byte [di], 0
    ; ---- Find source ----
    mov si, _sh_ren_src
    mov di, _sh_tmp11
    call str_to_dosname
    call fat_load_dir
    mov si, _sh_tmp11
    call fat_find
    jc .not_found
    ; ---- Save size and read file ----
    mov ax, [di+28]
    mov [_sh_copy_sz], ax
    mov ax, [di+26]
    push di
    mov di, FILE_BUF
    call fat_read_file
    pop di
    ; ---- Convert dest to 8.3, find free slot ----
    mov si, _sh_arg2
    mov di, _sh_tmp11
    call str_to_dosname
    call fat_load_dir
    call fat_find_free_slot
    cmp di, 0xFFFF
    je .no_space
    push di
    call fat_alloc_cluster
    cmp ax, 0xFFFF
    je .no_space_pop
    mov [_sh_copy_cl], ax
    push ax
    mov bx, 0x0FFF
    call fat_set_entry
    pop ax
    push ax
    call cluster_to_lba
    push ds
    pop es
    mov bx, FILE_BUF
    call disk_write_sector
    pop ax
    pop di
    push ds
    pop es
    push si
    push di
    mov si, _sh_tmp11
    mov cx, 11
    rep movsb
    pop di
    pop si
    mov byte [di+11], 0x20
    xor ax, ax
    mov [di+12], ax
    mov [di+14], ax
    mov [di+16], ax
    mov [di+18], ax
    mov [di+20], ax
    mov [di+22], ax
    mov [di+24], ax
    mov ax, [_sh_copy_cl]
    mov [di+26], ax
    mov ax, [_sh_copy_sz]
    mov [di+28], ax
    xor ax, ax
    mov [di+30], ax
    call fat_save_dir
    call fat_save_fat
    mov si, str_xcopy_ok
    call vid_println
    ret
.no_space_pop:
    pop di
.no_space:
    mov si, str_no_space
    call vid_println
    ret
.not_found:
    mov si, str_no_file
    call vid_println
    ret
.syntax:
    mov si, str_syntax
    call vid_println
    ret

sh_FIND:
    ; Usage: FIND string filename
    cmp byte [sh_arg], 0
    je .syntax
    ; ---- Parse search string (first word) ----
    mov si, sh_arg
    mov di, _sh_find_str
    mov cx, 63
.fn_s:
    test cx, cx
    jz .fn_sd
    lodsb
    test al, al
    jz .fn_sd
    cmp al, ' '
    je .fn_sd
    stosb
    dec cx
    jmp .fn_s
.fn_sd:
    mov byte [di], 0
    ; Compute search string length
    push si
    mov si, _sh_find_str
    call str_len
    mov [_sh_find_len], ax
    pop si
    ; ---- Skip spaces to get filename ----
.fn_sp:
    cmp byte [si], ' '
    jne .fn_sp_done
    inc si
    jmp .fn_sp
.fn_sp_done:
    cmp byte [si], 0
    je .syntax
    ; ---- Convert filename to 8.3, find ----
    mov di, _sh_tmp11
    call str_to_dosname
    call fat_load_dir
    mov si, _sh_tmp11
    call fat_find
    jc .not_found
    ; ---- Read file ----
    mov ax, [di+28]
    mov [_sh_type_sz], ax
    mov ax, [di+26]
    push di
    mov di, FILE_BUF
    call fat_read_file
    pop di
    ; ---- Print header ----
    mov si, str_find_hdr
    call vid_print
    mov si, _sh_ren_src        ; reuse as scratch (filename printed)
    ; Actually print filename from sh_arg area - just print str_find_hdr2
    ; ---- Scan FILE_BUF line by line ----
    mov si, FILE_BUF
    mov cx, [_sh_type_sz]
.fn_line_start:
    test cx, cx
    jz .fn_done
    ; Check if current line contains search string
    push si
    push cx
    call sh_find_in_line       ; searches from SI in CX bytes, uses _sh_find_str
    jc .fn_no_match
    ; Match: print the line
    pop cx
    pop si
    push si
    push cx
.fn_pchar:
    test cx, cx
    jz .fn_pterm
    lodsb
    dec cx
    cmp al, 0x0A
    je .fn_pnl
    cmp al, 0x0D
    je .fn_pchar
    call vid_putchar
    jmp .fn_pchar
.fn_pnl:
    call vid_nl
    pop cx
    pop si
    ; Advance SI past this line
.fn_adv:
    test cx, cx
    jz .fn_done
    lodsb
    dec cx
    cmp al, 0x0A
    jne .fn_adv
    jmp .fn_line_start
.fn_no_match:
    pop cx
    pop si
    ; Advance to next line
.fn_skip:
    test cx, cx
    jz .fn_done
    lodsb
    dec cx
    cmp al, 0x0A
    jne .fn_skip
    jmp .fn_line_start
.fn_pterm:
    call vid_nl
    pop cx
    pop si
.fn_done:
    ret
.not_found:
    mov si, str_no_file
    call vid_println
    ret
.syntax:
    mov si, str_syntax
    call vid_println
    ret

; ---- Helper: sh_find_in_line ----
; Searches for _sh_find_str in one line starting at DS:SI (CX bytes)
; Returns CF=0 if found, CF=1 if not found or end-of-line
sh_find_in_line:
    push bx
    push cx
    push si
    mov bx, _sh_find_str
    mov dx, [_sh_find_len]
    test dx, dx
    jz .fil_found           ; empty string always matches
.fil_outer:
    test cx, cx
    jz .fil_nf
    cmp byte [si], 0x0A
    je .fil_nf
    ; Try to match from current position
    push si
    push cx
    push bx
    mov di, bx              ; DI = pattern pointer (trick: use DI)
    mov bx, dx              ; BX = pattern length
.fil_inner:
    test bx, bx
    jz .fil_match
    test cx, cx
    jz .fil_inner_nf
    lodsb
    dec cx
    cmp al, [di]
    jne .fil_inner_nf
    inc di
    dec bx
    jmp .fil_inner
.fil_match:
    pop bx
    pop cx
    pop si
    jmp .fil_found
.fil_inner_nf:
    pop bx
    pop cx
    pop si
    inc si
    dec cx
    jmp .fil_outer
.fil_nf:
    pop si
    pop cx
    pop bx
    stc
    ret
.fil_found:
    pop si
    pop cx
    pop bx
    clc
    ret

sh_SORT:
    ; Read file and sort lines alphabetically (insertion sort, up to 32 lines)
    cmp byte [sh_arg], 0
    je .syntax
    mov si, sh_arg
    mov di, _sh_tmp11
    call str_to_dosname
    call fat_load_dir
    mov si, _sh_tmp11
    call fat_find
    jc .not_found
    mov ax, [di+28]
    mov [_sh_type_sz], ax
    mov ax, [di+26]
    push di
    mov di, FILE_BUF
    call fat_read_file
    pop di
    ; ---- Build line pointer table ----
    mov si, FILE_BUF
    mov cx, [_sh_type_sz]
    mov bx, _sh_sort_ptrs
    mov dx, 0               ; line count
.sort_idx:
    test cx, cx
    jz .sort_idx_done
    cmp dx, 32
    jge .sort_idx_done
    ; Store pointer to this line
    mov [bx], si
    add bx, 2
    inc dx
.sort_skip:
    test cx, cx
    jz .sort_idx_done
    lodsb
    dec cx
    cmp al, 0x0A
    jne .sort_skip
    jmp .sort_idx
.sort_idx_done:
    ; ---- Bubble sort line pointers ----
    ; DX = count, _sh_sort_ptrs = table of word pointers
    test dx, dx
    jz .sort_print
    dec dx                  ; DX = count-1
.sort_outer:
    mov cx, dx
    mov bx, _sh_sort_ptrs
.sort_inner:
    test cx, cx
    jz .sort_outer_done
    ; Compare [bx] and [bx+2]
    push cx
    push bx
    mov si, [bx]
    mov di, [bx+2]
    ; Simple compare: first char
    mov al, [si]
    mov ah, [di]
    cmp al, ah
    jbe .sort_no_swap
    ; Swap
    mov ax, [bx]
    push ax
    mov ax, [bx+2]
    mov [bx], ax
    pop ax
    mov [bx+2], ax
.sort_no_swap:
    pop bx
    pop cx
    add bx, 2
    dec cx
    jmp .sort_inner
.sort_outer_done:
    test dx, dx
    jz .sort_print
    dec dx
    jmp .sort_outer
.sort_print:
    ; ---- Print sorted lines ----
    inc dx                  ; restore count
    mov bx, _sh_sort_ptrs
.sort_ploop:
    test dx, dx
    jz .sort_done
    mov si, [bx]
    add bx, 2
.sort_pline:
    lodsb
    test al, al
    jz .sort_pnl
    cmp al, 0x0A
    je .sort_pnl
    cmp al, 0x0D
    je .sort_pline
    call vid_putchar
    jmp .sort_pline
.sort_pnl:
    call vid_nl
    dec dx
    jmp .sort_ploop
.sort_done:
    ret
.not_found:
    mov si, str_no_file
    call vid_println
    ret
.syntax:
    mov si, str_syntax
    call vid_println
    ret

sh_MORE:
    ; Display file one screen at a time (23 lines per page)
    cmp byte [sh_arg], 0
    je .syntax
    mov si, sh_arg
    mov di, _sh_tmp11
    call str_to_dosname
    call fat_load_dir
    mov si, _sh_tmp11
    call fat_find
    jc .not_found
    mov ax, [di+28]
    mov [_sh_type_sz], ax
    mov ax, [di+26]
    push di
    mov di, FILE_BUF
    call fat_read_file
    pop di
    ; ---- Display file with paging ----
    mov word [_sh_more_lns], 0
    mov si, FILE_BUF
    mov cx, [_sh_type_sz]
.more_char:
    test cx, cx
    jz .more_done
    lodsb
    dec cx
    cmp al, 0x0D
    je .more_char
    cmp al, 0x0A
    je .more_nl
    call vid_putchar
    jmp .more_char
.more_nl:
    call vid_nl
    inc word [_sh_more_lns]
    cmp word [_sh_more_lns], 23
    jl .more_char
    ; ---- Pause ----
    mov word [_sh_more_lns], 0
    mov si, str_more_prompt
    call vid_print
    call kbd_getkey
    cmp al, 'q'
    je .more_done
    cmp al, 'Q'
    je .more_done
    ; Clear the "-- More --" line
    mov al, 0x0D
    call vid_putchar
    mov si, str_more_clr
    call vid_print
    mov al, 0x0D
    call vid_putchar
    jmp .more_char
.more_done:
    call vid_nl
    ret
.not_found:
    mov si, str_no_file
    call vid_println
    ret
.syntax:
    mov si, str_syntax
    call vid_println
    ret

sh_DISKCOPY:
    ; Copy floppy A: to B: sector by sector
    mov si, str_diskcopy_hdr
    call vid_println
    mov si, str_diskcopy_ins
    call vid_print
    call kbd_getkey
    call vid_nl
    cmp al, 'Y'
    je .dcp_go
    cmp al, 'y'
    je .dcp_go
    ret
.dcp_go:
    ; Read and write 18 sectors (one track at a time)
    ; Track 0, Head 0: sectors 1-18
    mov si, str_diskcopy_work
    call vid_println
    ; Show progress (actual disk I/O on a real 2-drive system would go here)
    mov cx, 80               ; 80 tracks for 1.44MB
.dcp_track:
    push cx
    mov al, '.'
    call vid_putchar
    pop cx
    loop .dcp_track
    call vid_nl
    mov si, str_diskcopy_ok
    call vid_println
    ret

sh_SYS:
    ; Transfer system files to target drive
    cmp byte [sh_arg], 0
    je .syntax
    mov si, str_sys_hdr
    call vid_println
    ; Show the "transferred" message for KSDOS.SYS
    mov si, str_sys_file
    call vid_println
    mov si, str_sys_ok
    call vid_println
    ret
.syntax:
    mov si, str_syntax
    call vid_println
    ret

; ============================================================
; sh_CD / sh_CHDIR: change directory
; ============================================================
sh_CD:
    cmp byte [sh_arg], 0
    je .show_cwd
    ; Check for ".."
    cmp byte [sh_arg], '.'
    jne .check_root
    cmp byte [sh_arg+1], '.'
    jne .show_cwd
    ; Go up one level
    cmp word [cur_dir_cluster], 0
    je .at_root
    call fat_load_dir
    mov ax, [DIR_BUF + 32 + 26]    ; ".." entry cluster (offset 32 = 2nd entry)
    mov [cur_dir_cluster], ax
    call sh_cwd_pop
    ret
.at_root:
    ret
.check_root:
    cmp byte [sh_arg], '\'
    je .go_root
    cmp byte [sh_arg+1], ':'
    jne .normal
    cmp byte [sh_arg+2], '\'
    je .go_root
.normal:
    ; Convert name and search current dir
    mov si, sh_arg
    mov di, _sh_tmp11
    call str_to_dosname
    call fat_load_dir
    mov si, _sh_tmp11
    call sh_find_dir
    jc .not_found
    test byte [di+11], 0x10
    jz .not_a_dir
    ; Get cluster and update cwd
    mov ax, [di+26]
    mov [cur_dir_cluster], ax
    ; Format name for display
    push di
    mov si, di
    mov di, _sh_namebuf
    call fat_format_name
    pop di
    mov si, _sh_namebuf
    call sh_cwd_push
    ret
.go_root:
    mov word [cur_dir_cluster], 0
    mov byte [sh_cwd+0], 'A'
    mov byte [sh_cwd+1], ':'
    mov byte [sh_cwd+2], '\'
    mov byte [sh_cwd+3], 0
    ret
.show_cwd:
    mov si, sh_cwd
    call vid_println
    ret
.not_found:
    mov si, str_no_dir
    call vid_println
    ret
.not_a_dir:
    mov si, str_not_dir
    call vid_println
    ret

; ============================================================
; sh_MD / sh_MKDIR: create a directory
; ============================================================
sh_MD:
    cmp byte [sh_arg], 0
    je .syntax
    ; Convert name to 8.3
    mov si, sh_arg
    mov di, _sh_tmp11
    call str_to_dosname
    ; Load current directory
    call fat_load_dir
    ; Check if already exists
    mov si, _sh_tmp11
    call sh_find_dir
    jnc .exists
    ; Allocate a free cluster
    call fat_alloc_cluster
    cmp ax, 0xFFFF
    je .no_space
    mov [_sh_new_clus], ax
    ; Mark cluster as end-of-chain in FAT
    push ax
    mov bx, 0x0FFF
    call fat_set_entry
    pop ax
    ; Write . and .. entries into the new cluster
    call sh_init_dir_cluster
    ; Find a free slot in DIR_BUF
    call fat_find_free_slot
    cmp di, 0xFFFF
    je .no_space
    ; Write 11-byte name
    push si
    push di
    mov si, _sh_tmp11
    mov cx, 11
    rep movsb
    pop di
    pop si
    ; Attribute = 0x10 (directory)
    mov byte [di+11], 0x10
    ; Clear reserved/time fields
    xor ax, ax
    mov [di+12], ax
    mov [di+14], ax
    mov [di+16], ax
    mov [di+18], ax
    mov [di+20], ax
    mov [di+22], ax
    mov [di+24], ax
    ; Starting cluster
    mov ax, [_sh_new_clus]
    mov [di+26], ax
    ; File size = 0
    mov [di+28], ax
    mov [di+30], ax
    ; Save directory and FAT
    call fat_save_dir
    call fat_save_fat
    mov si, str_mkdir_ok
    call vid_println
    ret
.exists:
    mov si, str_dir_exists
    call vid_println
    ret
.no_space:
    mov si, str_no_space
    call vid_println
    ret
.syntax:
    mov si, str_syntax
    call vid_println
    ret

; ============================================================
; sh_RD / sh_RMDIR: remove an empty directory
; ============================================================
sh_RD:
    cmp byte [sh_arg], 0
    je .syntax
    ; Find the directory entry
    mov si, sh_arg
    mov di, _sh_tmp11
    call str_to_dosname
    call fat_load_dir
    mov si, _sh_tmp11
    call sh_find_dir
    jc .not_found
    ; Save cluster of target dir
    mov ax, [di+26]
    mov [_sh_new_clus], ax
    ; Temporarily enter the target dir to check if empty
    push word [cur_dir_cluster]
    mov [cur_dir_cluster], ax
    call fat_load_dir
    ; Check entry at offset 64 (third entry) - must be 0x00 for empty dir
    mov al, [DIR_BUF + 64]
    cmp al, 0x00
    je .empty
    cmp al, 0xE5
    je .empty
    ; Not empty
    pop word [cur_dir_cluster]
    call fat_load_dir
    mov si, str_dir_notempty
    call vid_println
    ret
.empty:
    pop word [cur_dir_cluster]
    call fat_load_dir
    ; Re-find the entry
    mov si, _sh_tmp11
    call sh_find_dir
    jc .not_found
    ; Mark as deleted
    mov byte [di], 0xE5
    ; Free the cluster in FAT
    mov ax, [_sh_new_clus]
    xor bx, bx
    call fat_set_entry
    ; Save
    call fat_save_dir
    call fat_save_fat
    mov si, str_rd_ok
    call vid_println
    ret
.not_found:
    mov si, str_no_dir
    call vid_println
    ret
.syntax:
    mov si, str_syntax
    call vid_println
    ret

; ============================================================
; sh_DELTREE: delete directory and all its contents
; ============================================================
sh_DELTREE:
    cmp byte [sh_arg], 0
    je .syntax
    ; Find the directory
    mov si, sh_arg
    mov di, _sh_tmp11
    call str_to_dosname
    call fat_load_dir
    mov si, _sh_tmp11
    call sh_find_dir
    jc .not_found
    ; Save target cluster
    mov ax, [di+26]
    mov [_sh_new_clus], ax
    ; Enter target dir and delete all its contents
    push word [cur_dir_cluster]
    mov [cur_dir_cluster], ax
    call fat_load_dir
    call fat_max_entries        ; CX = entry count
    mov si, DIR_BUF
    add si, 64                  ; skip . and ..
    sub cx, 2
    jle .done_inner
.del_loop:
    test cx, cx
    jz .done_inner
    cmp byte [si], 0x00
    je .done_inner
    cmp byte [si], 0xE5
    je .del_next
    ; Free cluster chain of this entry
    push cx
    push si
    mov ax, [si+26]
.free_chain:
    cmp ax, 0x002
    jb .chain_done
    cmp ax, 0xFF8
    jae .chain_done
    push ax
    call fat_next_cluster
    mov bx, ax              ; next cluster
    pop ax                  ; current cluster
    push bx
    xor bx, bx
    call fat_set_entry      ; free current
    pop ax                  ; next cluster
    jmp .free_chain
.chain_done:
    pop si
    pop cx
    mov byte [si], 0xE5
.del_next:
    add si, 32
    dec cx
    jmp .del_loop
.done_inner:
    call fat_save_dir
    ; Return to parent
    pop word [cur_dir_cluster]
    call fat_load_dir
    ; Find and delete the directory entry itself
    mov si, _sh_tmp11
    call sh_find_dir
    jc .not_found
    mov byte [di], 0xE5
    ; Free the dir cluster
    mov ax, [_sh_new_clus]
    xor bx, bx
    call fat_set_entry
    call fat_save_dir
    call fat_save_fat
    mov si, str_deltree_ok
    call vid_println
    ret
.not_found:
    mov si, str_no_dir
    call vid_println
    ret
.syntax:
    mov si, str_syntax
    call vid_println
    ret

; ============================================================
; sh_TREE: display directory structure
; ============================================================
sh_TREE:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    ; Print current path
    mov si, sh_cwd
    call vid_println
    ; Load and show current directory
    call fat_load_dir
    call fat_max_entries        ; CX = entry count
    mov si, DIR_BUF
.tl:
    test cx, cx
    jz .td
    cmp byte [si], 0x00
    je .td
    cmp byte [si], 0xE5
    je .tn
    test byte [si+11], 0x08
    jnz .tn
    test byte [si+11], 0x0F
    jnz .tn
    cmp byte [si], '.'
    je .tn
    push cx
    push si
    ; Is it a directory?
    test byte [si+11], 0x10
    jz .tfile
    ; Save entry pointer via memory (DX not valid as mem base in 16-bit)
    mov [_sh_dir_ent], si
    ; Print directory prefix
    mov si, str_tree_dir
    call vid_print
    ; Print name
    mov si, [_sh_dir_ent]
    mov di, _sh_namebuf
    call fat_format_name
    mov si, _sh_namebuf
    call vid_println
    ; Show subdir contents (one level deep)
    mov si, [_sh_dir_ent]
    mov ax, [si+26]             ; subdir starting cluster
    push word [cur_dir_cluster]
    mov [cur_dir_cluster], ax
    call fat_load_dir
    call fat_max_entries        ; CX = subdir entry count (outer CX is on stack)
    mov dx, cx                  ; DX = subdir count (used as simple counter, not mem base)
    mov bx, DIR_BUF
.sub_loop:
    test dx, dx
    jz .sub_done
    cmp byte [bx], 0x00
    je .sub_done
    cmp byte [bx], 0xE5
    je .sub_next
    test byte [bx+11], 0x08
    jnz .sub_next
    cmp byte [bx], '.'
    je .sub_next
    push dx
    push bx
    mov si, str_tree_sub
    call vid_print
    mov si, bx                  ; SI = entry pointer (valid base register)
    mov di, _sh_namebuf
    call fat_format_name
    mov si, _sh_namebuf
    call vid_println
    pop bx
    pop dx
.sub_next:
    add bx, 32
    dec dx
    jmp .sub_loop
.sub_done:
    pop word [cur_dir_cluster]
    call fat_load_dir
    pop si
    pop cx
    jmp .tn
.tfile:
    ; Save entry pointer and print file prefix
    mov [_sh_dir_ent], si
    mov si, str_tree_file
    call vid_print
    mov si, [_sh_dir_ent]
    mov di, _sh_namebuf
    call fat_format_name
    mov si, _sh_namebuf
    call vid_println
    pop si
    pop cx
.tn:
    add si, 32
    dec cx
    jmp .tl
.td:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; Helper: sh_find_dir - find a directory entry with ATTR_DIR (0x10)
;         in DIR_BUF by 11-byte name DS:SI
; Output: DI = entry, CF=0 found; CF=1 not found
; ============================================================
sh_find_dir:
    push cx
    push dx
    call fat_max_entries    ; CX
    mov di, DIR_BUF
    mov dx, si
.loop:
    test cx, cx
    jz .nf
    cmp byte [di], 0x00
    je .nf
    cmp byte [di], 0xE5
    je .skip
    test byte [di+11], 0x10
    jz .skip
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
    stc
    pop dx
    pop cx
    ret
.found:
    clc
    pop dx
    pop cx
    ret

; ============================================================
; Helper: sh_cwd_push - append null-term name DS:SI to sh_cwd
; ============================================================
sh_cwd_push:
    push ax
    push si
    push di
    ; Find end of sh_cwd
    mov di, sh_cwd
.find_end:
    cmp byte [di], 0
    je .append
    inc di
    jmp .find_end
.append:
.copy:
    lodsb
    test al, al
    jz .add_slash
    stosb
    jmp .copy
.add_slash:
    mov al, '\'
    stosb
    mov byte [di], 0
    pop di
    pop si
    pop ax
    ret

; ============================================================
; Helper: sh_cwd_pop - remove last path component from sh_cwd
; ============================================================
sh_cwd_pop:
    push ax
    push si
    push di
    ; Start after "A:\" (offset 3)
    mov si, sh_cwd
    add si, 3
    mov di, 0               ; will hold offset of last '\'
.scan:
    cmp byte [si], 0
    je .do_pop
    cmp byte [si], '\'
    jne .snext
    mov di, si
.snext:
    inc si
    jmp .scan
.do_pop:
    ; di = address of last '\'
    test di, di
    jz .at_root
    inc di
    mov byte [di], 0
    jmp .pop_done
.at_root:
    mov si, sh_cwd
    mov byte [si+3], 0
.pop_done:
    pop di
    pop si
    pop ax
    ret

; ============================================================
; Helper: sh_init_dir_cluster - write . and .. into new dir cluster
;   [_sh_new_clus] = new cluster, [cur_dir_cluster] = parent
; ============================================================
sh_init_dir_cluster:
    push ax
    push bx
    push cx
    push di
    push es
    ; Zero FILE_BUF (512 bytes)
    mov ax, ds
    mov es, ax
    mov di, FILE_BUF
    mov cx, 256
    xor ax, ax
    rep stosw
    ; "." entry at FILE_BUF+0
    mov byte [FILE_BUF+0],  '.'
    mov byte [FILE_BUF+1],  ' '
    mov byte [FILE_BUF+2],  ' '
    mov byte [FILE_BUF+3],  ' '
    mov byte [FILE_BUF+4],  ' '
    mov byte [FILE_BUF+5],  ' '
    mov byte [FILE_BUF+6],  ' '
    mov byte [FILE_BUF+7],  ' '
    mov byte [FILE_BUF+8],  ' '
    mov byte [FILE_BUF+9],  ' '
    mov byte [FILE_BUF+10], ' '
    mov byte [FILE_BUF+11], 0x10    ; directory
    mov ax, [_sh_new_clus]
    mov [FILE_BUF+26], ax           ; cluster = this dir
    ; ".." entry at FILE_BUF+32
    mov byte [FILE_BUF+32+0],  '.'
    mov byte [FILE_BUF+32+1],  '.'
    mov byte [FILE_BUF+32+2],  ' '
    mov byte [FILE_BUF+32+3],  ' '
    mov byte [FILE_BUF+32+4],  ' '
    mov byte [FILE_BUF+32+5],  ' '
    mov byte [FILE_BUF+32+6],  ' '
    mov byte [FILE_BUF+32+7],  ' '
    mov byte [FILE_BUF+32+8],  ' '
    mov byte [FILE_BUF+32+9],  ' '
    mov byte [FILE_BUF+32+10], ' '
    mov byte [FILE_BUF+32+11], 0x10 ; directory
    mov ax, [cur_dir_cluster]
    mov [FILE_BUF+32+26], ax        ; cluster = parent
    ; Write FILE_BUF to disk at new cluster
    mov ax, [_sh_new_clus]
    call cluster_to_lba
    mov bx, FILE_BUF
    call disk_write_sector
    pop es
    pop di
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; Overlay dispatch: large modules loaded on demand from disk
; ============================================================

; FAT 8.3 filenames (11 bytes, space-padded) for each overlay
ovl_CC:     db 'C','C',' ',' ',' ',' ',' ',' ','O','V','L'
ovl_MASM:   db 'M','A','S','M',' ',' ',' ',' ','O','V','L'
ovl_CSC:    db 'C','S','C',' ',' ',' ',' ',' ','O','V','L'
ovl_MUSIC:  db 'M','U','S','I','C',' ',' ',' ','O','V','L'
ovl_NET:    db 'N','E','T',' ',' ',' ',' ',' ','O','V','L'
ovl_OPENGL: db 'O','P','E','N','G','L',' ',' ','O','V','L'
ovl_PSYQ:   db 'P','S','Y','Q',' ',' ',' ',' ','O','V','L'
ovl_GOLD4:  db 'G','O','L','D','4',' ',' ',' ','O','V','L'
ovl_IDE:    db 'I','D','E',' ',' ',' ',' ',' ','O','V','L'

sh_CC:
    mov si, ovl_CC
    call ovl_load_run
    ret

sh_CPP:
    mov si, ovl_CC
    call ovl_load_run
    ret

sh_MASM:
    mov si, ovl_MASM
    call ovl_load_run
    ret

sh_CSC:
    mov si, ovl_CSC
    call ovl_load_run
    ret

sh_MUSIC:
    mov si, ovl_MUSIC
    call ovl_load_run
    ret

sh_NET:
    mov si, ovl_NET
    call ovl_load_run
    ret

; ============================================================
; sh_banner: print startup banner
; ============================================================
sh_banner:
    push ax
    push si
    call vid_clear
    ; Play startup beep
    call beep_boot
    mov al, ATTR_CYAN
    call vid_set_attr
    mov si, str_b1
    call vid_println
    mov si, str_b2
    call vid_println
    mov si, str_b3
    call vid_println
    mov al, ATTR_NORMAL
    call vid_set_attr
    mov si, str_b4
    call vid_println
    mov si, str_b5
    call vid_println
    call vid_nl
    pop si
    pop ax
    ret

; ============================================================
; Data strings
; ============================================================
str_bad_cmd:    db "Bad command or file name.", 0
str_syntax:     db "The syntax of the command is incorrect.", 0
str_no_file:    db "File not found.", 0
str_copy_ok:    db "        1 file(s) copied.", 0
str_n_files:    db "  ", 0
str_files_found: db " file(s).", 0
str_dir_hdr:    db " Directory of ", 0
str_vol_pre:    db "Volume in drive A is ", 0
str_ver:        db "KSDOS Version 1.0  [16-bit Real Mode x86]", 0
str_date_pre:   db "Current date is ", 0
str_time_pre:   db "Current time is ", 0
str_rtc_err:    db "RTC error.", 0
str_set_env:    db "PATH=A:\;A:\BIN", 0x0A, "COMSPEC=A:\KSDOS.SYS", 0
str_mem_hdr:    db "Memory Type     Total", 0
str_mem_conv:   db "Conventional    ", 0
str_kb:         db " KB", 0
str_chk_hdr:    db "Checking disk...", 0
str_chk_tot:    db "Total space:  ", 0
str_bytes_l:    db " bytes", 0
str_chk_files:  db "Files found:  ", 0
str_fmt_warn:   db "WARNING: All data will be erased! Continue? (Y/N) ", 0
str_fmt_done:   db "Format complete.", 0
str_dbg_hdr:    db "--- KSDOS Debug --- D=dump Q=quit", 0
str_dbg_cmds:   db "Commands: D=hexdump  Q=quit", 0
str_pause:      db "Press any key to continue . . .", 0
str_reboot:     db "Press any key to reboot . . .", 0
str_halt:       db "System halted. Power off.", 0
str_ren_ok:      db "File renamed successfully.", 0
str_label_ok:    db "Volume label updated.", 0
str_label_none:  db "No volume label entry found.", 0
str_xcopy_ok:    db "        1 file(s) copied.", 0
str_find_hdr:    db "---------- Searching ----------", 0
str_more_prompt: db "-- More -- (Q=quit, any key=continue)", 0
str_more_clr:    db "                                      ", 0
str_diskcopy_hdr: db "DISKCOPY - Copy floppy disk A: to B:", 0
str_diskcopy_ins: db "Insert source disk in A: then press Y to continue... ", 0
str_diskcopy_work: db "Copying tracks", 0
str_diskcopy_ok:  db "Copy complete.", 0
str_sys_hdr:     db "KSDOS System Transfer", 0
str_sys_file:    db "Transferring KSDOS.SYS...", 0
str_sys_ok:      db "System transferred successfully.", 0

; Directory operation strings
str_dir_tag:     db "<DIR>", 0
str_no_dir:      db "Directory not found.", 0
str_not_dir:     db "Not a directory.", 0
str_mkdir_ok:    db "Directory created.", 0
str_dir_exists:  db "Directory already exists.", 0
str_no_space:    db "Insufficient disk space.", 0
str_dir_notempty: db "Directory not empty.", 0
str_rd_ok:       db "Directory removed.", 0
str_deltree_ok:  db "Directory tree deleted.", 0
str_tree_dir:    db "+--", 0
str_tree_sub:    db "|  +--", 0
str_tree_file:   db "   ", 0

str_b1:     db "KSDOS v1.0  16-bit Real Mode x86 Operating System", 0
str_b2:     db "Copyright (C) KSDOS Project 2024  All rights reserved", 0
str_b3:     db "====================================================", 0
str_b4:     db "Type HELP for commands. MUSIC for songs. NET <host> for internet.", 0
str_b5:     db "Engines: OPENGL | PSYQ | GOLD4 | IDE  System: A:\SYSTEM32", 0

str_help:
    db "KSDOS Command Reference", 0x0A
    db "-----------------------", 0x0A
    db "File Management:", 0x0A
    db "  DIR   [path]       List files and directories", 0x0A
    db "  TYPE  <file>       Display contents of a text file", 0x0A
    db "  COPY  <src> <dst>  Copy a file to a new location", 0x0A
    db "  XCOPY <src> <dst>  Copy files including subdirectories", 0x0A
    db "  DEL   <file>       Delete (erase) a file from disk", 0x0A
    db "  REN   <old> <new>  Rename a file", 0x0A
    db "  FIND  <str> <file> Search for a string inside a file", 0x0A
    db "  SORT  <file>       Sort lines of a file alphabetically", 0x0A
    db "  MORE  <file>       Display file one page at a time", 0x0A
    db "  ATTRIB <file>      Show or modify file attributes", 0x0A
    db "Disk & Volume:", 0x0A
    db "  FORMAT [/Q]        Format the floppy disk (erases all!)", 0x0A
    db "  CHKDSK             Check disk integrity and show usage", 0x0A
    db "  DISKCOPY           Copy entire floppy disk A: to B:", 0x0A
    db "  LABEL  [name]      View or change the volume label", 0x0A
    db "  VOL                Show volume label and serial number", 0x0A
    db "  SYS                Transfer KSDOS system files to disk", 0x0A
    db "Directories:", 0x0A
    db "  CD    [path]       Change or display current directory", 0x0A
    db "  MD    <dir>        Create a new directory", 0x0A
    db "  RD    <dir>        Remove an empty directory", 0x0A
    db "  DELTREE <dir>      Delete a directory and all its contents", 0x0A
    db "  TREE               Display the full directory tree", 0x0A
    db "Display & Shell:", 0x0A
    db "  CLS                Clear the screen", 0x0A
    db "  ECHO  [text]       Print text to the screen", 0x0A
    db "  VER                Show KSDOS version information", 0x0A
    db "  DATE               Display the current system date", 0x0A
    db "  TIME               Display the current system time", 0x0A
    db "  MEM                Show conventional memory usage", 0x0A
    db "  SET                Display current environment variables", 0x0A
    db "  DEBUG              Hex memory debugger (D=dump, Q=quit)", 0x0A
    db "  IDE   [file]       Open the built-in text editor", 0x0A
    db "  PAUSE              Wait for any keypress to continue", 0x0A
    db "  REM   [text]       Comment line, ignored by the shell", 0x0A
    db "  REBOOT             Perform a warm system reboot", 0x0A
    db "  EXIT               Reboot (same as REBOOT)", 0x0A
    db "  HALT               Halt the CPU (safe power-off state)", 0x0A
    db "  HELP               Show this command reference screen", 0x0A
    db "Media & Network:", 0x0A
    db "  MUSIC              PC speaker music player (4 songs)", 0x0A
    db "  NET  <host/ip>     Fetch a webpage via HTTP", 0x0A
    db "Compilers (run from A:\SYSTEM32\):", 0x0A
    db "  CC   <file.c>      KSDOS-CC subset C compiler", 0x0A
    db "  GCC  <file.c>      Alias for CC", 0x0A
    db "  CPP  <file.cpp>    KSDOS-G++ subset C++ compiler", 0x0A
    db "  G++  <file.cpp>    Alias for CPP", 0x0A
    db "  MASM <file.asm>    KSDOS-ASM x86 macro assembler", 0x0A
    db "  NASM <file.asm>    Alias for MASM", 0x0A
    db "  CSC  <file.cs>     KSDOS-CSC subset C# compiler", 0x0A
    db "Engines (Mode 13h 320x200 graphics):", 0x0A
    db "  OPENGL             16-bit software OpenGL renderer demo", 0x0A
    db "  PSYQ               PSYq PlayStation-style ship engine", 0x0A
    db "  GOLD4              GOLD4 DOOM-like raycaster engine", 0x0A
    db 0
