; =============================================================================
; auth.asm - KSDOS User Authentication
; First-time setup (username/password) and login prompt
; 16-bit real mode
; =============================================================================

; ---- Constants ----
AUTH_MAGIC_0    equ 0x4B    ; 'K'
AUTH_MAGIC_1    equ 0x53    ; 'S'
AUTH_MAGIC_2    equ 0x44    ; 'D'
AUTH_MAGIC_3    equ 0x55    ; 'U'
AUTH_USER_MAX   equ 16
AUTH_PASS_MAX   equ 32
AUTH_MAX_TRIES  equ 3

; ---- FAT12 8.3 filename: "KSDOS   USR" (11 bytes) ----
auth_fname:     db 'K','S','D','O','S',' ',' ',' ','U','S','R'

; ---- Input / stored buffers ----
auth_user_buf:  times AUTH_USER_MAX db 0
auth_pass_buf:  times AUTH_PASS_MAX db 0
auth_pass_conf: times AUTH_PASS_MAX db 0
auth_stor_user: times AUTH_USER_MAX db 0
auth_stor_pass: times AUTH_PASS_MAX db 0

; ---- State ----
auth_try_count: db AUTH_MAX_TRIES

; ---- Strings ----
auth_s_setup:   db "KSDOS First-Time Setup", 0x0A
                db "======================", 0x0A, 0
auth_s_user:    db "Username: ", 0
auth_s_pass:    db "Password: ", 0
auth_s_confirm: db "Confirm  : ", 0
auth_s_nomatch: db "Passwords do not match. Please try again.", 0x0A, 0
auth_s_created: db "User account created successfully.", 0x0A, 0
auth_s_login:   db "KSDOS Login", 0x0A
                db "===========", 0x0A, 0
auth_s_welcome: db "Welcome, ", 0
auth_s_excl:    db "!", 0x0A, 0
auth_s_bad:     db "Incorrect username or password.", 0x0A, 0
auth_s_locked:  db "Too many failed attempts. System halted.", 0
auth_s_nl:      db 0x0A, 0

; ============================================================
; auth_init: entry point - setup on first run, login on subsequent runs
; ============================================================
auth_init:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; Look for KSDOS.USR in root directory
    mov word [cur_dir_cluster], 0
    mov si, auth_fname
    call fat_find
    jc .first_time

    ; File found - read it into FILE_BUF
    mov ax, [di+26]         ; starting cluster
    mov di, FILE_BUF
    call fat_read_file

    ; Verify magic signature
    cmp byte [FILE_BUF+0], AUTH_MAGIC_0
    jne .first_time
    cmp byte [FILE_BUF+1], AUTH_MAGIC_1
    jne .first_time
    cmp byte [FILE_BUF+2], AUTH_MAGIC_2
    jne .first_time
    cmp byte [FILE_BUF+3], AUTH_MAGIC_3
    jne .first_time

    ; Load stored credentials
    mov si, FILE_BUF + 4
    mov di, auth_stor_user
    mov cx, AUTH_USER_MAX
    rep movsb
    mov si, FILE_BUF + 4 + AUTH_USER_MAX
    mov di, auth_stor_pass
    mov cx, AUTH_PASS_MAX
    rep movsb

    call auth_login
    jmp .done

.first_time:
    call auth_setup

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; auth_setup: first-time username and password configuration
; ============================================================
auth_setup:
    push ax
    push bx
    push cx
    push si
    push di

    call vid_clear
    mov al, ATTR_CYAN
    call vid_set_attr
    mov si, auth_s_setup
    call vid_print
    mov al, ATTR_NORMAL
    call vid_set_attr

.get_user:
    mov si, auth_s_user
    call vid_print
    mov si, auth_user_buf
    mov cx, AUTH_USER_MAX - 1
    call kbd_readline
    cmp byte [auth_user_buf], 0
    je .get_user            ; reject empty username

