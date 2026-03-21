; =============================================================================
; compiler_csc.asm - KSDOS C# Compiler (subset → x86 16-bit COM output)
; Supports: class Program { static void Main() { ... } }
;           Console.WriteLine("str"), Console.Write("str"),
;           int x = N; x += N; if/while, return
; Output: .COM file
; Source: FILE_BUF, Output: COMP_BUF (= DIR_BUF = 0xD200)
; =============================================================================

; Reuses cc_tok_next, cc_emit_byte, cc_emit_word, cc_parse_* from compiler_c.asm
; Also reuses asm_sym_define, asm_sym_lookup, asm_apply_patches, asm_write_output

; ============================================================
; csc_run - main C# compiler entry point
; ============================================================
csc_run:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; Init state (same as cc_run)
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
    mov word [cc_str_patch_cnt], 0
    mov word [cc_main_addr], 0

    ; Emit JMP main placeholder
    mov al, 0xE9
    call cc_emit_byte
    xor ax, ax
    call cc_emit_word

    ; Parse top level
.csc_parse:
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_EOF
    je .csc_done_parse
    cmp byte [cc_tok_type], CTK_SHARP
    je .csc_skip_directive
    cmp byte [cc_tok_type], CTK_IDENT
    jne .csc_parse
    ; Check for: using, namespace, class, [modifiers like public/static/private]
    mov si, cc_tok_str
    mov di, csc_str_USING
    call str_cmp
    jz .csc_skip_line
    mov di, csc_str_NAMESPACE
    call str_cmp
    jz .csc_namespace
    mov di, csc_str_CLASS
    call str_cmp
    jz .csc_class
    ; Modifiers: public, private, static, internal, sealed, abstract
    call csc_is_modifier
    jnc .csc_modifier_loop
    jmp .csc_parse

.csc_skip_directive:
.csc_skip_line:
    call cc_skip_to_newline
    jmp .csc_parse

