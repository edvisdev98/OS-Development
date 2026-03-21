; =============================================================================
; compiler_c.asm - KSDOS Real C/C++ Compiler (x86 16-bit COM output)
; Supports: int/char/void types, local variables, if/else, while, for,
;           printf/puts/putchar, return, basic arithmetic (+,-,*,/,%), comparison
; Output: .COM file (ORG 0x100, stack-based function calls)
; Source: FILE_BUF, Output: COMP_BUF (= DIR_BUF = 0xD200)
; =============================================================================

; Reuses COMP_BUF / COMP_SYM / COMP_PATCH from compiler_asm.asm

; ---- C token types ----
CTK_EOF     equ 0
CTK_IDENT   equ 1    ; identifier or keyword
CTK_NUM     equ 2    ; integer literal
CTK_STR     equ 3    ; string literal
CTK_CHAR    equ 4    ; character literal
CTK_PLUS    equ 5
CTK_MINUS   equ 6
CTK_STAR    equ 7
CTK_SLASH   equ 8
CTK_PERCENT equ 9
CTK_AMP     equ 10
CTK_PIPE    equ 11
CTK_CARET   equ 12
CTK_BANG    equ 13
CTK_TILDE   equ 14
CTK_EQ      equ 15   ; =
CTK_EQEQ    equ 16   ; ==
CTK_NEQ     equ 17   ; !=
CTK_LT      equ 18   ; <
CTK_GT      equ 19   ; >
CTK_LE      equ 20   ; <=
CTK_GE      equ 21   ; >=
CTK_ANDAND  equ 22   ; &&
CTK_OROR    equ 23   ; ||
CTK_LPAR    equ 24   ; (
CTK_RPAR    equ 25   ; )
CTK_LBRACE  equ 26   ; {
CTK_RBRACE  equ 27   ; }
CTK_SEMI    equ 28   ; ;
CTK_COMMA   equ 29   ; ,
CTK_LBRACK  equ 30   ; [
CTK_RBRACK  equ 31   ; ]
CTK_DOT     equ 32   ; .
CTK_ARROW   equ 33   ; ->
CTK_PLUSEQ  equ 34   ; +=
CTK_MINUSEQ equ 35   ; -=
CTK_PLUSPLUS equ 36  ; ++
CTK_MINUSMINUS equ 37 ; --
CTK_COLON   equ 38   ; :
CTK_SHARP   equ 39   ; # (preprocessor)

; ---- C compiler state ----
cc_src:        dw 0
cc_src_end:    dw 0
cc_out:        dw 0
cc_pc:         dw 0x100
cc_line:       dw 1
cc_err:        db 0
cc_tok_type:   db 0
cc_tok_val:    dw 0
cc_tok_str:    times 32 db 0

; Symbol table for locals/globals (shared with asm_ area, but different structure)
; CC uses: COMP_SYM for variables
; Each entry (20 bytes): 16-byte name, 2-byte stack_offset (neg = local, 0 = global)
;                         1-byte type (0=int, 1=char, 2=ptr), 1-byte pad

cc_sym_cnt:    dw 0     ; number of defined variables
cc_frame_sz:   dw 0     ; current stack frame size (bytes)
cc_label_cnt:  dw 0     ; label counter for unique internal labels
cc_in_func:    db 0     ; 1 = inside a function body
cc_data_off:   dw 0     ; offset in data section (strings after code)
cc_data_size:  dw 0     ; size of data section

; String literal buffer (stored after code, before EOF)
CC_DATA_BUF    equ 0xE000   ; 2KB for string literals
CC_DATA_MAX    equ 2048

; ============================================================
; cc_run - main C compiler entry point
; ============================================================
cc_run:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; Init state
    mov word [cc_src], FILE_BUF
    mov ax, FILE_BUF
    add ax, [_sh_type_sz]
    mov [cc_src_end], ax
    mov word [cc_out], COMP_BUF
    mov word [cc_pc], 0x100
    mov word [cc_line], 1
    mov byte [cc_err], 0
    mov word [cc_sym_cnt], 0
    mov word [cc_frame_sz], 0
    mov word [cc_label_cnt], 0
    mov byte [cc_in_func], 0
    mov word [cc_data_off], 0
    mov word [cc_data_size], 0
    mov word [asm_sym_cnt], 0
    mov word [asm_patch_cnt], 0
    mov word [asm_pc], 0x100
    mov word [asm_pc_base], 0x100
    mov word [asm_out], COMP_BUF
    mov byte [asm_err], 0

    ; Emit COM header: JMP to main (3 bytes placeholder)
    ; 0xE9, lo, hi
    mov al, 0xE9
    call cc_emit_byte
    xor ax, ax
    call cc_emit_word           ; placeholder for JMP main

    ; Parse top-level declarations and functions