.get_pass:
    mov si, auth_s_pass
    call vid_print
    mov si, auth_pass_buf
    mov cx, AUTH_PASS_MAX - 1
    call auth_read_pass
    cmp byte [auth_pass_buf], 0
    je .get_pass            ; reject empty password

    mov si, auth_s_confirm
    call vid_print
    mov si, auth_pass_conf
    mov cx, AUTH_PASS_MAX - 1
    call auth_read_pass

    ; Compare password with confirmation
    mov si, auth_pass_buf
    mov di, auth_pass_conf
.cmp_lp:
    lodsb
    mov bl, [di]
    inc di
    cmp al, bl
    jne .mismatch
    test al, al
    jnz .cmp_lp
    jmp .do_save

.mismatch:
    mov al, ATTR_RED
    call vid_set_attr
    mov si, auth_s_nomatch
    call vid_print
    mov al, ATTR_NORMAL
    call vid_set_attr
    ; Clear password buffers and retry
    mov di, auth_pass_buf
    mov cx, AUTH_PASS_MAX
    xor al, al
    rep stosb
    mov di, auth_pass_conf
    mov cx, AUTH_PASS_MAX
    rep stosb
    jmp .get_pass

.do_save:
    call auth_write_file
    mov al, ATTR_GREEN
    call vid_set_attr
    mov si, auth_s_created
    call vid_print
    mov al, ATTR_NORMAL
    call vid_set_attr

    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; auth_login: prompt for credentials and verify
; ============================================================
auth_login:
    push ax
    push bx
    push cx
    push si
    push di

    call vid_clear
    mov al, ATTR_CYAN
    call vid_set_attr
    mov si, auth_s_login
    call vid_print
    mov al, ATTR_NORMAL
    call vid_set_attr

    mov byte [auth_try_count], AUTH_MAX_TRIES

.try_again:
    mov si, auth_s_user
    call vid_print
    mov si, auth_user_buf
    mov cx, AUTH_USER_MAX - 1
    call kbd_readline

    mov si, auth_s_pass
    call vid_print
    mov si, auth_pass_buf
    mov cx, AUTH_PASS_MAX - 1
    call auth_read_pass

    ; Compare username
    mov si, auth_user_buf
    mov di, auth_stor_user
.cmp_u:
    lodsb
    mov bl, [di]
    inc di
    cmp al, bl
    jne .bad_creds
    test al, al
    jnz .cmp_u

    ; Compare password
    mov si, auth_pass_buf
    mov di, auth_stor_pass
.cmp_p:
    lodsb
    mov bl, [di]
    inc di
    cmp al, bl
    jne .bad_creds
    test al, al
    jnz .cmp_p

    ; Credentials correct - welcome the user
    mov al, ATTR_GREEN
    call vid_set_attr
    mov si, auth_s_welcome
    call vid_print
    mov si, auth_stor_user
    call vid_print
    mov si, auth_s_excl
    call vid_print
    mov al, ATTR_NORMAL
    call vid_set_attr
    jmp .done

.bad_creds:
    mov al, ATTR_RED
    call vid_set_attr
    mov si, auth_s_bad
    call vid_print
    mov al, ATTR_NORMAL
    call vid_set_attr

    dec byte [auth_try_count]
    jz .system_lock

    ; Clear buffers and retry
    mov di, auth_user_buf
    mov cx, AUTH_USER_MAX
    xor al, al
    rep stosb
    mov di, auth_pass_buf
    mov cx, AUTH_PASS_MAX
    rep stosb
    jmp .try_again

.system_lock:
    mov al, ATTR_RED
    call vid_set_attr
    mov si, auth_s_locked
    call vid_print
    cli
.halt:
    hlt
    jmp .halt

.done:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; auth_read_pass: read a password echoing '*' for each character
; Input:  SI = destination buffer, CX = max length (not including null)
; ============================================================
auth_read_pass:
    push bx
    push cx
    push di
    push si

    mov di, si              ; DI = write pointer into buffer
    xor bx, bx              ; BX = character count

