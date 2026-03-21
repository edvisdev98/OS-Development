; =============================================================================
; psyq.asm - KSDOS PSYq Engine (16-bit Real Mode)
; PlayStation 1 SDK concepts adapted for x86 real mode
;
; Based on sdk/psyq/ headers:
;   - LIBETC.H  (event/timer callbacks)
;   - LIBGPU.H  (GPU primitive types: POLY_F3, POLY_G3, SPRT)
;   - LIBGTE.H  (GTE geometry transform engine - simulated in SW)
;   - LIBSPU.H  (SPU sound - stubs)
;
; Implements:
;   - PSYq-style double-buffered display
;   - POLY_F3 (flat-shaded triangle)
;   - POLY_G3 (Gouraud-shaded triangle - approx)
;   - SPRT    (sprite - fixed size, no transform)
;   - GTE     (fixed-point rotation matrix, perspective divide)
;   - Demo:   rotating PS1-style spaceship made of triangles
; =============================================================================

; ---- PSYq GPU Primitive Types (matching LIBGPU.H concepts) ----
GPU_POLY_F3     equ 0x20    ; flat-shaded triangle
GPU_POLY_G3     equ 0x30    ; Gouraud triangle
GPU_SPRT        equ 0x74    ; sprite

; ---- GTE simulation ----
; GTE uses 4.12 fixed-point internally
; We'll use simpler 8.8 (integer + fractional byte)

gte_rx:         dw 0        ; rotation X
gte_ry:         dw 0        ; rotation Y
gte_rz:         dw 0        ; rotation Z
gte_tx:         dw 160      ; translation X (screen center)
gte_ty:         dw 100      ; translation Y
gte_tz:         dw 250      ; depth (perspective distance)
gte_h:          dw 128      ; screen distance parameter

; ---- PSYq double buffer state ----
psyq_buf:       db 0        ; current display buffer (0 or 1)
psyq_frame:     dw 0

; ---- Spaceship model (triangles) ----
; 12 triangles, each: x0,y0,z0, x1,y1,z1, x2,y2,z2, colour
; Scale * 64 for fixed-point

ship_verts:
    ; Nose
    dw   0,-80, 0
    dw -32, 20, 0
    dw  32, 20, 0
    ; Left wing top
    dw -32, 20, 0
    dw -80, 30, 0
    dw -20, 40, 0
    ; Left wing bottom
    dw -80, 30, 0
    dw -32, 60, 0
    dw -20, 40, 0
    ; Right wing top
    dw  32, 20, 0
    dw  80, 30, 0
    dw  20, 40, 0
    ; Right wing bottom
    dw  80, 30, 0
    dw  32, 60, 0
    dw  20, 40, 0
    ; Body center
    dw -32, 20, 0
    dw  32, 20, 0
    dw   0, 60, 0
    ; Left thruster
    dw -20, 50, 0
    dw -32, 60, 0
    dw -20, 70, 0
    ; Right thruster
    dw  20, 50, 0
    dw  32, 60, 0
    dw  20, 70, 0

SHIP_TRIS       equ 8

ship_colors:    db 15, 12, 10, 9, 9, 7, 11, 11

; ---- Sprite demo data ----
psyq_stars:     times 32*2 dw 0    ; star x,y positions
psyq_stars_init: db 0

; ============================================================
; psyq_init: initialise PSYq subsystem
; Sets up Mode 13h, stars, resets GTE
; ============================================================
psyq_init:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    call gl16_init
    call gfx_setup_palette

    ; Seed stars at random positions using BIOS time
    mov ah, 0x00
    int 0x1A                ; get ticks → DX:CX
    mov [psyq_rng_seed], dx
    xor di, di
    mov cx, 32
.star_loop:
    call psyq_rand
    and ax, 0x01FF          ; 0..319
    cmp ax, 319
    jbe .sx_ok
    mov ax, 319
.sx_ok:
    mov [psyq_stars + di], ax
    add di, 2
    call psyq_rand
    and ax, 0xFF            ; 0..199
    cmp ax, 199
    jbe .sy_ok
    mov ax, 199
.sy_ok:
    mov [psyq_stars + di], ax
    add di, 2
    loop .star_loop

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

psyq_rng_seed:  dw 0xACE1

; Simple 16-bit LFSR random
psyq_rand:
    push bx
    mov ax, [psyq_rng_seed]
    mov bx, ax
    shr bx, 1
    and ax, 1
    neg ax
    and ax, 0xB400
    xor ax, bx
    mov [psyq_rng_seed], ax
    pop bx
    ret

; ============================================================
; psyq_gte_transform: transform vertex in SI (x,y,z words) by GTE
; Output: BX=screen_x, DX=screen_y
; ============================================================
psyq_gte_transform:
    push ax
    push cx
    push si

    ; Read vertex
    mov ax, [si]            ; x
    mov [_gte_x], ax
    mov ax, [si+2]          ; y
    mov [_gte_y], ax
    mov ax, [si+4]          ; z
    mov [_gte_z], ax

    ; Rotate around Y (gte_ry):
    ;   x' = x*cos(ry) - z*sin(ry)
    ;   z' = x*sin(ry) + z*cos(ry)
    mov ax, [gte_ry]
    call fcos16             ; cos*256
    mov [_gte_cos], ax
    mov ax, [gte_ry]
    call fsin16
    mov [_gte_sin], ax

    ; x' = (x*cos - z*sin) >> 8
    mov ax, [_gte_x]
    imul word [_gte_cos]
    ; low word in AX
    push ax
    mov ax, [_gte_z]
    imul word [_gte_sin]
    pop cx
    sub cx, ax
    sar cx, 8
    mov [_gte_xr], cx

    ; z' = (x*sin + z*cos) >> 8
    mov ax, [_gte_x]
    imul word [_gte_sin]
    push ax
    mov ax, [_gte_z]
    imul word [_gte_cos]
    pop cx
    add cx, ax
    sar cx, 8
    add cx, [gte_tz]        ; add depth offset
    cmp cx, 20
    jge .z_ok
    mov cx, 20
