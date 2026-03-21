; =============================================================================
; video.asm - VGA Text Mode + Mode 13h (320x200x256) driver
; 16-bit real mode
; =============================================================================

; ---- Text mode constants ----
VGA_TEXT_SEG    equ 0xB800
VGA_COLS        equ 80
VGA_ROWS        equ 25
ATTR_NORMAL     equ 0x07
ATTR_BRIGHT     equ 0x0F
ATTR_GREEN      equ 0x0A
ATTR_CYAN       equ 0x0B
ATTR_YELLOW     equ 0x0E
ATTR_RED        equ 0x04
ATTR_MAGENTA    equ 0x05

; ---- Mode 13h constants ----
VGA_GFX_SEG     equ 0xA000
MODE13_W        equ 320
MODE13_H        equ 200

; ---- State vars ----
vid_cur_col:    db 0
vid_cur_row:    db 0
vid_attr:       db ATTR_NORMAL

; =============================================================================
; TEXT MODE FUNCTIONS
; =============================================================================

; ---- vid_clear: clear screen, home cursor ----
vid_clear:
    push ax
    push bx
    push cx
    push dx
    mov ax, 0x0600      ; scroll up (clear)
    mov bh, ATTR_NORMAL
    xor cx, cx
    mov dx, ((VGA_ROWS-1) << 8) | (VGA_COLS-1)
    int 0x10
    xor dx, dx
    call vid_set_cursor
    mov byte [vid_cur_col], 0
    mov byte [vid_cur_row], 0
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---- vid_set_cursor: DH=row, DL=col ----
vid_set_cursor:
    push ax
    push bx
    mov ah, 0x02
    xor bh, bh
    int 0x10
    mov [vid_cur_row], dh
    mov [vid_cur_col], dl
    pop bx
    pop ax
    ret

; ---- vid_get_cursor: returns DH=row, DL=col ----
vid_get_cursor:
    push ax
    push bx
    push cx
    mov ah, 0x03
    xor bh, bh
    int 0x10
    pop cx
    pop bx
    pop ax
    ret

; ---- vid_putchar: print AL (handles \n \r \b) ----
vid_putchar:
    push ax
    push bx
    cmp al, 0x0A
    je .newline
    cmp al, 0x0D
    je .cr
    cmp al, 0x08
    je .bs
    ; Regular character via BIOS TTY
    mov ah, 0x0E
    xor bh, bh
    mov bl, [vid_attr]
    int 0x10
    pop bx
    pop ax
    ret
.newline:
    ; CR+LF
    mov al, 0x0D
    mov ah, 0x0E
    xor bh, bh
    int 0x10
    mov al, 0x0A
    mov ah, 0x0E
    int 0x10
    pop bx
    pop ax
    ret
.cr:
    mov al, 0x0D
    mov ah, 0x0E
    xor bh, bh
    int 0x10
    pop bx
    pop ax
    ret
.bs:
    ; Get cursor, go back 1
    call vid_get_cursor
    cmp dl, 0
    je .bs_done
    dec dl
    call vid_set_cursor
    mov al, ' '
    mov ah, 0x0E
    xor bh, bh
    int 0x10
    call vid_get_cursor
    dec dl
    call vid_set_cursor
.bs_done:
    pop bx
    pop ax
    ret

; ---- vid_print: print null-terminated string at DS:SI ----
vid_print:
    push ax
    push si
.lp:
    lodsb
    test al, al
    jz .done
    call vid_putchar
    jmp .lp
.done:
    pop si
    pop ax
    ret

; ---- vid_println: print DS:SI + newline ----
vid_println:
    call vid_print
    push ax
    mov al, 0x0A
    call vid_putchar
    pop ax
    ret

; ---- vid_nl: print newline ----
vid_nl:
    push ax
    mov al, 0x0A
    call vid_putchar
    pop ax
    ret

; ---- vid_print_char: print AL ----
vid_print_char:
    jmp vid_putchar

; ---- vid_set_attr: set text attribute AL ----
vid_set_attr:
    mov [vid_attr], al
    ret

; =============================================================================
; MODE 13h (320x200 x 256 colour) FUNCTIONS
; =============================================================================

; ---- gfx_enter: switch to Mode 13h ----
gfx_enter:
    push ax
    mov ax, 0x0013
    int 0x10
    pop ax
    ret

