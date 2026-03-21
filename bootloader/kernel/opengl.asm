; =============================================================================
; opengl.asm - KSDOS Software OpenGL 16-bit
; VGA Mode 13h (320x200 x 256 colours)
; Implements: gl16_init, gl16_exit, gl16_clear, gfx_pix, gfx_line,
;             gl16_tri, gl16_cube_demo, gl16_triangle_demo
;
; Uses sdk/psyq and sdk/gold4 rendering concepts adapted for 16-bit real mode
; Fixed-point math: 16.0 integer (no fractions needed for 320x200)
; =============================================================================

; ---------------------------------------------------------------------------
; Graphics constants (guarded — video.asm defines these in the full kernel)
; ---------------------------------------------------------------------------
%ifndef VGA_GFX_SEG
VGA_GFX_SEG     equ 0xA000
%endif
%ifndef MODE13_W
MODE13_W        equ 320
MODE13_H        equ 200
%endif

; ---------------------------------------------------------------------------
; gfx_setup_palette / helpers — copied from video.asm so opengl.asm is
; self-contained when assembled as an overlay (video.asm not included).
; Guarded so the kernel build (which includes video.asm) sees no duplicates.
; ---------------------------------------------------------------------------
%ifndef GFX_PALETTE_DEFINED
%define GFX_PALETTE_DEFINED

gfx_set_palette_entry:
    push ax
    push bx
    push cx
    push dx
    mov ah, 0x10
    mov al, 0x10
    xor bh, 0
    int 0x10
    pop dx
    pop cx
    pop bx
    pop ax
    ret

gfx_setup_palette:
    push ax
    push bx
    push cx
    push dx
    push si
    push ds
    push es
    mov ax, ds
    mov es, ax
    mov si, cga_palette
    mov ax, 0x1012
    xor bx, bx
    mov cx, 16
    mov dx, si
    int 0x10
    pop es
    pop ds
    mov al, 16
.pal_loop:
    cmp al, 255
    ja .pal_done
    push ax
    xor bx, bx
    mov bl, al
    mov dh, bl
    shr dh, 2
    and dh, 0x3F
    mov ch, bl
    shr ch, 1
    and ch, 0x3F
    mov cl, bl
    and cl, 0x3F
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

cga_palette:
    db  0, 0, 0
    db  0, 0,42
    db  0,42, 0
    db  0,42,42
    db 42, 0, 0
    db 42, 0,42
    db 42,21, 0
    db 42,42,42
    db 21,21,21
    db 21,21,63
    db 21,63,21
    db 21,63,63
    db 63,21,21
    db 63,21,63
    db 63,63,21
    db 63,63,63

; gfx_pix: plot one pixel  AL=colour, BX=x (0..319), DX=y (0..199)
gfx_pix:
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    cmp bx, MODE13_W
    jae .gp_skip
    cmp dx, MODE13_H
    jae .gp_skip
    mov cx, ax
    mov ax, VGA_GFX_SEG
    mov es, ax
    mov ax, dx
    mov di, ax
    shl di, 8
    shl ax, 6
    add di, ax
    add di, bx
    mov al, cl
    stosb
.gp_skip:
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; gfx_line: Bresenham line  AL=col, BX=x0, CX=y0, DX=x1, SI=y1
gfx_line:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es
    mov [gl_line_col], al
    mov [gl_x0], bx
    mov [gl_y0], cx
    mov [gl_x1], dx
    mov [gl_y1], si
    mov ax, dx
    sub ax, bx
    mov [gl_dx], ax
    jge .gdx_pos
    neg ax
.gdx_pos:
    mov [gl_dx_abs], ax
    mov ax, si
    sub ax, cx
    mov [gl_dy], ax
    jge .gdy_pos
    neg ax
.gdy_pos:
    mov [gl_dy_abs], ax
    mov ax, [gl_x0]
    cmp ax, [gl_x1]
    jl .gsx_pos
    mov word [gl_sx], -1
    jmp .gsy
.gsx_pos:
    mov word [gl_sx], 1
.gsy:
    mov ax, [gl_y0]
    cmp ax, [gl_y1]
    jl .gsy_pos
    mov word [gl_sy], -1
    jmp .gerr_init