.rp_loop:
    push cx
    call kbd_getkey         ; AL = ASCII, AH = scan code
    pop cx

    cmp al, 0x0D            ; Enter
    je .rp_done
    cmp al, 0x08            ; Backspace
    je .rp_bs
    cmp al, 0x20            ; must be printable
    jb .rp_loop
    cmp al, 0x7E
    ja .rp_loop

    ; Check buffer full (leave room for null)
    push cx
    dec cx
    cmp bx, cx
    pop cx
    jge .rp_loop

    ; Store the actual character and echo '*'
    mov [di + bx], al
    inc bx
    mov al, '*'
    call vid_putchar
    jmp .rp_loop

.rp_bs:
    test bx, bx
    jz .rp_loop
    dec bx
    ; Erase the '*' from the screen
    call vid_get_cursor
    cmp dl, 0
    je .rp_loop
    dec dl
    call vid_set_cursor
    mov al, ' '
    call vid_putchar
    call vid_get_cursor
    dec dl
    call vid_set_cursor
    jmp .rp_loop

.rp_done:
    mov byte [di + bx], 0   ; null-terminate
    call vid_nl

    pop si
    pop di
    pop cx
    pop bx
    ret

; ============================================================
; auth_write_file: create KSDOS.USR on the FAT12 disk
; ============================================================
auth_write_file:
    push ax
    push bx
    push cx
    push si
    push di
    push es

    ; --- Build 512-byte record in FILE_BUF ---
    mov di, FILE_BUF
    mov cx, 512
    xor al, al
    rep stosb

    ; Magic
    mov byte [FILE_BUF + 0], AUTH_MAGIC_0
    mov byte [FILE_BUF + 1], AUTH_MAGIC_1
    mov byte [FILE_BUF + 2], AUTH_MAGIC_2
    mov byte [FILE_BUF + 3], AUTH_MAGIC_3

    ; Username
    mov si, auth_user_buf
    mov di, FILE_BUF + 4
    mov cx, AUTH_USER_MAX
    rep movsb

    ; Password
    mov si, auth_pass_buf
    mov di, FILE_BUF + 4 + AUTH_USER_MAX
    mov cx, AUTH_PASS_MAX
    rep movsb

    ; --- Delete existing KSDOS.USR if present ---
    mov word [cur_dir_cluster], 0
    mov si, auth_fname
    call fat_find
    jc .no_existing
    mov byte [di], 0xE5     ; mark entry as deleted
    call fat_save_dir

.no_existing:
    ; Reload directory and find a free slot
    call fat_load_dir
    call fat_find_free_slot
    cmp di, 0xFFFF
    je .done

    push di                 ; save free slot pointer

    ; Allocate a cluster
    call fat_alloc_cluster
    cmp ax, 0xFFFF
    je .err_pop

    ; Mark cluster as end-of-chain in FAT
    push ax
    mov bx, 0x0FFF
    call fat_set_entry
    pop ax

    ; Write FILE_BUF to that cluster
    push ax                 ; save cluster number
    call cluster_to_lba
    push ds
    pop es
    mov bx, FILE_BUF
    call disk_write_sector
    pop ax                  ; restore cluster number

    pop di                  ; restore free slot pointer

    ; --- Build directory entry ---
    push ds
    pop es
    push si
    push di
    mov si, auth_fname
    mov cx, 11
    rep movsb               ; copy 8.3 name (DI advances 11, then restored)
    pop di
    pop si

    mov byte [di + 11], 0x20    ; archive attribute
    xor bx, bx
    mov [di + 12], bx
    mov [di + 14], bx
    mov [di + 16], bx
    mov [di + 18], bx
    mov [di + 20], bx
    mov [di + 22], bx
    mov [di + 24], bx
    mov [di + 26], ax           ; starting cluster
    mov word [di + 28], 4 + AUTH_USER_MAX + AUTH_PASS_MAX   ; file size
    mov [di + 30], bx

    call fat_save_dir
    call fat_save_fat
    jmp .done

.err_pop:
    pop di                  ; clean up saved slot pointer

.done:
    pop es
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret
