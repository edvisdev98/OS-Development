    bits 16
    org 0x7E00
_start:
	;; STRIPPED FROM BBI86 - rok3tt
	
    ;; Setting up the GDT (Global Descriptor Table)
    mov eax, gdt_desc                ; Remember, we are still in 16-bit addressing so we must use
                                     ; convert the 32-bit address into a valid segmented address
    mov ebx, eax
    shr eax, 4
    and ebx, 0xF
    mov ds, ax
    lgdt [ds:bx]                     ; Set the GDTR register to `gdt_desc`

    ;; Enable A20 line (Enable the 21st bit in any memory access)
    ;; NOTE: This only uses the fast A20 gate method---we will not
    ;;       support older systems that don't have this.
    in al, 0x92
    or al, 2
    out 0x92, al

    ;; Set PE bit (Protection Enable) in CR0 (Control Register 0)
    ;; Note: Enabled protected mode, hopefully with GDT set properly & A20 enabled.
    mov eax, cr0
    or al, 1
    mov cr0, eax

	jmp dword 0x08:after
.L1:
    hlt
    jmp .L1

;;; `gdt_start` - `gdt_end`: Global Descriptor Table (Basic Setup)
;;; Format:
;;;     - Entry 0 (NULL - 64-bit)
;;;     - Entry 1 (Code Segment - 64-bit)
;;;     - Entry 2 (Data Segment - 64-bit)
gdt_start:
    ;; Null Entry
    dq 0

    ; Code Segment: base=0, limit=0xFFFFF, 32-bit, executable, readable
    dw 0xFFFF          ; Limit low
    dw 0x0000          ; Base low
    db 0x00            ; Base middle
    db 0x9A            ; Access byte: 1 00 1 1010
    db 0xCF            ; flags + limit high: 1100 1111
    db 0x00            ; Base high

    ; Data Segment: base=0, limit=0xFFFFF, 32-bit, readable/writable
    dw 0xFFFF          ; Limit low
    dw 0x0000          ; Base low
    db 0x00            ; Base middle
    db 0x92            ; Access byte: 1 00 1 0010
    db 0xCF            ; Flags + limit high: 1100 1111
    db 0x00            ; Base high
gdt_end:

;;; `gdt_desc`: GDT (Global Descriptor Table) Descriptor
;;; Format:
;;;     - limit (16-bit)
;;;     - base (32-bit)
gdt_desc:
    dw gdt_end - gdt_start - 1
    dd gdt_start

    ;; Just to make sure there's room for changes
    times 256-($-$$) db 0
after:
