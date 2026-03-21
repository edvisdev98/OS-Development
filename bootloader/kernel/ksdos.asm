; =============================================================================
; ksdos.asm - KSDOS Kernel Entry Point
; 16-bit real mode x86, loaded at 0x1000:0x0000 by boot sector
;
; Memory layout of this binary (ORG 0x0000):
;   0x0000          3 bytes  initial JMP to kernel_entry
;   0x0003-0x005F  93 bytes  kernel jump table  (31 entries × 3 bytes)
;   0x0060-0x00DF 128 bytes  sh_arg   - shared command-argument buffer
;   0x00E0-0x00EB  12 bytes  _sh_tmp11 - shared DOS 8.3 temp buffer
;   0x00EC-0x00ED   2 bytes  _sh_type_sz - shared source-file-size word
;   0x00EE+               kernel_entry and all subsystem code
; =============================================================================

BITS 16
ORG 0x0000

; ---------------------------------------------------------------------------
; 0x0000: Initial jump over the jump table / shared data to kernel_entry
; ---------------------------------------------------------------------------
    jmp near kernel_entry

; ---------------------------------------------------------------------------
; 0x0003: Kernel jump table - 31 entries, 3 bytes each (E9 near jmp)
; These stable offsets let overlay binaries call kernel routines regardless
; of where those routines land in the kernel binary.
; ---------------------------------------------------------------------------
%macro KTENTRY 1
    db 0xE9
    dw (%1) - ($ + 2)
%endmacro

    KTENTRY vid_print           ; 0x0003
    KTENTRY vid_println         ; 0x0006
    KTENTRY vid_putchar         ; 0x0009
    KTENTRY vid_nl              ; 0x000C
    KTENTRY vid_clear           ; 0x000F
    KTENTRY vid_set_attr        ; 0x0012
    KTENTRY vid_get_cursor      ; 0x0015
    KTENTRY vid_set_cursor      ; 0x0018
    KTENTRY kbd_getkey          ; 0x001B
    KTENTRY kbd_check           ; 0x001E
    KTENTRY kbd_readline        ; 0x0021
    KTENTRY str_len             ; 0x0024
    KTENTRY str_copy            ; 0x0027
    KTENTRY str_cmp             ; 0x002A
    KTENTRY str_ltrim           ; 0x002D
    KTENTRY str_to_dosname      ; 0x0030
    KTENTRY _uc_al              ; 0x0033
    KTENTRY print_hex_byte      ; 0x0036
    KTENTRY print_word_dec      ; 0x0039
    KTENTRY fat_find            ; 0x003C
    KTENTRY fat_read_file       ; 0x003F
    KTENTRY fat_load_dir        ; 0x0042
    KTENTRY fat_save_dir        ; 0x0045
    KTENTRY fat_save_fat        ; 0x0048
    KTENTRY fat_alloc_cluster   ; 0x004B
    KTENTRY fat_set_entry       ; 0x004E
    KTENTRY fat_find_free_slot  ; 0x0051
    KTENTRY cluster_to_lba      ; 0x0054
    KTENTRY fat_next_cluster    ; 0x0057
    KTENTRY disk_read_sector    ; 0x005A
    KTENTRY disk_write_sector   ; 0x005D

; ---------------------------------------------------------------------------
; 0x0060: Shared data area - fixed addresses used by both kernel and overlays
; (Declared here so their offsets are stable. The labels are referenced by
;  shell.asm command handlers and by overlays via ovl_api.asm EQUs.)
; ---------------------------------------------------------------------------
sh_arg:         times 128 db 0      ; 0x0060 - 0x00DF
_sh_tmp11:      times  12 db 0      ; 0x00E0 - 0x00EB
_sh_type_sz:    dw 0                ; 0x00EC - 0x00ED

; ---------------------------------------------------------------------------
; 0x00EE: kernel_entry - real startup code begins here
; ---------------------------------------------------------------------------
kernel_entry:
    mov ax, 0x1000
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFE
    mov [boot_drive], dl

    ; Set 80x25 text mode
    mov ax, 0x0003
    int 0x10

    ; Hide cursor block (solid underscore style)
    mov ah, 0x01
    mov cx, 0x2607
    int 0x10

    call fat_init
    call auth_init
    call shell_run

    cli
.halt:
    hlt
    jmp .halt

; ---------------------------------------------------------------------------
; Overlay loader
; ---------------------------------------------------------------------------
OVERLAY_BUF equ 0x7000

; ovl_load_run: find an overlay file, load it into OVERLAY_BUF, and run it.
; Input:  SI = pointer to the 11-byte FAT 8.3 filename  (e.g. "NET     OVL")
; Effect: the overlay executes and returns; then control returns to caller.
ovl_load_run:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    ; Force root-directory search (overlays always live in the root)
    push word [cur_dir_cluster]
    mov word [cur_dir_cluster], 0

    call fat_find           ; SI = 11-byte name, result: DI = dir entry / CF
    jc .not_found

    ; Read overlay clusters into OVERLAY_BUF
    mov ax, [di+26]         ; starting cluster
    mov di, OVERLAY_BUF
    call fat_read_file

    ; Restore working directory
    pop word [cur_dir_cluster]

    ; Call the overlay (near call, same segment DS=0x1000)
    call OVERLAY_BUF
    jmp .done

.not_found:
    pop word [cur_dir_cluster]
    push si
    mov si, str_ovl_err
    call vid_println
    pop si

.done:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

str_ovl_err:  db "Error: overlay not found.", 0

; ---------------------------------------------------------------------------
; Subsystem includes (order matters for forward references)
; ---------------------------------------------------------------------------
%include "string.asm"
%include "video.asm"
%include "keyboard.asm"
%include "disk.asm"
%include "fat12.asm"
%include "auth.asm"
%include "music.asm"
%include "shell.asm"

kernel_end:
