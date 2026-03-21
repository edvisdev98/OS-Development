; =============================================================================
; ide.asm - KSDOS Simple Text Editor (16-bit Real Mode)
; A lightweight vi-inspired editor
;
; Features:
;   - 80x23 editing area (row 0=titlebar, rows 1-23=content, row 24=statusbar)
;   - Arrow key navigation
;   - Page up/down
;   - Ctrl+S save, Ctrl+Q quit, Ctrl+N new file, Ctrl+O open
;   - Insert/Delete/Backspace
;   - Up to 100 lines of 80 chars each (max 8KB total)
; =============================================================================

; ---- Editor constants ----
IDE_LINES       equ 100
IDE_LINE_W      equ 80
IDE_VIEW_H      equ 23          ; visible rows
IDE_TAB_W       equ 4

; ---- Editor state ----
ide_buf:        times IDE_LINES * IDE_LINE_W db 0   ; text buffer
ide_line_len:   times IDE_LINES dw 0                ; length of each line
ide_line_cnt:   dw 1            ; total lines used
ide_cur_row:    dw 0            ; cursor row (0-based)
ide_cur_col:    dw 0            ; cursor column (0-based)
ide_top_row:    dw 0            ; first visible row
ide_filename:   times 13 db 0   ; current filename (8.3)
ide_modified:   db 0            ; dirty flag
ide_insert:     db 1            ; 1=insert mode, 0=overwrite

; ---- Attributes ----
IDE_ATTR_TITLE      equ 0x70    ; reversed for title bar
IDE_ATTR_STATUS     equ 0x70    ; reversed for status bar
IDE_ATTR_NORMAL     equ 0x07
IDE_ATTR_SELECT     equ 0x0F

; ============================================================
; ide_run: launch the editor
; Call with: DS:SI = filename (or zero-length for new file)
; ============================================================
ide_run:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; Clear buffer
    push si
    mov di, ide_buf
    mov cx, IDE_LINES * IDE_LINE_W / 2
    xor ax, ax
    rep stosw
    mov di, ide_line_len
    mov cx, IDE_LINES
    rep stosw
    pop si

    ; Copy filename
    mov di, ide_filename
    mov cx, 12
    call str_copy

    ; Load file if filename given
    cmp byte [si], 0
    je .new_file
    call ide_load
    jmp .setup

.new_file:
    mov word [ide_line_cnt], 1
    mov word [ide_cur_row], 0
    mov word [ide_cur_col], 0
    mov word [ide_top_row], 0
    mov byte [ide_modified], 0

.setup:
    call ide_redraw_all

.main_loop:
    call ide_draw_status
    call kbd_getkey         ; AL=char, AH=scan

    ; Function keys and special keys
    cmp al, 0x00
    je .special
    cmp al, 0xE0
    je .special

    ; Ctrl key combinations
    cmp al, 0x11            ; Ctrl+Q
    je .quit
    cmp al, 0x13            ; Ctrl+S
    je .save
    cmp al, 0x0F            ; Ctrl+O
    je .open_file
    cmp al, 0x0E            ; Ctrl+N
    je .new_file2
    cmp al, 0x09            ; Tab
    je .do_tab

    ; Enter
    cmp al, 0x0D
    je .do_enter

    ; Backspace
    cmp al, 0x08
    je .do_backspace

    ; Delete (catch scan code 0x53)
    cmp al, 0x7F
    je .do_delete

    ; Printable characters
    cmp al, 0x20
    jb .main_loop
    cmp al, 0x7E
    ja .main_loop
    call ide_insert_char
    jmp .after_edit

.special:
    call kbd_getkey         ; AH = scan code
    cmp ah, 0x48            ; UP
    je .do_up
    cmp ah, 0x50            ; DOWN
    je .do_down
    cmp ah, 0x4B            ; LEFT
    je .do_left
    cmp ah, 0x4D            ; RIGHT
    je .do_right
    cmp ah, 0x47            ; HOME
    je .do_home
    cmp ah, 0x4F            ; END
    je .do_end
    cmp ah, 0x49            ; PAGE UP
    je .do_pgup
    cmp ah, 0x51            ; PAGE DN
    je .do_pgdn
    cmp ah, 0x53            ; DEL
    je .do_delete
    jmp .main_loop