.gsy_pos:
    mov word [gl_sy], 1
.gerr_init:
    mov ax, [gl_dx_abs]
    sub ax, [gl_dy_abs]
    mov [gl_err], ax
.gbres_loop:
    mov bx, [gl_x0]
    mov dx, [gl_y0]
    mov al, [gl_line_col]
    call gfx_pix
    mov ax, [gl_x0]
    cmp ax, [gl_x1]
    jne .gnot_done
    mov ax, [gl_y0]
    cmp ax, [gl_y1]
    jne .gnot_done
    jmp .gline_done
.gnot_done:
    mov ax, [gl_err]
    shl ax, 1
    mov [gl_e2], ax
    mov bx, [gl_dy_abs]
    neg bx
    cmp ax, bx
    jle .gno_x
    mov bx, [gl_dy_abs]
    sub [gl_err], bx
    mov bx, [gl_sx]
    add [gl_x0], bx
.gno_x:
    mov ax, [gl_e2]
    mov bx, [gl_dx_abs]
    cmp ax, bx
    jge .gno_y
    add [gl_err], bx
    mov bx, [gl_sy]
    add [gl_y0], bx
.gno_y:
    jmp .gbres_loop
.gline_done:
    pop es
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Data vars for gfx_line
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

%endif

; ---- gl state ----
gl_mode:        db 0        ; 0=text, 1=graphics

; ============================================================
; gl16_init: switch to Mode 13h and set up palette
; ============================================================
gl16_init:
    push ax
    mov ax, 0x0013
    int 0x10
    mov byte [gl_mode], 1
    call gfx_setup_palette
    pop ax
    ret

; ============================================================
; gl16_exit: return to 80x25 text mode
; ============================================================
gl16_exit:
    push ax
    mov ax, 0x0003
    int 0x10
    mov byte [gl_mode], 0
    pop ax
    ret

; ============================================================
; gl16_clear: fill screen with colour AL
; ============================================================
gl16_clear:
    push ax
    push cx
    push di
    push es
    mov cx, ax              ; save colour
    mov ax, VGA_GFX_SEG
    mov es, ax
    xor di, di
    mov al, cl
    mov ah, cl
    mov cx, MODE13_W * MODE13_H / 2
    rep stosw
    pop es
    pop di
    pop cx
    pop ax
    ret

; ============================================================
; gl16_pix: plot pixel  BX=x, DX=y, AL=colour
; ============================================================
gl16_pix:
    cmp bx, MODE13_W
    jae .skip
    cmp dx, MODE13_H
    jae .skip
    push ax
    push bx
    push dx
    push di
    push es
    mov cx, ax              ; save colour
    mov ax, VGA_GFX_SEG
    mov es, ax
    mov ax, dx
    ; offset = y*320 + x  (320 = 256 + 64)
    mov di, ax
    shl di, 8               ; di = y*256
    shl ax, 6               ; ax = y*64
    add di, ax              ; di = y*320
    add di, bx              ; di = y*320 + x
    mov al, cl              ; colour
    stosb
    pop es
    pop di
    pop dx
    pop bx
    pop ax
.skip:
    ret

; ============================================================
; gl16_tri: filled triangle (scanline fill)
; Arguments passed via memory (set before call):
;   tri_x0,tri_y0, tri_x1,tri_y1, tri_x2,tri_y2 (words)
;   tri_col (byte) = fill colour
; ============================================================
tri_x0: dw 0
tri_y0: dw 0
tri_x1: dw 0
tri_y1: dw 0
tri_x2: dw 0
tri_y2: dw 0
tri_col: db 0

gl16_tri:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; Sort vertices by Y (simple bubble sort on 3 points)
    ; Ensure y0 <= y1 <= y2
    mov ax, [tri_y0]
    cmp ax, [tri_y1]
    jle .ok01
    ; swap 0 and 1
    mov bx, [tri_x1]
    mov cx, [tri_y1]
    xchg bx, [tri_x0]
    xchg cx, [tri_y0]
    mov [tri_x1], bx
    mov [tri_y1], cx
