; =============================================================================
; string.asm - String utility functions
; All 16-bit real mode, BITS 16
; =============================================================================

; --------------------------------------------------------
; str_len: AX = length of null-terminated string at DS:SI
; --------------------------------------------------------
str_len:
    push si
    push di
    mov di, si
.loop:
    cmp byte [di], 0
    je .done
    inc di
    jmp .loop
.done:
    mov ax, di
    sub ax, si
    pop di
    pop si
    ret

; --------------------------------------------------------
; str_copy: copy DS:SI to DS:DI (null-terminated)
; Trashes: AL
; --------------------------------------------------------
str_copy:
    push si
    push di
.loop:
    lodsb
    stosb
    test al, al
    jnz .loop
    pop di
    pop si
    ret

; --------------------------------------------------------
; str_cmp: compare DS:SI and DS:DI (case-sensitive)
; Returns: ZF=1 equal, ZF=0 not equal
; --------------------------------------------------------
str_cmp:
    push ax
    push si
    push di
.loop:
    mov al, [si]
    cmp al, [di]
    jne .ne
    inc si
    inc di
    test al, al
    jnz .loop
    ; equal
    pop di
    pop si
    pop ax
    xor ax, ax      ; ZF=1
    ret
.ne:
    pop di
    pop si
    pop ax
    or ax, 1        ; ZF=0
    ret

; --------------------------------------------------------
; str_cmp_ic: case-insensitive compare DS:SI and DS:DI
; Returns: ZF=1 equal
; --------------------------------------------------------
str_cmp_ic:
    push ax
    push bx
    push si
    push di
.loop:
    mov al, [si]
    mov bl, [di]
    call _uc_al
    push ax
    mov al, bl
    call _uc_al
    mov bl, al
    pop ax
    cmp al, bl
    jne .ne
    inc si
    inc di
    test al, al
    jnz .loop
    pop di
    pop si
    pop bx
    pop ax
    xor ax, ax
    ret
.ne:
    pop di
    pop si
    pop bx
    pop ax
    or ax, 1
    ret

; --------------------------------------------------------
; char_upcase: uppercase AL
; --------------------------------------------------------
char_upcase:
    cmp al, 'a'
    jb .done
    cmp al, 'z'
    ja .done
    sub al, 32
.done:
    ret

; Internal helper: upcase AL (same as char_upcase)
_uc_al:
    cmp al, 'a'
    jb .d
    cmp al, 'z'
    ja .d
    sub al, 32
.d: ret

; --------------------------------------------------------
; str_upcase_copy: copy DS:SI to DS:DI uppercased
; --------------------------------------------------------
str_upcase_copy:
    push ax
    push si
    push di
.loop:
    lodsb
    call _uc_al
    stosb
    test al, al
    jnz .loop
    pop di
    pop si
    pop ax
    ret

; --------------------------------------------------------
; str_ltrim: advance SI past leading spaces
; --------------------------------------------------------
str_ltrim:
.loop:
    cmp byte [si], ' '
    jne .done
    inc si
    jmp .loop
.done:
    ret

; --------------------------------------------------------
; str_get_word: extract first space-delimited word from DS:SI
;   into DS:DI (uppercased, null-terminated, max CX chars)
;   SI advances past the word and trailing space
; Preserves: CX
; --------------------------------------------------------
str_get_word:
    push ax
    push cx
    call str_ltrim
.loop:
    cmp byte [si], 0
    je .term
    cmp byte [si], ' '
    je .term
    lodsb
    call _uc_al
    stosb
    dec cx
    jnz .loop
.term:
    ; Skip trailing spaces
.skip:
    cmp byte [si], ' '
    jne .end
    inc si
    jmp .skip
.end:
    mov byte [di], 0
    pop cx
    pop ax
    ret

; --------------------------------------------------------
; str_to_dosname: convert user name DS:SI → 11-byte 8.3 DS:DI
;   (padded with spaces, uppercased, no dot separator)
; --------------------------------------------------------
str_to_dosname:
    push ax
    push cx
    push si
    push di
    ; Fill with spaces
    push di
    mov cx, 11
    mov al, ' '
    rep stosb
    pop di
    ; Name part (up to 8 chars)
    mov cx, 8