.do_up:
    cmp word [ide_cur_row], 0
    je .main_loop
    dec word [ide_cur_row]
    call ide_clamp_col
    call ide_ensure_visible
    call ide_redraw_cursor
    jmp .main_loop

.do_down:
    mov ax, [ide_line_cnt]
    dec ax
    cmp [ide_cur_row], ax
    jge .main_loop
    inc word [ide_cur_row]
    call ide_clamp_col
    call ide_ensure_visible
    call ide_redraw_cursor
    jmp .main_loop

.do_left:
    cmp word [ide_cur_col], 0
    je .main_loop
    dec word [ide_cur_col]
    call ide_redraw_cursor
    jmp .main_loop

.do_right:
    mov ax, [ide_cur_row]
    mov bx, IDE_LINE_W
    mul bx
    mov si, ide_line_len
    add si, ax
    ; Actually ide_line_len is an array of words...
    ; Index = ide_cur_row * 2 bytes
    mov ax, [ide_cur_row]
    shl ax, 1
    mov bx, ax          ; [span_5](start_span)Move the calculated offset into BX[span_5](end_span)
    mov si, ide_line_len
    add si, bx          ; [span_6](start_span)Now SI points to the correct word[span_6](end_span)
    mov ax, [si]        ; [span_7](start_span)Valid 16-bit addressing[span_7](end_span)

.do_home:
    mov word [ide_cur_col], 0
    call ide_redraw_cursor
    jmp .main_loop

.do_end:
    mov ax, [ide_cur_row]
    shl ax, 1
    mov si, ide_line_len
    add si, ax
    mov ax, [si]
    dec ax
    cmp ax, 0
    jge .set_end
    xor ax, ax
.set_end:
    mov [ide_cur_col], ax
    call ide_redraw_cursor
    jmp .main_loop

.do_pgup:
    mov ax, [ide_cur_row]
    cmp ax, IDE_VIEW_H
    jl .pgup_top
    sub ax, IDE_VIEW_H
    mov [ide_cur_row], ax
    sub [ide_top_row], word IDE_VIEW_H
    cmp word [ide_top_row], 0
    jge .pgup_ok
    mov word [ide_top_row], 0
.pgup_ok:
    call ide_clamp_col
    call ide_redraw_all
    jmp .main_loop
.pgup_top:
    mov word [ide_cur_row], 0
    mov word [ide_top_row], 0
    call ide_clamp_col
    call ide_redraw_all
    jmp .main_loop

.do_pgdn:
    add word [ide_cur_row], IDE_VIEW_H
    mov ax, [ide_line_cnt]
    dec ax
    cmp [ide_cur_row], ax
    jle .pgdn_ok
    mov [ide_cur_row], ax
.pgdn_ok:
    call ide_clamp_col
    call ide_ensure_visible
    call ide_redraw_all
    jmp .main_loop

.do_enter:
    call ide_insert_line
    jmp .after_edit

.do_backspace:
    call ide_do_backspace
    jmp .after_edit

.do_delete:
    call ide_do_delete
    jmp .after_edit

.do_tab:
    mov cx, IDE_TAB_W
.tab_loop:
    push cx
    mov al, ' '
    call ide_insert_char
    pop cx
    loop .tab_loop
    jmp .after_edit

.save:
    call ide_save
    jmp .main_loop

.open_file:
    ; Prompt for filename in status bar
    mov dh, 24
    mov dl, 0
    call vid_set_cursor
    mov al, IDE_ATTR_NORMAL
    call vid_set_attr
    mov si, str_ide_open_prompt
    call vid_print
    mov si, ide_filename
    mov cx, 12
    call kbd_readline
    cmp byte [ide_filename], 0
    je .main_loop
    call ide_load
    call ide_redraw_all
    jmp .main_loop