; ---- gfx_exit: return to 80x25 text mode ----
gfx_exit:
    push ax
    mov ax, 0x0003
    int 0x10
    pop ax
    ret

; ---- gfx_clear: fill framebuffer with colour AL ----
gfx_clear:
    push ax
    push cx
    push di
    push es
    mov ah, al
    mov cx, ax          ; AH:AL = color
    mov ax, VGA_GFX_SEG
    mov es, ax
    xor di, di
    mov cx, MODE13_W * MODE13_H / 2
    ; pack 2 pixels into AX
    mov al, ah
    mov cx, MODE13_W * MODE13_H / 2
    rep stosw
    pop es
    pop di
    pop cx
    pop ax
    ret

; ---- gfx_pixel: plot pixel at DX=row, CX=col, AL=colour ----
; Uses direct VGA memory write
gfx_pixel:
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    ; Bounds check
    cmp dx, MODE13_H
    jae .done
    cmp cx, MODE13_W
    jae .done
    mov ax, VGA_GFX_SEG
    mov es, ax
    ; offset = row*320 + col
    mov di, dx
    ; di * 320 = di*256 + di*64
    shl di, 8
    mov bx, dx
    shl bx, 6
    add di, bx
    add di, cx
    mov al, [esp+10]    ; restore original AL from stack
    ; Actually let's save AL before we clobber it
    ; Let me redo this properly:
.done:
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Better gfx_pixel: AL=colour, BX=x (0..319), DX=y (0..199)
gfx_pix:
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    cmp bx, MODE13_W
    jae .skip
    cmp dx, MODE13_H
    jae .skip
    mov cx, ax          ; save colour in CL
    mov ax, VGA_GFX_SEG
    mov es, ax
    mov ax, dx
    mov di, ax
    shl di, 8           ; di = y * 256
    shl ax, 6           ; ax = y * 64
    add di, ax          ; di = y * 320
    add di, bx          ; di = y*320 + x
    mov al, cl
    stosb
.skip:
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---- gfx_line: Bresenham line AL=col, BX=x0, CX=y0, DX=x1, SI=y1 ----
; Trashes: BX, CX, DX, SI, AX
gfx_line:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es
    ; Store colour
    mov [gl_line_col], al
    mov [gl_x0], bx
    mov [gl_y0], cx
    mov [gl_x1], dx
    mov [gl_y1], si

    ; dx_abs = abs(x1-x0), dy_abs = abs(y1-y0)
    mov ax, dx
    sub ax, bx
    mov [gl_dx], ax
    jge .dx_pos
    neg ax
.dx_pos:
    mov [gl_dx_abs], ax

    mov ax, si
    sub ax, cx
    mov [gl_dy], ax
    jge .dy_pos
    neg ax
.dy_pos:
    mov [gl_dy_abs], ax

    ; sx = (x0<x1)?1:-1
    mov ax, [gl_x0]
    cmp ax, [gl_x1]
    jl .sx_pos
    mov word [gl_sx], -1
    jmp .sy
.sx_pos:
    mov word [gl_sx], 1
.sy:
    ; sy = (y0<y1)?1:-1
    mov ax, [gl_y0]
    cmp ax, [gl_y1]
    jl .sy_pos
    mov word [gl_sy], -1
    jmp .err_init
.sy_pos:
    mov word [gl_sy], 1

.err_init:
    mov ax, [gl_dx_abs]
    sub ax, [gl_dy_abs]
    mov [gl_err], ax

.bres_loop:
    ; Plot (gl_x0, gl_y0)
    mov bx, [gl_x0]
    mov dx, [gl_y0]
    mov al, [gl_line_col]
    call gfx_pix

    ; Check if at destination
    mov ax, [gl_x0]
    cmp ax, [gl_x1]
    jne .not_done
    mov ax, [gl_y0]
    cmp ax, [gl_y1]
    jne .not_done
    jmp .line_done
.not_done:

    ; e2 = 2 * err
    mov ax, [gl_err]
    shl ax, 1
    mov [gl_e2], ax

    ; if e2 > -dy_abs: err -= dy_abs, x0 += sx
    mov bx, [gl_dy_abs]
    neg bx                  ; -dy_abs
    cmp ax, bx
    jle .no_x
    mov bx, [gl_dy_abs]
    sub [gl_err], bx
    mov bx, [gl_sx]
    add [gl_x0], bx
