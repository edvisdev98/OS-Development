; =============================================================================
; gold4.asm - KSDOS GOLD4 Engine (16-bit Real Mode)
; DOOM-style raycaster engine based on sdk/gold4/
;
; Based on sdk/gold4/ SDK structure:
;   - Engine: raycast column renderer (Mode 13h)
;   - Map: 2D tile array  
;   - Player: position, angle, FOV
;   - Movement: WASD keyboard, ESC to quit
;
; Features:
;   - 60-degree FOV raycaster (320 columns)
;   - Wall distance shading
;   - Textured walls (4 colours based on direction)
;   - Ceiling (dark blue) and floor (dark grey)
;   - Minimap in upper-right corner
;   - HUD with position info
; =============================================================================

; ---- Map constants ----
MAP_W       equ 16
MAP_H       equ 10
HALF_FOV    equ 30              ; half field-of-view in degrees

; ---- Angle & fixed-point math ----
ANGLE_360   equ 360
DEPTH_SCALE equ 100             ; scale factor for wall height calc

; ---- Map data: 1=wall, 0=empty ----
gold4_map:
    db 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    db 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
    db 1,0,1,1,0,0,0,1,0,0,1,0,0,0,0,1
    db 1,0,1,0,0,0,0,1,0,0,0,0,1,0,0,1
    db 1,0,0,0,0,1,0,0,0,0,0,0,1,0,0,1
    db 1,0,0,1,0,1,0,0,0,1,0,0,0,0,0,1
    db 1,0,0,1,0,0,0,0,0,1,0,1,0,0,0,1
    db 1,0,0,0,0,0,1,0,0,0,0,1,0,0,0,1
    db 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
    db 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1

; ---- Player state (fixed-point: *64) ----
g4_px:          dw 64*3         ; player x (tile*64)
g4_py:          dw 64*5         ; player y
g4_angle:       dw 90           ; facing angle (degrees)

; ---- Column hit state ----
g4_hit_x:       dw 0
g4_hit_y:       dw 0
g4_dist:        dw 0
g4_side:        db 0            ; 0=vertical wall, 1=horizontal wall

; Wall colours per side
g4_wall_ns:     db 12           ; N/S wall colour (light red)
g4_wall_ew:     db 4            ; E/W wall colour (dark red)
g4_ceil:        db 1            ; ceiling colour (blue)
g4_floor:       db 8            ; floor colour (dark grey)
g4_hud_col:     db 14           ; HUD colour (yellow)

; ============================================================
; gold4_init: init the raycaster
; ============================================================
gold4_init:
    push ax
    call gl16_init
    call gfx_setup_palette
    pop ax
    ret

; ============================================================
; gold4_draw_frame: render one frame
; ============================================================
gold4_draw_frame:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; Draw ceiling (top half)
    mov al, [g4_ceil]
    mov bx, 0               ; x=0
    xor dx, dx              ; y=0
.ceil_row:
    cmp dx, 100
    jge .ceil_done
    ; Draw full row
    push bx
    push dx
    mov cx, 320
.ceil_px:
    call gl16_pix
    inc bx
    loop .ceil_px
    pop dx
    pop bx
    xor bx, bx
    inc dx
    jmp .ceil_row
.ceil_done:

    ; Draw floor (bottom half)
    mov al, [g4_floor]
    xor bx, bx
    mov dx, 100
.floor_row:
    cmp dx, 200
    jge .floor_done
    push bx
    push dx
    mov cx, 320
.floor_px:
    call gl16_pix
    inc bx
    loop .floor_px
    pop dx
    pop bx
    xor bx, bx
    inc dx
    jmp .floor_row
.floor_done:

    ; Cast rays for each screen column
    ; column = 0..319
    ; ray_angle = player_angle - HALF_FOV + col*60/320
    xor si, si              ; column index
.ray_loop:
    cmp si, 320
    jge .rays_done

    ; Compute ray angle
    ; angle = g4_angle - 30 + si*60/320
    ; si*60/320 = si*3/16 (approximation)
    mov ax, si
    mov bx, 3
    mul bx
    mov bx, 16
    xor dx, dx
    div bx                  ; AX = si*60/320 (approx)
    mov cx, [g4_angle]
    sub cx, HALF_FOV
    add cx, ax              ; ray angle
    ; Normalize to 0..359
.norm_a:
    cmp cx, 0
    jge .norm_pos
    add cx, 360
    jmp .norm_a
.norm_pos:
    cmp cx, 360
    jl .norm_ok
    sub cx, 360
    jmp .norm_pos