.ok01:
    mov ax, [tri_y0]
    cmp ax, [tri_y2]
    jle .ok02
    mov bx, [tri_x2]
    mov cx, [tri_y2]
    xchg bx, [tri_x0]
    xchg cx, [tri_y0]
    mov [tri_x2], bx
    mov [tri_y2], cx
.ok02:
    mov ax, [tri_y1]
    cmp ax, [tri_y2]
    jle .ok12
    mov bx, [tri_x2]
    mov cx, [tri_y2]
    xchg bx, [tri_x1]
    xchg cx, [tri_y1]
    mov [tri_x2], bx
    mov [tri_y2], cx
.ok12:

    ; Now y0 <= y1 <= y2
    ; Draw flat-bottom triangle (y0..y1) and flat-top (y1..y2)

    ; Flat-bottom: y from y0 to y1
    mov ax, [tri_y0]
    mov dx, [tri_y1]
    cmp ax, dx
    je .skip_top
.top_loop:
    cmp ax, dx
    jg .skip_top
    push ax
    push dx
    ; Interpolate x on left edge (p0→p2) and right edge (p0→p1)
    ; x_left  = x0 + (x2-x0)*(y-y0)/(y2-y0)
    ; x_right = x0 + (x1-x0)*(y-y0)/(y1-y0)
    ; Using fixed-point integer division
    mov bx, ax              ; bx = current y
    sub bx, [tri_y0]       ; bx = y - y0

    ; x_left: (x2-x0)*(y-y0) / (y2-y0)
    mov si, [tri_x2]
    sub si, [tri_x0]
    imul si, bx
    mov cx, [tri_y2]
    sub cx, [tri_y0]
    test cx, cx
    jz .skip_left
    cwd
    idiv cx
.skip_left:
    add ax, [tri_x0]
    mov [_tri_xl], ax

    ; x_right: (x1-x0)*(y-y0) / (y1-y0)
    mov ax, bx
    mov si, [tri_x1]
    sub si, [tri_x0]
    imul si, ax
    mov cx, [tri_y1]
    sub cx, [tri_y0]
    test cx, cx
    jz .flat_right
    cwd
    idiv cx