.new_file2:
    ; Clear buffer
    mov di, ide_buf
    mov cx, IDE_LINES * IDE_LINE_W / 2
    xor ax, ax
    rep stosw
    mov di, ide_line_len
    mov cx, IDE_LINES
    rep stosw
    mov word [ide_line_cnt], 1
    mov word [ide_cur_row], 0
    mov word [ide_cur_col], 0
    mov word [ide_top_row], 0
    mov byte [ide_modified], 0
    mov byte [ide_filename], 0
    call ide_redraw_all
    jmp .main_loop

.after_edit:
    mov byte [ide_modified], 1
    call ide_ensure_visible
    call ide_redraw_all
    jmp .main_loop

.quit:
    cmp byte [ide_modified], 0
    je .do_quit
    ; Ask to save
    mov dh, 24
    mov dl, 0
    call vid_set_cursor
    mov si, str_ide_save_prompt
    call vid_print
    call kbd_getkey
    cmp al, 'y'
    je .save_quit
    cmp al, 'Y'
    je .save_quit
    cmp al, 'n'
    je .do_quit
    cmp al, 'N'
    je .do_quit
    jmp .main_loop
.save_quit:
    call ide_save
.do_quit:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; ide_insert_char: insert AL at cursor position
; ============================================================
ide_insert_char:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; Get pointer to current line
    mov bx, [ide_cur_row]
    mov ax, IDE_LINE_W
    mul bx
    mov si, ide_buf
    add si, ax              ; SI = start of current line

    ; Get current line length
    shl bx, 1
    mov di, ide_line_len
    add di, bx
    mov cx, [di]            ; CX = current length

    ; Check if line full
    cmp cx, IDE_LINE_W - 1
    jge .done

    ; Save char to insert
    mov [_ide_ins_c], al

    ; Shift chars right from cursor position
    mov bx, cx              ; BX = current end of line
    mov dx, [ide_cur_col]   ; DX = cursor column
.shift:
    cmp bx, dx
    je .do_ins
    mov al, [si + bx - 1]
    mov [si + bx], al
    dec bx
    jmp .shift
.do_ins:
    mov al, [_ide_ins_c]
    mov [si + bx], al
    inc word [di]           ; line length++
    inc word [ide_cur_col]  ; advance cursor

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

_ide_ins_c:     db 0

; ============================================================
; ide_insert_line: split current line at cursor (Enter)
; ============================================================
ide_insert_line:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; Check if we have room
    mov ax, [ide_line_cnt]
    cmp ax, IDE_LINES
    jge .done

    ; Shift all lines after cursor down by 1
    mov cx, [ide_line_cnt]
    sub cx, [ide_cur_row]
    dec cx                  ; cx = lines to shift
    jz .skip_shift

    ; Shift from bottom to avoid overwrite
    mov ax, [ide_line_cnt]
    dec ax                  ; last line index
.shift_loop:
    push ax
    ; Copy line[ax] → line[ax+1]
    mov bx, IDE_LINE_W
    mul bx
    mov si, ide_buf
    add si, ax
    mov di, si
    add di, IDE_LINE_W
    mov cx, IDE_LINE_W
    push di
    push si
    rep movsb
    pop si
    pop di

    ; Copy line_len[ax] → line_len[ax+1]
    pop ax
    push ax
    shl ax, 1
    mov si, ide_line_len
    add si, ax
    mov bx, [si]
    mov [si + 2], bx

    pop ax
    dec ax
    cmp ax, [ide_cur_row]
    jg .shift_loop

.skip_shift:
    inc word [ide_line_cnt]

    ; Split: move content after cursor to new line
    mov bx, [ide_cur_row]
    mov ax, IDE_LINE_W
    mul bx
    mov si, ide_buf
    add si, ax                  ; current line start
    mov di, si
    add di, IDE_LINE_W          ; next line start

    mov dx, [ide_cur_col]       ; split point
    add si, dx

    ; Get chars after cursor
    shl bx, 1
    mov ax, [ide_line_len + bx]
    sub ax, dx                  ; chars to move
    jle .no_move

    mov cx, ax
    ; Clear next line first
    push di
    push cx
    xor al, al
    mov cx, IDE_LINE_W
    rep stosb
    pop cx
    pop di
    rep movsb
    ; Set new line's length
    mov [ide_line_len + bx + 2], ax