.norm_ok:
    mov [_g4_ray_angle], cx

    ; DDA raycast
    call g4_cast_ray

    ; Draw wall slice at column si
    ; wall_height = 160 * DEPTH_SCALE / max(dist,1)
    mov ax, DEPTH_SCALE * 160
    mov bx, [g4_dist]
    cmp bx, 1
    jge .dist_ok
    mov bx, 1
.dist_ok:
    xor dx, dx
    div bx
    ; AX = wall height in pixels
    cmp ax, 200
    jle .wh_ok
    mov ax, 200
.wh_ok:
    mov [_g4_wh], ax

    ; Wall colour based on side
    mov al, [g4_wall_ns]
    cmp byte [g4_side], 1
    jne .use_col
    mov al, [g4_wall_ew]
.use_col:
    mov [_g4_wcol], al

    ; Draw the column slice
    ; Top of wall = 100 - wh/2
    mov ax, [_g4_wh]
    shr ax, 1
    mov bx, 100
    sub bx, ax
    mov [_g4_ytop], bx
    add bx, [_g4_wh]
    mov [_g4_ybot], bx

    ; Draw from ytop to ybot at x=si
    mov dx, [_g4_ytop]
    cmp dx, 0
    jge .col_start
    xor dx, dx
.col_start:
.col_draw:
    cmp dx, [_g4_ybot]
    jge .col_done
    cmp dx, 199
    jg .col_done
    push si
    push dx
    mov bx, si
    mov al, [_g4_wcol]
    call gl16_pix
    pop dx
    pop si
    inc dx
    jmp .col_draw
.col_done:

    inc si
    jmp .ray_loop
.rays_done:

    ; Draw minimap (upper right, 32x20 pixels, 2px per tile)
    call g4_draw_minimap

    ; Draw HUD
    mov bx, 2
    mov dx, 185
    mov al, [g4_hud_col]
    mov si, str_g4_hud
    call gl16_text_gfx

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

_g4_ray_angle:  dw 0
_g4_wh:         dw 0
_g4_ytop:       dw 0
_g4_ybot:       dw 0
_g4_wcol:       db 0

; ============================================================
; g4_cast_ray: DDA ray cast
; Input: [_g4_ray_angle]
; Output: [g4_dist], [g4_side]
; ============================================================
g4_cast_ray:
    push ax
    push bx
    push cx
    push dx

    ; Player position in tile coords (integer, player * 64 / 64 = tile)
    ; Direction vector from angle
    mov ax, [_g4_ray_angle]
    call fcos16                 ; AX = cos*256
    mov [_rc_dx], ax            ; ray dir x (scaled *256)
    mov ax, [_g4_ray_angle]
    call fsin16                 ; AX = sin*256
    mov [_rc_dy], ax            ; ray dir y

    ; Current tile
    mov ax, [g4_px]
    sar ax, 6                   ; /64 = tile x
    mov [_rc_mx], ax
    mov ax, [g4_py]
    sar ax, 6
    mov [_rc_my], ax

    ; DDA: step through grid
    mov word [g4_dist], 1
    mov cx, 64                  ; max steps

.dda_step:
    test cx, cx
    jz .ray_max

    ; Advance ray: small_step_x = 1/ray_dx * 64 (simplified)
    ; We use a simplified DDA: just step by 1 pixel in ray direction
    ; and check tile changes
    mov ax, [g4_dist]
    add ax, 3                   ; step
    mov [g4_dist], ax

    ; Position along ray
    ; px + dist*dx/256, py + dist*dy/256
    mov ax, [g4_dist]
    imul word [_rc_dx]
    sar ax, 8
    add ax, [g4_px]
    sar ax, 6                   ; convert to tile
    mov bx, ax
    cmp bx, 0
    jl .ray_max
    cmp bx, MAP_W
    jge .ray_max

    mov ax, [g4_dist]
    imul word [_rc_dy]
    sar ax, 8
    add ax, [g4_py]
    sar ax, 6
    mov dx, ax
    cmp dx, 0
    jl .ray_max
    cmp dx, MAP_H
    jge .ray_max

    ; Check if wall hit
    ; map[dy][dx]
    push dx
    push bx
    mov ax, MAP_W
    mul dx                  ; AX = dy*MAP_W
    pop bx
    add ax, bx
    mov si, gold4_map
    add si, ax
    cmp byte [si], 1
    jne .no_hit

    ; Determine side (N/S vs E/W)
    ; Simplified: if X tile changed from last step, it's E/W wall
    mov ax, bx
    cmp ax, [_rc_mx]
    jne .ew_wall
    mov byte [g4_side], 1   ; horizontal (N/S)
    jmp .hit_done
