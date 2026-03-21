; =============================================================================
; ovl_api.asm - Kernel API for overlay modules
; Include this file FIRST in every overlay source, before the module code.
; Redefines kernel function names as jump-table EQUs so that the unmodified
; module source files work transparently inside the overlay binary.
; =============================================================================

BITS 16

; ---------------------------------------------------------------------------
; Overlay load address (must stay above the kernel binary end)
; ---------------------------------------------------------------------------
%ifndef OVERLAY_BUF
OVERLAY_BUF     equ 0x7000
%endif

; ---------------------------------------------------------------------------
; Shared data area: fixed addresses in the kernel prefix (set by ksdos.asm)
; These must match the declarations in ksdos.asm exactly.
; ---------------------------------------------------------------------------
sh_arg          equ 0x0060      ; 128-byte argument buffer
_sh_tmp11       equ 0x00E0      ; 12-byte DOS 8.3 name temp buffer
_sh_type_sz     equ 0x00EC      ; word: source file size (used by compilers)

; ---------------------------------------------------------------------------
; Constants mirrored from the kernel (EQUs, unchanged)
; ---------------------------------------------------------------------------
FAT_BUF         equ 0xC000
DIR_BUF         equ 0xD200
FILE_BUF        equ 0xF000

ATTR_NORMAL     equ 0x07
ATTR_BRIGHT     equ 0x0F
ATTR_GREEN      equ 0x0A
ATTR_CYAN       equ 0x0B
ATTR_YELLOW     equ 0x0E
ATTR_RED        equ 0x04
ATTR_MAGENTA    equ 0x05

; ---------------------------------------------------------------------------
; Kernel jump table (0x0003 + entry_index * 3)
; Each entry is a 3-byte near JMP to the real kernel function.
; Redefining these names here means all `call vid_print` etc. in the
; included module source automatically target the jump table.
; ---------------------------------------------------------------------------
vid_print           equ 0x0003
vid_println         equ 0x0006
vid_putchar         equ 0x0009
vid_nl              equ 0x000C
vid_clear           equ 0x000F
vid_set_attr        equ 0x0012
vid_get_cursor      equ 0x0015
vid_set_cursor      equ 0x0018
kbd_getkey          equ 0x001B
kbd_check           equ 0x001E
kbd_readline        equ 0x0021
str_len             equ 0x0024
str_copy            equ 0x0027
str_cmp             equ 0x002A
str_ltrim           equ 0x002D
str_to_dosname      equ 0x0030
_uc_al              equ 0x0033
print_hex_byte      equ 0x0036
print_word_dec      equ 0x0039
fat_find            equ 0x003C
fat_read_file       equ 0x003F
fat_load_dir        equ 0x0042
fat_save_dir        equ 0x0045
fat_save_fat        equ 0x0048
fat_alloc_cluster   equ 0x004B
fat_set_entry       equ 0x004E
fat_find_free_slot  equ 0x0051
cluster_to_lba      equ 0x0054
fat_next_cluster    equ 0x0057
disk_read_sector    equ 0x005A
disk_write_sector   equ 0x005D
