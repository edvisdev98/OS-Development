;;; `vgabios.asm`:
;;; provides basic print systems that use the bios.
    
;;; `printr`:
;;; Prints the string pointed to by the **SI** register.
;;; - Paramters:
;;; 	- SI (Source Index): points to the data for teletype output.
printr:
    push si                                                     ; Save the SI register, who knows someone might need it later.
    push ax                                                     ; AX is the most used register, most of the time. So saving it
                                                                ; is practically recommended.
    push bx
.Lputlp:
    lodsb							; Loads byte pointed to by SI (Source Index) into AX (Accumulator), advances SI.
    ;; If the AX (Lower) equal to zero, we have reached the null terminator
    ;; and must abort to avoid endlessly writing 'random' bytes.
    or al, al
    jz .Lend
    
    mov ah, 0x0E                                                ; Make sure when calling `int 0x10` we are in teletype output function.
    mov bh, 0                                                   ; Shouldn't always be setting page number every iteration, but
                                                                ; to avoid hard limits, it's basically the only option.
    int 0x10                                                    ; call **BIOS** interrupt 0x10 (Vector 17) on teletype output function, see above.
    jmp .Lputlp
.Lend:
    ;; Load saved registers on stack
    pop bx
    pop ax
    pop si
    ret
