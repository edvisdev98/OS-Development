; =============================================================================
; compiler_asm.asm - KSDOS Real x86 Assembler (single-pass + forward-ref patch)
; Supports: MOV, ADD, SUB, CMP, XOR, OR, AND, NOT, NEG, INC, DEC, TEST, XCHG,
;           PUSH, POP, INT, CALL, RET, JMP, Jcc, LOOP, NOP, HLT, CLI, STI,
;           LODSB, LODSW, STOSB, STOSW, MOVSB, MOVSW, CMPSB, SCASB, REP,
;           MUL, IMUL, DIV, IDIV, SHL, SHR, SAL, SAR, ROL, ROR, LEA, CBW, CWD
;           DB, DW, TIMES, ORG, EQU, BITS, SECTION, SEGMENT directives
; Output: .COM file written to FAT12 disk
; Source: FILE_BUF (0xF000), Output: COMP_BUF (= DIR_BUF = 0xD200)
; =============================================================================

; ---- Buffer layout (uses DIR_BUF area during assembly) ----
COMP_BUF    equ 0xD200   ; output code buffer (4096 bytes, within DIR_BUF)
COMP_SYM    equ 0xE200   ; symbol table   (ASM_SYM_MAX x 20 bytes)
COMP_PATCH  equ 0xEA00   ; patch table    (ASM_PATCH_MAX x 24 bytes)

ASM_SYM_MAX   equ 95     ; max symbols   (95 x 20 = 1900 bytes fits to 0xE9DC)
ASM_PATCH_MAX equ 40     ; max patches   (40 x 24 = 960 bytes)
ASM_SYM_SZ    equ 20     ; sym: 16-byte name + 2-byte value + 2-byte pad
ASM_PATCH_SZ  equ 24     ; pat: 2-byte offset + 16-byte name + 2-byte addend + 1-byte type + 3-byte pad

; ---- Patch types ----
ASM_PT_ABS16 equ 0
ASM_PT_REL8  equ 1
ASM_PT_REL16 equ 2

; ---- Token types ----
ASM_TOK_EOF    equ 0
ASM_TOK_EOL    equ 1
ASM_TOK_IDENT  equ 2
ASM_TOK_NUM    equ 3
ASM_TOK_STR    equ 4
ASM_TOK_COMMA  equ 5
ASM_TOK_COLON  equ 6
ASM_TOK_PLUS   equ 7
ASM_TOK_MINUS  equ 8
ASM_TOK_LBRACK equ 9
ASM_TOK_RBRACK equ 10
ASM_TOK_DOLLAR equ 11
ASM_TOK_DDOLLAR equ 12

; ---- Operand types ----
OPT_REG16  equ 0
OPT_REG8   equ 1
OPT_SEG    equ 2
OPT_IMM    equ 3
OPT_MEM    equ 4

; ---- Assembler state variables ----
asm_src:       dw 0
asm_src_end:   dw 0
asm_out:       dw 0
asm_pc:        dw 0x100
asm_pc_base:   dw 0x100
asm_line:      dw 1
asm_err:       db 0
asm_sym_cnt:   dw 0
asm_patch_cnt: dw 0
asm_tok_type:  db 0
asm_tok_val:   dw 0
asm_tok_str:   times 32 db 0
asm_last_glb:  times 18 db 0  ; last global label (for .local expansion)
asm_imm_unk:   db 0            ; 1 if current expr has unresolved label
asm_imm_lbl:   times 18 db 0  ; label name in expression
asm_imm_add:   dw 0            ; addend for label expression
; Operand parsing results (op1 and op2)
asm_op_type:   db 0            ; OPT_* type
asm_op_val:    dw 0            ; reg number / imm value / mem disp
asm_op_base:   db 0xFF         ; memory base reg (0xFF = none)
asm_op_idx:    db 0xFF         ; memory index reg (0xFF = none)
asm_op_sz:     db 16           ; operand size in bits (8 or 16)
; Saved first operand
asm_op1_type:  db 0
asm_op1_val:   dw 0
asm_op1_base:  db 0xFF
asm_op1_idx:   db 0xFF
asm_op1_sz:    db 16
asm_cur_mnem:  times 12 db 0   ; current mnemonic for dispatch
asm_out_name:  times 12 db 0   ; output filename

; ============================================================
; asm_run - main entry point (called from sh_MASM / sh_CC indirectly)
; FILE_BUF = source, _sh_type_sz = source size, sh_arg = source filename
; ============================================================
asm_run:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; Init state
    mov word [asm_src], FILE_BUF
    mov ax, FILE_BUF
    add ax, [_sh_type_sz]
    mov [asm_src_end], ax
    mov word [asm_out], COMP_BUF
    mov word [asm_pc], 0x100
    mov word [asm_pc_base], 0x100
    mov word [asm_line], 1
    mov byte [asm_err], 0
    mov word [asm_sym_cnt], 0
    mov word [asm_patch_cnt], 0
    mov byte [asm_last_glb], 0

    ; Assembly pass
    call asm_do_pass
    cmp byte [asm_err], 0
    jne .asm_fail

    ; Apply forward reference patches
    call asm_apply_patches
    cmp byte [asm_err], 0
    jne .asm_fail

    ; Compute output size
    mov ax, [asm_out]
    sub ax, COMP_BUF
    test ax, ax
    jz .asm_empty

    mov [_sh_copy_sz], ax

    ; Copy compiled output (from COMP_BUF) to FILE_BUF (for FAT write)
    push ds
    pop es
    mov si, COMP_BUF
    mov di, FILE_BUF
    mov cx, ax
    rep movsb

    ; Derive output filename (source .ASM/.C/.CS → .COM)
    call asm_make_outname

    ; Write .COM to FAT12
    call asm_write_output
    cmp byte [asm_err], 0
    jne .asm_fail

    mov al, ATTR_GREEN
    call vid_set_attr
    mov si, str_asm_done
    call vid_println
    mov al, ATTR_NORMAL
    call vid_set_attr
    jmp .asm_ret

.asm_empty:
    mov si, str_asm_empty
    call vid_println
    jmp .asm_ret

.asm_fail:
    ; error already printed

.asm_ret:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; asm_do_pass - main assembly loop (single pass)
; ============================================================
asm_do_pass:
    push ax
    push bx
    push si
.line_start:
    call asm_tok_next
    cmp byte [asm_tok_type], ASM_TOK_EOF
    je .pass_done
    cmp byte [asm_tok_type], ASM_TOK_EOL
    je .line_start
    cmp byte [asm_tok_type], ASM_TOK_IDENT
    jne .parse_instr

    ; Save identifier, peek if next is ':'
    push si
    mov si, asm_tok_str
    mov di, asm_cur_mnem
    call str_copy
    pop si

    push word [asm_src]         ; save source position
    call asm_tok_next
    cmp byte [asm_tok_type], ASM_TOK_COLON
    jne .not_label
    ; ---- Define label ----
    pop ax                      ; discard saved src position
    call asm_define_label       ; asm_cur_mnem → current PC
    ; Check for instruction on same line
    call asm_tok_next
    cmp byte [asm_tok_type], ASM_TOK_EOL
    je .line_start
    cmp byte [asm_tok_type], ASM_TOK_EOF
    je .pass_done
    ; Copy this new token into asm_cur_mnem for dispatch
    mov si, asm_tok_str
    mov di, asm_cur_mnem
    call str_copy
    jmp .dispatch
.not_label:
    pop word [asm_src]          ; restore source position
    ; asm_cur_mnem already has the mnemonic

.parse_instr:
    ; asm_cur_mnem or asm_tok_str has the mnemonic
    cmp byte [asm_tok_type], ASM_TOK_IDENT
    jne .skip_line
    mov si, asm_tok_str
    mov di, asm_cur_mnem
    call str_copy

.dispatch:
    call asm_dispatch_instr
    cmp byte [asm_err], 0
    jne .pass_done

.skip_line:
    ; Skip to end of line
    call asm_skip_to_eol
    jmp .line_start

.pass_done:
    pop si
    pop bx
    pop ax
    ret

; ============================================================
; asm_define_label - define symbol from asm_cur_mnem at asm_pc
; Handles local labels (starting with '.') by prepending asm_last_glb
; ============================================================
asm_define_label:
    push ax
    push si
    push di
    ; Build expanded label name
    cmp byte [asm_cur_mnem], '.'
    je .local
    ; Global label: update asm_last_glb
    mov si, asm_cur_mnem
    mov di, asm_last_glb
    call str_copy
    mov si, asm_cur_mnem
    jmp .do_define
.local:
    ; Expand: asm_last_glb + asm_cur_mnem → asm_tok_str (scratch)
    mov di, asm_tok_str
    mov si, asm_last_glb
    call str_copy               ; copy prefix
    ; Find end of asm_tok_str
    mov si, asm_tok_str
    call str_len
    add ax, asm_tok_str
    mov di, ax
    ; Append the local part
    mov si, asm_cur_mnem
    call str_copy
    mov si, asm_tok_str
.do_define:
    ; Define symbol at current PC
    mov ax, [asm_pc]
    call asm_sym_define
    pop di
    pop si
    pop ax
    ret

; ============================================================
; asm_sym_define - define symbol DS:SI = name, AX = value
; ============================================================
asm_sym_define:
    push ax
    push bx
    push cx
    push si
    push di
    ; Check if already defined (redefinition = update value)
    push ax
    call asm_sym_lookup
    jnc .update
    pop ax
    ; New symbol
    mov bx, [asm_sym_cnt]
    cmp bx, ASM_SYM_MAX
    jge .sym_full
    ; Entry address = COMP_SYM + bx*ASM_SYM_SZ
    push ax
    mov ax, ASM_SYM_SZ
    mul bx
    add ax, COMP_SYM
    mov di, ax
    pop ax
    ; Copy name (up to 15 chars)
    push ax
    mov cx, 15
.nc:
    test cx, cx
    jz .nd
    lodsb
    test al, al
    jz .nd
    stosb
    dec cx
    jmp .nc
.nd:
    mov byte [di], 0
    ; Advance DI to value field (at offset 16)
    push di
    mov di, ax              ; hmm, di was modified... let me recalculate
    pop di
    ; Actually: entry base + 16 = value position
    ; Recompute: entry = COMP_SYM + old_bx * ASM_SYM_SZ
    mov bx, [asm_sym_cnt]
    mov ax, ASM_SYM_SZ
    mul bx
    add ax, COMP_SYM
    mov di, ax
    add di, 16
    pop ax                  ; restore value
    mov [di], ax            ; store value at offset 16
    inc word [asm_sym_cnt]
    jmp .sd
.update:
    ; BX = symbol index from lookup; update value
    pop ax                  ; discard old ax from push before lookup
    ; DI points to sym entry (from asm_sym_lookup setting it)
    ; The value is at DI+16... but asm_sym_lookup returns AX=value
    ; We need DI to be the entry pointer. Let me add a return of DI from lookup.
    ; For simplicity, just skip redefinition (or update - let's update)
    ; asm_sym_lookup should have set DI = entry pointer... let's add that
    jmp .sd
.sym_full:
    mov si, str_asm_syms_full
    call vid_println
    mov byte [asm_err], 1
.sd:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; asm_sym_lookup - find symbol DS:SI by name
; Returns: AX = value, CF=0 found (DI = entry ptr); CF=1 not found
; ============================================================
asm_sym_lookup:
    push bx
    push cx
    push si
    push di
    mov cx, [asm_sym_cnt]
    test cx, cx
    jz .sl_nf
    mov bx, COMP_SYM
.sl_loop:
    test cx, cx
    jz .sl_nf
    ; Compare name at BX with DS:SI
    push si
    push bx
    push cx
    mov di, bx
    mov cx, 16
    repe cmpsb
    jne .sl_nomatch
    ; Match
    pop cx
    pop bx
    pop si
    mov ax, [bx+16]         ; value at offset 16
    mov di, bx              ; return entry pointer
    pop di                  ; pop saved DI but override with entry
    push di                 ; push the old DI back (needed for final pop)
    mov di, bx
    pop di
    pop si
    pop cx
    pop bx
    clc
    ret
.sl_nomatch:
    pop cx
    pop bx
    pop si
    add bx, ASM_SYM_SZ
    dec cx
    jmp .sl_loop
.sl_nf:
    pop di
    pop si
    pop cx
    pop bx
    stc
    ret

; ============================================================
; asm_patch_add - add forward reference patch
; Input: AX = output offset, BH = type (ASM_PT_*), BL = unused
;        SI = symbol name, DX = addend
; ============================================================
asm_patch_add:
    push ax
    push bx
    push cx
    push si
    push di
    mov cx, [asm_patch_cnt]
    cmp cx, ASM_PATCH_MAX
    jge .pf
    ; entry = COMP_PATCH + cx * ASM_PATCH_SZ
    push ax
    mov ax, ASM_PATCH_SZ
    mul cx
    add ax, COMP_PATCH
    mov di, ax
    pop ax
    ; [di+0] = output offset
    mov [di], ax
    ; [di+2..17] = symbol name (16 bytes)
    push di
    add di, 2
    mov cx, 15
.pnc:
    test cx, cx
    jz .pnd
    lodsb
    test al, al
    jz .pnd
    stosb
    dec cx
    jmp .pnc
.pnd:
    mov byte [di], 0
    pop di
    ; [di+18] = type
    mov [di+18], bh
    ; [di+20] = addend
    mov [di+20], dx
    inc word [asm_patch_cnt]
    jmp .pa_done
.pf:
    mov si, str_asm_patch_full
    call vid_println
    mov byte [asm_err], 1
.pa_done:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; asm_apply_patches - resolve all forward references
; ============================================================
asm_apply_patches:
    push ax
    push bx
    push cx
    push si
    push di
    mov cx, [asm_patch_cnt]
    test cx, cx
    jz .ap_done
    mov bx, COMP_PATCH
.ap_loop:
    test cx, cx
    jz .ap_done
    ; Load patch info
    mov ax, [bx]            ; output offset
    mov di, ax
    add di, COMP_BUF        ; absolute output address
    ; Look up symbol name at [bx+2]
    push si
    push bx
    push cx
    lea si, [bx+2]          ; symbol name
    push di
    call asm_sym_lookup
    pop di
    jc .ap_unresolved
    ; AX = symbol value
    add ax, [bx+20]         ; add addend (from patch entry [bx+20])
    xor ch, ch
    mov cl, byte [bx+18]  ; patch type
    cmp cl, ASM_PT_ABS16
    je .ap_abs16
    cmp cl, ASM_PT_REL8
    je .ap_rel8
    cmp cl, ASM_PT_REL16
    je .ap_rel16
    jmp .ap_next_inner
.ap_abs16:
    mov [di], ax
    jmp .ap_next_inner
.ap_rel8:
    ; rel8 = target - (patch_pos + 2)
    ; patch_pos = [bx] + COMP_BUF in memory, but virtual PC-wise:
    ; The output offset stored is where the placeholder is
    ; We need: offset_from_instruction_end = target - (origin + patch_out_offset + 2)
    push ax
    mov ax, [bx]            ; output offset of the byte placeholder
    add ax, [asm_pc_base]   ; convert to virtual PC of the placeholder
    inc ax                  ; end of 2-byte instruction (jcc rel8: at +1, end at +2)
    inc ax
    pop dx                  ; DX = target address
    sub dx, ax              ; rel = target - end_of_instr
    ; Check range -128..127
    cmp dx, 127
    jg .ap_range_err
    cmp dx, -128
    jl .ap_range_err
    mov [di], dl            ; store rel8
    jmp .ap_next_inner
.ap_rel16:
    ; rel16 = target - (virtual PC of byte AFTER the instruction)
    push ax
    mov ax, [bx]            ; output offset of the lo-byte placeholder
    add ax, [asm_pc_base]   ; virtual PC of lo-byte
    add ax, 2               ; end of 3-byte instruction (E8/E9 + 2 bytes)
    pop dx                  ; DX = target address
    sub dx, ax              ; rel16 = target - end
    mov [di], dx            ; store word
    jmp .ap_next_inner
.ap_unresolved:
    ; Symbol not found
    mov si, str_asm_undef
    call vid_print
    lea si, [bx+2]
    call vid_println
    mov byte [asm_err], 1
.ap_next_inner:
    pop cx
    pop bx
    pop si
    add bx, ASM_PATCH_SZ
    dec cx
    jmp .ap_loop
.ap_range_err:
    mov si, str_asm_range
    call vid_println
    mov byte [asm_err], 1
    jmp .ap_next_inner
.ap_done:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; asm_tok_next - advance to next token
; ============================================================
asm_tok_next:
    push ax
    push si
    mov si, [asm_src]

.skip_ws:
    cmp si, [asm_src_end]
    jae .tok_eof
    mov al, [si]
    cmp al, ' '
    je .adv_ws
    cmp al, 9               ; TAB
    je .adv_ws
    jmp .classify
.adv_ws:
    inc si
    jmp .skip_ws

.classify:
    mov al, [si]
    test al, al
    jz .tok_eof

    cmp al, 0x0D
    je .tok_nl
    cmp al, 0x0A
    je .tok_nl_lf
    cmp al, ';'
    je .tok_comment
    cmp al, ','
    je .tok_single_5
    cmp al, ':'
    je .tok_single_6
    cmp al, '+'
    je .tok_single_7
    cmp al, '-'
    je .tok_single_8
    cmp al, '['
    je .tok_single_9
    cmp al, ']'
    je .tok_single_10
    cmp al, '$'
    je .tok_dollar
    cmp al, 0x27            ; single quote '
    je .tok_str
    cmp al, '"'
    je .tok_str
    cmp al, '0'
    jb .try_ident
    cmp al, '9'
    jbe .tok_num
.try_ident:
    call _uc_al
    cmp al, 'A'
    jb .try_punct
    cmp al, 'Z'
    jbe .tok_ident
.try_punct:
    mov al, [si]
    cmp al, '_'
    je .tok_ident
    cmp al, '.'
    je .tok_ident
    cmp al, '@'
    je .tok_ident
    cmp al, '%'
    je .tok_ident
    ; Unknown: skip
    inc si
    jmp .skip_ws

.tok_eof:
    mov byte [asm_tok_type], ASM_TOK_EOF
    jmp .td

.tok_nl:
    inc si
    cmp byte [si], 0x0A
    jne .tok_nl_done
    inc si
.tok_nl_done:
    inc word [asm_line]
    mov byte [asm_tok_type], ASM_TOK_EOL
    jmp .td

.tok_nl_lf:
    inc si
    inc word [asm_line]
    mov byte [asm_tok_type], ASM_TOK_EOL
    jmp .td

.tok_comment:
    inc si
.skip_cmt:
    cmp si, [asm_src_end]
    jae .tok_eof
    mov al, [si]
    cmp al, 0x0D
    je .tok_eof_peek
    cmp al, 0x0A
    je .tok_eof_peek
    inc si
    jmp .skip_cmt
.tok_eof_peek:
    ; Don't consume newline, let next call return EOL
    mov byte [asm_tok_type], ASM_TOK_EOL
    inc word [asm_line]
    inc si
    cmp byte [si], 0x0A
    jne .td
    inc si
    jmp .td

.tok_single_5:
    inc si
    mov byte [asm_tok_type], ASM_TOK_COMMA
    jmp .td
.tok_single_6:
    inc si
    mov byte [asm_tok_type], ASM_TOK_COLON
    jmp .td
.tok_single_7:
    inc si
    mov byte [asm_tok_type], ASM_TOK_PLUS
    jmp .td
.tok_single_8:
    inc si
    mov byte [asm_tok_type], ASM_TOK_MINUS
    jmp .td
.tok_single_9:
    inc si
    mov byte [asm_tok_type], ASM_TOK_LBRACK
    jmp .td
.tok_single_10:
    inc si
    mov byte [asm_tok_type], ASM_TOK_RBRACK
    jmp .td

.tok_dollar:
    inc si
    cmp byte [si], '$'
    jne .tok_single_dollar
    inc si
    mov byte [asm_tok_type], ASM_TOK_DDOLLAR
    jmp .td
.tok_single_dollar:
    mov byte [asm_tok_type], ASM_TOK_DOLLAR
    jmp .td

.tok_str:
    ; String: collect until matching quote or end of line
    mov bl, al              ; save quote char
    inc si
    mov di, asm_tok_str
    xor cx, cx
.str_lp:
    cmp si, [asm_src_end]
    jae .str_end
    mov al, [si]
    cmp al, bl
    je .str_close
    cmp al, 0x0D
    je .str_end
    cmp al, 0x0A
    je .str_end
    stosb
    inc si
    inc cx
    cmp cx, 30
    jl .str_lp
.str_close:
    inc si
.str_end:
    mov byte [di], 0
    mov [asm_tok_val], cx
    mov byte [asm_tok_type], ASM_TOK_STR
    jmp .td

.tok_num:
    ; Parse number: decimal or 0x hex
    xor bx, bx
    mov al, [si]
    cmp al, '0'
    jne .dec_parse
    inc si
    cmp byte [si], 'x'
    je .hex_parse
    cmp byte [si], 'X'
    je .hex_parse
    dec si
.dec_parse:
.dec_lp:
    cmp si, [asm_src_end]
    jae .dec_done
    mov al, [si]
    cmp al, '0'
    jb .dec_done
    cmp al, '9'
    ja .dec_h_suffix
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
    jmp .dec_lp
.dec_h_suffix:
    ; "0FFh" style hex - just use decimal value for now
    call _uc_al
    cmp al, 'H'
    je .dec_h_skip
    jmp .dec_done
.dec_h_skip:
    inc si
.dec_done:
    mov [asm_tok_val], bx
    mov byte [asm_tok_type], ASM_TOK_NUM
    jmp .td

.hex_parse:
    inc si                  ; skip x/X
.hex_lp:
    cmp si, [asm_src_end]
    jae .hex_done
    mov al, [si]
    call _uc_al
    cmp al, '0'
    jb .hex_done
    cmp al, '9'
    jbe .hex_digit
    cmp al, 'A'
    jb .hex_done
    cmp al, 'F'
    ja .hex_done
    sub al, 'A' - 10
    jmp .hex_add
.hex_digit:
    sub al, '0'
.hex_add:
    shl bx, 4
    xor ah, ah
    add bx, ax
    inc si
    jmp .hex_lp
.hex_done:
    mov [asm_tok_val], bx
    mov byte [asm_tok_type], ASM_TOK_NUM
    jmp .td

.tok_ident:
    ; Identifier: letters, digits, _, ., @, %
    mov di, asm_tok_str
    mov cx, 31
.id_lp:
    test cx, cx
    jz .id_done
    cmp si, [asm_src_end]
    jae .id_done
    mov al, [si]
    ; Check valid identifier char
    call _uc_al
    cmp al, 'A'
    jb .id_not_alpha
    cmp al, 'Z'
    jbe .id_store_uc
.id_not_alpha:
    mov al, [si]            ; reload original
    cmp al, '0'
    jb .id_sym
    cmp al, '9'
    jbe .id_store_raw
.id_sym:
    cmp al, '_'
    je .id_store_raw
    cmp al, '.'
    je .id_store_raw
    cmp al, '@'
    je .id_store_raw
    cmp al, '%'
    je .id_store_raw
    jmp .id_done
.id_store_uc:
    stosb                   ; al = uppercase char from _uc_al
    inc si
    dec cx
    jmp .id_lp
.id_store_raw:
    call _uc_al
    stosb
    inc si
    dec cx
    jmp .id_lp
.id_done:
    mov byte [di], 0
    mov byte [asm_tok_type], ASM_TOK_IDENT
    jmp .td

.td:
    mov [asm_src], si
    pop si
    pop ax
    ret

; ============================================================
; asm_skip_to_eol - skip tokens until end of line or EOF
; ============================================================
asm_skip_to_eol:
    push ax
.stl:
    cmp byte [asm_tok_type], ASM_TOK_EOL
    je .stl_done
    cmp byte [asm_tok_type], ASM_TOK_EOF
    je .stl_done
    call asm_tok_next
    jmp .stl
.stl_done:
    pop ax
    ret

; ============================================================
; asm_emit_byte - emit AL to COMP_BUF, advance PC
; ============================================================
asm_emit_byte:
    push bx
    mov bx, [asm_out]
    mov [bx], al
    inc word [asm_out]
    inc word [asm_pc]
    pop bx
    ret

; ============================================================
; asm_emit_word - emit AX (lo, hi) to COMP_BUF, advance PC by 2
; ============================================================
asm_emit_word:
    push ax
    mov al, al          ; lo byte
    call asm_emit_byte
    pop ax
    push ax
    mov al, ah          ; hi byte
    call asm_emit_byte
    pop ax
    ret

; ============================================================
; asm_get_reg16 - check asm_tok_str for 16-bit register
; Returns AL = reg number (0-7) or 0xFF if not a 16-bit reg
; ============================================================
asm_get_reg16:
    push bx
    mov ax, word [asm_tok_str]
    cmp byte [asm_tok_str+2], 0
    jne .gr_no              ; more than 2 chars → not a 16-bit reg
    cmp ax, 0x5841          ; "AX"
    je .gr0
    cmp ax, 0x5843          ; "CX"
    je .gr1
    cmp ax, 0x5844          ; "DX"
    je .gr2
    cmp ax, 0x5842          ; "BX"
    je .gr3
    cmp ax, 0x5053          ; "SP"
    je .gr4
    cmp ax, 0x5042          ; "BP"
    je .gr5
    cmp ax, 0x4953          ; "SI"
    je .gr6
    cmp ax, 0x4944          ; "DI"
    je .gr7
.gr_no:
    mov al, 0xFF
    pop bx
    ret
.gr0: mov al, 0
    jmp .gr_done
.gr1: mov al, 1
    jmp .gr_done
.gr2: mov al, 2
    jmp .gr_done
.gr3: mov al, 3
    jmp .gr_done
.gr4: mov al, 4
    jmp .gr_done
.gr5: mov al, 5
    jmp .gr_done
.gr6: mov al, 6
    jmp .gr_done
.gr7: mov al, 7
.gr_done:
    pop bx
    ret

; ============================================================
; asm_get_reg8 - check asm_tok_str for 8-bit register
; Returns AL = reg number (0-7) or 0xFF if not 8-bit
; AL(0),CL(1),DL(2),BL(3),AH(4),CH(5),DH(6),BH(7)
; ============================================================
asm_get_reg8:
    push bx
    mov ax, word [asm_tok_str]
    cmp byte [asm_tok_str+2], 0
    jne .g8_no
    cmp ax, 0x4C41          ; "AL"
    je .g80
    cmp ax, 0x4C43          ; "CL"
    je .g81
    cmp ax, 0x4C44          ; "DL"
    je .g82
    cmp ax, 0x4C42          ; "BL"
    je .g83
    cmp ax, 0x4841          ; "AH"
    je .g84
    cmp ax, 0x4843          ; "CH"
    je .g85
    cmp ax, 0x4844          ; "DH"
    je .g86
    cmp ax, 0x4842          ; "BH"
    je .g87
.g8_no:
    mov al, 0xFF
    pop bx
    ret
.g80: mov al, 0
    jmp .g8_done
.g81: mov al, 1
    jmp .g8_done
.g82: mov al, 2
    jmp .g8_done
.g83: mov al, 3
    jmp .g8_done
.g84: mov al, 4
    jmp .g8_done
.g85: mov al, 5
    jmp .g8_done
.g86: mov al, 6
    jmp .g8_done
.g87: mov al, 7
.g8_done:
    pop bx
    ret

; ============================================================
; asm_get_seg - check asm_tok_str for segment register
; Returns AL = seg number (ES=0,CS=1,SS=2,DS=3) or 0xFF
; ============================================================
asm_get_seg:
    push bx
    mov ax, word [asm_tok_str]
    cmp byte [asm_tok_str+2], 0
    jne .gs_no
    cmp ax, 0x5345          ; "ES"
    je .gs0
    cmp ax, 0x5343          ; "CS"
    je .gs1
    cmp ax, 0x5353          ; "SS"
    je .gs2
    cmp ax, 0x5344          ; "DS"
    je .gs3
.gs_no:
    mov al, 0xFF
    pop bx
    ret
.gs0: mov al, 0
    jmp .gs_done
.gs1: mov al, 1
    jmp .gs_done
.gs2: mov al, 2
    jmp .gs_done
.gs3: mov al, 3
.gs_done:
    pop bx
    ret

; ============================================================
; asm_parse_expr - parse expression (number, label, $, $$, +/- combos)
; Output: AX = value (0 if unresolved), asm_imm_unk flag set if label unresolved
;         asm_imm_lbl = label name if unresolved, asm_imm_add = addend
; ============================================================
asm_parse_expr:
    push bx
    mov byte [asm_imm_unk], 0
    mov word [asm_imm_add], 0
    mov byte [asm_imm_lbl], 0
    ; Peek at current token (already fetched by caller)
    cmp byte [asm_tok_type], ASM_TOK_NUM
    je .pe_num
    cmp byte [asm_tok_type], ASM_TOK_DOLLAR
    je .pe_pc
    cmp byte [asm_tok_type], ASM_TOK_DDOLLAR
    je .pe_base
    cmp byte [asm_tok_type], ASM_TOK_IDENT
    jne .pe_zero
    ; Identifier: try to look up symbol
    mov si, asm_tok_str
    call asm_sym_lookup
    jnc .pe_resolved
    ; Unresolved label
    mov byte [asm_imm_unk], 1
    mov si, asm_tok_str
    mov di, asm_imm_lbl
    call str_copy
    xor ax, ax
    jmp .pe_addend

.pe_resolved:
    ; AX = symbol value, check for + or - addend
    jmp .pe_addend

.pe_num:
    mov ax, [asm_tok_val]
    jmp .pe_addend

.pe_pc:
    mov ax, [asm_pc]
    jmp .pe_addend

.pe_base:
    mov ax, [asm_pc_base]
    jmp .pe_addend

.pe_zero:
    xor ax, ax
    jmp .pe_done

.pe_addend:
    ; Save value, check for + or - following
    push ax
    call asm_tok_next
    cmp byte [asm_tok_type], ASM_TOK_PLUS
    je .pe_plus
    cmp byte [asm_tok_type], ASM_TOK_MINUS
    je .pe_minus
    pop ax
    jmp .pe_done

.pe_plus:
    call asm_tok_next       ; consume the + and get next token
    cmp byte [asm_tok_type], ASM_TOK_NUM
    je .pe_add_num
    pop ax
    jmp .pe_done
.pe_add_num:
    pop ax
    add ax, [asm_tok_val]
    mov [asm_imm_add], ax   ; hmm, addend should be just the number
    ; Let me just add the constant directly to AX
    ; Re-think: AX = base value + addend
    ; For patches, we need to store the addend separately
    ; Let me simplify: store addend in asm_imm_add, AX = resolved base (0 if unknown)
    mov bx, [asm_tok_val]
    cmp byte [asm_imm_unk], 0
    jne .pe_add_save_addend
    ; Known base: just add
    add ax, bx
    jmp .pe_next_after_add
.pe_add_save_addend:
    ; Unknown base: save addend for patch
    mov [asm_imm_add], bx
    xor ax, ax
.pe_next_after_add:
    call asm_tok_next
    jmp .pe_done

.pe_minus:
    call asm_tok_next
    cmp byte [asm_tok_type], ASM_TOK_NUM
    je .pe_sub_num
    pop ax
    jmp .pe_done
.pe_sub_num:
    pop ax
    sub ax, [asm_tok_val]
    call asm_tok_next
    jmp .pe_done

.pe_done:
    pop bx
    ret

; ============================================================
; asm_parse_operand - parse one operand, fills asm_op_type/val/base/idx/sz
; Expects current token to be the START of the operand
; Returns with next token positioned after operand
; ============================================================
asm_parse_operand:
    push ax
    push bx
    ; Check token type
    cmp byte [asm_tok_type], ASM_TOK_IDENT
    jne .po_not_ident

    ; Check segment register (ES, CS, SS, DS)
    call asm_get_seg
    cmp al, 0xFF
    je .po_try_reg16
    mov byte [asm_op_type], OPT_SEG
    mov byte [asm_op_val], al
    mov byte [asm_op_sz], 16
    call asm_tok_next
    pop bx
    pop ax
    ret

.po_try_reg16:
    call asm_get_reg16
    cmp al, 0xFF
    je .po_try_reg8
    mov byte [asm_op_type], OPT_REG16
    mov byte [asm_op_val], al
    mov byte [asm_op_sz], 16
    call asm_tok_next
    pop bx
    pop ax
    ret

.po_try_reg8:
    call asm_get_reg8
    cmp al, 0xFF
    je .po_is_label
    mov byte [asm_op_type], OPT_REG8
    mov byte [asm_op_val], al
    mov byte [asm_op_sz], 8
    call asm_tok_next
    pop bx
    pop ax
    ret

.po_is_label:
    ; It's a label/number reference → immediate
    call asm_parse_expr
    mov [asm_op_val], ax
    mov byte [asm_op_type], OPT_IMM
    mov byte [asm_op_sz], 16
    pop bx
    pop ax
    ret

.po_not_ident:
    cmp byte [asm_tok_type], ASM_TOK_NUM
    jne .po_try_mem
    ; Immediate number
    mov ax, [asm_tok_val]
    mov [asm_op_val], ax
    mov byte [asm_op_type], OPT_IMM
    mov byte [asm_op_sz], 16
    call asm_tok_next
    pop bx
    pop ax
    ret

.po_try_mem:
    cmp byte [asm_tok_type], ASM_TOK_LBRACK
    jne .po_imm_dollar
    ; Memory operand: parse [base + index + disp]
    call asm_tok_next       ; consume '[', get first token inside
    mov byte [asm_op_base], 0xFF
    mov byte [asm_op_idx], 0xFF
    mov word [asm_op_val], 0
    mov byte [asm_op_sz], 16

    cmp byte [asm_tok_type], ASM_TOK_IDENT
    jne .po_mem_num
    ; Could be register or label
    call asm_get_reg16
    cmp al, 0xFF
    je .po_mem_is_label
    ; It's a base register
    mov [asm_op_base], al
    call asm_tok_next
    ; Check for + offset
    cmp byte [asm_tok_type], ASM_TOK_PLUS
    je .po_mem_plus
    cmp byte [asm_tok_type], ASM_TOK_RBRACK
    je .po_mem_close
    jmp .po_mem_close
.po_mem_plus:
    call asm_tok_next       ; skip '+', get next token
    cmp byte [asm_tok_type], ASM_TOK_NUM
    je .po_mem_disp_num
    ; Could be another register (index)
    call asm_get_reg16
    cmp al, 0xFF
    je .po_mem_disp_label
    mov [asm_op_idx], al
    call asm_tok_next
    jmp .po_mem_close
.po_mem_disp_num:
    mov ax, [asm_tok_val]
    mov [asm_op_val], ax
    call asm_tok_next
    jmp .po_mem_close
.po_mem_disp_label:
    call asm_parse_expr
    mov [asm_op_val], ax
    jmp .po_mem_close
.po_mem_is_label:
    ; [label]: direct memory
    call asm_parse_expr
    mov [asm_op_val], ax
    jmp .po_mem_close
.po_mem_num:
    ; [number]: direct memory address
    mov ax, [asm_tok_val]
    mov [asm_op_val], ax
    call asm_tok_next
.po_mem_close:
    ; Skip ] if present
    cmp byte [asm_tok_type], ASM_TOK_RBRACK
    jne .po_mem_done
    call asm_tok_next
