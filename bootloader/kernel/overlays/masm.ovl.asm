; =============================================================================
; MASM.OVL - x86 Macro Assembler overlay  (MASM / NASM compatible)
; sh_arg (0x0060) = source filename (.asm)
; =============================================================================
BITS 16
ORG OVERLAY_BUF

%include "ovl_api.asm"

; ---------------------------------------------------------------------------
; Local data needed by asm_write_output  (mirrors shell.asm _sh_copy_* vars)
; ---------------------------------------------------------------------------
_sh_copy_sz:    dw 0
_sh_copy_cl:    dw 0

; ---------------------------------------------------------------------------
; Entry point
; ---------------------------------------------------------------------------
ovl_entry:
    ; Print banner
    mov al, ATTR_CYAN
    call vid_set_attr
    mov si, .str_banner
    call vid_println
    mov al, ATTR_NORMAL
    call vid_set_attr

    ; Require filename argument
    cmp byte [sh_arg], 0
    je .usage

    ; Show "Assembling: <filename>"
    mov si, .str_asm
    call vid_print
    mov si, sh_arg
    call vid_println

    ; Load source file into FILE_BUF
    call ovl_load_src
    jc .not_found

    ; Run assembler
    call asm_run
    ret

.not_found:
    mov si, .str_nf
    call vid_println
    ret

.usage:
    mov si, .str_usage
    call vid_println
    ret

.str_banner: db "KSDOS-ASM Macro Assembler v1.0  [MASM/NASM compatible]", 0
.str_asm:    db "Assembling: ", 0
.str_nf:     db "File not found.", 0
.str_usage:  db "Usage: MASM <file.asm>  or  NASM <file.asm>", 0

; ---------------------------------------------------------------------------
; ovl_load_src: local version of sh_load_source
; Reads sh_arg filename, finds it on disk, loads into FILE_BUF.
; Sets _sh_type_sz = file size.  CF=1 on error.
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
; Module code
; ---------------------------------------------------------------------------
%include "../compiler_asm.asm"