.no_x:

    ; if e2 < dx_abs: err += dx_abs, y0 += sy
    mov ax, [gl_e2]
    mov bx, [gl_dx_abs]
    cmp ax, bx
    jge .no_y
    add [gl_err], bx
    mov bx, [gl_sy]
    add [gl_y0], bx
.no_y:

    jmp .bres_loop

.line_done:
    pop es
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Temp vars for gfx_line
gl_line_col:    db 0
gl_x0:          dw 0
gl_y0:          dw 0
gl_x1:          dw 0
gl_y1:          dw 0
gl_dx:          dw 0
gl_dy:          dw 0
gl_dx_abs:      dw 0
gl_dy_abs:      dw 0
gl_sx:          dw 1
gl_sy:          dw 1
gl_err:         dw 0
gl_e2:          dw 0

; =============================================================================
; VGA PALETTE (DAC registers)
; Set palette entry: AL=index, BH=R, BL=G, DL=B (all 0..63)
; =============================================================================
gfx_set_palette_entry:
    push ax
    push bx
    push cx
    push dx
    mov ah, 0x10
    mov al, 0x10
    xor bh, 0
    ; INT 10h AX=1010h: set individual DAC register
    ; BX=palette register, CH=G, CL=B, DH=R
    int 0x10
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Setup a nice 256-color palette for demos
gfx_setup_palette:
    push ax
    push bx
    push cx
    push dx
    push si
    ; Set up first 16 entries as CGA-compatible
    ; Then a smooth gradient for the rest
    ; Use BIOS INT 10h AX=1012h: Set block of DAC registers
    ; ES:DX = table of RGB triplets (3 bytes each, 0..63 scale)
    ; BX = starting register, CX = count
    ; For simplicity, just set a basic palette:

    ; Black=0, Blue=1, Green=2, Cyan=3, Red=4, Magenta=5,
    ; Brown=6, LightGrey=7, DarkGrey=8, LightBlue=9...
    ; We'll do a simple ramp palette for colours 16-255

    ; First: standard CGA 16 colours in entries 0-15
    push ds
    push es
    mov ax, ds
    mov es, ax
    mov si, cga_palette
    mov ax, 0x1012          ; set block DAC
    xor bx, bx              ; starting register 0
    mov cx, 16              ; 16 entries
    ; ES:DX = pointer to table
    mov dx, si
    int 0x10
    pop es
    pop ds

    ; Entries 16-255: smooth RGB cube and gradients
    ; We'll do a simple approach: use INT 10h 1010h per entry
    mov al, 16              ; start at palette entry 16
.pal_loop:
    cmp al, 255
    ja .pal_done
    ; Calculate R,G,B from entry index
    ; Simple gradient: cycles through hues
    push ax
    xor ah, ah
    ; R = (index * 4) & 0xFF → 0..252
    mov bl, al
    shl bl, 2
    and bl, 0x3F            ; scale to 0..63
    ; G = (index * 2) & 0x3F
    mov bh, al
    shl bh, 1
    and bh, 0x3F
    ; B = index & 0x3F
    mov cl, al
    and cl, 0x3F

    ; INT 10h AX=1010h: set single DAC register
    ; DH=R, CH=G, CL=B, BX=register number
    pop ax
    push ax
    xor bx, bx
    mov bl, al              ; BX = register index
    mov dh, bl
    shr dh, 2
    and dh, 0x3F            ; R
    mov ch, bl
    shr ch, 1
    and ch, 0x3F            ; G  
    mov cl, bl
    and cl, 0x3F            ; B
    mov ax, 0x1010
    int 0x10

    pop ax
    inc al
    jnz .pal_loop
.pal_done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; CGA 16-color palette (R,G,B each 0..63)
cga_palette:
    db  0, 0, 0        ; 0: Black
    db  0, 0,42        ; 1: Blue
    db  0,42, 0        ; 2: Green
    db  0,42,42        ; 3: Cyan
    db 42, 0, 0        ; 4: Red
    db 42, 0,42        ; 5: Magenta
    db 42,21, 0        ; 6: Brown
    db 42,42,42        ; 7: Light Grey
    db 21,21,21        ; 8: Dark Grey
    db 21,21,63        ; 9: Light Blue
    db 21,63,21        ; 10: Light Green
    db 21,63,63        ; 11: Light Cyan
    db 63,21,21        ; 12: Light Red
    db 63,21,63        ; 13: Light Magenta
    db 63,63,21        ; 14: Yellow
    db 63,63,63        ; 15: White