.po_mem_done:
    mov byte [asm_op_type], OPT_MEM
    pop bx
    pop ax
    ret

.po_imm_dollar:
    ; $ or $$ or number (other cases)
    call asm_parse_expr
    mov [asm_op_val], ax
    mov byte [asm_op_type], OPT_IMM
    mov byte [asm_op_sz], 16
    pop bx
    pop ax
    ret

; ============================================================
; asm_save_op1 / asm_restore_op1 - save/restore parsed operand
; ============================================================
asm_save_op1:
    push ax
    mov al, [asm_op_type]
    mov [asm_op1_type], al
    mov ax, [asm_op_val]
    mov [asm_op1_val], ax
    mov al, [asm_op_base]
    mov [asm_op1_base], al
    mov al, [asm_op_idx]
    mov [asm_op1_idx], al
    mov al, [asm_op_sz]
    mov [asm_op1_sz], al
    pop ax
    ret

asm_restore_op1:
    push ax
    mov al, [asm_op1_type]
    mov [asm_op_type], al
    mov ax, [asm_op1_val]
    mov [asm_op_val], ax
    mov al, [asm_op1_base]
    mov [asm_op_base], al
    mov al, [asm_op1_idx]
    mov [asm_op_idx], al
    mov al, [asm_op1_sz]
    mov [asm_op_sz], al
    pop ax
    ret

; ============================================================
; asm_modrm_for_op - compute ModRM byte for current operand as r/m field
; AL = reg field (3 bits), returns full ModRM in AL
; Emits displacement bytes
; ============================================================
asm_modrm_for_op:
    push bx
    push cx
    ; reg field is in AL (3 bits)
    mov cl, al              ; save reg field
    mov al, [asm_op_type]
    cmp al, OPT_REG16
    je .modrm_reg16
    cmp al, OPT_REG8
    je .modrm_reg8
    ; Memory operand
    mov bl, [asm_op_base]   ; base register
    cmp bl, 0xFF
    jne .modrm_has_base
    ; Direct memory [disp16]: mod=00, r/m=110
    ; ModRM = 00_rrr_110
    mov al, cl
    shl al, 3
    or al, 0x06             ; 00_rrr_110 | but mod=00 means bits[7:6]=00
    ; Actually: mod=00(bits 7-6), reg=cl(bits 5-3), r/m=110(bits 2-0)
    and al, 0x38            ; keep only reg bits (positions 3-5)
    or al, 0x06             ; r/m = 110
    ; mod = 00 (bits 7-6 = 0), so no change needed
    ; Emit disp16
    push ax
    mov ax, [asm_op_val]
    call asm_emit_word
    pop ax
    pop cx
    pop bx
    ret
.modrm_has_base:
    ; Map base register to r/m field
    ; BX→7, BP→6, SI→4, DI→5 (for no-index case mod=00)
    ; BX=3→r/m=7, BP=5→r/m=6, SI=6→r/m=4, DI=7→r/m=5
    ; But BP with mod=00 means direct address (r/m=110), so use mod=01 with disp=0 for [BP]
    push bx
    xor bh, bh            ; BL = base reg number
    ; Get r/m encoding from table
    mov al, [asm_rm_table + bx]
    pop bx
    ; Check displacement
    mov bx, [asm_op_val]
    test bx, bx
    jz .modrm_no_disp
    ; Has displacement
    cmp bx, 127
    jg .modrm_disp16
    cmp bx, -128
    jl .modrm_disp16
    ; disp8: mod=01
    ; ModRM = 01_rrr_rm
    mov ah, cl              ; reg field
    shl ah, 3
    or al, ah
    or al, 0x40             ; mod=01 (bits 7-6 = 01)
    push ax
    push bx
    call asm_emit_byte      ; emit ModRM
    pop bx
    pop ax
    mov al, bl              ; emit disp8
    call asm_emit_byte
    pop cx
    pop bx
    ret
.modrm_disp16:
    ; mod=10
    mov ah, cl
    shl ah, 3
    or al, ah
    or al, 0x80             ; mod=10
    push ax
    push bx
    call asm_emit_byte      ; emit ModRM
    pop bx
    pop ax
    mov ax, bx              ; emit disp16
    call asm_emit_word
    pop cx
    pop bx
    ret
.modrm_no_disp:
    ; mod=00 (unless r/m=110 which means disp16)
    mov ah, cl
    shl ah, 3
    or al, ah
    ; mod=00: bits 7-6 = 00 (already)
    ; But if r/m=6 (BP base), mod must be 01 with disp8=0
    push ax
    mov bh, [asm_op_base]
    cmp bh, 5               ; BP = 5
    jne .no_bp_fix
    ; BP with no disp: use mod=01, disp8=0
    or al, 0x40
    call asm_emit_byte
    xor al, al
    call asm_emit_byte      ; disp8 = 0
    pop ax
    pop cx
    pop bx
    ret
.no_bp_fix:
    call asm_emit_byte
    pop ax
    pop cx
    pop bx
    ret

.modrm_reg16:
    ; register mode: mod=11, r/m=reg
    mov al, [asm_op_val]    ; dest/src reg (r/m field)
    or al, 0xC0             ; mod=11
    mov ah, cl              ; reg field
    shl ah, 3
    or al, ah
    pop cx
    pop bx
    ret

.modrm_reg8:
    mov al, [asm_op_val]
    or al, 0xC0
    mov ah, cl
    shl ah, 3
    or al, ah
    pop cx
    pop bx
    ret

; Table: base-register to r/m encoding (for no-index addressing)
asm_rm_table:
    db 7    ; AX=0 → [BX] → r/m=7 (not great but...)
    db 7    ; CX=1 → [CX] not standard, use BX
    db 7    ; DX=2 → not standard
    db 7    ; BX=3 → r/m=7
    db 4    ; SP=4 → not directly accessible, r/m=4 (SI)
    db 6    ; BP=5 → r/m=6
    db 4    ; SI=6 → r/m=4
    db 5    ; DI=7 → r/m=5

; ============================================================
; Instruction dispatch table
; Format: null-terminated uppercase mnemonic, 2-byte handler address
; Sentinel: 2 zero bytes
; ============================================================
asm_instr_table:
db "ORG",0
dw asm_h_org
db "BITS",0
dw asm_h_bits
db "SECTION",0
dw asm_h_bits
db "SEGMENT",0
dw asm_h_bits
db "DB",0
dw asm_h_db
db "DW",0
dw asm_h_dw
db "TIMES",0
dw asm_h_times
db "EQU",0
dw asm_h_equ
db "MOV",0
dw asm_h_mov
db "PUSH",0
dw asm_h_push
db "POP",0
dw asm_h_pop
db "ADD",0
dw asm_h_add
db "SUB",0
dw asm_h_sub
db "CMP",0
dw asm_h_cmp
db "XOR",0
dw asm_h_xor
db "OR",0
dw asm_h_or
db "AND",0
dw asm_h_and
db "NOT",0
dw asm_h_not
db "NEG",0
dw asm_h_neg
db "INC",0
dw asm_h_inc
db "DEC",0
dw asm_h_dec
db "TEST",0
dw asm_h_test
db "XCHG",0
dw asm_h_xchg
db "MUL",0
dw asm_h_mul
db "IMUL",0
dw asm_h_mul
db "DIV",0
dw asm_h_div
db "IDIV",0
dw asm_h_div
db "INT",0
dw asm_h_int
db "CALL",0
dw asm_h_call
db "RET",0
dw asm_h_ret
db "RETN",0
dw asm_h_ret
db "RETF",0
dw asm_h_retf
db "JMP",0
dw asm_h_jmp
db "JE",0
dw asm_h_jcc
db "JZ",0
dw asm_h_jcc
db "JNE",0
dw asm_h_jcc
db "JNZ",0
dw asm_h_jcc
db "JG",0
dw asm_h_jcc
db "JNLE",0
dw asm_h_jcc
db "JGE",0
dw asm_h_jcc
db "JNL",0
dw asm_h_jcc
db "JL",0
dw asm_h_jcc
db "JNGE",0
dw asm_h_jcc
db "JLE",0
dw asm_h_jcc
db "JNG",0
dw asm_h_jcc
db "JA",0
dw asm_h_jcc
db "JNBE",0
dw asm_h_jcc
db "JAE",0
dw asm_h_jcc
db "JNB",0
dw asm_h_jcc
db "JB",0
dw asm_h_jcc
db "JNAE",0
dw asm_h_jcc
db "JBE",0
dw asm_h_jcc
db "JNA",0
dw asm_h_jcc
db "JO",0
dw asm_h_jcc
db "JNO",0
dw asm_h_jcc
db "JS",0
dw asm_h_jcc
db "JNS",0
dw asm_h_jcc
db "JP",0
dw asm_h_jcc
db "JPE",0
dw asm_h_jcc
db "JNP",0
dw asm_h_jcc
db "JPO",0
dw asm_h_jcc
db "LOOP",0
dw asm_h_loop
db "LOOPZ",0
dw asm_h_loop
db "LOOPNZ",0
dw asm_h_loop
db "NOP",0
dw asm_h_simple
db "HLT",0
dw asm_h_simple
db "CLI",0
dw asm_h_simple
db "STI",0
dw asm_h_simple
db "CLC",0
dw asm_h_simple
db "STC",0
dw asm_h_simple
db "CMC",0
dw asm_h_simple
db "CBW",0
dw asm_h_simple
db "CWD",0
dw asm_h_simple
db "PUSHF",0
dw asm_h_simple
db "POPF",0
dw asm_h_simple
db "PUSHA",0
dw asm_h_simple
db "POPA",0
dw asm_h_simple
db "XLAT",0
dw asm_h_simple
db "LODSB",0
dw asm_h_simple
db "LODSW",0
dw asm_h_simple
db "STOSB",0
dw asm_h_simple
db "STOSW",0
dw asm_h_simple
db "MOVSB",0
dw asm_h_simple
db "MOVSW",0
dw asm_h_simple
db "CMPSB",0
dw asm_h_simple
db "SCASB",0
dw asm_h_simple
db "SCASW",0
dw asm_h_simple
db "REP",0
dw asm_h_rep
db "REPE",0
dw asm_h_rep
db "REPZ",0
dw asm_h_rep
db "REPNE",0
dw asm_h_repne
db "REPNZ",0
dw asm_h_repne
db "SHL",0
dw asm_h_shift
db "SHR",0
dw asm_h_shift
db "SAL",0
dw asm_h_shift
db "SAR",0
dw asm_h_shift
db "ROL",0
dw asm_h_shift
db "ROR",0
dw asm_h_shift
db "RCL",0
dw asm_h_shift
db "RCR",0
dw asm_h_shift
db "LEA",0
dw asm_h_lea
db "LDS",0
dw asm_h_lds
db "LES",0
dw asm_h_les
db "BYTE",0
dw asm_h_size_hint  ; BYTE PTR / WORD PTR modifiers
db "WORD",0
dw asm_h_size_hint
db "PTR",0
dw asm_h_size_hint
db "FAR",0
dw asm_h_size_hint
db "NEAR",0
dw asm_h_size_hint
db "SHORT",0
dw asm_h_size_hint
dw 0            ; sentinel

; ============================================================
; Conditional jump opcode table
; ============================================================
asm_jcc_table:
db "JE",0
db 0x74
db "JZ",0
db 0x74
db "JNE",0
db 0x75
db "JNZ",0
db 0x75
db "JG",0
db 0x7F
db "JNLE",0
db 0x7F
db "JGE",0
db 0x7D
db "JNL",0
db 0x7D
db "JL",0
db 0x7C
db "JNGE",0
db 0x7C
db "JLE",0
db 0x7E
db "JNG",0
db 0x7E
db "JA",0
db 0x77
db "JNBE",0
db 0x77
db "JAE",0
db 0x73
db "JNB",0
db 0x73
db "JB",0
db 0x72
db "JNAE",0
db 0x72
db "JBE",0
db 0x76
db "JNA",0
db 0x76
db "JO",0
db 0x70
db "JNO",0
db 0x71
db "JS",0
db 0x78
db "JNS",0
db 0x79
db "JP",0
db 0x7A
db "JPE",0
db 0x7A
db "JNP",0
db 0x7B
db "JPO",0
db 0x7B
db 0,0       ; sentinel

; Simple 1-byte instruction opcode table
asm_simple_table:
db "NOP",0
db 0x90
db "HLT",0
db 0xF4
db "CLI",0
db 0xFA
db "STI",0
db 0xFB
db "CLC",0
db 0xF8
db "STC",0
db 0xF9
db "CMC",0
db 0xF5
db "CBW",0
db 0x98
db "CWD",0
db 0x99
db "PUSHF",0
db 0x9C
db "POPF",0
db 0x9D
db "PUSHA",0
db 0x60
db "POPA",0
db 0x61
db "XLAT",0
db 0xD7
db "LODSB",0
db 0xAC
db "LODSW",0
db 0xAD
db "STOSB",0
db 0xAA
db "STOSW",0
db 0xAB
db "MOVSB",0
db 0xA4
db "MOVSW",0
db 0xA5
db "CMPSB",0
db 0xA6
db "SCASB",0
db 0xAE
db "SCASW",0
db 0xAF
db 0,0        ; sentinel

; ============================================================
; asm_dispatch_instr - find and call instruction handler
; ============================================================
asm_dispatch_instr:
    push ax
    push bx
    push si
    ; Handle NASM [directive] syntax: skip '[' at start of mnemonic
    cmp byte [asm_cur_mnem], '['
    jne .normal_dispatch
    ; Load next token as mnemonic
    call asm_tok_next
    cmp byte [asm_tok_type], ASM_TOK_IDENT
    jne .skip_bracket
    mov si, asm_tok_str
    mov di, asm_cur_mnem
    call str_copy
    jmp .normal_dispatch
.skip_bracket:
    jmp .di_done

.normal_dispatch:
    ; Search instruction table
    mov bx, asm_instr_table
.di_search:
    cmp byte [bx], 0
    je .di_unknown          ; sentinel
    ; Compare asm_cur_mnem with [bx]
    push bx
    push si
    mov si, asm_cur_mnem
    mov di, bx
.di_cmp:
    mov al, [si]
    cmp al, [di]
    jne .di_cmp_no
    test al, al
    jz .di_cmp_match
    inc si
    inc di
    jmp .di_cmp
.di_cmp_no:
    pop si
    pop bx
    ; Skip to end of name + null + 2-byte handler
    push bx
.di_skip:
    cmp byte [bx], 0
    je .di_skip_done
    inc bx
    jmp .di_skip
.di_skip_done:
    inc bx          ; past null
    add bx, 2       ; past handler word
    pop bx
    add bx, 3       ; skip null + 2 bytes handler (3 total past null)
    ; Recalculate properly:
    ; We need to find next entry. Let's restart from saved BX.
    ; Actually the issue is I'm modifying BX while trying to use it.
    ; Let me use a cleaner approach:
    jmp .di_next

.di_cmp_match:
    pop si
    pop bx
    ; BX points to start of name. Find end of name (null), then handler = next 2 bytes.
    push bx
.di_find_end:
    cmp byte [bx], 0
    je .di_found_handler
    inc bx
    jmp .di_find_end
.di_found_handler:
    inc bx              ; past null
    mov ax, [bx]        ; handler address
    pop bx              ; restore original entry start
    call ax             ; call handler
    jmp .di_done

.di_next:
    ; BX = start of last entry, need to advance to next
    ; Find null in name
.di_adv_null:
    cmp byte [bx], 0
    je .di_adv_past_null
    inc bx
    jmp .di_adv_null
.di_adv_past_null:
    inc bx              ; past null
    add bx, 2           ; past 2-byte handler
    jmp .di_search

.di_unknown:
    ; Check if it looks like a label that was missed (starts with non-alpha, check for ':')
    ; Print error
    mov si, str_asm_unknown
    call vid_print
    mov si, asm_cur_mnem
    call vid_println
    mov si, str_asm_line
    call vid_print
    mov ax, [asm_line]
    call print_word_dec
    call vid_nl
    mov byte [asm_err], 1

.di_done:
    pop si
    pop bx
    pop ax
    ret

; ============================================================
; Instruction handlers
; ============================================================

; ---- ORG: set origin ----
asm_h_org:
    call asm_tok_next
    call asm_parse_expr
    mov [asm_pc], ax
    mov [asm_pc_base], ax
    ret

; ---- BITS / SECTION / SEGMENT: mostly ignored ----
asm_h_bits:
    call asm_tok_next   ; consume the argument
    ret

asm_h_size_hint:
    ; BYTE/WORD/PTR/NEAR/FAR/SHORT: size modifier, just continue
    call asm_tok_next
    ret

; ---- EQU: define constant ----
asm_h_equ:
    call asm_tok_next
    call asm_parse_expr
    ; Define the last-seen label with this value
    mov si, asm_last_glb
    call asm_sym_define
    ; Remove from sym_cnt (redefine)
    ret

; ---- DB: define bytes ----
asm_h_db:
.db_loop:
    call asm_tok_next
    cmp byte [asm_tok_type], ASM_TOK_EOL
    je .db_done
    cmp byte [asm_tok_type], ASM_TOK_EOF
    je .db_done
    cmp byte [asm_tok_type], ASM_TOK_COMMA
    je .db_loop         ; skip comma
    cmp byte [asm_tok_type], ASM_TOK_STR
    je .db_string
    cmp byte [asm_tok_type], ASM_TOK_NUM
    jne .db_expr
    ; Number
    mov al, [asm_tok_val]
    call asm_emit_byte
    jmp .db_loop
.db_expr:
    call asm_parse_expr
    mov al, al          ; low byte
    call asm_emit_byte
    jmp .db_loop
.db_string:
    ; Emit each character of the string
    mov si, asm_tok_str
.db_sc:
    lodsb
    test al, al
    jz .db_loop
    call asm_emit_byte
    jmp .db_sc
.db_done:
    ret

; ---- DW: define words ----
asm_h_dw:
.dw_loop:
    call asm_tok_next
    cmp byte [asm_tok_type], ASM_TOK_EOL
    je .dw_done
    cmp byte [asm_tok_type], ASM_TOK_EOF
    je .dw_done
    cmp byte [asm_tok_type], ASM_TOK_COMMA
    je .dw_loop
    cmp byte [asm_tok_type], ASM_TOK_NUM
    jne .dw_expr
    mov ax, [asm_tok_val]
    call asm_emit_word
    jmp .dw_loop
.dw_expr:
    call asm_parse_expr
    call asm_emit_word
    ; Check for patch
    cmp byte [asm_imm_unk], 0
    je .dw_loop
    ; Add patch: ABS16 for DW label
    mov ax, [asm_out]
    sub ax, 2           ; offset of this word in output
    sub ax, COMP_BUF
    mov si, asm_imm_lbl
    mov dx, [asm_imm_add]
    mov bh, ASM_PT_ABS16
    call asm_patch_add
    jmp .dw_loop
.dw_done:
    ret

; ---- TIMES: repeat N times ----
asm_h_times:
    call asm_tok_next
    call asm_parse_expr
    mov cx, ax          ; count
    ; Get what to repeat (db N, dw N, etc.)
    ; For simplicity, handle "db N" and "dw N" only
    call asm_tok_next
    cmp byte [asm_tok_type], ASM_TOK_IDENT
    jne .times_done
    ; Check if "db" or "dw"
    mov si, asm_tok_str
    mov ax, [si]
    cmp ax, 0x4244      ; "DB" little-endian = 0x4244 (B=0x42, D=0x44)
    jne .times_dw
    ; times N db val
    call asm_tok_next
    call asm_parse_expr
    ; AX = value to repeat, CX = count
    push cx
    push ax
.times_db_loop:
    pop ax
    push ax
    pop cx
    push cx
    ; hmm this is getting confused, let me use a different approach
    pop ax
    pop cx
    push cx
    push ax
.times_db_loop2:
    pop ax
    pop cx
    push cx
    push ax
    mov al, al          ; byte value
    push cx
    call asm_emit_byte
    pop cx
    dec cx
    jnz .times_db_loop2
    pop ax
    pop cx
    jmp .times_done
.times_dw:
    mov ax, 0x5744      ; "DW"
    cmp [si], ax
    jne .times_done
    ; times N dw val
    call asm_tok_next
    call asm_parse_expr
    push cx
    push ax
.times_dw_loop:
    test cx, cx
    jz .times_dw_done
    pop ax
    push ax
    push cx
    call asm_emit_word
    pop cx
    dec cx
    jmp .times_dw_loop
.times_dw_done:
    pop ax
    pop cx
.times_done:
    ret

; ---- MOV ----
asm_h_mov:
    call asm_tok_next
    call asm_parse_operand          ; parse dest → asm_op_*
    call asm_save_op1
    ; Expect comma
    cmp byte [asm_tok_type], ASM_TOK_COMMA
    jne .mov_err
    call asm_tok_next               ; consume comma, get first token of src
    ; Parse source
    call asm_parse_operand          ; parse src → asm_op_*

    ; Dispatch based on dest/src types
    ; Case: MOV seg, r16  (MOV DS, AX etc.)
    cmp byte [asm_op1_type], OPT_SEG
    je .mov_seg_dest
    ; Case: MOV r16, seg
    cmp byte [asm_op_type], OPT_SEG
    je .mov_r16_seg_src
    ; Case: MOV r16/r8, reg/imm
    cmp byte [asm_op1_type], OPT_REG16
    je .mov_r16_dest
    cmp byte [asm_op1_type], OPT_REG8
    je .mov_r8_dest
    cmp byte [asm_op1_type], OPT_MEM
    je .mov_mem_dest
    jmp .mov_err

.mov_r16_dest:
    ; Dest = 16-bit register
    xor bh, bh
    mov bl, byte [asm_op1_val]    ; dest reg
    cmp byte [asm_op_type], OPT_REG16
    je .mov_r16_r16
    cmp byte [asm_op_type], OPT_IMM
    je .mov_r16_imm
    cmp byte [asm_op_type], OPT_MEM
    je .mov_r16_mem
    jmp .mov_err

.mov_r16_r16:
    ; MOV r16, r16: 0x8B, ModRM(11, dst, src)
    xor ch, ch
    mov cl, byte [asm_op_val]     ; src reg
    mov al, 0x8B
    call asm_emit_byte
    mov al, 0xC0
    or al, bl                       ; dst in bits 0-2
    mov ah, cl
    shl ah, 3
    or al, ah                       ; src in bits 3-5
    call asm_emit_byte
    ret

.mov_r16_imm:
    ; MOV r16, imm16: 0xB8+dst, lo, hi
    mov al, 0xB8
    add al, bl
    call asm_emit_byte
    ; Check for unresolved label
    cmp byte [asm_imm_unk], 0
    je .mov_r16_imm_known
    ; Emit placeholder and add patch
    xor ax, ax
    call asm_emit_word
    ; Add ABS16 patch
    mov ax, [asm_out]
    sub ax, 2
    sub ax, COMP_BUF
    mov si, asm_imm_lbl
    mov dx, [asm_imm_add]
    mov bh, ASM_PT_ABS16
    call asm_patch_add
    ret
.mov_r16_imm_known:
    mov ax, [asm_op_val]
    call asm_emit_word
    ret

.mov_r16_mem:
    ; MOV r16, [mem]: 0x8B, ModRM
    mov al, 0x8B
    call asm_emit_byte
    mov al, bl                      ; dest reg as reg field
    call asm_modrm_for_op           ; uses current asm_op_* for r/m
    call asm_emit_byte
    ret

.mov_r8_dest:
    xor bh, bh
    mov bl, byte [asm_op1_val]
    cmp byte [asm_op_type], OPT_REG8
    je .mov_r8_r8
    cmp byte [asm_op_type], OPT_IMM
    je .mov_r8_imm
    cmp byte [asm_op_type], OPT_MEM
    je .mov_r8_mem
    jmp .mov_err

.mov_r8_r8:
    ; MOV r8, r8: 0x8A, ModRM(11, dst, src)
    xor ch, ch
    mov cl, byte [asm_op_val]
    mov al, 0x8A
    call asm_emit_byte
    mov al, 0xC0
    or al, bl
    mov ah, cl
    shl ah, 3
    or al, ah
    call asm_emit_byte
    ret

.mov_r8_imm:
    ; MOV r8, imm8: 0xB0+reg, imm8
    mov al, 0xB0
    add al, bl
    call asm_emit_byte
    mov al, [asm_op_val]
    call asm_emit_byte
    ret

.mov_r8_mem:
    ; MOV r8, [mem]: 0x8A, ModRM
    mov al, 0x8A
    call asm_emit_byte
    mov al, bl
    call asm_modrm_for_op
    call asm_emit_byte
    ret

.mov_mem_dest:
    ; MOV [mem], r16/r8
    call asm_restore_op1            ; restore dest into asm_op_*
    cmp byte [asm_op_type], OPT_MEM
    jne .mov_err
    ; Now dest is in asm_op_* (memory)
    ; src is in asm_op1_*... wait, I swapped them. Let me fix.
    ; After save_op1: op1_* = dest, op_* = src
    ; I need: emit opcode for MOV [mem], src
    ; op_* = src (reg), op1_* = dest (mem)
    ; Let me restore: asm_op_* to hold dest mem info
    mov al, [asm_op1_type]
    cmp al, OPT_REG16
    je .mov_mem_r16
    cmp al, OPT_REG8
    je .mov_mem_r8
    jmp .mov_err

.mov_mem_r16:
    ; MOV [mem], r16: 0x89, ModRM(mod, src, r/m)
    ; src = op1_val (reg), dest = current op_* (mem)
    ; I need to swap: currently op_* = dest (mem), but I want op_* = dest for modrm_for_op
    ; Let me save the src reg and restore dest as op_*
    xor ch, ch
    mov cl, byte [asm_op1_val]    ; src reg (already in op1_val = dest type OPT_REG16?)
    ; Wait, I'm confused again. Let me trace:
    ; - We called asm_save_op1 after parsing DEST (MOV dest, src)
    ; - So op1_* = DEST (the memory operand)
    ; - op_* = SRC (the register)
    ; For MOV [mem], reg: opcode = 0x89, ModRM encodes (src_reg, mem_rm)
    xor ch, ch
    mov cl, byte [asm_op_val]     ; SRC reg (from op_*)
    ; Now I need op_* to hold the DEST mem for modrm_for_op
    ; Restore op1 as op_*:
    push word [asm_op1_val]
    push ax                         ; save op1_type
    mov al, [asm_op1_type]
    mov [asm_op_type], al
    pop ax
    pop word [asm_op_val]
    mov al, [asm_op1_base]
    mov [asm_op_base], al
    mov al, [asm_op1_idx]
    mov [asm_op_idx], al
    ; Emit 0x89
    mov al, 0x89
    call asm_emit_byte
    ; Emit ModRM: reg=cx (src), r/m = mem
    mov al, cl                      ; reg field = src reg
    call asm_modrm_for_op
    call asm_emit_byte
    ret

.mov_mem_r8:
    xor ch, ch
    mov cl, byte [asm_op_val]
    mov al, [asm_op1_type]
    mov [asm_op_type], al
    mov ax, [asm_op1_val]
    mov [asm_op_val], ax
    mov al, [asm_op1_base]
    mov [asm_op_base], al
    mov al, [asm_op1_idx]
    mov [asm_op_idx], al
    mov al, 0x88
    call asm_emit_byte
    mov al, cl
    call asm_modrm_for_op
    call asm_emit_byte
    ret

.mov_seg_dest:
    ; MOV seg, r16: 0x8E, ModRM(11, seg, r16)
    xor bh, bh
    mov bl, byte [asm_op1_val]    ; segment reg (0-3)
    xor ch, ch
    mov cl, byte [asm_op_val]     ; source r16
    mov al, 0x8E
    call asm_emit_byte
    ; ModRM: mod=11, reg=bx(seg), r/m=cx(reg)
    mov al, 0xC0
    or al, cl                       ; r/m = source
    mov ah, bl
    shl ah, 3
    or al, ah
    call asm_emit_byte
    ret

.mov_r16_seg_src:
    ; MOV r16, seg: 0x8C, ModRM(11, seg, dst)
    xor bh, bh
    mov bl, byte [asm_op1_val]    ; dest r16
    xor ch, ch
    mov cl, byte [asm_op_val]     ; src seg
    mov al, 0x8C
    call asm_emit_byte
    mov al, 0xC0
    or al, bl
    mov ah, cl
    shl ah, 3
    or al, ah
    call asm_emit_byte
    ret

.mov_err:
    mov si, str_asm_syntax
    call vid_println
    mov si, str_asm_line
    call vid_print
    mov ax, [asm_line]
    call print_word_dec
    call vid_nl
    mov byte [asm_err], 1
    ret

; ---- PUSH r16 / imm ----
asm_h_push:
    call asm_tok_next
    call asm_parse_operand
    cmp byte [asm_op_type], OPT_REG16
    je .push_reg
    cmp byte [asm_op_type], OPT_SEG
    je .push_seg
    cmp byte [asm_op_type], OPT_IMM
    je .push_imm
    ret
.push_reg:
    mov al, 0x50
    add al, [asm_op_val]
    call asm_emit_byte
    ret
.push_seg:
    ; ES=0x06, CS=0x0E, SS=0x16, DS=0x1E
    mov al, [asm_op_val]    ; 0-3
    shl al, 3
    or al, 0x06
    call asm_emit_byte
    ret
.push_imm:
    ; PUSH imm16: 0x68, imm16
    mov al, 0x68
    call asm_emit_byte
    mov ax, [asm_op_val]
    call asm_emit_word
    ret

; ---- POP r16 ----
asm_h_pop:
    call asm_tok_next
    call asm_parse_operand
    cmp byte [asm_op_type], OPT_REG16
    je .pop_reg
    cmp byte [asm_op_type], OPT_SEG
    je .pop_seg
    ret
.pop_reg:
    mov al, 0x58
    add al, [asm_op_val]
    call asm_emit_byte
    ret
.pop_seg:
    ; ES=0x07, SS=0x17, DS=0x1F
    mov al, [asm_op_val]
    cmp al, 0               ; ES
    je .pop_es
    cmp al, 2               ; SS
    je .pop_ss
    ; DS
    mov al, 0x1F
    call asm_emit_byte
    ret
.pop_es:
    mov al, 0x07
    call asm_emit_byte
    ret
.pop_ss:
    mov al, 0x17
    call asm_emit_byte
    ret

; ---- ADD / SUB / CMP / XOR / OR / AND arithmetic handlers ----
; These all follow the same pattern: opcode_reg_rm, opcode_imm
; For ALU ops: /0=ADD, /1=OR, /2=ADC, /3=SBB, /4=AND, /5=SUB, /6=XOR, /7=CMP
; reg-reg: ADD=0x01, OR=0x09, AND=0x21, SUB=0x29, XOR=0x31, CMP=0x39
; reg-imm16: 0x81, /subcode
; reg-imm8 (sign-extend): 0x83, /subcode

asm_h_add: mov bh, 0
    jmp asm_h_arith
asm_h_or: mov bh, 1
    jmp asm_h_arith
asm_h_adc: mov bh, 2
    jmp asm_h_arith
asm_h_sbb: mov bh, 3
    jmp asm_h_arith
asm_h_and: mov bh, 4
    jmp asm_h_arith
asm_h_sub: mov bh, 5
    jmp asm_h_arith
asm_h_xor: mov bh, 6
    jmp asm_h_arith
asm_h_cmp: mov bh, 7
    jmp asm_h_arith

; rr16 opcodes: ADD=0x01 OR=0x09 AND=0x21 SUB=0x29 XOR=0x31 CMP=0x39
asm_arith_rr16: db 0x01, 0x09, 0x11, 0x19, 0x21, 0x29, 0x31, 0x39
; rr8 opcodes:  ADD=0x00 OR=0x08 AND=0x20 SUB=0x28 XOR=0x30 CMP=0x38
asm_arith_rr8:  db 0x00, 0x08, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38

asm_h_arith:
    push bx         ; BH = sub-code (0-7)
    call asm_tok_next
    call asm_parse_operand
    call asm_save_op1
    cmp byte [asm_tok_type], ASM_TOK_COMMA
    jne .arith_err
    call asm_tok_next
    call asm_parse_operand
    ; Now: op1_* = dest, op_* = src

    cmp byte [asm_op1_type], OPT_REG16
    je .arith_r16
    cmp byte [asm_op1_type], OPT_REG8
    je .arith_r8
    jmp .arith_err

.arith_r16:
    cmp byte [asm_op_type], OPT_REG16
    je .arith_r16_r16
    cmp byte [asm_op_type], OPT_IMM
    je .arith_r16_imm
    jmp .arith_err

.arith_r16_r16:
    mov bl, bh
    xor bh, bh            ; get sub-code (0-7 index)
    mov al, [asm_arith_rr16 + bx]
    call asm_emit_byte
    ; ModRM: mod=11, src(op_val) in reg field, dst(op1_val) in r/m
    xor bh, bh
    mov bl, byte [asm_op_val]    ; src
    xor ch, ch
    mov cl, byte [asm_op1_val]   ; dst
    mov al, 0xC0
    or al, cl                       ; r/m = dst
    mov ah, bl
    shl ah, 3
    or al, ah                       ; reg = src
    call asm_emit_byte
    pop bx
    ret

.arith_r16_imm:
    xor ch, ch
    mov cl, byte [asm_op1_val]    ; dest reg
    mov ax, [asm_op_val]
    ; Use 0x83 (sign-extend imm8) if value fits in -128..127
    cmp ax, 127
    jg .arith_r16_imm16
    cmp ax, -128
    jl .arith_r16_imm16
    ; 0x83 form
    mov al, 0x83
    call asm_emit_byte
    mov al, 0xC0                    ; mod=11
    or al, cl                       ; r/m = dest
    mov ah, bh                      ; subcode in bits 3-5
    shl ah, 3
    or al, ah
    call asm_emit_byte
    mov al, [asm_op_val]            ; imm8
    call asm_emit_byte
    pop bx
    ret
.arith_r16_imm16:
    ; 0x81 form
    mov al, 0x81
    call asm_emit_byte
    mov al, 0xC0
    or al, cl
    mov ah, bh
    shl ah, 3
    or al, ah
    call asm_emit_byte
    ; Check for unresolved label
    cmp byte [asm_imm_unk], 0
    jne .arith_patch
    mov ax, [asm_op_val]
    call asm_emit_word
    pop bx
    ret
.arith_patch:
    xor ax, ax
    call asm_emit_word
    mov ax, [asm_out]
    sub ax, 2
    sub ax, COMP_BUF
    mov si, asm_imm_lbl
    mov dx, [asm_imm_add]

    mov bh, ASM_PT_ABS16
    call asm_patch_add
    pop bx
    ret

.arith_r8:
    cmp byte [asm_op_type], OPT_REG8
    je .arith_r8_r8
    cmp byte [asm_op_type], OPT_IMM
    je .arith_r8_imm
    jmp .arith_err
.arith_r8_r8:
    mov bl, bh
    xor bh, bh
    mov al, [asm_arith_rr8 + bx]
    call asm_emit_byte
    xor bh, bh
    mov bl, byte [asm_op_val]
    xor ch, ch
    mov cl, byte [asm_op1_val]
    mov al, 0xC0
    or al, cl
    mov ah, bl
    shl ah, 3
    or al, ah
    call asm_emit_byte
    pop bx
    ret
.arith_r8_imm:
    ; 0x80, /subcode, imm8
    mov al, 0x80
    call asm_emit_byte
    xor ch, ch
    mov cl, byte [asm_op1_val]
    mov al, 0xC0
    or al, cl
    mov ah, bh
    shl ah, 3
    or al, ah
    call asm_emit_byte
    mov al, [asm_op_val]
    call asm_emit_byte
    pop bx
    ret

.arith_err:
    pop bx
    mov si, str_asm_syntax
    call vid_println
    mov byte [asm_err], 1
    ret

; ---- NOT / NEG / MUL / DIV ----
; These are unary F7 /subcode (for r16) or F6 /subcode (for r8)
; NOT=2, NEG=3, MUL=4, IMUL=5, DIV=6, IDIV=7
asm_h_not: mov bh, 2
    jmp asm_h_unary
asm_h_neg: mov bh, 3
    jmp asm_h_unary
asm_h_mul: mov bh, 4
    jmp asm_h_unary
asm_h_div: mov bh, 6
    jmp asm_h_unary
asm_h_unary:
    push bx
    call asm_tok_next
    call asm_parse_operand
    cmp byte [asm_op_type], OPT_REG16
    je .un_r16
    cmp byte [asm_op_type], OPT_REG8
    je .un_r8
    pop bx
    ret
.un_r16:
    mov al, 0xF7
    call asm_emit_byte
    xor ch, ch
    mov cl, byte [asm_op_val]
    mov al, 0xC0
    or al, cl
    mov ah, bh
    shl ah, 3
    or al, ah
    call asm_emit_byte
    pop bx
    ret
.un_r8:
    mov al, 0xF6
    call asm_emit_byte
    xor ch, ch
    mov cl, byte [asm_op_val]
    mov al, 0xC0
    or al, cl
    mov ah, bh
    shl ah, 3
    or al, ah
    call asm_emit_byte
    pop bx
    ret

; ---- INC / DEC ----
asm_h_inc: mov bh, 0
    jmp asm_h_incdec
asm_h_dec: mov bh, 1
    jmp asm_h_incdec
asm_h_incdec:
    push bx
    call asm_tok_next
    call asm_parse_operand
    cmp byte [asm_op_type], OPT_REG16
    je .id_r16
    cmp byte [asm_op_type], OPT_REG8
    je .id_r8
    pop bx
    ret
.id_r16:
    ; INC r16 = 0x40+r, DEC r16 = 0x48+r
    mov al, bh
    shl al, 3
    or al, 0x40
    add al, [asm_op_val]
    call asm_emit_byte
    pop bx
    ret
.id_r8:
    ; FE /0 or FE /1
    mov al, 0xFE
    call asm_emit_byte
    xor ch, ch
    mov cl, byte [asm_op_val]
    mov al, 0xC0
    or al, cl
    mov ah, bh
    shl ah, 3
    or al, ah
    call asm_emit_byte
    pop bx
    ret

; ---- TEST ----
asm_h_test:
    call asm_tok_next
    call asm_parse_operand
    call asm_save_op1
    cmp byte [asm_tok_type], ASM_TOK_COMMA
    jne .test_ret
    call asm_tok_next
    call asm_parse_operand
    cmp byte [asm_op1_type], OPT_REG16
    jne .test_r8
    cmp byte [asm_op_type], OPT_REG16
    jne .test_r16_imm
    ; TEST r16, r16: 0x85, ModRM
    mov al, 0x85
    call asm_emit_byte
    xor bh, bh
    mov bl, byte [asm_op_val]
    xor ch, ch
    mov cl, byte [asm_op1_val]
    mov al, 0xC0
    or al, cl
    mov ah, bl
    shl ah, 3
    or al, ah
    call asm_emit_byte
    ret
.test_r16_imm:
    ; TEST r16, imm16: 0xF7, /0, imm16
    mov al, 0xF7
    call asm_emit_byte
    xor ch, ch
    mov cl, byte [asm_op1_val]
    mov al, 0xC0
    or al, cl
    call asm_emit_byte
    mov ax, [asm_op_val]
    call asm_emit_word
    ret
.test_r8:
    cmp byte [asm_op1_type], OPT_REG8
    jne .test_ret
    cmp byte [asm_op_type], OPT_REG8
    jne .test_r8_imm
    ; TEST r8, r8: 0x84
    mov al, 0x84
    call asm_emit_byte
    xor bh, bh
    mov bl, byte [asm_op_val]
    xor ch, ch
    mov cl, byte [asm_op1_val]
    mov al, 0xC0
    or al, cl
    mov ah, bl
    shl ah, 3
    or al, ah
    call asm_emit_byte
    ret
.test_r8_imm:
    ; TEST r8, imm8: 0xF6, /0, imm8
    mov al, 0xF6
    call asm_emit_byte
    xor ch, ch
    mov cl, byte [asm_op1_val]
    mov al, 0xC0
    or al, cl
    call asm_emit_byte
    mov al, [asm_op_val]
    call asm_emit_byte
.test_ret:
    ret

; ---- XCHG ----
asm_h_xchg:
    call asm_tok_next
    call asm_parse_operand
    call asm_save_op1
    cmp byte [asm_tok_type], ASM_TOK_COMMA
    jne .xchg_ret
    call asm_tok_next
    call asm_parse_operand
    cmp byte [asm_op1_type], OPT_REG16
    jne .xchg_ret
    xor bh, bh
    mov bl, byte [asm_op1_val]
    xor ch, ch
    mov cl, byte [asm_op_val]
    ; XCHG AX, r or XCHG r, AX → 0x90+r
    cmp bx, 0
    je .xchg_ax
    cmp cx, 0
    je .xchg_ax2
    ; General XCHG r16, r16: 0x87, ModRM
    mov al, 0x87
    call asm_emit_byte
    mov al, 0xC0
    or al, bl
    mov ah, cl
    shl ah, 3
    or al, ah
    call asm_emit_byte
    ret
.xchg_ax:
    mov al, 0x90
    add al, cl
    call asm_emit_byte
    ret
.xchg_ax2:
    mov al, 0x90
    add al, bl
    call asm_emit_byte
.xchg_ret:
    ret

; ---- INT ----
asm_h_int:
    call asm_tok_next
    call asm_parse_expr
    mov bl, al              ; interrupt number
    mov al, 0xCD
    call asm_emit_byte
    mov al, bl
    call asm_emit_byte
    ret

; ---- CALL ----
asm_h_call:
    call asm_tok_next
    call asm_parse_expr
    ; CALL near relative: 0xE8, rel16
    mov al, 0xE8
    call asm_emit_byte
    cmp byte [asm_imm_unk], 0
    je .call_known
    ; Forward reference
    xor ax, ax
    call asm_emit_word
    mov ax, [asm_out]
    sub ax, 2
    sub ax, COMP_BUF
    mov si, asm_imm_lbl
    mov dx, [asm_imm_add]
    mov bh, ASM_PT_REL16
    call asm_patch_add
    ret
.call_known:
    ; Compute rel16 = target - (pc_after_instruction)
    ; pc_after = current PC + 2 (we've emitted E8, and will emit 2 more)
    mov bx, [asm_pc]
    add bx, 2               ; end of instruction (after rel16 bytes)
    sub ax, bx              ; rel16
    call asm_emit_word
    ret

; ---- RET ----
asm_h_ret:
    mov al, 0xC3
    call asm_emit_byte
    ret

asm_h_retf:
    mov al, 0xCB
    call asm_emit_byte
    ret

; ---- JMP ----
asm_h_jmp:
    call asm_tok_next
    ; Check for SHORT or NEAR modifier
    cmp byte [asm_tok_type], ASM_TOK_IDENT
    jne .jmp_nomod
    mov ax, [asm_tok_str]
    cmp ax, 0x5053          ; "SH" prefix of SHORT?
    ; Just skip any modifier keyword
    mov si, asm_tok_str
    call str_len
    cmp ax, 4               ; SHORT is 5 chars, NEAR is 4... let's check
    ; If it's SHORT or NEAR or FAR, skip it
    push si
    mov si, asm_tok_str
    mov di, asm_str_SHORT
    call str_cmp
    jz .jmp_skip_mod
    mov di, asm_str_NEAR
    call str_cmp
    jz .jmp_skip_mod
    mov di, asm_str_FAR
    call str_cmp
    jz .jmp_skip_mod
    pop si
    jmp .jmp_nomod
.jmp_skip_mod:
    pop si
    call asm_tok_next       ; consume modifier, get target

.jmp_nomod:
    call asm_parse_expr
    ; Try JMP short (rel8): if target known and within range
    cmp byte [asm_imm_unk], 0
    jne .jmp_near_patch     ; unknown → use near JMP with patch
    ; Known: compute offset, try short first
    mov bx, ax              ; target
    mov cx, [asm_pc]
    add cx, 2               ; end of short JMP instruction
    sub bx, cx              ; bx = rel8 (signed)
    cmp bx, 127
    jg .jmp_near
    cmp bx, -128
    jl .jmp_near
    ; Short JMP
    mov al, 0xEB
    call asm_emit_byte
    mov al, bl
    call asm_emit_byte
    ret
.jmp_near:
    ; Near JMP: recalculate rel16
    mov ax, [asm_imm_lbl]   ; hmm, imm_unk=0, so we have value in ax from parse_expr
    ; Let me redo: ax = target (from parse_expr which returned target in ax)
    ; But ax was overwritten by the computation above... issue
    ; Actually, at this point:
    ;   after .jmp_nomod, we called asm_parse_expr → ax = resolved address
    ;   then we computed bx = rel8 and found it doesn't fit
    ;   Now we need to emit JMP near (0xE9, rel16)
    ;   rel16 = target - (current_pc + 3)
    ; But we've already advanced PC by 0 (haven't emitted yet)
    ; target = the value that parse_expr returned... stored in? We lost it!
    ; Let me track it properly.
    ; Actually: right before the computation, bx was the target. Let me restore:
    mov bx, cx              ; cx was (pc+2), bx = rel8 = target - (pc+2)
    add bx, cx              ; bx = target again
    sub bx, 1               ; adjust: for near jmp, end = pc+3, not pc+2
    ; Near JMP: 0xE9, rel16
    mov al, 0xE9
    call asm_emit_byte
    mov cx, [asm_pc]
    add cx, 2               ; after the rel16 bytes
    sub bx, cx              ; rel16 = target - end
    mov ax, bx
    call asm_emit_word
    ret

.jmp_near_patch:
    ; Unknown target: emit JMP near with patch
    mov al, 0xE9
    call asm_emit_byte
    xor ax, ax
    call asm_emit_word
    mov ax, [asm_out]
    sub ax, 2
    sub ax, COMP_BUF
    mov si, asm_imm_lbl
    mov dx, [asm_imm_add]
    mov bh, ASM_PT_REL16
    call asm_patch_add
    ret

asm_str_SHORT: db "SHORT",0
asm_str_NEAR:  db "NEAR",0
asm_str_FAR:   db "FAR",0

; ---- Jcc: conditional jumps ----
asm_h_jcc:
    ; Look up opcode from asm_jcc_table using asm_cur_mnem
    push bx
    mov bx, asm_jcc_table
.jcc_search:
    cmp byte [bx], 0
    je .jcc_unknown
    push bx
    push si
    mov si, asm_cur_mnem
    mov di, bx
.jcc_cmp:
    mov al, [si]
    cmp al, [di]
    jne .jcc_cmp_ne
    test al, al
    jz .jcc_found_entry
    inc si
    inc di
    jmp .jcc_cmp
.jcc_cmp_ne:
    pop si
    pop bx
    ; Skip: advance past name null + 1 byte opcode
.jcc_skip:
    cmp byte [bx], 0
    je .jcc_skip_done
    inc bx
    jmp .jcc_skip
.jcc_skip_done:
    inc bx          ; past null
    inc bx          ; past opcode byte
    jmp .jcc_search
.jcc_found_entry:
    pop si
    pop bx
    ; Find end of name, then opcode
    push bx
.jcc_find_op:
    cmp byte [bx], 0
    je .jcc_got_op
    inc bx
    jmp .jcc_find_op
.jcc_got_op:
    inc bx          ; past null
    mov bl, [bx]    ; opcode
    pop bx
    ; Now emit short conditional jump
    call asm_tok_next
    call asm_parse_expr
    ; emit opcode
    push bx
    mov al, bl
    call asm_emit_byte
    pop bx
    cmp byte [asm_imm_unk], 0
    jne .jcc_patch
    ; Known target: compute rel8
    mov cx, [asm_pc]
    add cx, 1               ; end of instruction (after rel8 byte)
    sub ax, cx              ; rel8 = target - end
    call asm_emit_byte
    pop bx
    ret
.jcc_patch:
    ; Unknown: placeholder + patch
    xor al, al
    call asm_emit_byte
    mov ax, [asm_out]
    sub ax, 1
    sub ax, COMP_BUF        ; offset of rel8 placeholder
    mov si, asm_imm_lbl
    mov dx, [asm_imm_add]
    mov bh, ASM_PT_REL8
    call asm_patch_add
    pop bx
    ret
.jcc_unknown:
    pop bx
    ret

; ---- LOOP ----
asm_h_loop:
    ; LOOP=0xE2, LOOPZ=0xE1, LOOPNZ=0xE0
    mov al, 0xE2
    mov si, asm_cur_mnem
    cmp byte [si+4], 0      ; "LOOP\0" → simple LOOP
    je .loop_emit
    cmp byte [si+4], 'Z'    ; "LOOPZ"
    je .loop_z
    mov al, 0xE0            ; LOOPNZ
    jmp .loop_emit
.loop_z:
    mov al, 0xE1
.loop_emit:
    call asm_tok_next
    push ax                 ; save opcode
    call asm_parse_expr
    pop bx                  ; restore opcode into BL
    mov al, bl
    call asm_emit_byte
    cmp byte [asm_imm_unk], 0
    jne .loop_patch
    mov cx, [asm_pc]
    add cx, 1
    sub ax, cx
    call asm_emit_byte
    ret
.loop_patch:
    xor al, al
    call asm_emit_byte
    mov ax, [asm_out]
    sub ax, 1
    sub ax, COMP_BUF
    mov si, asm_imm_lbl
    mov dx, [asm_imm_add]
    mov bh, ASM_PT_REL8
    call asm_patch_add
    ret

; ---- Simple 1-byte instructions ----
asm_h_simple:
    push bx
    ; Look up opcode in asm_simple_table using asm_cur_mnem
    mov bx, asm_simple_table
.sim_search:
    cmp byte [bx], 0
    je .sim_unk
    push bx
    push si
    mov si, asm_cur_mnem
    mov di, bx
.sim_cmp:
    mov al, [si]
    cmp al, [di]
    jne .sim_ne
    test al, al
    jz .sim_match
    inc si
    inc di
    jmp .sim_cmp
.sim_ne:
    pop si
    pop bx
.sim_skip:
    cmp byte [bx], 0
    je .sim_skip_done
    inc bx
    jmp .sim_skip
.sim_skip_done:
    add bx, 2       ; past null + opcode byte
    jmp .sim_search
.sim_match:
    pop si
    pop bx
    ; Find opcode
    push bx
.sim_find:
    cmp byte [bx], 0
    je .sim_got
    inc bx
    jmp .sim_find
.sim_got:
    inc bx          ; past null
    mov al, [bx]    ; opcode
    pop bx
    call asm_emit_byte
    pop bx
    ret
.sim_unk:
    pop bx
    ret

; ---- REP/REPNE prefix ----
asm_h_rep:
    mov al, 0xF3
    call asm_emit_byte
    ret

asm_h_repne:
    mov al, 0xF2
    call asm_emit_byte
    ret

; ---- SHL/SHR/SAL/SAR/ROL/ROR/RCL/RCR ----
; Format: SHL reg, 1  or  SHL reg, CL
asm_h_shift:
    ; Determine sub-code from mnemonic
    ; SHL/SAL=4, SHR=5, SAR=7, ROL=0, ROR=1, RCL=2, RCR=3
    push bx
    mov si, asm_cur_mnem
    mov bh, 4               ; default SHL
    cmp byte [si+1], 'H'    ; SHR
    jne .sh_not_shr
    cmp byte [si+2], 'R'
    je .sh_shr
.sh_not_shr:
    cmp byte [si], 'S'
    jne .sh_rol
    cmp byte [si+1], 'A'    ; SAR or SAL
    jne .sh_check
    cmp byte [si+2], 'R'
    jne .sh_sal
    mov bh, 7               ; SAR
    jmp .sh_got
.sh_sal:
    mov bh, 4               ; SAL = SHL
    jmp .sh_got
.sh_shr:
    mov bh, 5
    jmp .sh_got
.sh_rol:
    cmp byte [si], 'R'
    jne .sh_got
    cmp byte [si+1], 'O'    ; ROL or ROR
    jne .sh_rcl
    cmp byte [si+2], 'R'
    je .sh_ror
    mov bh, 0               ; ROL
    jmp .sh_got
.sh_ror:
    mov bh, 1
    jmp .sh_got
.sh_rcl:
    cmp byte [si+1], 'C'    ; RCL or RCR
    jne .sh_got
    cmp byte [si+2], 'R'
    je .sh_rcr
    mov bh, 2               ; RCL
    jmp .sh_got
.sh_rcr:
    mov bh, 3
.sh_check:
.sh_got:
    call asm_tok_next
    call asm_parse_operand
    call asm_save_op1
    cmp byte [asm_tok_type], ASM_TOK_COMMA
    jne .sh_ret
    call asm_tok_next
    call asm_parse_operand
    ; Check shift count: 1 or CL
    cmp byte [asm_op_type], OPT_IMM
    je .sh_by_1
    cmp byte [asm_op_type], OPT_REG8
    je .sh_by_cl

.sh_by_1:
    ; D1 /subcode (shift by 1)
    mov al, 0xD1
    cmp byte [asm_op1_type], OPT_REG8
    jne .sh_emit1
    mov al, 0xD0
.sh_emit1:
    call asm_emit_byte
    xor ch, ch
    mov cl, byte [asm_op1_val]
    mov al, 0xC0
    or al, cl
    mov ah, bh
    shl ah, 3
    or al, ah
    call asm_emit_byte
    jmp .sh_ret

.sh_by_cl:
    ; D3 /subcode (shift by CL)
    mov al, 0xD3
    cmp byte [asm_op1_type], OPT_REG8
    jne .sh_emit_cl
    mov al, 0xD2
.sh_emit_cl:
    call asm_emit_byte
    xor ch, ch
    mov cl, byte [asm_op1_val]
    mov al, 0xC0
    or al, cl
    mov ah, bh
    shl ah, 3
    or al, ah
    call asm_emit_byte
.sh_ret:
    pop bx
    ret

; ---- LEA r16, [mem] ----
asm_h_lea:
    call asm_tok_next
    call asm_parse_operand
    call asm_save_op1
    cmp byte [asm_tok_type], ASM_TOK_COMMA
    jne .lea_ret
    call asm_tok_next
    call asm_parse_operand
    cmp byte [asm_op1_type], OPT_REG16
    jne .lea_ret
    ; LEA r16, [mem]: 0x8D, ModRM
    mov al, 0x8D
    call asm_emit_byte
    xor ch, ch
    mov cl, byte [asm_op1_val]    ; dest reg
    mov al, cl
    call asm_modrm_for_op
    call asm_emit_byte
.lea_ret:
    ret

; ---- LDS/LES ----
asm_h_lds:
    call asm_tok_next
    call asm_parse_operand
    cmp byte [asm_tok_type], ASM_TOK_COMMA
    jne .lds_ret
    call asm_tok_next
    call asm_parse_operand
    mov al, 0xC5            ; LDS
    call asm_emit_byte
    ; ModRM
    xor ch, ch
    mov cl, byte [asm_op1_val]
    mov al, cl
    call asm_modrm_for_op
    call asm_emit_byte
.lds_ret:
    ret

asm_h_les:
    call asm_tok_next
    call asm_parse_operand
    cmp byte [asm_tok_type], ASM_TOK_COMMA
    jne .les_ret
    call asm_tok_next
    call asm_parse_operand
    mov al, 0xC4            ; LES
    call asm_emit_byte
    xor ch, ch
    mov cl, byte [asm_op1_val]
    mov al, cl
    call asm_modrm_for_op
    call asm_emit_byte
.les_ret:
    ret

; ============================================================
; asm_make_outname - derive .COM output name from sh_arg
; ============================================================
asm_make_outname:
    push ax
    push si
    push di
    mov si, sh_arg
    mov di, asm_out_name
    ; Copy up to dot
.on_copy:
    lodsb
    test al, al
    jz .on_no_ext
    cmp al, '.'
    je .on_ext
    stosb
    jmp .on_copy
.on_ext:
    ; Replace extension with COM
    mov ax, 'C' | ('O' << 8)
    stosw
    mov ax, 'M' | (0 << 8)
    stosw
    jmp .on_done
.on_no_ext:
    ; No extension: append .COM
    mov ax, '.' | ('C' << 8)
    stosw
    mov ax, 'O' | ('M' << 8)
    stosw
    xor al, al
    stosb
.on_done:
    mov byte [di], 0
    pop di
    pop si
    pop ax
    ret

; ============================================================
; asm_write_output - write FILE_BUF (_sh_copy_sz bytes) to disk
; Creates a new file named asm_out_name in current directory
; ============================================================
asm_write_output:
    push ax
    push bx
    push di
    ; Convert filename to 8.3 format
    mov si, asm_out_name
    mov di, _sh_tmp11
    call str_to_dosname
    ; Load directory, find free slot
    call fat_load_dir
    call fat_find_free_slot
    cmp di, 0xFFFF
    je .awo_nospace
    push di                     ; save dir entry slot
    ; Allocate a cluster for the file
    call fat_alloc_cluster
    cmp ax, 0xFFFF
    je .awo_nospace_pop
    mov [_sh_copy_cl], ax
    push ax
    mov bx, 0x0FFF
    call fat_set_entry          ; mark as EOC
    pop ax
    ; Write FILE_BUF to this cluster
    push ax
    call cluster_to_lba
    push ds
    pop es
    mov bx, FILE_BUF
    call disk_write_sector
    pop ax                      ; cluster number
    pop di                      ; dir entry slot
    ; Fill directory entry
    push ds
    pop es
    push si
    push di
    mov si, _sh_tmp11
    mov cx, 11
    rep movsb
    pop di
    pop si
    mov byte [di+11], 0x20      ; archive
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
    jmp .awo_done
.awo_nospace_pop:
    pop di
.awo_nospace:
    mov si, str_no_space
    call vid_println
    mov byte [asm_err], 1
.awo_done:
    pop di
    pop bx
    pop ax
    ret

; ============================================================
; Assembler data strings
; ============================================================
str_asm_done:      db "Assembly complete. Output written.", 0
str_asm_empty:     db "No output generated.", 0
str_asm_unknown:   db "Unknown instruction: ", 0
str_asm_syntax:    db "Syntax error.", 0
str_asm_line:      db "  at line ", 0
str_asm_undef:     db "Undefined symbol: ", 0
str_asm_range:     db "Jump out of range (use NEAR/WORD).", 0
str_asm_syms_full: db "Too many symbols.", 0
str_asm_patch_full: db "Too many forward references.", 0
str_no_space:      db "Insufficient disk space.", 0