.flat_right:
    add ax, [tri_x0]
    mov [_tri_xr], ax

    ; Draw horizontal line at y=bx from xl to xr
    pop dx
    push dx
    mov dx, [esp+2]         ; y value (it's on stack)
    pop dx
    pop ax
    push ax
    push dx

    mov dx, ax              ; DX = current y (scanline)
    mov ax, [_tri_xl]
    mov bx, [_tri_xr]
    cmp ax, bx
    jle .draw_top_span
    xchg ax, bx
.draw_top_span:
    ; Draw pixels from ax to bx on row dx
    cmp ax, bx
    jg .top_span_done
    push ax
    push bx
    push dx
    mov bx, ax              ; x position
    mov al, [tri_col]
    call gl16_pix
    pop dx
    pop bx
    pop ax
    inc ax
    jmp .draw_top_span
.top_span_done:
    pop dx
    pop ax
    inc ax
    jmp .top_loop
.skip_top:

    ; Flat-top triangle: y from y1 to y2
    mov ax, [tri_y1]
    mov dx, [tri_y2]
    cmp ax, dx
    je .skip_bot
.bot_loop:
    cmp ax, dx
    jg .skip_bot
    push ax
    push dx
    mov bx, ax
    sub bx, [tri_y1]

    ; x_left: (x2-x1)*(y-y1)/(y2-y1)
    mov si, [tri_x2]
    sub si, [tri_x1]
    imul si, bx
    mov cx, [tri_y2]
    sub cx, [tri_y1]
    test cx, cx
    jz .skip_bl
    cwd
    idiv cx
.skip_bl:
    add ax, [tri_x1]
    mov [_tri_xl], ax

    ; x_right: (x2-x0)*(y-y0)/(y2-y0) [the long edge]
    mov ax, bx
    add ax, [tri_y1]
    sub ax, [tri_y0]        ; ax = y - y0
    mov si, [tri_x2]
    sub si, [tri_x0]
    imul si, ax
    mov cx, [tri_y2]
    sub cx, [tri_y0]
    test cx, cx
    jz .skip_br
    cwd
    idiv cx
.skip_br:
    add ax, [tri_x0]
    mov [_tri_xr], ax

    pop dx
    push dx
    pop ax                  ; tricky: restore ax = current y
    pop dx
    push ax
    push dx

    mov dx, ax
    mov ax, [_tri_xl]
    mov bx, [_tri_xr]
    cmp ax, bx
    jle .draw_bot_span
    xchg ax, bx
.draw_bot_span:
    cmp ax, bx
    jg .bot_span_done
    push ax
    push bx
    push dx
    mov bx, ax
    mov al, [tri_col]
    call gl16_pix
    pop dx
    pop bx
    pop ax
    inc ax
    jmp .draw_bot_span
.bot_span_done:
    pop dx
    pop ax
    inc ax
    jmp .bot_loop
.skip_bot:

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

_tri_xl: dw 0
_tri_xr: dw 0

; ============================================================
; 5x7 pixel font for graphics mode text (bitmap chars 32-127)
; Each char = 5 bytes, each byte = 7 bits
; ============================================================
gl_font:
    ; Space..tilde (95 chars, 5 bytes each = 475 bytes)
    db 0x00,0x00,0x00,0x00,0x00 ; 32 ' '
    db 0x00,0x00,0x5F,0x00,0x00 ; 33 '!'
    db 0x00,0x07,0x00,0x07,0x00 ; 34 '"'
    db 0x14,0x7F,0x14,0x7F,0x14 ; 35 '#'
    db 0x24,0x2A,0x7F,0x2A,0x12 ; 36 '$'
    db 0x23,0x13,0x08,0x64,0x62 ; 37 '%'
    db 0x36,0x49,0x55,0x22,0x50 ; 38 '&'
    db 0x00,0x05,0x03,0x00,0x00 ; 39 '''
    db 0x00,0x1C,0x22,0x41,0x00 ; 40 '('
    db 0x00,0x41,0x22,0x1C,0x00 ; 41 ')'
    db 0x14,0x08,0x3E,0x08,0x14 ; 42 '*'
    db 0x08,0x08,0x3E,0x08,0x08 ; 43 '+'
    db 0x00,0x50,0x30,0x00,0x00 ; 44 ','
    db 0x08,0x08,0x08,0x08,0x08 ; 45 '-'
    db 0x00,0x60,0x60,0x00,0x00 ; 46 '.'
    db 0x20,0x10,0x08,0x04,0x02 ; 47 '/'
    db 0x3E,0x51,0x49,0x45,0x3E ; 48 '0'
    db 0x00,0x42,0x7F,0x40,0x00 ; 49 '1'
    db 0x42,0x61,0x51,0x49,0x46 ; 50 '2'
    db 0x21,0x41,0x45,0x4B,0x31 ; 51 '3'
    db 0x18,0x14,0x12,0x7F,0x10 ; 52 '4'
    db 0x27,0x45,0x45,0x45,0x39 ; 53 '5'
    db 0x3C,0x4A,0x49,0x49,0x30 ; 54 '6'
    db 0x01,0x71,0x09,0x05,0x03 ; 55 '7'
    db 0x36,0x49,0x49,0x49,0x36 ; 56 '8'
    db 0x06,0x49,0x49,0x29,0x1E ; 57 '9'
    db 0x00,0x36,0x36,0x00,0x00 ; 58 ':'
    db 0x00,0x56,0x36,0x00,0x00 ; 59 ';'
    db 0x08,0x14,0x22,0x41,0x00 ; 60 '<'
    db 0x14,0x14,0x14,0x14,0x14 ; 61 '='
    db 0x00,0x41,0x22,0x14,0x08 ; 62 '>'
    db 0x02,0x01,0x51,0x09,0x06 ; 63 '?'
    db 0x32,0x49,0x79,0x41,0x3E ; 64 '@'
    db 0x7E,0x11,0x11,0x11,0x7E ; 65 'A'
    db 0x7F,0x49,0x49,0x49,0x36 ; 66 'B'
    db 0x3E,0x41,0x41,0x41,0x22 ; 67 'C'
    db 0x7F,0x41,0x41,0x22,0x1C ; 68 'D'
    db 0x7F,0x49,0x49,0x49,0x41 ; 69 'E'
    db 0x7F,0x09,0x09,0x09,0x01 ; 70 'F'
    db 0x3E,0x41,0x49,0x49,0x7A ; 71 'G'
    db 0x7F,0x08,0x08,0x08,0x7F ; 72 'H'
    db 0x00,0x41,0x7F,0x41,0x00 ; 73 'I'
    db 0x20,0x40,0x41,0x3F,0x01 ; 74 'J'
    db 0x7F,0x08,0x14,0x22,0x41 ; 75 'K'
    db 0x7F,0x40,0x40,0x40,0x40 ; 76 'L'
    db 0x7F,0x02,0x0C,0x02,0x7F ; 77 'M'
    db 0x7F,0x04,0x08,0x10,0x7F ; 78 'N'
    db 0x3E,0x41,0x41,0x41,0x3E ; 79 'O'
    db 0x7F,0x09,0x09,0x09,0x06 ; 80 'P'
    db 0x3E,0x41,0x51,0x21,0x5E ; 81 'Q'
    db 0x7F,0x09,0x19,0x29,0x46 ; 82 'R'
    db 0x46,0x49,0x49,0x49,0x31 ; 83 'S'
    db 0x01,0x01,0x7F,0x01,0x01 ; 84 'T'
    db 0x3F,0x40,0x40,0x40,0x3F ; 85 'U'
    db 0x1F,0x20,0x40,0x20,0x1F ; 86 'V'
    db 0x3F,0x40,0x38,0x40,0x3F ; 87 'W'
    db 0x63,0x14,0x08,0x14,0x63 ; 88 'X'
    db 0x07,0x08,0x70,0x08,0x07 ; 89 'Y'
    db 0x61,0x51,0x49,0x45,0x43 ; 90 'Z'
    db 0x00,0x7F,0x41,0x41,0x00 ; 91 '['
    db 0x02,0x04,0x08,0x10,0x20 ; 92 '\'
    db 0x00,0x41,0x41,0x7F,0x00 ; 93 ']'
    db 0x04,0x02,0x01,0x02,0x04 ; 94 '^'
    db 0x40,0x40,0x40,0x40,0x40 ; 95 '_'

; ============================================================
; gl16_text_gfx: draw text string at pixel coords
; BX=x, DX=y, AL=colour, DS:SI=string
; ============================================================
gl16_text_gfx:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov [_gt_x], bx
    mov [_gt_y], dx
    mov [_gt_col], al
.char_loop:
    lodsb
    test al, al
    jz .done
    cmp al, 32
    jb .next_char
    cmp al, 95+32
    ja .next_char
    sub al, 32
    ; Get font data pointer: gl_font + al*5
    xor ah, ah
    mov di, ax
    shl di, 2          ; di = al*4
    add di, ax         ; di = al*5
    add di, gl_font    ; di points to 5-byte glyph
    ; Draw 5 columns x 7 rows
    mov cx, 5          ; column index
    mov bx, [_gt_x]    ; current x
.col_loop:
    test cx, cx
    jz .next_char
    push cx
    mov al, [di]       ; column byte
    inc di
    ; Draw 7 bits (rows)
    push bx
    mov cx, 7
    mov dx, [_gt_y]
.row_loop:
    test al, 1
    jz .no_dot
    push ax
    push cx
    push dx
    mov al, [_gt_col]
    call gl16_pix
    pop dx
    pop cx
    pop ax
.no_dot:
    shr al, 1
    inc dx
    loop .row_loop
    pop bx
    pop cx
    inc bx
    dec cx
    jmp .col_loop
.next_char:
    add word [_gt_x], 6
    jmp .char_loop
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

_gt_x:   dw 0
_gt_y:   dw 0
_gt_col: db 15

; ============================================================
; 3D Math: fixed-point sine table (0..90 degrees, *256)
; ============================================================
sin_tab:
    dw    0,   4,   9,  13,  18,  22,  27,  31,  36,  40
    dw   44,  49,  53,  57,  62,  66,  70,  74,  79,  83
    dw   87,  91,  95,  99, 103, 107, 111, 115, 118, 122
    dw  126, 130, 133, 137, 141, 144, 148, 151, 154, 158
    dw  161, 164, 167, 171, 174, 177, 180, 182, 185, 188
    dw  191, 193, 196, 198, 201, 203, 205, 208, 210, 212
    dw  214, 216, 218, 220, 221, 223, 225, 226, 228, 229
    dw  231, 232, 233, 234, 235, 236, 237, 238, 239, 240
    dw  241, 241, 242, 242, 243, 243, 244, 244, 244, 245
    dw  245

; fsin16: AX = angle (degrees, 0..359) → AX = sin*256 (signed)
fsin16:
    push bx
    push cx
    ; normalize to 0..359
    mov bx, 360
    xor dx, dx
    cmp ax, 0
    jge .noneg
    add ax, 360
.noneg:
    div bx              ; AX = deg % 360
    mov ax, dx

    ; Quadrant
    cmp ax, 90
    jle .q1
    cmp ax, 180
    jle .q2
    cmp ax, 270
    jle .q3
    ; Q4: 270..359  sin = -sin(360-ax)
    mov cx, 360
    sub cx, ax
    mov bx, cx
    shl bx, 1
    mov ax, [sin_tab + bx]
    neg ax
    pop cx
    pop bx
    ret
.q1:
    shl ax, 1
    mov bx, ax
    mov ax, [sin_tab + bx]
    pop cx
    pop bx
    ret
.q2:
    mov cx, 180
    sub cx, ax
    shl cx, 1
    mov bx, cx
    mov ax, [sin_tab + bx]
    pop cx
    pop bx
    ret
.q3:
    sub ax, 180
    shl ax, 1
    mov bx, ax
    mov ax, [sin_tab + bx]
    neg ax
    pop cx
    pop bx
    ret

; fcos16: same as fsin16(angle+90)
fcos16:
    push bx
    add ax, 90
    cmp ax, 360
    jb .ok
    sub ax, 360
.ok:
    call fsin16
    pop bx
    ret

; ============================================================
; gl16_project: 3D → 2D perspective projection
; Input: SI=x*256, DI=y*256, [_pz]=z*256, [_rx],[_ry],[_rz]=angles
; Output: BX=screen_x, DX=screen_y
; Uses temp vars, fixed-point 16-bit
; ============================================================
_pz:    dw 0
_rx:    dw 0
_ry:    dw 0
_rz:    dw 0

; Simple rotation + projection (integer math, *256 scale)
; Rotates around Y axis only for simplicity
gl16_project_y:
    push ax
    push cx
    ; Rotate X and Z by angle _ry:
    ;   x' = x*cos(ry) + z*sin(ry)
    ;   z' = -x*sin(ry) + z*cos(ry)
    ; Then project:
    ;   screen_x = 160 + x'*128/z'
    ;   screen_y = 100 + y *128/z'
    mov ax, [_ry]
    call fcos16         ; AX = cos*256
    ; x' = (SI * cos) >> 8
    push ax
    mov ax, si
    imul word [_ry_cos]
    ; This is getting complex for integer-only; use lookup
    pop ax
    ; Simplified: just return center for now (this will be
    ; replaced by the full cube demo which uses its own math)
    mov bx, 160
    mov dx, 100
    pop cx
    pop ax
    ret
_ry_cos: dw 256

; ============================================================
; gl16_cube_demo: animated rotating wireframe cube
; Press any key to exit
; ============================================================

; Cube vertices (x,y,z each * 64, 8 vertices)
cube_vx: dw -64,  64,  64, -64, -64,  64,  64, -64
cube_vy: dw -64, -64,  64,  64, -64, -64,  64,  64
cube_vz: dw -64, -64, -64, -64,  64,  64,  64,  64

; Cube edges (pairs of vertex indices, 12 edges)
cube_edges:
    db 0,1, 1,2, 2,3, 3,0   ; front face
    db 4,5, 5,6, 6,7, 7,4   ; back face
    db 0,4, 1,5, 2,6, 3,7   ; connecting edges

; Projected 2D coords
proj_x: times 8 dw 0
proj_y: times 8 dw 0

gl16_cube_demo:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    call gl16_init

    mov word [_cube_angle], 0

.frame:
    ; Check for keypress to exit
    call kbd_check
    jnz .exit_cube

    ; Clear screen (dark blue = colour 1)
    mov al, 1
    call gl16_clear

    ; Draw title
    mov bx, 60
    mov dx, 5
    mov al, 15
    mov si, str_gl_title
    call gl16_text_gfx

    ; Project all 8 vertices
    mov cx, 8
    xor di, di              ; vertex index
.proj_loop:
    push cx
    push di
    ; Get vertex coords
    shl di, 1               ; word index
    mov si, [cube_vx + di]  ; x
    mov ax, [cube_vy + di]  ; y
    mov bx, [cube_vz + di]  ; z

    ; Rotate around Y axis: angle = _cube_angle
    ; x' = x*cos - z*sin
    ; z' = x*sin + z*cos
    push si
    push ax
    push bx
    mov ax, [_cube_angle]
    call fcos16             ; AX = cos*256
    mov [_tmp_cos], ax
    mov ax, [_cube_angle]
    call fsin16             ; AX = sin*256
    mov [_tmp_sin], ax
    pop bx                  ; z
    pop ax                  ; y (don't rotate for Y-axis rotation)
    pop si                  ; x

    ; x' = (x*cos - z*sin) / 256
    push ax                 ; save y
    mov ax, si
    imul word [_tmp_cos]
    ; DX:AX = x*cos (we just use AX, ignore DX for small values)
    push ax
    mov ax, bx
    imul word [_tmp_sin]
    pop cx                  ; cx = x*cos low word
    sub cx, ax              ; cx = x*cos - z*sin (low words)
    sar cx, 8               ; x' = /256
    mov [_pxrot], cx

    ; z' = (x*sin + z*cos) / 256
    mov ax, si
    imul word [_tmp_sin]
    push ax
    mov ax, bx
    imul word [_tmp_cos]
    pop cx
    add cx, ax
    sar cx, 8               ; z' = /256
    add cx, 200             ; add depth offset so z' > 0
    cmp cx, 10
    jge .z_ok
    mov cx, 10
.z_ok:
    pop ax                  ; restore y

    ; Perspective project
    ; screen_x = 160 + x'*128/z'
    ; screen_y = 100 + y*128/z'
    ; x' is in [_pxrot], y in AX, z' in CX
    push ax
    mov ax, [_pxrot]
    imul word [_proj_scale]
    push dx
    cwd
    idiv cx
    add ax, 160             ; center x
    pop dx
    pop dx                  ; y value
    push ax                 ; save screen_x

    mov ax, dx              ; y
    imul word [_proj_scale]
    cwd
    idiv cx
    neg ax                  ; flip Y
    add ax, 100             ; center y
    mov dx, ax              ; screen_y

    pop ax                  ; screen_x
    pop di
    push di
    mov bx, ax
    ; Store projected coords
    shl di, 1
    mov [proj_x + di], bx
    mov [proj_y + di], dx

    pop di
    pop cx
    inc di
    dec cx
    jz .proj_done
    jmp .proj_loop
.proj_done:

    ; Draw edges
    mov si, cube_edges
    mov cx, 12
.edge_loop:
    push cx
    push si
    movzx di, byte [si]
    inc si
    movzx bx, byte [si]
    inc si

    ; Get projected coords of both endpoints
    shl di, 1
    shl bx, 1
    mov ax, [proj_x + di]
    mov [_e_x0], ax
    mov ax, [proj_y + di]
    mov [_e_y0], ax
    mov ax, [proj_x + bx]
    mov [_e_x1], ax
    mov ax, [proj_y + bx]
    mov [_e_y1], ax

    ; Draw line (use gfx_line with params)
    mov [gl_x0], ax
    mov ax, [_e_x0]
    mov [gl_x0], ax
    mov ax, [_e_y0]
    mov [gl_y0], ax
    mov ax, [_e_x1]
    mov [gl_x1], ax
    mov ax, [_e_y1]
    mov [gl_y1], ax
    mov al, 14             ; yellow
    mov [gl_line_col], al
    call gfx_line_mem       ; draw from gl_* vars

    pop si
    pop cx
    loop .edge_loop

    ; Advance angle
    inc word [_cube_angle]
    mov ax, [_cube_angle]
    cmp ax, 360
    jb .frame
    mov word [_cube_angle], 0
    jmp .frame

.exit_cube:
    ; Drain the keypress
    call kbd_getkey
    call gl16_exit

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

_cube_angle:    dw 0
_tmp_cos:       dw 256
_tmp_sin:       dw 0
_pxrot:         dw 0
_proj_scale:    dw 100
_e_x0:          dw 0
_e_y0:          dw 0
_e_x1:          dw 0
_e_y1:          dw 0

str_gl_title:   db "KSDOS OpenGL 16-bit - Rotating Cube [key=exit]", 0

; gfx_line wrapper using gl_* memory variables
gfx_line_mem:
    push ax
    push bx
    push cx
    push dx
    push si
    mov bx, [gl_x0]
    mov cx, [gl_y0]
    mov dx, [gl_x1]
    mov si, [gl_y1]
    mov al, [gl_line_col]
    call gfx_line
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; gl16_triangle_demo: coloured filled triangle demo
; ============================================================
gl16_triangle_demo:
    push ax
    push bx
    push cx
    push dx
    push si

    call gl16_init

    mov word [_tdemo_frame], 0

.tframe:
    call kbd_check
    jnz .texit

    ; Dark background
    mov al, 0
    call gl16_clear

    mov bx, 40
    mov dx, 5
    mov al, 14
    mov si, str_tri_title
    call gl16_text_gfx

    ; Draw 8 rotating triangles of different colors
    mov cx, 8
    mov byte [_tdemo_c], 0
.tri_loop:
    push cx
    ; Calculate angle offset for this triangle
    mov al, [_tdemo_c]
    mov ah, 45
    mul ah
    add ax, [_tdemo_frame]
    mov [_tang], ax

    ; Vertex 0: center
    mov word [tri_x0], 160
    mov word [tri_y0], 100

    ; Vertex 1: angle _tang, radius 80
    mov ax, [_tang]
    call fcos16
    ; AX = cos*256; scale by 80/256 ≈ 80
    imul word [_tdemo_r]
    sar ax, 8
    add ax, 160
    mov [tri_x1], ax

    mov ax, [_tang]
    call fsin16
    imul word [_tdemo_r]
    sar ax, 8
    neg ax
    add ax, 100
    mov [tri_y1], ax

    ; Vertex 2: angle _tang+120
    mov ax, [_tang]
    add ax, 120
    cmp ax, 360
    jb .v2ok
    sub ax, 360
.v2ok:
    call fcos16
    imul word [_tdemo_r]
    sar ax, 8
    add ax, 160
    mov [tri_x2], ax

    mov ax, [_tang]
    add ax, 120
    cmp ax, 360
    jb .v2yok
    sub ax, 360
.v2yok:
    call fsin16
    imul word [_tdemo_r]
    sar ax, 8
    neg ax
    add ax, 100
    mov [tri_y2], ax

    ; Colour: cycle through palette
    movzx ax, byte [_tdemo_c]
    add ax, 16
    add ax, [_tdemo_frame]
    and ax, 0xFF
    mov [tri_col], al

    call gl16_tri

    inc byte [_tdemo_c]
    pop cx
    dec cx
    jz .tri_done
    jmp .tri_loop
.tri_done:

    add word [_tdemo_frame], 2
    cmp word [_tdemo_frame], 360
    jb .tframe
    mov word [_tdemo_frame], 0
    jmp .tframe

.texit:
    call kbd_getkey
    call gl16_exit
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

_tdemo_frame:   dw 0
_tdemo_r:       dw 80
_tdemo_c:       db 0
_tang:          dw 0

str_tri_title:  db "KSDOS OpenGL 16-bit - Triangle Demo [key=exit]", 0