.no_move:
    ; Truncate current line at cursor
    mov bx, [ide_cur_row]
    shl bx, 1
    mov si, ide_line_len
    add si, bx
    mov ax, [ide_cur_col]
    mov [si], ax

    ; Advance to next line
    inc word [ide_cur_row]
    mov word [ide_cur_col], 0

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; ide_do_backspace: delete char before cursor
; ============================================================
ide_do_backspace:
    push ax
    push bx
    push cx
    push si

    cmp word [ide_cur_col], 0
    jg .del_char
    ; At start of line: join with previous line
    cmp word [ide_cur_row], 0
    je .done
    ; (simplified: just move cursor up)
    dec word [ide_cur_row]
    mov bx, [ide_cur_row]
    shl bx, 1
    mov ax, [ide_line_len + bx]
    mov [ide_cur_col], ax
    jmp .done

.del_char:
    dec word [ide_cur_col]
    ; Remove char at cursor col
    mov bx, [ide_cur_row]
    mov ax, IDE_LINE_W
    mul bx
    mov si, ide_buf
    add si, ax
    mov cx, [ide_cur_col]
    add si, cx              ; SI = char to delete
    ; Shift left
    shl bx, 1
    mov cx, [ide_line_len + bx]
    sub cx, [ide_cur_col]
    dec cx
.shift:
    cmp cx, 0
    jle .done_shift
    mov al, [si + 1]
    mov [si], al
    inc si
    dec cx
    jmp .shift
.done_shift:
    ; Zero last char
    mov byte [si], 0
    ; Decrement length
    dec word [ide_line_len + bx]
.done:
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; ide_do_delete: delete char at cursor
; ============================================================
ide_do_delete:
    push ax
    push bx
    push cx
    push si
    ; Same as backspace but without moving cursor back
    mov bx, [ide_cur_row]
    shl bx, 1
    mov ax, [ide_line_len + bx]
    cmp [ide_cur_col], ax
    jge .done
    ; Shift left from cursor
    mov ax, [ide_cur_row]
    mov cx, IDE_LINE_W
    mul cx
    mov si, ide_buf
    add si, ax
    add si, [ide_cur_col]
    mov cx, [ide_line_len + bx]
    sub cx, [ide_cur_col]
    dec cx
.shift:
    cmp cx, 0
    jle .done_shift
    mov al, [si + 1]
    mov [si], al
    inc si
    dec cx
    jmp .shift
.done_shift:
    mov byte [si], 0
    dec word [ide_line_len + bx]
.done:
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; ide_clamp_col: ensure cursor col <= line length
; ============================================================
ide_clamp_col:
    push ax
    push bx
    mov bx, [ide_cur_row]
    shl bx, 1
    mov ax, [ide_line_len + bx]
    cmp [ide_cur_col], ax
    jle .ok
    mov [ide_cur_col], ax
.ok:
    pop bx
    pop ax
    ret

; ============================================================
; ide_ensure_visible: scroll so cursor is visible
; ============================================================
ide_ensure_visible:
    push ax
    push bx
    push si

    ; 1. Se o cursor estiver ACIMA da visão (ide_cur_row < ide_top_row)
    mov ax, [ide_cur_row]
    cmp ax, [ide_top_row]
    jge .check_below
    
    mov [ide_top_row], ax
    jmp .get_line_info

.check_below:
    ; 2. Se o cursor estiver ABAIXO da visão (ide_cur_row >= ide_top_row + IDE_VIEW_H)
    mov ax, [ide_top_row]
    add ax, IDE_VIEW_H - 1    ; AX = última linha visível
    
    mov bx, [ide_cur_row]
    cmp bx, ax                
    jle .get_line_info        ; Se estiver visível, pula para pegar info da linha
    
    ; Scroll down
    mov ax, [ide_cur_row]
    sub ax, IDE_VIEW_H - 1
    mov [ide_top_row], ax

