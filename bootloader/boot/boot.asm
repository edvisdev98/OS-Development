	org 0x7C00 						; The BIOS loads the 512-byte boot sector at address 0x7C00.
	bits 16							; In legacy BIOS boot, we always begin in real mode. Meaning
									; we are limited to 16-bit operands and instructions (not ideal on a >16-bit machine).
_start:
	;; Setup data segments
	mov ax, 0
	mov es, ax
	mov ds, ax
	mov ss, ax

	;; Setup the stack register.
	mov sp, 0x7C00					; The stack grows downwards, which is why we are able to set
									; the address to the same address as our boot sector.
	
	mov si, msg_hello_world
	call printr
.L1:
	cli								; Clear the interrupt flag, meaning we won't expect a maskable
									; interrupt to continue execution after halt.
	hlt								; Halt the CPU, meaning it shouldn't continue executing instructions..
	
	jmp .L1							; Just in case the CPU continues, we don't want
									; the CPU trying to execute random memory beyond our boot sector.

;;; `printr`:
;;; Prints the string pointed to by the **SI** register.
;;; - Paramters:
;;; 	- SI (Source Index): points to the data for teletype output.
printr:
	push si							; Save the SI register, who knows someone might need it later.
	push ax							; AX is the most used register, most of the time. So saving it
									; is practically recommended.
	push bx
.Lputlp:
	lodsb							; Loads byte pointed to by SI (Source Index) into AX (Accumulator), advances SI.
	;; If the AX (Lower) equal to zero, we have reached the null terminator
	;; and must abort to avoid endlessly writing 'random' bytes.
	or al, al
	jz .Lend	
	
	mov ah, 0x0E					; Make sure when calling `int 0x10` we are in teletype output function.
	mov bh, 0						; Shouldn't always be setting page number every iteration, but
									; to avoid hard limits, it's basically the only option.
	int 0x10						; call **BIOS** interrupt 0x10 (Vector 17) on teletype output function, see above.
	jmp .Lputlp
.Lend:
	;; Load saved registers on stack
	pop bx
	pop ax
	pop si
	ret

msg_hello_world: db 'Hello, World!', 0x0A, 0x0D, 0

	times 510-($-$$) db 0			; Pad the remaining bytes of the boot sector (if any).
									; we do this because the BIOS expects a 512-byte boot
									; sector, nothing more and nothing less.
	dw 0xAA55						; Boot sector magic number - signifies it's bootable.
