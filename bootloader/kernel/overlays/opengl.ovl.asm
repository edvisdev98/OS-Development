; =============================================================================
; OPENGL.OVL - 16-bit software OpenGL renderer overlay
; =============================================================================
BITS 16
ORG OVERLAY_BUF

%include "ovl_api.asm"

ovl_entry:
    mov si, .str_menu
    call vid_println
    call kbd_getkey
    cmp al, '1'
    je .cube
    cmp al, '2'
    je .tri
    ret
.cube:
    call gl16_cube_demo
    ret
.tri:
    call gl16_triangle_demo
    ret

.str_menu: db "OpenGL Demos: 1=Cube  2=Triangles  (press key)", 0

%include "../opengl.asm"