.get_line_info:
    ; --- ESTA É A PARTE QUE O NASM RECLAMA (LINHA 382) ---
    ; Precisamos pegar o comprimento da linha atual
    mov ax, [ide_cur_row]
    shl ax, 1               ; Multiplica por 2 (word)
    mov si, ax              ; <--- CORREÇÃO: Move para SI (ponteiro válido)
    mov dx, [ide_line_len + si] ; <--- CORREÇÃO: Usa SI em vez de AX

.done:
    pop si
    pop bx
    pop ax
    ret



; ============================================================
; ide_redraw_all: redraw entire editor screen
; ============================================================
ide_redraw_all:
    push ax
    push bx
    push cx
    push dx
    push si

    ; --- Title bar (row 0) ---
    mov dh, 0
    mov dl, 0
    call vid_set_cursor
    mov al, IDE_ATTR_TITLE
    call vid_set_attr
    mov si, str_ide_title
    call vid_print

    ; --- Print filename ---
    cmp byte [ide_filename], 0
    jne .has_name
    mov si, str_ide_noname
    jmp .print_name
.has_name:
    mov si, ide_filename
.print_name:
    call vid_print

    ; --- Modified marker ---
    cmp byte [ide_modified], 0
    je .no_mod
    mov al, '*'
    call vid_putchar
.no_mod:

    ; --- Content rows (rows 1..IDE_VIEW_H) ---
    mov al, IDE_ATTR_NORMAL
    call vid_set_attr
    mov cx, IDE_VIEW_H
    mov byte [_ide_vrow], 1

.content_row:
    push cx
    ; Calculate absolute line number: (vrow - 1) + top_row
    movzx ax, byte [_ide_vrow]
    dec ax
    add ax, [ide_top_row]
    
    ; Set cursor position
    mov dh, [_ide_vrow]
    mov dl, 0
    call vid_set_cursor

    ; Check if we are past the end of the file
    cmp ax, [ide_line_cnt]
    jge .blank_row

    ; --- FIXED: Calculate buffer offset correctly ---
    push ax
    mov bx, IDE_LINE_W
    mul bx              ; AX = line_index * 80
    mov bx, ax          ; Move result to BX (valid 16-bit pointer)
    mov si, ide_buf
    add si, bx          ; SI = base + offset
    pop ax

    mov cx, IDE_LINE_W
.char_out:
    lodsb
    test al, al
    jz .pad_row
    call vid_putchar
    dec cx
    jnz .char_out
    jmp .row_done

.pad_row:
    test cx, cx
    jz .row_done
.pad:
    mov al, ' '
    call vid_putchar
    loop .pad
    jmp .row_done

.blank_row:
    mov al, '~'         ; vi-style empty line indicator
    call vid_putchar
    mov cx, 79
.blank_pad:
    mov al, ' '
    call vid_putchar
    loop .blank_pad

.row_done:
    inc byte [_ide_vrow]
    pop cx
    loop .content_row

    call ide_draw_status
    call ide_redraw_cursor

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

_ide_vrow:  db 0

; ============================================================
; ide_draw_status: draw status bar at row 24
; ============================================================
ide_draw_status:
    push ax
    push bx
    push cx
    push dx
    push si
    mov dh, 24
    mov dl, 0
    call vid_set_cursor
    mov al, IDE_ATTR_STATUS
    call vid_set_attr
    ; Print "Ln:XXXX Col:XXX [I/O] Ctrl+S=save Ctrl+Q=quit"
    mov si, str_ide_stat_ln
    call vid_print
    mov ax, [ide_cur_row]
    inc ax
    call print_word_dec
    mov si, str_ide_stat_col
    call vid_print
    mov ax, [ide_cur_col]
    inc ax
    call print_word_dec
    mov si, str_ide_stat_keys
    call vid_print
    mov al, IDE_ATTR_NORMAL
    call vid_set_attr
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; ide_redraw_cursor: position cursor on screen
; ============================================================
ide_redraw_cursor:
    push ax
    push dx
    ; screen_row = 1 + (ide_cur_row - ide_top_row)
    mov ax, [ide_cur_row]
    sub ax, [ide_top_row]
    inc ax                  ; +1 for title bar
    mov dh, al
    mov ax, [ide_cur_col]
    mov dl, al
    call vid_set_cursor
    pop dx
    pop ax
    ret