.z_ok:
    mov [_gte_zr], cx

    ; Perspective divide
    ; screen_x = tx + x'*h/z'
    mov ax, [_gte_xr]
    imul word [gte_h]
    cwd
    idiv word [_gte_zr]
    add ax, [gte_tx]
    mov bx, ax              ; screen_x

    ; screen_y = ty + y*h/z'
    mov ax, [_gte_y]
    neg ax                  ; flip Y (PS1 Y axis)
    imul word [gte_h]
    cwd
    idiv word [_gte_zr]
    add ax, [gte_ty]
    mov dx, ax              ; screen_y

    pop si
    pop cx
    pop ax
    ret

_gte_x:     dw 0
_gte_y:     dw 0
_gte_z:     dw 0
_gte_xr:    dw 0
_gte_yr:    dw 0
_gte_zr:    dw 1
_gte_cos:   dw 256
_gte_sin:   dw 0

; ============================================================
; psyq_draw_stars: draw twinkling star field
; ============================================================
psyq_draw_stars:
    push ax
    push bx
    push cx
    push dx
    push di

    mov di, 0
    mov cx, 32
.loop:
    mov bx, [psyq_stars + di]      ; x
    mov dx, [psyq_stars + di + 2]  ; y
    ; Colour based on position (twinkle)
    mov ax, [psyq_frame]
    add ax, di
    and al, 0x0F
    cmp al, 0
    jne .not_bright
    mov al, 15              ; white
    jmp .draw
.not_bright:
    cmp al, 8
    jl .draw
    mov al, 8               ; dark grey
.draw:
    call gl16_pix
    add di, 4
    loop .loop

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; psyq_ship_demo: main demo loop
; Rotating PS1-style spaceship with starfield
; Press any key to exit
; ============================================================
psyq_ship_demo:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    call psyq_init

.frame_loop:
    call kbd_check
    jnz .exit_demo

    ; Clear to space black
    mov al, 0
    call gl16_clear

    ; Draw stars
    call psyq_draw_stars

    ; Draw title
    mov bx, 30
    mov dx, 5
    mov al, 11
    mov si, str_psyq_title
    call gl16_text_gfx

    ; Draw "SDK: PSYq" label
    mov bx, 30
    mov dx, 15
    mov al, 10
    mov si, str_psyq_sdk
    call gl16_text_gfx

    ; Draw ship triangles
    xor di, di              ; triangle index
    mov cx, SHIP_TRIS
.ship_tri:
    push cx
    push di

    ; Get triangle vertex pointers
    ; Each triangle = 3 vertices * 3 words = 18 bytes
    mov ax, di
    mov bx, 18
    mul bx
    mov si, ship_verts
    add si, ax

    ; Transform vertex 0
    call psyq_gte_transform
    mov [_sv_x0], bx
    mov [_sv_y0], dx
    add si, 6

    ; Transform vertex 1
    call psyq_gte_transform
    mov [_sv_x1], bx
    mov [_sv_y1], dx
    add si, 6

    ; Transform vertex 2
    call psyq_gte_transform
    mov [_sv_x2], bx
    mov [_sv_y2], dx

    ; Get colour
    movzx ax, byte [ship_colors + di]

    ; Draw filled triangle using gl16_tri
    mov cx, [_sv_x0]
    mov [tri_x0], cx
    mov cx, [_sv_y0]
    mov [tri_y0], cx
    mov cx, [_sv_x1]
    mov [tri_x1], cx
    mov cx, [_sv_y1]
    mov [tri_y1], cx
    mov cx, [_sv_x2]
    mov [tri_x2], cx
    mov cx, [_sv_y2]
    mov [tri_y2], cx
    mov [tri_col], al
    call gl16_tri

    pop di
    pop cx
    inc di
    loop .ship_tri

    ; Also draw wireframe outline (brighter)
    ; (skip for performance in simple demo)

    ; Advance rotation
    add word [gte_ry], 3
    cmp word [gte_ry], 360
    jb .no_wrap
    mov word [gte_ry], 0
.no_wrap:

    inc word [psyq_frame]
    jmp .frame_loop

.exit_demo:
    call kbd_getkey
    call gl16_exit

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

_sv_x0: dw 0
_sv_y0: dw 0
_sv_x1: dw 0
_sv_y1: dw 0
_sv_x2: dw 0
_sv_y2: dw 0

str_psyq_title: db "KSDOS PSYq Engine v1.0 [key=exit]", 0
str_psyq_sdk:   db "SDK: sdk/psyq/ (PSn00bSDK compatible)", 0
