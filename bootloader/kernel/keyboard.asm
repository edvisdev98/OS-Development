; =============================================================================
; keyboard.asm - Keyboard driver (INT 16h)
; 16-bit real mode
; =============================================================================

HIST_MAX    equ 10
HIST_SZ     equ 80

; History buffer
kbd_hist:       times HIST_MAX * HIST_SZ db 0
kbd_hist_n:     dw 0        ; number of valid entries (max HIST_MAX)

; Readline state (set before calling kbd_readline)
rl_buf_ptr:     dw 0        ; offset of user's buffer
rl_max_len:     dw 0        ; max chars (including null)
rl_row:         db 0        ; starting row
rl_col:         db 0        ; starting column
rl_len:         dw 0        ; current length
rl_hidx:        db 0xFF     ; history index (0xFF = no history selected)

; ---- kbd_getkey: wait for key, return AL=ASCII, AH=scancode ----
kbd_getkey:
    push bx
    xor ah, ah
    int 0x16
    pop bx
    ret

; ---- kbd_check: check if key available (ZF=0 if yes) ----
kbd_check:
    push ax
    mov ah, 0x01
    int 0x16
    pop ax
    ret

; ---- kbd_readline: read line of text into buffer ----
; Call with: SI = buffer, CX = max length
; Returns: nothing; buffer null-terminated
kbd_readline:
    ; Save parameters
    mov [rl_buf_ptr], si
    mov [rl_max_len], cx
    mov word [rl_len], 0
    mov byte [rl_hidx], 0xFF

    ; Get starting cursor position
    call vid_get_cursor
    mov [rl_row], dh
    mov [rl_col], dl

.main_loop:
    call kbd_getkey         ; AL=ASCII, AH=scancode

    ; Enter
    cmp al, 0x0D
    je .enter

    ; Backspace
    cmp al, 0x08
    je .backspace

    ; Special key (AL=0 or AL=0xE0)
    cmp al, 0x00
    je .special
    cmp al, 0xE0
    je .special2

    ; Printable?
    cmp al, 0x20
    jb .main_loop
    cmp al, 0x7E
    ja .main_loop

    ; Add char if room
    mov bx, [rl_max_len]
    dec bx
    cmp [rl_len], bx
    jge .main_loop

    ; Store char and echo
    push ax
    mov bx, [rl_buf_ptr]
    add bx, [rl_len]
    pop ax
    mov [bx], al
    inc word [rl_len]
    call vid_putchar
    jmp .main_loop

.backspace:
    cmp word [rl_len], 0
    je .main_loop
    dec word [rl_len]
    ; Clear char on screen
    call vid_get_cursor
    cmp dl, 0
    je .main_loop
    dec dl
    call vid_set_cursor
    mov al, ' '
    call vid_putchar
    call vid_get_cursor
    dec dl
    call vid_set_cursor
    jmp .main_loop

.special:
    cmp ah, 0x48            ; UP arrow
    je .hist_up
    cmp ah, 0x50            ; DOWN arrow
    je .hist_down
    jmp .main_loop

.special2:
    ; Extended key prefix, next key gives scan
    call kbd_getkey
    cmp ah, 0x48
    je .hist_up
    cmp ah, 0x50
    je .hist_down
    jmp .main_loop

.hist_up:
    ; Go to older history
    cmp byte [rl_hidx], 0xFF
    je .hist_first
    mov al, [rl_hidx]
    cmp al, [kbd_hist_n]
    jae .main_loop
    inc byte [rl_hidx]
    jmp .hist_load
.hist_first:
    cmp word [kbd_hist_n], 0
    je .main_loop
    mov byte [rl_hidx], 0
.hist_load:
    call _rl_clear_line
    ; Copy history[hidx] into buffer
    mov bx, HIST_SZ
    movzx ax, byte [rl_hidx]
    mul bx
    mov si, kbd_hist
    add si, ax
    mov di, [rl_buf_ptr]
    xor cx, cx
.hist_copy:
    lodsb
    stosb
    test al, al
    jz .hist_copy_done
    inc cx
    call vid_putchar
    jmp .hist_copy
.hist_copy_done:
    dec cx                  ; don't count null
    ; cx might be negative if buffer was empty
    cmp cx, 0xFFFF
    je .hist_empty
    mov [rl_len], cx
    jmp .main_loop
.hist_empty:
    mov word [rl_len], 0
    jmp .main_loop

.hist_down:
    cmp byte [rl_hidx], 0xFF
    je .main_loop
    cmp byte [rl_hidx], 0
    je .hist_clear
    dec byte [rl_hidx]
    jmp .hist_load
.hist_clear:
    mov byte [rl_hidx], 0xFF
    call _rl_clear_line
    mov word [rl_len], 0
    jmp .main_loop

.enter:
    ; Null-terminate buffer
    mov bx, [rl_buf_ptr]
    add bx, [rl_len]
    mov byte [bx], 0
    call vid_nl
    ; Push to history if non-empty
    cmp word [rl_len], 0
    je .done
    call _hist_push
.done:
    ret

; Clear current input from screen and reset position
_rl_clear_line:
    push ax
    push bx
    push cx
    push dx
    ; Go to start of input
    mov dh, [rl_row]
    mov dl, [rl_col]
    call vid_set_cursor
    ; Overwrite with spaces
    mov cx, [rl_len]
    test cx, cx
    jz .done
.clr:
    mov al, ' '
    call vid_putchar
    loop .clr
    ; Return cursor to start
    mov dh, [rl_row]
    mov dl, [rl_col]
    call vid_set_cursor
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Push current buffer to history (shift down, add at 0)
_hist_push:
    push ax
    push bx
    push cx
    push si
    push di
    ; Shift all entries down one slot
    mov ax, [kbd_hist_n]
    cmp ax, HIST_MAX
    jae .capped
    inc word [kbd_hist_n]
    mov ax, [kbd_hist_n]
.capped:
    ; Shift entries 0..n-2 → 1..n-1
    mov cx, HIST_MAX - 1
.shift:
    test cx, cx
    jz .done_shift
    ; hist[cx] = hist[cx-1]
    mov ax, HIST_SZ
    mul cl
    mov di, kbd_hist
    add di, ax
    sub di, HIST_SZ         ; di = &hist[cx-1]  -- wait, actually mul al=HIST_SZ, cx=index
    ; di = kbd_hist + cx * HIST_SZ
    push cx
    movzx ax, cl
    mov bx, HIST_SZ
    mul bx
    mov di, kbd_hist
    add di, ax
    ; si = kbd_hist + (cx-1) * HIST_SZ
    dec cx
    movzx ax, cl
    mul bx
    mov si, kbd_hist
    add si, ax
    mov cx, HIST_SZ
    rep movsb
    pop cx
    dec cx
    jnz .shift
.done_shift:
    ; Copy buffer to hist[0]
    mov si, [rl_buf_ptr]
    mov di, kbd_hist
    mov cx, HIST_SZ
    rep movsb
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret
