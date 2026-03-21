; =============================================================================
; CSC.OVL - C# compiler overlay  (KSDOS-CSC)
; sh_arg (0x0060) = source filename (.cs)
; =============================================================================
BITS 16
ORG OVERLAY_BUF

%include "ovl_api.asm"

; ---------------------------------------------------------------------------
; Local data needed by compiler write routines
; ---------------------------------------------------------------------------
_sh_copy_sz:    dw 0
_sh_copy_cl:    dw 0

; ---------------------------------------------------------------------------
; Entry point
; ---------------------------------------------------------------------------
ovl_entry:
    mov al, ATTR_CYAN
    call vid_set_attr
    mov si, .str_banner
    call vid_println
    mov al, ATTR_NORMAL
    call vid_set_attr

    cmp byte [sh_arg], 0
    je .usage

    mov si, .str_comp
    call vid_print
    mov si, sh_arg
    call vid_println

    call ovl_load_src
    jc .not_found

    call csc_run
    ret

.not_found:
    mov si, .str_nf
    call vid_println
    ret

.usage:
    mov si, .str_usage
    call vid_println
    ret

.str_banner: db "KSDOS-CSC C# Compiler v1.0  [16-bit real mode]", 0
.str_comp:   db "Compiling: ", 0
.str_nf:     db "File not found.", 0
.str_usage:  db "Usage: CSC <file.cs>", 0

; ---------------------------------------------------------------------------
; ovl_load_src: local file loader
; ---------------------------------------------------------------------------
ovl_load_src:
    mov si, sh_arg
    mov di, _sh_tmp11
    call str_to_dosname
    call fat_load_dir
    mov si, _sh_tmp11
    call fat_find
    jc .nf
    mov ax, [di+28]
    mov [_sh_type_sz], ax
    mov ax, [di+26]
    push ax
    mov di, FILE_BUF
    call fat_read_file
    pop ax
    clc
    ret
.nf:
    stc
    ret

; ---------------------------------------------------------------------------
; Module code: assembler + C first (csc_run calls cc_* and asm_* helpers)
; ---------------------------------------------------------------------------
%include "../compiler_asm.asm"
%include "../compiler_c.asm"
%include "../compiler_csc.asm"