.csc_namespace:
    ; namespace X { ... } → just skip the name, parse the block
    call cc_tok_next        ; namespace name
    call cc_tok_next        ; should be {
    cmp byte [cc_tok_type], CTK_LBRACE
    jne .csc_parse
    jmp .csc_parse          ; continue parsing inside namespace

.csc_class:
    ; class Name { ... }
    call cc_tok_next        ; class name
    call cc_tok_next        ; { or : base
    ; Skip base class/interfaces: : IFoo, IBar
    cmp byte [cc_tok_type], CTK_COLON
    jne .csc_class_body
.csc_skip_base:
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_LBRACE
    jne .csc_skip_base
.csc_class_body:
    ; Parse class body members
    jmp .csc_parse          ; continue: class body looks like top-level

.csc_modifier_loop:
    ; Skip modifier, continue
    jmp .csc_parse

.csc_done_parse:
    ; Check for Main method presence
    ; (csc_run_main_if_present handles it)
    call cc_patch_main_jump
    call cc_emit_data_section
    ; Apply string patches
    call csc_apply_str_patches

    mov ax, [cc_out]
    sub ax, COMP_BUF
    test ax, ax
    jz .csc_empty

    mov [_sh_copy_sz], ax
    push ds
    pop es
    mov si, COMP_BUF
    mov di, FILE_BUF
    mov cx, ax
    rep movsb

    call asm_make_outname
    call asm_write_output
    cmp byte [cc_err], 0
    jne .csc_fail

    mov al, ATTR_GREEN
    call vid_set_attr
    mov si, str_csc_done
    call vid_println
    mov al, ATTR_NORMAL
    call vid_set_attr
    jmp .csc_ret

.csc_empty:
    mov si, str_asm_empty
    call vid_println
    jmp .csc_ret

.csc_fail:
    ; error already printed

.csc_ret:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; csc_is_modifier - check if identifier is a C# modifier keyword
; CF=0 = is modifier; CF=1 = not modifier
; ============================================================
csc_is_modifier:
    push si
    push di
    mov si, cc_tok_str
    mov di, csc_str_PUBLIC
    call str_cmp
    jz .ism
    mov di, csc_str_PRIVATE
    call str_cmp
    jz .ism
    mov di, csc_str_STATIC
    call str_cmp
    jz .ism
    mov di, csc_str_INTERNAL
    call str_cmp
    jz .ism
    mov di, csc_str_SEALED
    call str_cmp
    jz .ism
    mov di, csc_str_ABSTRACT
    call str_cmp
    jz .ism
    mov di, csc_str_OVERRIDE
    call str_cmp
    jz .ism
    mov di, csc_str_VIRTUAL
    call str_cmp
    jz .ism
    ; Check for: int, void, string, bool (type keywords in C# context)
    mov di, cc_str_INT
    call str_cmp
    jz .ism_type
    mov di, cc_str_VOID
    call str_cmp
    jz .ism_type
    mov di, csc_str_STRING
    call str_cmp
    jz .ism_type
    mov di, csc_str_BOOL
    call str_cmp
    jz .ism_type
    pop di
    pop si
    stc
    ret
.ism_type:
    ; It's a type: parse as method or field declaration
    pop di
    pop si
    call csc_parse_member
    clc
    ret
.ism:
    pop di
    pop si
    clc
    ret

; ============================================================
; csc_parse_member - parse a class member (method or field)
; Current token: already past any modifiers, on the type keyword
; ============================================================
csc_parse_member:
    push ax
    push si
    ; We might be on a modifier (public, static, etc.) or a type
    ; Skip modifiers first
.cpm_skip_mods:
    cmp byte [cc_tok_type], CTK_IDENT
    jne .cpm_done
    call csc_is_modifier
    jnc .cpm_skip_mods  ; was a modifier
    ; Now on type keyword or method/field name
    ; Check if current tok is a type
    call cc_is_type
    jc .cpm_try_name    ; not a type keyword - might be identifier used as type
    ; Skip the type keyword
    call cc_tok_next
    jmp .cpm_get_name

.cpm_try_name:
    ; It's an identifier - could be a type name (like "string", "bool", or class name)
    mov di, csc_str_STRING
    mov si, cc_tok_str
    call str_cmp
    jz .cpm_skip_type_ident
    mov di, csc_str_BOOL
    call str_cmp
    jz .cpm_skip_type_ident
    mov di, csc_str_CONSOLE
    call str_cmp
    jz .cpm_done        ; Console.X → skip
    ; Treat as member name directly
    jmp .cpm_get_name

.cpm_skip_type_ident:
    call cc_tok_next    ; skip type name

.cpm_get_name:
    ; Current token should be the member name
    cmp byte [cc_tok_type], CTK_IDENT
    jne .cpm_done

    mov si, cc_tok_str
    mov di, asm_last_glb
    call str_copy

    ; Check for [] (array type indicator after name - skip)
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_LBRACK
    jne .cpm_check_paren
    call cc_tok_next    ; skip ]
    call cc_tok_next
    jmp .cpm_check_paren

.cpm_check_paren:
    cmp byte [cc_tok_type], CTK_LPAR
    je .cpm_method
    ; Field declaration: skip to ;
    call cc_skip_to_semi
    call cc_tok_next
    jmp .cpm_done

.cpm_method:
    ; It's a method: compile it
    ; Check if it's Main
    mov si, asm_last_glb
    mov di, cc_str_MAIN
    call str_cmp
    jnz .cpm_not_main
    ; Main method: record address
    mov ax, [cc_pc]
    mov [cc_main_addr], ax

.cpm_not_main:
    ; Skip parameter list
    mov cx, 1
.cpm_skip_params:
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_EOF
    je .cpm_done
    cmp byte [cc_tok_type], CTK_LPAR
    jne .cpm_not_lp
    inc cx
    jmp .cpm_skip_params
.cpm_not_lp:
    cmp byte [cc_tok_type], CTK_RPAR
    jne .cpm_skip_params
    dec cx
    jnz .cpm_skip_params

    call cc_tok_next    ; should be '{'
    cmp byte [cc_tok_type], CTK_LBRACE
    jne .cpm_done

    ; Define method symbol
    mov si, asm_last_glb
    mov ax, [cc_pc]
    call asm_sym_define

    ; Emit prologue
    mov al, 0x55
    call cc_emit_byte
    mov al, 0x89
    call cc_emit_byte
    mov al, 0xEC
    call cc_emit_byte
    mov al, 0x83
    call cc_emit_byte
    mov al, 0xEC
    call cc_emit_byte
    mov ax, [cc_out]
    sub ax, COMP_BUF
    mov [cc_frame_patch], ax
    mov al, 0
    call cc_emit_byte

    mov word [cc_frame_sz], 0
    mov word [cc_sym_cnt], 0
    mov byte [cc_in_func], 1

    ; Parse method body
    call cc_tok_next
.cpm_body_loop:
    cmp byte [cc_tok_type], CTK_RBRACE
    je .cpm_end_body
    cmp byte [cc_tok_type], CTK_EOF
    je .cpm_end_body
    ; Check for C#-specific statements
    cmp byte [cc_tok_type], CTK_IDENT
    jne .cpm_stmt
    mov si, cc_tok_str
    mov di, csc_str_CONSOLE
    call str_cmp
    jz .cpm_console
    jmp .cpm_stmt
.cpm_console:
    call csc_parse_console
    jmp .cpm_body_loop
.cpm_stmt:
    call cc_parse_statement
    cmp byte [cc_err], 0
    jne .cpm_end_body
    jmp .cpm_body_loop

.cpm_end_body:
    ; Patch frame size
    mov bx, [cc_frame_patch]
    add bx, COMP_BUF
    mov ax, [cc_frame_sz]
    mov [bx], al
    ; Epilogue
    mov al, 0x89
    call cc_emit_byte
    mov al, 0xE5
    call cc_emit_byte
    mov al, 0x5D
    call cc_emit_byte
    mov al, 0xC3
    call cc_emit_byte
    mov byte [cc_in_func], 0

.cpm_done:
    pop si
    pop ax
    ret

; ============================================================
; csc_parse_console - parse Console.WriteLine("str") / Console.Write("str")
; Current token is "CONSOLE"
; ============================================================
csc_parse_console:
    push ax
    call cc_tok_next    ; expect '.'
    cmp byte [cc_tok_type], CTK_DOT
    jne .pcon_skip
    call cc_tok_next    ; WRITELINE, WRITE, READLINE, etc.
    cmp byte [cc_tok_type], CTK_IDENT
    jne .pcon_skip
    ; Check which method
    mov si, cc_tok_str
    mov di, csc_str_WRITELINE
    call str_cmp
    jz .pcon_writeline
    mov di, csc_str_WRITE
    call str_cmp
    jz .pcon_write
    mov di, csc_str_READKEY
    call str_cmp
    jz .pcon_readkey
    jmp .pcon_skip

.pcon_writeline:
    ; Console.WriteLine("str") → print str + newline (same as puts)
    call cc_tok_next    ; '('
    cmp byte [cc_tok_type], CTK_LPAR
    jne .pcon_skip
    call cc_tok_next    ; argument
    cmp byte [cc_tok_type], CTK_STR
    jne .pcon_skip_parens
    ; Add newline to string
    mov bx, [cc_tok_val]
    mov byte [cc_tok_str + bx], 0x0A
    mov byte [cc_tok_str + bx + 1], 0
    inc word [cc_tok_val]
    call cc_add_string_literal  ; AX = data offset
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
    ; Print loop (LODSB/INT 0x10)
    call csc_emit_print_loop
    jmp .pcon_skip_parens

.pcon_write:
    ; Console.Write("str") → print str without newline
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_LPAR
    jne .pcon_skip
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_STR
    jne .pcon_skip_parens
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
    call csc_emit_print_loop
    jmp .pcon_skip_parens

.pcon_readkey:
    ; Console.ReadKey() → INT 16h
    call cc_tok_next
    cmp byte [cc_tok_type], CTK_LPAR
    jne .pcon_skip
    call cc_tok_next    ; )
    mov al, 0xB4
    call cc_emit_byte
    mov al, 0x00        ; MOV AH, 0 (wait for key)
    call cc_emit_byte
    mov al, 0xCD
    call cc_emit_byte
    mov al, 0x16        ; INT 0x16
    call cc_emit_byte

.pcon_skip_parens:
    ; Skip to ')' and ';'
    call cc_skip_to_semi
    call cc_tok_next
    pop ax
    ret

.pcon_skip:
    call cc_skip_to_semi
    call cc_tok_next
    pop ax
    ret

; ============================================================
; csc_emit_print_loop - emit LODSB loop to print null-term string in SI
; ============================================================
csc_emit_print_loop:
    push ax
    ; SI points to string; loop until null
    ; LODSB; OR AL, AL; JZ +5; MOV AH, 0E; XOR BH, BH; INT 10; JMP back
    mov al, 0xAC        ; LODSB
    call cc_emit_byte
    mov al, 0x08        ; OR AL, AL
    call cc_emit_byte
    mov al, 0xC0
    call cc_emit_byte
    mov al, 0x74        ; JZ +5 (past the INT 10 and JMP)
    call cc_emit_byte
    mov al, 0x05
    call cc_emit_byte
    mov al, 0xB4        ; MOV AH, 0x0E
    call cc_emit_byte
    mov al, 0x0E
    call cc_emit_byte
    mov al, 0xB7        ; MOV BH, 0
    call cc_emit_byte
    xor al, al
    call cc_emit_byte
    mov al, 0xCD        ; INT 0x10
    call cc_emit_byte
    mov al, 0x10
    call cc_emit_byte
    mov al, 0xEB        ; JMP -12 (back to LODSB)
    call cc_emit_byte
    mov al, 0xF2
    call cc_emit_byte
    pop ax
    ret

; ============================================================
; csc_apply_str_patches - patch string addresses in output
; Must be called AFTER cc_emit_data_section
; ============================================================
csc_apply_str_patches:
    push ax
    push bx
    push cx
    push si
    ; data section starts at: pc_base + (cc_out - COMP_BUF) - cc_data_size
    ; But we need to apply patches BEFORE copying to FILE_BUF
    ; At this point cc_out already includes data_size (emitted by emit_data_section)
    ; data_start_vaddr = pc_base + (cc_out - COMP_BUF) - cc_data_size
    mov ax, [cc_out]
    sub ax, COMP_BUF
    sub ax, [cc_data_size]      ; ax = code_section_size
    add ax, [asm_pc_base]       ; ax = virtual addr of data section start

    mov cx, [cc_str_patch_cnt]
    xor si, si
.casp_loop:
    test cx, cx
    jz .casp_done
    mov bx, si
    shl bx, 2                   ; bx = si * 4 (2 words per entry)
    mov di, [cc_str_patches + bx]       ; output offset
    mov dx, [cc_str_patches + bx + 2]   ; data section offset
    ; Compute virtual address of this string
    push ax
    add ax, dx                  ; ax = vaddr of string
    ; Patch at COMP_BUF + di
    push di
    add di, COMP_BUF
    mov [di], ax                ; store 16-bit address
    pop di
    pop ax
    inc si
    dec cx
    jmp .casp_loop
.casp_done:
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; C# string constants
; ============================================================
csc_str_USING:      db "USING",0
csc_str_NAMESPACE:  db "NAMESPACE",0
csc_str_CLASS:      db "CLASS",0
csc_str_PUBLIC:     db "PUBLIC",0
csc_str_PRIVATE:    db "PRIVATE",0
csc_str_STATIC:     db "STATIC",0
csc_str_INTERNAL:   db "INTERNAL",0
csc_str_SEALED:     db "SEALED",0
csc_str_ABSTRACT:   db "ABSTRACT",0
csc_str_OVERRIDE:   db "OVERRIDE",0
csc_str_VIRTUAL:    db "VIRTUAL",0
csc_str_STRING:     db "STRING",0
csc_str_BOOL:       db "BOOL",0
csc_str_CONSOLE:    db "CONSOLE",0
csc_str_WRITELINE:  db "WRITELINE",0
csc_str_WRITE:      db "WRITE",0
csc_str_READKEY:    db "READKEY",0
str_csc_done:       db "C# compilation successful. Output: A.COM", 0