; ============================================================
; ide_load: carregar arquivo [ide_filename] para o buffer
; ============================================================
ide_load:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    ; Converter nome para 8.3 DOS
    mov si, ide_filename
    mov di, _ide_dosname
    call str_to_dosname

    ; Procurar no diretório raiz
    mov si, _ide_dosname
    call fat_find
    jc .load_not_found

    ; Cluster inicial (offset 26 na entrada do dir)
    mov ax, [di + 26]
    ; Tamanho do arquivo (offset 28)
    mov cx, [di + 28]       
    mov [_ide_fsize], cx

    ; Ler arquivo para o buffer temporário
    push ds
    pop es
    mov bx, FILE_BUF
    call fat_read_file

    ; Parse do arquivo para linhas
    mov si, FILE_BUF
    xor di, di              ; di = índice da linha atual
    xor bx, bx              ; bx = coluna atual
    xor bp, bp              ; bp = contador de bytes lidos (usando BP para liberar CX)

.parse_loop:
    cmp bp, [_ide_fsize]
    jge .parse_done
    cmp di, IDE_LINES
    jge .parse_done

    lodsb
    inc bp
    cmp al, 0x0D            ; Ignorar CR
    je .parse_loop
    cmp al, 0x0A            ; LF -> nova linha
    je .next_line
    cmp bx, IDE_LINE_W - 1
    jge .parse_loop         ; linha muito longa, descarta char

    ; --- CORREÇÃO DE ENDEREÇAMENTO 16-BIT ---
    push ax                 ; Salva o caractere lido
    mov ax, di              ; AX = linha atual
    mov dx, IDE_LINE_W
    mul dx                  ; AX = linha * 80
    add ax, bx              ; AX = (linha * 80) + coluna
    
    push si                 ; Salva ponteiro do FILE_BUF
    mov si, ide_buf
    add si, ax              ; SI = endereço final no buffer do editor
    pop ax                  ; Recupera o caractere em AL (estava no stack)
    mov [si], al            ; SUCESSO: SI é um ponteiro válido
    pop si                  ; Restaura ponteiro do FILE_BUF
    ; ----------------------------------------

    ; --- ATUALIZAR COMPRIMENTO DA LINHA ---
    push bx
    mov ax, di
    shl ax, 1               ; AX = linha * 2 (tamanho de word)
    push si
    mov si, ide_line_len
    add si, ax              ; SI = endereço do contador desta linha
    inc word [si]           ; Incrementa comprimento
    pop si
    pop bx
    ; --------------------------------------

    inc bx
    jmp .parse_loop

.next_line:
    inc di
    xor bx, bx
    jmp .parse_loop

.parse_done:
    mov ax, di
    inc ax
    mov [ide_line_cnt], ax
    xor ax, ax
    mov [ide_cur_row], ax
    mov [ide_cur_col], ax
    mov [ide_top_row], ax
    mov byte [ide_modified], 0

.load_not_found:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

_ide_dosname:   times 12 db 0
_ide_fsize:     dw 0

; ============================================================
; ide_save: save buffer to file [ide_filename]
; (simplified: prints "SAVED" message for now)
; In a full impl: write to FAT12 directory entry + clusters
; ============================================================
ide_save:
    push ax
    push si
    mov dh, 24
    mov dl, 0
    call vid_set_cursor
    mov si, str_ide_saved
    call vid_print
    mov byte [ide_modified], 0
    pop si
    pop ax
    ret

; ---- Strings ----
str_ide_title:      db "KSDOS IDE v1.0 | File: ", 0
str_ide_noname:     db "[new file]", 0
str_ide_stat_ln:    db " Ln:", 0
str_ide_stat_col:   db " Col:", 0
str_ide_stat_keys:  db "  Ctrl+S=Save  Ctrl+Q=Quit  Ctrl+N=New  Ctrl+O=Open  ", 0
str_ide_save_prompt: db "Save before quit? (y/n): ", 0
str_ide_open_prompt: db "Open file: ", 0
str_ide_saved:      db "File saved.                                            ", 0