.name:
    cmp byte [si], 0
    je .done
    cmp byte [si], '.'
    je .ext
    lodsb
    call _uc_al
    stosb
    loop .name
    ; Skip rest of name until dot
.skip_name:
    cmp byte [si], 0
    je .done
    cmp byte [si], '.'
    je .ext
    inc si
    jmp .skip_name
.ext:
    cmp byte [si], '.'
    jne .done
    inc si                  ; skip '.'
    ; Reposition DI to extension (original DI + 8)
    pop di
    push di
    add di, 8
    mov cx, 3
.ext_loop:
    cmp byte [si], 0
    je .done
    lodsb
    call _uc_al
    stosb
    loop .ext_loop
.done:
    pop di
    pop si
    pop cx
    pop ax
    ret

; --------------------------------------------------------
; fat_format_name: convert 11-byte FAT entry DS:SI → printable DS:DI
;   Output: "NAME    EXT" → "NAME.EXT\0"
; --------------------------------------------------------
fat_format_name:
    push ax
    push cx
    push si
    push di
    ; Name: up to 8 chars, trim trailing spaces
    mov cx, 8
.n:
    cmp byte [si], ' '
    je .do_ext
    movsb
    loop .n
    ; Skip remaining name spaces
.skip_n:
    test cx, cx
    jz .do_ext
    cmp byte [si], ' '
    jne .skip_n2
    inc si
    dec cx
    jmp .skip_n
.skip_n2:
    add si, cx          ; skip non-space remainder
.do_ext:
    ; Skip to extension position in source
    ; SI might not be at position 8 yet
    ; We stored relative to original SI... let's recalculate
    ; Actually movsb already advanced SI correctly
    ; Now SI is past the name portion; adjust to extension
    ; Extension starts at original_si + 8
    ; We need to seek SI to original_si+8:
    ; We'll do it differently - go back to saved SI+8
    pop di
    pop si
    push si
    push di
    add si, 8           ; SI now at extension
    ; Check if extension is all spaces
    mov al, [si]
    cmp al, ' '
    je .no_ext
    ; Add dot
    mov al, '.'
    stosb
    mov cx, 3
.e:
    cmp byte [si], ' '
    je .end_ext
    movsb
    loop .e
.end_ext:
.no_ext:
    mov byte [di], 0
    pop di
    pop si
    pop cx
    pop ax
    ret

; --------------------------------------------------------
; print_hex_byte: print AL as two hex chars via vid_putchar
; --------------------------------------------------------
print_hex_byte:
    push ax
    push cx
    push ax
    shr al, 4
    and al, 0x0F
    add al, '0'
    cmp al, '9'+1
    jb .h1ok
    add al, 7
.h1ok:
    call vid_putchar
    pop ax
    and al, 0x0F
    add al, '0'
    cmp al, '9'+1
    jb .h2ok
    add al, 7
.h2ok:
    call vid_putchar
    pop cx
    pop ax
    ret

; --------------------------------------------------------
; print_word_dec: print AX as decimal
; --------------------------------------------------------
print_word_dec:
    push ax
    push bx
    push cx
    push dx
    xor cx, cx
    mov bx, 10
.div:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .div
.prt:
    pop ax
    add al, '0'
    call vid_putchar
    loop .prt
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; --------------------------------------------------------
; print_word_hex: print AX as 4 hex digits
; --------------------------------------------------------
print_word_hex:
    push ax
    push cx
    mov cx, 4
.lp:
    rol ax, 4
    push ax
    and al, 0x0F
    add al, '0'
    cmp al, '9'+1
    jb .ok
    add al, 7
.ok:
    call vid_putchar
    pop ax
    loop .lp
    pop cx
    pop ax
    ret

; --------------------------------------------------------
; print_bcd: print BCD byte AL as two decimal digits
; --------------------------------------------------------
print_bcd:
    push ax
    push bx
    mov bh, al
    shr al, 4
    add al, '0'
    call vid_putchar
    mov al, bh
    and al, 0x0F
    add al, '0'
    call vid_putchar
    pop bx
    pop ax
    ret