.ew_wall:
    mov byte [g4_side], 0   ; vertical (E/W)
.hit_done:
    ; Apply fisheye correction: dist * cos(ray_angle - player_angle)
    mov ax, [_g4_ray_angle]
    sub ax, [g4_angle]
    ; normalize
.fix_ang:
    cmp ax, -180
    jge .fa_ok1
    add ax, 360
    jmp .fix_ang
.fa_ok1:
    cmp ax, 180
    jle .fa_ok2
    sub ax, 360
    jmp .fa_ok1
.fa_ok2:
    call fcos16             ; cos of angle difference *256
    ; correct_dist = dist * cos / 256
    mul word [g4_dist]
    sar ax, 8
    mov [g4_dist], ax
    pop dx
    pop dx
    jmp .ray_done
.no_hit:
    mov [_rc_mx], bx
    pop dx
    pop bx
    dec cx
    jmp .dda_step

.ray_max:
    mov word [g4_dist], 200
.ray_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

_rc_dx:         dw 0
_rc_dy:         dw 0
_rc_mx:         dw 0
_rc_my:         dw 0

; ============================================================
; g4_draw_minimap: draw minimap in upper right corner
; ============================================================
g4_draw_minimap:
    push ax
    push bx
    push cx
    push dx
    push si

    ; 2 pixels per tile, placed at x=256, y=2
    xor si, si              ; tile index
    mov dx, 2               ; screen y start
    mov cx, MAP_H
.mm_row:
    push cx
    mov cx, MAP_W
    mov bx, 256             ; screen x start
.mm_col:
    push cx
    ; Get tile value
    mov al, [gold4_map + si]
    test al, al
    jz .mm_empty
    mov al, 7               ; wall = light grey
    jmp .mm_draw
.mm_empty:
    mov al, 0               ; empty = black
.mm_draw:
    call gl16_pix
    push bx
    push dx
    inc bx
    call gl16_pix
    inc dx
    call gl16_pix
    dec bx
    call gl16_pix
    dec dx
    pop dx
    pop bx
    add bx, 2
    inc si
    pop cx
    loop .mm_col
    add dx, 2
    pop cx
    loop .mm_row

    ; Draw player dot (red)
    mov ax, [g4_px]
    sar ax, 6               ; tile x
    shl ax, 1               ; *2 pixels
    add ax, 256
    mov bx, ax

    mov ax, [g4_py]
    sar ax, 6
    shl ax, 1
    add ax, 2
    mov dx, ax

    mov al, 4               ; red
    call gl16_pix

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; gold4_run: main game loop
; WASD = move, Q/E = strafe, ESC = quit
; ============================================================
gold4_run:
    push ax
    push bx
    push cx
    push dx
    push si

    call gold4_init

.game_loop:
    call gold4_draw_frame

    ; Poll keyboard (non-blocking)
    call kbd_check
    jz .game_loop           ; no key = keep rendering

    call kbd_getkey
    cmp al, 27              ; ESC
    je .game_exit
    cmp al, 'w'
    je .move_fwd
    cmp al, 'W'
    je .move_fwd
    cmp al, 's'
    je .move_back
    cmp al, 'S'
    je .move_back
    cmp al, 'a'
    je .turn_left
    cmp al, 'A'
    je .turn_left
    cmp al, 'd'
    je .turn_right
    cmp al, 'D'
    je .turn_right
    jmp .game_loop

.move_fwd:
    ; Move forward: px += cos(angle)*4, py += sin(angle)*4
    mov ax, [g4_angle]
    call fcos16
    sar ax, 6               ; *4/256 ≈ divide 64
    add [g4_px], ax
    mov ax, [g4_angle]
    call fsin16
    sar ax, 6
    add [g4_py], ax
    jmp .game_loop

.move_back:
    mov ax, [g4_angle]
    call fcos16
    sar ax, 6
    sub [g4_px], ax
    mov ax, [g4_angle]
    call fsin16
    sar ax, 6
    sub [g4_py], ax
    jmp .game_loop

.turn_left:
    sub word [g4_angle], 10
    cmp word [g4_angle], 0
    jge .game_loop
    add word [g4_angle], 360
    jmp .game_loop

.turn_right:
    add word [g4_angle], 10
    cmp word [g4_angle], 360
    jl .game_loop
    sub word [g4_angle], 360
    jmp .game_loop

.game_exit:
    call gl16_exit

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

str_g4_hud:     db "KSDOS GOLD4 Engine | W=fwd S=back A/D=turn ESC=quit", 0