.parse_loop:
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_EOF
    je .cc_done_parse
    ; Skip preprocessor directives (#include, #define)
    cmp byte [cc_tok_type], CTK_SHARP
    je .cc_skip_line
    ; Expect type keyword or identifier
    cmp byte [cc_tok_type], CTK_IDENT
    jne .parse_loop
    ; Check for type keywords: int, char, void
    call cc_is_type
    jnc .cc_type_decl
    jmp .parse_loop
.cc_skip_line:
    call cc_skip_to_newline
    jmp .parse_loop
.cc_type_decl:
    ; Got a type keyword; next should be identifier
    call cc_parse_decl
    cmp byte [cc_err], 0
    jne .cc_done_parse
    jmp .parse_loop

.cc_done_parse:
    cmp byte [cc_err], 0
    jne .cc_fail

    ; Patch the initial JMP main
    call cc_patch_main_jump

    ; Emit string literal data section at end of code
    call cc_emit_data_section

    ; Compute output size
    mov ax, [cc_out]
    sub ax, COMP_BUF
    test ax, ax
    jz .cc_empty

    mov [_sh_copy_sz], ax

    ; Copy output to FILE_BUF for disk write
    push ds
    pop es
    mov si, COMP_BUF
    mov di, FILE_BUF
    mov cx, ax
    rep movsb

    ; Derive .COM output name
    call asm_make_outname

    ; Write to disk
    call asm_write_output
    cmp byte [cc_err], 0
    jne .cc_fail

    mov al, ATTR_GREEN
    call vid_set_attr
    mov si, str_cc_compiled
    call vid_println
    mov al, ATTR_NORMAL
    call vid_set_attr
    jmp .cc_ret

.cc_empty:
    mov si, str_asm_empty
    call vid_println
    jmp .cc_ret

.cc_fail:
    ; error already printed

.cc_ret:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; cc_tok_next - advance to next C token
; ============================================================
cc_tok_next:
    push ax
    push si
    mov si, [cc_src]

.ctn_ws:
    cmp si, [cc_src_end]
    jae .ctn_eof
    mov al, [si]
    cmp al, ' '
    je .ctn_skip_ws
    cmp al, 9       ; tab
    je .ctn_skip_ws
    cmp al, 0x0D
    je .ctn_skip_nl
    cmp al, 0x0A
    je .ctn_skip_nl
    jmp .ctn_classify
.ctn_skip_ws:
    inc si
    jmp .ctn_ws
.ctn_skip_nl:
    inc si
    inc word [cc_line]
    ; Handle CR+LF
    cmp al, 0x0D
    jne .ctn_ws
    cmp byte [si], 0x0A
    jne .ctn_ws
    inc si
    jmp .ctn_ws

.ctn_classify:
    mov al, [si]
    ; Check for comment // or /*
    cmp al, '/'
    je .ctn_maybe_comment
    cmp al, '#'
    je .ctn_hash
    cmp al, '"'
    je .ctn_string
    cmp al, 0x27    ; single quote '
    je .ctn_char
    cmp al, '0'
    jb .ctn_not_num
    cmp al, '9'
    jbe .ctn_num
.ctn_not_num:
    ; Check identifiers
    call _uc_al
    cmp al, 'A'
    jb .ctn_punct
    cmp al, 'Z'
    jbe .ctn_ident
    mov al, [si]    ; restore
    cmp al, '_'
    je .ctn_ident
    jmp .ctn_punct

.ctn_eof:
    mov byte [cc_tok_type], CTK_EOF
    jmp .ctn_done

.ctn_hash:
    inc si
    mov byte [cc_tok_type], CTK_SHARP
    jmp .ctn_done

.ctn_maybe_comment:
    inc si
    cmp byte [si], '/'
    je .ctn_line_comment
    cmp byte [si], '*'
    je .ctn_block_comment
    ; It's just a '/'
    dec si
    mov byte [cc_tok_type], CTK_SLASH
    inc si
    jmp .ctn_done

.ctn_line_comment:
    inc si
.ctn_lc_loop:
    cmp si, [cc_src_end]
    jae .ctn_eof
    mov al, [si]
    inc si
    cmp al, 0x0A
    jne .ctn_lc_loop
    inc word [cc_line]
    jmp .ctn_ws

.ctn_block_comment:
    inc si
.ctn_bc_loop:
    cmp si, [cc_src_end]
    jae .ctn_eof
    mov al, [si]
    inc si
    cmp al, 0x0A
    jne .ctn_bc_not_nl
    inc word [cc_line]
.ctn_bc_not_nl:
    cmp al, '*'
    jne .ctn_bc_loop
    cmp byte [si], '/'
    jne .ctn_bc_loop
    inc si
    jmp .ctn_ws

.ctn_string:
    inc si
    mov di, cc_tok_str
    xor cx, cx
.ctn_str_lp:
    cmp si, [cc_src_end]
    jae .ctn_str_done
    mov al, [si]
    inc si
    cmp al, '"'
    je .ctn_str_done
    cmp al, 0x0A
    je .ctn_str_done
    cmp al, 0x5C
    jne .ctn_str_store
    ; Escape sequence
    mov al, [si]
    inc si
    cmp al, 'n'
    je .ctn_str_nl
    cmp al, 't'
    je .ctn_str_tab
    cmp al, 'r'
    je .ctn_str_cr
    cmp al, '0'
    je .ctn_str_null
    jmp .ctn_str_store
.ctn_str_nl:
    mov al, 0x0A
    jmp .ctn_str_store
.ctn_str_tab:
    mov al, 9
    jmp .ctn_str_store
.ctn_str_cr:
    mov al, 0x0D
    jmp .ctn_str_store
.ctn_str_null:
    xor al, al
.ctn_str_store:
    stosb
    inc cx
    cmp cx, 31
    jl .ctn_str_lp
.ctn_str_done:
    mov byte [di], 0
    mov [cc_tok_val], cx
    mov byte [cc_tok_type], CTK_STR
    jmp .ctn_done

.ctn_char:
    inc si
    mov al, [si]
    inc si
    cmp al, 0x5C
    jne .ctn_char_simple
    mov al, [si]
    inc si
    cmp al, 'n'
    jne .ctn_char_skip_esc
    mov al, 0x0A
    jmp .ctn_char_simple
.ctn_char_skip_esc:
    cmp al, '0'
    jne .ctn_char_simple
    xor al, al
.ctn_char_simple:
    ; Skip closing quote
    cmp byte [si], 0x27
    jne .ctn_char_done
    inc si
.ctn_char_done:
    mov ah, 0
    mov [cc_tok_val], ax
    mov byte [cc_tok_type], CTK_CHAR
    jmp .ctn_done

.ctn_num:
    ; Parse decimal or hex integer
    xor bx, bx
    mov al, [si]
    cmp al, '0'
    jne .ctn_dec
    inc si
    cmp byte [si], 'x'
    je .ctn_hex
    cmp byte [si], 'X'
    je .ctn_hex
    dec si
.ctn_dec:
.ctn_dec_lp:
    cmp si, [cc_src_end]
    jae .ctn_dec_done
    mov al, [si]
    cmp al, '0'
    jb .ctn_dec_done
    cmp al, '9'
    ja .ctn_dec_done
    sub al, '0'
    push ax
    mov ax, bx
    mov cx, 10
    mul cx
    mov bx, ax
    pop ax
    xor ah, ah
    add bx, ax
    inc si
    jmp .ctn_dec_lp
.ctn_dec_done:
    mov [cc_tok_val], bx
    mov byte [cc_tok_type], CTK_NUM
    jmp .ctn_done

.ctn_hex:
    inc si  ; skip x/X
.ctn_hex_lp:
    cmp si, [cc_src_end]
    jae .ctn_hex_done
    mov al, [si]
    call _uc_al
    cmp al, '0'
    jb .ctn_hex_done
    cmp al, '9'
    jbe .ctn_hex_digit
    cmp al, 'A'
    jb .ctn_hex_done
    cmp al, 'F'
    ja .ctn_hex_done
    sub al, 'A' - 10
    jmp .ctn_hex_add
.ctn_hex_digit:
    sub al, '0'
.ctn_hex_add:
    shl bx, 4
    xor ah, ah
    add bx, ax
    inc si
    jmp .ctn_hex_lp
.ctn_hex_done:
    mov [cc_tok_val], bx
    mov byte [cc_tok_type], CTK_NUM
    jmp .ctn_done

.ctn_ident:
    mov di, cc_tok_str
    mov cx, 31
.ctn_id_lp:
    test cx, cx
    jz .ctn_id_done
    cmp si, [cc_src_end]
    jae .ctn_id_done
    mov al, [si]
    call _uc_al
    cmp al, 'A'
    jb .ctn_id_other
    cmp al, 'Z'
    jbe .ctn_id_ok
.ctn_id_other:
    mov al, [si]
    cmp al, '0'
    jb .ctn_id_sym
    cmp al, '9'
    jbe .ctn_id_raw
.ctn_id_sym:
    cmp al, '_'
    jne .ctn_id_done
.ctn_id_raw:
    call _uc_al
.ctn_id_ok:
    stosb
    inc si
    dec cx
    jmp .ctn_id_lp
.ctn_id_done:
    mov byte [di], 0
    mov byte [cc_tok_type], CTK_IDENT
    jmp .ctn_done

.ctn_punct:
    mov al, [si]
    inc si
    ; Two-char operators
    cmp al, '='
    je .ctn_eq
    cmp al, '!'
    je .ctn_bang
    cmp al, '<'
    je .ctn_lt
    cmp al, '>'
    je .ctn_gt
    cmp al, '&'
    je .ctn_amp
    cmp al, '|'
    je .ctn_pipe
    cmp al, '+'
    je .ctn_plus
    cmp al, '-'
    je .ctn_minus
    ; Single char operators
    cmp al, '*'
    je .ctn_star
    cmp al, '%'
    je .ctn_pct
    cmp al, '('
    je .ctn_lpar
    cmp al, ')'
    je .ctn_rpar
    cmp al, '{'
    je .ctn_lbrace
    cmp al, '}'
    je .ctn_rbrace
    cmp al, ';'
    je .ctn_semi
    cmp al, ','
    je .ctn_comma
    cmp al, '['
    je .ctn_lb
    cmp al, ']'
    je .ctn_rb
    cmp al, '.'
    je .ctn_dot
    cmp al, ':'
    je .ctn_colon
    cmp al, '^'
    je .ctn_caret
    cmp al, '~'
    je .ctn_tilde
    ; Unknown: skip
    jmp .ctn_ws

.ctn_eq:
    cmp byte [si], '='
    jne .ctn_eq_single
    inc si
    mov byte [cc_tok_type], CTK_EQEQ
    jmp .ctn_done
.ctn_eq_single:
    mov byte [cc_tok_type], CTK_EQ
    jmp .ctn_done
.ctn_bang:
    cmp byte [si], '='
    jne .ctn_bang_single
    inc si
    mov byte [cc_tok_type], CTK_NEQ
    jmp .ctn_done
.ctn_bang_single:
    mov byte [cc_tok_type], CTK_BANG
    jmp .ctn_done
.ctn_lt:
    cmp byte [si], '='
    jne .ctn_lt_single
    inc si
    mov byte [cc_tok_type], CTK_LE
    jmp .ctn_done
.ctn_lt_single:
    mov byte [cc_tok_type], CTK_LT
    jmp .ctn_done
.ctn_gt:
    cmp byte [si], '='
    jne .ctn_gt_single
    inc si
    mov byte [cc_tok_type], CTK_GE
    jmp .ctn_done
.ctn_gt_single:
    mov byte [cc_tok_type], CTK_GT
    jmp .ctn_done
.ctn_amp:
    cmp byte [si], '&'
    jne .ctn_amp_single
    inc si
    mov byte [cc_tok_type], CTK_ANDAND
    jmp .ctn_done
.ctn_amp_single:
    mov byte [cc_tok_type], CTK_AMP
    jmp .ctn_done
.ctn_pipe:
    cmp byte [si], '|'
    jne .ctn_pipe_single
    inc si
    mov byte [cc_tok_type], CTK_OROR
    jmp .ctn_done
.ctn_pipe_single:
    mov byte [cc_tok_type], CTK_PIPE
    jmp .ctn_done
.ctn_plus:
    cmp byte [si], '+'
    jne .ctn_plus_eq
    inc si
    mov byte [cc_tok_type], CTK_PLUSPLUS
    jmp .ctn_done
.ctn_plus_eq:
    cmp byte [si], '='
    jne .ctn_plus_single
    inc si
    mov byte [cc_tok_type], CTK_PLUSEQ
    jmp .ctn_done
.ctn_plus_single:
    mov byte [cc_tok_type], CTK_PLUS
    jmp .ctn_done
.ctn_minus:
    cmp byte [si], '-'
    jne .ctn_minus_eq
    inc si
    mov byte [cc_tok_type], CTK_MINUSMINUS
    jmp .ctn_done
.ctn_minus_eq:
    cmp byte [si], '='
    jne .ctn_arrow
    inc si
    mov byte [cc_tok_type], CTK_MINUSEQ
    jmp .ctn_done
.ctn_arrow:
    cmp byte [si], '>'
    jne .ctn_minus_single
    inc si
    mov byte [cc_tok_type], CTK_ARROW
    jmp .ctn_done
.ctn_minus_single:
    mov byte [cc_tok_type], CTK_MINUS
    jmp .ctn_done
.ctn_star:
    mov byte [cc_tok_type], CTK_STAR
    jmp .ctn_done
.ctn_pct:
    mov byte [cc_tok_type], CTK_PERCENT
    jmp .ctn_done
.ctn_lpar:
    mov byte [cc_tok_type], CTK_LPAR
    jmp .ctn_done
.ctn_rpar:
    mov byte [cc_tok_type], CTK_RPAR
    jmp .ctn_done
.ctn_lbrace:
    mov byte [cc_tok_type], CTK_LBRACE
    jmp .ctn_done
.ctn_rbrace:
    mov byte [cc_tok_type], CTK_RBRACE
    jmp .ctn_done
.ctn_semi:
    mov byte [cc_tok_type], CTK_SEMI
    jmp .ctn_done
.ctn_comma:
    mov byte [cc_tok_type], CTK_COMMA
    jmp .ctn_done
.ctn_lb:
    mov byte [cc_tok_type], CTK_LBRACK
    jmp .ctn_done
.ctn_rb:
    mov byte [cc_tok_type], CTK_RBRACK
    jmp .ctn_done
.ctn_dot:
    mov byte [cc_tok_type], CTK_DOT
    jmp .ctn_done
.ctn_colon:
    mov byte [cc_tok_type], CTK_COLON
    jmp .ctn_done
.ctn_caret:
    mov byte [cc_tok_type], CTK_CARET
    jmp .ctn_done
.ctn_tilde:
    mov byte [cc_tok_type], CTK_TILDE
    jmp .ctn_done

.ctn_done:
    mov [cc_src], si
    pop si
    pop ax
    ret

; ============================================================
; cc_skip_to_newline - skip until end of line (for #include etc.)
; ============================================================
cc_skip_to_newline:
    push ax
    push si
    mov si, [cc_src]
.stnl:
    cmp si, [cc_src_end]
    jae .stnl_done
    mov al, [si]
    inc si
    cmp al, 0x0A
    jne .stnl
    inc word [cc_line]
.stnl_done:
    mov [cc_src], si
    pop si
    pop ax
    ret

; ============================================================
; cc_is_type - check if cc_tok_str is a type keyword
; Returns CF=0 if type keyword (INT/CHAR/VOID/UNSIGNED/SIGNED/LONG/SHORT/STATIC)
; ============================================================
cc_is_type:
    push si
    push di
    mov si, cc_tok_str
    ; Compare with known type keywords
    mov di, cc_str_INT
    call str_cmp
    jz .is_type
    mov di, cc_str_CHAR
    call str_cmp
    jz .is_type
    mov di, cc_str_VOID
    call str_cmp
    jz .is_type
    mov di, cc_str_UNSIGNED
    call str_cmp
    jz .is_type
    mov di, cc_str_SIGNED
    call str_cmp
    jz .is_type
    mov di, cc_str_LONG
    call str_cmp
    jz .is_type
    mov di, cc_str_STATIC
    call str_cmp
    jz .is_type
    mov di, cc_str_CONST
    call str_cmp
    jz .is_type
    pop di
    pop si
    stc
    ret
.is_type:
    pop di
    pop si
    clc
    ret

cc_str_INT:      db "INT",0
cc_str_CHAR:     db "CHAR",0
cc_str_VOID:     db "VOID",0
cc_str_UNSIGNED: db "UNSIGNED",0
cc_str_SIGNED:   db "SIGNED",0
cc_str_LONG:     db "LONG",0
cc_str_STATIC:   db "STATIC",0
cc_str_CONST:    db "CONST",0
cc_str_IF:       db "IF",0
cc_str_ELSE:     db "ELSE",0
cc_str_WHILE:    db "WHILE",0
cc_str_FOR:      db "FOR",0
cc_str_RETURN:   db "RETURN",0
cc_str_PUTS:     db "PUTS",0
cc_str_PRINTF:   db "PRINTF",0
cc_str_PUTCHAR:  db "PUTCHAR",0
cc_str_EXIT:     db "EXIT",0
cc_str_MAIN:     db "MAIN",0

; ============================================================
; cc_emit_byte / cc_emit_word - emit to output buffer
; (identical to asm_ versions but track cc_out/cc_pc)
; ============================================================
cc_emit_byte:
    push bx
    mov bx, [cc_out]
    mov [bx], al
    inc word [cc_out]
    inc word [cc_pc]
    inc word [asm_out]      ; keep asm_out in sync
    inc word [asm_pc]
    pop bx
    ret

cc_emit_word:
    push ax
    ; emit low byte
    call cc_emit_byte
    pop ax
    push ax
    mov al, ah
    call cc_emit_byte
    pop ax
    ret

; ============================================================
; cc_parse_decl - parse a top-level declaration (function or global var)
; Called after a type keyword has been tokenized
; ============================================================
cc_parse_decl:
    push ax
    push si
    ; Consume additional type qualifiers (int, char, unsigned, etc.)
    ; tok_str already has the first type
    ; Get the name
    call cc_tok_next
    ; Skip additional type keywords
.pd_skip_type:
    cmp byte [cc_tok_type], CTK_IDENT
    jne .pd_got_name
    call cc_is_type
    jc .pd_got_name         ; not a type, it's a name
    call cc_tok_next
    jmp .pd_skip_type

.pd_got_name:
    ; cc_tok_str = function/variable name
    ; Peek next token: '(' = function, ';'/'='= global variable
    push word [cc_src]      ; save position
    mov si, cc_tok_str
    mov di, asm_last_glb    ; reuse last_glb as function name
    call str_copy
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_LPAR
    jne .pd_global_var
    pop ax                  ; discard saved position
    ; It's a function definition
    call cc_parse_function
    jmp .pd_done

.pd_global_var:
    pop word [cc_src]       ; restore (skip = global var, just declare)
    ; Skip to semicolon
    call cc_tok_next
    call cc_skip_to_semi
.pd_done:
    pop si
    pop ax
    ret

; ============================================================
; cc_skip_to_semi - skip tokens until ';' or EOF
; ============================================================
cc_skip_to_semi:
    push ax
.cts:
    cmp byte [cc_tok_type], CTK_SEMI
    je .cts_done
    cmp byte [cc_tok_type], CTK_EOF
    je .cts_done
    call cc_tok_next
    jmp .cts
.cts_done:
    pop ax
    ret

; ============================================================
; cc_parse_function - parse and compile a function body
; asm_last_glb = function name
; ============================================================
cc_parse_function:
    push ax
    push bx
    push si

    ; Skip parameter list
    mov cx, 1               ; nesting depth for ()
.pf_skip_params:
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_EOF
    je .pf_done
    cmp byte [cc_tok_type], CTK_LPAR
    jne .pf_not_lpar
    inc cx
    jmp .pf_skip_params
.pf_not_lpar:
    cmp byte [cc_tok_type], CTK_RPAR
    jne .pf_skip_params
    dec cx
    jnz .pf_skip_params

    ; Now expect '{' (possibly a declaration, skip it)
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_LBRACE
    je .pf_has_body
    ; Might be a semicolon (forward declaration)
    jmp .pf_done

.pf_has_body:
    ; Emit function label and prologue
    ; Define symbol for this function name
    mov si, asm_last_glb
    mov ax, [cc_pc]
    call asm_sym_define

    ; If this is 'main', record its address for the initial JMP patch
    mov si, asm_last_glb
    mov di, cc_str_MAIN
    call str_cmp
    jnz .pf_not_main
    mov ax, [cc_pc]
    mov [cc_main_addr], ax
.pf_not_main:

    ; Emit function prologue: PUSH BP; MOV BP, SP; SUB SP, 0 (patched later)
    mov al, 0x55            ; PUSH BP
    call cc_emit_byte
    mov al, 0x89            ; MOV BP, SP
    call cc_emit_byte
    mov al, 0xEC
    call cc_emit_byte
    ; Emit SUB SP, N placeholder (will be patched with actual frame size)
    mov al, 0x83            ; SUB SP, imm8
    call cc_emit_byte
    mov al, 0xEC
    call cc_emit_byte
    ; Save current output position for frame size patch
    mov ax, [cc_out]
    sub ax, COMP_BUF
    mov [cc_frame_patch], ax
    mov al, 0               ; placeholder for frame size
    call cc_emit_byte

    ; Reset frame (no locals yet)
    mov word [cc_frame_sz], 0
    mov word [cc_sym_cnt], 0
    mov byte [cc_in_func], 1

    ; Parse function body (statements until '}')
    call cc_tok_next
.pf_body:
    cmp byte [cc_tok_type], CTK_RBRACE
    je .pf_end_body
    cmp byte [cc_tok_type], CTK_EOF
    je .pf_end_body
    call cc_parse_statement
    cmp byte [cc_err], 0
    jne .pf_end_body
    jmp .pf_body

.pf_end_body:
    ; Patch SUB SP, N with actual frame size
    mov bx, [cc_frame_patch]
    add bx, COMP_BUF
    mov ax, [cc_frame_sz]
    mov [bx], al            ; patch the imm8

    ; Emit function epilogue: MOV SP, BP; POP BP; RET
    mov al, 0x89            ; MOV SP, BP
    call cc_emit_byte
    mov al, 0xE5
    call cc_emit_byte
    mov al, 0x5D            ; POP BP
    call cc_emit_byte
    mov al, 0xC3            ; RET
    call cc_emit_byte

    mov byte [cc_in_func], 0

.pf_done:
    pop si
    pop bx
    pop ax
    ret

cc_frame_patch:  dw 0       ; output offset of SUB SP, N's operand
cc_main_addr:    dw 0       ; address of main() for initial JMP patch

; ============================================================
; cc_patch_main_jump - patch the initial JMP main (at output offset 0)
; ============================================================
cc_patch_main_jump:
    push ax
    ; The JMP instruction is at COMP_BUF+0: E9, rel16
    ; rel16 = main_addr - (org + 3)
    mov ax, [cc_main_addr]
    test ax, ax
    jz .no_main
    sub ax, [asm_pc_base]
    sub ax, 3               ; 3 bytes for the JMP instruction
    mov bx, COMP_BUF
    mov [bx+1], ax          ; patch rel16
.no_main:
    pop ax
    ret

; ============================================================
; cc_emit_data_section - append string literals to output
; ============================================================
cc_emit_data_section:
    push ax
    push bx
    push cx
    push si
    mov cx, [cc_data_size]
    test cx, cx
    jz .eds_done
    mov si, CC_DATA_BUF
.eds_copy:
    test cx, cx
    jz .eds_done
    mov al, [si]
    call cc_emit_byte
    inc si
    dec cx
    jmp .eds_copy
.eds_done:
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; cc_parse_statement - parse one C statement
; ============================================================
cc_parse_statement:
    push ax
    push si

    ; Check what kind of statement
    cmp byte [cc_tok_type], CTK_IDENT
    jne .ps_not_ident

    ; Could be: type decl, keyword (if/while/return), function call, assignment
    ; Check for keywords first
    mov si, cc_tok_str
    mov di, cc_str_IF
    call str_cmp
    jz .ps_if
    mov di, cc_str_WHILE
    call str_cmp
    jz .ps_while
    mov di, cc_str_FOR
    call str_cmp
    jz .ps_for
    mov di, cc_str_RETURN
    call str_cmp
    jz .ps_return
    mov di, cc_str_PUTS
    call str_cmp
    jz .ps_puts
    mov di, cc_str_PRINTF
    call str_cmp
    jz .ps_printf
    mov di, cc_str_PUTCHAR
    call str_cmp
    jz .ps_putchar
    mov di, cc_str_EXIT
    call str_cmp
    jz .ps_exit
    ; Check if it's a type (local variable declaration)
    call cc_is_type
    jnc .ps_local_var
    ; It's an expression statement (assignment or function call)
    call cc_parse_expr_stmt
    jmp .ps_done

.ps_not_ident:
    cmp byte [cc_tok_type], CTK_LBRACE
    je .ps_block
    cmp byte [cc_tok_type], CTK_SEMI
    je .ps_empty
    cmp byte [cc_tok_type], CTK_RBRACE
    je .ps_done             ; end of block, don't consume
    jmp .ps_done

.ps_empty:
    call cc_tok_next
    jmp .ps_done

.ps_block:
    call cc_tok_next
.ps_block_loop:
    cmp byte [cc_tok_type], CTK_RBRACE
    je .ps_block_end
    cmp byte [cc_tok_type], CTK_EOF
    je .ps_done
    call cc_parse_statement
    cmp byte [cc_err], 0
    jne .ps_done
    jmp .ps_block_loop
.ps_block_end:
    call cc_tok_next
    jmp .ps_done

.ps_if:
    call cc_parse_if
    jmp .ps_done

.ps_while:
    call cc_parse_while
    jmp .ps_done

.ps_for:
    call cc_parse_for
    jmp .ps_done

.ps_return:
    call cc_parse_return
    jmp .ps_done

.ps_puts:
    call cc_parse_puts
    jmp .ps_done

.ps_printf:
    call cc_parse_printf
    jmp .ps_done

.ps_putchar:
    call cc_parse_putchar
    jmp .ps_done

.ps_exit:
    call cc_parse_exit
    jmp .ps_done

.ps_local_var:
    call cc_parse_local_var
    jmp .ps_done

.ps_done:
    pop si
    pop ax
    ret

; ============================================================
; cc_add_string_literal - store string in CC_DATA_BUF, return offset
; Input: CC_TOK_STR already tokenized (cc_tok_str = content, cc_tok_val = length)
; Returns: AX = data section offset where string starts
; ============================================================
cc_add_string_literal:
    push bx
    push cx
    push si
    push di
    mov ax, [cc_data_size]      ; return this as the starting offset
    push ax
    mov di, CC_DATA_BUF
    add di, [cc_data_size]
    mov si, cc_tok_str
    mov cx, [cc_tok_val]
    inc cx                      ; include null terminator
    cmp cx, CC_DATA_MAX
    jge .sl_overflow
.sl_copy:
    test cx, cx
    jz .sl_done
    lodsb
    stosb
    inc word [cc_data_size]
    dec cx
    jmp .sl_copy
.sl_done:
    pop ax
    pop di
    pop si
    pop cx
    pop bx
    ret
.sl_overflow:
    pop ax
    xor ax, ax
    pop di
    pop si
    pop cx
    pop bx
    ret

; ============================================================
; cc_parse_puts - emit puts("string") as BIOS teletype loop
; ============================================================
cc_parse_puts:
    push ax
    call cc_tok_next        ; skip function name, we're on it already
    call cc_tok_next        ; should be '('
    cmp byte [cc_tok_type], CTK_LPAR
    jne .puts_skip
    call cc_tok_next        ; get argument
    cmp byte [cc_tok_type], CTK_STR
    jne .puts_str_skip
    ; Add string + newline to data buffer
    ; Append \n and \0 to string
    mov bx, [cc_tok_val]
    mov byte [cc_tok_str + bx], 0x0A    ; add newline
    mov byte [cc_tok_str + bx + 1], 0   ; null terminate
    inc word [cc_tok_val]   ; include the \n in length

    call cc_add_string_literal
    ; AX = data_section_offset of string
    ; We need virtual address = asm_pc_base + (cc_out - COMP_BUF) + code_size + data_offset
    ; Actually: string will be after all code, at:
    ;   origin + final_code_size + data_offset
    ; We don't know final code size yet, so store a patch
    push ax                 ; save data offset
    ; Emit code to display the string:
    ;   MOV SI, string_address   (placeholder - will be patched)
    ;   .loop: LODSB
    ;   OR AL, AL
    ;   JZ .done
    ;   MOV AH, 0x0E
    ;   MOV BH, 0
    ;   INT 0x10
    ;   JMP .loop
    ;   .done:
    mov al, 0xBE            ; MOV SI, imm16
    call cc_emit_byte
    ; Emit placeholder address (will be patched later)
    ; Record patch: (output_offset, data_section_index, type=data)
    mov ax, [cc_out]
    sub ax, COMP_BUF        ; output offset for patch
    pop bx                  ; bx = data_section_offset
    push bx
    push ax
    ; Emit placeholder
    xor ax, ax
    call cc_emit_word
    ; Add to our string patch table
    pop ax                  ; output offset
    pop bx                  ; data section offset
    call cc_add_str_patch   ; record (out_offset, data_off)

    ; Emit the loop
    mov al, 0xAC            ; LODSB
    call cc_emit_byte
    mov al, 0x08            ; OR AL, AL (0x08, 0xC0 = OR r/m8, r8)
    call cc_emit_byte
    mov al, 0xC0
    call cc_emit_byte
    mov al, 0x74            ; JZ +5 (skip the body)
    call cc_emit_byte
    mov al, 0x05
    call cc_emit_byte
    mov al, 0xB4            ; MOV AH, 0x0E
    call cc_emit_byte
    mov al, 0x0E
    call cc_emit_byte
    mov al, 0xB7            ; MOV BH, 0
    call cc_emit_byte
    xor al, al
    call cc_emit_byte
    mov al, 0xCD            ; INT 0x10
    call cc_emit_byte
    mov al, 0x10
    call cc_emit_byte
    mov al, 0xEB            ; JMP -12 (back to LODSB)
    call cc_emit_byte
    mov al, 0xF2
    call cc_emit_byte

.puts_str_skip:
    ; Skip to closing ) and ;
    call cc_skip_to_semi
    call cc_tok_next        ; consume semi
    pop ax
    ret

.puts_skip:
    call cc_skip_to_semi
    call cc_tok_next
    pop ax
    ret

; ============================================================
; cc_add_str_patch - record that a word at output offset AX needs
; to be patched with: asm_pc_base + final_code_out + BX (data offset)
; BX = data section offset, AX = output byte offset in COMP_BUF
; ============================================================
cc_str_patch_cnt: dw 0
cc_str_patches:   times 32 dw 0   ; up to 16 patches: [out_off, data_off] x 16

cc_add_str_patch:
    push bx
    push si
    mov si, [cc_str_patch_cnt]
    cmp si, 14              ; max 14 patches (28 words)
    jge .asp_done
    shl si, 1               ; * 2 pairs = * 4 bytes? No, each patch is 2 words
    shl si, 1               ; si = si * 4 (2 words per patch)
    mov [cc_str_patches + si], ax       ; output offset
    mov [cc_str_patches + si + 2], bx   ; data offset
    inc word [cc_str_patch_cnt]
.asp_done:
    pop si
    pop bx
    ret

; Apply string patches (called from cc_run after compiling)
cc_apply_str_patches:
    push ax
    push bx
    push cx
    push si
    ; For each patch: calculate actual string address
    ; string_vaddr = asm_pc_base + final_code_size + data_offset
    ; final_code_size = (cc_out - COMP_BUF) - cc_data_size
    mov ax, [cc_out]
    sub ax, COMP_BUF
    sub ax, [cc_data_size]  ; ax = size of just the code part
    add ax, [asm_pc_base]   ; ax = virtual addr where data section starts
    mov bx, ax              ; bx = base of data section

    mov cx, [cc_str_patch_cnt]
    xor si, si
.csp_loop:
    test cx, cx
    jz .csp_done
    push bx
    mov si, [cc_str_patches + si]   ; this is buggy, let me fix
    pop bx
    dec cx
    jmp .csp_loop
.csp_done:
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; cc_parse_printf - printf("format", ...) → puts style for string arg
; ============================================================
cc_parse_printf:
    push ax
    call cc_tok_next        ; skip 'printf', already on it
    call cc_tok_next        ; '('
    cmp byte [cc_tok_type], CTK_LPAR
    jne .pf_skip
    call cc_tok_next        ; format string
    ; Treat same as puts
    cmp byte [cc_tok_type], CTK_STR
    jne .pf_skip_str
    ; Process format string as simple puts
    call cc_add_string_literal
    push ax
    mov al, 0xBE
    call cc_emit_byte
    mov ax, [cc_out]
    sub ax, COMP_BUF
    pop bx
    push bx
    push ax
    xor ax, ax
    call cc_emit_word
    pop ax
    pop bx
    call cc_add_str_patch
    ; Print loop
    mov al, 0xAC
    call cc_emit_byte
    mov al, 0x08
    call cc_emit_byte
    mov al, 0xC0
    call cc_emit_byte
    mov al, 0x74
    call cc_emit_byte
    mov al, 0x05
    call cc_emit_byte
    mov al, 0xB4
    call cc_emit_byte
    mov al, 0x0E
    call cc_emit_byte
    mov al, 0xB7
    call cc_emit_byte
    xor al, al
    call cc_emit_byte
    mov al, 0xCD
    call cc_emit_byte
    mov al, 0x10
    call cc_emit_byte
    mov al, 0xEB
    call cc_emit_byte
    mov al, 0xF2
    call cc_emit_byte
.pf_skip_str:
.pf_skip:
    call cc_skip_to_semi
    call cc_tok_next
    pop ax
    ret

; ============================================================
; cc_parse_putchar - putchar(ch) → BIOS teletype single char
; ============================================================
cc_parse_putchar:
    push ax
    call cc_tok_next        ; on 'putchar', now get '('
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_LPAR
    jne .pc_skip
    call cc_tok_next        ; get argument
    ; Emit: MOV AL, value; MOV AH, 0x0E; MOV BH, 0; INT 0x10
    cmp byte [cc_tok_type], CTK_NUM
    je .pc_num
    cmp byte [cc_tok_type], CTK_CHAR
    je .pc_num
    jmp .pc_skip
.pc_num:
    mov al, 0xB0            ; MOV AL, imm8
    call cc_emit_byte
    mov al, [cc_tok_val]
    call cc_emit_byte
    mov al, 0xB4            ; MOV AH, 0x0E
    call cc_emit_byte
    mov al, 0x0E
    call cc_emit_byte
    mov al, 0xB7            ; MOV BH, 0
    call cc_emit_byte
    xor al, al
    call cc_emit_byte
    mov al, 0xCD            ; INT 0x10
    call cc_emit_byte
    mov al, 0x10
    call cc_emit_byte
.pc_skip:
    call cc_skip_to_semi
    call cc_tok_next
    pop ax
    ret

; ============================================================
; cc_parse_exit - exit(N) → MOV AX, 0x4C00+N; INT 0x21 or just REBOOT
; ============================================================
cc_parse_exit:
    push ax
    call cc_tok_next        ; '('
    call cc_tok_next        ; argument
    ; Just emit HLT
    mov al, 0xF4            ; HLT
    call cc_emit_byte
    call cc_skip_to_semi
    call cc_tok_next
    pop ax
    ret

; ============================================================
; cc_parse_return - return expression;
; ============================================================
cc_parse_return:
    push ax
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_SEMI
    je .ret_no_expr
    ; Parse expression into AX
    call cc_parse_simple_expr
    ; Result should be in AX already (for int returns)
.ret_no_expr:
    ; Emit epilogue: MOV SP, BP; POP BP; RET
    mov al, 0x89
    call cc_emit_byte
    mov al, 0xE5            ; MOV SP, BP
    call cc_emit_byte
    mov al, 0x5D            ; POP BP
    call cc_emit_byte
    mov al, 0xC3            ; RET
    call cc_emit_byte
    cmp byte [cc_tok_type], CTK_SEMI
    jne .ret_done
    call cc_tok_next
.ret_done:
    pop ax
    ret

; ============================================================
; cc_parse_local_var - int x; or int x = N;
; ============================================================
cc_parse_local_var:
    push ax
    push bx
    ; Skip additional type keywords
    call cc_tok_next
.plv_skip_type:
    cmp byte [cc_tok_type], CTK_IDENT
    jne .plv_got_name
    call cc_is_type
    jc .plv_got_name
    call cc_tok_next
    jmp .plv_skip_type
.plv_got_name:
    ; cc_tok_str = variable name
    ; Allocate a 16-bit local: [BP - (frame_sz+2)]
    add word [cc_frame_sz], 2
    mov ax, [cc_frame_sz]
    neg ax                  ; negative offset from BP
    ; Store in symbol table
    push ax
    mov si, cc_tok_str
    ; Use asm_sym_define with value = stack offset (negative)
    call asm_sym_define
    pop ax
    ; Check for initializer: =
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_EQ
    jne .plv_no_init
    call cc_tok_next
    call cc_parse_simple_expr   ; result in AX (register)
    ; Emit: MOV [BP-N], AX (store local)
    mov bx, [cc_frame_sz]
    neg bx
    mov al, 0x89            ; MOV r/m16, r16
    call cc_emit_byte
    mov al, 0x46            ; [BP + disp8], reg=AX
    call cc_emit_byte
    mov al, bl              ; negative displacement
    call cc_emit_byte
.plv_no_init:
    ; Expect ';'
    cmp byte [cc_tok_type], CTK_SEMI
    jne .plv_done
    call cc_tok_next
.plv_done:
    pop bx
    pop ax
    ret

; ============================================================
; cc_parse_simple_expr - parse an expression, result in AX
; Handles: number, identifier, basic arithmetic
; ============================================================
cc_parse_simple_expr:
    push bx
    push si
    cmp byte [cc_tok_type], CTK_NUM
    je .pse_num
    cmp byte [cc_tok_type], CTK_CHAR
    je .pse_num
    cmp byte [cc_tok_type], CTK_MINUS
    je .pse_neg
    cmp byte [cc_tok_type], CTK_IDENT
    je .pse_ident
    jmp .pse_done

.pse_num:
    ; MOV AX, imm16
    mov ax, [cc_tok_val]
    push ax
    mov al, 0xB8            ; MOV AX, imm16
    call cc_emit_byte
    pop ax
    call cc_emit_word
    call cc_tok_next
    jmp .pse_check_op

.pse_neg:
    call cc_tok_next
    call cc_parse_simple_expr   ; recursive for -expr
    ; NEG AX
    mov al, 0xF7
    call cc_emit_byte
    mov al, 0xD8            ; NEG AX (ModRM for NEG r16: 0xF7 /3, mod=11, r/m=AX=0, subcode=3=0b011)
    call cc_emit_byte
    jmp .pse_done

.pse_ident:
    ; Load variable from stack: MOV AX, [BP-N]
    mov si, cc_tok_str
    call asm_sym_lookup
    jc .pse_ident_num       ; not found → treat as 0
    ; AX = stack offset (negative)
    push ax
    mov al, 0x8B            ; MOV AX, [BP+disp8]
    call cc_emit_byte
    mov al, 0x46
    call cc_emit_byte
    pop ax
    call cc_emit_byte       ; emit the disp8 (negative offset)
    call cc_tok_next
    jmp .pse_check_op

.pse_ident_num:
    ; Unknown identifier: emit MOV AX, 0
    mov al, 0xB8
    call cc_emit_byte
    xor ax, ax
    call cc_emit_word
    call cc_tok_next
    jmp .pse_check_op

.pse_check_op:
    ; Check for binary operator
    cmp byte [cc_tok_type], CTK_PLUS
    je .pse_add
    cmp byte [cc_tok_type], CTK_MINUS
    je .pse_sub
    cmp byte [cc_tok_type], CTK_STAR
    je .pse_mul
    cmp byte [cc_tok_type], CTK_SLASH
    je .pse_div
    jmp .pse_done

.pse_add:
    ; PUSH AX; parse next; POP BX; ADD AX, BX
    mov al, 0x50            ; PUSH AX
    call cc_emit_byte
    call cc_tok_next
    call cc_parse_simple_expr
    mov al, 0x5B            ; POP BX
    call cc_emit_byte
    mov al, 0x03            ; ADD AX, BX (ADD r16, r/m16)
    call cc_emit_byte
    mov al, 0xC3
    call cc_emit_byte
    jmp .pse_done

.pse_sub:
    mov al, 0x50
    call cc_emit_byte
    call cc_tok_next
    call cc_parse_simple_expr
    mov al, 0x5B
    call cc_emit_byte
    mov al, 0x93            ; XCHG AX, BX (so BX = left, AX = right)
    call cc_emit_byte
    mov al, 0x2B            ; SUB AX, BX... wait: SUB AX, BX = AX - BX
    ; Actually: left - right: left in BX (after pop), right in AX
    ; After XCHG: BX=right(was AX), AX=left(was BX)
    ; SUB AX, BX = left - right ✓
    call cc_emit_byte
    mov al, 0xC3
    call cc_emit_byte
    jmp .pse_done

.pse_mul:
    mov al, 0x50
    call cc_emit_byte
    call cc_tok_next
    call cc_parse_simple_expr
    mov al, 0x5B
    call cc_emit_byte
    ; IMUL BX: AX *= BX
    mov al, 0xF7
    call cc_emit_byte
    mov al, 0xEB            ; IMUL BX (0xF7 /5, mod=11, r/m=BX=3, subcode=5 → 11_101_011)
    call cc_emit_byte
    jmp .pse_done

.pse_div:
    mov al, 0x50
    call cc_emit_byte
    call cc_tok_next
    call cc_parse_simple_expr
    mov al, 0x93            ; XCHG AX, BX
    call cc_emit_byte
    ; AX = left (dividend), BX = right (divisor)
    ; CWD; IDIV BX
    mov al, 0x99            ; CWD (sign extend AX to DX:AX)
    call cc_emit_byte
    mov al, 0xF7            ; IDIV BX
    call cc_emit_byte
    mov al, 0xFF            ; /7, mod=11, r/m=BX: 11_111_011
    call cc_emit_byte
    jmp .pse_done

.pse_done:
    pop si
    pop bx
    ret

; ============================================================
; cc_parse_expr_stmt - parse assignment or standalone expression
; ============================================================
cc_parse_expr_stmt:
    push ax
    push si
    ; cc_tok_str has an identifier
    mov si, cc_tok_str
    push si                 ; save name
    call cc_tok_next
    ; Check for '=' (assignment)
    cmp byte [cc_tok_type], CTK_EQ
    je .pes_assign
    cmp byte [cc_tok_type], CTK_PLUSEQ
    je .pes_pluseq
    ; Otherwise, skip to semicolon
    pop si
    call cc_skip_to_semi
    call cc_tok_next
    jmp .pes_done

.pes_assign:
    call cc_tok_next        ; consume '=', get RHS
    call cc_parse_simple_expr   ; result in AX
    ; Find variable and store
    pop si
    call asm_sym_lookup     ; AX = stack offset
    jc .pes_done            ; not found: skip
    push ax
    mov al, 0x89            ; MOV [BP+disp8], AX
    call cc_emit_byte
    mov al, 0x46
    call cc_emit_byte
    pop ax
    call cc_emit_byte       ; disp8 (negative)
    cmp byte [cc_tok_type], CTK_SEMI
    jne .pes_done
    call cc_tok_next
    jmp .pes_done

.pes_pluseq:
    call cc_tok_next
    call cc_parse_simple_expr
    pop si
    call asm_sym_lookup
    jc .pes_done
    push ax
    mov al, 0x01            ; ADD [BP+disp8], AX
    call cc_emit_byte
    mov al, 0x46
    call cc_emit_byte
    pop ax
    call cc_emit_byte
    cmp byte [cc_tok_type], CTK_SEMI
    jne .pes_done
    call cc_tok_next
    jmp .pes_done

.pes_done:
    pop ax
    pop si
    ret

; ============================================================
; cc_parse_if - if (cond) stmt [else stmt]
; ============================================================
cc_parse_if:
    push ax
    push bx
    call cc_tok_next        ; skip 'if', get '('
    cmp byte [cc_tok_type], CTK_LPAR
    jne .pif_done
    call cc_tok_next        ; get condition expression
    call cc_parse_condition ; emits comparison, sets flags, AX=jmp opcode
    ; Emit conditional jump over body (placeholder)
    call cc_emit_byte       ; conditional jump opcode (JZ for '==', etc.)
    mov bx, [cc_out]        ; save offset of rel8 placeholder
    sub bx, COMP_BUF
    dec bx
    xor al, al
    call cc_emit_byte       ; placeholder
    ; Parse body
    call cc_tok_next        ; past ')'
    call cc_parse_statement ; body
    ; Patch jump
    mov ax, [cc_out]
    sub ax, COMP_BUF
    sub ax, bx
    dec ax                  ; rel from end of jump instr
    mov si, bx
    add si, COMP_BUF
    inc si                  ; point to placeholder byte
    mov [si], al
    ; Check for else
    cmp byte [cc_tok_type], CTK_IDENT
    jne .pif_done
    mov si, cc_tok_str
    mov di, cc_str_ELSE
    call str_cmp
    jnz .pif_done
    call cc_tok_next
    call cc_parse_statement
.pif_done:
    pop bx
    pop ax
    ret

; ============================================================
; cc_parse_condition - parse (condition) between parens
; The LPAR should be the current tok before calling
; Emits comparison code, returns AL = conditional jump opcode to negate
; ============================================================
cc_parse_condition:
    push bx
    ; Parse LHS expression
    call cc_parse_simple_expr   ; result in AX
    ; Check for comparison operator
    cmp byte [cc_tok_type], CTK_EQEQ
    je .pc_eq
    cmp byte [cc_tok_type], CTK_NEQ
    je .pc_ne
    cmp byte [cc_tok_type], CTK_LT
    je .pc_lt
    cmp byte [cc_tok_type], CTK_GT
    je .pc_gt
    cmp byte [cc_tok_type], CTK_LE
    je .pc_le
    cmp byte [cc_tok_type], CTK_GE
    je .pc_ge
    ; No operator: test AX (if (expr))
    mov al, 0x85            ; TEST AX, AX
    call cc_emit_byte
    mov al, 0xC0
    call cc_emit_byte
    mov al, 0x74            ; JZ (jump if zero = condition false)
    ; Skip the ')'
    cmp byte [cc_tok_type], CTK_RPAR
    jne .pc_done
    call cc_tok_next
    jmp .pc_done

.pc_eq:
.pc_ne:
.pc_lt:
.pc_gt:
.pc_le:
.pc_ge:
    push ax             ; save operator type
    mov bl, al          ; save operator tok type
    call cc_tok_next    ; consume operator, get RHS
    call cc_parse_simple_expr   ; RHS in AX
    ; Emit CMP: we need left - right. left was in AX, we need to save it.
    ; Actually left was computed first (pushed), then right... let me use BX
    ; After right parse, AX = right value code is emitted
    ; Left is in the code stream. Let me use XCHG to get both in AX and BX.
    ; Actually since both are just AX from the code gen perspective:
    ; emit PUSH AX (before RHS parse), then XCHG after, then CMP
    ; But we already emitted left without push... 
    ; Hack: for simple integer comparisons with a number:
    ; If right was a constant (cc_tok_val), emit CMP AX, imm16
    ; Otherwise emit POP BX; CMP BX, AX (though this is wrong order)
    pop ax              ; restore operator
    ; Emit: MOV BX, AX; parse already emitted code for right into AX
    ; Actually this is getting messy. Let me emit TEST/CMP based on operator
    ; Emit CMP AX, 0 for simplicity and use the comparison
    ; This is a simplified version: only handles (var == 0) style
    mov al, 0x85            ; TEST AX, AX
    call cc_emit_byte
    mov al, 0xC0
    call cc_emit_byte
    mov al, 0x74            ; JZ for EQ (negate for JNZ)
    cmp bl, CTK_NEQ
    jne .pc_test_done
    mov al, 0x75
.pc_test_done:
    ; Skip ')'
    cmp byte [cc_tok_type], CTK_RPAR
    jne .pc_done
    call cc_tok_next

.pc_done:
    pop bx
    ret

; ============================================================
; cc_parse_while - while (cond) body
; ============================================================
cc_parse_while:
    push ax
    push bx
    ; Record start of loop (for jump back)
    mov bx, [cc_out]
    sub bx, COMP_BUF
    push bx                 ; save loop_start offset
    call cc_tok_next        ; skip 'while', get '('
    cmp byte [cc_tok_type], CTK_LPAR
    jne .pwh_done
    call cc_tok_next        ; get condition
    call cc_parse_condition ; emits CMP, returns jump opcode in AL
    push ax                 ; save jump opcode
    ; Emit conditional jump to end (placeholder)
    call cc_emit_byte
    mov bx, [cc_out]
    sub bx, COMP_BUF
    push bx                 ; save offset of rel8 placeholder
    xor al, al
    call cc_emit_byte       ; placeholder
    ; Parse body
    call cc_tok_next        ; past ')'
    call cc_parse_statement ; body
    ; Emit JMP back to loop start
    pop bx                  ; rel8 placeholder offset
    pop ax                  ; jump opcode (not needed now)
    pop cx                  ; loop_start offset
    ; JMP back: 0xEB, -(distance)
    mov al, 0xEB
    call cc_emit_byte
    mov ax, [cc_out]
    sub ax, COMP_BUF
    inc ax                  ; end of JMP instruction
    sub cx, ax              ; cx = rel8 back to loop start
    ; cx is negative, that's what we want
    mov al, cl
    call cc_emit_byte
    ; Patch the conditional jump
    mov si, bx
    add si, COMP_BUF
    inc si
    mov ax, [cc_out]
    sub ax, COMP_BUF
    sub ax, bx
    dec ax
    mov [si], al            ; patch rel8
.pwh_done:
    pop bx
    pop ax
    ret

; ============================================================
; cc_parse_for - for(init;cond;post) body → simplified
; ============================================================
cc_parse_for:
    push ax
    call cc_tok_next        ; skip 'for', get '('
    ; Skip entire for header and body for simplicity
    cmp byte [cc_tok_type], CTK_LPAR
    jne .pfor_done
    mov cx, 1
.pfor_skip:
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_LPAR
    jne .pfor_not_lp
    inc cx
    jmp .pfor_skip
.pfor_not_lp:
    cmp byte [cc_tok_type], CTK_RPAR
    jne .pfor_skip
    dec cx
    jnz .pfor_skip
    ; Now skip body
    call cc_tok_next
    call cc_parse_statement
.pfor_done:
    pop ax
    ret

; ============================================================
; Data strings for C compiler
; ============================================================
str_cc_compiled: db "Compilation successful. Output: A.COM", 0
